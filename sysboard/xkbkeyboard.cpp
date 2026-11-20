// SPDX-License-Identifier: Apache-2.0
#include "xkbkeyboard.h"

#include <QChar>
#include <qpa/qwindowsysteminterface.h>

#include <xkbcommon/xkbcommon-keysyms.h>
#include <xkbcommon/xkbcommon.h>

namespace {

// The Qt::Key of a keysym: the special keys by a table, the characters by their Unicode value (Qt's keys for letters are the
// capital letter's code).
int qtKey(xkb_keysym_t sym)
{
    if (sym >= XKB_KEY_F1 && sym <= XKB_KEY_F35)
        return Qt::Key_F1 + int(sym - XKB_KEY_F1);
    if (sym >= XKB_KEY_KP_0 && sym <= XKB_KEY_KP_9)
        return Qt::Key_0 + int(sym - XKB_KEY_KP_0);
    switch (sym) {
    case XKB_KEY_Escape: return Qt::Key_Escape;
    case XKB_KEY_Tab: return Qt::Key_Tab;
    case XKB_KEY_ISO_Left_Tab: return Qt::Key_Backtab;
    case XKB_KEY_BackSpace: return Qt::Key_Backspace;
    case XKB_KEY_Return: return Qt::Key_Return;
    case XKB_KEY_KP_Enter: return Qt::Key_Enter;
    case XKB_KEY_Insert: case XKB_KEY_KP_Insert: return Qt::Key_Insert;
    case XKB_KEY_Delete: case XKB_KEY_KP_Delete: return Qt::Key_Delete;
    case XKB_KEY_Pause: return Qt::Key_Pause;
    case XKB_KEY_Print: return Qt::Key_Print;
    case XKB_KEY_Home: case XKB_KEY_KP_Home: return Qt::Key_Home;
    case XKB_KEY_End: case XKB_KEY_KP_End: return Qt::Key_End;
    case XKB_KEY_Left: case XKB_KEY_KP_Left: return Qt::Key_Left;
    case XKB_KEY_Up: case XKB_KEY_KP_Up: return Qt::Key_Up;
    case XKB_KEY_Right: case XKB_KEY_KP_Right: return Qt::Key_Right;
    case XKB_KEY_Down: case XKB_KEY_KP_Down: return Qt::Key_Down;
    case XKB_KEY_Prior: case XKB_KEY_KP_Prior: return Qt::Key_PageUp;
    case XKB_KEY_Next: case XKB_KEY_KP_Next: return Qt::Key_PageDown;
    case XKB_KEY_Shift_L: case XKB_KEY_Shift_R: return Qt::Key_Shift;
    case XKB_KEY_Control_L: case XKB_KEY_Control_R: return Qt::Key_Control;
    case XKB_KEY_Alt_L: case XKB_KEY_Alt_R: return Qt::Key_Alt;
    case XKB_KEY_Meta_L: case XKB_KEY_Meta_R: case XKB_KEY_Super_L: case XKB_KEY_Super_R: return Qt::Key_Meta;
    case XKB_KEY_ISO_Level3_Shift: return Qt::Key_AltGr;
    case XKB_KEY_Mode_switch: return Qt::Key_Mode_switch;
    case XKB_KEY_Caps_Lock: return Qt::Key_CapsLock;
    case XKB_KEY_Num_Lock: return Qt::Key_NumLock;
    case XKB_KEY_Scroll_Lock: return Qt::Key_ScrollLock;
    case XKB_KEY_Menu: return Qt::Key_Menu;
    case XKB_KEY_KP_Add: return Qt::Key_Plus;
    case XKB_KEY_KP_Subtract: return Qt::Key_Minus;
    case XKB_KEY_KP_Multiply: return Qt::Key_Asterisk;
    case XKB_KEY_KP_Divide: return Qt::Key_Slash;
    case XKB_KEY_KP_Decimal: case XKB_KEY_KP_Separator: return Qt::Key_Period;
    case XKB_KEY_dead_grave: return Qt::Key_Dead_Grave;
    case XKB_KEY_dead_acute: return Qt::Key_Dead_Acute;
    case XKB_KEY_dead_circumflex: return Qt::Key_Dead_Circumflex;
    case XKB_KEY_dead_tilde: return Qt::Key_Dead_Tilde;
    case XKB_KEY_dead_diaeresis: return Qt::Key_Dead_Diaeresis;
    case XKB_KEY_XF86AudioRaiseVolume: return Qt::Key_VolumeUp;
    case XKB_KEY_XF86AudioLowerVolume: return Qt::Key_VolumeDown;
    case XKB_KEY_XF86AudioMute: return Qt::Key_VolumeMute;
    case XKB_KEY_XF86AudioPlay: return Qt::Key_MediaPlay;
    case XKB_KEY_XF86AudioStop: return Qt::Key_MediaStop;
    case XKB_KEY_XF86AudioPrev: return Qt::Key_MediaPrevious;
    case XKB_KEY_XF86AudioNext: return Qt::Key_MediaNext;
    case XKB_KEY_XF86MonBrightnessUp: return Qt::Key_MonBrightnessUp;
    case XKB_KEY_XF86MonBrightnessDown: return Qt::Key_MonBrightnessDown;
    case XKB_KEY_XF86PowerOff: return Qt::Key_PowerOff;
    case XKB_KEY_XF86Sleep: return Qt::Key_Sleep;
    case XKB_KEY_XF86Suspend: return Qt::Key_Suspend;
    default: break;
    }
    const uint32_t cp = xkb_keysym_to_utf32(sym);
    if (cp >= 0x20 && cp != 0x7f) {
        const uint32_t upper = QChar::toUpper(cp);
        return int(upper);
    }
    return Qt::Key_unknown;
}

} // namespace

