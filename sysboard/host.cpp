// SPDX-License-Identifier: Apache-2.0
#include "host.h"

#include <astra/client.h>
#include <astra/global.h>
#include <astra/paths.h>
#include <astra/properties.h>

#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QLibraryInfo>
#include <QLocalServer>
#include <QLocalSocket>
#include <QJsonObject>
#include <QPointingDevice>
#include <QProcess>
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

    m_powerLong = new QTimer(this);
    m_powerLong->setSingleShot(true);
    m_powerLong->setInterval(600);
    connect(m_powerLong, &QTimer::timeout, this, [this] {
        m_powerLongFired = true;
        Q_EMIT powerKeyLongPressed();
    });
    // A volume press waits a moment: power may follow (screenshot combo).
    m_volumeDelay = new QTimer(this);
    m_volumeDelay->setSingleShot(true);
    m_volumeDelay->setInterval(90);
    connect(m_volumeDelay, &QTimer::timeout, this, [this] {
        Q_EMIT volumeStep(m_pendingVolume);
        m_volumeRepeat->start(380);
    });
    m_volumeRepeat = new QTimer(this);
    connect(m_volumeRepeat, &QTimer::timeout, this, [this] {
        m_volumeRepeat->setInterval(110);
        if ((m_pendingVolume > 0 && m_volUpDown) || (m_pendingVolume < 0 && m_volDownDown))
            Q_EMIT volumeStep(m_pendingVolume);
        else
            m_volumeRepeat->stop();
    });

    astra::Client *c = astra::Client::instance();
    c->subscribe({QStringLiteral("system")});
    connect(c, &astra::Client::event, this, &SysBoardHost::onSystemEvent);
}

void SysBoardHost::onSystemEvent(const QString &name, const QJsonValue &data)
{
    if (name == QLatin1String("system.screenshot")) {
        // Requested by adud or a developer tool: capture, then answer astrad.
        const QJsonObject req = data.toObject();
        const QString path = req.value(QLatin1String("path")).toString();
        const bool ok = saveScreenshot(path);
        astra::Client::instance()->call(QStringLiteral("system.screenshotDone"),
                                        {{QStringLiteral("id"), req.value(QLatin1String("id"))},
                                         {QStringLiteral("path"), path},
                                         {QStringLiteral("ok"), ok}});
    } else if (name == QLatin1String("system.restartShell")) {
        restartSelf();
    }
}

bool SysBoardHost::saveScreenshot(const QString &path)
{
    if (!m_window || path.isEmpty())
        return false;
    QDir().mkpath(QFileInfo(path).absolutePath());
    return m_window->grabWindow().save(path, "PNG");
}

QString SysBoardHost::newScreenshotPath() const
{
    return Paths::userMedia() + QStringLiteral("/Pictures/Screenshots/Screenshot_%1.png")
                                    .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss")));
}

bool SysBoardHost::removeScreenshot(const QString &path)
{
    const QString dir = QFileInfo(Paths::userMedia() + QStringLiteral("/Pictures/Screenshots")).canonicalFilePath();
    const QFileInfo f(path);
    return !dir.isEmpty() && f.canonicalPath() == dir && QFile::remove(f.canonicalFilePath());
}

// Development trees have no init to restart SysBoard ("Restart SysBoard" in
// Developer options): start a fresh copy, which comes up on the lock screen.
void SysBoardHost::restartSelf()
{
    qInfo("sysboard: restarting");
    QProcess p;
    p.setProgram(QCoreApplication::applicationFilePath());
    p.setArguments(QCoreApplication::arguments().mid(1));
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("ASTRA_SYSBOARD_WAIT_PID"), QString::number(QCoreApplication::applicationPid()));
    p.setProcessEnvironment(env);
    if (p.startDetached())
        QTimer::singleShot(0, qApp, &QCoreApplication::quit);
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
    return keyboard() != nullptr;
}

