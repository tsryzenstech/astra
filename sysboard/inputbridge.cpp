// SPDX-License-Identifier: Apache-2.0
#include "inputbridge.h"

#include <QGuiApplication>
#include <QPointingDevice>
#include <QScreen>
#include <QSocketNotifier>
#include <private/qguiapplication_p.h>
#include <private/qinputdevicemanager_p.h>
#include <private/qinputdevicemanager_p_p.h>
#include <qpa/qwindowsysteminterface.h>

#include <cerrno>
#include <fcntl.h>
#include <libinput.h>
#include <libudev.h>
#include <linux/input-event-codes.h>
#include <unistd.h>

namespace {

int openRestricted(const char *path, int flags, void *)
{
    const int fd = ::open(path, flags | O_CLOEXEC);
    return fd < 0 ? -errno : fd;
}

void closeRestricted(int fd, void *)
{
    ::close(fd);
}

const libinput_interface kInterface = {openRestricted, closeRestricted};

} // namespace

InputBridge::InputBridge(QObject *parent) : QObject(parent) {}

InputBridge::~InputBridge()
{
    if (m_li)
        libinput_unref(m_li);
}

bool InputBridge::start()
{
    udev *ud = udev_new();
    if (!ud)
        return false;
    m_li = libinput_udev_create_context(&kInterface, nullptr, ud);
    udev_unref(ud);     // libinput keeps its own reference
    if (!m_li)
        return false;
    if (libinput_udev_assign_seat(m_li, "seat0") != 0) {
        libinput_unref(m_li);
        m_li = nullptr;
        return false;
    }
    m_notifier = new QSocketNotifier(libinput_get_fd(m_li), QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &InputBridge::process);
    process();      // the devices that are already there
    qInfo("sysboard: libinput: %d pointer(s), %d touch screen(s)", m_pointers, m_touches);
    return true;
}

QRectF InputBridge::screen() const
{
    if (QScreen *s = QGuiApplication::primaryScreen())
        return s->geometry();
    return QRectF(0, 0, 1280, 720);
}

void InputBridge::process()
{
    if (libinput_dispatch(m_li) < 0)
        return;
    while (libinput_event *ev = libinput_get_event(m_li)) {
        handle(ev);
        libinput_event_destroy(ev);
    }
}

// eglfs draws its cursor only while Qt's input device manager counts a pointer (its own evdev handlers say so; ours has to).
void InputBridge::announceDevices()
{
    if (auto *manager = QGuiApplicationPrivate::inputDeviceManager()) {
        auto *p = QInputDeviceManagerPrivate::get(manager);
        p->setDeviceCount(QInputDeviceManager::DeviceTypePointer, m_pointers);
        p->setDeviceCount(QInputDeviceManager::DeviceTypeTouch, m_touches);
        qInfo("sysboard: input device manager: %d pointer(s), %d touch", manager->deviceCount(QInputDeviceManager::DeviceTypePointer),
              manager->deviceCount(QInputDeviceManager::DeviceTypeTouch));
    }
}

void InputBridge::deviceRemoved(libinput_event *event)
{
    libinput_device *dev = libinput_event_get_device(event);
    if (libinput_device_has_capability(dev, LIBINPUT_DEVICE_CAP_POINTER) && m_pointers > 0)
        --m_pointers;
    if (libinput_device_has_capability(dev, LIBINPUT_DEVICE_CAP_TOUCH) && m_touches > 0)
        --m_touches;
    announceDevices();
}

void InputBridge::deviceAdded(libinput_event *event)
{
    libinput_device *dev = libinput_event_get_device(event);
    const bool pointer = libinput_device_has_capability(dev, LIBINPUT_DEVICE_CAP_POINTER);
    const bool touchScreen = libinput_device_has_capability(dev, LIBINPUT_DEVICE_CAP_TOUCH);
    if (pointer)
        ++m_pointers;
    if (touchScreen)
        ++m_touches;
    announceDevices();
    if (touchScreen) {
        if (!m_touchDevice) {
            m_touchDevice = new QPointingDevice(QStringLiteral("astra touch"), 1, QInputDevice::DeviceType::TouchScreen,
                                                QPointingDevice::PointerType::Finger,
                                                QInputDevice::Capability::Position | QInputDevice::Capability::Area |
                                                    QInputDevice::Capability::NormalizedPosition,
                                                10, 0, QString(), QPointingDeviceUniqueId(), this);
            QWindowSystemInterface::registerInputDevice(m_touchDevice);
        }
    }
    if (!pointer)
        return;
    // A touchpad (it taps) behaves like a Mac's: tap to click, two finger scroll and click, natural scrolling, and it
    // does not move under the palm or while typing.
    if (libinput_device_config_tap_get_finger_count(dev) > 0) {
        libinput_device_config_tap_set_enabled(dev, LIBINPUT_CONFIG_TAP_ENABLED);
        libinput_device_config_tap_set_drag_enabled(dev, LIBINPUT_CONFIG_DRAG_ENABLED);
        if (libinput_device_config_scroll_get_methods(dev) & LIBINPUT_CONFIG_SCROLL_2FG)
            libinput_device_config_scroll_set_method(dev, LIBINPUT_CONFIG_SCROLL_2FG);
        if (libinput_device_config_scroll_has_natural_scroll(dev))
            libinput_device_config_scroll_set_natural_scroll_enabled(dev, 1);
        if (libinput_device_config_click_get_methods(dev) & LIBINPUT_CONFIG_CLICK_METHOD_CLICKFINGER)
            libinput_device_config_click_set_method(dev, LIBINPUT_CONFIG_CLICK_METHOD_CLICKFINGER);
        if (libinput_device_config_dwt_is_available(dev))
            libinput_device_config_dwt_set_enabled(dev, LIBINPUT_CONFIG_DWT_ENABLED);
    }
}

