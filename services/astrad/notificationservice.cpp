// SPDX-License-Identifier: Apache-2.0
#include "notificationservice.h"
#include "jsonstore.h"
#include "packagemanager.h"
#include "permissions.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QDateTime>

namespace astrad {

using namespace astra;

namespace {
constexpr int kMaxNotifications = 50;
constexpr int kMaxText = 1024;
}

NotificationService::NotificationService(Server *server, PackageManager *packages, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_packages(packages)
    , m_path(Paths::dataSystem() + QStringLiteral("/notifications.json"))
{
    const QJsonObject stored = loadJson(m_path);
    m_nextId = qMax(1, stored.value(QLatin1String("nextId")).toInt());
    // Ongoing notifications (a download, a recording) describe work that
    // died with the previous boot.
    for (const QJsonValue &v : stored.value(QLatin1String("items")).toArray())
        if (!v.toObject().value(QLatin1String("ongoing")).toBool())
            m_items.append(v);
    connect(packages, &PackageManager::packageRemoved, this, &NotificationService::removePackage);
    // ... and with the app that runs it.
    connect(server, &Server::clientDisconnected, this, [this](const Caller &c) {
        if (!c.package.isEmpty())
            removeOngoing(c.package);
    });
}

void NotificationService::removeOngoing(const QString &package)
{
    bool changed = false;
    for (int i = m_items.size() - 1; i >= 0; --i) {
        const QJsonObject n = m_items.at(i).toObject();
        if (n.value(QLatin1String("package")).toString() == package && n.value(QLatin1String("ongoing")).toBool()) {
            m_items.removeAt(i);
            changed = true;
            m_server->broadcast(QStringLiteral("notifications.removed"), QJsonObject{{QStringLiteral("id"), n.value(QLatin1String("id"))}});
        }
    }
    if (changed)
        save();
}

// Ongoing notifications cannot be dismissed by the user: they last until
// the app updates them into a normal one, removes them or exits.
// "progress" is 0..1, or -1 for work of unknown length.
void NotificationService::applyOptions(QJsonObject &n, const QJsonObject &params)
{
    if (!params.value(QLatin1String("title")).toString().isEmpty())
        n.insert(QStringLiteral("title"), params.value(QLatin1String("title")).toString().left(kMaxText));
    if (params.contains(QLatin1String("body")))
        n.insert(QStringLiteral("body"), params.value(QLatin1String("body")).toString().left(kMaxText));
    if (params.contains(QLatin1String("ongoing")))
        n.insert(QStringLiteral("ongoing"), params.value(QLatin1String("ongoing")).toBool());
    if (params.contains(QLatin1String("progress"))) {
        const QJsonValue p = params.value(QLatin1String("progress"));
        if (!p.isDouble())
            n.remove(QStringLiteral("progress"));
        else
            n.insert(QStringLiteral("progress"), p.toDouble() < 0 ? -1.0 : qBound(0.0, p.toDouble(), 1.0));
    }
    // Launch arguments for the app when the notification is opened.
    if (params.value(QLatin1String("args")).isObject())
        n.insert(QStringLiteral("args"), params.value(QLatin1String("args")));
}

void NotificationService::save()
{
    saveJson(m_path, {{QStringLiteral("items"), m_items}, {QStringLiteral("nextId"), m_nextId}});
}

// Adds the app name and icon so SysBoard does not need a second lookup.
QJsonObject NotificationService::decorate(const QJsonObject &n) const
{
    QJsonObject out = n;
    const QJsonObject info = m_packages->info(n.value(QLatin1String("package")).toString());
    out.insert(QStringLiteral("appName"), info.value(QLatin1String("name")).toString(n.value(QLatin1String("package")).toString()));
    out.insert(QStringLiteral("icon"), info.value(QLatin1String("icon")));
    out.insert(QStringLiteral("accent"), info.value(QLatin1String("accent")));
    return out;
}

int NotificationService::post(const QString &package, const QString &title, const QString &body, const QJsonObject &options)
{
    QJsonObject n{
        {QStringLiteral("id"), m_nextId++},
        {QStringLiteral("package"), package},
        {QStringLiteral("title"), title.left(kMaxText)},
        {QStringLiteral("body"), body.left(kMaxText)},
        {QStringLiteral("time"), double(QDateTime::currentMSecsSinceEpoch())},
    };
    applyOptions(n, options);
    m_items.prepend(n);
    while (m_items.size() > kMaxNotifications)
        m_items.removeLast();
    save();
    m_server->broadcast(QStringLiteral("notifications.posted"), decorate(n));
    return n.value(QLatin1String("id")).toInt();
}

void NotificationService::removePackage(const QString &package)
{
    for (int i = m_items.size() - 1; i >= 0; --i) {
        const QJsonObject n = m_items.at(i).toObject();
        if (n.value(QLatin1String("package")).toString() == package) {
            m_items.removeAt(i);
            m_server->broadcast(QStringLiteral("notifications.removed"), QJsonObject{{QStringLiteral("id"), n.value(QLatin1String("id"))}});
        }
    }
    save();
}

bool NotificationService::dismissId(int id)
{
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i).toObject().value(QLatin1String("id")).toInt() != id)
            continue;
        m_items.removeAt(i);
        save();
        m_server->broadcast(QStringLiteral("notifications.removed"), QJsonObject{{QStringLiteral("id"), id}});
        return true;
    }
    return false;
}

