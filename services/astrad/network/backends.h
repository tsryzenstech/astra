// SPDX-License-Identifier: Apache-2.0
#pragma once

// Radio backends used by NetworkService. Each one has a real implementation
// on top of the standard Linux daemons (D-Bus): iwd, BlueZ and ModemManager.
//
//   Wi-Fi       iwd            (net.connman.iwd)
//   Bluetooth   BlueZ          (org.bluez)
//   Cellular    ModemManager   (org.freedesktop.ModemManager1): data, calls, SMS

#include <QJsonArray>
#include <QJsonObject>
#include <QObject>

#include <functional>

namespace astrad::network {

using Done = std::function<void(const QString &error)>; // empty error = success

class WifiBackend : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    virtual QString kind() const = 0;          // "iwd", "bluez", "modemmanager"
    virtual bool available() const = 0;        // hardware + daemon present
    virtual bool powered() const = 0;
    virtual void setPowered(bool on) = 0;
    virtual bool scanning() const = 0;
    virtual void scan() = 0;
    // [{id, ssid, security: open|psk|8021x|wep, strength 0-100, known, connected}]
    virtual QJsonArray networks() const = 0;
    virtual QString state() const = 0;         // disconnected|connecting|connected
    virtual void connectTo(const QString &id, const QString &passphrase, Done done) = 0;
    virtual void disconnectCurrent() = 0;
    virtual void forget(const QString &ssid) = 0;
    virtual QJsonArray knownNetworks() const = 0; // [{ssid, security}]
    // Nearby access points for network location: [{macAddress, signalStrength (dBm)}]
    virtual QJsonArray accessPoints() const { return {}; }
    virtual QString address() const { return {}; }   // MAC address
    // Personal Hotspot (access point mode).
    virtual bool hotspotSupported() const { return false; }
    virtual bool hotspotActive() const { return false; }
    virtual void setHotspot(bool on, const QString &ssid, const QString &passphrase, Done done)
    {
        Q_UNUSED(on) Q_UNUSED(ssid) Q_UNUSED(passphrase)
        done(QStringLiteral("not supported"));
    }
Q_SIGNALS:
    void changed();
};

class BluetoothBackend : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    virtual QString kind() const = 0;
    virtual bool available() const = 0;
    virtual bool powered() const = 0;
    virtual void setPowered(bool on) = 0;
    virtual QString name() const = 0;
    virtual void setName(const QString &name) = 0;
    virtual bool discovering() const = 0;
    virtual void setDiscovering(bool on) = 0;
    // [{address, name, icon, paired, connected, rssi}]
    virtual QJsonArray devices() const = 0;
    virtual void pair(const QString &address, Done done) = 0;
    virtual void connectDevice(const QString &address, Done done) = 0;
    virtual void disconnectDevice(const QString &address) = 0;
    virtual void forget(const QString &address) = 0;
    virtual QString address() const { return {}; }   // adapter address
Q_SIGNALS:
    void changed();
};

class CellularBackend : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    virtual QString kind() const = 0;
    virtual bool available() const = 0;        // a modem exists
    // {simPresent, operator, technology (5G|LTE|3G|2G|""), signal 0-100,
    //  registered, roaming, dataEnabled, dataConnected, apn, allowRoaming}
    virtual QJsonObject state() const = 0;
    virtual void setDataEnabled(bool on, Done done) = 0;
    virtual void setApn(const QString &apn) = 0;
    virtual void setAllowRoaming(bool on) = 0;

    // Calls: [{id, number, state: dialing|ringing|incoming|active|held|ended, direction: in|out}]
    virtual QJsonArray calls() const = 0;
    virtual void dial(const QString &number, Done done) = 0;
    virtual void accept(const QString &id) = 0;
    virtual void hangup(const QString &id) = 0;
    virtual void sendSms(const QString &number, const QString &text, Done done) = 0;
    // Location from the modem: "gnss" {lat, lon, accuracy} when the GNSS has
    // a fix, and the serving "cell" {radioType, mobileCountryCode, ...}.
    virtual void locate(std::function<void(const QJsonObject &)> done) { done({}); }
    // Network interface of the mobile data connection (for the hotspot).
    virtual QString dataInterface() const { return {}; }
Q_SIGNALS:
    void changed();
    void callsChanged();
    void smsReceived(const QString &number, const QString &text, qint64 timestamp);
};

// Factories (pick the real backend when its daemon is reachable).
WifiBackend *createWifi(QObject *parent);
BluetoothBackend *createBluetooth(QObject *parent);
CellularBackend *createCellular(QObject *parent);

} // namespace astrad::network
