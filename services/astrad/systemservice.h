// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

namespace astrad {

class NotificationService;
class PackageManager;
class SettingsService;

// System information, boot state and power control (through init).
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
    static bool sendToInit(const QByteArray &command);

    Server *m_server;
    SettingsService *m_settings;
    NotificationService *m_notifications;
    PackageManager *m_packages;
    bool m_bootCompleted = false;
};

} // namespace astrad
