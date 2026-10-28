// SPDX-License-Identifier: Apache-2.0
//
// adud - Astra Debugging Utility daemon.
//
// Runs when USB (or wireless) debugging is enabled in Developer options and
// serves the "adu" tool on a computer: shell, files, apps, logs, screenshots.
// See protocol.md.

#include "adud.h"

#include <astra/client.h>
#include <astra/paths.h>
#include <astra/properties.h>

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLoggingCategory>
#include <QMessageAuthenticationCode>
#include <QProcess>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QSocketNotifier>
#include <QTcpServer>
#include <QTcpSocket>
#include <QtEndian>

#include <csignal>
#include <fcntl.h>
#include <pty.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

Q_LOGGING_CATEGORY(lcAdu, "adud")

using astra::Client;
using astra::Paths;
using astra::Properties;

namespace adud {

namespace {
constexpr quint16 kPort = 5560;
constexpr int kMaxFrame = 4 * 1024 * 1024;
constexpr uid_t kShellUid = 2000;

QString keysPath()
{
    return Paths::resolve(QStringLiteral("/data/misc/adu/keys.json"));
}

QJsonObject loadKeys()
{
    QFile f(keysPath());
    return f.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(f.readAll()).object() : QJsonObject();
}

void storeKey(const QString &fingerprint, const QString &name, const QByteArray &secret)
{
    QJsonObject keys = loadKeys();
    keys.insert(fingerprint, QJsonObject{{QStringLiteral("name"), name},
                                         {QStringLiteral("secret"), QString::fromLatin1(secret.toHex())},
                                         {QStringLiteral("added"), double(QDateTime::currentMSecsSinceEpoch())}});
    QDir().mkpath(QFileInfo(keysPath()).absolutePath());
    QSaveFile f(keysPath());
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(keys).toJson());
        f.commit();
        QFile::setPermissions(keysPath(), QFile::ReadOwner | QFile::WriteOwner);
    }
}

QString fingerprintOf(const QByteArray &secret)
{
    return QString::fromLatin1(QCryptographicHash::hash(secret, QCryptographicHash::Sha256).toHex().left(32));
}

QString pretty(const QString &fp)
{
    QStringList parts;
    for (int i = 0; i < fp.size(); i += 2)
        parts << fp.mid(i, 2).toUpper();
    return parts.mid(0, 8).join(QLatin1Char(':'));
}

// Paths from the computer are device paths; relative ones start in /data/local/tmp.
QString devicePath(const QString &path)
{
    return Paths::resolve(path.startsWith(QLatin1Char('/')) ? path : QStringLiteral("/data/local/tmp/") + path);
}

bool rootShell()
{
    return Paths::isDevelopmentRoot() || Properties::get(QStringLiteral("ro.build.type")) != QLatin1String("user");
}
} // namespace

// ---------------------------------------------------------------------------

Session::Session(QTcpSocket *socket, QObject *parent)
    : QObject(parent)
    , m_socket(socket)
{
    socket->setParent(this);
    connect(socket, &QTcpSocket::readyRead, this, &Session::onReadyRead);
    connect(socket, &QTcpSocket::disconnected, this, &QObject::deleteLater);
}

Session::~Session()
{
    if (m_child > 0) {
        kill(m_child, SIGHUP);
        waitpid(m_child, nullptr, WNOHANG);
    }
    if (m_pty >= 0)
        close(m_pty);
    if (m_kmsg >= 0)
        close(m_kmsg);
    delete m_push;
}

void Session::send(quint8 type, const QByteArray &payload)
{
    QByteArray frame(5, Qt::Uninitialized);
    qToBigEndian<quint32>(quint32(payload.size() + 1), frame.data());
    frame[4] = char(type);
    m_socket->write(frame + payload);
}

void Session::sendJson(const QJsonObject &msg)
{
    send(Control, QJsonDocument(msg).toJson(QJsonDocument::Compact));
}

void Session::fail(const QString &error)
{
    sendJson({{QStringLiteral("ok"), false}, {QStringLiteral("error"), error}});
    m_socket->flush();
    m_socket->disconnectFromHost();
}

