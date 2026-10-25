// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QHash>

namespace astrad {

class PackageManager;

// Media sessions: apps playing audio publish what they play (title, artist,
// artwork, position...). SysBoard shows the active session on the lock
// screen and in Control Center and sends transport commands back.
class MediaSessionService : public Service
{
    Q_OBJECT
public:
    MediaSessionService(Server *server, PackageManager *packages, QObject *parent = nullptr);

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;
    void release(const QString &package);

private:
    QJsonValue active() const;
    void announce();

    Server *m_server;
    PackageManager *m_packages;
    QHash<QString, QJsonObject> m_sessions;
};

} // namespace astrad
