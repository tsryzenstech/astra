// SPDX-License-Identifier: Apache-2.0
#include "systemservice.h"
#include "initcontrol.h"
#include "notificationservice.h"
#include "packagemanager.h"
#include "permissions.h"
#include "settingsservice.h"

#include <astra/global.h>
#include <astra/paths.h>
#include <astra/properties.h>
#include <astra/protocol.h>

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QLoggingCategory>
#include <QStorageInfo>
#include <QThread>
#include <QTimeZone>
#include <QTimer>

#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>

Q_LOGGING_CATEGORY(lcSystem, "astrad.system")

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s)
{
    return QString::fromLatin1(s);
}

QString readTrimmed(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QString::fromUtf8(f.readAll()).remove(QChar(0)).trimmed() : QString();
}

// Human readable SoC name: vendor property, kernel socinfo, then cpuinfo.
QString cpuName()
{
    const QString prop = Properties::get(K("ro.vendor.cpu"));
    if (!prop.isEmpty())
        return prop;
    const QString soc = readTrimmed(K("/sys/devices/soc0/machine"));
    if (!soc.isEmpty())
        return QStringLiteral("Qualcomm %1").arg(soc);
    QFile f(K("/proc/cpuinfo"));
    if (f.open(QIODevice::ReadOnly)) {
        for (const QByteArray &line : f.readAll().split('\n')) {
            if (line.startsWith("model name") || line.startsWith("Hardware")) {
                const int colon = line.indexOf(':');
                if (colon > 0)
                    return QString::fromUtf8(line.mid(colon + 1)).trimmed();
            }
        }
    }
    return {};
}

qint64 memInfo(const char *key)
{
    QFile f(K("/proc/meminfo"));
    if (!f.open(QIODevice::ReadOnly))
        return 0;
    for (const QByteArray &line : f.readAll().split('\n'))
        if (line.startsWith(key))
            return line.mid(qstrlen(key)).trimmed().split(' ').value(0).toLongLong() * 1024;
    return 0;
}
} // namespace

