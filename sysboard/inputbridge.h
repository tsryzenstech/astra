// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QHash>
#include <QList>
#include <QObject>
#include <QPointF>
#include <QVariantMap>

class QPointingDevice;
class XkbKeyboard;
struct libinput_device;
class QSocketNotifier;
struct libinput;
struct libinput_event;

// Pointers and touch for the desktop, through libinput (as every desktop Linux does): mice, touchpads (tap to click, two
// finger scroll, palm and typing rejection, acceleration) and touch screens. Qt's own eglfs input is evdev only in
// astra's Qt build, which reads a mouse but cannot drive a touchpad. The keyboard stays Qt's (evdev, see main.cpp).
class InputBridge : public QObject
{
    Q_OBJECT
public:
    explicit InputBridge(QObject *parent = nullptr);
    ~InputBridge() override;

    // False when libinput cannot be started (no udev, no permission on /dev/input).
    bool start();
    // Settings > Keyboard and Trackpad: { layout, variant, naturalScroll, tapToClick, pointerSpeed }.
    void setConfig(const QVariantMap &config);
    // Whether the keyboard is ours (xkbcommon) rather than Qt's evdev plugin.
    bool keyboardReady() const;

Q_SIGNALS:
    // Where the pointer is, and whether it is the thing in use (a touch hides it).
    void pointerChanged(const QPointF &position, bool visible);

private:
    void process();
    void handle(libinput_event *event);
    void deviceAdded(libinput_event *event);
    void deviceRemoved(libinput_event *event);
    void announceDevices();
    void motion(const QPointF &delta);
    void moveTo(const QPointF &pos);
    void button(quint32 code, bool pressed);
    void scroll(libinput_event *event, int source);
    void touch(libinput_event *event, int type);
    QRectF screen() const;
    void configure(libinput_device *device);

    libinput *m_li = nullptr;
    QSocketNotifier *m_notifier = nullptr;
    QPointF m_pos;
    bool m_placed = false;
    int m_buttons = 0;
    QPointingDevice *m_touchDevice = nullptr;
    struct Finger { int slot; QPointF pos; int state; };
    QHash<int, Finger> m_fingers;
    int m_pointers = 0, m_touches = 0;
    XkbKeyboard *m_keyboard = nullptr;
    QList<libinput_device *> m_touchpads;
    QVariantMap m_config;
};
