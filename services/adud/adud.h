// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QObject>
#include <QPointer>

class QTcpServer;
class QTcpSocket;
class QSocketNotifier;
class QFile;

namespace adud {

enum FrameType : quint8 { Control = 1, Data = 2, Stderr = 3, End = 4 };

// One client connection (see protocol.md).
class Session : public QObject
{
    Q_OBJECT
public:
    Session(QTcpSocket *socket, QObject *parent);
    ~Session() override;

private:
    void onReadyRead();
    void handleFrame(quint8 type, const QByteArray &payload);
    void handleControl(const QJsonObject &msg);
    void handleCommand(const QJsonObject &msg);
    void send(quint8 type, const QByteArray &payload);
    void sendJson(const QJsonObject &msg);
    void fail(const QString &error);

    void startShell(const QJsonObject &msg);
    void startLogcat();
    void sendFile(const QString &path);

    QTcpSocket *m_socket;
    QByteArray m_buffer;
    enum class State { Hello, Challenge, Ready, Shell, Push, Logcat } m_state = State::Hello;
    QByteArray m_nonce;
    QString m_fingerprint;
    QString m_name;

    int m_pty = -1;
    pid_t m_child = -1;
    QSocketNotifier *m_ptyNotifier = nullptr;
    QFile *m_push = nullptr;
    QString m_pushPath;
    int m_kmsg = -1;
    QSocketNotifier *m_kmsgNotifier = nullptr;
};

class Daemon : public QObject
{
    Q_OBJECT
public:
    explicit Daemon(QObject *parent = nullptr);
    bool start();
    void stop();

private:
    QTcpServer *m_server;
};

} // namespace adud
