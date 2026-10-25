// SPDX-License-Identifier: Apache-2.0
#include "services.h"
#include "common.h"

#include <astra/client.h>
#include <astra/paths.h>

#include <QCoreApplication>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>

namespace astra::qml {

WeatherInfo::WeatherInfo(QObject *parent)
    : QObject(parent)
{
    Client *c = Client::instance();
    c->subscribe({QStringLiteral("weather")});
    connect(c, &Client::connectedChanged, this, [this](bool up) {
        if (up)
            refresh();
    });
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &data) {
        if (name == QLatin1String("weather.changed")) {
            m_current = data.toObject().toVariantMap();
            Q_EMIT currentChanged();
        }
    });
    if (c->isConnected())
        refresh();
}

void WeatherInfo::refresh()
{
    Client::instance()->call(QStringLiteral("weather.current"), {}, [this](const QJsonValue &r, const QString &) {
        m_current = r.toObject().toVariantMap();
        Q_EMIT currentChanged();
    });
}

LockState::LockState(QObject *parent)
    : QObject(parent)
{
    Client *c = Client::instance();
    c->subscribe({QStringLiteral("lock")});
    connect(c, &Client::connectedChanged, this, [this](bool up) {
        if (up)
            reload();
    });
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &) {
        if (name == QLatin1String("lock.changed"))
            reload();
    });
    if (c->isConnected())
        reload();
}

void LockState::reload()
{
    Client::instance()->call(QStringLiteral("lock.state"), {}, [this](const QJsonValue &r, const QString &) {
        const QJsonObject o = r.toObject();
        m_hasPin = o.value(QLatin1String("hasPin")).toBool();
        m_length = o.value(QLatin1String("length")).toInt();
        Q_EMIT changed();
    });
}

void LockState::verify(const QString &pin, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("lock.verify"), {{QStringLiteral("pin"), pin}},
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r.toBool(), e); });
}

void LockState::setPin(const QString &current, const QString &pin, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("lock.setPin"), {{QStringLiteral("current"), current}, {QStringLiteral("pin"), pin}},
                             [this, callback](const QJsonValue &r, const QString &e) {
                                 reload();
                                 invokeCallback(this, callback, r.toBool(), e);
                             });
}

ApplicationInfo::ApplicationInfo(QObject *parent)
    : QObject(parent)
{
    m_args = QJsonDocument::fromJson(qgetenv("ASTRA_LAUNCH_ARGS")).object().toVariantMap();
    connect(Client::instance(), &Client::event, this, [this](const QString &name, const QJsonValue &data) {
        if (name != QLatin1String("activity.intent"))
            return;
        m_args = data.toObject().toVariantMap();
        Q_EMIT argsChanged();
        Q_EMIT intent(m_args);
    });
}

QString ApplicationInfo::packageName() const
{
    return qEnvironmentVariable("ASTRA_PACKAGE");
}

QString ApplicationInfo::dataDir() const
{
    return QDir::homePath();
}

QString ApplicationInfo::mediaDir() const
{
    return Paths::userMedia();
}

void ApplicationInfo::quit()
{
    QCoreApplication::quit();
}

} // namespace astra::qml
