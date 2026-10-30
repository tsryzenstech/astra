// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QFileSystemWatcher>
#include <QHash>
#include <QJSValue>
#include <QColor>
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
    // The app's own colour ("accent" in app.json), or the user's system
    // accent when the app has none. The only colour an app may add to Theme.
    Q_PROPERTY(QColor accent READ accent CONSTANT)

public:
    explicit ApplicationInfo(QObject *parent = nullptr);
    QColor accent() const;
    QString packageName() const;
    QVariantMap args() const { return m_args; }
    QString dataDir() const;
    QString mediaDir() const; // shared user storage (/data/media/0, a.k.a. /sdcard)

    Q_INVOKABLE void quit();

    // Shared storage (needs the MEDIA permission). Paths are absolute.
    // media(["*.png", "*.jpg"]) -> [{ path, url, name, folder, modified, size, video }], newest first
    Q_INVOKABLE QVariantList media(const QStringList &nameFilters) const;
    // The same list, scanned on a worker thread: callback(list). Galleries
    // use it so the first frame doesn't wait for the storage.
    Q_INVOKABLE void mediaAsync(const QStringList &nameFilters, const QJSValue &callback);
    Q_INVOKABLE bool removeMedia(const QString &path);
    Q_INVOKABLE QVariantMap imageInfo(const QString &path) const; // width, height, size, modified

Q_SIGNALS:
    void argsChanged();
    void intent(const QVariantMap &args);
    void mediaChanged();   // something was added to or removed from shared storage

private:
    void watchMedia();

    QVariantMap m_args;
    QFileSystemWatcher *m_watcher = nullptr;
    int m_mediaRequest = 0;
    QHash<int, QJSValue> m_mediaCallbacks;
};

} // namespace astra::qml
