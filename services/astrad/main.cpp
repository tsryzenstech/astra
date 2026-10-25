// SPDX-License-Identifier: Apache-2.0
//
// astrad - the astraOS system server.
//
// Hosts the system services every component talks to over
// /dev/socket/astrad (see docs/IPC.md).

#include "activitymanager.h"
#include "hardwareservice.h"
#include "locksettingsservice.h"
#include "mediasessionservice.h"
#include "notificationservice.h"
#include "packagemanager.h"
#include "server.h"
#include "settingsservice.h"
#include "systemservice.h"
#include "weatherservice.h"

#include <astra/paths.h>

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QSocketNotifier>

#include <csignal>
#include <sys/socket.h>
#include <unistd.h>

using namespace astrad;
using astra::Paths;

static int signalPipe[2];

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("astrad"));
    app.setApplicationVersion(QString::fromLatin1(astra::version()));

    for (const QString &dir : {Paths::dataSystem(), Paths::dataApp(), Paths::dataData(), Paths::userMedia(),
                               QFileInfo(Paths::astradSocket()).absolutePath()})
        QDir().mkpath(dir);

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
    packages.scan();
    ActivityManager activity(&server, &packages);
    NotificationService notifications(&server, &packages);
    LockSettingsService lock(&server);
    MediaSessionService media(&server, &packages);
    HardwareService hardware(&server, &settings);
    WeatherService weather(&server, &settings);
    SystemService system(&server, &settings, &notifications, &packages);

    server.setIdentify([&](Caller &caller) {
        QString package = activity.packageForPid(caller.pid);
        if (package.isEmpty())
            package = packages.packageForUid(caller.uid);
        caller.package = package;
        caller.permissions = packages.permissionsOf(package);
    });

    server.registerService(QStringLiteral("packages"), &packages);
    server.registerService(QStringLiteral("activity"), &activity);
    server.registerService(QStringLiteral("notifications"), &notifications);
    server.registerService(QStringLiteral("settings"), &settings);
    server.registerService(QStringLiteral("lock"), &lock);
    server.registerService(QStringLiteral("media"), &media);
    server.registerService(QStringLiteral("hardware"), &hardware);
    server.registerService(QStringLiteral("weather"), &weather);
    server.registerService(QStringLiteral("system"), &system);

    if (!server.listen(Paths::astradSocket()))
        return 1;
    return app.exec();
}
