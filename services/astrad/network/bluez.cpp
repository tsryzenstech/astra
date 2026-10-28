// SPDX-License-Identifier: Apache-2.0
// Bluetooth through BlueZ (bluetoothd), D-Bus API org.bluez.
#include "bluez.h"

#include <QLoggingCategory>

Q_LOGGING_CATEGORY(lcBt, "astrad.bluetooth")

namespace astrad::network {

namespace {
const QString kService = QStringLiteral("org.bluez");
const QString kAdapter = QStringLiteral("org.bluez.Adapter1");
const QString kDevice = QStringLiteral("org.bluez.Device1");
const QString kAgentPath = QStringLiteral("/org/astra/bluez/agent");
} // namespace

BluezBluetooth::BluezBluetooth(QObject *parent)
    : BluetoothBackend(parent)
{
    registerDBusTypes();
    QDBusConnection::systemBus().registerObject(kAgentPath, new BluezAgent(this), QDBusConnection::ExportScriptableSlots);
    m_watcher = new DBusWatcher(kService, [this] { refresh(); }, this);
    refresh();
}

void BluezBluetooth::refresh()
{
    if (!serviceRegistered(kService)) {
        m_objects.clear();
        m_adapter.clear();
        m_agentRegistered = false;
        Q_EMIT changed();
        return;
    }
    if (!m_agentRegistered) {
        m_agentRegistered = true;
        const QVariant agent = QVariant::fromValue(QDBusObjectPath(kAgentPath));
        dbusCall(kService, QStringLiteral("/org/bluez"), QStringLiteral("org.bluez.AgentManager1"),
                 QStringLiteral("RegisterAgent"), {agent, QStringLiteral("NoInputNoOutput")}, this,
                 [this, agent](const QString &error, const QDBusMessage &) {
                     if (!error.isEmpty()) {
                         qCWarning(lcBt) << "cannot register agent:" << error;
                         return;
                     }
                     dbusCall(kService, QStringLiteral("/org/bluez"), QStringLiteral("org.bluez.AgentManager1"),
                              QStringLiteral("RequestDefaultAgent"), {agent}, this, {});
                 });
    }
    dbusManagedObjects(kService, QStringLiteral("/"), this, [this](const ManagedObjects &objects) {
        m_objects = objects;
        m_adapter.clear();
        for (auto it = objects.cbegin(); it != objects.cend() && m_adapter.isEmpty(); ++it)
            if (it.value().contains(kAdapter))
                m_adapter = it.key().path();
        Q_EMIT changed();
    });
}

QVariantMap BluezBluetooth::adapterProps() const
{
    return m_objects.value(QDBusObjectPath(m_adapter)).value(kAdapter);
}

bool BluezBluetooth::powered() const
{
    return adapterProps().value(QStringLiteral("Powered")).toBool();
}

void BluezBluetooth::setPowered(bool on)
{
    if (!m_adapter.isEmpty())
        dbusSetProperty(kService, m_adapter, kAdapter, QStringLiteral("Powered"), on, this,
                        [this](const QString &) { m_watcher->poke(); });
}

QString BluezBluetooth::name() const
{
    return adapterProps().value(QStringLiteral("Alias")).toString();
}

void BluezBluetooth::setName(const QString &name)
{
    if (!m_adapter.isEmpty())
        dbusSetProperty(kService, m_adapter, kAdapter, QStringLiteral("Alias"), name, this,
                        [this](const QString &) { m_watcher->poke(); });
}

bool BluezBluetooth::discovering() const
{
    return adapterProps().value(QStringLiteral("Discovering")).toBool();
}

void BluezBluetooth::setDiscovering(bool on)
{
    if (!m_adapter.isEmpty())
        dbusCall(kService, m_adapter, kAdapter, on ? QStringLiteral("StartDiscovery") : QStringLiteral("StopDiscovery"),
                 {}, this, [this](const QString &, const QDBusMessage &) { m_watcher->poke(); });
}

QJsonArray BluezBluetooth::devices() const
{
    QJsonArray out;
    for (auto it = m_objects.cbegin(); it != m_objects.cend(); ++it) {
        if (!it.value().contains(kDevice))
            continue;
        const QVariantMap d = it.value().value(kDevice);
        out.append(QJsonObject{
            {QStringLiteral("address"), d.value(QStringLiteral("Address")).toString()},
            {QStringLiteral("name"), d.value(QStringLiteral("Alias"), d.value(QStringLiteral("Address"))).toString()},
            {QStringLiteral("icon"), d.value(QStringLiteral("Icon")).toString()},
            {QStringLiteral("paired"), d.value(QStringLiteral("Paired")).toBool()},
            {QStringLiteral("connected"), d.value(QStringLiteral("Connected")).toBool()},
            {QStringLiteral("rssi"), d.value(QStringLiteral("RSSI")).toInt()},
        });
    }
    return out;
}

QString BluezBluetooth::pathOf(const QString &address) const
{
    for (auto it = m_objects.cbegin(); it != m_objects.cend(); ++it)
        if (it.value().value(kDevice).value(QStringLiteral("Address")).toString() == address)
            return it.key().path();
    return {};
}

void BluezBluetooth::pair(const QString &address, Done done)
{
    const QString path = pathOf(address);
    if (path.isEmpty()) {
        done(QStringLiteral("unknown device"));
        return;
    }
    dbusSetProperty(kService, path, kDevice, QStringLiteral("Trusted"), true, this);
    dbusCall(kService, path, kDevice, QStringLiteral("Pair"), {}, this,
             [this, address, done](const QString &error, const QDBusMessage &) {
                 m_watcher->poke();
                 if (error.isEmpty())
                     connectDevice(address, done);
                 else
                     done(error);
             });
}

void BluezBluetooth::connectDevice(const QString &address, Done done)
{
    const QString path = pathOf(address);
    if (path.isEmpty()) {
        done(QStringLiteral("unknown device"));
        return;
    }
    dbusCall(kService, path, kDevice, QStringLiteral("Connect"), {}, this,
             [this, done](const QString &error, const QDBusMessage &) {
                 m_watcher->poke();
                 done(error);
             });
}

void BluezBluetooth::disconnectDevice(const QString &address)
{
    const QString path = pathOf(address);
    if (!path.isEmpty())
        dbusCall(kService, path, kDevice, QStringLiteral("Disconnect"), {}, this,
                 [this](const QString &, const QDBusMessage &) { m_watcher->poke(); });
}

void BluezBluetooth::forget(const QString &address)
{
    const QString path = pathOf(address);
    if (!path.isEmpty() && !m_adapter.isEmpty())
        dbusCall(kService, m_adapter, kAdapter, QStringLiteral("RemoveDevice"), {QVariant::fromValue(QDBusObjectPath(path))},
                 this, [this](const QString &, const QDBusMessage &) { m_watcher->poke(); });
}

} // namespace astrad::network
