// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "../server.h"
#include "backends.h"

#include <QHash>
#include <QJsonArray>
#include <QTimer>

namespace astrad {

class NotificationService;
class SettingsService;
class PackageManager;

// Wi-Fi, Bluetooth, mobile data and telephony (calls, call log, SMS).
//
//   network.state                                  everything, also pushed as network.changed
//   network.wifi{SetPowered,Scan,Connect,Disconnect,Forget}
//   network.bt{SetPowered,SetName,Discover,Pair,Connect,Disconnect,Forget}
//   network.cell{SetData,SetApn,SetRoaming}, network.setAirplane
//   telephony.{calls,dial,accept,hangup,callLog,clearCallLog}           PHONE
//   telephony.{conversations,messages,sendSms,markRead,deleteConversation} SMS
class NetworkService : public Service
{
    Q_OBJECT
public:
    NetworkService(Server *server, SettingsService *settings, NotificationService *notifications,
                   PackageManager *packages, QObject *parent = nullptr);

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;
    QJsonObject state() const;

private:
    QJsonValue handleTelephony(const QString &call, const QJsonObject &params, const Caller &caller);
    void announce();
    void setWifiPowered(bool on);
    void setBluetoothPowered(bool on);
    void setCellularData(bool on, network::Done done);
    void setAirplane(bool on);
    void onCallsChanged();
    void onSmsReceived(const QString &number, const QString &text, qint64 timestamp);
    void storeMessage(const QString &number, const QString &text, bool incoming, qint64 timestamp);
    void saveTelephony();

    Server *m_server;
    SettingsService *m_settings;
    NotificationService *m_notifications;
    PackageManager *m_packages;
    network::WifiBackend *m_wifi;
    network::BluetoothBackend *m_bt;
    network::CellularBackend *m_cell;
    QTimer m_announce;
    QTimer m_rescan;

    QString m_storePath;
    QJsonArray m_callLog;   // [{number, direction, missed, start, duration}]
    QJsonArray m_messages;  // [{id, number, text, incoming, time, read}]
    int m_nextMessage = 1;
    QHash<QString, QJsonObject> m_liveCalls; // id -> {number, direction, start, answered}
};

} // namespace astrad
