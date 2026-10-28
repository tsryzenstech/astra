// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QMap>
#include <QTimer>
#include <QVariantMap>

#include <functional>

namespace astrad::network {

using InterfaceMap = QMap<QString, QVariantMap>;
using ManagedObjects = QMap<QDBusObjectPath, InterfaceMap>;

inline void registerDBusTypes()
{
    static bool done = false;
    if (done)
        return;
    done = true;
    qDBusRegisterMetaType<InterfaceMap>();
    qDBusRegisterMetaType<ManagedObjects>();
}

inline bool serviceRegistered(const QString &service)
{
    QDBusConnection bus = QDBusConnection::systemBus();
    return bus.isConnected() && bus.interface() && bus.interface()->isServiceRegistered(service).value();
}

// Asynchronous method call with a reply callback (error message, reply).
inline void dbusCall(const QString &service, const QString &path, const QString &interface, const QString &method,
                     const QVariantList &args, QObject *context,
                     std::function<void(const QString &error, const QDBusMessage &reply)> done)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, interface, method);
    msg.setArguments(args);
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(msg, 120000), context);
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, context, [watcher, done] {
        const QDBusMessage reply = watcher->reply();
        watcher->deleteLater();
        if (done)
            done(reply.type() == QDBusMessage::ErrorMessage ? reply.errorMessage() : QString(), reply);
    });
}

inline void dbusSetProperty(const QString &service, const QString &path, const QString &interface,
                            const QString &property, const QVariant &value, QObject *context,
                            std::function<void(const QString &error)> done = {})
{
    dbusCall(service, path, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Set"),
             {interface, property, QVariant::fromValue(QDBusVariant(value))}, context,
             [done](const QString &error, const QDBusMessage &) {
                 if (done)
                     done(error);
             });
}

// Fetches all objects of an ObjectManager.
inline void dbusManagedObjects(const QString &service, const QString &root, QObject *context,
                               std::function<void(const ManagedObjects &)> done)
{
    dbusCall(service, root, QStringLiteral("org.freedesktop.DBus.ObjectManager"), QStringLiteral("GetManagedObjects"), {},
             context, [done](const QString &error, const QDBusMessage &reply) {
                 ManagedObjects objects;
                 if (error.isEmpty() && !reply.arguments().isEmpty())
                     reply.arguments().at(0).value<QDBusArgument>() >> objects;
                 done(objects);
             });
}

// Re-reads a daemon's state shortly after any of its property or object
// signals (debounced), and whenever the daemon (re)appears on the bus.
class DBusWatcher : public QObject
{
    Q_OBJECT
public:
    DBusWatcher(const QString &service, std::function<void()> refresh, QObject *parent)
        : QObject(parent)
        , m_refresh(std::move(refresh))
        , m_services(service, QDBusConnection::systemBus(),
                     QDBusServiceWatcher::WatchForRegistration | QDBusServiceWatcher::WatchForUnregistration)
    {
        m_timer.setSingleShot(true);
        m_timer.setInterval(150);
        connect(&m_timer, &QTimer::timeout, this, [this] { m_refresh(); });
        connect(&m_services, &QDBusServiceWatcher::serviceRegistered, this, &DBusWatcher::poke);
        connect(&m_services, &QDBusServiceWatcher::serviceUnregistered, this, &DBusWatcher::poke);
        QDBusConnection bus = QDBusConnection::systemBus();
        bus.connect(service, QString(), QStringLiteral("org.freedesktop.DBus.Properties"),
                    QStringLiteral("PropertiesChanged"), this, SLOT(onSignal(QDBusMessage)));
        bus.connect(service, QString(), QStringLiteral("org.freedesktop.DBus.ObjectManager"),
                    QStringLiteral("InterfacesAdded"), this, SLOT(onSignal(QDBusMessage)));
        bus.connect(service, QString(), QStringLiteral("org.freedesktop.DBus.ObjectManager"),
                    QStringLiteral("InterfacesRemoved"), this, SLOT(onSignal(QDBusMessage)));
    }

public Q_SLOTS:
    void poke() { m_timer.start(); }
    void onSignal(const QDBusMessage &) { poke(); }

private:
    std::function<void()> m_refresh;
    QDBusServiceWatcher m_services;
    QTimer m_timer;
};

} // namespace astrad::network
