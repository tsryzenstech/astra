// SPDX-License-Identifier: Apache-2.0
#include "mail.h"

#include <QDateTime>
#include <QJSEngine>
#include <QRegularExpression>
#include <QStringDecoder>
#include <QUuid>

namespace astra::qml {

namespace {

QByteArray quote(const QString &s)
{
    QByteArray out = s.toUtf8();
    out.replace('\\', "\\\\").replace('"', "\\\"");
    return '"' + out + '"';
}

// IMAP folder names use a modified UTF-7 (RFC 3501 5.1.3).
QString decodeUtf7(const QByteArray &in)
{
    QString out;
    for (int i = 0; i < in.size(); ++i) {
        if (in[i] != '&') {
            out += QLatin1Char(in[i]);
            continue;
        }
        const int end = in.indexOf('-', i);
        if (end < 0)
            break;
        if (end == i + 1) {
            out += QLatin1Char('&');
        } else {
            QByteArray b64 = in.mid(i + 1, end - i - 1).replace(',', '/');
            const QByteArray raw = QByteArray::fromBase64(b64);
            for (int k = 0; k + 1 < raw.size(); k += 2)
                out += QChar(ushort((uchar(raw[k]) << 8) | uchar(raw[k + 1])));
        }
        i = end;
    }
    return out;
}

QByteArray encodeUtf7(const QString &in)
{
    QByteArray out;
    QByteArray pending;
    auto flush = [&] {
        if (pending.isEmpty())
            return;
        QByteArray b64 = pending.toBase64(QByteArray::OmitTrailingEquals);
        out += '&' + b64.replace('/', ',') + '-';
        pending.clear();
    };
    for (QChar c : in) {
        if (c.unicode() >= 0x20 && c.unicode() < 0x7f) {
            flush();
            out += c == QLatin1Char('&') ? QByteArray("&-") : QByteArray(1, char(c.unicode()));
        } else {
            pending += char(c.unicode() >> 8);
            pending += char(c.unicode() & 0xff);
        }
    }
    flush();
    return out;
}

QString decodeCharset(const QByteArray &data, const QByteArray &charset)
{
    QStringDecoder dec(charset.isEmpty() ? "UTF-8" : charset.constData());
    if (!dec.isValid())
        return QString::fromLatin1(data);
    return dec.decode(data);
}

QByteArray decodeQuotedPrintable(const QByteArray &in, bool header = false)
{
    QByteArray out;
    for (int i = 0; i < in.size(); ++i) {
        const char c = in[i];
        if (header && c == '_') {
            out += ' ';
        } else if (c == '=' && i + 2 < in.size() + 1) {
            if (in.mid(i + 1, 2) == "\r\n") { i += 2; continue; }
            if (in.mid(i + 1, 1) == "\n") { i += 1; continue; }
            bool ok = false;
            const int v = in.mid(i + 1, 2).toInt(&ok, 16);
            if (ok) { out += char(v); i += 2; } else { out += c; }
        } else {
            out += c;
        }
    }
    return out;
}

// "=?utf-8?B?...?=" encoded words in headers (RFC 2047).
QString decodeHeader(const QByteArray &raw)
{
    static const QRegularExpression word(QStringLiteral("=\\?([^?]+)\\?([bBqQ])\\?([^?]*)\\?="));
    const QString in = QString::fromLatin1(raw);
    QString out;
    qsizetype last = 0;
    auto it = word.globalMatch(in);
    while (it.hasNext()) {
        const auto m = it.next();
        const QString between = in.mid(last, m.capturedStart() - last);
        if (!between.trimmed().isEmpty() || last == 0)
            out += between;
        const QByteArray text = m.captured(3).toLatin1();
        const QByteArray bytes = m.captured(2).toUpper() == QLatin1String("B") ? QByteArray::fromBase64(text) : decodeQuotedPrintable(text, true);
        out += decodeCharset(bytes, m.captured(1).toLatin1());
        last = m.capturedEnd();
    }
    out += in.mid(last);
    // Headers without encoded words are often UTF-8 anyway.
    if (last == 0)
        return QString::fromUtf8(raw);
    return out;
}

QByteArray encodeHeader(const QString &s)
{
    for (QChar c : s)
        if (c.unicode() > 0x7e)
            return "=?UTF-8?B?" + s.toUtf8().toBase64() + "?=";
    return s.toUtf8();
}

QMap<QByteArray, QByteArray> parseHeaders(const QByteArray &block)
{
    QMap<QByteArray, QByteArray> h;
    QByteArray last;
    for (const QByteArray &line : block.split('\n')) {
        const QByteArray l = line.endsWith('\r') ? line.chopped(1) : line;
        if (l.isEmpty())
            continue;
        if ((l[0] == ' ' || l[0] == '\t') && !last.isEmpty()) {
            h[last] += ' ' + l.trimmed();
            continue;
        }
        const int colon = l.indexOf(':');
        if (colon <= 0)
            continue;
        last = l.left(colon).trimmed().toLower();
        h[last] = l.mid(colon + 1).trimmed();
    }
    return h;
}

QByteArray param(const QByteArray &header, const QByteArray &name)
{
    const QRegularExpression re(QStringLiteral("%1\\*?=\\s*\"?([^\";]+)\"?").arg(QString::fromLatin1(name)), QRegularExpression::CaseInsensitiveOption);
    const auto m = re.match(QString::fromLatin1(header));
    return m.hasMatch() ? m.captured(1).toLatin1() : QByteArray();
}

// The display name of "Name <a@b>" or the address itself.
QString displayName(const QString &from)
{
    static const QRegularExpression re(QStringLiteral("^\\s*\"?([^\"<]*)\"?\\s*<([^>]+)>"));
    const auto m = re.match(from);
    if (!m.hasMatch())
        return from.trimmed();
    return m.captured(1).trimmed().isEmpty() ? m.captured(2) : m.captured(1).trimmed();
}

struct Mime {
    QString text, html;
    QStringList attachments;
};

void walkMime(const QByteArray &entity, Mime &out, int depth = 0)
{
    int split = entity.indexOf("\r\n\r\n");
    int skip = 4;
    if (split < 0) { split = entity.indexOf("\n\n"); skip = 2; }
    const QByteArray head = split < 0 ? entity : entity.left(split);
    const QByteArray body = split < 0 ? QByteArray() : entity.mid(split + skip);
    const auto h = parseHeaders(head);
    const QByteArray type = h.value("content-type", "text/plain").toLower();
    if (type.startsWith("multipart/") && depth < 8) {
        const QByteArray boundary = "--" + param(h.value("content-type"), "boundary");
        if (boundary.size() > 2) {
            const QList<QByteArray> parts = body.split('\n');
            QByteArray part;
            bool inside = false;
            for (const QByteArray &line : parts) {
                const QByteArray l = line.endsWith('\r') ? line.chopped(1) : line;
                if (l.startsWith(boundary)) {
                    if (inside && !part.isEmpty())
                        walkMime(part, out, depth + 1);
                    part.clear();
                    inside = !l.startsWith(boundary + "--");
                    continue;
                }
                if (inside)
                    part += line + '\n';
            }
            return;
        }
    }
    const QByteArray enc = h.value("content-transfer-encoding").toLower().trimmed();
    QByteArray data = enc == "base64" ? QByteArray::fromBase64(QByteArray(body).replace("\r", "").replace("\n", ""))
                    : enc == "quoted-printable" ? decodeQuotedPrintable(body) : body;
    const QByteArray disposition = h.value("content-disposition").toLower();
    QByteArray filename = param(h.value("content-disposition"), "filename");
    if (filename.isEmpty())
        filename = param(h.value("content-type"), "name");
    if (disposition.startsWith("attachment") || (!filename.isEmpty() && !type.startsWith("text/"))) {
        out.attachments << decodeHeader(filename);
        return;
    }
    const QString decoded = decodeCharset(data, param(h.value("content-type"), "charset"));
    if (type.startsWith("text/html") && out.html.isEmpty())
        out.html = decoded;
    else if (type.startsWith("text/plain") && out.text.isEmpty())
        out.text = decoded;
}

// Literal content right after "{n}" at position pos of line.
QByteArray literalAt(const QByteArray &line, int brace)
{
    const int close = line.indexOf('}', brace);
    if (close < 0)
        return {};
    const int n = line.mid(brace + 1, close - brace - 1).toInt();
    return line.mid(close + 1, n);
}

} // namespace

MailClient::MailClient(QObject *parent)
    : QObject(parent)
{
}

void MailClient::configure(const QVariantMap &account)
{
    disconnectFromServer();
    m_account = account;
}

void MailClient::disconnectFromServer()
{
    if (m_imap) {
        m_imap->disconnect(this);
        m_imap->abort();
        m_imap->deleteLater();
        m_imap = nullptr;
    }
    m_state = State::Disconnected;
    m_selected.clear();
    m_buffer.clear();
    m_lines.clear();
    m_literalLeft = -1;
    if (m_current) {
        delete m_current;
        m_current = nullptr;
    }
}

void MailClient::reply(const QJSValue &callback, const QVariant &result, const QString &error)
{
    if (!error.isEmpty())
        m_lastError = error;
    Q_EMIT busyChanged();
    if (!callback.isCallable())
        return;
    QJSEngine *engine = qjsEngine(this);
    if (!engine)
        return;
    QJSValue cb = callback;
    cb.call({engine->toScriptValue(result), error.isEmpty() ? QJSValue(QJSValue::NullValue) : QJSValue(error)});
}

void MailClient::enqueue(const QByteArray &text, std::function<void(const QList<QByteArray> &, const QString &)> done)
{
    m_queue.enqueue({text, std::move(done)});
    Q_EMIT busyChanged();
    pump();
}

void MailClient::fail(const QString &error)
{
    m_lastError = error;
    const auto pending = std::exchange(m_queue, {});
    Command *current = std::exchange(m_current, nullptr);
    disconnectFromServer();
    if (current) {
        current->done({}, error);
        delete current;
    }
    for (const Command &c : pending)
        c.done({}, error);
    Q_EMIT busyChanged();
}

void MailClient::pump()
{
    if (m_current || m_queue.isEmpty())
        return;
    if (m_state == State::Disconnected) {
        const QString host = m_account.value(QStringLiteral("imapHost")).toString();
        if (host.isEmpty()) {
            fail(tr("Set up your mail account first"));
            return;
        }
        m_imap = new QSslSocket(this);
        connect(m_imap, &QSslSocket::readyRead, this, &MailClient::onReadyRead);
        connect(m_imap, &QSslSocket::errorOccurred, this, [this](QAbstractSocket::SocketError) {
            if (m_imap)
                fail(m_imap->errorString());
        });
        connect(m_imap, &QSslSocket::sslErrors, this, [this](const QList<QSslError> &errors) {
            fail(errors.isEmpty() ? tr("Secure connection failed") : errors.first().errorString());
        });
        m_state = State::Greeting;
        m_imap->connectToHostEncrypted(host, quint16(m_account.value(QStringLiteral("imapPort"), 993).toInt()));
        return;
    }
    if (m_state != State::Ready)
        return;
    m_current = new Command(m_queue.dequeue());
    m_tag = "a" + QByteArray::number(++m_counter);
    m_lines.clear();
    m_imap->write(m_tag + ' ' + m_current->text + "\r\n");
}

void MailClient::onReadyRead()
{
    m_buffer += m_imap->readAll();
    while (true) {
        if (m_literalLeft >= 0) {
            if (m_buffer.size() < m_literalLeft)
                return;
            m_lines.last() += m_buffer.left(m_literalLeft);
            m_buffer.remove(0, m_literalLeft);
            m_literalLeft = -1;
            // The rest of the line continues after the literal.
            const int nl = m_buffer.indexOf("\r\n");
            if (nl < 0) {
                m_literalLeft = -2; // waiting for the end of a continued line
                return;
            }
            const QByteArray tail = m_buffer.left(nl);
            m_buffer.remove(0, nl + 2);
            m_lines.last() += tail;
            static const QRegularExpression lit(QStringLiteral("\\{(\\d+)\\}$"));
            const auto m = lit.match(QString::fromLatin1(tail));
            if (m.hasMatch())
                m_literalLeft = m.captured(1).toLongLong();
            continue;
        }
        if (m_literalLeft == -2) {
            const int nl = m_buffer.indexOf("\r\n");
            if (nl < 0)
                return;
            m_lines.last() += m_buffer.left(nl);
            m_buffer.remove(0, nl + 2);
            m_literalLeft = -1;
            continue;
        }
        const int nl = m_buffer.indexOf("\r\n");
        if (nl < 0)
            return;
        const QByteArray line = m_buffer.left(nl);
        m_buffer.remove(0, nl + 2);

        if (m_state == State::Greeting) {
            if (!line.startsWith("* OK")) {
                fail(QString::fromUtf8(line));
                return;
            }
            m_state = State::LoggingIn;
            m_tag = "a" + QByteArray::number(++m_counter);
            m_imap->write(m_tag + " LOGIN " + quote(m_account.value(QStringLiteral("user")).toString()) + ' '
                          + quote(m_account.value(QStringLiteral("password")).toString()) + "\r\n");
            continue;
        }
        if (line.startsWith(m_tag + ' ')) {
            const QByteArray status = line.mid(m_tag.size() + 1);
            const QString error = status.startsWith("OK") ? QString() : QString::fromUtf8(status.mid(status.indexOf(' ') + 1));
            if (m_state == State::LoggingIn) {
                if (!error.isEmpty()) {
                    fail(tr("Sign-in failed: %1").arg(error));
                    return;
                }
                m_state = State::Ready;
                pump();
                continue;
            }
            Command *c = std::exchange(m_current, nullptr);
            const QList<QByteArray> lines = std::exchange(m_lines, {});
            if (c) {
                c->done(lines, error);
                delete c;
            }
            Q_EMIT busyChanged();
            pump();
            continue;
        }
        m_lines.append(line);
        static const QRegularExpression lit(QStringLiteral("\\{(\\d+)\\}$"));
        const auto m = lit.match(QString::fromLatin1(line));
        if (m.hasMatch())
            m_literalLeft = m.captured(1).toLongLong();
    }
}

void MailClient::select(const QString &folder, std::function<void(const QString &)> then)
{
    enqueue("SELECT " + quote(QString::fromLatin1(encodeUtf7(folder))), [this, folder, then](const QList<QByteArray> &lines, const QString &error) {
        if (error.isEmpty())
            m_selected = folder;
        int exists = 0;
        for (const QByteArray &l : lines)
            if (l.endsWith(" EXISTS"))
                exists = l.split(' ').value(1).toInt();
        m_exists = exists;
        then(error);
    });
}

void MailClient::folders(const QJSValue &callback)
{
    enqueue("LIST \"\" \"*\"", [this, callback](const QList<QByteArray> &lines, const QString &error) {
        QVariantList out;
        static const QRegularExpression re(QStringLiteral("^\\* LIST \\(([^)]*)\\) (NIL|\"(?:[^\"\\\\]|\\\\.)*\") (.+)$"));
        for (const QByteArray &l : lines) {
            const auto m = re.match(QString::fromLatin1(l));
            if (!m.hasMatch())
                continue;
            QByteArray name = m.captured(3).toLatin1();
            if (name.startsWith('{'))
                name = literalAt(name, 0);
            else if (name.startsWith('"'))
                name = name.mid(1, name.size() - 2).replace("\\\"", "\"").replace("\\\\", "\\");
            const QString flags = m.captured(1);
            if (flags.contains(QLatin1String("\\Noselect"), Qt::CaseInsensitive))
                continue;
            const QString path = decodeUtf7(name);
            QString special;
            for (const char *f : {"\\Inbox", "\\Sent", "\\Drafts", "\\Trash", "\\Junk", "\\Archive", "\\Flagged", "\\All"})
                if (flags.contains(QLatin1String(f), Qt::CaseInsensitive))
                    special = QString::fromLatin1(f + 1).toLower();
            if (path.compare(QLatin1String("INBOX"), Qt::CaseInsensitive) == 0)
                special = QStringLiteral("inbox");
            out.append(QVariantMap{{QStringLiteral("path"), path}, {QStringLiteral("name"), path.section(QRegularExpression(QStringLiteral("[/.]")), -1)},
                                   {QStringLiteral("special"), special}});
        }
        reply(callback, out, error);
    });
}

void MailClient::messages(const QString &folder, int count, const QJSValue &callback)
{
    select(folder, [this, count, callback](const QString &error) {
        const int exists = m_exists;
        if (!error.isEmpty() || exists == 0) {
            reply(callback, QVariantList(), error);
            return;
        }
        const int first = qMax(1, exists - qMax(1, count) + 1);
        enqueue("FETCH " + QByteArray::number(first) + ':' + QByteArray::number(exists)
                    + " (UID FLAGS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE CONTENT-TYPE)])",
                [this, callback](const QList<QByteArray> &lines, const QString &err) {
                    QVariantList out;
                    static const QRegularExpression uidRe(QStringLiteral("UID (\\d+)"));
                    static const QRegularExpression flagsRe(QStringLiteral("FLAGS \\(([^)]*)\\)"));
                    for (const QByteArray &l : lines) {
                        if (!l.contains(" FETCH "))
                            continue;
                        const int body = l.indexOf("BODY[HEADER.FIELDS");
                        const int brace = body < 0 ? -1 : l.indexOf('{', body);
                        const QByteArray headerBlock = brace < 0 ? QByteArray() : literalAt(l, brace);
                        // Look for UID/FLAGS outside the header literal.
                        const QByteArray meta = brace < 0 ? l : l.left(brace) + l.mid(l.indexOf('}', brace) + 1 + headerBlock.size());
                        const auto h = parseHeaders(headerBlock);
                        const QString flags = flagsRe.match(QString::fromLatin1(meta)).captured(1);
                        const QString from = decodeHeader(h.value("from"));
                        out.prepend(QVariantMap{
                            {QStringLiteral("uid"), uidRe.match(QString::fromLatin1(meta)).captured(1).toLongLong()},
                            {QStringLiteral("from"), displayName(from)},
                            {QStringLiteral("fromAddress"), from},
                            {QStringLiteral("subject"), decodeHeader(h.value("subject"))},
                            {QStringLiteral("date"), QDateTime::fromString(QString::fromLatin1(h.value("date")).section(QLatin1String(" ("), 0, 0), Qt::RFC2822Date).toMSecsSinceEpoch()},
                            {QStringLiteral("seen"), flags.contains(QLatin1String("\\Seen"), Qt::CaseInsensitive)},
                            {QStringLiteral("flagged"), flags.contains(QLatin1String("\\Flagged"), Qt::CaseInsensitive)},
                            {QStringLiteral("attachments"), h.value("content-type").toLower().startsWith("multipart/mixed")}});
                    }
                    reply(callback, out, err);
                });
    });
}

void MailClient::message(const QString &folder, qint64 uid, const QJSValue &callback)
{
    select(folder, [this, uid, callback](const QString &error) {
        if (!error.isEmpty()) {
            reply(callback, QVariant(), error);
            return;
        }
        enqueue("UID FETCH " + QByteArray::number(uid) + " (BODY.PEEK[])", [this, uid, callback](const QList<QByteArray> &lines, const QString &err) {
            QByteArray raw;
            for (const QByteArray &l : lines) {
                const int body = l.indexOf("BODY[]");
                const int brace = body < 0 ? -1 : l.indexOf('{', body);
                if (brace >= 0)
                    raw = literalAt(l, brace);
            }
            if (raw.isEmpty()) {
                reply(callback, QVariant(), err.isEmpty() ? tr("The message is not available") : err);
                return;
            }
            const int split = raw.indexOf("\r\n\r\n");
            const auto h = parseHeaders(raw.left(split < 0 ? raw.size() : split));
            Mime mime;
            walkMime(raw, mime);
            reply(callback, QVariantMap{
                {QStringLiteral("uid"), uid},
                {QStringLiteral("from"), decodeHeader(h.value("from"))},
                {QStringLiteral("to"), decodeHeader(h.value("to"))},
                {QStringLiteral("cc"), decodeHeader(h.value("cc"))},
                {QStringLiteral("subject"), decodeHeader(h.value("subject"))},
                {QStringLiteral("messageId"), QString::fromLatin1(h.value("message-id"))},
                {QStringLiteral("date"), QDateTime::fromString(QString::fromLatin1(h.value("date")).section(QLatin1String(" ("), 0, 0), Qt::RFC2822Date).toMSecsSinceEpoch()},
                {QStringLiteral("text"), mime.text},
                {QStringLiteral("html"), mime.html},
                {QStringLiteral("attachments"), mime.attachments}}, QString());
            enqueue("UID STORE " + QByteArray::number(uid) + " +FLAGS (\\Seen)", [](const QList<QByteArray> &, const QString &) {});
        });
    });
}

void MailClient::setFlag(const QString &folder, qint64 uid, const QString &flag, bool on, const QJSValue &callback)
{
    select(folder, [this, uid, flag, on, callback](const QString &error) {
        if (!error.isEmpty()) {
            reply(callback, false, error);
            return;
        }
        enqueue("UID STORE " + QByteArray::number(uid) + (on ? " +FLAGS (" : " -FLAGS (") + flag.toLatin1() + ')',
                [this, callback](const QList<QByteArray> &, const QString &err) { reply(callback, err.isEmpty(), err); });
    });
}

void MailClient::move(const QString &folder, qint64 uid, const QString &target, const QJSValue &callback)
{
    select(folder, [this, uid, target, callback](const QString &error) {
        if (!error.isEmpty()) {
            reply(callback, false, error);
            return;
        }
        const QByteArray id = QByteArray::number(uid);
        const QByteArray to = quote(QString::fromLatin1(encodeUtf7(target)));
        enqueue("UID MOVE " + id + ' ' + to, [this, id, to, callback](const QList<QByteArray> &, const QString &err) {
            if (err.isEmpty()) {
                reply(callback, true, QString());
                return;
            }
            // Servers without MOVE: copy, mark deleted, expunge.
            enqueue("UID COPY " + id + ' ' + to, [this, id, callback](const QList<QByteArray> &, const QString &copyErr) {
                if (!copyErr.isEmpty()) {
                    reply(callback, false, copyErr);
                    return;
                }
                enqueue("UID STORE " + id + " +FLAGS (\\Deleted)", [](const QList<QByteArray> &, const QString &) {});
                enqueue("EXPUNGE", [this, callback](const QList<QByteArray> &, const QString &e) { reply(callback, e.isEmpty(), e); });
            });
        });
    });
}

void MailClient::remove(const QString &folder, qint64 uid, const QJSValue &callback)
{
    select(folder, [this, uid, callback](const QString &error) {
        if (!error.isEmpty()) {
            reply(callback, false, error);
            return;
        }
        enqueue("UID STORE " + QByteArray::number(uid) + " +FLAGS (\\Deleted)", [](const QList<QByteArray> &, const QString &) {});
        enqueue("EXPUNGE", [this, callback](const QList<QByteArray> &, const QString &e) { reply(callback, e.isEmpty(), e); });
    });
}

// SMTP: a small state machine over its own connection.
void MailClient::send(const QVariantMap &mail, const QJSValue &callback)
{
    const QString host = m_account.value(QStringLiteral("smtpHost")).toString();
    const int port = m_account.value(QStringLiteral("smtpPort"), 465).toInt();
    if (host.isEmpty()) {
        reply(callback, false, tr("Set up your mail account first"));
        return;
    }
    const QString address = m_account.value(QStringLiteral("address")).toString();
    QStringList rcpt;
    static const QRegularExpression addr(QStringLiteral("[^\\s<>,;\"]+@[^\\s<>,;\"]+"));
    for (const QString &field : {mail.value(QStringLiteral("to")).toString(), mail.value(QStringLiteral("cc")).toString()}) {
        auto it = addr.globalMatch(field);
        while (it.hasNext())
            rcpt << it.next().captured(0);
    }
    if (rcpt.isEmpty()) {
        reply(callback, false, tr("Add at least one recipient"));
        return;
    }
    QByteArray body = mail.value(QStringLiteral("text")).toString().toUtf8().toBase64();
    QByteArray wrapped;
    for (int i = 0; i < body.size(); i += 76)
        wrapped += body.mid(i, 76) + "\r\n";
    const QString domain = address.section(QLatin1Char('@'), 1);
    QByteArray message = "From: " + encodeHeader(m_account.value(QStringLiteral("name")).toString()) + " <" + address.toUtf8() + ">\r\n"
        + "To: " + mail.value(QStringLiteral("to")).toString().toUtf8() + "\r\n"
        + (mail.value(QStringLiteral("cc")).toString().isEmpty() ? QByteArray() : "Cc: " + mail.value(QStringLiteral("cc")).toString().toUtf8() + "\r\n")
        + "Subject: " + encodeHeader(mail.value(QStringLiteral("subject")).toString()) + "\r\n"
        + "Date: " + QDateTime::currentDateTime().toString(Qt::RFC2822Date).toLatin1() + "\r\n"
        + "Message-ID: <" + QUuid::createUuid().toString(QUuid::WithoutBraces).toLatin1() + '@' + domain.toLatin1() + ">\r\n"
        + (mail.value(QStringLiteral("inReplyTo")).toString().isEmpty() ? QByteArray()
              : "In-Reply-To: " + mail.value(QStringLiteral("inReplyTo")).toString().toLatin1() + "\r\nReferences: " + mail.value(QStringLiteral("inReplyTo")).toString().toLatin1() + "\r\n")
        + "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n"
        + "User-Agent: astraOS Mail\r\n\r\n" + wrapped;

    // Steps: the command to send once the previous reply had the expected code.
    struct Step { QByteArray command; QByteArray expect; };
    QList<Step> steps;
    const bool startTls = port != 465;
    steps << Step{"", "220"} << Step{"EHLO astraos", "250"};
    if (startTls)
        steps << Step{"STARTTLS", "220"} << Step{"EHLO astraos", "250"};
    const QByteArray auth = QByteArray('\0' + m_account.value(QStringLiteral("user")).toString().toUtf8() + '\0' + m_account.value(QStringLiteral("password")).toString().toUtf8()).toBase64();
    steps << Step{"AUTH PLAIN " + auth, "235"} << Step{"MAIL FROM:<" + address.toUtf8() + ">", "250"};
    for (const QString &r : rcpt)
        steps << Step{"RCPT TO:<" + r.toUtf8() + ">", "25"};
    steps << Step{"DATA", "354"} << Step{message + "\r\n.", "250"} << Step{"QUIT", "221"};

    auto *smtp = new QSslSocket(this);
    auto state = std::make_shared<std::pair<int, QByteArray>>(0, QByteArray()); // step index, buffer
    auto done = std::make_shared<bool>(false);
    auto finish = [this, smtp, callback, done](const QString &error) {
        if (*done)
            return;
        *done = true;
        smtp->disconnect(this);
        smtp->deleteLater();
        reply(callback, error.isEmpty(), error);
    };
    connect(smtp, &QSslSocket::readyRead, this, [smtp, steps, state, finish, startTls]() {
        state->second += smtp->readAll();
        while (true) {
            const int nl = state->second.indexOf("\r\n");
            if (nl < 0)
                return;
            const QByteArray line = state->second.left(nl);
            state->second.remove(0, nl + 2);
            if (line.size() > 3 && line[3] == '-')
                continue; // multi-line reply
            const Step &step = steps.at(state->first);
            if (!line.startsWith(step.expect)) {
                finish(QString::fromUtf8(line.mid(4)));
                return;
            }
            if (step.command == "STARTTLS" && startTls)
                smtp->startClientEncryption();
            if (++state->first >= steps.size()) {
                finish(QString());
                return;
            }
            smtp->write(steps.at(state->first).command + "\r\n");
            // after QUIT the server closes; after "." wait for 250
        }
    });
    connect(smtp, &QSslSocket::errorOccurred, this, [smtp, finish](QAbstractSocket::SocketError e) {
        if (e != QAbstractSocket::RemoteHostClosedError)
            finish(smtp->errorString());
    });
    if (startTls)
        smtp->connectToHost(host, quint16(port));
    else
        smtp->connectToHostEncrypted(host, quint16(port));
    Q_EMIT busyChanged();
}

} // namespace astra::qml
