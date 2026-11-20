// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QSize>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QLocalServer;
class QJsonValue;
class QTouchEvent;
class QWaylandQuickItem;

// Glue between SysBoard's QML and the platform: display hand-over from the
// boot animation, Wayland socket publication, power key and screen power.
class SysBoardHost : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Host)
    QML_SINGLETON

    Q_PROPERTY(QString socketName READ socketName CONSTANT)
    Q_PROPERTY(QSize windowSize READ windowSize CONSTANT)
    Q_PROPERTY(bool fullscreen READ fullscreen CONSTANT)
    Q_PROPERTY(bool development READ development CONSTANT)
    // "phone" or "desktop" (astra::Form): which shell Main.qml loads.
    Q_PROPERTY(QString formFactor READ formFactor CONSTANT)
    Q_PROPERTY(bool desktop READ desktop CONSTANT)
    // The recovery environment of the live ISO: the shell shows the Installer, Disk Utility and a browser.
    Q_PROPERTY(bool installer READ installer CONSTANT)
    Q_PROPERTY(QUrl wallpaper READ wallpaper CONSTANT)
    Q_PROPERTY(QUrl bootLogo READ bootLogo CONSTANT)
    Q_PROPERTY(bool screenOn READ screenOn NOTIFY screenOnChanged)
    Q_PROPERTY(bool virtualKeyboard READ virtualKeyboard CONSTANT)
    // The input method bridge (visible, hints, commit(), backspace(), enter(), hide()).
    Q_PROPERTY(QObject *keyboard READ keyboard CONSTANT)
    // The desktop's pointer, drawn by the shell itself (Qt's eglfs cursor is not reliable on every GPU path).
    Q_PROPERTY(QPointF pointerPosition READ pointerPosition NOTIFY pointerChanged)
    Q_PROPERTY(bool pointerVisible READ pointerVisible NOTIFY pointerChanged)
    // Settings > Keyboard: the layout the compositor's keymap (and so every app) has.
    Q_PROPERTY(QString keyboardLayout READ keyboardLayout NOTIFY inputConfigChanged)
    Q_PROPERTY(QString keyboardVariant READ keyboardVariant NOTIFY inputConfigChanged)

public:
    static SysBoardHost *instance();
    static SysBoardHost *create(QQmlEngine *, QJSEngine *) { return instance(); }

    QString socketName() const;
    QSize windowSize() const;
    bool fullscreen() const;
    bool development() const;
    QString formFactor() const;
    bool desktop() const;
    bool installer() const;
    QUrl wallpaper() const;
    QUrl bootLogo() const;
    bool screenOn() const { return m_screenOn; }
    bool virtualKeyboard() const; // is the astraOS input method loaded?
    QObject *keyboard() const;
    QPointF pointerPosition() const { return m_pointerPosition; }
    bool pointerVisible() const { return m_pointerVisible; }
    void setPointer(const QPointF &position, bool visible);
    QString keyboardLayout() const { return m_config.value(QStringLiteral("layout"), QStringLiteral("us")).toString(); }
    QString keyboardVariant() const { return m_config.value(QStringLiteral("variant")).toString(); }
    // { layout, variant, naturalScroll, tapToClick, pointerSpeed } from the settings (DesktopShell.qml).
    Q_INVOKABLE void setInputConfig(const QVariantMap &config);

    // Blocks until the boot animation released the display (max ~1.5 s).
    static void stopBootAnimation();

    Q_INVOKABLE void compositorReady(QQuickWindow *window);
    // The shell finished loading behind the boot logo.
    Q_INVOKABLE void shellLoaded();
    Q_INVOKABLE void setScreenOn(bool on);
    // Saves what is on screen as a PNG.
    Q_INVOKABLE bool saveScreenshot(const QString &path);
    // Pictures/Screenshots/Screenshot_<date>.png in the user's storage.
    Q_INVOKABLE QString newScreenshotPath() const;
    // Deletes a file inside Pictures/Screenshots (the screenshot editor's Delete).
    Q_INVOKABLE bool removeScreenshot(const QString &path);

Q_SIGNALS:
    void pointerChanged();
    void inputConfigChanged(const QVariantMap &config);
    // Hardware buttons (development trees: F12 power, F11 volume up, F10 volume down)
    void powerKeyPressed();        // short press
    void powerKeyLongPressed();    // held for 600 ms: power menu
    void volumeStep(int delta);    // +1 / -1, repeats while held
    void screenshotRequested();    // power + volume down together
    // Find My Device > Lock, from the AstraID website.
    void lockRequested(const QString &message);
    void screenOnChanged();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    explicit SysBoardHost(QObject *parent = nullptr);
    void startDevAutomation();
    bool forwardTouch(QWaylandQuickItem *item, QTouchEvent *event);
    void onSystemEvent(const QString &name, const QJsonValue &data);
    enum class Button { Power, VolumeUp, VolumeDown };
    void buttonChanged(Button b, bool down);
    void restartSelf();

    QPointer<QQuickWindow> m_window;
    QLocalServer *m_automation = nullptr;
    bool m_screenOn = true;
    QPointF m_pointerPosition;
    QVariantMap m_config;
    bool m_pointerVisible = false;

    // Button state
    bool m_powerDown = false;
    bool m_volUpDown = false;
    bool m_volDownDown = false;
    bool m_comboFired = false;
    bool m_powerLongFired = false;
    int m_pendingVolume = 0;
    QTimer *m_powerLong = nullptr;
    QTimer *m_volumeDelay = nullptr;
    QTimer *m_volumeRepeat = nullptr;
};
