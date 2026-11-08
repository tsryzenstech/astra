// SPDX-License-Identifier: Apache-2.0
#include "androidservice.h"
#include "initcontrol.h"
#include "notificationservice.h"
#include "packagemanager.h"
#include "settingsservice.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QLoggingCategory>
#include <QProcess>
#include <QRegularExpression>
#include <QTimer>

#include <grp.h>
#include <unistd.h>

Q_LOGGING_CATEGORY(lcAndroid, "astrad.android")

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s)
{
    return QString::fromLatin1(s);
}
const char kMyDroid[] = "com.astra.mydroid";
QString waydroidBin()
{
    return Paths::resolve(QStringLiteral("/system/bin/waydroid"));
}
QString waydroidData()
{
    return Paths::resolve(QStringLiteral("/data/var/lib/waydroid"));
}
// "android." + the Android package, as an astraOS package name.
QString shortcutName(const QString &androidPackage)
{
    QStringList parts;
    for (QString part : androidPackage.toLower().split(QLatin1Char('.'), Qt::SkipEmptyParts)) {
        part.replace(QRegularExpression(QStringLiteral("[^a-z0-9_]")), QStringLiteral("_"));
        if (part.isEmpty() || !part.at(0).isLetter())
            part.prepend(QLatin1Char('a'));
        parts << part;
    }
    return QStringLiteral("android.") + parts.join(QLatin1Char('.'));
}
} // namespace

AndroidService::AndroidService(Server *server, PackageManager *packages, NotificationService *notifications,
                               SettingsService *settings, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_packages(packages)
    , m_notifications(notifications)
    , m_settings(settings)
    , m_poll(new QTimer(this))
{
    m_poll->setInterval(15000);
    connect(m_poll, &QTimer::timeout, this, &AndroidService::pollNotifications);
    // An Android app's home icon removed (App Info > Uninstall): the app too.
    connect(packages, &PackageManager::packageRemoved, this, [this](const QString &pkg) {
        for (const QJsonValue &v : std::as_const(m_apps)) {
            const QJsonObject a = v.toObject();
            if (a.value(K("shortcut")).toString() == pkg && m_running)
                waydroid({K("app"), K("remove"), a.value(K("package")).toString()}, true, [this](int, QString) { refreshApps(); });
        }
    });
    // Android was on before the phone restarted: on again.
    if (m_settings->value(K("android.enabled")).toBool() && installed())
        QTimer::singleShot(20000, this, &AndroidService::start);
}

AndroidService::~AndroidService()
{
    if (m_session) {
        m_session->disconnect(this);
        m_session->terminate();
        m_session->waitForFinished(2000);
    }
}

bool AndroidService::installed() const
{
    return QFile::exists(waydroidData() + QStringLiteral("/images/system.img"));
}

QString AndroidService::userHome() const
{
    return m_packages->info(K(kMyDroid)).value(K("dataDir")).toString();
}

QJsonObject AndroidService::status() const
{
    return {
        {K("available"), QFileInfo(waydroidBin()).isExecutable()},
        {K("installed"), installed()},
        {K("running"), m_running},
        {K("busy"), m_setup != nullptr || (!m_step.isEmpty() && !m_running)},
        {K("step"), m_step},
        {K("progress"), m_progress},
        {K("error"), m_error},
        {K("variant"), m_settings->value(K("android.variant")).toString(K("vanilla"))},
        {K("apps"), m_apps},
    };
}

void AndroidService::changed()
{
    m_server->broadcast(K("android.changed"), status());
}

QProcess *AndroidService::waydroid(const QStringList &args, bool asUser, std::function<void(int, QString)> done)
{
    auto *p = new QProcess(this);
    p->setProgram(waydroidBin());
    p->setArguments(args);
    p->setProcessChannelMode(QProcess::MergedChannels);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(K("PATH"), K("/system/bin"));
    // Waydroid's session and its commands find each other on a session bus of
    // their own (astraOS has no desktop session bus), at a fixed address. They
    // run as root: Waydroid asks the system for its user's name, and the apps'
    // users are not in /etc/passwd (tried on the phone). Android itself stays
    // in its container.
    Q_UNUSED(asUser)
    const QString home = userHome();
    if (!home.isEmpty()) {
        QDir().mkpath(home + QStringLiteral("/.local/share"));
        env.insert(K("HOME"), home);
        env.insert(K("XDG_DATA_HOME"), home + QStringLiteral("/.local/share"));
        p->setWorkingDirectory(home);
    }
    QDir().mkpath(Paths::resolve(QStringLiteral("/run/waydroid/xdg")));
    env.insert(K("XDG_RUNTIME_DIR"), Paths::resolve(QStringLiteral("/run/waydroid/xdg")));
    env.insert(K("DBUS_SESSION_BUS_ADDRESS"), QStringLiteral("unix:path=") + Paths::resolve(QStringLiteral("/run/waydroid/session-bus")));
    env.insert(K("WAYLAND_DISPLAY"), m_display);
    // Where Waydroid finds the sound server it shares with Android.
    env.insert(K("PULSE_RUNTIME_PATH"), K("/run/astra/audio/pulse"));
    p->setProcessEnvironment(env);
    connect(p, &QProcess::finished, this, [p, done](int code, QProcess::ExitStatus st) {
        const QString out = QString::fromUtf8(p->readAll());
        p->deleteLater();
        if (done)
            done(st == QProcess::NormalExit ? code : -1, out);
    });
    connect(p, &QProcess::errorOccurred, this, [p, done](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart)
            return;
        p->deleteLater();
        if (done)
            done(-1, QStringLiteral("waydroid is not installed"));
    });
    p->start();
    return p;
}

