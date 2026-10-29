// SPDX-License-Identifier: Apache-2.0
#include "hardwareservice.h"
#include "permissions.h"
#include "settingsservice.h"

#include <astra/paths.h>
#include <astra/properties.h>
#include <astra/protocol.h>

#include <QDir>
#include <QFile>
#include <QLoggingCategory>

#include <fcntl.h>
#include <unistd.h>

Q_LOGGING_CATEGORY(lcHw, "astrad.hardware")

namespace astrad {

using namespace astra;

namespace {
QByteArray readSys(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll().trimmed() : QByteArray();
}

bool writeSys(const QString &path, const QByteArray &value)
{
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly))
        return false;
    return f.write(value) == value.size();
}

// First entry of a sysfs class whose name contains one of the hints.
QString findClassEntry(const QString &cls, const QStringList &hints)
{
    const QDir dir(Paths::resolve(QStringLiteral("/sys/class/") + cls));
    const QStringList entries = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System);
    for (const QString &e : entries)
        for (const QString &hint : hints)
            if (hint.isEmpty() || e.contains(hint, Qt::CaseInsensitive))
                return dir.filePath(e);
    return {};
}
} // namespace

HardwareService::HardwareService(Server *server, SettingsService *settings, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_settings(settings)
{
    m_backlight = Properties::get(QStringLiteral("ro.vendor.backlight"));
    if (m_backlight.isEmpty())
        m_backlight = findClassEntry(QStringLiteral("backlight"), {QString()});
    m_torch = Properties::get(QStringLiteral("ro.vendor.torch"));
    if (m_torch.isEmpty())
        m_torch = findClassEntry(QStringLiteral("leds"), {QStringLiteral("torch"), QStringLiteral("flash")});

    const QDir ps(Paths::resolve(QStringLiteral("/sys/class/power_supply")));
    for (const QString &e : ps.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System)) {
        // Skip batteries of peripherals (e.g. a stylus or a HID device).
        if (readSys(ps.filePath(e) + QStringLiteral("/type")) == "Battery" &&
            readSys(ps.filePath(e) + QStringLiteral("/scope")) != "Device" && m_batteryDir.isEmpty())
            m_batteryDir = ps.filePath(e);
    }
    qCInfo(lcHw) << "backlight:" << m_backlight << "torch:" << m_torch << "battery:" << m_batteryDir;

    // Restore persisted state.
    setBrightness(m_settings->value(QStringLiteral("display.brightness")).toDouble(0.7));

    m_lastBattery = battery();
    m_batteryTimer.setInterval(10000);
    connect(&m_batteryTimer, &QTimer::timeout, this, &HardwareService::pollBattery);
    m_batteryTimer.start();
}

QJsonObject HardwareService::battery() const
{
    if (m_batteryDir.isEmpty()) {
        // No battery (e.g. a desktop development tree): say so, invent nothing.
        return {{QStringLiteral("present"), false}};
    }
    auto num = [this](const char *file) { return readSys(m_batteryDir + QLatin1Char('/') + QLatin1String(file)).toLongLong(); };
    const QByteArray status = readSys(m_batteryDir + QStringLiteral("/status"));
    QJsonObject b{
        {QStringLiteral("level"), int(num("capacity"))},
        {QStringLiteral("charging"), status == "Charging" || status == "Full"},
        {QStringLiteral("present"), true},
        {QStringLiteral("status"), QString::fromLatin1(status)},
        {QStringLiteral("health"), QString::fromLatin1(readSys(m_batteryDir + QStringLiteral("/health")))},
        {QStringLiteral("technology"), QString::fromLatin1(readSys(m_batteryDir + QStringLiteral("/technology")))},
        {QStringLiteral("temperature"), double(num("temp")) / 10.0},          // °C
        {QStringLiteral("voltage"), double(num("voltage_now")) / 1e6},        // V
        {QStringLiteral("current"), double(num("current_now")) / 1e3},        // mA
    };
    const qint64 full = num("charge_full"), design = num("charge_full_design");
    if (full > 0 && design > 0)
        b.insert(QStringLiteral("capacityPercent"), int(100 * full / design));
    if (design > 0)
        b.insert(QStringLiteral("designCapacity"), double(design) / 1e3); // mAh
    // Some fuel gauges expose capacity only through the level class.
    if (b.value(QStringLiteral("level")).toInt() == 0 && readSys(m_batteryDir + QStringLiteral("/capacity")).isEmpty()) {
        const QByteArray lvl = readSys(m_batteryDir + QStringLiteral("/capacity_level"));
        b.insert(QStringLiteral("level"), lvl == "Full" ? 100 : lvl == "High" ? 80 : lvl == "Normal" ? 50 : lvl == "Low" ? 15 : 5);
    }
    return b;
}