QObject *SysBoardHost::keyboard() const
{
    // Set by the input method plugin when Qt loads it (QT_IM_MODULE=astra).
    QGuiApplication::inputMethod(); // makes sure the input context exists
    return qApp->property("astraKeyboard").value<QObject *>();
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
    // First frame on screen: the GPU path works (see main.cpp).
    connect(window, &QQuickWindow::frameSwapped, this, [] {
        QFile::remove(Paths::runtimeDir() + QStringLiteral("/sysboard.starting"));
    }, Qt::ConnectionType(Qt::QueuedConnection | Qt::SingleShotConnection));
    // The input method follows the focus window (nested development
    // displays may not activate it by themselves).
    window->requestActivate();
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

void SysBoardHost::buttonChanged(Button b, bool down)
{
    switch (b) {
    case Button::Power:
        m_powerDown = down;
        break;
    case Button::VolumeUp:
        m_volUpDown = down;
        break;
    case Button::VolumeDown:
        m_volDownDown = down;
        break;
    }

    // Power + volume down: screenshot (in either order).
    if (down && m_powerDown && m_volDownDown && !m_comboFired) {
        m_comboFired = true;
        m_powerLong->stop();
        m_volumeDelay->stop();
        m_volumeRepeat->stop();
        Q_EMIT screenshotRequested();
        return;
    }
    if (!m_powerDown && !m_volDownDown && !m_volUpDown && m_comboFired) {
        m_comboFired = false;
        return;
    }
    if (m_comboFired)
        return;

    if (b == Button::Power) {
        if (down) {
            m_powerLongFired = false;
            m_powerLong->start();
        } else if (m_powerLong->isActive()) {
            m_powerLong->stop();
            Q_EMIT powerKeyPressed();
        }
        return;
    }
    if (down) {
        m_pendingVolume = b == Button::VolumeUp ? 1 : -1;
        m_volumeDelay->start();
    } else {
        m_volumeRepeat->stop();
        // Released before the combo window closed: still one step.
        if (m_volumeDelay->isActive()) {
            m_volumeDelay->stop();
            Q_EMIT volumeStep(m_pendingVolume);
        }
    }
}

bool SysBoardHost::eventFilter(QObject *watched, QEvent *event)
{
    if (event->type() != QEvent::KeyPress && event->type() != QEvent::KeyRelease)
        return QObject::eventFilter(watched, event);
    auto *ke = static_cast<QKeyEvent *>(event);
    const int key = ke->key();
    Button b;
    if (key == Qt::Key_PowerOff || key == Qt::Key_PowerDown || key == Qt::Key_Sleep || key == Qt::Key_Suspend ||
        (development() && key == Qt::Key_F12))
        b = Button::Power;
    else if (key == Qt::Key_VolumeUp || (development() && key == Qt::Key_F11))
        b = Button::VolumeUp;
    else if (key == Qt::Key_VolumeDown || (development() && key == Qt::Key_F10))
        b = Button::VolumeDown;
    else
        return QObject::eventFilter(watched, event);
    // Buttons belong to the system: apps never see them.
    if (!ke->isAutoRepeat())
        buttonChanged(b, event->type() == QEvent::KeyPress);
    return true;
}

// ---------------------------------------------------------------------------
// Development automation: lets scripts drive a nested SysBoard.
//   echo "tap 200 400" | socat - UNIX-CONNECT:$ASTRA_ROOT/run/astra/sysboard-dev.sock
// Commands: screenshot <png>, tap x y, press x y ms, swipe x1 y1 x2 y2 ms,
// swipehold x1 y1 x2 y2 ms hold_ms (stays down at the end),
// key power|volup|voldown|screenshot [hold_ms]

namespace {
void sendMouse(QQuickWindow *w, QEvent::Type type, QPointF pos, Qt::MouseButtons buttons)
{
    // Moves carry no button: a move with a button counts as a new press in Qt.
    const Qt::MouseButton button = type == QEvent::MouseMove ? Qt::NoButton : Qt::LeftButton;
    QMouseEvent ev(type, pos, w->mapToGlobal(pos), button, buttons, Qt::NoModifier);
    QCoreApplication::sendEvent(w, &ev);
}

void gesture(QQuickWindow *w, QPointF from, QPointF to, int ms, std::function<void()> done, int holdMs = 0)
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
        if (*step >= steps + holdMs / 16) {
            sendMouse(w, QEvent::MouseButtonRelease, to, Qt::NoButton);
            timer->deleteLater();
            done();
        } else if (*step > steps && *step % 4 == 0) {
            sendMouse(w, QEvent::MouseMove, to, Qt::LeftButton); // a resting finger still reports
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
                } else if (a[0] == QLatin1String("swipehold") && a.size() == 7) {
                    gesture(m_window, QPointF(a[1].toDouble(), a[2].toDouble()), QPointF(a[3].toDouble(), a[4].toDouble()),
                            a[5].toInt(), [reply] { reply("ok"); }, a[6].toInt());
                } else if (a[0] == QLatin1String("key") && a.size() >= 2) {
                    // Simulates the hardware buttons through the same state machine.
                    const QString k = a[1];
                    const int hold = a.value(2, QStringLiteral("80")).toInt();
                    QList<Button> buttons;
                    if (k == QLatin1String("power"))
                        buttons = {Button::Power};
                    else if (k == QLatin1String("volup"))
                        buttons = {Button::VolumeUp};
                    else if (k == QLatin1String("voldown"))
                        buttons = {Button::VolumeDown};
                    else if (k == QLatin1String("screenshot"))
                        buttons = {Button::VolumeDown, Button::Power};
                    if (buttons.isEmpty()) {
                        reply("error");
                    } else {
                        for (Button b : buttons)
                            buttonChanged(b, true);
                        QTimer::singleShot(hold, this, [this, buttons, reply] {
                            for (Button b : buttons)
                                buttonChanged(b, false);
                            reply("ok");
                        });
                    }
                } else {
                    reply("error");
                }
            }
        });
    });
}
