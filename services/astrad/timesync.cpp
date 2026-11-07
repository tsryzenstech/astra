// SPDX-License-Identifier: Apache-2.0
#include "timesync.h"
#include "server.h"
#include "settingsservice.h"

#include <astra/paths.h>
#include <astra/properties.h>

#include <QDateTime>
#include <QFile>
#include <QHostInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QNetworkDatagram>
#include <QUdpSocket>

#include <cerrno>
#include <cstring>
#include <utility>

#include <time.h>

Q_LOGGING_CATEGORY(lcTime, "astrad.time")

namespace astrad {

namespace {
const QStringList kServers = {QStringLiteral("pool.ntp.org"), QStringLiteral("time.google.com"),
                              QStringLiteral("time.cloudflare.com")};
const quint16 kNtpPort = 123;
const qint64 kNtpToUnix = 2208988800LL; // seconds from 1900 to 1970
const int kAnswerMs = 4000;
const int kRetryMs = 30 * 1000;              // until the first sync
const int kRefreshMs = 6 * 60 * 60 * 1000;   // afterwards

QString stateFile()
{
    return astra::Paths::dataSystem() + QStringLiteral("/time.json");
}

// Seconds the RTC has counted, or -1 without one.
qint64 rtcSeconds()
{
    QFile f(QStringLiteral("/sys/class/rtc/rtc0/since_epoch"));
    if (!f.open(QIODevice::ReadOnly))
        return -1;
    bool ok = false;
    const qint64 v = f.readAll().trimmed().toLongLong(&ok);
    return ok ? v : -1;
}

quint32 be32(const QByteArray &b, int at)
{
    const auto *p = reinterpret_cast<const uchar *>(b.constData()) + at;
    return (quint32(p[0]) << 24) | (quint32(p[1]) << 16) | (quint32(p[2]) << 8) | quint32(p[3]);
}
} // namespace

TimeSync::TimeSync(Server *server, SettingsService *settings, QObject *parent)
    : QObject(parent)
    , m_server(server)
    , m_settings(settings)
{
    m_timeout.setSingleShot(true);
    m_timeout.setInterval(kAnswerMs);
    connect(&m_timeout, &QTimer::timeout, this, [this] { tryServer(m_server_index + 1); });

    if (astra::Paths::isDevelopmentRoot())
        return; // the computer's clock is not ours to set

    restore();
    connect(&m_timer, &QTimer::timeout, this, &TimeSync::onTimer);
    m_timer.setInterval(kRetryMs);
    m_timer.start();
    QTimer::singleShot(2000, this, &TimeSync::onTimer);
}

void TimeSync::onTimer()
{
    if (m_settings->value(QStringLiteral("system.auto_time")).toBool(true))
        sync();
}

void TimeSync::restore()
{
    QFile f(stateFile());
    qint64 target = 0;
    if (f.open(QIODevice::ReadOnly)) {
        const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
        const qint64 epoch = qint64(o.value(QStringLiteral("epoch")).toDouble());
        const qint64 rtc = qint64(o.value(QStringLiteral("rtc")).toDouble());
        m_lastSync = qint64(o.value(QStringLiteral("synced")).toDouble());
        const qint64 rtcNow = rtcSeconds();
        // An RTC that went back lost power: the saved time is still a lower bound.
        if (epoch > 0)
            target = (epoch + (rtcNow >= rtc && rtc >= 0 ? rtcNow - rtc : 0)) * 1000;
    }
    const qint64 built = qint64(astra::Properties::get(QStringLiteral("ro.astra.build.date")).toDouble()) * 1000;
    target = qMax(target, built);
    if (target > QDateTime::currentMSecsSinceEpoch()) {
        setClock(target);
        qCInfo(lcTime) << "clock restored to" << QDateTime::fromMSecsSinceEpoch(target).toString(Qt::ISODate);
    }
}

bool TimeSync::setClock(qint64 msecs)
{
    struct timespec ts {};
    ts.tv_sec = time_t(msecs / 1000);
    ts.tv_nsec = long(msecs % 1000) * 1000000L;
    if (clock_settime(CLOCK_REALTIME, &ts) != 0) {
        qCWarning(lcTime) << "cannot set the clock:" << strerror(errno);
        return false;
    }
    return true;
}

void TimeSync::save(qint64 msecs)
{
    QFile f(stateFile());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        f.write(QJsonDocument(QJsonObject{{QStringLiteral("epoch"), double(msecs / 1000)},
                                          {QStringLiteral("rtc"), double(rtcSeconds())},
                                          {QStringLiteral("synced"), double(msecs)}})
                    .toJson(QJsonDocument::Compact));
}

void TimeSync::sync(std::function<void(bool, const QString &)> done)
{
    if (done)
        m_waiting.append(std::move(done));
    if (m_busy)
        return;
    m_busy = true;
    tryServer(0);
}

void TimeSync::tryServer(int index)
{
    if (m_lookup >= 0) {
        QHostInfo::abortHostLookup(m_lookup);
        m_lookup = -1;
    }
    if (m_socket) {
        m_socket->deleteLater();
        m_socket = nullptr;
    }
    if (index >= kServers.size()) {
        finish(false, tr("No time server answered. Is there a connection?"));
        return;
    }
    m_server_index = index;
    m_timeout.start();
    m_lookup = QHostInfo::lookupHost(kServers.at(index), this, [this, index](const QHostInfo &host) {
        m_lookup = -1;
        if (index != m_server_index || !m_busy)
            return;
        // IPv4: what a phone on Wi-Fi certainly has.
        QHostAddress address;
        for (const QHostAddress &a : host.addresses()) {
            if (a.protocol() == QAbstractSocket::IPv4Protocol) {
                address = a;
                break;
            }
        }
        if (address.isNull()) {
            tryServer(index + 1);
            return;
        }
        m_socket = new QUdpSocket(this);
        connect(m_socket, &QUdpSocket::readyRead, this, [this] {
            while (m_socket && m_socket->hasPendingDatagrams()) {
                const QByteArray reply = m_socket->receiveDatagram().data();
                // Version in the first byte, a server's mode (4), stratum not 0.
                if (reply.size() < 48 || (uchar(reply.at(0)) & 7) != 4 || uchar(reply.at(1)) == 0)
                    continue;
                const qint64 seconds = qint64(be32(reply, 40)) - kNtpToUnix;
                const qint64 fraction = (qint64(be32(reply, 44)) * 1000) >> 32;
                const qint64 msecs = seconds * 1000 + fraction;
                if (seconds <= 0) {
                    tryServer(m_server_index + 1);
                    return;
                }
                m_timeout.stop();
                if (!setClock(msecs)) {
                    finish(false, tr("The clock could not be set."));
                    return;
                }
                save(msecs);
                m_lastSync = msecs;
                qCInfo(lcTime) << "clock set from" << kServers.at(m_server_index) << "to"
                               << QDateTime::fromMSecsSinceEpoch(msecs).toString(Qt::ISODate);
                m_server->broadcast(QStringLiteral("system.timeSynced"), double(msecs));
                m_timer.setInterval(kRefreshMs);
                finish(true, QString());
                return;
            }
        });
        // Client request: version 4, mode 3; the rest stays zero.
        QByteArray request(48, '\0');
        request[0] = char(0x23);
        m_socket->writeDatagram(request, address, kNtpPort);
    });
}

void TimeSync::finish(bool ok, const QString &message)
{
    m_busy = false;
    m_timeout.stop();
    if (m_socket) {
        m_socket->deleteLater();
        m_socket = nullptr;
    }
    const auto waiting = std::exchange(m_waiting, {});
    for (const auto &done : waiting)
        done(ok, message);
}

} // namespace astrad
