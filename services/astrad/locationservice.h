// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QJsonObject>
#include <QList>
#include <QNetworkAccessManager>
#include <QTimer>

namespace astrad {

class SettingsService;
namespace network { class WifiBackend; class CellularBackend; }

// Where the phone is. The GNSS of the modem when it has a fix, otherwise
// the Wi-Fi access points and the serving cell around the phone, looked up
// with BeaconDB (an open, crowd sourced database; the IP address is the
// last resort). Settings > Privacy > Location Services turns it off.
//   location.get [{maxAge: seconds}] -> {lat, lon, accuracy, source, time}   LOCATION
//   location.state -> {enabled, fix}                                          LOCATION
//   event location.changed (to apps with LOCATION)
class LocationService : public Service
{
    Q_OBJECT
public:
    LocationService(Server *server, SettingsService *settings, network::WifiBackend *wifi,
                    network::CellularBackend *cell, QObject *parent = nullptr);
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    bool enabled() const;
    QJsonObject lastFix() const { return m_fix; }
    // Used inside astrad (Find My Device): a fresh fix, or {} when off.
    void locate(std::function<void(const QJsonObject &fix)> done);

private:
    void refresh();
    void lookup(const QJsonObject &modem);
    void finish(const QJsonObject &fix);

    Server *m_server;
    SettingsService *m_settings;
    network::WifiBackend *m_wifi;
    network::CellularBackend *m_cell;
    QNetworkAccessManager m_network;
    QJsonObject m_fix;
    bool m_busy = false;
    QList<std::function<void(const QJsonObject &)>> m_waiting;
    QTimer m_watch;          // refreshes while apps follow the location
    qint64 m_watchUntil = 0;
};

} // namespace astrad
