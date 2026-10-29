// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QJsonArray>
#include <QTimer>

namespace astrad {

class NotificationService;

// The calendar shared by Calendar, the lock screen widgets and Planet.
// Alerts become notifications even when Calendar is closed.
//   calendar.list {from, to} (ms) -> occurrences [{id, title, start, end, allDay,
//                 location, notes, color, alert, repeat}] sorted by start
//   calendar.add {title, start, end, allDay, location, notes, color, alert, repeat}
//   calendar.update {id, ...}, calendar.delete {id}                       CALENDAR
//   alert: minutes before the start (-1 = none); repeat: none|daily|weekly|monthly|yearly
class CalendarService : public Service
{
    Q_OBJECT
public:
    CalendarService(Server *server, NotificationService *notifications, QObject *parent = nullptr);
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

private:
    void save();
    void schedule();
    QJsonArray occurrences(qint64 from, qint64 to) const;
    static QJsonObject sanitize(const QJsonObject &in, const QJsonObject &base);

    Server *m_server;
    NotificationService *m_notifications;
    QString m_path;
    QJsonArray m_events;
    int m_nextId = 1;
    qint64 m_lastAlert = 0;  // alerts up to this time have been shown
    QTimer m_timer;
};

} // namespace astrad
