// SPDX-License-Identifier: Apache-2.0
#include "terminalservice.h"
#include "permissions.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QFileInfo>
#include <QLoggingCategory>
#include <QSocketNotifier>

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <grp.h>
#include <pty.h>
#include <pwd.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

Q_LOGGING_CATEGORY(lcTerm, "astrad.terminal")

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s) { return QString::fromLatin1(s); }

// The user the shell runs as: the owner of the shared storage (the home directory of the one user of the computer).
// In a development tree, whoever runs astrad.
const passwd *shellUser()
{
    if (Paths::isDevelopmentRoot())
        return getpwuid(geteuid());
    struct stat st {};
    const QByteArray media = QFile::encodeName(QFileInfo(Paths::userMedia()).canonicalFilePath());
    if (!media.isEmpty() && ::stat(media.constData(), &st) == 0 && st.st_uid != 0)
        return getpwuid(st.st_uid);
    return nullptr;
}
} // namespace

TerminalService::TerminalService(Server *server, QObject *parent)
    : Service(parent)
    , m_server(server)
{
}

TerminalService::~TerminalService()
{
    const QList<int> ids = m_sessions.keys();
    for (int id : ids)
        closeSession(id, true);
}

void TerminalService::closeSession(int id, bool kill)
{
    const auto it = m_sessions.find(id);
    if (it == m_sessions.end())
        return;
    Session s = it.value();
    m_sessions.erase(it);
    delete s.notifier;
    if (s.fd >= 0)
        ::close(s.fd);
    if (s.pid > 0) {
        if (kill)
            ::kill(s.pid, SIGHUP);
        int status = 0;
        ::waitpid(s.pid, &status, WNOHANG);
    }
}

QJsonValue TerminalService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    caller.require(QLatin1String(permissions::TERMINAL));
    if (call == QLatin1String("open")) {
        const passwd *pw = shellUser();
        if (!pw)
            throw RpcError{protocol::Failed, K("There is no user to open a shell for")};
        winsize ws{};
        ws.ws_col = ushort(qBound(10, params.value(K("cols")).toInt(80), 500));
        ws.ws_row = ushort(qBound(2, params.value(K("rows")).toInt(24), 300));
        const uid_t uid = pw->pw_uid;
        const gid_t gid = pw->pw_gid;
        const QByteArray home = pw->pw_dir, name = pw->pw_name;
        QByteArray shell = pw->pw_shell && *pw->pw_shell && !QByteArray(pw->pw_shell).endsWith("nologin") && !QByteArray(pw->pw_shell).endsWith("/false")
                               ? QByteArray(pw->pw_shell) : QByteArray("/bin/bash");
        int master = -1;
        const pid_t pid = ::forkpty(&master, nullptr, nullptr, &ws);
        if (pid < 0)
            throw RpcError{protocol::Failed, K("cannot open a terminal")};
        if (pid == 0) {
            // The child: the user, the environment, the shell.
            if (geteuid() == 0) {
                if (initgroups(name.constData(), gid) != 0 || setgid(gid) != 0 || setuid(uid) != 0)
                    _exit(126);
            }
            setenv("HOME", home.constData(), 1);
            setenv("USER", name.constData(), 1);
            setenv("LOGNAME", name.constData(), 1);
            setenv("SHELL", shell.constData(), 1);
            setenv("TERM", "xterm-256color", 1);
            setenv("COLORTERM", "truecolor", 1);
            setenv("LANG", "C.UTF-8", 0);
            unsetenv("ASTRA_ROOT");
            if (chdir(home.constData()) != 0)
                (void)!chdir("/");
            const char *argv0 = strrchr(shell.constData(), '/');
            const QByteArray login = QByteArray("-") + (argv0 ? argv0 + 1 : shell.constData());
            execl(shell.constData(), login.constData(), static_cast<char *>(nullptr));
            _exit(127);
        }
        fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK);
        fcntl(master, F_SETFD, FD_CLOEXEC);
        Session s;
        s.id = m_next++;
        s.fd = master;
        s.pid = pid;
        s.owner = caller.package;
        s.notifier = new QSocketNotifier(master, QSocketNotifier::Read, this);
        const int id = s.id;
        connect(s.notifier, &QSocketNotifier::activated, this, [this, id] {
            const auto it = m_sessions.find(id);
            if (it == m_sessions.end())
                return;
            char buf[16384];
            for (;;) {
                const ssize_t n = ::read(it->fd, buf, sizeof(buf));
                if (n > 0) {
                    m_server->broadcast(K("terminal.data"), QJsonObject{{K("id"), id}, {K("data"), QString::fromLatin1(QByteArray(buf, int(n)).toBase64())}},
                                        [](const Caller &c) { return c.can(QLatin1String(permissions::TERMINAL)); });
                    continue;
                }
                if (n < 0 && (errno == EAGAIN || errno == EINTR))
                    return;
                // EOF or EIO: the shell ended.
                m_server->broadcast(K("terminal.exit"), QJsonObject{{K("id"), id}},
                                    [](const Caller &c) { return c.can(QLatin1String(permissions::TERMINAL)); });
                QMetaObject::invokeMethod(this, [this, id] { closeSession(id, false); }, Qt::QueuedConnection);
                return;
            }
        });
        m_sessions.insert(s.id, s);
        qCInfo(lcTerm) << "opened" << s.id << "for" << name << "pid" << pid;
        return QJsonObject{{K("id"), s.id}};
    }

    const int id = params.value(K("id")).toInt();
    const auto it = m_sessions.find(id);
    if (it == m_sessions.end() || (it->owner != caller.package && !caller.isSystem()))
        throw RpcError{protocol::NotFound, K("no such terminal")};
    if (call == QLatin1String("write")) {
        const QByteArray data = QByteArray::fromBase64(params.value(K("data")).toString().toLatin1());
        const char *p = data.constData();
        qsizetype left = data.size();
        while (left > 0) {
            const ssize_t n = ::write(it->fd, p, size_t(left));
            if (n > 0) { p += n; left -= n; continue; }
            if (n < 0 && errno == EINTR) continue;
            break;   // EAGAIN: the shell is not reading; what does not fit is dropped (a paste of megabytes)
        }
        return true;
    }
    if (call == QLatin1String("resize")) {
        winsize ws{};
        ws.ws_col = ushort(qBound(10, params.value(K("cols")).toInt(80), 500));
        ws.ws_row = ushort(qBound(2, params.value(K("rows")).toInt(24), 300));
        ::ioctl(it->fd, TIOCSWINSZ, &ws);
        return true;
    }
    if (call == QLatin1String("close")) {
        closeSession(id, true);
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