SystemService::SystemService(Server *server, SettingsService *settings, NotificationService *notifications,
                             PackageManager *packages, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_settings(settings)
    , m_notifications(notifications)
    , m_packages(packages)
{
    applyTimezone(m_settings->value(K("system.timezone")).toString());
}

void SystemService::applyTimezone(const QString &tz)
{
    if (tz.isEmpty())
        return;
    qputenv("TZ", tz.toUtf8());
    tzset();
}

QJsonObject SystemService::info() const
{
    struct utsname uts {};
    uname(&uts);
    double uptime = readTrimmed(K("/proc/uptime")).split(' ').value(0).toDouble();
    const QStorageInfo storage(Paths::dataDir());
    const QString model = Properties::get(K("ro.product.model"), K("astra development device"));
    return {
        {K("name"), K("astraOS")},
        {K("version"), Properties::get(K("ro.astra.version"), QString::fromLatin1(astra::version()))},
        {K("codename"), Properties::get(K("ro.astra.codename"))},
        {K("channel"), Properties::get(K("ro.astra.channel"))},
        {K("build"), Properties::getInt(K("ro.astra.build.number"), 0)},
        {K("buildId"), Properties::get(K("ro.astra.build.id"))},
        {K("buildDate"), Properties::get(K("ro.astra.build.date")).toDouble()},
        {K("commit"), Properties::get(K("ro.astra.build.commit"))},
        {K("apiLevel"), Properties::getInt(K("ro.astra.api_level"), 1)},
        {K("buildType"), Properties::get(K("ro.build.type"))},
        {K("display"), Properties::get(K("ro.build.display.id"))},
        {K("device"), Properties::get(K("ro.product.device"), K("generic"))},
        {K("model"), model},
        {K("deviceName"), m_settings->value(K("system.device_name")).toString(model)},
        {K("manufacturer"), Properties::get(K("ro.product.manufacturer"))},
        {K("cpu"), cpuName()},
        {K("cores"), QThread::idealThreadCount()},
        {K("ram"), double(memInfo("MemTotal:"))},
        {K("ramAvailable"), double(memInfo("MemAvailable:"))},
        {K("storageTotal"), double(storage.bytesTotal())},
        {K("storageFree"), double(storage.bytesAvailable())},
        {K("kernel"), QString::fromLatin1(uts.release)},
        {K("serial"), [] {
             QFile f(QStringLiteral("/sys/devices/soc0/serial_number"));
             const QString soc = f.open(QIODevice::ReadOnly) ? QString::fromLatin1(f.readAll()).trimmed() : QString();
             return Properties::get(QStringLiteral("ro.serialno"), soc);
         }()},
        {K("architecture"), QString::fromLatin1(uts.machine)},
        {K("qt"), QString::fromLatin1(qVersion())},
        {K("uptime"), uptime},
        {K("bootCompleted"), m_bootCompleted},
        {K("development"), Paths::isDevelopmentRoot()},
    };
}

void SystemService::bootCompleted()
{
    if (m_bootCompleted)
        return;
    m_bootCompleted = true;
    qCInfo(lcSystem) << "boot completed";

    // First boot: Tips welcomes the user (a real notification, dismissable).
    if (!m_settings->value(K("system.welcome_posted")).toBool() && m_packages->contains(K("com.astra.tips"))) {
        m_notifications->post(K("com.astra.tips"), K("Welcome to astra! Start by configuring your device."),
                              K("Open Settings to connect to Wi-Fi, set a PIN and choose your widgets."));
        m_settings->setValue(K("system.welcome_posted"), true);
    }
    m_server->broadcast(K("system.bootCompleted"), true);
}

QJsonValue SystemService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    if (call == QLatin1String("ping"))
        return K("pong");
    if (call == QLatin1String("info"))
        return info();
    if (call == QLatin1String("timezones")) {
        QJsonArray out;
        for (const QByteArray &id : QTimeZone::availableTimeZoneIds())
            out.append(QString::fromLatin1(id));
        return out;
    }
    if (call == QLatin1String("bootCompleted")) {
        caller.requireSystem();
        bootCompleted();
        return true;
    }
    if (call == QLatin1String("setTimezone")) {
        caller.require(QLatin1String(permissions::MANAGE_SETTINGS));
        const QString tz = params.value(K("timezone")).toString();
        if (!QTimeZone(tz.toLatin1()).isValid())
            throw RpcError{protocol::InvalidParams, QStringLiteral("unknown time zone %1").arg(tz)};
        m_settings->setValue(K("system.timezone"), tz);
        applyTimezone(tz);
        m_server->broadcast(K("system.timezone"), tz);
        return true;
    }
    if (call == QLatin1String("setDeviceName")) {
        caller.require(QLatin1String(permissions::MANAGE_SETTINGS));
        m_settings->setValue(K("system.device_name"), params.value(K("name")).toString().trimmed().left(40));
        return info();
    }
    if (call == QLatin1String("screenshot")) {
        // Taken by SysBoard; adud and Settings use it.
        caller.require(QLatin1String(permissions::DEVELOPER));
        const int id = m_nextScreenshot++;
        QString path = params.value(K("path")).toString();
        if (path.isEmpty()) {
            QDir().mkpath(Paths::userMedia() + QStringLiteral("/Pictures/Screenshots"));
            path = Paths::userMedia() + QStringLiteral("/Pictures/Screenshots/Screenshot_%1.png")
                                            .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss")));
        }
        m_screenshots.insert(id, caller.defer());
        m_server->broadcast(K("system.screenshot"), QJsonObject{{K("id"), id}, {K("path"), path}});
        QTimer::singleShot(5000, this, [this, id] {
            if (m_screenshots.contains(id))
                m_screenshots.take(id).reject(protocol::Failed, K("the shell did not answer"));
        });
        return Deferred;
    }
    if (call == QLatin1String("screenshotDone")) {
        caller.requireSystem();
        const int id = params.value(K("id")).toInt();
        if (m_screenshots.contains(id)) {
            const PendingReply r = m_screenshots.take(id);
            if (params.value(K("ok")).toBool())
                r.resolve(params.value(K("path")));
            else
                r.reject(protocol::Failed, K("screenshot failed"));
        }
        return true;
    }
    if (call == QLatin1String("factoryReset")) {
        caller.require(QLatin1String(permissions::POWER));
        caller.require(QLatin1String(permissions::MANAGE_SETTINGS));
        if (Paths::isDevelopmentRoot())
            throw RpcError{protocol::Failed, K("Erasing all data is not available in development trees")};
        QFile marker(Paths::resolve(QStringLiteral("/data/.astra-wipe")));
        if (!marker.open(QIODevice::WriteOnly))
            throw RpcError{protocol::Failed, marker.errorString()};
        marker.close();
        qCWarning(lcSystem) << "factory reset requested by" << (caller.isSystem() ? K("system") : caller.package);
        sendToInit("reboot");
        return true;
    }
    if (call == QLatin1String("power")) {
        caller.require(QLatin1String(permissions::POWER));
        const QString action = params.value(K("action")).toString();
        // Back to the lock screen (Developer Options > Testing), screen on.
        if (action == QLatin1String("lock")) {
            m_server->broadcast(K("system.lock"), QJsonObject());
            return true;
        }
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
        qCInfo(lcSystem) << "power request" << command << "from" << (caller.isSystem() ? K("system") : caller.package);
        if (sendToInit(command))
            return true;
        // Development trees have no init: SysBoard restarts itself.
        if (action == QLatin1String("restart-sysboard") && Paths::isDevelopmentRoot()) {
            m_server->broadcast(K("system.restartShell"), true);
            return true;
        }
        throw RpcError{protocol::Failed, K("init is not reachable")};
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
