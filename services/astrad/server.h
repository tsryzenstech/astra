// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QHash>
#include <QJsonObject>
#include <QJsonValue>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QStringList>

#include <functional>
#include <sys/types.h>

class QLocalServer;
class QLocalSocket;

namespace astrad {

class Connection;

// Error raised by service handlers; becomes a JSON-RPC style error reply.
struct RpcError {
    int code;
    QString message;
};

// A reply sent later (e.g. after the user answered a permission prompt).
// Handlers that defer return Deferred from handle().
class PendingReply
{
public:
    PendingReply() = default;
    PendingReply(Connection *connection, const QJsonValue &id);
    void resolve(const QJsonValue &result) const;
    void reject(int code, const QString &message) const;
    bool isValid() const;

private:
    QPointer<Connection> m_connection;
    QJsonValue m_id;
};

inline const QJsonValue Deferred = QJsonValue(QJsonValue::Undefined);

// Who is calling. Identity always comes from the kernel (SO_PEERCRED).
struct Caller {
    uid_t uid = 0;
    pid_t pid = 0;
    QString package;         // empty for system components (SysBoard, daemons)
    QStringList permissions; // granted permissions of the package
    Connection *connection = nullptr;
    QJsonValue requestId;    // id of the request being handled

    bool isSystem() const { return package.isEmpty(); }
    bool can(const QString &permission) const { return isSystem() || permissions.contains(permission); }
    void require(const QString &permission) const;
    void requireSystem() const;
    PendingReply defer() const { return PendingReply(connection, requestId); }
};

class Service : public QObject
{
public:
    using QObject::QObject;
    virtual QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) = 0;
};

class Connection : public QObject
{
    Q_OBJECT
public:
    Connection(QLocalSocket *socket, QObject *parent);
    void send(const QJsonObject &message);

    QLocalSocket *socket;
    Caller caller;
    QSet<QString> topics;
    QByteArray buffer;
};

class Server : public QObject
{
    Q_OBJECT
public:
    // Maps a peer to its package (pid of a launched app first, then uid).
    using Identify = std::function<void(Caller &caller)>;

    explicit Server(QObject *parent = nullptr);
    bool listen(const QString &path);

    void registerService(const QString &prefix, Service *service);
    // A package's permissions changed: its open connections see them at once.
    void updatePermissions(const QString &package, const QStringList &permissions);
    void setIdentify(Identify identify) { m_identify = std::move(identify); }

    // Sends an event to every connection subscribed to its topic
    // (the part of the name before the first dot) that passes filter.
    void broadcast(const QString &event, const QJsonValue &data,
                   const std::function<bool(const Caller &)> &filter = {});
    // Sends an event to all connections of a package, subscribed or not.
    void sendToPackage(const QString &package, const QString &event, const QJsonValue &data);
    // True when a system component (SysBoard) listens to the topic.
    bool hasSystemSubscriber(const QString &topic) const;

Q_SIGNALS:
    void clientDisconnected(const Caller &caller);

private:
    void onNewConnection();
    void onReadyRead(Connection *connection);
    void dispatch(Connection *connection, const QJsonObject &request);
    QJsonValue subscribe(Connection *connection, const QJsonObject &params);
    static bool topicAllowed(const QString &topic, const Caller &caller);

    QLocalServer *m_server;
    QList<Connection *> m_connections;
    QHash<QString, Service *> m_services;
    Identify m_identify;
};

} // namespace astrad