// Downloads Android (Waydroid's LineageOS images) and prepares the container.
void AndroidService::setup(const QString &variant)
{
    if (m_setup)
        return;
    m_settings->setValue(K("android.variant"), variant);
    m_step = K("download");
    m_error.clear();
    m_progress = -1;
    changed();
    QDir().mkpath(waydroidData());
    m_setup = waydroid({K("init"), K("-f"), K("-s"), variant == QLatin1String("gapps") ? K("GAPPS") : K("VANILLA")}, false,
                       [this](int code, QString out) {
        m_setup = nullptr;
        if (code != 0 || !installed()) {
            m_step.clear();
            m_error = out.trimmed().section(QLatin1Char('\n'), -3).trimmed();
            if (m_error.isEmpty())
                m_error = K("Android could not be downloaded");
            qCWarning(lcAndroid) << "init failed:" << out.right(2000);
            changed();
            return;
        }
        // Each Android app in its own window, which SysBoard shows like any app.
        QFile prop(waydroidData() + QStringLiteral("/waydroid_base.prop"));
        if (prop.open(QIODevice::Append))
            prop.write("persist.waydroid.multi_windows=false\n");
        prop.close();
        m_progress = -1;
        start();
    });
    // "[Downloading] 512.05 MB/850.00 MB ..." lines: the share done.
    connect(m_setup, &QProcess::readyRead, this, [this] {
        if (!m_setup)
            return;
        static const QRegularExpression re(QStringLiteral("([0-9.]+) ?MB ?/ ?([0-9.]+) ?MB"));
        const QString out = QString::fromUtf8(m_setup->peek(1 << 16));
        QRegularExpressionMatch last;
        for (auto it = re.globalMatch(out); it.hasNext();)
            last = it.next();
        if (last.hasMatch() && last.captured(2).toDouble() > 0) {
            const double progress = last.captured(1).toDouble() / last.captured(2).toDouble();
            if (progress - m_progress > 0.01) {
                m_progress = progress;
                changed();
            }
        }
        if (m_setup->bytesAvailable() > (1 << 20))
            m_setup->read(m_setup->bytesAvailable() - (1 << 16)); // keep the tail only
    });
}

void AndroidService::start()
{
    if (m_running || !installed())
        return;
    m_settings->setValue(K("android.enabled"), true);
    m_step = K("starting");
    m_error.clear();
    changed();
    sendToInit("start waydroid-container");
    // The container needs a moment before a session can attach.
    QTimer::singleShot(4000, this, &AndroidService::startSession);
}