QJsonValue NotificationService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    const bool manager = caller.can(QLatin1String(permissions::MANAGE_NOTIFICATIONS));

    if (call == QLatin1String("post")) {
        QString package = caller.package;
        // Managers (the system, Settings' test tools) may post for any app.
        if (params.contains(QLatin1String("package")) && manager)
            package = params.value(QLatin1String("package")).toString();
        if (package.isEmpty() || !m_packages->contains(package))
            throw RpcError{protocol::InvalidParams, QStringLiteral("unknown package")};
        // Apps need the (runtime) NOTIFICATIONS permission; the user can
        // turn notifications of any app off in Settings > Notifications.
        if (!manager && !m_packages->isGranted(package, QLatin1String(permissions::NOTIFICATIONS)))
            throw RpcError{protocol::PermissionDenied, QStringLiteral("notifications are not allowed for %1").arg(package)};
        const QString title = params.value(QLatin1String("title")).toString();
        if (title.isEmpty())
            throw RpcError{protocol::InvalidParams, QStringLiteral("title is required")};
        return post(package, title, params.value(QLatin1String("body")).toString(), params);
    }
    if (call == QLatin1String("update")) {
        // { id, title?, body?, ongoing?, progress?, args?, alert? }: alert
        // shows the banner again (e.g. "Download complete").
        const int id = params.value(QLatin1String("id")).toInt();
        for (int i = 0; i < m_items.size(); ++i) {
            QJsonObject n = m_items.at(i).toObject();
            if (n.value(QLatin1String("id")).toInt() != id)
                continue;
            if (!manager && n.value(QLatin1String("package")).toString() != caller.package)
                throw RpcError{protocol::PermissionDenied, QStringLiteral("not your notification")};
            applyOptions(n, params);
            const bool alert = params.value(QLatin1String("alert")).toBool();
            if (alert)
                n.insert(QStringLiteral("time"), double(QDateTime::currentMSecsSinceEpoch()));
            m_items.replace(i, n);
            // Progress changes several times a second: only what lasts is saved.
            if (!n.value(QLatin1String("ongoing")).toBool() || params.contains(QLatin1String("ongoing")))
                save();
            QJsonObject event = decorate(n);
            if (alert)
                event.insert(QStringLiteral("alert"), true);
            m_server->broadcast(QStringLiteral("notifications.updated"), event);
            return true;
        }
        return false;
    }
    if (call == QLatin1String("list")) {
        QJsonArray out;
        for (const QJsonValue &v : std::as_const(m_items)) {
            const QJsonObject n = v.toObject();
            if (manager || n.value(QLatin1String("package")).toString() == caller.package)
                out.append(decorate(n));
        }
        return out;
    }
    if (call == QLatin1String("dismiss")) {
        const int id = params.value(QLatin1String("id")).toInt();
        for (int i = 0; i < m_items.size(); ++i) {
            const QJsonObject n = m_items.at(i).toObject();
            if (n.value(QLatin1String("id")).toInt() != id)
                continue;
            const bool own = n.value(QLatin1String("package")).toString() == caller.package;
            if (!manager && !own)
                throw RpcError{protocol::PermissionDenied, QStringLiteral("not your notification")};
            // Only the app ends an ongoing notification.
            if (!own && n.value(QLatin1String("ongoing")).toBool())
                return false;
            m_items.removeAt(i);
            save();
            m_server->broadcast(QStringLiteral("notifications.removed"), QJsonObject{{QStringLiteral("id"), id}});
            return true;
        }
        return false;
    }
    if (call == QLatin1String("clear")) {
        caller.require(QLatin1String(permissions::MANAGE_NOTIFICATIONS));
        // Ongoing notifications stay.
        for (int i = m_items.size() - 1; i >= 0; --i) {
            const QJsonObject n = m_items.at(i).toObject();
            if (n.value(QLatin1String("ongoing")).toBool())
                continue;
            m_items.removeAt(i);
            m_server->broadcast(QStringLiteral("notifications.removed"), QJsonObject{{QStringLiteral("id"), n.value(QLatin1String("id"))}});
        }
        save();
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
