// SPDX-License-Identifier: Apache-2.0
// Wi-Fi through iwd (https://iwd.wiki.kernel.org/), D-Bus API net.connman.iwd.
#include "iwd.h"

#include <QDBusContext>
#include <QLoggingCategory>

Q_LOGGING_CATEGORY(lcIwd, "astrad.wifi")

namespace astrad::network {

namespace {
const QString kService = QStringLiteral("net.connman.iwd");
const QString kStation = QStringLiteral("net.connman.iwd.Station");
const QString kDevice = QStringLiteral("net.connman.iwd.Device");
const QString kNetwork = QStringLiteral("net.connman.iwd.Network");
const QString kKnown = QStringLiteral("net.connman.iwd.KnownNetwork");
const QString kAgentPath = QStringLiteral("/org/astra/iwd/agent");

// iwd reports signal strength in 100 * dBm.
int strengthPercent(int centiDbm)
{
    const double dbm = centiDbm / 100.0;
    return qBound(0, int((dbm + 100.0) * 2.0), 100);
}
} // namespace

IwdAgent::IwdAgent(IwdWifi *owner)
    : QObject(owner)
    , m_owner(owner)
{
}

QString IwdAgent::RequestPassphrase(const QDBusObjectPath &network)
{
    const QString pass = m_owner->takePassphrase(network.path());
    if (pass.isEmpty())
        sendErrorReply(QStringLiteral("net.connman.iwd.Agent.Error.Canceled"), QStringLiteral("no passphrase"));
    return pass;
}

QString IwdAgent::RequestPrivateKeyPassphrase(const QDBusObjectPath &network)
{
    return RequestPassphrase(network);
}

void IwdAgent::Cancel(const QString &reason)
{
    qCInfo(lcIwd) << "agent request cancelled:" << reason;
}

IwdWifi::IwdWifi(QObject *parent)
    : WifiBackend(parent)
    , m_agent(new IwdAgent(this))
{
    registerDBusTypes();
    QDBusConnection::systemBus().registerObject(kAgentPath, m_agent, QDBusConnection::ExportScriptableSlots);
    m_watcher = new DBusWatcher(kService, [this] { refresh(); }, this);
    refresh();
}

QString IwdWifi::takePassphrase(const QString &networkPath)
{
    return m_passphrases.take(networkPath);
}

void IwdWifi::refresh()
{
    if (!serviceRegistered(kService)) {
        m_objects.clear();
        m_agentRegistered = false;
        Q_EMIT changed();
        return;
    }
    if (!m_agentRegistered) {
        dbusCall(kService, QStringLiteral("/net/connman/iwd"), QStringLiteral("net.connman.iwd.AgentManager"),
                 QStringLiteral("RegisterAgent"), {QVariant::fromValue(QDBusObjectPath(kAgentPath))}, this,
                 [this](const QString &error, const QDBusMessage &) {
                     m_agentRegistered = error.isEmpty();
                     if (!error.isEmpty())
                         qCWarning(lcIwd) << "cannot register agent:" << error;
                 });
    }
    dbusManagedObjects(kService, QStringLiteral("/"), this, [this](const ManagedObjects &objects) {
        m_objects = objects;
        m_station.clear();
        m_device.clear();
        for (auto it = objects.cbegin(); it != objects.cend(); ++it) {
            if (it.value().contains(kStation) && m_station.isEmpty())
                m_station = it.key().path();
            if (it.value().contains(kDevice) && m_device.isEmpty())
                m_device = it.key().path();
        }
        if (m_station.isEmpty()) {
            m_ordered.clear();
            Q_EMIT changed();
            return;
        }
        dbusCall(kService, m_station, kStation, QStringLiteral("GetOrderedNetworks"), {}, this,
                 [this](const QString &error, const QDBusMessage &reply) {
                     m_ordered.clear();
                     if (error.isEmpty() && !reply.arguments().isEmpty()) {
                         const QDBusArgument arg = reply.arguments().at(0).value<QDBusArgument>();
                         arg.beginArray();
                         while (!arg.atEnd()) {
                             QDBusObjectPath path;
                             qint16 strength = 0;
                             arg.beginStructure();
                             arg >> path >> strength;
                             arg.endStructure();
                             m_ordered.append({path.path(), strengthPercent(strength)});
                         }
                         arg.endArray();
                     }
                     Q_EMIT changed();
                 });
    });
}

QVariantMap IwdWifi::props(const QString &path, const QString &iface) const
{
    return m_objects.value(QDBusObjectPath(path)).value(iface);
}

bool IwdWifi::available() const
{
    return !m_device.isEmpty();
}

bool IwdWifi::powered() const
{
    return props(m_device, kDevice).value(QStringLiteral("Powered")).toBool();
}

void IwdWifi::setPowered(bool on)
{
    if (m_device.isEmpty())
        return;
    dbusSetProperty(kService, m_device, kDevice, QStringLiteral("Powered"), on, this,
                    [this](const QString &) { m_watcher->poke(); });
}

bool IwdWifi::scanning() const
{
    return props(m_station, kStation).value(QStringLiteral("Scanning")).toBool();
}

void IwdWifi::scan()
{
    if (!m_station.isEmpty())
        dbusCall(kService, m_station, kStation, QStringLiteral("Scan"), {}, this, {});
}

QString IwdWifi::state() const
{
    const QString s = props(m_station, kStation).value(QStringLiteral("State")).toString();
    if (s == QLatin1String("connected") || s == QLatin1String("roaming"))
        return QStringLiteral("connected");
    if (s == QLatin1String("connecting"))
        return QStringLiteral("connecting");
    return QStringLiteral("disconnected");
}

QJsonArray IwdWifi::networks() const
{
    QJsonArray out;
    for (const auto &[path, strength] : m_ordered) {
        const QVariantMap n = props(path, kNetwork);
        if (n.isEmpty())
            continue;
        const QString known = n.value(QStringLiteral("KnownNetwork")).value<QDBusObjectPath>().path();
        out.append(QJsonObject{
            {QStringLiteral("id"), path},
            {QStringLiteral("ssid"), n.value(QStringLiteral("Name")).toString()},
            {QStringLiteral("security"), n.value(QStringLiteral("Type")).toString()},
            {QStringLiteral("strength"), strength},
            {QStringLiteral("known"), !known.isEmpty() && known != QLatin1String("/")},
            {QStringLiteral("connected"), n.value(QStringLiteral("Connected")).toBool()},
        });
    }
    return out;
}

QJsonArray IwdWifi::knownNetworks() const
{
    QJsonArray out;
    for (auto it = m_objects.cbegin(); it != m_objects.cend(); ++it)
        if (it.value().contains(kKnown))
            out.append(QJsonObject{{QStringLiteral("ssid"), it.value().value(kKnown).value(QStringLiteral("Name")).toString()},
                                   {QStringLiteral("security"), it.value().value(kKnown).value(QStringLiteral("Type")).toString()}});
    return out;
}

void IwdWifi::connectTo(const QString &id, const QString &passphrase, Done done)
{
    if (!passphrase.isEmpty())
        m_passphrases.insert(id, passphrase);
    dbusCall(kService, id, kNetwork, QStringLiteral("Connect"), {}, this,
             [this, id, done](const QString &error, const QDBusMessage &) {
                 m_passphrases.remove(id);
                 m_watcher->poke();
                 done(error);
             });
}

void IwdWifi::disconnectCurrent()
{
    if (!m_station.isEmpty())
        dbusCall(kService, m_station, kStation, QStringLiteral("Disconnect"), {}, this,
                 [this](const QString &, const QDBusMessage &) { m_watcher->poke(); });
}

void IwdWifi::forget(const QString &ssid)
{
    for (auto it = m_objects.cbegin(); it != m_objects.cend(); ++it) {
        if (it.value().contains(kKnown) && it.value().value(kKnown).value(QStringLiteral("Name")).toString() == ssid) {
            dbusCall(kService, it.key().path(), kKnown, QStringLiteral("Forget"), {}, this,
                     [this](const QString &, const QDBusMessage &) { m_watcher->poke(); });
            return;
        }
    }
}

// Every BSS of the networks in range, with the network's signal.
QJsonArray IwdWifi::accessPoints() const
{
    QJsonArray out;
    for (const auto &[path, percent] : m_ordered) {
        const QVariant ess = props(path, QStringLiteral("net.connman.iwd.Network")).value(QStringLiteral("ExtendedServiceSet"));
        const QList<QDBusObjectPath> bsses = qdbus_cast<QList<QDBusObjectPath>>(ess);
        for (const QDBusObjectPath &bss : bsses) {
            const QString mac = props(bss.path(), QStringLiteral("net.connman.iwd.BasicServiceSet")).value(QStringLiteral("Address")).toString();
            if (!mac.isEmpty())
                out.append(QJsonObject{{QStringLiteral("macAddress"), mac.toLower()},
                                       {QStringLiteral("signalStrength"), int(percent / 2.0 - 100)}});
        }
    }
    return out;
}

bool IwdWifi::hotspotSupported() const
{
    return available();
}

bool IwdWifi::hotspotActive() const
{
    return props(m_device, kDevice).value(QStringLiteral("Mode")).toString() == QLatin1String("ap")
        && props(m_device, QStringLiteral("net.connman.iwd.AccessPoint")).value(QStringLiteral("Started")).toBool();
}

// iwd runs the access point and its DHCP server itself
// ([General] EnableNetworkConfiguration=true in /etc/iwd/main.conf).
void IwdWifi::setHotspot(bool on, const QString &ssid, const QString &passphrase, Done done)
{
    if (m_device.isEmpty()) {
        done(QStringLiteral("no Wi-Fi"));
        return;
    }
    const QString device = m_device;
    const QString ap = QStringLiteral("net.connman.iwd.AccessPoint");
    if (!on) {
        dbusCall(kService, device, ap, QStringLiteral("Stop"), {}, this,
                 [this, device, done](const QString &, const QDBusMessage &) {
                     dbusSetProperty(kService, device, kDevice, QStringLiteral("Mode"), QStringLiteral("station"), this,
                                     [this, done](const QString &error) {
                                         refresh();
                                         done(error);
                                     });
                 });
        return;
    }
    dbusSetProperty(kService, device, kDevice, QStringLiteral("Mode"), QStringLiteral("ap"), this,
                    [this, device, ap, ssid, passphrase, done](const QString &error) {
                        if (!error.isEmpty()) {
                            done(error);
                            return;
                        }
                        dbusCall(kService, device, ap, QStringLiteral("Start"), {ssid, passphrase}, this,
                                 [this, done](const QString &startError, const QDBusMessage &) {
                                     refresh();
                                     done(startError);
                                 });
                    });
}

} // namespace astrad::network
