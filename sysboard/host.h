// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QSize>
#include <QTimer>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

class QLocalServer;
class QJsonValue;

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
    Q_PROPERTY(QUrl wallpaper READ wallpaper CONSTANT)
    Q_PROPERTY(bool screenOn READ screenOn NOTIFY screenOnChanged)
    Q_PROPERTY(bool virtualKeyboard READ virtualKeyboard CONSTANT)
    // The input method bridge (visible, hints, commit(), backspace(), enter(), hide()).
    Q_PROPERTY(QObject *keyboard READ keyboard CONSTANT)

public:
    static SysBoardHost *instance();
    static SysBoardHost *create(QQmlEngine *, QJSEngine *) { return instance(); }

    QString socketName() const;
    QSize windowSize() const;
    bool fullscreen() const;
    bool development() const;
    QUrl wallpaper() const;
    bool screenOn() const { return m_screenOn; }
    bool virtualKeyboard() const; // is the astraOS input method loaded?
    QObject *keyboard() const;

    // Blocks until the boot animation released the display (max ~1.5 s).
    static void stopBootAnimation();

    Q_INVOKABLE void compositorReady(QQuickWindow *window);
    Q_INVOKABLE void setScreenOn(bool on);
    // Saves what is on screen as a PNG.
    Q_INVOKABLE bool saveScreenshot(const QString &path);
    // Pictures/Screenshots/Screenshot_<date>.png in the user's storage.
    Q_INVOKABLE QString newScreenshotPath() const;
    // Deletes a file inside Pictures/Screenshots (the screenshot editor's Delete).
    Q_INVOKABLE bool removeScreenshot(const QString &path);

Q_SIGNALS:
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
    void onSystemEvent(const QString &name, const QJsonValue &data);
    enum class Button { Power, VolumeUp, VolumeDown };
    void buttonChanged(Button b, bool down);
    void restartSelf();

    QPointer<QQuickWindow> m_window;
    QLocalServer *m_automation = nullptr;
    bool m_screenOn = true;

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