void Session::onReadyRead()
{
    m_buffer.append(m_socket->readAll());
    while (m_buffer.size() >= 5) {
        const quint32 len = qFromBigEndian<quint32>(m_buffer.constData());
        if (len == 0 || len > kMaxFrame) {
            m_socket->abort();
            return;
        }
        if (quint32(m_buffer.size()) < 4 + len)
            return;
        const quint8 type = quint8(m_buffer.at(4));
        const QByteArray payload = m_buffer.mid(5, int(len) - 1);
        m_buffer.remove(0, int(4 + len));
        handleFrame(type, payload);
    }
}

void Session::handleFrame(quint8 type, const QByteArray &payload)
{
    if (type == Control) {
        handleControl(QJsonDocument::fromJson(payload).object());
        return;
    }
    if (m_state == State::Shell && type == Data && m_pty >= 0) {
        if (write(m_pty, payload.constData(), size_t(payload.size())) < 0)
            qCWarning(lcAdu) << "pty write failed";
        return;
    }
    if (m_state == State::Push && m_push) {
        if (type == Data) {
            m_push->write(payload);
        } else if (type == End) {
            m_push->close();
            delete m_push;
            m_push = nullptr;
            sendJson({{QStringLiteral("ok"), true}, {QStringLiteral("path"), m_pushPath}});
            m_state = State::Ready;
        }
    }
}

void Session::handleControl(const QJsonObject &msg)
{
    const QString cmd = msg.value(QLatin1String("cmd")).toString();
    if (m_state == State::Hello) {
        if (cmd != QLatin1String("hello")) {
            fail(QStringLiteral("expected hello"));
            return;
        }
        m_name = msg.value(QLatin1String("name")).toString().left(64);
        m_fingerprint = msg.value(QLatin1String("id")).toString().left(64);
        m_nonce = QByteArray(16, Qt::Uninitialized);
        QRandomGenerator::system()->fillRange(reinterpret_cast<quint32 *>(m_nonce.data()), 4);
        m_state = State::Challenge;
        sendJson({{QStringLiteral("challenge"), QString::fromLatin1(m_nonce.toHex())},
                  {QStringLiteral("known"), loadKeys().contains(m_fingerprint)}});
        return;
    }
    if (m_state == State::Challenge) {
        if (cmd == QLatin1String("auth")) {
            const QByteArray secret = QByteArray::fromHex(loadKeys().value(m_fingerprint).toObject()
                                                              .value(QLatin1String("secret")).toString().toLatin1());
            const QByteArray mac = QMessageAuthenticationCode::hash(m_nonce, secret, QCryptographicHash::Sha256);
            if (secret.isEmpty() || mac.toHex() != msg.value(QLatin1String("mac")).toString().toLatin1()) {
                fail(QStringLiteral("unauthorized"));
                return;
            }
            m_state = State::Ready;
            sendJson({{QStringLiteral("ok"), true}});
            return;
        }
        if (cmd == QLatin1String("pair")) {
            const QByteArray secret = QByteArray::fromHex(msg.value(QLatin1String("secret")).toString().toLatin1());
            if (secret.size() < 16 || fingerprintOf(secret) != m_fingerprint) {
                fail(QStringLiteral("bad key"));
                return;
            }
            // The user decides on the phone.
            const QJsonObject dialog{
                {QStringLiteral("kind"), QStringLiteral("usb-debugging")},
                {QStringLiteral("title"), QStringLiteral("Allow debugging from this computer?")},
                {QStringLiteral("message"), QStringLiteral("%1\nKey fingerprint: %2").arg(m_name, pretty(m_fingerprint))},
                {QStringLiteral("icon"), QStringLiteral("code")},
                {QStringLiteral("details"), QJsonObject{{QStringLiteral("computer"), m_name},
                                                        {QStringLiteral("fingerprint"), pretty(m_fingerprint)}}},
                {QStringLiteral("buttons"), QJsonArray{
                     QJsonObject{{QStringLiteral("id"), QStringLiteral("deny")}, {QStringLiteral("label"), QStringLiteral("Deny")},
                                 {QStringLiteral("style"), QStringLiteral("secondary")}},
                     QJsonObject{{QStringLiteral("id"), QStringLiteral("allow")}, {QStringLiteral("label"), QStringLiteral("Allow")},
                                 {QStringLiteral("style"), QStringLiteral("primary")}}}},
            };
            sendJson({{QStringLiteral("waiting"), QStringLiteral("Confirm on the phone")}});
            QPointer<Session> self(this);
            Client::instance()->call(QStringLiteral("dialogs.show"), dialog, [self, secret](const QJsonValue &r, const QString &) {
                if (!self)
                    return;
                if (r.toString() != QLatin1String("allow")) {
                    self->fail(QStringLiteral("unauthorized"));
                    return;
                }
                storeKey(self->m_fingerprint, self->m_name, secret);
                self->m_state = State::Ready;
                self->sendJson({{QStringLiteral("ok"), true}});
            });
            return;
        }
        fail(QStringLiteral("expected auth or pair"));
        return;
    }
    if (m_state == State::Shell && msg.contains(QLatin1String("resize")) && m_pty >= 0) {
        const QJsonObject r = msg.value(QLatin1String("resize")).toObject();
        struct winsize ws {};
        ws.ws_col = ushort(r.value(QLatin1String("cols")).toInt(80));
        ws.ws_row = ushort(r.value(QLatin1String("rows")).toInt(24));
        ioctl(m_pty, TIOCSWINSZ, &ws);
        return;
    }
    if (m_state == State::Ready)
        handleCommand(msg);
}

