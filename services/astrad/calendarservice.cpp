// SPDX-License-Identifier: Apache-2.0
#include "calendarservice.h"
#include "jsonstore.h"
#include "notificationservice.h"
#include "permissions.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QDateTime>
#include <QLocale>

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s) { return QString::fromLatin1(s); }
constexpr qint64 kDay = 24LL * 3600 * 1000;

// Start of the n-th repetition of a repeating event.
QDateTime step(const QDateTime &start, const QString &repeat, int n)
{
    if (repeat == QLatin1String("daily"))
        return start.addDays(n);
    if (repeat == QLatin1String("weekly"))
        return start.addDays(7LL * n);
    if (repeat == QLatin1String("monthly"))
        return start.addMonths(n);
    if (repeat == QLatin1String("yearly"))
        return start.addYears(n);
    return start;
}
} // namespace

CalendarService::CalendarService(Server *server, NotificationService *notifications, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_notifications(notifications)
    , m_path(Paths::dataSystem() + QStringLiteral("/calendar.json"))
{
    const QJsonObject stored = loadJson(m_path);
    m_events = stored.value(K("events")).toArray();
    m_nextId = qMax(1, stored.value(K("nextId")).toInt());
    m_lastAlert = qint64(stored.value(K("lastAlert")).toDouble(double(QDateTime::currentMSecsSinceEpoch())));
    m_timer.setSingleShot(true);
    connect(&m_timer, &QTimer::timeout, this, &CalendarService::schedule);
    schedule();
}

void CalendarService::save()
{
    saveJson(m_path, {{K("events"), m_events}, {K("nextId"), m_nextId}, {K("lastAlert"), double(m_lastAlert)}});
    m_server->broadcast(K("calendar.changed"), QJsonValue(),
                        [](const Caller &c) { return c.can(QLatin1String(permissions::CALENDAR)); });
    schedule();
}

QJsonArray CalendarService::occurrences(qint64 from, qint64 to) const
{
    QList<QJsonObject> out;
    for (const QJsonValue &v : m_events) {
        const QJsonObject e = v.toObject();
        const QDateTime start = QDateTime::fromMSecsSinceEpoch(qint64(e.value(K("start")).toDouble()));
        const qint64 length = qint64(e.value(K("end")).toDouble()) - start.toMSecsSinceEpoch();
        const QString repeat = e.value(K("repeat")).toString(K("none"));
        for (int n = 0; n < 5000; ++n) {
            const QDateTime s = step(start, repeat, n);
            const qint64 sm = s.toMSecsSinceEpoch();
            if (sm > to)
                break;
            if (sm + length >= from) {
                QJsonObject o = e;
                o.insert(K("start"), double(sm));
                o.insert(K("end"), double(sm + length));
                out.append(o);
            }
            if (repeat == QLatin1String("none"))
                break;
        }
    }
    std::sort(out.begin(), out.end(), [](const QJsonObject &a, const QJsonObject &b) {
        return a.value(QLatin1String("start")).toDouble() < b.value(QLatin1String("start")).toDouble();
    });
    QJsonArray list;
    for (const QJsonObject &o : out)
        list.append(o);
    return list;
}

// Shows the alerts that are due and waits for the next one.
void CalendarService::schedule()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    qint64 next = now + kDay;
    const QJsonArray soon = occurrences(m_lastAlert - 7 * kDay, now + 8 * kDay);
    for (const QJsonValue &v : soon) {
        const QJsonObject o = v.toObject();
        const int minutes = o.value(K("alert")).toInt(-1);
        if (minutes < 0)
            continue;
        const qint64 start = qint64(o.value(K("start")).toDouble());
        const qint64 at = start - qint64(minutes) * 60000;
        if (at > m_lastAlert && at <= now && now - at < 6 * 3600 * 1000) {
            QString body = QLocale().toString(QDateTime::fromMSecsSinceEpoch(start).time(), QLocale::ShortFormat);
            if (!o.value(K("location")).toString().isEmpty())
                body += QStringLiteral(" • ") + o.value(K("location")).toString();
            m_notifications->post(K("com.astra.calendar"), o.value(K("title")).toString(), body);
        } else if (at > now) {
            next = qMin(next, at);
        }
    }
    if (m_lastAlert != now) {
        m_lastAlert = now;
        saveJson(m_path, {{K("events"), m_events}, {K("nextId"), m_nextId}, {K("lastAlert"), double(m_lastAlert)}});
    }
    m_timer.start(int(qBound<qint64>(1000, next - now + 50, kDay)));
}

QJsonObject CalendarService::sanitize(const QJsonObject &in, const QJsonObject &base)
{
    QJsonObject e = base;
    for (const char *key : {"title", "location", "notes", "color"})
        if (in.contains(QLatin1String(key)))
            e.insert(QLatin1String(key), in.value(QLatin1String(key)).toString().left(2000).trimmed());
    for (const char *key : {"start", "end"})
        if (in.contains(QLatin1String(key)))
            e.insert(QLatin1String(key), in.value(QLatin1String(key)).toDouble());
    if (in.contains(K("allDay")))
        e.insert(K("allDay"), in.value(K("allDay")).toBool());
    if (in.contains(K("alert")))
        e.insert(K("alert"), qBound(-1, in.value(K("alert")).toInt(-1), 60 * 24 * 14));
    if (in.contains(K("repeat"))) {
        const QString r = in.value(K("repeat")).toString();
        e.insert(K("repeat"), QStringList{K("daily"), K("weekly"), K("monthly"), K("yearly")}.contains(r) ? r : K("none"));
    }
    if (e.value(K("end")).toDouble() < e.value(K("start")).toDouble())
        e.insert(K("end"), e.value(K("start")).toDouble() + 3600000);
    return e;
}

QJsonValue CalendarService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    caller.require(QLatin1String(permissions::CALENDAR));
    const int id = params.value(K("id")).toInt();
    auto indexOf = [this](int id) {
        for (int i = 0; i < m_events.size(); ++i)
            if (m_events.at(i).toObject().value(QLatin1String("id")).toInt() == id)
                return i;
        throw RpcError{protocol::InvalidParams, QStringLiteral("no such event")};
    };

    if (call == QLatin1String("list")) {
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        return occurrences(qint64(params.value(K("from")).toDouble(double(now))),
                           qint64(params.value(K("to")).toDouble(double(now + 30 * kDay))));
    }
    if (call == QLatin1String("add")) {
        QJsonObject e = sanitize(params, {{K("title"), K("New Event")}, {K("allDay"), false}, {K("alert"), 15},
                                          {K("repeat"), K("none")}, {K("color"), K("orange")}});
        if (!e.contains(K("start")))
            throw RpcError{protocol::InvalidParams, QStringLiteral("an event needs a start")};
        e.insert(K("id"), m_nextId++);
        m_events.append(e);
        save();
        return e;
    }
    if (call == QLatin1String("update")) {
        const int i = indexOf(id);
        m_events.replace(i, sanitize(params, m_events.at(i).toObject()));
        save();
        return m_events.at(i);
    }
    if (call == QLatin1String("delete")) {
        m_events.removeAt(indexOf(id));
        save();
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
