// SPDX-License-Identifier: Apache-2.0
#include "hardwareservice.h"
#include "permissions.h"
#include "settingsservice.h"

#include <astra/paths.h>
#include <astra/properties.h>
#include <astra/protocol.h>

#include <QDateTime>
#include <QDir>
#include <QJsonDocument>
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
    m_brightnessTimer.setInterval(150);
    m_brightnessTimer.setSingleShot(true);
    connect(&m_brightnessTimer, &QTimer::timeout, this, [this] {
        if (m_brightnessPending) {
            writeBrightness();
            m_brightnessTimer.start();
        }
    });
    setBrightness(m_settings->value(QStringLiteral("display.brightness")).toDouble(0.7));

    // The battery's capacity (the gauge does not know it): the device says.
    m_capacityMah = qMax(1000, Properties::getInt(QStringLiteral("ro.vendor.battery.capacity_mah"), 4000));
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
// A Li-ion cell's charge from its voltage at rest, for cells charged to 4.4 V
// (typical curve). The gauge of mainline Linux maps the voltage linearly from
// 3.4 to 4.4 V instead: 100 % while charging lifts the voltage, a few % under load.
double socFromVoltage(double volts)
{
    static const double v[] = {3.40, 3.55, 3.65, 3.70, 3.73, 3.76, 3.79, 3.83, 3.87, 3.92, 3.97, 4.03, 4.10, 4.18, 4.26, 4.35};
    static const double l[] = {0, 3, 8, 15, 22, 30, 38, 46, 54, 62, 70, 78, 86, 92, 96, 100};
    const int n = int(sizeof(v) / sizeof(v[0]));
    if (volts <= v[0])
        return 0;
    for (int i = 1; i < n; ++i)
        if (volts <= v[i])
            return l[i - 1] + (volts - v[i - 1]) / (v[i] - v[i - 1]) * (l[i] - l[i - 1]);
    return 100;
}
// The cell's resistance: the voltage at rest is the one measured minus I x R.
constexpr double kResistanceOhm = 0.12;
QString stateFile()
{
    return Paths::dataSystem() + QStringLiteral("/battery.json");
}
} // namespace

// The level shown is counted, not read: the charge going in and out of the
// battery (the gauge measures the current well), on the battery's capacity,
// corrected by the voltage when the battery rests and kept across restarts.
int HardwareService::shownLevel(const QJsonObject &raw)
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const double volts = raw.value(QLatin1String("voltage")).toDouble();
    const double mA = raw.value(QLatin1String("current")).toDouble();   // + into the battery
    const bool charging = raw.value(QLatin1String("charging")).toBool();
    const bool full = raw.value(QLatin1String("status")).toString() == QLatin1String("Full");
    if (volts < 2.5) // no reading: the gauge's own figure
        return qBound(0, raw.value(QLatin1String("level")).toInt(), 100);
    const double rest = socFromVoltage(volts - mA / 1000.0 * kResistanceOhm);

    if (m_soc < 0) {
        // At start: what was counted before, unless the battery says otherwise
        // (charged or used while the phone was off).
        m_soc = rest;
        QFile f(stateFile());
        if (f.open(QIODevice::ReadOnly)) {
            const double saved = QJsonDocument::fromJson(f.readAll()).object().value(QLatin1String("soc")).toDouble(-1);
            if (saved >= 0 && qAbs(saved - rest) < 15)
                m_soc = saved;
        }
        qCInfo(lcHw) << "battery: starting at" << m_soc << "% (" << volts << "V," << mA << "mA)";
    } else if (m_lastCount > 0) {
        const double hours = double(now - m_lastCount) / 3600000.0;
        if (hours > 0 && hours < 0.1) // a long gap (suspend, a stall): not counted
            m_soc += mA * hours / m_capacityMah * 100.0;
    }
    m_lastCount = now;

    // At rest (little current for a few minutes) the voltage tells the charge:
    // the count is pulled towards it, a little at a time.
    if (qAbs(mA) < 40) {
        if (m_restSince == 0)
            m_restSince = now;
        else if (now - m_restSince > 5 * 60 * 1000)
            m_soc += (rest - m_soc) * 0.05;
    } else {
        m_restSince = 0;
    }
    // The ends.
    if (full || (charging && volts >= 4.37 && mA >= 0 && mA < 150))
        m_soc = 100;
    else if (charging)
        m_soc = qMin(m_soc, 99.0);
    if (!charging && volts < 3.45)
        m_soc = qMin(m_soc, 3.0);
    // Far from what the voltage says (a battery swapped, a bad start): trust it.
    if (!charging && qAbs(mA) < 300 && qAbs(rest - m_soc) > 30)
        m_soc = rest;
    m_soc = qBound(0.0, m_soc, 100.0);

    if (now - m_lastSave > 60 * 1000) {
        m_lastSave = now;
        QFile f(stateFile());
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
            f.write(QJsonDocument(QJsonObject{{QStringLiteral("soc"), m_soc}, {QStringLiteral("time"), double(now)}}).toJson());
    }
    return int(m_soc + 0.5);
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
            m_chargerTuned = false;
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
        if (m_notHost >= 2 && !m_chargerTuned) {
            m_chargerTuned = true;
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
    // The panel takes each change as a command sent while the picture streams:
    // a slider dragged sends dozens a second, which can leave the picture in
    // blocks. Changes are gathered and written at most every 150 ms, the last
    // one always.
    if (!m_brightnessTimer.isActive()) {
        writeBrightness();
        m_brightnessTimer.start();
    } else {
        m_brightnessPending = true;
    }
    m_settings->setValue(QStringLiteral("display.brightness"), m_brightness);
    notify(QStringLiteral("brightness"), m_brightness);
}

void HardwareService::writeBrightness()
{
    m_brightnessPending = false;
    if (m_backlight.isEmpty())
        return;
    const int max = readSys(m_backlight + QStringLiteral("/max_brightness")).toInt();
    const int level = qRound(m_brightness * max);
    if (max <= 0 || level == m_writtenBrightness)
        return;
    if (writeSys(m_backlight + QStringLiteral("/brightness"), QByteArray::number(level)))
        m_writtenBrightness = level;
    else
        qCWarning(lcHw) << "cannot write backlight";
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
