// SPDX-License-Identifier: Apache-2.0
#include "nm.h"

#include <QDBusInterface>
#include <QDBusReply>
#include <QLoggingCategory>
#include <QSet>

#include <memory>

Q_LOGGING_CATEGORY(lcNm, "astrad.wifi.nm")

namespace astrad::network {

namespace {
const QString kService = QStringLiteral("org.freedesktop.NetworkManager");
const QString kManagerPath = QStringLiteral("/org/freedesktop/NetworkManager");
const QString kManager = QStringLiteral("org.freedesktop.NetworkManager");
const QString kDevice = QStringLiteral("org.freedesktop.NetworkManager.Device");
const QString kWireless = QStringLiteral("org.freedesktop.NetworkManager.Device.Wireless");
const QString kAp = QStringLiteral("org.freedesktop.NetworkManager.AccessPoint");
const QString kSettingsPath = QStringLiteral("/org/freedesktop/NetworkManager/Settings");
const QString kSettings = QStringLiteral("org.freedesktop.NetworkManager.Settings");
const QString kConnection = QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection");
const QString kProps = QStringLiteral("org.freedesktop.DBus.Properties");

constexpr int kDeviceTypeWifi = 2;

std::unique_ptr<QDBusInterface> iface(const QString &path, const QString &interface)
{
    auto i = std::make_unique<QDBusInterface>(kService, path, interface, QDBusConnection::systemBus());
    i->setTimeout(8000);
    return i;
}

QString security(const QVariantMap &ap)
{
    const uint flags = ap.value(QStringLiteral("Flags")).toUInt();
    const uint wpa = ap.value(QStringLiteral("WpaFlags")).toUInt();
    const uint rsn = ap.value(QStringLiteral("RsnFlags")).toUInt();
    if ((wpa | rsn) & 0x200)            // key management 802.1X
        return QStringLiteral("8021x");
    if (wpa | rsn)
        return QStringLiteral("psk");
    return flags & 0x1 ? QStringLiteral("wep") : QStringLiteral("open");
}
} // namespace

NMWifi::NMWifi(QObject *parent)
    : WifiBackend(parent)
{
    registerDBusTypes();
    m_watcher = new DBusWatcher(kService, [this] { refresh(); }, this);
    refresh();
}

bool NMWifi::daemonPresent()
{
    return serviceRegistered(kService);
}

QVariantMap NMWifi::getAll(const QString &path, const QString &interface) const
{
    QDBusInterface p(kService, path, kProps, QDBusConnection::systemBus());
    p.setTimeout(8000);
    const QDBusReply<QVariantMap> r = p.call(QStringLiteral("GetAll"), interface);
    return r.isValid() ? r.value() : QVariantMap();
}

QString NMWifi::connectionFor(const QString &ssid) const
{
    return m_profiles.value(ssid);
}

void NMWifi::refresh()
{
    if (!serviceRegistered(kService)) {
        m_device.clear();
        m_networks = {};
        m_known = {};
        m_apList = {};
        m_state = QStringLiteral("disconnected");
        m_powered = false;
        Q_EMIT changed();
        return;
    }
    const QVariantMap manager = getAll(kManagerPath, kManager);
    m_powered = manager.value(QStringLiteral("WirelessEnabled")).toBool();

    // The Wi-Fi device.
    m_device.clear();
    auto nm = iface(kManagerPath, kManager);
    const QDBusReply<QList<QDBusObjectPath>> devices = nm->call(QStringLiteral("GetDevices"));
    if (devices.isValid())
        for (const QDBusObjectPath &d : devices.value())
            if (getAll(d.path(), kDevice).value(QStringLiteral("DeviceType")).toUInt() == kDeviceTypeWifi) {
                m_device = d.path();
                break;
            }
    if (m_device.isEmpty()) {
        m_networks = {};
        m_apList = {};
        Q_EMIT changed();
        return;
    }
    const QVariantMap dev = getAll(m_device, kDevice);
    const uint st = dev.value(QStringLiteral("State")).toUInt();
    m_state = st == 100 ? QStringLiteral("connected") : (st >= 40 && st < 100) ? QStringLiteral("connecting") : QStringLiteral("disconnected");
    const QVariantMap wireless = getAll(m_device, kWireless);
    m_mac = wireless.value(QStringLiteral("HwAddress")).toString();
    const QString activeAp = wireless.value(QStringLiteral("ActiveAccessPoint")).value<QDBusObjectPath>().path();

    // Saved Wi-Fi profiles.
    m_profiles.clear();
    m_known = {};
    auto settings = iface(kSettingsPath, kSettings);
    const QDBusReply<QList<QDBusObjectPath>> list = settings->call(QStringLiteral("ListConnections"));
    if (list.isValid()) {
        for (const QDBusObjectPath &c : list.value()) {
            auto conn = iface(c.path(), kConnection);
            const QDBusReply<InterfaceMap> r = conn->call(QStringLiteral("GetSettings"));
            if (!r.isValid())
                continue;
            const InterfaceMap s = r.value();
            if (s.value(QStringLiteral("connection")).value(QStringLiteral("type")).toString() != QLatin1String("802-11-wireless"))
                continue;
            if (s.value(QStringLiteral("802-11-wireless")).value(QStringLiteral("mode")).toString() == QLatin1String("ap"))
                continue;   // the hotspot's own profile
            const QString ssid = QString::fromUtf8(s.value(QStringLiteral("802-11-wireless")).value(QStringLiteral("ssid")).toByteArray());
            if (ssid.isEmpty())
                continue;
            m_profiles.insert(ssid, c.path());
            const QString key = s.value(QStringLiteral("802-11-wireless-security")).value(QStringLiteral("key-mgmt")).toString();
            m_known.append(QJsonObject{{QStringLiteral("ssid"), ssid}, {QStringLiteral("security"), key.isEmpty() ? QStringLiteral("open") : QStringLiteral("psk")}});
        }
    }

    // The access points, one entry per network (the strongest).
    QHash<QString, QJsonObject> best;
    QJsonArray macs;
    auto w = iface(m_device, kWireless);
    const QDBusReply<QList<QDBusObjectPath>> aps = w->call(QStringLiteral("GetAllAccessPoints"));
    if (aps.isValid()) {
        for (const QDBusObjectPath &a : aps.value()) {
            const QVariantMap ap = getAll(a.path(), kAp);
            const QString ssid = QString::fromUtf8(ap.value(QStringLiteral("Ssid")).toByteArray());
            const int strength = ap.value(QStringLiteral("Strength")).toInt();
            macs.append(QJsonObject{{QStringLiteral("macAddress"), ap.value(QStringLiteral("HwAddress")).toString()},
                                    {QStringLiteral("signalStrength"), strength / 2 - 100}});
            if (ssid.isEmpty())
                continue;
            const bool connected = a.path() == activeAp && m_state != QLatin1String("disconnected");
            QJsonObject n{{QStringLiteral("id"), ssid}, {QStringLiteral("ssid"), ssid}, {QStringLiteral("security"), security(ap)},
                          {QStringLiteral("strength"), strength}, {QStringLiteral("known"), m_profiles.contains(ssid)},
                          {QStringLiteral("connected"), connected}};
            const auto it = best.find(ssid);
            if (it == best.end() || connected || (!it->value(QStringLiteral("connected")).toBool() && strength > it->value(QStringLiteral("strength")).toInt()))
                best.insert(ssid, n);
        }
    }
    QList<QJsonObject> sorted = best.values();
    std::sort(sorted.begin(), sorted.end(), [](const QJsonObject &a, const QJsonObject &b) {
        if (a.value(QStringLiteral("connected")).toBool() != b.value(QStringLiteral("connected")).toBool())
            return a.value(QStringLiteral("connected")).toBool();
        return a.value(QStringLiteral("strength")).toInt() > b.value(QStringLiteral("strength")).toInt();
    });
    m_networks = {};
    for (const QJsonObject &o : sorted)
        m_networks.append(o);
    m_apList = macs;

    // Is the hotspot still up?
    if (!m_hotspot.isEmpty()) {
        const QVariantMap mgr = getAll(kManagerPath, kManager);
        QSet<QString> active;
        for (const QVariant &v : mgr.value(QStringLiteral("ActiveConnections")).toList())
            active.insert(v.value<QDBusObjectPath>().path());
        if (!active.contains(m_hotspot))
            m_hotspot.clear();
    }
    Q_EMIT changed();
}

void NMWifi::setPowered(bool on)
{
    dbusSetProperty(kService, kManagerPath, kManager, QStringLiteral("WirelessEnabled"), on, this, [this](const QString &) { m_watcher->poke(); });
}

void NMWifi::scan()
{
    if (m_device.isEmpty())
        return;
    m_scanning = true;
    Q_EMIT changed();
    dbusCall(kService, m_device, kWireless, QStringLiteral("RequestScan"), {QVariant::fromValue(QVariantMap())}, this,
             [this](const QString &, const QDBusMessage &) {
                 QTimer::singleShot(3500, this, [this] { m_scanning = false; m_watcher->poke(); });
             });
}

void NMWifi::connectTo(const QString &id, const QString &passphrase, Done done)
{
    if (m_device.isEmpty()) {
        done(QStringLiteral("no Wi-Fi device"));
        return;
    }
    const QString profile = connectionFor(id);
    auto finished = [this, done](const QString &error, const QDBusMessage &) {
        if (!error.isEmpty())
            qCWarning(lcNm) << "connect failed:" << error;
        done(error);
        m_watcher->poke();
    };
    if (profile.isEmpty() || !passphrase.isEmpty()) {
        // A new network (or a new passphrase): a profile is made and activated in one call.
        InterfaceMap settings;
        settings.insert(QStringLiteral("connection"), {{QStringLiteral("type"), QStringLiteral("802-11-wireless")}, {QStringLiteral("id"), id}});
        settings.insert(QStringLiteral("802-11-wireless"), {{QStringLiteral("ssid"), id.toUtf8()}, {QStringLiteral("mode"), QStringLiteral("infrastructure")}});
        if (!passphrase.isEmpty())
            settings.insert(QStringLiteral("802-11-wireless-security"), {{QStringLiteral("key-mgmt"), QStringLiteral("wpa-psk")}, {QStringLiteral("psk"), passphrase}});
        if (!profile.isEmpty()) {
            auto old = iface(profile, kConnection);
            old->call(QStringLiteral("Delete"));
        }
        dbusCall(kService, kManagerPath, kManager, QStringLiteral("AddAndActivateConnection"),
                 {QVariant::fromValue(settings), QVariant::fromValue(QDBusObjectPath(m_device)), QVariant::fromValue(QDBusObjectPath(QStringLiteral("/")))},
                 this, finished);
        return;
    }
    dbusCall(kService, kManagerPath, kManager, QStringLiteral("ActivateConnection"),
             {QVariant::fromValue(QDBusObjectPath(profile)), QVariant::fromValue(QDBusObjectPath(m_device)), QVariant::fromValue(QDBusObjectPath(QStringLiteral("/")))},
             this, finished);
}

void NMWifi::disconnectCurrent()
{
    if (m_device.isEmpty())
        return;
    dbusCall(kService, m_device, kDevice, QStringLiteral("Disconnect"), {}, this, [this](const QString &, const QDBusMessage &) { m_watcher->poke(); });
}

void NMWifi::forget(const QString &ssid)
{
    const QString profile = connectionFor(ssid);
    if (profile.isEmpty())
        return;
    dbusCall(kService, profile, kConnection, QStringLiteral("Delete"), {}, this, [this](const QString &, const QDBusMessage &) { m_watcher->poke(); });
}

// Personal Hotspot: an access point that shares the wired or mobile connection (NetworkManager's "shared" IPv4).
void NMWifi::setHotspot(bool on, const QString &ssid, const QString &passphrase, Done done)
{
    if (m_device.isEmpty()) {
        done(QStringLiteral("no Wi-Fi device"));
        return;
    }
    if (!on) {
        if (!m_hotspot.isEmpty())
            dbusCall(kService, kManagerPath, kManager, QStringLiteral("DeactivateConnection"), {QVariant::fromValue(QDBusObjectPath(m_hotspot))}, this,
                     [this, done](const QString &error, const QDBusMessage &) { m_hotspot.clear(); done(error); m_watcher->poke(); });
        else
            done(QString());
        return;
    }
    InterfaceMap settings;
    settings.insert(QStringLiteral("connection"), {{QStringLiteral("type"), QStringLiteral("802-11-wireless")}, {QStringLiteral("id"), QStringLiteral("astraOS Hotspot")},
                                                   {QStringLiteral("autoconnect"), false}});
    settings.insert(QStringLiteral("802-11-wireless"), {{QStringLiteral("ssid"), ssid.toUtf8()}, {QStringLiteral("mode"), QStringLiteral("ap")}, {QStringLiteral("band"), QStringLiteral("bg")}});
    settings.insert(QStringLiteral("802-11-wireless-security"), {{QStringLiteral("key-mgmt"), QStringLiteral("wpa-psk")}, {QStringLiteral("psk"), passphrase}});
    settings.insert(QStringLiteral("ipv4"), {{QStringLiteral("method"), QStringLiteral("shared")}});
    settings.insert(QStringLiteral("ipv6"), {{QStringLiteral("method"), QStringLiteral("ignore")}});
    dbusCall(kService, kManagerPath, kManager, QStringLiteral("AddAndActivateConnection"),
             {QVariant::fromValue(settings), QVariant::fromValue(QDBusObjectPath(m_device)), QVariant::fromValue(QDBusObjectPath(QStringLiteral("/")))}, this,
             [this, done](const QString &error, const QDBusMessage &reply) {
                 if (error.isEmpty() && reply.arguments().size() >= 2)
                     m_hotspot = reply.arguments().at(1).value<QDBusObjectPath>().path();
                 done(error);
                 m_watcher->poke();
             });
}

} // namespace astrad::network
