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

    // Restore persisted state and unblank panel.
    if (!m_backlight.isEmpty())
        writeSys(m_backlight + QStringLiteral("/bl_power"), "0");
    setBrightness(m_settings->value(QStringLiteral("display.brightness")).toDouble(0.7));

    m_lastBattery = battery();
    m_lastBattery.insert(QStringLiteral("level"), shownLevel(m_lastBattery));
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
    QByteArray status = readSys(m_batteryDir + QStringLiteral("/status"));
    // Some fuel gauges (sweet's qcom_qg) do not know: the charger does.
    if (status.isEmpty() || status == "Unknown") {
        const QDir ps(Paths::resolve(QStringLiteral("/sys/class/power_supply")));
        for (const QString &e : ps.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System)) {
            const QString dir = ps.filePath(e);
            if (readSys(dir + QStringLiteral("/type")) != "Battery" && readSys(dir + QStringLiteral("/online")) == "1") {
                const QByteArray s = readSys(dir + QStringLiteral("/status"));
                if (s == "Charging" || s == "Full")
                    status = s;
            }
        }
    }
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

namespace {
// A Li-ion cell's charge from its voltage at rest (typical curve, 3.4-4.4 V):
// a sanity check for the gauge, not a gauge.
int levelFromVoltage(double volts)
{
    static const double v[] = {3.40, 3.60, 3.70, 3.75, 3.80, 3.87, 3.95, 4.03, 4.12, 4.20, 4.30};
    static const int l[] = {3, 12, 25, 35, 45, 55, 65, 75, 85, 93, 100};
    if (volts <= v[0])
        return l[0];
    for (int i = 1; i < 11; ++i)
        if (volts <= v[i])
            return l[i - 1] + int((volts - v[i - 1]) / (v[i] - v[i - 1]) * (l[i] - l[i - 1]));
    return 100;
}
} // namespace

int HardwareService::shownLevel(const QJsonObject &raw)
{
    int target = raw.value(QLatin1String("level")).toInt();
    const bool charging = raw.value(QLatin1String("charging")).toBool();
    const double volts = raw.value(QLatin1String("voltage")).toDouble();
    if (raw.value(QLatin1String("status")).toString() == QLatin1String("Full"))
        target = 100;
    else if (volts > 2.5) {
        // Charging lifts the voltage a little above the cell's.
        const int byVoltage = levelFromVoltage(charging ? volts - 0.12 : volts);
        if (target < 0 || target > 100 || qAbs(target - byVoltage) > 35) {
            qCInfo(lcHw) << "battery: the gauge says" << target << "at" << volts << "V: showing" << byVoltage;
            target = byVoltage;
        }
    }
    target = qBound(0, target, 100);
    if (m_shown < 0) {
        m_shown = target;
    } else if (charging) {
        // Up while charging; down only when clearly lower.
        if (target > m_shown)
            m_shown += qMax(1, (target - m_shown) / 4);
        else if (m_shown - target >= 10)
            m_shown -= 1;
    } else {
        if (target < m_shown)
            m_shown -= qMax(1, (m_shown - target) / 4);
        else if (target - m_shown >= 10)
            m_shown += 1;
    }
    return m_shown;
}

void HardwareService::tuneCharger()
{
    const QDir ps(Paths::resolve(QStringLiteral("/sys/class/power_supply")));
    for (const QString &e : ps.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System)) {
        const QString dir = ps.filePath(e);
        const QByteArray types = readSys(dir + QStringLiteral("/usb_type"));
        if (types.isEmpty() || readSys(dir + QStringLiteral("/type")) != "USB")
            continue;
        if (readSys(dir + QStringLiteral("/online")) != "1") {
            m_notHost = 0;
            return;
        }
        const int open = types.indexOf('['), close = types.indexOf(']');
        const QByteArray selected = open >= 0 && close > open ? types.mid(open + 1, close - open - 1) : QByteArray();
        // A computer enumerates the phone (the USB device is "configured");
        // a charger does not. CDP ports give 1.5 A anyway.
        bool host = false;
        const QDir udc(Paths::resolve(QStringLiteral("/sys/class/udc")));
        for (const QString &u : udc.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System))
            if (readSys(udc.filePath(u) + QStringLiteral("/state")) == "configured")
                host = true;
        m_notHost = host || selected == "CDP" ? 0 : m_notHost + 1;
        // Twenty seconds without a computer: a wall charger, which gives 1.5 A at
        // 5 V by the USB charging rules (the IC lowers it if the charger cannot).
        if (m_notHost >= 2 && readSys(dir + QStringLiteral("/current_max")).toLongLong() < 1500000) {
            if (writeSys(dir + QStringLiteral("/current_max"), "1500000"))
                qCInfo(lcHw) << "charger: not a computer (" << selected << "), charging at up to 1.5 A";
        }
        return;
    }
}

void HardwareService::pollBattery()
{
    tuneCharger();
    QJsonObject b = battery();
    b.insert(QStringLiteral("level"), shownLevel(b));
    b.insert(QStringLiteral("gaugeLevel"), battery().value(QLatin1String("level")));
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
