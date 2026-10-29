// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QHash>

class QProcess;

namespace astrad {

class PackageManager;
class SettingsService;

// Launches apps in their own process, uid and sandbox environment.
//
// SysBoard asks for "activity.start"; if the app is already running the
// launch arguments are delivered to it as an "activity.intent" event instead.
class ActivityManager : public Service
{
    Q_OBJECT
public:
    ActivityManager(Server *server, PackageManager *packages, SettingsService *settings, QObject *parent = nullptr);

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    QString packageForPid(pid_t pid) const;
    bool isRunning(const QString &package) const { return m_running.contains(package); }
    void stop(const QString &package);
    void restart(const QString &package);
    // Starts an app from a system service (alarms, incoming calls...).
    void startFromSystem(const QString &package, const QJsonObject &args);
    // Battery saver engaged (low battery): apps start without animations.
    void setBatterySaving(bool on) { m_batterySaving = on; }

private:
    void start(const QString &package, const QJsonObject &args);

    struct Running {
        QProcess *process = nullptr;
        QJsonObject args;
        qint64 started = 0;
        bool restarting = false;
        QList<gid_t> groups;          // supplementary groups the process started with
    };
    // A permission granted while the app runs: open its files and devices
    // to the app's uid (POSIX ACLs) instead of restarting it.
    void grantAccess(const QString &package, gid_t gid);

    Server *m_server;
    PackageManager *m_packages;
    SettingsService *m_settings;
    QHash<QString, Running> m_running;
    QString m_waylandDisplay;
    QString m_scaleFactor;
    bool m_batterySaving = false;
};

} // namespace astrad