XkbKeyboard::XkbKeyboard(QObject *parent) : QObject(parent)
{
    m_context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    m_repeat.setSingleShot(false);
    connect(&m_repeat, &QTimer::timeout, this, [this] {
        m_repeat.setInterval(33);
        if (m_repeating) {
            send(m_repeating, false, true);
            send(m_repeating, true, true);
        }
    });
}

XkbKeyboard::~XkbKeyboard()
{
    if (m_state)
        xkb_state_unref(m_state);
    if (m_keymap)
        xkb_keymap_unref(m_keymap);
    if (m_context)
        xkb_context_unref(m_context);
}

bool XkbKeyboard::setLayout(const QString &layout, const QString &variant)
{
    if (!m_context)
        return false;
    const QByteArray l = layout.isEmpty() ? QByteArray("us") : layout.toLatin1();
    const QByteArray v = variant.toLatin1();
    // "us" first as a fallback when the layout has none of its own letters (Cyrillic, Greek...): Alt+Shift switches is not done here.
    xkb_rule_names names = {};
    names.rules = "evdev";
    names.model = "pc105";
    names.layout = l.constData();
    names.variant = v.isEmpty() ? nullptr : v.constData();
    xkb_keymap *keymap = xkb_keymap_new_from_names(m_context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (!keymap)
        return false;
    xkb_state *state = xkb_state_new(keymap);
    if (!state) {
        xkb_keymap_unref(keymap);
        return false;
    }
    if (m_state)
        xkb_state_unref(m_state);
    if (m_keymap)
        xkb_keymap_unref(m_keymap);
    m_keymap = keymap;
    m_state = state;
    m_repeat.stop();
    m_repeating = 0;
    m_down.clear();
    return true;
}

Qt::KeyboardModifiers XkbKeyboard::modifiers() const
{
    Qt::KeyboardModifiers m;
    auto on = [this](const char *name) { return xkb_state_mod_name_is_active(m_state, name, XKB_STATE_MODS_EFFECTIVE) > 0; };
    if (on(XKB_MOD_NAME_SHIFT)) m |= Qt::ShiftModifier;
    if (on(XKB_MOD_NAME_CTRL)) m |= Qt::ControlModifier;
    if (on(XKB_MOD_NAME_ALT)) m |= Qt::AltModifier;
    if (on(XKB_MOD_NAME_LOGO)) m |= Qt::MetaModifier;
    return m;
}

void XkbKeyboard::send(quint32 code, bool pressed, bool repeat)
{
    const xkb_keycode_t kc = code + 8;
    const xkb_keysym_t sym = xkb_state_key_get_one_sym(m_state, kc);
    char buf[16] = {};
    const int n = xkb_state_key_get_utf8(m_state, kc, buf, sizeof buf);
    QString text = n > 0 ? QString::fromUtf8(buf) : QString();
    // Keys that are not characters carry no text.
    if (!text.isEmpty() && text.at(0).unicode() < 0x20 && text != QLatin1String("\r") && text != QLatin1String("\t") &&
        text != QLatin1String("\b") && text != QLatin1String("\x1b") && sym > 0xff)
        text.clear();
    Qt::KeyboardModifiers mods = modifiers();
    QWindowSystemInterface::handleExtendedKeyEvent(nullptr, pressed ? QEvent::KeyPress : QEvent::KeyRelease, qtKey(sym), mods, kc,
                                                   sym, 0, text, repeat);
}

void XkbKeyboard::key(quint32 evdevCode, bool pressed)
{
    if (!m_state)
        return;
    const xkb_keycode_t kc = evdevCode + 8;
    if (pressed) {
        if (m_down.contains(evdevCode))
            return;
        m_down.insert(evdevCode);
        send(evdevCode, true, false);
        xkb_state_update_key(m_state, kc, XKB_KEY_DOWN);
        if (xkb_keymap_key_repeats(m_keymap, kc)) {
            m_repeating = evdevCode;
            m_repeat.start(400);
        }
    } else {
        m_down.remove(evdevCode);
        if (m_repeating == evdevCode) {
            m_repeat.stop();
            m_repeating = 0;
        }
        send(evdevCode, false, false);
        xkb_state_update_key(m_state, kc, XKB_KEY_UP);
    }
}