void Session::handleCommand(const QJsonObject &msg)
{
    const QString cmd = msg.value(QLatin1String("cmd")).toString();
    QPointer<Session> self(this);
    auto relay = [self](const QJsonValue &r, const QString &error) {
        if (!self)
            return;
        if (error.isEmpty())
            self->sendJson({{QStringLiteral("ok"), true}, {QStringLiteral("result"), r}});
        else
            self->sendJson({{QStringLiteral("ok"), false}, {QStringLiteral("error"), error}});
    };

    if (cmd == QLatin1String("info")) {
        Client::instance()->call(QStringLiteral("system.info"), {}, relay);
    } else if (cmd == QLatin1String("packages")) {
        Client::instance()->call(QStringLiteral("packages.list"), {}, relay);
    } else if (cmd == QLatin1String("install")) {
        Client::instance()->call(QStringLiteral("packages.install"), {{QStringLiteral("path"), devicePath(msg.value(QLatin1String("path")).toString())}}, relay);
    } else if (cmd == QLatin1String("uninstall")) {
        Client::instance()->call(QStringLiteral("packages.uninstall"),
                                 {{QStringLiteral("package"), msg.value(QLatin1String("package"))}}, relay);
    } else if (cmd == QLatin1String("start")) {
        Client::instance()->call(QStringLiteral("activity.start"),
                                 {{QStringLiteral("package"), msg.value(QLatin1String("package"))}}, relay);
    } else if (cmd == QLatin1String("reboot")) {
        const QString target = msg.value(QLatin1String("target")).toString();
        Client::instance()->call(QStringLiteral("system.power"),
                                 {{QStringLiteral("action"), target.isEmpty() ? QStringLiteral("reboot") : target}}, relay);
    } else if (cmd == QLatin1String("screenshot")) {
        const QString path = Paths::resolve(QStringLiteral("/data/local/tmp/adu-screenshot.png"));
        QDir().mkpath(QFileInfo(path).absolutePath());
        Client::instance()->call(QStringLiteral("system.screenshot"), {{QStringLiteral("path"), path}},
                                 [self, path](const QJsonValue &, const QString &error) {
                                     if (!self)
                                         return;
                                     if (!error.isEmpty())
                                         self->fail(error);
                                     else
                                         self->sendFile(path);
                                 });
    } else if (cmd == QLatin1String("pull")) {
        sendFile(devicePath(msg.value(QLatin1String("path")).toString()));
    } else if (cmd == QLatin1String("push")) {
        m_pushPath = devicePath(msg.value(QLatin1String("path")).toString());
        QDir().mkpath(QFileInfo(m_pushPath).absolutePath());
        m_push = new QFile(m_pushPath);
        if (!m_push->open(QIODevice::WriteOnly)) {
            const QString error = m_push->errorString();
            delete m_push;
            m_push = nullptr;
            fail(error);
            return;
        }
        if (msg.contains(QLatin1String("mode")))
            chmod(QFile::encodeName(m_pushPath).constData(), mode_t(msg.value(QLatin1String("mode")).toInt(0644)));
        m_state = State::Push;
        sendJson({{QStringLiteral("ready"), true}});
    } else if (cmd == QLatin1String("shell")) {
        startShell(msg);
    } else if (cmd == QLatin1String("logcat")) {
        startLogcat();
    } else {
        fail(QStringLiteral("unknown command %1").arg(cmd));
    }
}

