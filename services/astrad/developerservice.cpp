// SPDX-License-Identifier: Apache-2.0
#include "developerservice.h"
#include "initcontrol.h"
#include "jsonstore.h"
#include "locksettingsservice.h"
#include "permissions.h"
#include "settingsservice.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QFile>
#include <QJsonArray>
#include <QLoggingCategory>
#include <QProcess>
#include <QTimer>

Q_LOGGING_CATEGORY(lcDev, "astrad.developer")

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s)
{
    return QString::fromLatin1(s);
}
} // namespace

DeveloperService::DeveloperService(Server *server, SettingsService *settings, LockSettingsService *lock, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_settings(settings)
    , m_lock(lock)
{
    QTimer::singleShot(2000, this, &DeveloperService::applyDaemon);
}

QString DeveloperService::keysPath()
{
    return Paths::resolve(QStringLiteral("/data/misc/adu/keys.json"));
}

QJsonObject DeveloperService::state() const
{
    QJsonArray hosts;
    const QJsonObject keys = loadJson(keysPath());
    for (auto it = keys.begin(); it != keys.end(); ++it) {
        QJsonObject h = it.value().toObject();
        h.remove(K("secret"));
        h.insert(K("fingerprint"), it.key());
        hosts.append(h);
    }
    return {
        {K("enabled"), m_settings->value(K("developer.enabled")).toBool()},
        {K("usbDebugging"), m_settings->value(K("developer.usb_debugging")).toBool()},
        {K("wireless"), m_settings->value(K("developer.wireless_debugging")).toBool()},
        {K("hosts"), hosts},
        {K("port"), 5560},
        {K("usbAddress"), K("10.42.0.1")},
    };
}

void DeveloperService::applyDaemon()
{
    const bool wanted = m_settings->value(K("developer.enabled")).toBool() &&
                        (m_settings->value(K("developer.usb_debugging")).toBool() ||
                         m_settings->value(K("developer.wireless_debugging")).toBool());
    if (Paths::isDevelopmentRoot()) {
        if (wanted && !m_devDaemon) {
            m_devDaemon = new QProcess(this);
            m_devDaemon->setProcessChannelMode(QProcess::ForwardedChannels);
            m_devDaemon->start(Paths::resolve(QStringLiteral("/system/bin/adud")), {});
            connect(m_devDaemon, &QProcess::finished, this, [this] {
                m_devDaemon->deleteLater();
                m_devDaemon = nullptr;
            });
        } else if (!wanted && m_devDaemon) {
            m_devDaemon->terminate();
        }
        return;
    }
    // On devices init owns the daemon (and the USB gadget it configures).
    if (!sendToInit(wanted ? "start adud" : "stop adud"))
        qCWarning(lcDev) << "init is not reachable, cannot" << (wanted ? "start" : "stop") << "adud";
}

QJsonValue DeveloperService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    if (call == QLatin1String("state"))
        return state();
    caller.require(QLatin1String(permissions::DEVELOPER));

    if (call == QLatin1String("setEnabled")) {
        const bool on = params.value(K("on")).toBool();
        if (on) {
            if (!m_lock->hasPin())
                throw RpcError{protocol::PermissionDenied, K("Set a lock screen PIN first")};
            if (!m_lock->verifyPin(params.value(K("pin")).toString()))
                throw RpcError{protocol::PermissionDenied, K("Wrong PIN")};
        }
        m_settings->setValue(K("developer.enabled"), on);
        if (!on) {
            m_settings->setValue(K("developer.usb_debugging"), false);
            m_settings->setValue(K("developer.wireless_debugging"), false);
        }
        applyDaemon();
        m_server->broadcast(K("developer.changed"), state());
        return state();
    }
    if (!m_settings->value(K("developer.enabled")).toBool())
        throw RpcError{protocol::PermissionDenied, K("Developer options are off")};

    if (call == QLatin1String("setUsbDebugging") || call == QLatin1String("setWireless")) {
        m_settings->setValue(call == QLatin1String("setWireless") ? K("developer.wireless_debugging")
                                                                   : K("developer.usb_debugging"),
                             params.value(K("on")).toBool());
        applyDaemon();
        m_server->broadcast(K("developer.changed"), state());
        return state();
    }
    if (call == QLatin1String("revokeAuthorizations")) {
        QFile::remove(keysPath());
        m_server->broadcast(K("developer.changed"), state());
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
