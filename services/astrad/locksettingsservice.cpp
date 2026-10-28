// SPDX-License-Identifier: Apache-2.0
#include "locksettingsservice.h"
#include "jsonstore.h"
#include "permissions.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QFile>
#include <QPasswordDigestor>
#include <QRandomGenerator>
#include <QRegularExpression>

namespace astrad {

using namespace astra;

namespace {
constexpr int kIterations = 20000;
constexpr int kFreeAttempts = 5;

QByteArray derive(const QString &pin, const QByteArray &salt)
{
    return QPasswordDigestor::deriveKeyPbkdf2(QCryptographicHash::Sha256, pin.toUtf8(), salt, kIterations, 32);
}

bool validPin(const QString &pin)
{
    static const QRegularExpression re(QStringLiteral("^[0-9]{4,8}$"));
    return re.match(pin).hasMatch();
}
} // namespace

LockSettingsService::LockSettingsService(Server *server, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_path(Paths::dataSystem() + QStringLiteral("/locksettings.json"))
{
    m_state = loadJson(m_path);
}

bool LockSettingsService::hasPin() const
{
    return m_state.contains(QLatin1String("hash"));
}

bool LockSettingsService::check(const QString &pin)
{
    if (!hasPin())
        return true;
    if (m_lockoutMs && m_lockout.isValid() && m_lockout.elapsed() < m_lockoutMs)
        throw RpcError{protocol::Failed, QStringLiteral("locked out for %1 s").arg((m_lockoutMs - m_lockout.elapsed()) / 1000 + 1)};

    const QByteArray salt = QByteArray::fromHex(m_state.value(QLatin1String("salt")).toString().toLatin1());
    const QByteArray expected = QByteArray::fromHex(m_state.value(QLatin1String("hash")).toString().toLatin1());
    if (derive(pin, salt) == expected) {
        m_failures = 0;
        m_lockoutMs = 0;
        return true;
    }
    if (++m_failures >= kFreeAttempts) {
        m_lockoutMs = 30000LL * (m_failures - kFreeAttempts + 1);
        m_lockout.start();
    }
    return false;
}

bool LockSettingsService::verifyPin(const QString &pin)
{
    try {
        return check(pin);
    } catch (const RpcError &) {
        return false;
    }
}

void LockSettingsService::store(const QString &pin)
{
    if (pin.isEmpty()) {
        m_state = {};
    } else {
        QByteArray salt(16, Qt::Uninitialized);
        QRandomGenerator::system()->fillRange(reinterpret_cast<quint32 *>(salt.data()), salt.size() / 4);
        m_state = {
            {QStringLiteral("salt"), QString::fromLatin1(salt.toHex())},
            {QStringLiteral("hash"), QString::fromLatin1(derive(pin, salt).toHex())},
            {QStringLiteral("length"), pin.size()},
        };
    }
    saveJson(m_path, m_state);
    QFile::setPermissions(m_path, QFile::ReadOwner | QFile::WriteOwner);
    m_server->broadcast(QStringLiteral("lock.changed"),
                        QJsonObject{{QStringLiteral("hasPin"), hasPin()}, {QStringLiteral("length"), m_state.value(QLatin1String("length"))}});
}

QJsonValue LockSettingsService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    if (call == QLatin1String("state")) {
        return QJsonObject{{QStringLiteral("hasPin"), hasPin()},
                           {QStringLiteral("length"), m_state.value(QLatin1String("length")).toInt(0)}};
    }
    if (call == QLatin1String("verify")) {
        caller.require(QLatin1String(permissions::MANAGE_LOCK));
        return check(params.value(QLatin1String("pin")).toString());
    }
    if (call == QLatin1String("setPin")) {
        caller.require(QLatin1String(permissions::MANAGE_LOCK));
        const QString pin = params.value(QLatin1String("pin")).toString();
        if (!pin.isEmpty() && !validPin(pin))
            throw RpcError{protocol::InvalidParams, QStringLiteral("the PIN must be 4 to 8 digits")};
        if (!check(params.value(QLatin1String("current")).toString()))
            throw RpcError{protocol::PermissionDenied, QStringLiteral("wrong current PIN")};
        store(pin);
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
