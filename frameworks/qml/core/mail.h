// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QJSValue>
#include <QObject>
#include <QPointer>
#include <QQueue>
#include <QSslSocket>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <functional>

namespace astra::qml {

// E-mail for the Mail app: IMAP over TLS (port 993) to read, SMTP over TLS
// (465) or STARTTLS (587) to send. One IMAP connection, commands in order.
//
//   MailClient { id: mail }
//   mail.configure({ imapHost, imapPort, smtpHost, smtpPort, user, password, name, address })
//   mail.folders(cb)                      cb([{ name, path, flags }], error)
//   mail.messages(folder, count, cb)      newest first: [{ uid, from, subject, date, seen, flagged, attachments }]
//   mail.message(folder, uid, cb)         { uid, from, to, cc, subject, date, text, html, attachments: [names] }
//   mail.setFlag(folder, uid, flag, on, cb)   flag: "\\Seen" | "\\Flagged"
//   mail.move(folder, uid, target, cb)    mail.remove(folder, uid, cb)
//   mail.send({ to, cc, subject, text, inReplyTo }, cb)
class MailClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY busyChanged)
public:
    explicit MailClient(QObject *parent = nullptr);

    bool busy() const { return m_current != nullptr || !m_queue.isEmpty(); }
    QString lastError() const { return m_lastError; }

    Q_INVOKABLE void configure(const QVariantMap &account);
    Q_INVOKABLE void folders(const QJSValue &callback);
    Q_INVOKABLE void messages(const QString &folder, int count, const QJSValue &callback);
    Q_INVOKABLE void message(const QString &folder, qint64 uid, const QJSValue &callback);
    Q_INVOKABLE void setFlag(const QString &folder, qint64 uid, const QString &flag, bool on, const QJSValue &callback);
    Q_INVOKABLE void move(const QString &folder, qint64 uid, const QString &target, const QJSValue &callback);
    Q_INVOKABLE void remove(const QString &folder, qint64 uid, const QJSValue &callback);
    Q_INVOKABLE void send(const QVariantMap &mail, const QJSValue &callback);
    Q_INVOKABLE void disconnectFromServer();

Q_SIGNALS:
    void busyChanged();

private:
    // One IMAP command; the response is the untagged lines plus literals.
    struct Command {
        QByteArray text;                                    // without tag
        std::function<void(const QList<QByteArray> &lines, const QString &error)> done;
    };
    void enqueue(const QByteArray &text, std::function<void(const QList<QByteArray> &, const QString &)> done);
    void select(const QString &folder, std::function<void(const QString &error)> then);
    void pump();
    void onReadyRead();
    void fail(const QString &error);
    void reply(const QJSValue &callback, const QVariant &result, const QString &error);

    QVariantMap m_account;
    QSslSocket *m_imap = nullptr;
    enum class State { Disconnected, Connecting, Greeting, LoggingIn, Ready } m_state = State::Disconnected;
    QQueue<Command> m_queue;
    Command *m_current = nullptr;
    QByteArray m_tag;
    int m_counter = 0;
    QByteArray m_buffer;
    QList<QByteArray> m_lines;          // response lines, literals joined in
    qint64 m_literalLeft = -1;          // bytes of a literal still to read
    QString m_selected;
    int m_exists = 0;                   // messages in the selected folder
    QString m_lastError;
};

} // namespace astra::qml
