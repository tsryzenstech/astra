// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QHash>

namespace astrad {

class NotificationService;
class PackageManager;
class SettingsService;

// System information, boot state, power control (through init), time zone,
// factory reset and screenshots (taken by SysBoard).
class SystemService : public Service
{
    Q_OBJECT
public:
    SystemService(Server *server, SettingsService *settings, NotificationService *notifications,
                  PackageManager *packages, QObject *parent = nullptr);

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

private:
    QJsonObject info() const;
    void bootCompleted();
    void applyTimezone(const QString &tz);

    Server *m_server;
    SettingsService *m_settings;
    NotificationService *m_notifications;
    PackageManager *m_packages;
    bool m_bootCompleted = false;
    QHash<int, PendingReply> m_screenshots;
    int m_nextScreenshot = 1;
};

} // namespace astrad
