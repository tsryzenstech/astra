// SPDX-License-Identifier: Apache-2.0
//
// astrad - the astraOS system server.
//
// Hosts the system services every component talks to over
// /dev/socket/astrad (see docs/IPC.md).

#include "activitymanager.h"
#include "alarmservice.h"
#include "accountservice.h"
#include "calendarservice.h"
#include "cloudyservice.h"
#include "contactsservice.h"
#include "locationservice.h"
#include "developerservice.h"
#include "dialogservice.h"
#include "displayservice.h"
#include "hardwareservice.h"
#include "locksettingsservice.h"
#include "mediasessionservice.h"
#include "network/networkservice.h"
#include "notificationservice.h"
#include "packagemanager.h"
#include "server.h"
#include "settingsservice.h"
#include "systemservice.h"
#include "updateservice.h"
#include "weatherservice.h"

#include <astra/paths.h>

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QThread>
#include <QSocketNotifier>

#include <csignal>
#include <sys/socket.h>
#include <unistd.h>

using namespace astrad;
using astra::Paths;

namespace {
int signalPipe[2];

// telephony.* is served by the network service (it owns the modem).
class TelephonyFacade : public Service
{
public:
    TelephonyFacade(NetworkService *network, QObject *parent)
        : Service(parent)
        , m_network(network)
    {
    }
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override
    {
        return m_network->handle(QStringLiteral("tel.") + call, params, caller);
    }

private:
    NetworkService *m_network;
};

// PipeWire (wpctl) when it runs, otherwise the ALSA mixer.
void applyVolume(SettingsService &settings)
{
    if (astra::Paths::isDevelopmentRoot())
        return;
    const double volume = qBound(0.0, settings.value(QStringLiteral("audio.volume")).toDouble(0.6), 1.0);
    const bool muted = !settings.value(QStringLiteral("controls.sound")).toBool(true);
    const QString wpctl = QStandardPaths::findExecutable(QStringLiteral("wpctl"), {QStringLiteral("/system/bin"), QStringLiteral("/usr/bin")});
    if (!wpctl.isEmpty()) {
        QProcess::startDetached(wpctl, {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), QString::number(volume, 'f', 2)});
        QProcess::startDetached(wpctl, {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"), muted ? QStringLiteral("1") : QStringLiteral("0")});
        return;
    }
    const QString amixer = QStandardPaths::findExecutable(QStringLiteral("amixer"), {QStringLiteral("/system/bin"), QStringLiteral("/usr/bin")});
    if (!amixer.isEmpty())
        QProcess::startDetached(amixer, {QStringLiteral("-q"), QStringLiteral("sset"), QStringLiteral("Master"),
                                         QString::number(qRound(volume * 100)) + QLatin1Char('%'),
                                         muted ? QStringLiteral("mute") : QStringLiteral("unmute")});
}
} // namespace

// Game Mode (a Focus): every CPU cluster on the performance governor;
// otherwise back to schedutil.
static void applyGameMode(SettingsService &settings)
{
    if (Paths::isDevelopmentRoot())
        return;
    const bool game = settings.value(QStringLiteral("focus.mode")).toString() == QLatin1String("game");
    const QDir cpufreq(QStringLiteral("/sys/devices/system/cpu/cpufreq"));
    for (const QString &policy : cpufreq.entryList({QStringLiteral("policy*")}, QDir::Dirs)) {
        QFile f(cpufreq.filePath(policy + QStringLiteral("/scaling_governor")));
        if (f.open(QIODevice::WriteOnly))
            f.write(game ? "performance" : "schedutil");
    }
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("astrad"));
    app.setApplicationVersion(QString::fromLatin1(astra::version()));

    for (const QString &dir : {Paths::dataSystem(), Paths::dataApp(), Paths::dataData(), Paths::userMedia(),
                               QFileInfo(Paths::astradSocket()).absolutePath()})
        QDir().mkpath(dir);
    for (const char *sub : {"Music", "Pictures", "Pictures/Screenshots", "DCIM/Camera", "Download", "Documents",
                            "Movies", "Recordings"})
        QDir().mkpath(Paths::userMedia() + QLatin1Char('/') + QLatin1String(sub));

