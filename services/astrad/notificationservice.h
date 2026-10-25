// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QJsonArray>

namespace astrad {

class PackageManager;

// Delivers notifications posted by apps to SysBoard's Notification Center.
// Notifications persist across reboots until dismissed.
class NotificationService : public Service
{
    Q_OBJECT
public:
    NotificationService(Server *server, PackageManager *packages, QObject *parent = nullptr);

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    // Posts on behalf of a package (used by the system itself, e.g. Tips).
    int post(const QString &package, const QString &title, const QString &body);
    void removePackage(const QString &package);

private:
    void save();
    QJsonObject decorate(const QJsonObject &n) const;

    Server *m_server;
    PackageManager *m_packages;
    QString m_path;
    QJsonArray m_items;
    int m_nextId = 1;
};

} // namespace astrad
