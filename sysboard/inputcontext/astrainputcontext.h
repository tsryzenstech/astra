// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QObject>
#include <QPointer>
#include <QTimer>
#include <qpa/qplatforminputcontext.h>
#include <qpa/qplatforminputcontextplugin_p.h>

// The keyboard's side of the input method: SysBoard's QML keyboard finds
// it as qApp->property("astraKeyboard") (see host.cpp) and types through it.
class KeyboardBridge : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool visible READ visible NOTIFY visibleChanged)
    Q_PROPERTY(int hints READ hints NOTIFY stateChanged)          // Qt::InputMethodHints
    Q_PROPERTY(int enterKeyType READ enterKeyType NOTIFY stateChanged) // Qt::EnterKeyType
    Q_PROPERTY(bool shiftAtStart READ shiftAtStart NOTIFY stateChanged) // empty field or new sentence

public:
    bool visible() const { return m_visible; }
    int hints() const { return m_hints; }
    int enterKeyType() const { return m_enterKeyType; }
    bool shiftAtStart() const { return m_shiftAtStart; }

    Q_INVOKABLE void commit(const QString &text);
    Q_INVOKABLE void backspace();
    Q_INVOKABLE void enter();
    Q_INVOKABLE void hide();

    void setVisible(bool visible);
    void setFocusObject(QObject *object);
    void refresh();

Q_SIGNALS:
    void visibleChanged();
    void stateChanged();

private:
    void sendKey(int key, quint32 scanCode, const QString &text);

    QPointer<QObject> m_focus;
    bool m_visible = false;
    int m_hints = 0;
    int m_enterKeyType = 0;
    bool m_shiftAtStart = true;
};

class AstraInputContext : public QPlatformInputContext
{
    Q_OBJECT
public:
    AstraInputContext();
    bool isValid() const override { return true; }
    bool isInputPanelVisible() const override { return m_bridge->visible(); }
    void showInputPanel() override;
    void hideInputPanel() override;
    void setFocusObject(QObject *object) override;
    void update(Qt::InputMethodQueries queries) override;

private:
    // The keyboard follows what the field does, not each message about it: a
    // tap sends a burst of enable / disable / show / hide while the focus moves
    // from SysBoard to the app and to the field. It opens when a field the user
    // just touched becomes active, and closes only when no field has been
    // active for a moment, or the app asks for it after the burst.
    void show();
    void hideSoon();
    static bool touchedRecently(int ms);

    KeyboardBridge *m_bridge;
    QTimer m_hide;
    qint64 m_shownAt = 0;
};

class AstraInputContextPlugin : public QPlatformInputContextPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QPlatformInputContextFactoryInterface_iid FILE "astrainputcontext.json")
public:
    QPlatformInputContext *create(const QString &key, const QStringList &params) override;
};
