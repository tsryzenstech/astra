// SPDX-License-Identifier: Apache-2.0
// Cellular data, voice calls and SMS through ModemManager
// (org.freedesktop.ModemManager1). IP settings of the data bearer are applied
// with the system "ip" tool and DNS servers written to /run/resolv.conf.
#include "modemmanager.h"

#include <QDateTime>
#include <QFile>
#include <QLoggingCategory>
#include <QProcess>

Q_LOGGING_CATEGORY(lcMm, "astrad.cellular")

namespace astrad::network {

namespace {
const QString kService = QStringLiteral("org.freedesktop.ModemManager1");
const QString kRoot = QStringLiteral("/org/freedesktop/ModemManager1");
const QString kModem = QStringLiteral("org.freedesktop.ModemManager1.Modem");
const QString k3gpp = QStringLiteral("org.freedesktop.ModemManager1.Modem.Modem3gpp");
const QString kSimple = QStringLiteral("org.freedesktop.ModemManager1.Modem.Simple");
const QString kVoice = QStringLiteral("org.freedesktop.ModemManager1.Modem.Voice");
const QString kMessaging = QStringLiteral("org.freedesktop.ModemManager1.Modem.Messaging");
const QString kCall = QStringLiteral("org.freedesktop.ModemManager1.Call");
const QString kBearer = QStringLiteral("org.freedesktop.ModemManager1.Bearer");
const QString kSms = QStringLiteral("org.freedesktop.ModemManager1.Sms");

constexpr int kStateRegistered = 8;
constexpr int kStateConnected = 11;
constexpr int kStateDisabled = 3;

// MMModemAccessTechnology bits -> label
QString technology(uint bits)
{
    if (bits & (1u << 15))
        return QStringLiteral("5G");
    if (bits & (1u << 14))
        return QStringLiteral("LTE");
    if (bits & ((1u << 5) | (1u << 6) | (1u << 7) | (1u << 8) | (1u << 9)))
        return QStringLiteral("3G");
    if (bits & ((1u << 1) | (1u << 2) | (1u << 3) | (1u << 4)))
        return QStringLiteral("2G");
    return {};
}

void run(const QStringList &argv)
{
    QProcess p;
    p.start(argv.first(), argv.mid(1));
    p.waitForFinished(5000);
}

QString callStateName(int state, int direction)
{
    switch (state) {
    case 1: case 2: return QStringLiteral("dialing");
    case 3: case 6: return direction == 1 ? QStringLiteral("incoming") : QStringLiteral("ringing");
    case 4: return QStringLiteral("active");
    case 5: return QStringLiteral("held");
    default: return QStringLiteral("ended");
    }
}
} // namespace

MMCellular::MMCellular(QObject *parent)
    : CellularBackend(parent)
{
    registerDBusTypes();
    m_watcher = new DBusWatcher(kService, [this] { refresh(); }, this);
    refresh();
}

QVariantMap MMCellular::props(const QString &path, const QString &iface) const
{
    return m_objects.value(QDBusObjectPath(path)).value(iface);
}

void MMCellular::refresh()
{
    if (!serviceRegistered(kService)) {
        m_objects.clear();
        m_modem.clear();
        Q_EMIT changed();
        return;
    }
    dbusManagedObjects(kService, kRoot, this, [this](const ManagedObjects &objects) {
        m_objects = objects;
        m_modem.clear();
        for (auto it = objects.cbegin(); it != objects.cend() && m_modem.isEmpty(); ++it)
            if (it.value().contains(kModem))
                m_modem = it.key().path();
        if (!m_modem.isEmpty() && !m_connectedSignals.contains(m_modem)) {
            m_connectedSignals.insert(m_modem);
            QDBusConnection::systemBus().connect(kService, m_modem, kMessaging, QStringLiteral("Added"), this,
                                                 SLOT(onSmsAdded(QDBusObjectPath, bool)));
            enableModem();
        }
        Q_EMIT changed();
        if (m_modem.isEmpty())
            return;
        // Calls are separate objects listed by the Voice interface.
        dbusCall(kService, m_modem, kVoice, QStringLiteral("ListCalls"), {}, this,
                 [this](const QString &error, const QDBusMessage &reply) {
                     m_calls.clear();
                     if (!error.isEmpty() || reply.arguments().isEmpty()) {
                         Q_EMIT callsChanged();
                         return;
                     }
                     QList<QDBusObjectPath> paths;
                     reply.arguments().at(0).value<QDBusArgument>() >> paths;
                     auto remaining = std::make_shared<int>(int(paths.size()));
                     if (paths.isEmpty())
                         Q_EMIT callsChanged();
                     for (const QDBusObjectPath &p : paths) {
                         dbusCall(kService, p.path(), QStringLiteral("org.freedesktop.DBus.Properties"),
                                  QStringLiteral("GetAll"), {kCall}, this,
                                  [this, p, remaining](const QString &err, const QDBusMessage &r) {
                                      if (err.isEmpty() && !r.arguments().isEmpty()) {
                                          QVariantMap map;
                                          r.arguments().at(0).value<QDBusArgument>() >> map;
                                          m_calls[p].insert(kCall, map);
                                          // Watch each call's state changes too.
                                          if (!m_connectedSignals.contains(p.path()) && (m_connectedSignals.insert(p.path()), true))
                                              QDBusConnection::systemBus().connect(
                                              kService, p.path(), QStringLiteral("org.freedesktop.DBus.Properties"),
                                              QStringLiteral("PropertiesChanged"), m_watcher, SLOT(onSignal(QDBusMessage)));
                                      }
                                      if (--*remaining == 0)
                                          Q_EMIT callsChanged();
                                  });
                     }
                 });
    });
    if (!m_connectedSignals.contains(QStringLiteral("voice"))) {
        m_connectedSignals.insert(QStringLiteral("voice"));
        QDBusConnection::systemBus().connect(kService, QString(), kVoice, QStringLiteral("CallAdded"), m_watcher,
                                             SLOT(onSignal(QDBusMessage)));
        QDBusConnection::systemBus().connect(kService, QString(), kVoice, QStringLiteral("CallDeleted"), m_watcher,
                                             SLOT(onSignal(QDBusMessage)));
    }
}

void MMCellular::enableModem()
{
    if (props(m_modem, kModem).value(QStringLiteral("State")).toInt() <= kStateDisabled)
        dbusCall(kService, m_modem, kModem, QStringLiteral("Enable"), {true}, this,
                 [](const QString &error, const QDBusMessage &) {
                     if (!error.isEmpty())
                         qCWarning(lcMm) << "cannot enable modem:" << error;
                 });
}

QJsonObject MMCellular::state() const
{
    const QVariantMap m = props(m_modem, kModem);
    const QVariantMap g = props(m_modem, k3gpp);
    const QString sim = m.value(QStringLiteral("Sim")).value<QDBusObjectPath>().path();
    const int modemState = m.value(QStringLiteral("State")).toInt();
    uint quality = 0;
    const QDBusArgument sq = m.value(QStringLiteral("SignalQuality")).value<QDBusArgument>();
    if (sq.currentType() == QDBusArgument::StructureType) {
        bool recent = false;
        sq.beginStructure();
        sq >> quality >> recent;
        sq.endStructure();
    }
    const uint registration = g.value(QStringLiteral("RegistrationState")).toUInt();
    return {
        {QStringLiteral("simPresent"), !sim.isEmpty() && sim != QLatin1String("/")},
        {QStringLiteral("operator"), g.value(QStringLiteral("OperatorName")).toString()},
        {QStringLiteral("technology"), technology(m.value(QStringLiteral("AccessTechnologies")).toUInt())},
        {QStringLiteral("signal"), int(quality)},
        {QStringLiteral("registered"), modemState >= kStateRegistered},
        {QStringLiteral("roaming"), registration == 5},
        {QStringLiteral("dataEnabled"), m_dataWanted},
        {QStringLiteral("dataConnected"), modemState == kStateConnected},
        {QStringLiteral("apn"), m_apn},
        {QStringLiteral("allowRoaming"), m_allowRoaming},
    };
}

void MMCellular::setDataEnabled(bool on, Done done)
{
    m_dataWanted = on;
    if (m_modem.isEmpty()) {
        done(QStringLiteral("no modem"));
        return;
    }
    if (!on) {
        dbusCall(kService, m_modem, kSimple, QStringLiteral("Disconnect"), {QVariant::fromValue(QDBusObjectPath("/"))},
                 this, [this, done](const QString &error, const QDBusMessage &) {
                     m_bearer.clear();
                     m_watcher->poke();
                     done(error);
                 });
        return;
    }
    QVariantMap settings{{QStringLiteral("apn"), m_apn}, {QStringLiteral("allow-roaming"), m_allowRoaming}};
    dbusCall(kService, m_modem, kSimple, QStringLiteral("Connect"), {settings}, this,
             [this, done](const QString &error, const QDBusMessage &reply) {
                 if (error.isEmpty() && !reply.arguments().isEmpty()) {
                     m_bearer = reply.arguments().at(0).value<QDBusObjectPath>().path();
                     applyBearer(m_bearer);
                 }
                 m_watcher->poke();
                 done(error);
             });
}

void MMCellular::applyBearer(const QString &bearerPath)
{
    dbusCall(kService, bearerPath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"), {kBearer},
             this, [](const QString &error, const QDBusMessage &reply) {
                 if (!error.isEmpty() || reply.arguments().isEmpty())
                     return;
                 QVariantMap bearer;
                 reply.arguments().at(0).value<QDBusArgument>() >> bearer;
                 const QString iface = bearer.value(QStringLiteral("Interface")).toString();
                 QVariantMap ip4;
                 bearer.value(QStringLiteral("Ip4Config")).value<QDBusArgument>() >> ip4;
                 if (iface.isEmpty())
                     return;
                 run({QStringLiteral("ip"), QStringLiteral("link"), QStringLiteral("set"), iface, QStringLiteral("up")});
                 const uint method = ip4.value(QStringLiteral("method")).toUInt();
                 if (method == 3) { // DHCP
                     run({QStringLiteral("udhcpc"), QStringLiteral("-i"), iface, QStringLiteral("-q"), QStringLiteral("-n")});
                     return;
                 }
                 const QString address = ip4.value(QStringLiteral("address")).toString();
                 const uint prefix = ip4.value(QStringLiteral("prefix")).toUInt();
                 const QString gateway = ip4.value(QStringLiteral("gateway")).toString();
                 if (!address.isEmpty())
                     run({QStringLiteral("ip"), QStringLiteral("addr"), QStringLiteral("add"),
                          QStringLiteral("%1/%2").arg(address).arg(prefix ? prefix : 32), QStringLiteral("dev"), iface});
                 run({QStringLiteral("ip"), QStringLiteral("route"), QStringLiteral("replace"), QStringLiteral("default"),
                      QStringLiteral("dev"), iface});
                 if (!gateway.isEmpty())
                     run({QStringLiteral("ip"), QStringLiteral("route"), QStringLiteral("replace"), QStringLiteral("default"),
                          QStringLiteral("via"), gateway, QStringLiteral("dev"), iface});
                 QFile resolv(QStringLiteral("/run/resolv.conf"));
                 if (resolv.open(QIODevice::WriteOnly)) {
                     for (const char *key : {"dns1", "dns2", "dns3"}) {
                         const QString dns = ip4.value(QLatin1String(key)).toString();
                         if (!dns.isEmpty())
                             resolv.write("nameserver " + dns.toLatin1() + '\n');
                     }
                 }
                 qCInfo(lcMm) << "data bearer up on" << iface << address;
             });
}

QJsonArray MMCellular::calls() const
{
    QJsonArray out;
    for (auto it = m_calls.cbegin(); it != m_calls.cend(); ++it) {
        const QVariantMap c = it.value().value(kCall);
        const int direction = c.value(QStringLiteral("Direction")).toInt();
        out.append(QJsonObject{
            {QStringLiteral("id"), it.key().path()},
            {QStringLiteral("number"), c.value(QStringLiteral("Number")).toString()},
            {QStringLiteral("state"), callStateName(c.value(QStringLiteral("State")).toInt(), direction)},
            {QStringLiteral("direction"), direction == 1 ? QStringLiteral("in") : QStringLiteral("out")},
        });
    }
    return out;
}

void MMCellular::dial(const QString &number, Done done)
{
    if (m_modem.isEmpty()) {
        done(QStringLiteral("no modem"));
        return;
    }
    dbusCall(kService, m_modem, kVoice, QStringLiteral("CreateCall"), {QVariantMap{{QStringLiteral("number"), number}}},
             this, [this, done](const QString &error, const QDBusMessage &reply) {
                 if (!error.isEmpty() || reply.arguments().isEmpty()) {
                     done(error.isEmpty() ? QStringLiteral("cannot create call") : error);
                     return;
                 }
                 const QString call = reply.arguments().at(0).value<QDBusObjectPath>().path();
                 dbusCall(kService, call, kCall, QStringLiteral("Start"), {}, this,
                          [this, done](const QString &err, const QDBusMessage &) {
                              m_watcher->poke();
                              done(err);
                          });
             });
}

void MMCellular::accept(const QString &id)
{
    dbusCall(kService, id, kCall, QStringLiteral("Accept"), {}, this,
             [this](const QString &, const QDBusMessage &) { m_watcher->poke(); });
}

void MMCellular::hangup(const QString &id)
{
    dbusCall(kService, id, kCall, QStringLiteral("Hangup"), {}, this,
             [this](const QString &, const QDBusMessage &) { m_watcher->poke(); });
}

void MMCellular::sendSms(const QString &number, const QString &text, Done done)
{
    if (m_modem.isEmpty()) {
        done(QStringLiteral("no modem"));
        return;
    }
    const QVariantMap sms{{QStringLiteral("number"), number}, {QStringLiteral("text"), text}};
    dbusCall(kService, m_modem, kMessaging, QStringLiteral("Create"), {sms}, this,
             [this, done](const QString &error, const QDBusMessage &reply) {
                 if (!error.isEmpty() || reply.arguments().isEmpty()) {
                     done(error.isEmpty() ? QStringLiteral("cannot create message") : error);
                     return;
                 }
                 const QString path = reply.arguments().at(0).value<QDBusObjectPath>().path();
                 dbusCall(kService, path, kSms, QStringLiteral("Send"), {}, this,
                          [done](const QString &err, const QDBusMessage &) { done(err); });
             });
}

void MMCellular::onSmsAdded(const QDBusObjectPath &path, bool received)
{
    if (!received)
        return;
    dbusCall(kService, path.path(), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"), {kSms},
             this, [this, path](const QString &error, const QDBusMessage &reply) {
                 if (!error.isEmpty() || reply.arguments().isEmpty())
                     return;
                 QVariantMap sms;
                 reply.arguments().at(0).value<QDBusArgument>() >> sms;
                 const QDateTime ts = QDateTime::fromString(sms.value(QStringLiteral("Timestamp")).toString(), Qt::ISODate);
                 Q_EMIT smsReceived(sms.value(QStringLiteral("Number")).toString(), sms.value(QStringLiteral("Text")).toString(),
                                    ts.isValid() ? ts.toMSecsSinceEpoch() : QDateTime::currentMSecsSinceEpoch());
                 // Messages live in astraOS's store, not on the SIM.
                 dbusCall(kService, m_modem, kMessaging, QStringLiteral("Delete"), {QVariant::fromValue(path)}, this, {});
             });
}

} // namespace astrad::network
