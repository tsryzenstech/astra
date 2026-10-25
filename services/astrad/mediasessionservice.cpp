// SPDX-License-Identifier: Apache-2.0
#include "mediasessionservice.h"
#include "packagemanager.h"
#include "permissions.h"

#include <astra/protocol.h>

#include <QDateTime>

namespace astrad {

using namespace astra;

MediaSessionService::MediaSessionService(Server *server, PackageManager *packages, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_packages(packages)
{
    // A session dies with the app that owns it.
    connect(server, &Server::clientDisconnected, this, [this](const Caller &c) {
        if (!c.package.isEmpty())
            release(c.package);
    });
}

QJsonValue MediaSessionService::active() const
{
    // Prefer what is playing right now, then whatever changed last.
    QJsonObject best;
    for (const QJsonObject &s : m_sessions) {
        const bool playing = s.value(QLatin1String("playing")).toBool();
        const bool bestPlaying = best.value(QLatin1String("playing")).toBool();
        if (best.isEmpty() || (playing && !bestPlaying) ||
            (playing == bestPlaying && s.value(QLatin1String("updated")).toDouble() > best.value(QLatin1String("updated")).toDouble()))
            best = s;
    }
    return best.isEmpty() ? QJsonValue() : QJsonValue(best);
}

void MediaSessionService::announce()
{
    m_server->broadcast(QStringLiteral("media.changed"), active());
}

void MediaSessionService::release(const QString &package)
{
    if (m_sessions.remove(package))
        announce();
}

QJsonValue MediaSessionService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    if (call == QLatin1String("publish")) {
        if (caller.package.isEmpty())
            throw RpcError{protocol::InvalidParams, QStringLiteral("only apps own media sessions")};
        const QJsonObject info = m_packages->info(caller.package);
        QJsonObject s;
        for (const char *key : {"title", "artist", "album", "artwork", "duration", "position", "playing", "accent"})
            if (params.contains(QLatin1String(key)))
                s.insert(QLatin1String(key), params.value(QLatin1String(key)));
        if (s.value(QLatin1String("artwork")).toString().size() > 512 * 1024)
            s.remove(QStringLiteral("artwork"));
        s.insert(QStringLiteral("package"), caller.package);
        s.insert(QStringLiteral("appName"), info.value(QLatin1String("name")));
        s.insert(QStringLiteral("icon"), info.value(QLatin1String("icon")));
        s.insert(QStringLiteral("updated"), double(QDateTime::currentMSecsSinceEpoch()));
        m_sessions.insert(caller.package, s);
        announce();
        return true;
    }
    if (call == QLatin1String("release")) {
        release(caller.package);
        return true;
    }
    if (call == QLatin1String("current")) {
        caller.require(QLatin1String(permissions::MEDIA_CONTROL));
        return active();
    }
    if (call == QLatin1String("command")) {
        caller.require(QLatin1String(permissions::MEDIA_CONTROL));
        QString target = params.value(QLatin1String("package")).toString();
        if (target.isEmpty())
            target = active().toObject().value(QLatin1String("package")).toString();
        if (!m_sessions.contains(target))
            throw RpcError{protocol::NotFound, QStringLiteral("no media session")};
        m_server->sendToPackage(target, QStringLiteral("media.command"),
                                QJsonObject{{QStringLiteral("action"), params.value(QLatin1String("action"))},
                                            {QStringLiteral("position"), params.value(QLatin1String("position"))}});
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
