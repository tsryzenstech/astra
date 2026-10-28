// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QJsonArray>
#include <QTimer>

namespace astrad {

class NotificationService;

// Alarms and timers. They ring even when Clock is closed: astrad keeps the
// schedule and SysBoard shows the full screen alarm (alarms.fired).
//
//   alarms.list, alarms.set {id?, hour, minute, days[0..6], label, enabled}
//   alarms.delete {id}, alarms.next
//   alarms.startTimer {seconds, label} -> id, alarms.cancelTimer {id}, alarms.timers
//   alarms.snooze {id}, alarms.dismiss {id}         (SysBoard)
class AlarmService : public Service
{
    Q_OBJECT
public:
    AlarmService(Server *server, NotificationService *notifications, QObject *parent = nullptr);
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

private:
    void schedule();
    void fireDue();
    qint64 nextOccurrence(const QJsonObject &alarm, qint64 after) const;
    QJsonObject nextAlarm() const;
    void save();
    void announce();

    Server *m_server;
    NotificationService *m_notifications;
    QString m_path;
    QJsonArray m_alarms;  // {id, hour, minute, days, label, enabled, snoozeUntil}
    QJsonArray m_timers;  // {id, label, end, duration}
    QJsonObject m_ringing; // the alarm/timer currently ringing
    int m_nextId = 1;
    qint64 m_lastCheck = 0;
    QTimer m_timer;
};

} // namespace astrad