void InputBridge::moveTo(const QPointF &pos)
{
    static const bool debug = qEnvironmentVariableIntValue("ASTRA_INPUT_DEBUG") == 1;
    static int logged = 0;
    if (debug && logged++ < 20)
        qInfo("sysboard: pointer to %.0f,%.0f (screen %dx%d)", pos.x(), pos.y(), int(screen().width()), int(screen().height()));
    const QRectF r = screen();
    m_pos = QPointF(qBound(r.left(), pos.x(), r.right() - 1), qBound(r.top(), pos.y(), r.bottom() - 1));
    m_placed = true;
    Q_EMIT pointerChanged(m_pos, true);
    QWindowSystemInterface::handleMouseEvent(nullptr, m_pos, m_pos, Qt::MouseButtons(m_buttons), Qt::NoButton,
                                             QEvent::MouseMove, QGuiApplication::keyboardModifiers());
}

void InputBridge::motion(const QPointF &delta)
{
    if (!m_placed)
        m_pos = screen().center();
    moveTo(m_pos + delta);
}

void InputBridge::button(quint32 code, bool pressed)
{
    Qt::MouseButton b = Qt::NoButton;
    switch (code) {
    case BTN_LEFT: b = Qt::LeftButton; break;
    case BTN_RIGHT: b = Qt::RightButton; break;
    case BTN_MIDDLE: b = Qt::MiddleButton; break;
    case BTN_SIDE: case BTN_BACK: b = Qt::BackButton; break;
    case BTN_EXTRA: case BTN_FORWARD: b = Qt::ForwardButton; break;
    default: return;
    }
    if (!m_placed)
        m_pos = screen().center();
    m_placed = true;
    if (pressed)
        m_buttons |= int(b);
    else
        m_buttons &= ~int(b);
    QWindowSystemInterface::handleMouseEvent(nullptr, m_pos, m_pos, Qt::MouseButtons(m_buttons), b,
                                             pressed ? QEvent::MouseButtonPress : QEvent::MouseButtonRelease,
                                             QGuiApplication::keyboardModifiers());
}

void InputBridge::scroll(libinput_event *event, int source)
{
    libinput_event_pointer *p = libinput_event_get_pointer_event(event);
    QPoint angle, pixels;
    const auto v = LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL;
    const auto h = LIBINPUT_POINTER_AXIS_SCROLL_HORIZONTAL;
    if (source == LIBINPUT_EVENT_POINTER_SCROLL_WHEEL) {
        // 120 is one notch of the wheel, as in Qt; libinput counts down as positive, Qt up.
        if (libinput_event_pointer_has_axis(p, v))
            angle.setY(int(-libinput_event_pointer_get_scroll_value_v120(p, v)));
        if (libinput_event_pointer_has_axis(p, h))
            angle.setX(int(libinput_event_pointer_get_scroll_value_v120(p, h)));
    } else {
        // Fingers: pixels. Qt wants eighths of a degree as well.
        if (libinput_event_pointer_has_axis(p, v))
            pixels.setY(int(-libinput_event_pointer_get_scroll_value(p, v)));
        if (libinput_event_pointer_has_axis(p, h))
            pixels.setX(int(libinput_event_pointer_get_scroll_value(p, h)));
        angle = pixels * 3;
    }
    if (angle.isNull() && pixels.isNull())
        return;
    if (!m_placed)
        m_pos = screen().center();
    QWindowSystemInterface::handleWheelEvent(nullptr, m_pos, m_pos, pixels, angle, QGuiApplication::keyboardModifiers());
}

