// SPDX-License-Identifier: Apache-2.0
//
// astraOS input method (QT_IM_MODULE=astra), loaded by SysBoard only.
//
// SysBoard's own text fields and every app (through the Wayland text-input
// protocol, served by the compositor) end up as the focus object here:
// a focused app surface reports ImEnabled while one of its fields has focus,
// and its show/hide requests arrive as showInputPanel()/hideInputPanel().
// The QML keyboard types by sending input method events to that object.

#include "astrainputcontext.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QInputMethodEvent>
#include <QKeyEvent>
#include <QVariant>

void KeyboardBridge::setVisible(bool visible)
{
    if (m_visible == visible)
        return;
    m_visible = visible;
    Q_EMIT visibleChanged();
}

void KeyboardBridge::setFocusObject(QObject *object)
{
    m_focus = object;
    refresh();
}

void KeyboardBridge::refresh()
{
    int hints = 0, enter = 0;
    bool start = true;
    if (m_focus) {
        QInputMethodQueryEvent q(Qt::ImHints | Qt::ImEnterKeyType | Qt::ImSurroundingText | Qt::ImCursorPosition);
        QCoreApplication::sendEvent(m_focus, &q);
        hints = q.value(Qt::ImHints).toInt();
        enter = q.value(Qt::ImEnterKeyType).toInt();
        const QString text = q.value(Qt::ImSurroundingText).toString();
        const int cursor = q.value(Qt::ImCursorPosition).toInt();
        const QString before = text.left(cursor).trimmed();
        start = before.isEmpty() || before.endsWith(QLatin1Char('.')) || before.endsWith(QLatin1Char('!')) ||
                before.endsWith(QLatin1Char('?'));
    }
    if (hints != m_hints || enter != m_enterKeyType || start != m_shiftAtStart) {
        m_hints = hints;
        m_enterKeyType = enter;
        m_shiftAtStart = start;
        Q_EMIT stateChanged();
    }
}

void KeyboardBridge::commit(const QString &text)
{
    if (!m_focus)
        return;
    QInputMethodEvent ev;
    ev.setCommitString(text);
    QCoreApplication::sendEvent(m_focus, &ev);
    refresh();
}

void KeyboardBridge::backspace()
{
    if (!m_focus)
        return;
    // A key event works for SysBoard fields and Wayland clients alike
    // (xkb keycode 22 = evdev KEY_BACKSPACE 14 + 8).
    sendKey(Qt::Key_Backspace, 22, QString());
    refresh();
}

void KeyboardBridge::enter()
{
    if (!m_focus)
        return;
    sendKey(Qt::Key_Return, 36, QStringLiteral("\r"));
    refresh();
}

void KeyboardBridge::hide()
{
    setVisible(false);
}

void KeyboardBridge::sendKey(int key, quint32 scanCode, const QString &text)
{
    QKeyEvent press(QEvent::KeyPress, key, Qt::NoModifier, scanCode, 0, 0, text);
    QCoreApplication::sendEvent(m_focus, &press);
    QKeyEvent release(QEvent::KeyRelease, key, Qt::NoModifier, scanCode, 0, 0, text);
    QCoreApplication::sendEvent(m_focus, &release);
}

AstraInputContext::AstraInputContext()
    : m_bridge(new KeyboardBridge)
{
    // SysBoard picks the bridge up from the application object.
    if (QCoreApplication::instance())
        QCoreApplication::instance()->setProperty("astraKeyboard", QVariant::fromValue<QObject *>(m_bridge));
}

// show() can arrive before setFocusObject(): ask the focus object itself.
static bool acceptsInput(QObject *object)
{
    if (!object)
        return false;
    QInputMethodQueryEvent q(Qt::ImEnabled);
    QCoreApplication::sendEvent(object, &q);
    return q.value(Qt::ImEnabled).toBool();
}

void AstraInputContext::showInputPanel()
{
    QObject *focus = QGuiApplication::focusObject();
    if (acceptsInput(focus)) {
        m_bridge->setFocusObject(focus);
        m_bridge->setVisible(true);
    }
    emitInputPanelVisibleChanged();
}

void AstraInputContext::hideInputPanel()
{
    m_bridge->setVisible(false);
    emitInputPanelVisibleChanged();
}

void AstraInputContext::setFocusObject(QObject *object)
{
    m_bridge->setFocusObject(object);
    if (!acceptsInput(object)) {
        m_bridge->setVisible(false);
        emitInputPanelVisibleChanged();
    }
}

void AstraInputContext::update(Qt::InputMethodQueries queries)
{
    if (queries & Qt::ImEnabled) {
        // An app field gained or lost focus inside an already focused surface.
        if (!acceptsInput(QGuiApplication::focusObject()))
            m_bridge->setVisible(false);
        emitInputPanelVisibleChanged();
    }
    m_bridge->refresh();
}

QPlatformInputContext *AstraInputContextPlugin::create(const QString &key, const QStringList &)
{
    if (key.compare(QLatin1String("astra"), Qt::CaseInsensitive) == 0)
        return new AstraInputContext;
    return nullptr;
}
