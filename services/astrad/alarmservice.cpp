// SPDX-License-Identifier: Apache-2.0
#include "alarmservice.h"
#include "jsonstore.h"
#include "notificationservice.h"
#include "permissions.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QDateTime>

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s)
{
    return QString::fromLatin1(s);
}
constexpr int kSnoozeMinutes = 9;
} // namespace

AlarmService::AlarmService(Server *server, NotificationService *notifications, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_notifications(notifications)
    , m_path(Paths::dataSystem() + QStringLiteral("/alarms.json"))
{
    const QJsonObject stored = loadJson(m_path);
    m_alarms = stored.value(K("alarms")).toArray();
    m_timers = stored.value(K("timers")).toArray();
    m_nextId = qMax(1, stored.value(K("nextId")).toInt());
    m_lastCheck = QDateTime::currentMSecsSinceEpoch();
    m_timer.setSingleShot(true);
    connect(&m_timer, &QTimer::timeout, this, &AlarmService::fireDue);
    schedule();
}

void AlarmService::save()
{
    saveJson(m_path, {{K("alarms"), m_alarms}, {K("timers"), m_timers}, {K("nextId"), m_nextId}});
}

void AlarmService::announce()
{
    m_server->broadcast(K("alarms.changed"),
                        QJsonObject{{K("alarms"), m_alarms}, {K("timers"), m_timers}, {K("next"), nextAlarm()}});
}

qint64 AlarmService::nextOccurrence(const QJsonObject &alarm, qint64 after) const
{
    const qint64 snooze = qint64(alarm.value(K("snoozeUntil")).toDouble());
    if (snooze > after)
        return snooze;
    const QDateTime from = QDateTime::fromMSecsSinceEpoch(after);
    const QTime time(alarm.value(K("hour")).toInt(), alarm.value(K("minute")).toInt());
    QList<int> days;
    for (const QJsonValue &d : alarm.value(K("days")).toArray())
        days.append(d.toInt());
    for (int offset = 0; offset <= 7; ++offset) {
        const QDate date = from.date().addDays(offset);
        const QDateTime candidate(date, time);
        if (candidate.toMSecsSinceEpoch() <= after)
            continue;
        if (days.isEmpty() || days.contains(date.dayOfWeek()))
            return candidate.toMSecsSinceEpoch();
    }
    return 0;
}

QJsonObject AlarmService::nextAlarm() const
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    QJsonObject best;
    qint64 bestTime = 0;
    for (const QJsonValue &v : m_alarms) {
        const QJsonObject a = v.toObject();
        if (!a.value(K("enabled")).toBool())
            continue;
        const qint64 t = nextOccurrence(a, now);
        if (t && (!bestTime || t < bestTime)) {
            bestTime = t;
            best = a;
        }
    }
    if (!best.isEmpty())
        best.insert(K("time"), double(bestTime));
    return best;
}

void AlarmService::schedule()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    qint64 next = now + 60000; // re-check every minute (clock changes, DST)
    for (const QJsonValue &v : std::as_const(m_alarms))
        if (v.toObject().value(K("enabled")).toBool())
            if (const qint64 t = nextOccurrence(v.toObject(), now))
                next = qMin(next, t);
    for (const QJsonValue &v : std::as_const(m_timers))
        next = qMin(next, qint64(v.toObject().value(K("end")).toDouble()));
    m_timer.start(int(qBound(qint64(10), next - now, qint64(60000))));
}

