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
    m_items = stored.value(QLatin1String("items")).toArray();
    m_nextId = qMax(1, stored.value(QLatin1String("nextId")).toInt());
    connect(packages, &PackageManager::packageRemoved, this, &NotificationService::removePackage);
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
    return out;
}

int NotificationService::post(const QString &package, const QString &title, const QString &body)
{
    const QJsonObject n{
        {QStringLiteral("id"), m_nextId++},
        {QStringLiteral("package"), package},
        {QStringLiteral("title"), title.left(kMaxText)},
        {QStringLiteral("body"), body.left(kMaxText)},
        {QStringLiteral("time"), double(QDateTime::currentMSecsSinceEpoch())},
    };
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
        const QString title = params.value(QLatin1String("title")).toString();
        if (title.isEmpty())
            throw RpcError{protocol::InvalidParams, QStringLiteral("title is required")};
        return post(package, title, params.value(QLatin1String("body")).toString());
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
            if (!manager && n.value(QLatin1String("package")).toString() != caller.package)
                throw RpcError{protocol::PermissionDenied, QStringLiteral("not your notification")};
            m_items.removeAt(i);
            save();
            m_server->broadcast(QStringLiteral("notifications.removed"), QJsonObject{{QStringLiteral("id"), id}});
            return true;
        }
        return false;
    }
    if (call == QLatin1String("clear")) {
        caller.require(QLatin1String(permissions::MANAGE_NOTIFICATIONS));
        m_items = {};
        save();
        m_server->broadcast(QStringLiteral("notifications.cleared"), QJsonValue());
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