void Session::sendFile(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        fail(f.errorString());
        return;
    }
    sendJson({{QStringLiteral("size"), double(f.size())}});
    while (!f.atEnd())
        send(Data, f.read(64 * 1024));
    send(End, {});
}

void Session::startShell(const QJsonObject &msg)
{
    struct winsize ws {};
    ws.ws_col = ushort(msg.value(QLatin1String("cols")).toInt(80));
    ws.ws_row = ushort(msg.value(QLatin1String("rows")).toInt(24));
    const QByteArray command = msg.value(QLatin1String("command")).toString().toUtf8();
    QByteArray shell = QFile::encodeName(Paths::resolve(QStringLiteral("/system/bin/sh")));
    if (!QFileInfo::exists(QString::fromLocal8Bit(shell)))
        shell = "/bin/sh";
    const QByteArray home = QFile::encodeName(Paths::resolve(QStringLiteral("/data/local/tmp")));
    QDir().mkpath(QString::fromLocal8Bit(home));
    const bool root = rootShell() || geteuid() != 0;
    // Without a terminal on the computer (pipes, scripts) the pty must not
    // echo input or rewrite line endings.
    const bool tty = msg.value(QLatin1String("tty")).toBool(true);

    const pid_t pid = forkpty(&m_pty, nullptr, nullptr, &ws);
    if (pid < 0) {
        fail(QStringLiteral("cannot allocate a terminal"));
        return;
    }
    if (pid == 0) {
        if (!root && geteuid() == 0 && (setgid(kShellUid) != 0 || setuid(kShellUid) != 0))
            _exit(126);
        if (!tty) {
            struct termios t {};
            tcgetattr(STDIN_FILENO, &t);
            t.c_lflag &= ~tcflag_t(ECHO | ECHOE | ECHOK | ECHONL);
            t.c_oflag &= ~tcflag_t(ONLCR);
            tcsetattr(STDIN_FILENO, TCSANOW, &t);
        }
        setenv("TERM", tty ? "xterm-256color" : "dumb", 1);
        setenv("HOME", home.constData(), 1);
        setenv("PATH", "/system/bin:/vendor/bin:/bin:/usr/bin", 1);
        setenv("PS1", !tty ? "" : root ? "astra:\\w # " : "astra:\\w $ ", 1);
        setenv("PS2", tty ? "> " : "", 1);
        if (chdir(home.constData()) != 0)
            (void)!chdir("/");
        if (command.isEmpty())
            execl(shell.constData(), "sh", tty ? "-l" : "-s", static_cast<char *>(nullptr));
        else
            execl(shell.constData(), "sh", "-c", command.constData(), static_cast<char *>(nullptr));
        _exit(127);
    }
    m_child = pid;
    m_state = State::Shell;
    fcntl(m_pty, F_SETFL, fcntl(m_pty, F_GETFL) | O_NONBLOCK);
    sendJson({{QStringLiteral("ok"), true}});
    m_ptyNotifier = new QSocketNotifier(m_pty, QSocketNotifier::Read, this);
    connect(m_ptyNotifier, &QSocketNotifier::activated, this, [this] {
        char buf[16384];
        const ssize_t n = read(m_pty, buf, sizeof(buf));
        if (n > 0) {
            send(Data, QByteArray(buf, int(n)));
            return;
        }
        if (n < 0 && errno == EAGAIN)
            return;
        // EOF / EIO: the shell exited.
        m_ptyNotifier->setEnabled(false);
        int status = 0;
        waitpid(m_child, &status, 0);
        m_child = -1;
        send(End, {});
        sendJson({{QStringLiteral("exit"), WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status)}});
        m_socket->flush();
        m_socket->disconnectFromHost();
    });
}

