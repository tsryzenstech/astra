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

} // namespace astrad::network
