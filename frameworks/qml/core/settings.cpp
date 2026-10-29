// SPDX-License-Identifier: Apache-2.0
#include "settings.h"

#include <QJSValue>

#include <astra/client.h>

#include <QJsonObject>

namespace astra::qml {

SettingsStore::SettingsStore(QObject *parent)
    : QObject(parent)
{
    Client *c = Client::instance();
    c->subscribe({QStringLiteral("settings")});
    connect(c, &Client::connectedChanged, this, [this](bool up) {
        if (up)
            reload();
    });
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &data) {
        if (name != QLatin1String("settings.changed"))
            return;
        const QJsonObject o = data.toObject();
        const QString key = o.value(QLatin1String("key")).toString();
        const QVariant v = o.value(QLatin1String("value")).toVariant();
        if (m_values.value(key) == v)
            return;
        m_values.insert(key, v);
        Q_EMIT valuesChanged();
        Q_EMIT changed(key, v);
    });
    if (c->isConnected())
        reload();
}

void SettingsStore::reload()
{
    Client::instance()->call(QStringLiteral("settings.getAll"), {}, [this](const QJsonValue &r, const QString &) {
        m_values = r.toObject().toVariantMap();
        m_ready = true;
        Q_EMIT valuesChanged();
    });
}

QVariant SettingsStore::value(const QString &key, const QVariant &fallback) const
{
    return m_values.value(key, fallback);
}

void SettingsStore::setValue(const QString &key, const QVariant &raw)
{
    // JS arrays and objects arrive as QJSValue: turn them into plain lists
    // and maps, or they would reach astrad as null.
    const QVariant value = raw.metaType() == QMetaType::fromType<QJSValue>() ? raw.value<QJSValue>().toVariant() : raw;
    m_values.insert(key, value);
    Q_EMIT valuesChanged();
    Q_EMIT changed(key, value);
    Client::instance()->call(QStringLiteral("settings.set"),
                             {{QStringLiteral("key"), key}, {QStringLiteral("value"), QJsonValue::fromVariant(value)}});
}

void SettingsStore::reset(const QString &key)
{
    Client::instance()->call(QStringLiteral("settings.reset"), {{QStringLiteral("key"), key}});
}

} // namespace astra::qml