void InputBridge::touch(libinput_event *event, int type)
{
    libinput_event_touch *t = libinput_event_get_touch_event(event);
    const QRectF r = screen();
    if (type == LIBINPUT_EVENT_TOUCH_CANCEL) {
        if (m_touchDevice)
            QWindowSystemInterface::handleTouchCancelEvent(nullptr, m_touchDevice);
        m_fingers.clear();
        return;
    }
    if (type == LIBINPUT_EVENT_TOUCH_FRAME) {
        // One frame is everything that changed at the same time: Qt gets it as one event.
        if (!m_touchDevice || m_fingers.isEmpty())
            return;
        QList<QWindowSystemInterface::TouchPoint> points;
        for (const Finger &f : std::as_const(m_fingers)) {
            QWindowSystemInterface::TouchPoint tp;
            tp.id = f.slot;
            tp.state = QEventPoint::State(f.state);
            tp.area = QRectF(f.pos.x() - 2, f.pos.y() - 2, 4, 4);
            tp.normalPosition = QPointF((f.pos.x() - r.left()) / r.width(), (f.pos.y() - r.top()) / r.height());
            tp.pressure = tp.state == QEventPoint::State::Released ? 0 : 1;
            points.append(tp);
        }
        QWindowSystemInterface::handleTouchEvent(nullptr, m_touchDevice, points);
        for (auto it = m_fingers.begin(); it != m_fingers.end();) {
            if (it->state == int(QEventPoint::State::Released))
                it = m_fingers.erase(it);
            else {
                it->state = int(QEventPoint::State::Stationary);
                ++it;
            }
        }
        return;
    }
    Q_EMIT pointerChanged(m_pos, false);
    const int slot = libinput_event_touch_get_slot(t);
    if (type == LIBINPUT_EVENT_TOUCH_UP) {
        if (m_fingers.contains(slot))
            m_fingers[slot].state = int(QEventPoint::State::Released);
        return;
    }
    const QPointF pos(r.left() + libinput_event_touch_get_x_transformed(t, int(r.width())),
                      r.top() + libinput_event_touch_get_y_transformed(t, int(r.height())));
    if (type == LIBINPUT_EVENT_TOUCH_DOWN)
        m_fingers.insert(slot, {slot, pos, int(QEventPoint::State::Pressed)});
    else if (m_fingers.contains(slot)) {
        Finger &f = m_fingers[slot];
        f.pos = pos;
        if (f.state != int(QEventPoint::State::Pressed))
            f.state = int(QEventPoint::State::Updated);
    }
}

void InputBridge::handle(libinput_event *event)
{
    const int type = libinput_event_get_type(event);
    switch (type) {
    case LIBINPUT_EVENT_DEVICE_ADDED:
        deviceAdded(event);
        break;
    case LIBINPUT_EVENT_DEVICE_REMOVED:
        deviceRemoved(event);
        break;
    case LIBINPUT_EVENT_POINTER_MOTION: {
        libinput_event_pointer *p = libinput_event_get_pointer_event(event);
        motion(QPointF(libinput_event_pointer_get_dx(p), libinput_event_pointer_get_dy(p)));
        break;
    }
    case LIBINPUT_EVENT_POINTER_MOTION_ABSOLUTE: {
        // A tablet-like pointer (a virtual machine's, a drawing tablet): where it is on the screen.
        libinput_event_pointer *p = libinput_event_get_pointer_event(event);
        const QRectF r = screen();
        moveTo(QPointF(r.left() + libinput_event_pointer_get_absolute_x_transformed(p, int(r.width())),
                       r.top() + libinput_event_pointer_get_absolute_y_transformed(p, int(r.height()))));
        break;
    }
    case LIBINPUT_EVENT_POINTER_BUTTON: {
        libinput_event_pointer *p = libinput_event_get_pointer_event(event);
        button(libinput_event_pointer_get_button(p),
               libinput_event_pointer_get_button_state(p) == LIBINPUT_BUTTON_STATE_PRESSED);
        break;
    }
    case LIBINPUT_EVENT_POINTER_SCROLL_WHEEL:
    case LIBINPUT_EVENT_POINTER_SCROLL_FINGER:
    case LIBINPUT_EVENT_POINTER_SCROLL_CONTINUOUS:
        scroll(event, type);
        break;
    case LIBINPUT_EVENT_TOUCH_DOWN:
    case LIBINPUT_EVENT_TOUCH_MOTION:
    case LIBINPUT_EVENT_TOUCH_UP:
    case LIBINPUT_EVENT_TOUCH_CANCEL:
    case LIBINPUT_EVENT_TOUCH_FRAME:
        touch(event, type);
        break;
    default:
        break;
    }
}