void Session::startLogcat()
{
    m_kmsg = open("/dev/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (m_kmsg < 0) {
        fail(QStringLiteral("cannot read the kernel log: %1").arg(QString::fromLocal8Bit(strerror(errno))));
        return;
    }
    m_state = State::Logcat;
    sendJson({{QStringLiteral("ok"), true}});
    m_kmsgNotifier = new QSocketNotifier(m_kmsg, QSocketNotifier::Read, this);
    connect(m_kmsgNotifier, &QSocketNotifier::activated, this, [this] {
        char buf[8192];
        for (;;) {
            const ssize_t n = read(m_kmsg, buf, sizeof(buf) - 1);
            if (n <= 0)
                break;
            // "prio,seq,usec,flags;message"
            const QByteArray rec(buf, int(n));
            const int semi = rec.indexOf(';');
            const QList<QByteArray> head = rec.left(semi).split(',');
            const double secs = head.value(2).toDouble() / 1e6;
            send(Data, "[" + QByteArray::number(secs, 'f', 3).rightJustified(12) + "] " + rec.mid(semi + 1));
        }
    });
}

// ---------------------------------------------------------------------------

Daemon::Daemon(QObject *parent)
    : QObject(parent)
    , m_server(new QTcpServer(this))
{
    connect(m_server, &QTcpServer::newConnection, this, [this] {
        while (QTcpSocket *s = m_server->nextPendingConnection()) {
            qCInfo(lcAdu) << "connection from" << s->peerAddress().toString();
            new Session(s, this);
        }
    });
}

bool Daemon::start()
{
    // Over USB only the gadget interface is reachable; wireless debugging
    // listens everywhere. Development trees listen on loopback.
    QHostAddress address = QHostAddress::Any;
    if (Paths::isDevelopmentRoot())
        address = QHostAddress::LocalHost;
    if (!Paths::isDevelopmentRoot()) {
        QProcess::execute(QStringLiteral("/system/bin/sh"), {QStringLiteral("/system/etc/adu/usb-gadget.sh"), QStringLiteral("start")});
    }
    if (!m_server->listen(address, kPort)) {
        qCCritical(lcAdu) << "cannot listen on port" << kPort << m_server->errorString();
        return false;
    }
    qCInfo(lcAdu) << "listening on" << address.toString() << kPort;
    return true;
}

void Daemon::stop()
{
    m_server->close();
    if (!Paths::isDevelopmentRoot())
        QProcess::execute(QStringLiteral("/system/bin/sh"), {QStringLiteral("/system/etc/adu/usb-gadget.sh"), QStringLiteral("stop")});
}

} // namespace adud

static int g_signalPipe[2];

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("adud"));
    std::signal(SIGPIPE, SIG_IGN);
    std::signal(SIGCHLD, SIG_DFL);

    adud::Daemon daemon;
    if (!daemon.start())
        return 1;
    if (pipe(g_signalPipe) == 0) {
        std::signal(SIGTERM, [](int) { (void)!write(g_signalPipe[1], "x", 1); });
        auto *n = new QSocketNotifier(g_signalPipe[0], QSocketNotifier::Read, &app);
        QObject::connect(n, &QSocketNotifier::activated, &app, [&daemon, &app] {
            daemon.stop();
            app.quit();
        });
    }
    return app.exec();
}
