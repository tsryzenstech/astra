// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "backends.h"
#include "dbusutil.h"

namespace astrad::network {

// Pairing agent: astraOS pairs without a passkey ("just works"); devices
// that require confirmation are accepted because the user started pairing.
class BluezAgent : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")
public:
    using QObject::QObject;

public Q_SLOTS:
    Q_SCRIPTABLE void Release() {}
    Q_SCRIPTABLE QString RequestPinCode(const QDBusObjectPath &) { return QStringLiteral("0000"); }
    Q_SCRIPTABLE uint RequestPasskey(const QDBusObjectPath &) { return 0; }
    Q_SCRIPTABLE void DisplayPasskey(const QDBusObjectPath &, uint, ushort) {}
    Q_SCRIPTABLE void DisplayPinCode(const QDBusObjectPath &, const QString &) {}
    Q_SCRIPTABLE void RequestConfirmation(const QDBusObjectPath &, uint) {}
    Q_SCRIPTABLE void RequestAuthorization(const QDBusObjectPath &) {}
    Q_SCRIPTABLE void AuthorizeService(const QDBusObjectPath &, const QString &) {}
    Q_SCRIPTABLE void Cancel() {}
};

class BluezBluetooth : public BluetoothBackend
{
    Q_OBJECT
public:
    explicit BluezBluetooth(QObject *parent);

    QString kind() const override { return QStringLiteral("bluez"); }
    bool available() const override { return !m_adapter.isEmpty(); }
    bool powered() const override;
    void setPowered(bool on) override;
    QString name() const override;
    QString address() const override;
    void setName(const QString &name) override;
    bool discovering() const override;
    void setDiscovering(bool on) override;
    QJsonArray devices() const override;
    void pair(const QString &address, Done done) override;
    void connectDevice(const QString &address, Done done) override;
    void disconnectDevice(const QString &address) override;
    void forget(const QString &address) override;

private:
    void refresh();
    QString pathOf(const QString &address) const;
    QVariantMap adapterProps() const;

    DBusWatcher *m_watcher;
    bool m_agentRegistered = false;
    ManagedObjects m_objects;
    QString m_adapter;
};

} // namespace astrad::network
