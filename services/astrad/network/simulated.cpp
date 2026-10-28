// SPDX-License-Identifier: Apache-2.0
// Simulated radios for development trees (no Wi-Fi/Bluetooth/modem daemons).
// They behave like the real ones (scans, passwords, pairing, calls) so the
// whole UI can be exercised on a desktop. Never used on devices.
#include "backends.h"
#include "bluez.h"
#include "iwd.h"
#include "modemmanager.h"

#include <astra/paths.h>

#include <QDateTime>
#include <QRandomGenerator>
#include <QTimer>

namespace astrad::network {

namespace {

class SimWifi : public WifiBackend
{
public:
    explicit SimWifi(QObject *parent)
        : WifiBackend(parent)
    {
        m_networks = {
            {QStringLiteral("Iliad 5G"), QStringLiteral("psk"), 92},
            {QStringLiteral("astra-lab"), QStringLiteral("psk"), 74},
            {QStringLiteral("Vodafone-7F3A"), QStringLiteral("psk"), 51},
            {QStringLiteral("Cafe Guest"), QStringLiteral("open"), 38},
            {QStringLiteral("TIM-29481533"), QStringLiteral("psk"), 22},
        };
    }
    QString kind() const override { return QStringLiteral("simulated"); }
    bool available() const override { return true; }
    bool powered() const override { return m_powered; }
    void setPowered(bool on) override
    {
        m_powered = on;
        if (!on)
            m_connected.clear();
        Q_EMIT changed();
    }
    bool scanning() const override { return m_scanning; }
    void scan() override
    {
        if (!m_powered)
            return;
        m_scanning = true;
        Q_EMIT changed();
        QTimer::singleShot(1500, this, [this] {
            m_scanning = false;
            for (Net &n : m_networks)
                n.strength = qBound(5, n.strength + int(QRandomGenerator::global()->bounded(-8, 9)), 100);
            Q_EMIT changed();
        });
    }
    QJsonArray networks() const override
    {
        QJsonArray out;
        if (!m_powered)
            return out;
        for (const Net &n : m_networks)
            out.append(QJsonObject{{QStringLiteral("id"), n.ssid}, {QStringLiteral("ssid"), n.ssid},
                                   {QStringLiteral("security"), n.security}, {QStringLiteral("strength"), n.strength},
                                   {QStringLiteral("known"), m_known.contains(n.ssid)},
                                   {QStringLiteral("connected"), m_connected == n.ssid && !m_connecting}});
        return out;
    }
    QString state() const override
    {
        if (m_connecting)
            return QStringLiteral("connecting");
        return m_connected.isEmpty() ? QStringLiteral("disconnected") : QStringLiteral("connected");
    }
    void connectTo(const QString &id, const QString &passphrase, Done done) override
    {
        const auto it = std::find_if(m_networks.begin(), m_networks.end(), [&](const Net &n) { return n.ssid == id; });
        if (it == m_networks.end()) {
            done(QStringLiteral("network not found"));
            return;
        }
        const bool needsKey = it->security != QLatin1String("open") && !m_known.contains(id);
        m_connecting = true;
        m_connected = id;
        Q_EMIT changed();
        QTimer::singleShot(1200, this, [this, id, passphrase, needsKey, done] {
            m_connecting = false;
            if (needsKey && passphrase.size() < 8) {
                m_connected.clear();
                Q_EMIT changed();
                done(QStringLiteral("net.connman.iwd.Failed: wrong passphrase"));
                return;
            }
            m_known.insert(id);
            Q_EMIT changed();
            done({});
        });
    }
    void disconnectCurrent() override
    {
        m_connected.clear();
        Q_EMIT changed();
    }
    void forget(const QString &ssid) override
    {
        m_known.remove(ssid);
        if (m_connected == ssid)
            m_connected.clear();
        Q_EMIT changed();
    }
    QJsonArray knownNetworks() const override
    {
        QJsonArray out;
        for (const QString &k : m_known)
            out.append(QJsonObject{{QStringLiteral("ssid"), k}, {QStringLiteral("security"), QStringLiteral("psk")}});
        return out;
    }

private:
    struct Net {
        QString ssid, security;
        int strength;
    };
    QList<Net> m_networks;
    QSet<QString> m_known{QStringLiteral("Iliad 5G")};
    QString m_connected = QStringLiteral("Iliad 5G");
    bool m_powered = true;
    bool m_scanning = false;
    bool m_connecting = false;
};

class SimBluetooth : public BluetoothBackend
{
public:
    explicit SimBluetooth(QObject *parent)
        : BluetoothBackend(parent)
    {
        m_devices = {
            {QStringLiteral("4C:87:5D:11:22:33"), QStringLiteral("AirPods"), QStringLiteral("audio-headphones"), true, false, -48},
            {QStringLiteral("F8:DF:15:44:55:66"), QStringLiteral("JBL Flip 5"), QStringLiteral("audio-card"), false, false, -63},
            {QStringLiteral("C8:0F:10:77:88:99"), QStringLiteral("Mi Smart Band 7"), QStringLiteral("watch"), false, false, -71},
            {QStringLiteral("00:1A:7D:AA:BB:CC"), QStringLiteral("Desktop PC"), QStringLiteral("computer"), false, false, -80},
        };
    }
    QString kind() const override { return QStringLiteral("simulated"); }
    bool available() const override { return true; }
    bool powered() const override { return m_powered; }
    void setPowered(bool on) override
    {
        m_powered = on;
        if (!on)
            for (Dev &d : m_devices)
                d.connected = false;
        Q_EMIT changed();
    }
    QString name() const override { return m_name; }
    void setName(const QString &name) override
    {
        m_name = name;
        Q_EMIT changed();
    }
    bool discovering() const override { return m_discovering; }
    void setDiscovering(bool on) override
    {
        m_discovering = on && m_powered;
        Q_EMIT changed();
        if (m_discovering)
            QTimer::singleShot(8000, this, [this] {
                m_discovering = false;
                Q_EMIT changed();
            });
    }
    QJsonArray devices() const override
    {
        QJsonArray out;
        if (!m_powered)
            return out;
        for (const Dev &d : m_devices) {
            if (!d.paired && !m_discovering && !m_seen.contains(d.address))
                continue;
            out.append(QJsonObject{{QStringLiteral("address"), d.address}, {QStringLiteral("name"), d.name},
                                   {QStringLiteral("icon"), d.icon}, {QStringLiteral("paired"), d.paired},
                                   {QStringLiteral("connected"), d.connected}, {QStringLiteral("rssi"), d.rssi}});
        }
        return out;
    }
    void pair(const QString &address, Done done) override
    {
        QTimer::singleShot(1500, this, [this, address, done] {
            for (Dev &d : m_devices)
                if (d.address == address) {
                    d.paired = true;
                    d.connected = true;
                    m_seen.insert(address);
                }
            Q_EMIT changed();
            done({});
        });
    }
    void connectDevice(const QString &address, Done done) override
    {
        QTimer::singleShot(800, this, [this, address, done] {
            for (Dev &d : m_devices)
                if (d.address == address)
                    d.connected = true;
            Q_EMIT changed();
            done({});
        });
    }
    void disconnectDevice(const QString &address) override
    {
        for (Dev &d : m_devices)
            if (d.address == address)
                d.connected = false;
        Q_EMIT changed();
    }
    void forget(const QString &address) override
    {
        for (Dev &d : m_devices)
            if (d.address == address)
                d.paired = d.connected = false;
        m_seen.remove(address);
        Q_EMIT changed();
    }

private:
    struct Dev {
        QString address, name, icon;
        bool paired, connected;
        int rssi;
    };
    QList<Dev> m_devices;
    QSet<QString> m_seen;
    QString m_name = QStringLiteral("astra phone");
    bool m_powered = false;
    bool m_discovering = false;
};

class SimCellular : public CellularBackend
{
public:
    using CellularBackend::CellularBackend;
    QString kind() const override { return QStringLiteral("simulated"); }
    bool available() const override { return true; }
    QJsonObject state() const override
    {
        return {{QStringLiteral("simPresent"), true}, {QStringLiteral("operator"), QStringLiteral("astra Mobile")},
                {QStringLiteral("technology"), QStringLiteral("5G")}, {QStringLiteral("signal"), 78},
                {QStringLiteral("registered"), true}, {QStringLiteral("roaming"), false},
                {QStringLiteral("dataEnabled"), m_data}, {QStringLiteral("dataConnected"), m_data},
                {QStringLiteral("apn"), m_apn}, {QStringLiteral("allowRoaming"), m_roaming}};
    }
    void setDataEnabled(bool on, Done done) override
    {
        m_data = on;
        Q_EMIT changed();
        done({});
    }
    void setApn(const QString &apn) override { m_apn = apn; }
    void setAllowRoaming(bool on) override { m_roaming = on; }
    QJsonArray calls() const override { return m_calls; }
    void dial(const QString &number, Done done) override
    {
        const QString id = QStringLiteral("sim-call-%1").arg(++m_nextCall);
        m_calls.append(QJsonObject{{QStringLiteral("id"), id}, {QStringLiteral("number"), number},
                                   {QStringLiteral("state"), QStringLiteral("dialing")}, {QStringLiteral("direction"), QStringLiteral("out")}});
        Q_EMIT callsChanged();
        QTimer::singleShot(2500, this, [this, id] { setCallState(id, QStringLiteral("active")); });
        done({});
    }
    void accept(const QString &id) override { setCallState(id, QStringLiteral("active")); }
    void hangup(const QString &id) override
    {
        for (int i = 0; i < m_calls.size(); ++i)
            if (m_calls.at(i).toObject().value(QLatin1String("id")).toString() == id)
                m_calls.removeAt(i);
        Q_EMIT callsChanged();
    }
    void sendSms(const QString &, const QString &, Done done) override
    {
        QTimer::singleShot(600, this, [done] { done({}); });
    }

private:
    void setCallState(const QString &id, const QString &state)
    {
        for (int i = 0; i < m_calls.size(); ++i) {
            QJsonObject c = m_calls.at(i).toObject();
            if (c.value(QLatin1String("id")).toString() == id) {
                c.insert(QStringLiteral("state"), state);
                m_calls.replace(i, c);
            }
        }
        Q_EMIT callsChanged();
    }
    QJsonArray m_calls;
    int m_nextCall = 0;
    bool m_data = true;
    bool m_roaming = false;
    QString m_apn = QStringLiteral("internet");
};

// Development trees use simulated radios unless the real daemon is running.
bool simulate(const QString &service)
{
    return astra::Paths::isDevelopmentRoot() && !serviceRegistered(service);
}

} // namespace

WifiBackend *createWifi(QObject *parent)
{
    if (simulate(QStringLiteral("net.connman.iwd")))
        return new SimWifi(parent);
    return new IwdWifi(parent);
}

BluetoothBackend *createBluetooth(QObject *parent)
{
    if (simulate(QStringLiteral("org.bluez")))
        return new SimBluetooth(parent);
    return new BluezBluetooth(parent);
}

CellularBackend *createCellular(QObject *parent)
{
    if (simulate(QStringLiteral("org.freedesktop.ModemManager1")))
        return new SimCellular(parent);
    return new MMCellular(parent);
}

} // namespace astrad::network