void AndroidService::startSession()
{
    if (m_session)
        return;
    if (m_display.isEmpty()) {
        QTimer::singleShot(3000, this, &AndroidService::startSession);
        return;
    }
    // Android draws in one full screen surface: multi-window mode leaves each app
    // in a small floating window, whatever size SysBoard asks for (tried).
    QFile prop(waydroidData() + QStringLiteral("/waydroid_base.prop"));
    if (prop.open(QIODevice::ReadOnly)) {
        QByteArray text = prop.readAll();
        prop.close();
        if (text.contains("persist.waydroid.multi_windows=true") && prop.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            text.replace("persist.waydroid.multi_windows=true", "persist.waydroid.multi_windows=false");
            prop.write(text);
            prop.close();
        }
    }
    // The session bus, once.
    if (!m_bus) {
        const QString socket = Paths::resolve(QStringLiteral("/run/waydroid/session-bus"));
        QDir().mkpath(Paths::resolve(QStringLiteral("/run/waydroid")));
        QFile::remove(socket);
        m_bus = new QProcess(this);
        m_bus->setProgram(Paths::resolve(QStringLiteral("/system/bin/dbus-daemon")));
        m_bus->setArguments({K("--session"), QStringLiteral("--address=unix:path=") + socket, K("--nofork"), K("--nopidfile")});
        m_bus->setStandardOutputFile(QProcess::nullDevice());
        m_bus->setStandardErrorFile(QProcess::nullDevice());
        connect(m_bus, &QProcess::finished, this, [this] {
            m_bus->deleteLater();
            m_bus = nullptr;
        });
        m_bus->start();
        QTimer::singleShot(800, this, &AndroidService::startSession);
        return;
    }
    m_session = waydroid({K("session"), K("start")}, true, [this](int code, QString out) {
        m_session = nullptr;
        const bool wasRunning = m_running;
        m_running = false;
        m_poll->stop();
        if (m_step == QLatin1String("stopping") || code == 0) {
            m_step.clear();
        } else {
            m_step.clear();
            m_error = out.trimmed().section(QLatin1Char('\n'), -3).trimmed();
            qCWarning(lcAndroid) << "session ended" << code << out.right(2000);
        }
        if (wasRunning || !m_error.isEmpty())
            changed();
    });
    connect(m_session, &QProcess::readyRead, this, [this] {
        if (!m_session)
            return;
        const QString out = QString::fromUtf8(m_session->readAll());
        if (!m_running && out.contains(QLatin1String("is ready"))) {
            m_running = true;
            m_step.clear();
            m_poll->start();
            changed();
            QTimer::singleShot(2000, this, &AndroidService::refreshApps);
        }
    });
}

void AndroidService::stop()
{
    m_settings->setValue(K("android.enabled"), false);
    m_step = K("stopping");
    changed();
    waydroid({K("session"), K("stop")}, true, [this](int, QString) {
        sendToInit("stop waydroid-container");
        if (m_session)
            m_session->terminate();
        m_running = false;
        m_step.clear();
        m_poll->stop();
        changed();
    });
}

void AndroidService::reset()
{
    stop();
    QTimer::singleShot(5000, this, [this] {
        for (const QJsonValue &v : std::as_const(m_apps))
            m_packages->removeShortcut(v.toObject().value(K("shortcut")).toString());
        m_apps = {};
        m_settings->setValue(K("android.apps"), QJsonArray());
        QDir(waydroidData()).removeRecursively();
        QDir().mkpath(waydroidData());
        QDir(userHome() + QStringLiteral("/.local/share/waydroid")).removeRecursively();
        changed();
    });
}