void AlarmService::fireDue()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    auto ring = [this, now](const QString &kind, const QJsonObject &item) {
        m_ringing = {{K("kind"), kind}, {K("id"), item.value(K("id"))}, {K("label"), item.value(K("label"))},
                     {K("time"), double(now)}};
        if (m_server->hasSystemSubscriber(K("alarms")))
            m_server->broadcast(K("alarms.fired"), m_ringing);
        else
            m_notifications->post(K("com.astra.clock"), kind == QLatin1String("timer") ? K("Timer finished") : K("Alarm"),
                                  item.value(K("label")).toString());
    };

    bool changed = false;
    for (int i = 0; i < m_alarms.size(); ++i) {
        QJsonObject a = m_alarms.at(i).toObject();
        if (!a.value(K("enabled")).toBool())
            continue;
        const qint64 t = nextOccurrence(a, m_lastCheck);
        if (!t || t > now)
            continue;
        a.remove(K("snoozeUntil"));
        if (a.value(K("days")).toArray().isEmpty())
            a.insert(K("enabled"), false); // one-shot alarm
        m_alarms.replace(i, a);
        ring(K("alarm"), a);
        changed = true;
    }
    for (int i = m_timers.size() - 1; i >= 0; --i) {
        const QJsonObject t = m_timers.at(i).toObject();
        if (qint64(t.value(K("end")).toDouble()) <= now) {
            m_timers.removeAt(i);
            ring(K("timer"), t);
            changed = true;
        }
    }
    m_lastCheck = now;
    if (changed) {
        save();
        announce();
    }
    schedule();
}

QJsonValue AlarmService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    const int id = params.value(K("id")).toInt();
    if (call == QLatin1String("list"))
        return m_alarms;
    if (call == QLatin1String("timers"))
        return m_timers;
    if (call == QLatin1String("next"))
        return nextAlarm();
    if (call == QLatin1String("ringing"))
        return m_ringing.isEmpty() ? QJsonValue() : QJsonValue(m_ringing);

    if (call == QLatin1String("snooze") || call == QLatin1String("dismiss")) {
        caller.requireSystem();
        if (call == QLatin1String("snooze") && m_ringing.value(K("kind")).toString() == QLatin1String("alarm")) {
            for (int i = 0; i < m_alarms.size(); ++i) {
                QJsonObject a = m_alarms.at(i).toObject();
                if (a.value(K("id")).toInt() == m_ringing.value(K("id")).toInt()) {
                    a.insert(K("enabled"), true);
                    a.insert(K("snoozeUntil"), double(QDateTime::currentMSecsSinceEpoch() + kSnoozeMinutes * 60000));
                    m_alarms.replace(i, a);
                }
            }
        }
        m_ringing = {};
        m_server->broadcast(K("alarms.stopped"), QJsonValue());
        save();
        announce();
        schedule();
        return true;
    }

    caller.require(QLatin1String(permissions::ALARMS));
    if (call == QLatin1String("set")) {
        QJsonObject a{
            {K("id"), id > 0 ? id : m_nextId++},
            {K("hour"), qBound(0, params.value(K("hour")).toInt(), 23)},
            {K("minute"), qBound(0, params.value(K("minute")).toInt(), 59)},
            {K("days"), params.value(K("days")).toArray()},
            {K("label"), params.value(K("label")).toString().left(60)},
            {K("enabled"), params.value(K("enabled")).toBool(true)},
            {K("owner"), caller.package},
        };
        bool replaced = false;
        for (int i = 0; i < m_alarms.size(); ++i)
            if (m_alarms.at(i).toObject().value(K("id")).toInt() == a.value(K("id")).toInt()) {
                m_alarms.replace(i, a);
                replaced = true;
            }
        if (!replaced)
            m_alarms.append(a);
        save();
        announce();
        schedule();
        return a;
    }
    if (call == QLatin1String("delete")) {
        for (int i = 0; i < m_alarms.size(); ++i)
            if (m_alarms.at(i).toObject().value(K("id")).toInt() == id)
                m_alarms.removeAt(i);
        save();
        announce();
        schedule();
        return true;
    }
    if (call == QLatin1String("startTimer")) {
        const int seconds = params.value(K("seconds")).toInt();
        if (seconds <= 0)
            throw RpcError{protocol::InvalidParams, QStringLiteral("seconds must be positive")};
        const QJsonObject t{{K("id"), m_nextId++},
                            {K("label"), params.value(K("label")).toString().left(60)},
                            {K("duration"), seconds},
                            {K("end"), double(QDateTime::currentMSecsSinceEpoch() + qint64(seconds) * 1000)}};
        m_timers.append(t);
        save();
        announce();
        schedule();
        return t;
    }
    if (call == QLatin1String("cancelTimer")) {
        for (int i = 0; i < m_timers.size(); ++i)
            if (m_timers.at(i).toObject().value(K("id")).toInt() == id)
                m_timers.removeAt(i);
        save();
        announce();
        schedule();
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
