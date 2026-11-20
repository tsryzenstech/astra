// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "backends.h"
#include "dbusutil.h"

namespace astrad::network {

// Wi-Fi through NetworkManager (org.freedesktop.NetworkManager): the desktop's network daemon (Debian). It does
// what IwdWifi does on the phone: scan, list, connect (with a passphrase for a new network, a saved profile
// otherwise), disconnect, forget, and share the connection as an access point. A network's `id` is its SSID.
// The calls are synchronous (short, to a local daemon) and run when the daemon says something changed.
class NMWifi : public WifiBackend
{
    Q_OBJECT
public:
    explicit NMWifi(QObject *parent);

    QString kind() const override { return QStringLiteral("networkmanager"); }
    bool available() const override { return !m_device.isEmpty(); }
    bool powered() const override { return m_powered; }
    void setPowered(bool on) override;
    bool scanning() const override { return m_scanning; }
    void scan() override;
    QJsonArray networks() const override { return m_networks; }
    QString state() const override { return m_state; }
    void connectTo(const QString &id, const QString &passphrase, Done done) override;
    void disconnectCurrent() override;
    void forget(const QString &ssid) override;
    QJsonArray knownNetworks() const override { return m_known; }
    QJsonArray accessPoints() const override { return m_apList; }
    QString address() const override { return m_mac; }
    bool hotspotSupported() const override { return available(); }
    bool hotspotActive() const override { return !m_hotspot.isEmpty(); }
    void setHotspot(bool on, const QString &ssid, const QString &passphrase, Done done) override;

    static bool daemonPresent();

private:
    void refresh();
    QVariantMap getAll(const QString &path, const QString &iface) const;
    QString connectionFor(const QString &ssid) const;

    DBusWatcher *m_watcher;
    QString m_device;                    // the Wi-Fi device's object path
    bool m_powered = false;
    bool m_scanning = false;
    QString m_state = QStringLiteral("disconnected");
    QString m_mac;
    QString m_hotspot;                   // the active connection of the hotspot, if any
    QJsonArray m_networks, m_known, m_apList;
    QHash<QString, QString> m_profiles;  // ssid -> saved connection path
};

} // namespace astrad::network
