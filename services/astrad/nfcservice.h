// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QJsonObject>
#include <QThread>
#include <QTimer>

namespace astrad {

class NotificationService;
class SettingsService;
namespace nfc { class NfcAdapter; }

// NFC: tags held to the back of the phone. The setting "controls.nfc" turns it
// on (Settings > NFC, Control Center). A tag with an address, a number or a text
// gives a notification that opens it; Settings shows the last one in full and
// writes an address or a text to a tag.
//   nfc.state -> {available, enabled, on, tag, write: {waiting, ok, error}}   MANAGE_NETWORK
//   nfc.write {uri | text} -> the next tag held to the phone gets it          MANAGE_NETWORK
//   nfc.cancelWrite, nfc.forget (the last tag)                                MANAGE_NETWORK
//   event nfc.changed (the state), nfc.tag (a tag was read)
class NfcService : public Service
{
    Q_OBJECT
public:
    NfcService(Server *server, SettingsService *settings, NotificationService *notifications, QObject *parent = nullptr);
    ~NfcService() override;

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

private:
    QJsonObject state() const;
    bool wanted() const;
    void changed();
    void onTag(const QJsonObject &tag);
    void notify(const QJsonObject &tag);
    void endWrite(bool ok, const QString &error);

    Server *m_server;
    SettingsService *m_settings;
    NotificationService *m_notifications;
    QThread m_thread;
    nfc::NfcAdapter *m_adapter;
    bool m_available = false;
    bool m_on = false;
    QJsonObject m_tag;
    QJsonObject m_write;     // {waiting} or {ok, error} of the last one
    QTimer m_writeTimeout;
    int m_notification = 0;
};

} // namespace astrad
