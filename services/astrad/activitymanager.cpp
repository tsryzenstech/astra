// SPDX-License-Identifier: Apache-2.0
#include "activitymanager.h"
#include "packagemanager.h"
#include "permissions.h"

#include <astra/global.h>
#include <astra/paths.h>
#include <astra/protocol.h>

#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLoggingCategory>
#include <QProcess>

#include <grp.h>
#include <unistd.h>

Q_LOGGING_CATEGORY(lcAm, "astrad.activity")

namespace astrad {

using namespace astra;

ActivityManager::ActivityManager(Server *server, PackageManager *packages, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_packages(packages)
{
    connect(packages, &PackageManager::packageRemoved, this, &ActivityManager::stop);
}

QString ActivityManager::packageForPid(pid_t pid) const
{
    for (auto it = m_running.cbegin(); it != m_running.cend(); ++it)
        if (it.value()->processId() == pid)
            return it.key();
    return {};
}

void ActivityManager::stop(const QString &package)
{
    if (QProcess *p = m_running.value(package))
        p->terminate();
}

void ActivityManager::start(const QString &package, const QJsonObject &args)
{
    if (m_running.contains(package)) {
        m_server->sendToPackage(package, QStringLiteral("activity.intent"), args);
        return;
    }
    const QJsonObject info = m_packages->info(package);
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
    env.insert(QStringLiteral("LANG"), QStringLiteral("en_US.UTF-8"));
    env.insert(QStringLiteral("ASTRA_PACKAGE"), package);
    env.insert(QStringLiteral("ASTRA_LAUNCH_ARGS"), QString::fromUtf8(QJsonDocument(args).toJson(QJsonDocument::Compact)));
    if (!m_scaleFactor.isEmpty())
        env.insert(QStringLiteral("QT_SCALE_FACTOR"), m_scaleFactor);
    // Development trees keep their own library and QML locations.
    for (const char *passthrough : {"ASTRA_ROOT", "ASTRA_ANIMATION_SCALE", "LD_LIBRARY_PATH", "QT_PLUGIN_PATH",
                                    "QML_IMPORT_PATH", "QT_LOGGING_RULES", "TZ", "PULSE_SERVER"}) {
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
        const bool internet = m_packages->permissionsOf(package).contains(QLatin1String(permissions::INTERNET));
        process->setChildProcessModifier([uid, internet] {
            gid_t groups[3] = {AID_GRAPHICS, AID_AUDIO, AID_INET};
            if (setgroups(internet ? 3 : 2, groups) != 0 || setgid(uid) != 0 || setuid(uid) != 0)
                _exit(126);
        });
    }

    connect(process, &QProcess::finished, this, [this, package, process](int code, QProcess::ExitStatus status) {
        qCInfo(lcAm) << package << "exited" << code << (status == QProcess::CrashExit ? "(crashed)" : "");
        m_running.remove(package);
        process->deleteLater();
        m_server->broadcast(QStringLiteral("activity.exited"), QJsonObject{{QStringLiteral("package"), package}});
    });
    m_running.insert(package, process);
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

QJsonValue ActivityManager::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    const QString pkg = params.value(QLatin1String("package")).toString();
    if (call == QLatin1String("start")) {
        // Apps may only start themselves or ask the system for other apps
        // through SysBoard; privileged apps (Settings) may start anything.
        if (!caller.isSystem() && caller.package != pkg && !caller.can(QLatin1String(permissions::MANAGE_PACKAGES)))
            throw RpcError{protocol::PermissionDenied, QStringLiteral("cannot start other apps")};
        if (!m_packages->contains(pkg))
            throw RpcError{protocol::NotFound, QStringLiteral("no package %1").arg(pkg)};
        if (m_waylandDisplay.isEmpty())
            throw RpcError{protocol::Failed, QStringLiteral("display not ready")};
        start(pkg, params.value(QLatin1String("args")).toObject());
        return true;
    }
    if (call == QLatin1String("stop")) {
        if (!caller.isSystem() && caller.package != pkg)
            throw RpcError{protocol::PermissionDenied, QStringLiteral("cannot stop other apps")};
        stop(pkg);
        return true;
    }
    if (call == QLatin1String("running")) {
        caller.requireSystem();
        return QJsonArray::fromStringList(m_running.keys());
    }
    if (call == QLatin1String("registerDisplay")) {
        // SysBoard announces the Wayland socket apps must connect to.
        caller.requireSystem();
        m_waylandDisplay = params.value(QLatin1String("socket")).toString();
        m_scaleFactor = params.value(QLatin1String("scale")).toVariant().toString();
        qCInfo(lcAm) << "display registered at" << m_waylandDisplay << "scale" << m_scaleFactor;
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
