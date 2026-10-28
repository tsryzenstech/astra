// SPDX-License-Identifier: Apache-2.0
#include "server.h"
#include "permissions.h"

#include <astra/protocol.h>

#include <QFile>
#include <QJsonArray>
#include <QLocalServer>
#include <QLocalSocket>
#include <QLoggingCategory>

#include <sys/socket.h>

Q_LOGGING_CATEGORY(lcServer, "astrad.server")

namespace astrad {

using namespace astra;

void Caller::require(const QString &permission) const
{
    if (!can(permission))
        throw RpcError{protocol::PermissionDenied, QStringLiteral("%1 requires %2").arg(package, permission)};
}

void Caller::requireSystem() const
{
    if (!isSystem())
        throw RpcError{protocol::PermissionDenied, QStringLiteral("system only")};
}

PendingReply::PendingReply(Connection *connection, const QJsonValue &id)
    : m_connection(connection)
    , m_id(id)
{
}

bool PendingReply::isValid() const
{
    return !m_connection.isNull();
}

void PendingReply::resolve(const QJsonValue &result) const
{
    if (m_connection)
        m_connection->send({{QStringLiteral("id"), m_id}, {QStringLiteral("result"), result}});
}

void PendingReply::reject(int code, const QString &message) const
{
    if (m_connection)
        m_connection->send({{QStringLiteral("id"), m_id},
                            {QStringLiteral("error"), QJsonObject{{QStringLiteral("code"), code},
                                                                  {QStringLiteral("message"), message}}}});
}

Connection::Connection(QLocalSocket *s, QObject *parent)
    : QObject(parent)
    , socket(s)
{
    s->setParent(this);
}

void Connection::send(const QJsonObject &message)
{
    socket->write(protocol::encode(message));
}

Server::Server(QObject *parent)
    : QObject(parent)
    , m_server(new QLocalServer(this))
{
    m_server->setSocketOptions(QLocalServer::WorldAccessOption);
    connect(m_server, &QLocalServer::newConnection, this, &Server::onNewConnection);
}

bool Server::listen(const QString &path)
{
    QLocalServer::removeServer(path);
    if (!m_server->listen(path)) {
        qCCritical(lcServer) << "cannot listen on" << path << m_server->errorString();
        return false;
    }
    qCInfo(lcServer) << "listening on" << path;
    return true;
}

void Server::registerService(const QString &prefix, Service *service)
{
    m_services.insert(prefix, service);
}

void Server::onNewConnection()
{
    while (QLocalSocket *socket = m_server->nextPendingConnection()) {
        auto *c = new Connection(socket, this);
        struct ucred cred {};
        socklen_t len = sizeof(cred);
        if (getsockopt(int(socket->socketDescriptor()), SOL_SOCKET, SO_PEERCRED, &cred, &len) == 0) {
            c->caller.uid = cred.uid;
            c->caller.pid = cred.pid;
        }
        c->caller.connection = c;
        if (m_identify)
            m_identify(c->caller);
        m_connections.append(c);

        connect(socket, &QLocalSocket::readyRead, c, [this, c] { onReadyRead(c); });
        connect(socket, &QLocalSocket::disconnected, c, [this, c] {
            m_connections.removeAll(c);
            Q_EMIT clientDisconnected(c->caller);
            c->deleteLater();
        });
    }
}

void Server::onReadyRead(Connection *c)
{
    c->buffer.append(c->socket->readAll());
    if (c->buffer.size() > 4 * 1024 * 1024) { // misbehaving client
        c->socket->abort();
        return;
    }
    qsizetype nl;
    while ((nl = c->buffer.indexOf('\n')) >= 0) {
        const QByteArray line = c->buffer.left(nl);
        c->buffer.remove(0, nl + 1);
        if (line.trimmed().isEmpty())
            continue;
        QJsonParseError err;
        const QJsonDocument doc = QJsonDocument::fromJson(line, &err);
        if (!doc.isObject()) {
            c->send({{QStringLiteral("id"), QJsonValue::Null},
                     {QStringLiteral("error"), QJsonObject{{QStringLiteral("code"), protocol::InvalidRequest},
                                                           {QStringLiteral("message"), err.errorString()}}}});
            continue;
        }
        dispatch(c, doc.object());
    }
}

void Server::dispatch(Connection *c, const QJsonObject &request)
{
    const QJsonValue id = request.value(QLatin1String("id"));
    const QString method = request.value(QLatin1String("method")).toString();
    const QJsonObject params = request.value(QLatin1String("params")).toObject();
    QJsonObject reply{{QStringLiteral("id"), id}};

    // Re-identify on every call: a launched app may connect before
    // ActivityManager recorded its pid.
    if (m_identify && c->caller.package.isEmpty())
        m_identify(c->caller);

    c->caller.requestId = id;
    try {
        QJsonValue result;
        if (method == QLatin1String("system.subscribe")) {
            result = subscribe(c, params);
        } else {
            const qsizetype dot = method.indexOf(QLatin1Char('.'));
            Service *service = dot > 0 ? m_services.value(method.left(dot)) : nullptr;
            if (!service)
                throw RpcError{protocol::MethodNotFound, QStringLiteral("unknown method %1").arg(method)};
            result = service->handle(method.mid(dot + 1), params, c->caller);
        }
        if (result.isUndefined())
            return; // deferred: the service replies through PendingReply
        reply.insert(QStringLiteral("result"), result);
    } catch (const RpcError &e) {
        reply.insert(QStringLiteral("error"), QJsonObject{{QStringLiteral("code"), e.code},
                                                          {QStringLiteral("message"), e.message}});
        if (e.code == protocol::PermissionDenied)
            qCWarning(lcServer) << "denied" << method << "to uid" << c->caller.uid << c->caller.package;
    }
    if (!id.isUndefined() && !(id.isDouble() && id.toInt() == 0))
        c->send(reply);
}

bool Server::topicAllowed(const QString &topic, const Caller &caller)
{
    static const QHash<QString, QString> restricted{
        {QStringLiteral("notifications"), QLatin1String(permissions::MANAGE_NOTIFICATIONS)},
        {QStringLiteral("media"), QLatin1String(permissions::MEDIA_CONTROL)},
        {QStringLiteral("activity"), QString()},
        {QStringLiteral("lock"), QString()},
        {QStringLiteral("display"), QString()},
        {QStringLiteral("dialogs"), QString()},
        {QStringLiteral("alarms"), QLatin1String(permissions::ALARMS)},
        {QStringLiteral("contacts"), QLatin1String(permissions::CONTACTS)},
        {QStringLiteral("telephony"), QLatin1String(permissions::PHONE)},
        {QStringLiteral("developer"), QLatin1String(permissions::DEVELOPER)},
    };
    if (!restricted.contains(topic))
        return true;
    const QString perm = restricted.value(topic);
    return perm.isEmpty() ? caller.isSystem() : caller.can(perm);
}

QJsonValue Server::subscribe(Connection *c, const QJsonObject &params)
{
    QJsonArray accepted;
    for (const QJsonValue &v : params.value(QLatin1String("topics")).toArray()) {
        const QString topic = v.toString();
        if (topicAllowed(topic, c->caller)) {
            c->topics.insert(topic);
            accepted.append(topic);
        }
    }
    return accepted;
}

void Server::broadcast(const QString &event, const QJsonValue &data, const std::function<bool(const Caller &)> &filter)
{
    const QString topic = event.section(QLatin1Char('.'), 0, 0);
    const QJsonObject msg{{QStringLiteral("event"), event}, {QStringLiteral("data"), data}};
    for (Connection *c : std::as_const(m_connections))
        if (c->topics.contains(topic) && (!filter || filter(c->caller)))
            c->send(msg);
}

bool Server::hasSystemSubscriber(const QString &topic) const
{
    for (Connection *c : std::as_const(m_connections))
        if (c->caller.isSystem() && c->topics.contains(topic))
            return true;
    return false;
}

void Server::sendToPackage(const QString &package, const QString &event, const QJsonValue &data)
{
    const QJsonObject msg{{QStringLiteral("event"), event}, {QStringLiteral("data"), data}};
    for (Connection *c : std::as_const(m_connections))
        if (c->caller.package == package)
            c->send(msg);
}

} // namespace astrad
