// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "backends.h"
#include "dbusutil.h"

#include <QDBusContext>
#include <QHash>

namespace astrad::network {

class IwdWifi;

// iwd calls back into this agent for passphrases of protected networks.
class IwdAgent : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "net.connman.iwd.Agent")
public:
    explicit IwdAgent(IwdWifi *owner);

public Q_SLOTS:
    Q_SCRIPTABLE void Release() {}
    Q_SCRIPTABLE QString RequestPassphrase(const QDBusObjectPath &network);
    Q_SCRIPTABLE QString RequestPrivateKeyPassphrase(const QDBusObjectPath &network);
    Q_SCRIPTABLE void Cancel(const QString &reason);

private:
    IwdWifi *m_owner;
};

class IwdWifi : public WifiBackend
{
    Q_OBJECT
public:
    explicit IwdWifi(QObject *parent);

    QString kind() const override { return QStringLiteral("iwd"); }
    bool available() const override;
    bool powered() const override;
    void setPowered(bool on) override;
    bool scanning() const override;
    void scan() override;
    QJsonArray networks() const override;
    QString state() const override;
    void connectTo(const QString &id, const QString &passphrase, Done done) override;
    void disconnectCurrent() override;
    void forget(const QString &ssid) override;
    QJsonArray knownNetworks() const override;
    QJsonArray accessPoints() const override;
    QString address() const override;
    bool hotspotSupported() const override;
    bool hotspotActive() const override;
    void setHotspot(bool on, const QString &ssid, const QString &passphrase, Done done) override;

    QString takePassphrase(const QString &networkPath);

private:
    void refresh();
    QVariantMap props(const QString &path, const QString &iface) const;

    IwdAgent *m_agent;
    DBusWatcher *m_watcher;
    bool m_agentRegistered = false;
    ManagedObjects m_objects;
    QString m_station;
    QString m_device;
    QList<std::pair<QString, int>> m_ordered; // network path, strength %
    QHash<QString, QString> m_passphrases;
};

} // namespace astrad::network
