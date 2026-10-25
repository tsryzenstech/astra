// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "global.h"

#include <QHash>
#include <QJsonObject>
#include <QJsonValue>
#include <QObject>
#include <QStringList>
#include <QTimer>

#include <functional>

class QLocalSocket;

namespace astra {

// Connection to astrad, the astraOS system server. One per process.
class ASTRA_EXPORT Client : public QObject
{
    Q_OBJECT
public:
    using Callback = std::function<void(const QJsonValue &result, const QString &error)>;

    static Client *instance();

    bool isConnected() const;

    // Asynchronous call; requests issued while disconnected are queued.
    void call(const QString &method, const QJsonObject &params = {}, Callback callback = {});

    // Blocking call, meant for start-up code only.
    QJsonValue callSync(const QString &method, const QJsonObject &params = {},
                        QString *error = nullptr, int timeoutMs = 3000);

    // Topics survive reconnects (astrad restarts are transparent to clients).
    void subscribe(const QStringList &topics);

Q_SIGNALS:
    void connectedChanged(bool connected);
    void event(const QString &name, const QJsonValue &data);

private:
    explicit Client(QObject *parent = nullptr);
    void connectToServer();
    void onReadyRead();
    void processLine(const QByteArray &line);
    void flushQueue();

    QLocalSocket *m_socket;
    QTimer m_reconnect;
    QByteArray m_buffer;
    QList<QByteArray> m_queue;
    QHash<int, Callback> m_pending;
    QHash<int, QJsonObject> m_syncReplies;
    QStringList m_topics;
    int m_nextId = 1;
};

} // namespace astra