    // Clean shutdown on SIGTERM (init stops services before rebooting).
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, signalPipe) == 0) {
        std::signal(SIGTERM, [](int) { (void)!write(signalPipe[0], "x", 1); });
        auto *notifier = new QSocketNotifier(signalPipe[1], QSocketNotifier::Read, &app);
        QObject::connect(notifier, &QSocketNotifier::activated, &app, &QCoreApplication::quit);
    }
    std::signal(SIGPIPE, SIG_IGN);

    Server server;
    SettingsService settings(&server);
    PackageManager packages(&server);
    packages.setLanguageProvider([&settings] { return settings.value(QStringLiteral("system.language")).toString(); });
    packages.setSideloadProvider([&settings] {
        return settings.value(QStringLiteral("developer.enabled")).toBool()
            && settings.value(QStringLiteral("developer.sideload")).toBool();
    });
    packages.scan();
    DialogService dialogs(&server, &packages);
    packages.setDialogs(&dialogs);
    ActivityManager activity(&server, &packages, &settings);
    NotificationService notifications(&server, &packages);
    LockSettingsService lock(&server);
    MediaSessionService media(&server, &packages);
    HardwareService hardware(&server, &settings);
    WeatherService weather(&server, &settings);
    SystemService system(&server, &settings, &notifications, &packages);
    // The radios talk to their daemons over the system bus, which init
    // starts just before us.
    if (!Paths::isDevelopmentRoot())
        for (int i = 0; i < 50 && !QFileInfo::exists(QStringLiteral("/run/dbus/system_bus_socket")); ++i)
            QThread::msleep(100);
    NetworkService network(&server, &settings, &notifications, &packages);
    TelephonyFacade telephony(&network, nullptr);
    ContactsService contacts(&server);
    LocationService location(&server, &settings, network.wifi(), network.cellular());
    AlarmService alarms(&server, &notifications);
    DisplayService display(&settings);
    UpdateService update(&server, &settings);
    DeveloperService developer(&server, &settings, &lock);
    CalendarService calendar(&server, &notifications);
    CloudyService cloudy(&server);
    AccountService account(&server, &settings, &notifications, &contacts, &location, &hardware, &network, &alarms);
    contacts.setChangedHook([&account] { account.contactsChanged(); });
    // Find My Device > Lock: SysBoard locks the phone.
    QObject::connect(&account, &AccountService::lockRequested, &server, [&server](const QString &message) {
        server.broadcast(QStringLiteral("system.lock"), QJsonObject{{QStringLiteral("message"), message}});
    });

    // App names follow the system language; the media volume and silent
    // mode go to the audio server.
    QObject::connect(&settings, &SettingsService::changed, &server, [&](const QString &key) {
        if (key == QLatin1String("system.language"))
            for (const QString &pkg : packages.packages())
                server.broadcast(QStringLiteral("packages.changed"), packages.info(pkg));
        if (key == QLatin1String("audio.volume") || key == QLatin1String("controls.sound"))
            applyVolume(settings);
        if (key == QLatin1String("focus.mode"))
            applyGameMode(settings);
    });
    applyVolume(settings);
    applyGameMode(settings);

    QObject::connect(&packages, &PackageManager::permissionsChanged, &server, [&](const QString &pkg, bool) {
        server.updatePermissions(pkg, packages.permissionsOf(pkg));
    });
    server.setIdentify([&](Caller &caller) {
        QString package = activity.packageForPid(caller.pid);
        if (package.isEmpty())
            package = packages.packageForUid(caller.uid);
        caller.package = package;
        caller.permissions = packages.permissionsOf(package);
    });

    auto updateSaver = [&](int level, bool charging) {
        activity.setBatterySaving(settings.value(QStringLiteral("battery.saver")).toBool() && level <= 20 && !charging);
    };
    QObject::connect(&hardware, &HardwareService::batteryChanged, &activity, updateSaver);

    server.registerService(QStringLiteral("packages"), &packages);
    server.registerService(QStringLiteral("activity"), &activity);
    server.registerService(QStringLiteral("notifications"), &notifications);
    server.registerService(QStringLiteral("settings"), &settings);
    server.registerService(QStringLiteral("lock"), &lock);
    server.registerService(QStringLiteral("media"), &media);
    server.registerService(QStringLiteral("hardware"), &hardware);
    server.registerService(QStringLiteral("weather"), &weather);
    server.registerService(QStringLiteral("system"), &system);
    server.registerService(QStringLiteral("dialogs"), &dialogs);
    server.registerService(QStringLiteral("network"), &network);
    server.registerService(QStringLiteral("telephony"), &telephony);
    server.registerService(QStringLiteral("contacts"), &contacts);
    server.registerService(QStringLiteral("location"), &location);
    server.registerService(QStringLiteral("calendar"), &calendar);
    server.registerService(QStringLiteral("cloudy"), &cloudy);
    server.registerService(QStringLiteral("account"), &account);
    server.registerService(QStringLiteral("alarms"), &alarms);
    server.registerService(QStringLiteral("display"), &display);
    server.registerService(QStringLiteral("update"), &update);
    server.registerService(QStringLiteral("developer"), &developer);

    if (!server.listen(Paths::astradSocket()))
        return 1;
    return app.exec();
}
