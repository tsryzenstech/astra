// SPDX-License-Identifier: Apache-2.0
#include "networkservice.h"
#include "../jsonstore.h"
#include "../notificationservice.h"
#include "../packagemanager.h"
#include "../permissions.h"
#include "../settingsservice.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QDateTime>
#include <QLoggingCategory>

Q_LOGGING_CATEGORY(lcNet, "astrad.network")

namespace astrad {

using namespace astra;
using namespace astrad::network;

namespace {
QString K(const char *s)
{
    return QString::fromLatin1(s);
}
constexpr int kMaxLog = 200;
constexpr int kMaxMessages = 2000;
} // namespace

NetworkService::NetworkService(Server *server, SettingsService *settings, NotificationService *notifications,
                               PackageManager *packages, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_settings(settings)
    , m_notifications(notifications)
    , m_packages(packages)
    , m_wifi(createWifi(this))
    , m_bt(createBluetooth(this))
    , m_cell(createCellular(this))
    , m_storePath(Paths::dataSystem() + QStringLiteral("/telephony.json"))
{
    const QJsonObject store = loadJson(m_storePath);
    m_callLog = store.value(K("calls")).toArray();
    m_messages = store.value(K("messages")).toArray();
    m_nextMessage = qMax(1, store.value(K("nextMessage")).toInt());

    m_announce.setSingleShot(true);
    m_announce.setInterval(100);
    connect(&m_announce, &QTimer::timeout, this, [this] {
        m_server->broadcast(K("network.changed"), state());
    });
    connect(m_wifi, &WifiBackend::changed, this, &NetworkService::announce);
    connect(m_bt, &BluetoothBackend::changed, this, &NetworkService::announce);
    connect(m_cell, &CellularBackend::changed, this, &NetworkService::announce);
    connect(m_cell, &CellularBackend::callsChanged, this, &NetworkService::onCallsChanged);
    connect(m_cell, &CellularBackend::smsReceived, this, &NetworkService::onSmsReceived);

    // Periodic background scan while Wi-Fi is on and not connected.
    m_rescan.setInterval(30000);
    connect(&m_rescan, &QTimer::timeout, this, [this] {
        if (m_wifi->powered() && m_wifi->state() != QLatin1String("connected"))
            m_wifi->scan();
    });
    m_rescan.start();

    // Restore the user's radio choices once the daemons have reported in.
    QTimer::singleShot(1500, this, [this] {
        const bool airplane = m_settings->value(K("radio.airplane")).toBool();
        setWifiPowered(!airplane && m_settings->value(K("radio.wifi")).toBool(true));
        setBluetoothPowered(!airplane && m_settings->value(K("radio.bluetooth")).toBool(false));
        m_cell->setApn(m_settings->value(K("radio.apn")).toString(K("internet")));
        m_cell->setAllowRoaming(m_settings->value(K("radio.roaming")).toBool(false));
        setCellularData(!airplane && m_settings->value(K("radio.cellular")).toBool(true), [](const QString &) {});
    });
}

void NetworkService::announce()
{
    m_announce.start();
}

QJsonObject NetworkService::state() const
{
    const QJsonArray networks = m_wifi->networks();
    QJsonObject current;
    for (const QJsonValue &v : networks)
        if (v.toObject().value(K("connected")).toBool())
            current = v.toObject();
    return {
        {K("airplane"), m_settings->value(K("radio.airplane")).toBool()},
        {K("wifi"), QJsonObject{
             {K("kind"), m_wifi->kind()},
             {K("available"), m_wifi->available()},
             {K("powered"), m_wifi->powered()},
             {K("scanning"), m_wifi->scanning()},
             {K("state"), m_wifi->state()},
             {K("ssid"), current.value(K("ssid"))},
             {K("strength"), current.value(K("strength")).toInt(0)},
             {K("security"), current.value(K("security"))},
             {K("networks"), networks},
             {K("known"), m_wifi->knownNetworks()},
         }},
        {K("bluetooth"), QJsonObject{
             {K("kind"), m_bt->kind()},
             {K("available"), m_bt->available()},
             {K("powered"), m_bt->powered()},
             {K("name"), m_bt->name()},
             {K("discovering"), m_bt->discovering()},
             {K("devices"), m_bt->devices()},
         }},
        {K("cellular"), [this] {
             QJsonObject c = m_cell->state();
             c.insert(K("kind"), m_cell->kind());
             c.insert(K("available"), m_cell->available());
             return c;
         }()},
    };
}

void NetworkService::setWifiPowered(bool on)
{
    m_settings->setValue(K("radio.wifi"), on);
    m_wifi->setPowered(on);
    if (on)
        QTimer::singleShot(500, this, [this] { m_wifi->scan(); });
}

void NetworkService::setBluetoothPowered(bool on)
{
    m_settings->setValue(K("radio.bluetooth"), on);
    m_bt->setPowered(on);
}

void NetworkService::setCellularData(bool on, Done done)
{
    m_settings->setValue(K("radio.cellular"), on);
    m_cell->setDataEnabled(on, std::move(done));
}

void NetworkService::setAirplane(bool on)
{
    m_settings->setValue(K("radio.airplane"), on);
    if (on) {
        m_wifi->setPowered(false);
        m_bt->setPowered(false);
        m_cell->setDataEnabled(false, [](const QString &) {});
    } else {
        m_wifi->setPowered(m_settings->value(K("radio.wifi")).toBool(true));
        m_bt->setPowered(m_settings->value(K("radio.bluetooth")).toBool(false));
        m_cell->setDataEnabled(m_settings->value(K("radio.cellular")).toBool(true), [](const QString &) {});
    }
    announce();
}

// ---- telephony ---------------------------------------------------------------

void NetworkService::saveTelephony()
{
    saveJson(m_storePath, {{K("calls"), m_callLog}, {K("messages"), m_messages}, {K("nextMessage"), m_nextMessage}});
}

void NetworkService::onCallsChanged()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    QSet<QString> present;
    for (const QJsonValue &v : m_cell->calls()) {
        const QJsonObject c = v.toObject();
        const QString id = c.value(K("id")).toString();
        const QString st = c.value(K("state")).toString();
        if (st == QLatin1String("ended"))
            continue;
        present.insert(id);
        if (!m_liveCalls.contains(id)) {
            m_liveCalls.insert(id, {{K("number"), c.value(K("number"))}, {K("direction"), c.value(K("direction"))},
                                    {K("start"), double(now)}, {K("answered"), false}});
            if (st == QLatin1String("incoming"))
                m_server->broadcast(K("telephony.incoming"), c);
        }
        if (st == QLatin1String("active") && !m_liveCalls[id].value(K("answered")).toBool()) {
            m_liveCalls[id].insert(K("answered"), true);
            m_liveCalls[id].insert(K("answeredAt"), double(now));
        }
    }
    // Calls that are gone end up in the call log.
    const QStringList ids = m_liveCalls.keys();
    for (const QString &id : ids) {
        if (present.contains(id))
            continue;
        const QJsonObject c = m_liveCalls.take(id);
        const bool answered = c.value(K("answered")).toBool();
        const bool incoming = c.value(K("direction")).toString() == QLatin1String("in");
        const qint64 answeredAt = qint64(c.value(K("answeredAt")).toDouble());
        m_callLog.prepend(QJsonObject{
            {K("number"), c.value(K("number"))},
            {K("direction"), c.value(K("direction"))},
            {K("missed"), incoming && !answered},
            {K("start"), c.value(K("start"))},
            {K("duration"), answered ? double(now - answeredAt) / 1000.0 : 0.0},
        });
        while (m_callLog.size() > kMaxLog)
            m_callLog.removeLast();
        if (incoming && !answered && m_packages->contains(K("com.astra.phone")))
            m_notifications->post(K("com.astra.phone"), QStringLiteral("Missed call from %1").arg(c.value(K("number")).toString()), {});
        saveTelephony();
    }
    m_server->broadcast(K("telephony.calls"), m_cell->calls(),
                        [](const Caller &cl) { return cl.can(QLatin1String(permissions::PHONE)); });
}

void NetworkService::storeMessage(const QString &number, const QString &text, bool incoming, qint64 timestamp)
{
    const QJsonObject msg{{K("id"), m_nextMessage++}, {K("number"), number}, {K("text"), text},
                          {K("incoming"), incoming}, {K("time"), double(timestamp)}, {K("read"), !incoming}};
    m_messages.append(msg);
    while (m_messages.size() > kMaxMessages)
        m_messages.removeFirst();
    saveTelephony();
    m_server->broadcast(K("telephony.message"), msg,
                        [](const Caller &cl) { return cl.can(QLatin1String(permissions::SMS)); });
}

void NetworkService::onSmsReceived(const QString &number, const QString &text, qint64 timestamp)
{
    storeMessage(number, text, true, timestamp);
    if (m_packages->contains(K("com.astra.messages")))
        m_notifications->post(K("com.astra.messages"), number, text);
}

QJsonValue NetworkService::handleTelephony(const QString &call, const QJsonObject &params, const Caller &caller)
{
    const bool smsCall = call.contains(QLatin1String("ms")) || call.contains(QLatin1String("essage")) ||
                         call.contains(QLatin1String("onversation")) || call == QLatin1String("markRead");
    caller.require(QLatin1String(smsCall ? permissions::SMS : permissions::PHONE));

    if (call == QLatin1String("calls"))
        return m_cell->calls();
    if (call == QLatin1String("dial")) {
        const QString number = params.value(K("number")).toString().trimmed();
        if (number.isEmpty())
            throw RpcError{protocol::InvalidParams, QStringLiteral("number is required")};
        const PendingReply reply = caller.defer();
        m_cell->dial(number, [reply](const QString &error) {
            if (error.isEmpty())
                reply.resolve(true);
            else
                reply.reject(protocol::Failed, error);
        });
        return Deferred;
    }
    if (call == QLatin1String("accept")) {
        m_cell->accept(params.value(K("id")).toString());
        return true;
    }
    if (call == QLatin1String("hangup")) {
        m_cell->hangup(params.value(K("id")).toString());
        return true;
    }
    if (call == QLatin1String("callLog"))
        return m_callLog;
    if (call == QLatin1String("clearCallLog")) {
        m_callLog = {};
        saveTelephony();
        return true;
    }
    if (call == QLatin1String("conversations")) {
        // Latest message per number, newest conversation first.
        QHash<QString, QJsonObject> latest;
        QHash<QString, int> unread;
        for (const QJsonValue &v : std::as_const(m_messages)) {
            const QJsonObject m = v.toObject();
            const QString n = m.value(K("number")).toString();
            latest.insert(n, m);
            if (!m.value(K("read")).toBool())
                unread[n]++;
        }
        QList<QJsonObject> list = latest.values();
        std::sort(list.begin(), list.end(), [](const QJsonObject &a, const QJsonObject &b) {
            return a.value(K("time")).toDouble() > b.value(K("time")).toDouble();
        });
        QJsonArray out;
        for (QJsonObject m : list) {
            m.insert(K("unread"), unread.value(m.value(K("number")).toString()));
            out.append(m);
        }
        return out;
    }
    if (call == QLatin1String("messages")) {
        const QString number = params.value(K("number")).toString();
        QJsonArray out;
        for (const QJsonValue &v : std::as_const(m_messages))
            if (v.toObject().value(K("number")).toString() == number)
                out.append(v);
        return out;
    }
    if (call == QLatin1String("sendSms")) {
        const QString number = params.value(K("number")).toString().trimmed();
        const QString text = params.value(K("text")).toString();
        if (number.isEmpty() || text.isEmpty())
            throw RpcError{protocol::InvalidParams, QStringLiteral("number and text are required")};
        const PendingReply reply = caller.defer();
        m_cell->sendSms(number, text, [this, reply, number, text](const QString &error) {
            if (!error.isEmpty()) {
                reply.reject(protocol::Failed, error);
                return;
            }
            storeMessage(number, text, false, QDateTime::currentMSecsSinceEpoch());
            reply.resolve(true);
        });
        return Deferred;
    }
    if (call == QLatin1String("markRead")) {
        const QString number = params.value(K("number")).toString();
        for (int i = 0; i < m_messages.size(); ++i) {
            QJsonObject m = m_messages.at(i).toObject();
            if (m.value(K("number")).toString() == number && !m.value(K("read")).toBool()) {
                m.insert(K("read"), true);
                m_messages.replace(i, m);
            }
        }
        saveTelephony();
        return true;
    }
    if (call == QLatin1String("deleteConversation")) {
        const QString number = params.value(K("number")).toString();
        for (int i = m_messages.size() - 1; i >= 0; --i)
            if (m_messages.at(i).toObject().value(K("number")).toString() == number)
                m_messages.removeAt(i);
        saveTelephony();
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

QJsonValue NetworkService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    if (call.startsWith(QLatin1String("tel.")))
        return handleTelephony(call.mid(4), params, caller);
    if (call == QLatin1String("state"))
        return state();
    if (call == QLatin1String("wifiScan")) {
        m_wifi->scan();
        return true;
    }

    // Everything below changes radios.
    caller.require(QLatin1String(permissions::MANAGE_NETWORK));
    auto deferDone = [&caller]() {
        const PendingReply reply = caller.defer();
        return [reply](const QString &error) {
            if (error.isEmpty())
                reply.resolve(true);
            else
                reply.reject(protocol::Failed, error);
        };
    };
    const bool on = params.value(K("on")).toBool();

    if (call == QLatin1String("wifiSetPowered")) {
        setWifiPowered(on);
        return true;
    }
    if (call == QLatin1String("wifiConnect")) {
        m_wifi->connectTo(params.value(K("id")).toString(), params.value(K("passphrase")).toString(), deferDone());
        return Deferred;
    }
    if (call == QLatin1String("wifiDisconnect")) {
        m_wifi->disconnectCurrent();
        return true;
    }
    if (call == QLatin1String("wifiForget")) {
        m_wifi->forget(params.value(K("ssid")).toString());
        return true;
    }
    if (call == QLatin1String("btSetPowered")) {
        setBluetoothPowered(on);
        return true;
    }
    if (call == QLatin1String("btSetName")) {
        m_bt->setName(params.value(K("name")).toString());
        return true;
    }
    if (call == QLatin1String("btDiscover")) {
        m_bt->setDiscovering(on);
        return true;
    }
    if (call == QLatin1String("btPair")) {
        m_bt->pair(params.value(K("address")).toString(), deferDone());
        return Deferred;
    }
    if (call == QLatin1String("btConnect")) {
        m_bt->connectDevice(params.value(K("address")).toString(), deferDone());
        return Deferred;
    }
    if (call == QLatin1String("btDisconnect")) {
        m_bt->disconnectDevice(params.value(K("address")).toString());
        return true;
    }
    if (call == QLatin1String("btForget")) {
        m_bt->forget(params.value(K("address")).toString());
        return true;
    }
    if (call == QLatin1String("cellSetData")) {
        setCellularData(on, deferDone());
        return Deferred;
    }
    if (call == QLatin1String("cellSetApn")) {
        const QString apn = params.value(K("apn")).toString().trimmed();
        m_settings->setValue(K("radio.apn"), apn);
        m_cell->setApn(apn);
        announce();
        return true;
    }
    if (call == QLatin1String("cellSetRoaming")) {
        m_settings->setValue(K("radio.roaming"), on);
        m_cell->setAllowRoaming(on);
        announce();
        return true;
    }
    if (call == QLatin1String("setAirplane")) {
        setAirplane(on);
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
