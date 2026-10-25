// SPDX-License-Identifier: Apache-2.0
#include "host.h"

#include <astra/client.h>
#include <astra/global.h>
#include <astra/paths.h>
#include <astra/properties.h>

#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QLibraryInfo>
#include <QLocalServer>
#include <QLocalSocket>
#include <QPointingDevice>
#include <QQuickWindow>
#include <QThread>
#include <QTimer>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

using astra::Paths;
using astra::Properties;

SysBoardHost *SysBoardHost::instance()
{
    static SysBoardHost *host = [] {
        auto *h = new SysBoardHost;
        QJSEngine::setObjectOwnership(h, QJSEngine::CppOwnership);
        return h;
    }();
    return host;
}

SysBoardHost::SysBoardHost(QObject *parent)
    : QObject(parent)
{
    qApp->installEventFilter(this);
}

QString SysBoardHost::socketName() const
{
    return qEnvironmentVariable("ASTRA_WAYLAND_SOCKET", QStringLiteral("wayland-0"));
}

bool SysBoardHost::development() const
{
    return Paths::isDevelopmentRoot();
}

bool SysBoardHost::fullscreen() const
{
    return !development();
}

QSize SysBoardHost::windowSize() const
{
    // Development window: the reference phone size of the design concepts.
    return QSize(393, 852);
}

QUrl SysBoardHost::wallpaper() const
{
    return QUrl::fromLocalFile(Paths::resolve(Properties::get(
        QStringLiteral("ro.system.wallpaper"), QStringLiteral("/system/media/wallpapers/default_wallpaper.png"))));
}

bool SysBoardHost::virtualKeyboard() const
{
    QStringList roots{Paths::frameworkQml(), QLibraryInfo::path(QLibraryInfo::QmlImportsPath)};
    roots += qEnvironmentVariable("QML_IMPORT_PATH").split(QLatin1Char(':'), Qt::SkipEmptyParts);
    for (const QString &root : std::as_const(roots))
        if (QFileInfo::exists(root + QStringLiteral("/QtQuick/VirtualKeyboard/qmldir")))
            return true;
    return false;
}

void SysBoardHost::stopBootAnimation()
{
    const QByteArray fifo = QFile::encodeName(Paths::bootAnimationControl());
    const int fd = ::open(fifo.constData(), O_WRONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0)
        return; // not running (development or already gone)
    if (::write(fd, "stop\n", 5) < 0)
        qWarning("sysboard: cannot signal the boot animation");
    ::close(fd);
    QElapsedTimer t;
    t.start();
    while (QFileInfo::exists(QString::fromLocal8Bit(fifo)) && t.elapsed() < 1500)
        QThread::msleep(10);
}

void SysBoardHost::compositorReady(QQuickWindow *window)
{
    m_window = window;
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    const QString socket = runtime + QLatin1Char('/') + socketName();

    // Apps run under their own uid in the "graphics" group.
    if (!development()) {
        const QByteArray path = QFile::encodeName(socket);
        if (::chmod(path.constData(), 0660) != 0 || ::chown(path.constData(), uid_t(-1), astra::AID_GRAPHICS) != 0)
            qWarning("sysboard: cannot open the Wayland socket to apps");
    }
    astra::Client::instance()->call(QStringLiteral("activity.registerDisplay"),
                                    {{QStringLiteral("socket"), socket},
                                     {QStringLiteral("scale"), qEnvironmentVariable("QT_SCALE_FACTOR")}});
    if (development())
        startDevAutomation();
}

void SysBoardHost::setScreenOn(bool on)
{
    if (m_screenOn == on)
        return;
    m_screenOn = on;
    astra::Client::instance()->call(QStringLiteral("hardware.setScreen"), {{QStringLiteral("on"), on}});
    Q_EMIT screenOnChanged();
}

bool SysBoardHost::eventFilter(QObject *watched, QEvent *event)
{
    if (event->type() == QEvent::KeyPress) {
        const int key = static_cast<QKeyEvent *>(event)->key();
        const bool power = key == Qt::Key_PowerOff || key == Qt::Key_PowerDown || key == Qt::Key_Sleep ||
                           key == Qt::Key_Suspend || (development() && key == Qt::Key_F12);
        if (power) {
            if (!static_cast<QKeyEvent *>(event)->isAutoRepeat())
                Q_EMIT powerKeyPressed();
            return true;
        }
    }
    return QObject::eventFilter(watched, event);
}