void HardwareService::pollBattery()
{
    const QJsonObject b = battery();
    if (b != m_lastBattery) {
        m_lastBattery = b;
        m_server->broadcast(QStringLiteral("hardware.battery"), b);
        Q_EMIT batteryChanged(b.value(QLatin1String("level")).toInt(), b.value(QLatin1String("charging")).toBool());
    }
}

QJsonObject HardwareService::state() const
{
    return {
        {QStringLiteral("battery"), m_lastBattery},
        {QStringLiteral("brightness"), m_brightness},
        {QStringLiteral("torch"), m_torchOn},
        {QStringLiteral("torchAvailable"), !m_torch.isEmpty()},
    };
}

void HardwareService::notify(const QString &key, const QJsonValue &value)
{
    m_server->broadcast(QStringLiteral("hardware.changed"), QJsonObject{{QStringLiteral("key"), key}, {QStringLiteral("value"), value}});
}

void HardwareService::setBrightness(double value)
{
    m_brightness = qBound(0.02, value, 1.0);
    if (!m_backlight.isEmpty()) {
        const int max = readSys(m_backlight + QStringLiteral("/max_brightness")).toInt();
        if (max > 0 && !writeSys(m_backlight + QStringLiteral("/brightness"), QByteArray::number(qRound(m_brightness * max))))
            qCWarning(lcHw) << "cannot write backlight";
    }
    m_settings->setValue(QStringLiteral("display.brightness"), m_brightness);
    notify(QStringLiteral("brightness"), m_brightness);
}

void HardwareService::setTorch(bool on)
{
    if (!m_torch.isEmpty()) {
        const QByteArray max = readSys(m_torch + QStringLiteral("/max_brightness"));
        if (!writeSys(m_torch + QStringLiteral("/brightness"), on ? (max.isEmpty() ? QByteArray("1") : max) : QByteArray("0")))
            qCWarning(lcHw) << "cannot write torch";
    }
    m_torchOn = on;
    notify(QStringLiteral("torch"), on);
}

QJsonValue HardwareService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    if (call == QLatin1String("state"))
        return state();
    if (call == QLatin1String("battery"))
        return m_lastBattery;

    caller.require(QLatin1String(permissions::HARDWARE));
    if (call == QLatin1String("setBrightness")) {
        setBrightness(params.value(QLatin1String("value")).toDouble(m_brightness));
        return m_brightness;
    }
    if (call == QLatin1String("setTorch")) {
        setTorch(params.value(QLatin1String("on")).toBool());
        return m_torchOn;
    }
    if (call == QLatin1String("setScreen")) {
        // FB_BLANK_UNBLANK (0) / FB_BLANK_POWERDOWN (4)
        const bool on = params.value(QLatin1String("on")).toBool(true);
        if (!m_backlight.isEmpty() && !writeSys(m_backlight + QStringLiteral("/bl_power"), on ? "0" : "4"))
            qCWarning(lcHw) << "cannot change panel power";
        notify(QStringLiteral("screen"), on);
        return on;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
