// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QObject>
#include <QStringList>
#include <QTimer>

#include <functional>

class QUdpSocket;

namespace astrad {

class Server;
class SettingsService;

// The clock. The phone's RTC only counts seconds since it last lost power and
// cannot be set, so what it reads is 1970. The real time comes from the network
// (SNTP) and is kept as an offset from the RTC in a file, so it survives reboots
// and time without network. Until the first sync the clock is at least the date
// the system was built, because certificates do not validate in 1970.
class TimeSync : public QObject
{
    Q_OBJECT
public:
    TimeSync(Server *server, SettingsService *settings, QObject *parent = nullptr);

    // Asks the network now. done(ok, message) is called once.
    void sync(std::function<void(bool, const QString &)> done = {});
    qint64 lastSync() const { return m_lastSync; }

private:
    void restore();
    void tryServer(int index);
    void finish(bool ok, const QString &message);
    bool setClock(qint64 msecs);
    void save(qint64 msecs);
    void onTimer();

    Server *m_server;
    SettingsService *m_settings;
    QUdpSocket *m_socket = nullptr;
    QTimer m_timer;     // automatic syncs
    QTimer m_timeout;   // one server's answer
    int m_server_index = 0;
    int m_lookup = -1;
    bool m_busy = false;
    qint64 m_lastSync = 0;
    QList<std::function<void(bool, const QString &)>> m_waiting;
};

} // namespace astrad
