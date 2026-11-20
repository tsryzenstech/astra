// SPDX-License-Identifier: Apache-2.0
#include "activitymanager.h"
#include "packagemanager.h"
#include "permissions.h"
#include "settingsservice.h"

#include <astra/global.h>
#include <astra/paths.h>
#include <astra/protocol.h>

#include <QDateTime>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLoggingCategory>
#include <QMimeDatabase>
#include <QProcess>
#include <QTimer>

#include <grp.h>
#include <pwd.h>
#include <unistd.h>

Q_LOGGING_CATEGORY(lcAm, "astrad.activity")

namespace astrad {

using namespace astra;

ActivityManager::ActivityManager(Server *server, PackageManager *packages, SettingsService *settings, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_packages(packages)
    , m_settings(settings)
{
    connect(packages, &PackageManager::packageRemoved, this, &ActivityManager::stop);
    connect(packages, &PackageManager::dataCleared, this, &ActivityManager::stop);
    // A process keeps the groups it started with: new access is added with
    // ACLs so the app keeps running; only a revoked one restarts it.
    connect(packages, &PackageManager::permissionsChanged, this, [this](const QString &pkg, bool groupsChanged) {
        if (!groupsChanged || !m_running.contains(pkg))
            return;
        const QList<gid_t> now = m_packages->groupsOf(pkg);
        Running &r = m_running[pkg];
        bool revoked = false;
        for (gid_t g : std::as_const(r.groups))
            if (!now.contains(g))
                revoked = true;
        if (revoked) {
            restart(pkg);
            return;
        }
        for (gid_t g : now)
            if (!r.groups.contains(g)) {
                grantAccess(pkg, g);
                r.groups.append(g);
            }
    });
}

QString ActivityManager::packageForPid(pid_t pid) const
{
    for (auto it = m_running.cbegin(); it != m_running.cend(); ++it)
        if (it.value().process->processId() == pid)
            return it.key();
    return {};
}

void ActivityManager::stop(const QString &package)
{
    if (m_running.contains(package))
        m_running[package].process->terminate();
}

void ActivityManager::restart(const QString &package)
{
    if (!m_running.contains(package))
        return;
    Running &r = m_running[package];
    r.restarting = true;
    m_server->broadcast(QStringLiteral("activity.restarting"), QJsonObject{{QStringLiteral("package"), package}});
    r.process->terminate();
}

// Whether an app may hand these launch arguments to another app: an "open"
// or "share" of files (or a URL / text) of a type the target declares in
// its app.json ("opens" / "share"), as ShareSheet does.
static bool declaresIntent(const QJsonObject &target, const QJsonObject &args)
{
    QString action = args.value(QLatin1String("action")).toString();
    // A bare { url } (a link opened in Planet) is an "open" too.
    if (action.isEmpty() && (args.contains(QLatin1String("url")) || args.contains(QLatin1String("files"))))
        action = QStringLiteral("open");
    if (action != QLatin1String("open") && action != QLatin1String("share"))
        return false;
    const QJsonArray accepted = target.value(action == QLatin1String("open") ? QLatin1String("opens") : QLatin1String("share")).toArray();
    if (accepted.isEmpty())
        return false;
    static QMimeDatabase db;
    auto matches = [&accepted](const QMimeType &type, const QString &name) {
        QStringList names{name};
        if (type.isValid()) {
            names << type.name() << type.aliases();
            for (const QString &parent : type.allAncestors())
                if (parent != QLatin1String("application/octet-stream"))
                    names << parent << db.mimeTypeForName(parent).aliases();
        }
        for (const QJsonValue &v : accepted) {
            const QString pattern = v.toString();
            if (pattern == QLatin1String("*/*"))
                return true;
            for (const QString &n : std::as_const(names))
                if (pattern == n || (pattern.endsWith(QLatin1String("/*")) && n.startsWith(pattern.chopped(1))))
                    return true;
        }
        return false;
    };
    const QJsonArray files = args.value(QLatin1String("files")).toArray();
    for (const QJsonValue &f : files) {
        const QString path = f.toString();
        const QMimeType type = path.endsWith(QLatin1String(".apkg"), Qt::CaseInsensitive)
                                   ? db.mimeTypeForName(QStringLiteral("application/x-astra-apkg"))
                                   : db.mimeTypeForFile(path);
        if (!matches(type, type.isValid() ? type.name() : QStringLiteral("application/x-astra-apkg")))
            return false;
    }
    if (!files.isEmpty())
        return true;
    if (args.contains(QLatin1String("url")))
        return matches(db.mimeTypeForName(QStringLiteral("text/uri-list")), QStringLiteral("text/uri-list"));
    if (args.contains(QLatin1String("text")))
        return matches(db.mimeTypeForName(QStringLiteral("text/plain")), QStringLiteral("text/plain"));
    return false;
}

void ActivityManager::grantAccess(const QString &package, gid_t gid)
{
    if (Paths::isDevelopmentRoot())
        return; // development trees run every app as the developer
    const uid_t uid = m_packages->uidOf(package);
    QStringList paths;
    bool tree = false;
    if (gid == 1023) {                       // media_rw: the shared storage
        paths << Paths::resolve(QStringLiteral("/data/media"));
        tree = true;
    } else if (gid == 1006) {                // camera: video devices
        const QDir dev(QStringLiteral("/dev"));
        for (const QString &n : dev.entryList({QStringLiteral("video*"), QStringLiteral("media*"), QStringLiteral("v4l-subdev*")}, QDir::System))
            paths << dev.filePath(n);
    } else {
        return;                              // reached through astrad: nothing to open
    }
    const QString entry = QStringLiteral("u:%1:rwX").arg(uid);
    for (const QString &path : std::as_const(paths)) {
        if (tree) {
            // Existing files, then the default for files created later.
            QProcess::execute(QStringLiteral("setfacl"), {QStringLiteral("-R"), QStringLiteral("-m"), entry, path});
            QProcess::execute(QStringLiteral("setfacl"), {QStringLiteral("-R"), QStringLiteral("-d"), QStringLiteral("-m"), entry, path});
        } else {
            QProcess::execute(QStringLiteral("setfacl"), {QStringLiteral("-m"), entry, path});
        }
    }
    qCInfo(lcAm) << package << "can now use group" << gid << "without restarting";
}

void ActivityManager::startFromSystem(const QString &package, const QJsonObject &args)
{
    if (m_waylandDisplay.isEmpty() || !m_packages->contains(package))
        return;
    try {
        start(package, args);
    } catch (const RpcError &e) {
        qCWarning(lcAm) << "cannot start" << package << e.message;
    }
}

void ActivityManager::start(const QString &package, const QJsonObject &args)
{
    if (m_running.contains(package)) {
        m_running[package].args = args;
        m_server->sendToPackage(package, QStringLiteral("activity.intent"), args);
        m_server->broadcast(QStringLiteral("activity.resumed"), QJsonObject{{QStringLiteral("package"), package}});
        return;
    }
    const QJsonObject info = m_packages->info(package);
    const QString android = info.value(QLatin1String("android")).toString();
    if (!android.isEmpty()) {
        // Its window comes from the Android session (app_id "waydroid.<package>").
        if (m_android)
            m_android(android);
        return;
    }
    const QJsonObject legacy = info.value(QLatin1String("legacy")).toObject();
    if (!legacy.value(QLatin1String("exec")).toString().isEmpty()) {
        startLegacy(package, legacy);
        return;
    }
    const uid_t uid = uid_t(info.value(QLatin1String("uid")).toInt());
    const bool asRoot = geteuid() == 0;

    QProcessEnvironment env;
    const QString runtimeDir = Paths::resolve(QStringLiteral("/run/user/%1").arg(uid));
    QDir().mkpath(runtimeDir);
    if (asRoot) {
        const QByteArray rd = QFile::encodeName(runtimeDir);
        if (chown(rd.constData(), uid, uid) != 0)
            qCWarning(lcAm) << "cannot chown" << runtimeDir;
        QFile::setPermissions(runtimeDir, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    }
    const QString home = info.value(QLatin1String("dataDir")).toString();
    const QString language = m_settings->value(QStringLiteral("system.language")).toString(QStringLiteral("en"));
    env.insert(QStringLiteral("PATH"), QStringLiteral("/system/bin"));
    env.insert(QStringLiteral("HOME"), home);
    env.insert(QStringLiteral("TMPDIR"), home + QStringLiteral("/cache"));
    env.insert(QStringLiteral("XDG_CONFIG_HOME"), home + QStringLiteral("/files/.config"));
    env.insert(QStringLiteral("XDG_CACHE_HOME"), home + QStringLiteral("/cache"));
    env.insert(QStringLiteral("XDG_DATA_HOME"), home + QStringLiteral("/files"));
    env.insert(QStringLiteral("XDG_RUNTIME_DIR"), runtimeDir);
    env.insert(QStringLiteral("WAYLAND_DISPLAY"), m_waylandDisplay);
    env.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("wayland"));
    env.insert(QStringLiteral("QT_WAYLAND_DISABLE_WINDOWDECORATION"), QStringLiteral("1"));
    env.insert(QStringLiteral("QT_QUICK_CONTROLS_STYLE"), QStringLiteral("Basic"));
    env.insert(QStringLiteral("LANG"), language + QStringLiteral(".UTF-8"));
    env.insert(QStringLiteral("ASTRA_LANGUAGE"), language);
    env.insert(QStringLiteral("ASTRA_PACKAGE"), package);
    env.insert(QStringLiteral("ASTRA_LAUNCH_ARGS"), QString::fromUtf8(QJsonDocument(args).toJson(QJsonDocument::Compact)));
    const QString tz = m_settings->value(QStringLiteral("system.timezone")).toString();
    if (!tz.isEmpty())
        env.insert(QStringLiteral("TZ"), tz);
    if (!m_scaleFactor.isEmpty())
        env.insert(QStringLiteral("QT_SCALE_FACTOR"), m_scaleFactor);
    if (!Paths::isDevelopmentRoot())
        env.insert(QStringLiteral("PULSE_SERVER"), QStringLiteral("unix:/run/astra/audio/pulse/native"));
    const double animationScale = m_settings->value(QStringLiteral("developer.animation_scale")).toDouble(1.0);
    const bool reduceMotion = m_settings->value(QStringLiteral("accessibility.reduce_motion")).toBool() || m_batterySaving;
    env.insert(QStringLiteral("ASTRA_ANIMATION_SCALE"), QString::number(reduceMotion ? 0.0 : animationScale));
    // Development trees keep their own library and QML locations.
    for (const char *passthrough : {"ASTRA_ROOT", "LD_LIBRARY_PATH", "QT_PLUGIN_PATH", "QML_IMPORT_PATH",
                                    "QT_LOGGING_RULES", "PULSE_SERVER", "QT_QUICK_BACKEND", "LIBGL_ALWAYS_SOFTWARE",
                                    "QTWEBENGINEPROCESS_PATH", "QTWEBENGINE_RESOURCES_PATH", "QTWEBENGINE_LOCALES_PATH"}) {
        const QString key = QString::fromLatin1(passthrough);
        if (qEnvironmentVariableIsSet(passthrough))
            env.insert(key, qEnvironmentVariable(passthrough));
    }

    auto *process = new QProcess(this);
    process->setProgram(Paths::resolve(QStringLiteral("/system/bin/astra-app")));
    process->setArguments({QStringLiteral("--package"), package});
    process->setProcessEnvironment(env);
    process->setWorkingDirectory(home);
    process->setProcessChannelMode(QProcess::ForwardedChannels);
    if (asRoot) {
        const QList<gid_t> groups = m_packages->groupsOf(package);
        process->setChildProcessModifier([uid, groups] {
            if (setgroups(size_t(groups.size()), groups.constData()) != 0 || setgid(uid) != 0 || setuid(uid) != 0)
                _exit(126);
        });
    }

    connect(process, &QProcess::finished, this, [this, package, process](int code, QProcess::ExitStatus status) {
        qCInfo(lcAm) << package << "exited" << code << (status == QProcess::CrashExit ? "(crashed)" : "");
        const Running r = m_running.take(package);
        process->deleteLater();
        if (r.restarting) {
            QTimer::singleShot(150, this, [this, package, args = r.args] { startFromSystem(package, args); });
            return;
        }
        m_server->broadcast(QStringLiteral("activity.exited"), QJsonObject{{QStringLiteral("package"), package}});
    });
    m_running.insert(package, Running{process, args, QDateTime::currentMSecsSinceEpoch(), false, m_packages->groupsOf(package)});
    process->start();
    if (!process->waitForStarted(3000)) {
        qCWarning(lcAm) << "cannot start" << package << process->errorString();
        m_running.remove(package);
        process->deleteLater();
        throw RpcError{protocol::Failed, process->errorString()};
    }
    qCInfo(lcAm) << "started" << package << "pid" << process->processId() << "uid" << uid;
    m_server->broadcast(QStringLiteral("activity.started"),
                        QJsonObject{{QStringLiteral("package"), package}, {QStringLiteral("pid"), qint64(process->processId())}});
}

// A Linux program of the system (docs/DESKTOP.md): started as the user the listing names, drawing on SysBoard's Wayland
// socket (an absolute WAYLAND_DISPLAY: it has its own runtime directory). Its window is matched to the package by its app_id.
void ActivityManager::startLegacy(const QString &package, const QJsonObject &legacy)
{
    const QString user = legacy.value(QLatin1String("user")).toString();
    const struct passwd *pw = user.isEmpty() ? nullptr : getpwnam(user.toLocal8Bit().constData());
    // A listed program never runs as root by accident: a user that does not exist is an error.
    if (!user.isEmpty() && !pw)
        throw RpcError{protocol::Failed, QStringLiteral("the user %1 of %2 does not exist").arg(user, package)};
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    const uid_t uid = pw ? pw->pw_uid : geteuid();
    const QString runtimeDir = Paths::resolve(QStringLiteral("/run/user/%1").arg(uid));
    QDir().mkpath(runtimeDir);
    if (pw && geteuid() == 0) {
        if (chown(QFile::encodeName(runtimeDir).constData(), uid, pw->pw_gid) != 0)
            qCWarning(lcAm) << "cannot chown" << runtimeDir;
        QFile::setPermissions(runtimeDir, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    }
    env.insert(QStringLiteral("XDG_RUNTIME_DIR"), runtimeDir);
    env.insert(QStringLiteral("WAYLAND_DISPLAY"), Paths::displayDir() + QLatin1Char('/') + m_waylandDisplay);
    env.insert(QStringLiteral("XDG_SESSION_TYPE"), QStringLiteral("wayland"));
    env.insert(QStringLiteral("MOZ_ENABLE_WAYLAND"), QStringLiteral("1"));
    env.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("wayland"));
    env.insert(QStringLiteral("GDK_BACKEND"), QStringLiteral("wayland"));
    env.insert(QStringLiteral("LANG"), m_settings->value(QStringLiteral("system.language")).toString(QStringLiteral("en")) + QStringLiteral(".UTF-8"));
    if (pw) {
        env.insert(QStringLiteral("HOME"), QString::fromLocal8Bit(pw->pw_dir));
        env.insert(QStringLiteral("USER"), user);
    }
    auto *process = new QProcess(this);
    process->setProgram(legacy.value(QLatin1String("exec")).toString());
    QStringList args;
    for (const QJsonValue &a : legacy.value(QLatin1String("args")).toArray())
        args << a.toString();
    process->setArguments(args);
    process->setProcessEnvironment(env);
    process->setProcessChannelMode(QProcess::ForwardedChannels);
    if (pw && geteuid() == 0) {
        const uid_t u = pw->pw_uid;
        const gid_t g = pw->pw_gid;
        const QByteArray name = user.toLocal8Bit();
        process->setChildProcessModifier([u, g, name] {
            if (initgroups(name.constData(), g) != 0 || setgid(g) != 0 || setuid(u) != 0)
                _exit(126);
        });
    }
    connect(process, &QProcess::finished, this, [this, package, process](int code, QProcess::ExitStatus) {
        qCInfo(lcAm) << package << "(legacy) exited" << code;
        m_running.remove(package);
        process->deleteLater();
        m_server->broadcast(QStringLiteral("activity.exited"), QJsonObject{{QStringLiteral("package"), package}});
    });
    m_running.insert(package, Running{process, {}, QDateTime::currentMSecsSinceEpoch(), false, {}});
    process->start();
    if (!process->waitForStarted(3000)) {
        qCWarning(lcAm) << "cannot start" << package << process->errorString();
        m_running.remove(package);
        process->deleteLater();
        throw RpcError{protocol::Failed, process->errorString()};
    }
    qCInfo(lcAm) << "started" << package << "(legacy) pid" << process->processId();
    m_server->broadcast(QStringLiteral("activity.started"), QJsonObject{{QStringLiteral("package"), package}, {QStringLiteral("pid"), qint64(process->processId())}});
}

QJsonValue ActivityManager::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    const QString pkg = params.value(QLatin1String("package")).toString();
    if (call == QLatin1String("start")) {
        // Apps may start themselves, or another app to open or share files
        // of a type it declares ("Open with", the share sheet); privileged
        // apps (Settings) may start anything.
        if (!m_packages->contains(pkg))
            throw RpcError{protocol::NotFound, QStringLiteral("no package %1").arg(pkg)};
        if (!caller.isSystem() && caller.package != pkg && !caller.can(QLatin1String(permissions::MANAGE_PACKAGES)) &&
            !declaresIntent(m_packages->info(pkg), params.value(QLatin1String("args")).toObject()))
            throw RpcError{protocol::PermissionDenied, QStringLiteral("cannot start other apps")};
        if (m_waylandDisplay.isEmpty())
            throw RpcError{protocol::Failed, QStringLiteral("display not ready")};
        start(pkg, params.value(QLatin1String("args")).toObject());
        // Apps opening other apps (e.g. Settings > Open) bring them to the front.
        if (!caller.isSystem())
            m_server->broadcast(QStringLiteral("activity.front"), QJsonObject{{QStringLiteral("package"), pkg}});
        return true;
    }
    if (call == QLatin1String("stop")) {
        if (!caller.isSystem() && caller.package != pkg && !caller.can(QLatin1String(permissions::MANAGE_PACKAGES)))
            throw RpcError{protocol::PermissionDenied, QStringLiteral("cannot stop other apps")};
        stop(pkg);
        return true;
    }
    if (call == QLatin1String("stopAll")) {
        caller.requireSystem();
        const QStringList running = m_running.keys();
        for (const QString &p : running)
            stop(p);
        return QJsonArray::fromStringList(running);
    }
    if (call == QLatin1String("restart")) {
        if (!caller.isSystem() && caller.package != pkg)
            throw RpcError{protocol::PermissionDenied, QStringLiteral("cannot restart other apps")};
        restart(pkg.isEmpty() ? caller.package : pkg);
        return true;
    }
    if (call == QLatin1String("running")) {
        if (!caller.isSystem())
            caller.require(QLatin1String(permissions::MANAGE_PACKAGES));
        QJsonArray out;
        for (auto it = m_running.cbegin(); it != m_running.cend(); ++it)
            out.append(QJsonObject{{QStringLiteral("package"), it.key()},
                                   {QStringLiteral("pid"), qint64(it.value().process->processId())},
                                   {QStringLiteral("started"), double(it.value().started)}});
        return out;
    }
    if (call == QLatin1String("registerDisplay")) {
        // SysBoard announces the Wayland socket apps must connect to.
        caller.requireSystem();
        m_waylandDisplay = params.value(QLatin1String("socket")).toString();
        m_scaleFactor = params.value(QLatin1String("scale")).toVariant().toString();
        Q_EMIT displayRegistered(m_waylandDisplay);
        qCInfo(lcAm) << "display registered at" << m_waylandDisplay << "scale" << m_scaleFactor;
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
