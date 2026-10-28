// SPDX-License-Identifier: Apache-2.0
#include "dialogservice.h"
#include "packagemanager.h"

#include <astra/protocol.h>

#include <QTimer>

namespace astrad {

using namespace astra;

DialogService::DialogService(Server *server, PackageManager *packages, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_packages(packages)
{
    // Dialogs of an app that went away are cancelled.
    connect(server, &Server::clientDisconnected, this, [this](const Caller &c) {
        if (c.package.isEmpty())
            return;
        const QList<int> ids = m_pending.keys();
        for (int id : ids)
            if (m_pending.value(id).dialog.value(QLatin1String("package")).toString() == c.package &&
                m_pending.value(id).dialog.value(QLatin1String("fromApp")).toBool())
                finish(id, m_pending.value(id).cancelButton);
    });
}

int DialogService::show(const QString &package, const QJsonObject &content, const QString &cancelButton, Callback callback)
{
    const int id = m_nextId++;
    QJsonObject dialog = content;
    dialog.insert(QStringLiteral("id"), id);
    dialog.insert(QStringLiteral("package"), package);
    if (!package.isEmpty()) {
        const QJsonObject info = m_packages->info(package);
        dialog.insert(QStringLiteral("appName"), info.value(QLatin1String("name")));
        dialog.insert(QStringLiteral("appIcon"), info.value(QLatin1String("icon")));
    }
    m_pending.insert(id, {dialog, cancelButton, std::move(callback)});
    m_order.append(id);

    if (!m_server->hasSystemSubscriber(QStringLiteral("dialogs"))) {
        // No shell to show it (e.g. SysBoard restarting): answer safely.
        QTimer::singleShot(0, this, [this, id, cancelButton] { finish(id, cancelButton); });
        return id;
    }
    m_server->broadcast(QStringLiteral("dialogs.show"), dialog);
    return id;
}

void DialogService::finish(int id, const QString &button)
{
    if (!m_pending.contains(id))
        return;
    const Pending p = m_pending.take(id);
    m_order.removeAll(id);
    m_server->broadcast(QStringLiteral("dialogs.closed"), QJsonObject{{QStringLiteral("id"), id}});
    if (p.callback)
        p.callback(button);
}

QJsonValue DialogService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    if (call == QLatin1String("show")) {
        const QJsonArray buttons = params.value(QLatin1String("buttons")).toArray();
        if (params.value(QLatin1String("title")).toString().isEmpty() || buttons.isEmpty() || buttons.size() > 3)
            throw RpcError{protocol::InvalidParams, QStringLiteral("a dialog needs a title and 1 to 3 buttons")};
        QJsonObject content{
            {QStringLiteral("title"), params.value(QLatin1String("title")).toString().left(120)},
            {QStringLiteral("message"), params.value(QLatin1String("message")).toString().left(600)},
            {QStringLiteral("icon"), params.value(QLatin1String("icon"))},
            {QStringLiteral("buttons"), buttons},
            {QStringLiteral("fromApp"), !caller.isSystem()},
        };
        // System callers may describe well-known dialogs so SysBoard can
        // present (and translate) them properly.
        if (caller.isSystem()) {
            content.insert(QStringLiteral("kind"), params.value(QLatin1String("kind")));
            content.insert(QStringLiteral("details"), params.value(QLatin1String("details")));
        }
        const QString cancel = buttons.first().toObject().value(QLatin1String("id")).toString();
        const PendingReply reply = caller.defer();
        show(caller.package, content, cancel, [reply](const QString &button) { reply.resolve(button); });
        return Deferred;
    }
    if (call == QLatin1String("answer")) {
        caller.requireSystem();
        finish(params.value(QLatin1String("id")).toInt(), params.value(QLatin1String("button")).toString());
        return true;
    }
    if (call == QLatin1String("pending")) {
        caller.requireSystem();
        QJsonArray out;
        for (int id : std::as_const(m_order))
            out.append(m_pending.value(id).dialog);
        return out;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
