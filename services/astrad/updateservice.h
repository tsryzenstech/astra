// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QCryptographicHash>
#include <QJsonArray>

class QFile;
class QNetworkAccessManager;
class QNetworkReply;
class QTimer;

namespace astrad {

class NotificationService;
class SettingsService;

// OTA updates (see docs/VERSIONING.md), from the GitHub releases of the device
// repository the build names (ro.astra.ota.repo, from the device's board.conf).
//
// Channels: "stable" offers the releases, "prerelease" also the pre-releases
// (the automatic delta builds). The phone starts on its build's channel; the
// user can change it (update.channel). Each release carries ota.json:
//   {"tag", "version", "codename", "channel", "time", "notes": [...],
//    "files": {"super": {name, size, sha256, raw_size, raw_sha256}, "esp": {...}}}
// A release is newer when its "time" is later than this build's (ro.astra.ota.time).
//
// Installing: both files are downloaded and verified, unpacked into
// /data/ota/apply and verified again; on the next start the first stage of init
// writes them (core/init/ota.c) and restarts into the new system.
//
//   update.info, update.check, update.download, update.cancel, update.install,
//   update.setChannel {channel}, update.changelog
//   events: update.changed {status: idle|checking|uptodate|available|downloading|
//                                   preparing|ready|installing|error, ...}
class UpdateService : public Service
{
    Q_OBJECT
public:
    UpdateService(Server *server, SettingsService *settings, NotificationService *notifications,
                  QObject *parent = nullptr);
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

private:
    QJsonObject info() const;
    QJsonObject release() const;
    QString repository() const;
    QString channel() const;
    void check(bool automatic = false);
    void checkManifest(const QJsonObject &rel, bool automatic);
    void download();
    void downloadNext();
    void prepare();
    void unpackNext();
    void install();
    void cancel();
    void fail(const QString &error);
    void setStatus(const QString &status, const QString &error = QString());
    void afterUpdate();
    void announceAvailable();

    Server *m_server;
    SettingsService *m_settings;
    NotificationService *m_notifications;
    QNetworkAccessManager *m_network;
    QTimer *m_timer;
    QNetworkReply *m_reply = nullptr;
    QFile *m_file = nullptr;
    QCryptographicHash m_hash{QCryptographicHash::Sha256};
    QStringList m_queue;   // the files still to download or unpack ("super", "esp")
    qint64 m_done = 0;     // bytes of the files already downloaded
    qint64 m_total = 0;
    QString m_status = QStringLiteral("idle");
    QString m_error;
    QJsonObject m_available;
    double m_progress = 0;
    int m_notification = 0;
};

} // namespace astrad