// Installs an APK; its app gets a home icon. The new package is what the
// app list gains.
void AndroidService::installApk(const QString &path, std::function<void(QString)> done)
{
    if (!m_running) {
        done(K("Turn Android on first"));
        return;
    }
    waydroid({K("app"), K("list")}, true, [this, path, done](int, QString before) {
        // The session user may not read the file where it is: a copy it can.
        const QString copy = userHome() + QStringLiteral("/cache/install.apk");
        QFile::remove(copy);
        if (!QFile::copy(path, copy)) {
            done(K("The file could not be read"));
            return;
        }
        waydroid({K("app"), K("install"), copy}, true, [this, before, copy, done](int code, QString out) {
            QFile::remove(copy);
            if (code != 0) {
                done(out.trimmed().isEmpty() ? K("Android could not install this app") : out.trimmed().section(QLatin1Char('\n'), -1));
                return;
            }
            // Android lists the new app after a moment.
            QTimer::singleShot(3000, this, [this, before, done] {
                waydroid({K("app"), K("list")}, true, [this, before, done](int, QString after) {
                    static const QRegularExpression pkgRe(QStringLiteral("packageName: (\\S+)"));
                    QStringList tracked;
                    for (const QJsonValue &v : m_settings->value(K("android.apps")).toArray())
                        tracked << v.toString();
                    for (auto it = pkgRe.globalMatch(after); it.hasNext();) {
                        const QString pkg = it.next().captured(1);
                        if (!before.contains(QStringLiteral("packageName: ") + pkg + QLatin1Char('\n')) &&
                            !before.endsWith(QStringLiteral("packageName: ") + pkg) && !tracked.contains(pkg))
                            tracked << pkg;
                    }
                    m_settings->setValue(K("android.apps"), QJsonArray::fromStringList(tracked));
                    refreshApps();
                    done(QString());
                });
            });
        });
    });
}

// The Android apps installed through MyDroid, with their home icons.
void AndroidService::refreshApps()
{
    if (!m_running)
        return;
    waydroid({K("app"), K("list")}, true, [this](int code, QString out) {
        if (code != 0)
            return;
        QStringList tracked;
        for (const QJsonValue &v : m_settings->value(K("android.apps")).toArray())
            tracked << v.toString();
        QJsonArray apps;
        QString name;
        for (const QString &line : out.split(QLatin1Char('\n'))) {
            if (line.startsWith(QLatin1String("Name: ")))
                name = line.mid(6).trimmed();
            else if (line.startsWith(QLatin1String("packageName: "))) {
                const QString pkg = line.mid(13).trimmed();
                if (tracked.contains(pkg))
                    apps.append(QJsonObject{{K("package"), pkg}, {K("name"), name}, {K("shortcut"), shortcutName(pkg)}});
            }
        }
        // Gone from Android (removed there): forget it.
        QStringList present;
        for (const QJsonValue &v : apps)
            present << v.toObject().value(K("package")).toString();
        m_settings->setValue(K("android.apps"), QJsonArray::fromStringList(present));
        syncShortcuts(apps);
        m_apps = apps;
        changed();
    });
}

void AndroidService::syncShortcuts(const QJsonArray &apps)
{
    QSet<QString> wanted;
    const QString icons = userHome() + QStringLiteral("/.local/share/waydroid/data/icons/");
    for (const QJsonValue &v : apps) {
        const QJsonObject a = v.toObject();
        const QString shortcut = a.value(K("shortcut")).toString();
        wanted.insert(shortcut);
        const QString icon = icons + a.value(K("package")).toString() + QStringLiteral(".png");
        if (m_packages->contains(shortcut) && m_packages->info(shortcut).value(K("name")) == a.value(K("name")))
            continue;
        m_packages->installShortcut(QJsonObject{{K("package"), shortcut}, {K("name"), a.value(K("name"))},
                                                {K("android"), QJsonObject{{K("package"), a.value(K("package"))}}},
                                                {K("description"), K("Android app (MyDroid)")}},
                                    icon, K(kMyDroid));
    }
    // Shortcuts whose app is gone.
    for (const QString &pkg : m_packages->packages())
        if (pkg.startsWith(QLatin1String("android.")) && !wanted.contains(pkg) &&
            m_packages->info(pkg).value(K("installer")).toString() == QLatin1String(kMyDroid))
            m_packages->removeShortcut(pkg);
}

void AndroidService::launchApp(const QString &androidPackage)
{
    if (!m_running) {
        // Tapped with Android off: on, then the app.
        start();
        QTimer *wait = new QTimer(this);
        wait->setInterval(1000);
        int *tries = new int(0);
        connect(wait, &QTimer::timeout, this, [this, wait, tries, androidPackage] {
            if (m_running || ++*tries > 90) {
                wait->deleteLater();
                delete tries;
                if (m_running)
                    launchApp(androidPackage);
            }
        });
        wait->start();
        return;
    }
    waydroid({K("app"), K("launch"), androidPackage}, true, nullptr);
}

