// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QHash>

class QProcess;

namespace astrad {

class PackageManager;

// Launches apps in their own process, uid and sandbox environment.
//
// SysBoard asks for "activity.start"; if the app is already running the
// launch arguments are delivered to it as an "activity.intent" event instead.
class ActivityManager : public Service
{
    Q_OBJECT
public:
    ActivityManager(Server *server, PackageManager *packages, QObject *parent = nullptr);

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    QString packageForPid(pid_t pid) const;
    void stop(const QString &package);

private:
    void start(const QString &package, const QJsonObject &args);

    Server *m_server;
    PackageManager *m_packages;
    QHash<QString, QProcess *> m_running;
    QString m_waylandDisplay;
    QString m_scaleFactor;
};

} // namespace astrad
