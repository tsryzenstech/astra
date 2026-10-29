// SPDX-License-Identifier: Apache-2.0
#include "system.h"
#include "common.h"

#include <astra/client.h>
#include <astra/global.h>
#include <astra/paths.h>
#include <astra/properties.h>

#include <QDateTime>
#include <QDir>
#include <QTimeZone>
#include <QJsonObject>

namespace astra::qml {

SystemInfo::SystemInfo(QObject *parent)
    : QObject(parent)
{
    Client *c = Client::instance();
    c->subscribe({QStringLiteral("hardware"), QStringLiteral("system")});
    connect(c, &Client::connectedChanged, this, [this](bool up) {
        Q_EMIT connectedChanged();
        if (up)
            reload();
    });
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &data) {
        if (name == QLatin1String("hardware.battery")) {
            m_hw.insert(QStringLiteral("battery"), data.toVariant());
            Q_EMIT hardwareChanged();
        } else if (name == QLatin1String("hardware.changed")) {
            const QJsonObject o = data.toObject();
            m_hw.insert(o.value(QLatin1String("key")).toString(), o.value(QLatin1String("value")).toVariant());
            Q_EMIT hardwareChanged();
        } else if (name == QLatin1String("system.bootCompleted")) {
            reload();
            Q_EMIT bootCompleted();
        }
    });
    if (c->isConnected())
        reload();
}

void SystemInfo::reload()
{
    Client::instance()->call(QStringLiteral("system.info"), {}, [this](const QJsonValue &r, const QString &) {
        m_info = r.toObject().toVariantMap();
        Q_EMIT infoChanged();
    });
    Client::instance()->call(QStringLiteral("hardware.state"), {}, [this](const QJsonValue &r, const QString &) {
        if (r.isObject()) {
            m_hw = r.toObject().toVariantMap();
            Q_EMIT hardwareChanged();
        }
    });
}

bool SystemInfo::connected() const
{
    return Client::instance()->isConnected();
}

int SystemInfo::batteryLevel() const
{
    // -1 when there is no battery.
    const QVariantMap b = m_hw.value(QStringLiteral("battery")).toMap();
    return b.value(QStringLiteral("present")).toBool() ? b.value(QStringLiteral("level")).toInt() : -1;
}

bool SystemInfo::charging() const
{
    return m_hw.value(QStringLiteral("battery")).toMap().value(QStringLiteral("charging")).toBool();
}

QString SystemInfo::version() const
{
    return QString::fromLatin1(astra::version());
}

void SystemInfo::setBrightness(qreal value)
{
    m_hw.insert(QStringLiteral("brightness"), value); // optimistic, keeps sliders smooth
    Q_EMIT hardwareChanged();
    Client::instance()->call(QStringLiteral("hardware.setBrightness"), {{QStringLiteral("value"), value}});
}

void SystemInfo::setTorch(bool on)
{
    Client::instance()->call(QStringLiteral("hardware.setTorch"), {{QStringLiteral("on"), on}});
}

void SystemInfo::setScreen(bool on)
{
    Client::instance()->call(QStringLiteral("hardware.setScreen"), {{QStringLiteral("on"), on}});
}

void SystemInfo::screenshot(const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("system.screenshot"), {},
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

void SystemInfo::power(const QString &action, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("system.power"), {{QStringLiteral("action"), action}},
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

void SystemInfo::markBootCompleted()
{
    Client::instance()->call(QStringLiteral("system.bootCompleted"));
}

QString SystemInfo::property(const QString &key, const QString &fallback) const
{
    return Properties::get(key, fallback);
}

QUrl SystemInfo::fileUrl(const QString &path) const
{
    return QUrl::fromLocalFile(Paths::resolve(path));
}

QVariantMap SystemInfo::zone(const QString &ianaId) const
{
    const QTimeZone tz(ianaId.toLatin1());
    if (!tz.isValid())
        return {{QStringLiteral("valid"), false}};
    const QDateTime now = QDateTime::currentDateTime();
    const QDateTime there = now.toTimeZone(tz);
    return {
        {QStringLiteral("valid"), true},
        {QStringLiteral("time"), there.toString(QStringLiteral("HH:mm"))},
        {QStringLiteral("hour"), there.time().hour()},
        {QStringLiteral("offset"), tz.offsetFromUtc(now) - now.offsetFromUtc()},
        {QStringLiteral("dayShift"), int(now.date().daysTo(there.date()))},
        {QStringLiteral("city"), ianaId.section(QLatin1Char('/'), -1).replace(QLatin1Char('_'), QLatin1Char(' '))},
    };
}

QStringList SystemInfo::files(const QString &dir, const QStringList &nameFilters) const
{
    QStringList out;
    if (!dir.startsWith(QLatin1String("/system/")) && !dir.startsWith(QLatin1String("/product/")) &&
        !dir.startsWith(QLatin1String("/vendor/")))
        return out; // read-only system locations only
    const QDir d(Paths::resolve(dir));
    for (const QString &f : d.entryList(nameFilters, QDir::Files, QDir::Name))
        out.append(dir + QLatin1Char('/') + f);
    return out;
}

void SystemInfo::call(const QString &method, const QVariantMap &params, const QJSValue &callback)
{
    Client::instance()->call(method, QJsonObject::fromVariantMap(params),
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

} // namespace astra::qml
