// SPDX-License-Identifier: Apache-2.0
#include "systemservice.h"
#include "notificationservice.h"
#include "packagemanager.h"
#include "permissions.h"
#include "settingsservice.h"

#include <astra/global.h>
#include <astra/paths.h>
#include <astra/properties.h>
#include <astra/protocol.h>

#include <QFile>
#include <QLoggingCategory>

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/utsname.h>
#include <unistd.h>

Q_LOGGING_CATEGORY(lcSystem, "astrad.system")

namespace astrad {

using namespace astra;

SystemService::SystemService(Server *server, SettingsService *settings, NotificationService *notifications,
                             PackageManager *packages, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_settings(settings)
    , m_notifications(notifications)
    , m_packages(packages)
{
}

QJsonObject SystemService::info() const
{
    struct utsname uts {};
    uname(&uts);
    double uptime = 0;
    QFile up(QStringLiteral("/proc/uptime"));
    if (up.open(QIODevice::ReadOnly))
        uptime = up.readAll().split(' ').value(0).toDouble();
    return {
        {QStringLiteral("name"), QStringLiteral("astraOS")},
        {QStringLiteral("version"), QString::fromLatin1(astra::version())},
        {QStringLiteral("release"), Properties::get(QStringLiteral("ro.astra.release"))},
        {QStringLiteral("apiLevel"), Properties::getInt(QStringLiteral("ro.astra.api_level"), 1)},
        {QStringLiteral("buildType"), Properties::get(QStringLiteral("ro.build.type"))},
        {QStringLiteral("display"), Properties::get(QStringLiteral("ro.build.display.id"))},
        {QStringLiteral("device"), Properties::get(QStringLiteral("ro.product.device"), QStringLiteral("generic"))},
        {QStringLiteral("model"), Properties::get(QStringLiteral("ro.product.model"), QStringLiteral("astra development device"))},
        {QStringLiteral("manufacturer"), Properties::get(QStringLiteral("ro.product.manufacturer"))},
        {QStringLiteral("kernel"), QString::fromLatin1(uts.release)},
        {QStringLiteral("architecture"), QString::fromLatin1(uts.machine)},
        {QStringLiteral("qt"), QString::fromLatin1(qVersion())},
        {QStringLiteral("uptime"), uptime},
        {QStringLiteral("bootCompleted"), m_bootCompleted},
        {QStringLiteral("development"), Paths::isDevelopmentRoot()},
    };
}

void SystemService::bootCompleted()
{
    if (m_bootCompleted)
        return;
    m_bootCompleted = true;
    qCInfo(lcSystem) << "boot completed";

    // First boot: Tips welcomes the user (a real notification, dismissable).
    if (!m_settings->value(QStringLiteral("system.welcome_posted")).toBool() &&
        m_packages->contains(QStringLiteral("com.astra.tips"))) {
        m_notifications->post(QStringLiteral("com.astra.tips"),
                              QStringLiteral("Welcome to astra! Start by configuring your device."),
                              QStringLiteral("Open Settings to connect to Wi-Fi, set a lock screen PIN and choose your widgets."));
        m_settings->setValue(QStringLiteral("system.welcome_posted"), true);
    }
    m_server->broadcast(QStringLiteral("system.bootCompleted"), true);
}

bool SystemService::sendToInit(const QByteArray &command)
{
    const int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (fd < 0)
        return false;
    sockaddr_un addr {};
    addr.sun_family = AF_UNIX;
    const QByteArray path = QFile::encodeName(Paths::initSocket());
    qstrncpy(addr.sun_path, path.constData(), sizeof(addr.sun_path));
    const bool ok = sendto(fd, command.constData(), size_t(command.size()), 0,
                           reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) == command.size();
    close(fd);
    return ok;
}

QJsonValue SystemService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    if (call == QLatin1String("ping"))
        return QStringLiteral("pong");
    if (call == QLatin1String("info"))
        return info();
    if (call == QLatin1String("bootCompleted")) {
        caller.requireSystem();
        bootCompleted();
        return true;
    }
    if (call == QLatin1String("power")) {
        caller.require(QLatin1String(permissions::POWER));
        const QString action = params.value(QLatin1String("action")).toString();
        QByteArray command;
        if (action == QLatin1String("reboot"))
            command = "reboot";
        else if (action == QLatin1String("poweroff"))
            command = "poweroff";
        else if (action == QLatin1String("bootloader") || action == QLatin1String("recovery"))
            command = "reboot " + action.toLatin1();
        else if (action == QLatin1String("restart-sysboard"))
            command = "restart sysboard";
        else
            throw RpcError{protocol::InvalidParams, QStringLiteral("unknown power action %1").arg(action)};
        qCInfo(lcSystem) << "power request" << command << "from" << (caller.isSystem() ? QStringLiteral("system") : caller.package);
        if (!sendToInit(command))
            throw RpcError{protocol::Failed, QStringLiteral("init is not reachable")};
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