// ---------------------------------------------------------------------------
// Development automation: lets scripts drive a nested SysBoard.
//   echo "tap 200 400" | socat - UNIX-CONNECT:$ASTRA_ROOT/run/astra/sysboard-dev.sock
// Commands: screenshot <png>, tap x y, press x y ms, swipe x1 y1 x2 y2 ms, key power

namespace {
void sendMouse(QQuickWindow *w, QEvent::Type type, QPointF pos, Qt::MouseButtons buttons)
{
    // Moves carry no button: a move with a button counts as a new press in Qt.
    const Qt::MouseButton button = type == QEvent::MouseMove ? Qt::NoButton : Qt::LeftButton;
    QMouseEvent ev(type, pos, w->mapToGlobal(pos), button, buttons, Qt::NoModifier);
    QCoreApplication::sendEvent(w, &ev);
}

void gesture(QQuickWindow *w, QPointF from, QPointF to, int ms, std::function<void()> done)
{
    sendMouse(w, QEvent::MouseButtonPress, from, Qt::LeftButton);
    const int steps = qMax(1, ms / 16);
    auto *timer = new QTimer;
    auto step = std::make_shared<int>(0);
    QObject::connect(timer, &QTimer::timeout, [=] {
        ++*step;
        const QPointF p = from + (to - from) * (double(*step) / steps);
        if (*step <= steps && from != to)
            sendMouse(w, QEvent::MouseMove, p, Qt::LeftButton);
        if (*step >= steps) {
            sendMouse(w, QEvent::MouseButtonRelease, to, Qt::NoButton);
            timer->deleteLater();
            done();
        }
    });
    timer->start(16);
}
} // namespace

void SysBoardHost::startDevAutomation()
{
    if (m_automation)
        return;
    m_automation = new QLocalServer(this);
    const QString path = Paths::runtimeDir() + QStringLiteral("/sysboard-dev.sock");
    QDir().mkpath(Paths::runtimeDir());
    QLocalServer::removeServer(path);
    m_automation->listen(path);
    connect(m_automation, &QLocalServer::newConnection, this, [this] {
        QLocalSocket *s = m_automation->nextPendingConnection();
        connect(s, &QLocalSocket::disconnected, s, &QObject::deleteLater);
        connect(s, &QLocalSocket::readyRead, this, [this, s] {
            while (s->canReadLine()) {
                const QStringList a = QString::fromUtf8(s->readLine()).trimmed().split(QLatin1Char(' '), Qt::SkipEmptyParts);
                auto reply = [s](const QByteArray &msg) {
                    if (s->state() == QLocalSocket::ConnectedState) {
                        s->write(msg + '\n');
                        s->flush();
                    }
                };
                if (a.isEmpty() || !m_window) {
                    reply("error");
                } else if (a[0] == QLatin1String("screenshot") && a.size() == 2) {
                    reply(m_window->grabWindow().save(a[1]) ? "ok" : "error");
                } else if (a[0] == QLatin1String("tap") && a.size() == 3) {
                    const QPointF p(a[1].toDouble(), a[2].toDouble());
                    gesture(m_window, p, p, 60, [reply] { reply("ok"); });
                } else if (a[0] == QLatin1String("press") && a.size() == 4) {
                    const QPointF p(a[1].toDouble(), a[2].toDouble());
                    gesture(m_window, p, p, a[3].toInt(), [reply] { reply("ok"); });
                } else if (a[0] == QLatin1String("swipe") && a.size() == 6) {
                    gesture(m_window, QPointF(a[1].toDouble(), a[2].toDouble()), QPointF(a[3].toDouble(), a[4].toDouble()),
                            a[5].toInt(), [reply] { reply("ok"); });
                } else if (a[0] == QLatin1String("key") && a.value(1) == QLatin1String("power")) {
                    Q_EMIT powerKeyPressed();
                    reply("ok");
                } else {
                    reply("error");
                }
            }
        });
    });
}
