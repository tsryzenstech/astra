// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QElapsedTimer>

namespace astrad {

// Lock screen credential (numeric PIN). The PIN never leaves astrad: it is
// stored as a salted PBKDF2-SHA256 hash and only SysBoard may verify it.
// Repeated failures are throttled.
class LockSettingsService : public Service
{
    Q_OBJECT
public:
    LockSettingsService(Server *server, QObject *parent = nullptr);

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    bool hasPin() const;
    // Throttled PIN check; false on a wrong PIN or while locked out.
    bool verifyPin(const QString &pin);

private:
    bool check(const QString &pin);
    void store(const QString &pin);

    Server *m_server;
    QString m_path;
    QJsonObject m_state;
    int m_failures = 0;
    QElapsedTimer m_lockout;
    qint64 m_lockoutMs = 0;
};

} // namespace astrad
