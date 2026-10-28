// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QSize>
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

public:
    static SysBoardHost *instance();
    static SysBoardHost *create(QQmlEngine *, QJSEngine *) { return instance(); }

    QString socketName() const;
    QSize windowSize() const;
    bool fullscreen() const;
    bool development() const;
    QUrl wallpaper() const;
    bool screenOn() const { return m_screenOn; }
    bool virtualKeyboard() const; // is Qt Virtual Keyboard installed?

    // Blocks until the boot animation released the display (max ~1.5 s).
    static void stopBootAnimation();

    Q_INVOKABLE void compositorReady(QQuickWindow *window);
    Q_INVOKABLE void setScreenOn(bool on);
    // Saves what is on screen as a PNG.
    Q_INVOKABLE bool saveScreenshot(const QString &path);

Q_SIGNALS:
    void powerKeyPressed();
    void screenOnChanged();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    explicit SysBoardHost(QObject *parent = nullptr);
    void startDevAutomation();
    void onSystemEvent(const QString &name, const QJsonValue &data);
    void restartSelf();

    QPointer<QQuickWindow> m_window;
    QLocalServer *m_automation = nullptr;
    bool m_screenOn = true;
};
