// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QObject>
#include <QSet>
#include <QTimer>

struct xkb_context;
struct xkb_keymap;
struct xkb_state;

// The desktop's keyboard: key codes from libinput turned into Qt key events through xkbcommon, with the layout the user chose
// (Settings > Keyboard), the modifiers, the text and the key repeat. The Wayland clients get the same layout from the
// compositor's keymap (Main.qml) and the raw key codes, so a program draws what the user typed whatever toolkit it uses.
class XkbKeyboard : public QObject
{
    Q_OBJECT
public:
    explicit XkbKeyboard(QObject *parent = nullptr);
    ~XkbKeyboard() override;

    // "it", "us", "gb"... and a variant ("intl", ""). False when xkbcommon cannot make the keymap (no xkb-data).
    bool setLayout(const QString &layout, const QString &variant = QString());
    bool ready() const { return m_state != nullptr; }
    // An evdev key code (linux/input-event-codes.h) going down or up.
    void key(quint32 evdevCode, bool pressed);

private:
    void send(quint32 code, bool pressed, bool repeat);
    Qt::KeyboardModifiers modifiers() const;

    xkb_context *m_context = nullptr;
    xkb_keymap *m_keymap = nullptr;
    xkb_state *m_state = nullptr;
    QTimer m_repeat;
    quint32 m_repeating = 0;
    QSet<quint32> m_down;
};
