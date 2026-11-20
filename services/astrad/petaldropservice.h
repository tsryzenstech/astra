// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QByteArray>
#include <QElapsedTimer>
#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QPointer>
#include <QTimer>

class QFile;
class QTcpServer;
class QTcpSocket;
class QUdpSocket;

namespace astrad {

class AccountService;
class DialogService;
class NotificationService;
class SettingsService;

// PetalDrop: send photos and files to a device nearby, at once, from any "Share" button (Gallery, Files...).
// It is a part of the system, not an app: there is no icon, no window; the share sheet lists the devices near
// you and astrad does the rest (docs/DESKTOP.md).
//
//   petaldrop.state                      -> {receive, name, kind, port, peers, transfers}
//   petaldrop.peers                      -> the devices nearby: [{id, name, kind, mine, address, port}]
//   petaldrop.send {peer, files: [path]} -> {id}; progress comes as "petaldrop.transfer" events (topic "petaldrop")
//   petaldrop.cancel {id}
//       send, peers: NEARBY_DEVICES (a runtime permission, so the first share asks the user); files must be in the
//       shared storage or the app's own data directory. state, cancel: the same.
// The switch is the setting "petaldrop.receive": "off", "mydevices" (the default: only the devices of your own
// AstraID; others are refused) or "everyone" (anybody on the network can ask, and the user answers each time).
//
// How: every device that can receive announces itself on the network (UDP broadcast, port 47742: a random id,
// the name of its owner, phone or desktop, and the port it listens on). AstraID makes it "mine": it gives each
// device of the account a common secret (astra-cloud /api/device/petal); an offer signed with it (HMAC-SHA256)
// is from the same account, and is accepted without asking. The devices of the account are also listed by the
// server with the addresses they reported, so they are found even where broadcasts do not reach. A transfer is
// a TCP connection on port 47743: the offer (names, sizes), the answer, the files each with its SHA-256.
//
// Not yet: transport encryption (the files cross the local network in the clear; their integrity is checked).
class PetalDropService : public Service
{
    Q_OBJECT
public:
    PetalDropService(Server *server, SettingsService *settings, AccountService *account, DialogService *dialogs,
                     NotificationService *notifications, QObject *parent = nullptr);
    ~PetalDropService() override;
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    static constexpr quint16 BeaconPort = 47742;
    static constexpr quint16 TransferPort = 47743;

private:
    struct Peer {
        QString id, name, kind, address;
        quint16 port = 0;
        bool mine = false;
        qint64 seen = 0;
    };
    struct Transfer;
    struct Incoming;

    QString receiveMode() const;
    QString deviceName() const;
    QString deviceKind() const;
    QString selfId();
    void configure();
    void beacon();
    void readBeacons();
    void syncAccount();
    QJsonArray peerList() const;
    QJsonObject state() const;
    QByteArray sign(const QString &id, const QJsonArray &files) const;
    bool isMine(const QString &id, const QJsonArray &files, const QString &signature) const;

    void incomingConnection();
    void readIncoming(Incoming *in);
    void finishIncoming(Incoming *in, const QString &outcome);
    void startTransfer(Transfer *t);
    void pump(Transfer *t);
    void emitTransfer(const Transfer *t);

    Server *m_server;
    SettingsService *m_settings;
    AccountService *m_account;
    DialogService *m_dialogs;
    NotificationService *m_notifications;

    QTcpServer *m_tcp = nullptr;
    QUdpSocket *m_udp = nullptr;
    QTimer m_beaconTimer;
    QTimer m_accountTimer;
    QString m_selfId;
    QByteArray m_key;                  // the account's PetalDrop secret (empty: signed out)
    QHash<QString, Peer> m_beaconPeers;   // by id, from broadcasts
    QHash<QString, Peer> m_accountPeers;  // by id, from the server
    QHash<int, Transfer *> m_transfers;
    int m_nextTransfer = 1;
};

} // namespace astrad
