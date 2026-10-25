// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QJSValue>
#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace astra::qml {

// Current weather (singleton "Weather").
class WeatherInfo : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Weather)
    QML_SINGLETON

    Q_PROPERTY(QVariantMap current READ current NOTIFY currentChanged)
    Q_PROPERTY(bool available READ available NOTIFY currentChanged)

public:
    explicit WeatherInfo(QObject *parent = nullptr);
    QVariantMap current() const { return m_current; }
    bool available() const { return !m_current.isEmpty(); }
    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void currentChanged();

private:
    QVariantMap m_current;
};

// Lock screen credential (singleton "Lock").
class LockState : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Lock)
    QML_SINGLETON

    Q_PROPERTY(bool hasPin READ hasPin NOTIFY changed)
    Q_PROPERTY(int pinLength READ pinLength NOTIFY changed)

public:
    explicit LockState(QObject *parent = nullptr);
    bool hasPin() const { return m_hasPin; }
    int pinLength() const { return m_length; }

    // callback(ok, error)
    Q_INVOKABLE void verify(const QString &pin, const QJSValue &callback);
    Q_INVOKABLE void setPin(const QString &current, const QString &pin, const QJSValue &callback);

Q_SIGNALS:
    void changed();

private:
    void reload();
    bool m_hasPin = false;
    int m_length = 0;
};

// The running app (singleton "Application"): identity, launch arguments
// and intents delivered while it is already running.
class ApplicationInfo : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Application)
    QML_SINGLETON

    Q_PROPERTY(QString packageName READ packageName CONSTANT)
    Q_PROPERTY(QVariantMap args READ args NOTIFY argsChanged)
    Q_PROPERTY(QString dataDir READ dataDir CONSTANT)
    Q_PROPERTY(QString mediaDir READ mediaDir CONSTANT)

public:
    explicit ApplicationInfo(QObject *parent = nullptr);
    QString packageName() const;
    QVariantMap args() const { return m_args; }
    QString dataDir() const;
    QString mediaDir() const; // shared user storage (/data/media/0, a.k.a. /sdcard)

    Q_INVOKABLE void quit();

Q_SIGNALS:
    void argsChanged();
    void intent(const QVariantMap &args);

private:
    QVariantMap m_args;
};

} // namespace astra::qml
