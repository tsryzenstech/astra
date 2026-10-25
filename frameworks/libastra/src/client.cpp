// SPDX-License-Identifier: Apache-2.0
#include "astra/client.h"
#include "astra/paths.h"
#include "astra/protocol.h"

#include <QDeadlineTimer>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocalSocket>

namespace astra {

Client *Client::instance()
{
    static Client *client = new Client;
    return client;
}

Client::Client(QObject *parent)
    : QObject(parent)
    , m_socket(new QLocalSocket(this))
{
    m_reconnect.setInterval(500);
    m_reconnect.setSingleShot(true);
    connect(&m_reconnect, &QTimer::timeout, this, &Client::connectToServer);

    connect(m_socket, &QLocalSocket::connected, this, [this] {
        if (!m_topics.isEmpty())
            m_queue.prepend(protocol::encode({{QStringLiteral("id"), 0},
                                              {QStringLiteral("method"), QStringLiteral("system.subscribe")},
                                              {QStringLiteral("params"), QJsonObject{{QStringLiteral("topics"), QJsonArray::fromStringList(m_topics)}}}}));
        flushQueue();
        Q_EMIT connectedChanged(true);
    });
    connect(m_socket, &QLocalSocket::disconnected, this, [this] {
        // Fail outstanding calls; callers retry if they care.
        const auto pending = std::exchange(m_pending, {});
        for (const Callback &cb : pending)
            if (cb)
                cb(QJsonValue(), QStringLiteral("disconnected"));
        Q_EMIT connectedChanged(false);
        m_reconnect.start();
    });
    connect(m_socket, &QLocalSocket::errorOccurred, this, [this] {
        if (m_socket->state() == QLocalSocket::UnconnectedState)
            m_reconnect.start();
    });
    connect(m_socket, &QLocalSocket::readyRead, this, &Client::onReadyRead);
    connectToServer();
}

void Client::connectToServer()
{
    if (m_socket->state() != QLocalSocket::UnconnectedState)
        return;
    m_socket->connectToServer(Paths::astradSocket());
}

bool Client::isConnected() const
{
    return m_socket->state() == QLocalSocket::ConnectedState;
}

void Client::flushQueue()
{
    if (!isConnected())
        return;
    for (const QByteArray &msg : std::as_const(m_queue))
        m_socket->write(msg);
    m_queue.clear();
    m_socket->flush();
}

void Client::call(const QString &method, const QJsonObject &params, Callback callback)
{
    const int id = m_nextId++;
    if (callback)
        m_pending.insert(id, std::move(callback));
    m_queue.append(protocol::encode({{QStringLiteral("id"), id},
                                     {QStringLiteral("method"), method},
                                     {QStringLiteral("params"), params}}));
    flushQueue();
}

QJsonValue Client::callSync(const QString &method, const QJsonObject &params, QString *error, int timeoutMs)
{
    QDeadlineTimer deadline(timeoutMs);
    if (!isConnected()) {
        connectToServer();
        if (!m_socket->waitForConnected(int(deadline.remainingTime()))) {
            if (error)
                *error = QStringLiteral("astrad unavailable");
            return {};
        }
    }
    const int id = m_nextId++;
    m_syncReplies.insert(id, {});
    m_socket->write(protocol::encode({{QStringLiteral("id"), id},
                                      {QStringLiteral("method"), method},
                                      {QStringLiteral("params"), params}}));
    m_socket->flush();

    while (m_syncReplies.value(id).isEmpty() && !deadline.hasExpired()) {
        if (!m_socket->waitForReadyRead(int(deadline.remainingTime())))
            break;
        onReadyRead();
    }
    const QJsonObject reply = m_syncReplies.take(id);
    if (reply.isEmpty()) {
        if (error)
            *error = QStringLiteral("timeout");
        return {};
    }
    if (reply.contains(QLatin1String("error"))) {
        if (error)
            *error = reply.value(QLatin1String("error")).toObject().value(QLatin1String("message")).toString();
        return {};
    }
    if (error)
        error->clear();
    return reply.value(QLatin1String("result"));
}

void Client::subscribe(const QStringList &topics)
{
    QStringList added;
    for (const QString &t : topics)
        if (!m_topics.contains(t))
            added.append(t);
    if (added.isEmpty())
        return;
    m_topics.append(added);
    call(QStringLiteral("system.subscribe"), {{QStringLiteral("topics"), QJsonArray::fromStringList(added)}});
}

void Client::onReadyRead()
{
    m_buffer.append(m_socket->readAll());
    qsizetype nl;
    while ((nl = m_buffer.indexOf('\n')) >= 0) {
        const QByteArray line = m_buffer.left(nl);
        m_buffer.remove(0, nl + 1);
        if (!line.isEmpty())
            processLine(line);
    }
}

void Client::processLine(const QByteArray &line)
{
    const QJsonObject msg = QJsonDocument::fromJson(line).object();
    if (msg.contains(QLatin1String("event"))) {
        Q_EMIT event(msg.value(QLatin1String("event")).toString(), msg.value(QLatin1String("data")));
        return;
    }
    const int id = msg.value(QLatin1String("id")).toInt();
    if (m_syncReplies.contains(id)) {
        m_syncReplies.insert(id, msg);
        return;
    }
    const Callback cb = m_pending.take(id);
    if (!cb)
        return;
    if (msg.contains(QLatin1String("error")))
        cb(QJsonValue(), msg.value(QLatin1String("error")).toObject().value(QLatin1String("message")).toString());
    else
        cb(msg.value(QLatin1String("result")), QString());
}

} // namespace astra
