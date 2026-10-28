// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

class QNetworkAccessManager;
class QNetworkReply;

namespace astrad {

class SettingsService;

// OTA updates (see docs/VERSIONING.md).
//
// The server publishes one manifest per device and channel:
//   <ro.astra.ota.url>/<device>/<channel>.json
//   {"version": "0.1d", "build": 128, "codename": "...", "url": "...", "size": 123, "sha256": "...", "notes": "..."}
// An update is available when its build number is greater than ours.
//
//   update.info, update.check, update.download, update.cancel
//   events: update.changed {status: idle|checking|uptodate|available|downloading|ready|error, ...}
class UpdateService : public Service
{
    Q_OBJECT
public:
    UpdateService(Server *server, SettingsService *settings, QObject *parent = nullptr);
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

private:
    QJsonObject info() const;
    void check();
    void download();
    void setStatus(const QString &status, const QString &error = QString());

    Server *m_server;
    SettingsService *m_settings;
    QNetworkAccessManager *m_network;
    QNetworkReply *m_download = nullptr;
    QString m_status = QStringLiteral("idle");
    QString m_error;
    QJsonObject m_available;
    double m_progress = 0;
};

} // namespace astrad