// Android's notifications as the app's: what dumpsys lists now.
void AndroidService::pollNotifications()
{
    if (!m_running || m_apps.isEmpty())
        return;
    QHash<QString, QString> shortcuts; // android package -> astraOS package
    for (const QJsonValue &v : std::as_const(m_apps))
        shortcuts.insert(v.toObject().value(K("package")).toString(), v.toObject().value(K("shortcut")).toString());
    waydroid({K("shell"), K("--"), K("dumpsys"), K("notification"), K("--noredact")}, false,
             [this, shortcuts](int code, QString out) {
        if (code != 0)
            return;
        static const QRegularExpression recordRe(QStringLiteral("NotificationRecord\\([^)]*pkg=(\\S+)[^)]*id=(-?\\d+)"));
        static const QRegularExpression titleRe(QStringLiteral("android\\.title=\\w+ \\((.*)\\)"));
        static const QRegularExpression textRe(QStringLiteral("android\\.text=\\w+ \\((.*)\\)"));
        static const QRegularExpression ongoingRe(QStringLiteral("flags=0x[0-9a-fA-F]*"));
        QHash<QString, int> seen;
        const QStringList blocks = out.split(QStringLiteral("NotificationRecord("));
        for (int i = 1; i < blocks.size(); ++i) {
            const QString block = QStringLiteral("NotificationRecord(") + blocks.at(i);
            const QRegularExpressionMatch rec = recordRe.match(block);
            if (!rec.hasMatch() || !shortcuts.contains(rec.captured(1)))
                continue;
            const QString key = rec.captured(1) + QLatin1Char('|') + rec.captured(2);
            if (seen.contains(key))
                continue;
            // Ongoing ones (a player, a download) are left out, as Android's own badge does.
            const QRegularExpressionMatch flags = ongoingRe.match(block);
            if (flags.hasMatch() && (flags.captured(0).mid(8).toUInt(nullptr, 16) & 0x2))
                continue;
            const QString title = titleRe.match(block).captured(1);
            const QString text = textRe.match(block).captured(1);
            int id = m_posted.value(key);
            if (!id) {
                id = m_notifications->post(shortcuts.value(rec.captured(1)), title.isEmpty() ? K("Android") : title, text,
                                           QJsonObject());
            }
            seen.insert(key, id);
        }
        // What Android no longer has goes away here too.
        for (auto it = m_posted.cbegin(); it != m_posted.cend(); ++it)
            if (!seen.contains(it.key()))
                m_notifications->dismissId(it.value());
        m_posted = seen;
    });
}

QJsonValue AndroidService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    if (!caller.isSystem() && caller.package != QLatin1String(kMyDroid))
        throw RpcError{protocol::PermissionDenied, K("only MyDroid manages Android")};
    if (call == QLatin1String("status"))
        return status();
    if (!QFileInfo(waydroidBin()).isExecutable())
        throw RpcError{protocol::Failed, K("This build has no Android environment (waydroid)")};
    if (call == QLatin1String("setup")) {
        setup(params.value(K("variant")).toString(K("vanilla")));
        return true;
    }
    if (call == QLatin1String("start")) {
        start();
        return true;
    }
    if (call == QLatin1String("stop")) {
        stop();
        return true;
    }
    if (call == QLatin1String("reset")) {
        reset();
        return true;
    }
    if (call == QLatin1String("refresh")) {
        refreshApps();
        return true;
    }
    if (call == QLatin1String("install")) {
        const QString path = params.value(K("path")).toString();
        if (!path.endsWith(QLatin1String(".apk"), Qt::CaseInsensitive) || !QFile::exists(path))
            throw RpcError{protocol::InvalidParams, K("choose an .apk file")};
        const PendingReply reply = caller.defer();
        installApk(path, [reply](const QString &error) {
            if (error.isEmpty())
                reply.resolve(true);
            else
                reply.reject(protocol::Failed, error);
        });
        return Deferred;
    }
    if (call == QLatin1String("launch")) {
        launchApp(params.value(K("package")).toString());
        return true;
    }
    if (call == QLatin1String("remove")) {
        const QString pkg = params.value(K("package")).toString();
        waydroid({K("app"), K("remove"), pkg}, true, [this](int, QString) { refreshApps(); });
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
