// SPDX-License-Identifier: Apache-2.0
#include "settingsservice.h"
#include "jsonstore.h"
#include "permissions.h"

#include <astra/paths.h>
#include <astra/protocol.h>

namespace astrad {

using namespace astra;

SettingsService::SettingsService(Server *server, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_path(Paths::dataSystem() + QStringLiteral("/settings.json"))
{
    m_defaults = loadJson(Paths::resolve(QStringLiteral("/system/etc/settings/defaults.json")));
    const QJsonObject vendor = loadJson(Paths::resolve(QStringLiteral("/vendor/etc/settings/defaults.json")));
    for (auto it = vendor.begin(); it != vendor.end(); ++it)
        m_defaults.insert(it.key(), it.value());
    m_values = loadJson(m_path);
}

QJsonValue SettingsService::value(const QString &key) const
{
    return m_values.contains(key) ? m_values.value(key) : m_defaults.value(key);
}

void SettingsService::setValue(const QString &key, const QJsonValue &v)
{
    if (value(key) == v)
        return;
    if (v.isNull() || v.isUndefined())
        m_values.remove(key);
    else
        m_values.insert(key, v);
    saveJson(m_path, m_values);
    const QJsonValue effective = value(key);
    Q_EMIT changed(key, effective);
    m_server->broadcast(QStringLiteral("settings.changed"),
                        QJsonObject{{QStringLiteral("key"), key}, {QStringLiteral("value"), effective}},
                        [key](const Caller &c) { return !key.startsWith(QLatin1String("secure.")) || c.isSystem(); });
}

// Who may change a key besides MANAGE_SETTINGS holders: an app owns its
// "app.<package>." namespace, a few system apps own their feature's keys.
bool SettingsService::mayWrite(const QString &key, const Caller &caller) const
{
    if (caller.can(QLatin1String(permissions::MANAGE_SETTINGS)))
        return true;
    if (key.startsWith(QStringLiteral("app.%1.").arg(caller.package)))
        return true;
    static const QHash<QString, QString> owners{
        {QStringLiteral("weather."), QStringLiteral("com.astra.weather")},
        {QStringLiteral("clock."), QStringLiteral("com.astra.clock")},
        {QStringLiteral("market."), QStringLiteral("com.astra.market")},
        {QStringLiteral("planet."), QStringLiteral("com.astra.planet")},
        {QStringLiteral("camera."), QStringLiteral("com.astra.camera")},
    };
    for (auto it = owners.cbegin(); it != owners.cend(); ++it)
        if (key.startsWith(it.key()) && caller.package == it.value())
            return true;
    if ((key.startsWith(QLatin1String("ui.")) || key.startsWith(QLatin1String("lockscreen.")) ||
         key.startsWith(QLatin1String("wallpaper."))) && caller.can(QLatin1String(permissions::MANAGE_THEMES)))
        return true;
    return false;
}

QJsonValue SettingsService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    const QString key = params.value(QLatin1String("key")).toString();
    const bool secure = key.startsWith(QLatin1String("secure."));

    if (call == QLatin1String("get")) {
        if (secure)
            caller.requireSystem();
        return value(key);
    }
    if (call == QLatin1String("getAll")) {
        const QString prefix = params.value(QLatin1String("prefix")).toString();
        QJsonObject out;
        auto collect = [&](const QJsonObject &src) {
            for (auto it = src.begin(); it != src.end(); ++it)
                if (it.key().startsWith(prefix) && (!it.key().startsWith(QLatin1String("secure.")) || caller.isSystem()))
                    out.insert(it.key(), it.value());
        };
        collect(m_defaults);
        collect(m_values);
        return out;
    }
    if (call == QLatin1String("set") || call == QLatin1String("reset")) {
        if (key.isEmpty())
            throw RpcError{protocol::InvalidParams, QStringLiteral("key is required")};
        if (secure)
            caller.requireSystem();
        if (!mayWrite(key, caller))
            throw RpcError{protocol::PermissionDenied, QStringLiteral("%1 cannot change %2").arg(caller.package, key)};
        setValue(key, call == QLatin1String("set") ? params.value(QLatin1String("value")) : QJsonValue());
        return value(key);
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
