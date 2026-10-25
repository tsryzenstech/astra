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
#include <linux/rfkill.h>
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
    for (const QString &e : ps.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System))
        if (readSys(ps.filePath(e) + QStringLiteral("/type")) == "Battery")
            m_batteryDir = ps.filePath(e);
    qCInfo(lcHw) << "backlight:" << m_backlight << "torch:" << m_torch << "battery:" << m_batteryDir;

    // Restore persisted state.
    setBrightness(m_settings->value(QStringLiteral("display.brightness")).toDouble(0.7));
    for (const char *radio : {"wifi", "bluetooth"})
        setRadio(QLatin1String(radio), m_settings->value(QStringLiteral("radio.") + QLatin1String(radio)).toBool(true));

    m_lastBattery = battery();
    m_batteryTimer.setInterval(30000);
    connect(&m_batteryTimer, &QTimer::timeout, this, &HardwareService::pollBattery);
    m_batteryTimer.start();
}

QJsonObject HardwareService::battery() const
{
    if (m_batteryDir.isEmpty())
        return {{QStringLiteral("level"), 100}, {QStringLiteral("charging"), false}, {QStringLiteral("present"), false}};
    const QByteArray status = readSys(m_batteryDir + QStringLiteral("/status"));
    return {{QStringLiteral("level"), readSys(m_batteryDir + QStringLiteral("/capacity")).toInt()},
            {QStringLiteral("charging"), status == "Charging" || status == "Full"},
            {QStringLiteral("present"), true}};
}

void HardwareService::pollBattery()
{
    const QJsonObject b = battery();
    if (b != m_lastBattery) {
        m_lastBattery = b;
        m_server->broadcast(QStringLiteral("hardware.battery"), b);
    }
}

QJsonObject HardwareService::state() const
{
    return {
        {QStringLiteral("battery"), m_lastBattery},
        {QStringLiteral("brightness"), m_brightness},
        {QStringLiteral("torch"), m_torchOn},
        {QStringLiteral("torchAvailable"), !m_torch.isEmpty() || Paths::isDevelopmentRoot()},
        {QStringLiteral("wifi"), m_settings->value(QStringLiteral("radio.wifi")).toBool()},
        {QStringLiteral("bluetooth"), m_settings->value(QStringLiteral("radio.bluetooth")).toBool()},
        {QStringLiteral("cellular"), m_settings->value(QStringLiteral("radio.cellular")).toBool()},
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

void HardwareService::setRadio(const QString &radio, bool enabled)
{
    const quint8 type = radio == QLatin1String("wifi") ? RFKILL_TYPE_WLAN
                      : radio == QLatin1String("bluetooth") ? RFKILL_TYPE_BLUETOOTH : 0;
    if (type) {
        const int fd = open(QFile::encodeName(Paths::resolve(QStringLiteral("/dev/rfkill"))).constData(), O_WRONLY | O_CLOEXEC);
        if (fd >= 0) {
            struct rfkill_event ev {};
            ev.type = type;
            ev.op = RFKILL_OP_CHANGE_ALL;
            ev.soft = enabled ? 0 : 1;
            if (write(fd, &ev, RFKILL_EVENT_SIZE_V1) < 0)
                qCWarning(lcHw) << "rfkill write failed for" << radio;
            close(fd);
        }
    }
    m_settings->setValue(QStringLiteral("radio.") + radio, enabled);
    notify(radio, enabled);
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
    if (call == QLatin1String("setRadio")) {
        const QString radio = params.value(QLatin1String("radio")).toString();
        if (radio != QLatin1String("wifi") && radio != QLatin1String("bluetooth") && radio != QLatin1String("cellular"))
            throw RpcError{protocol::InvalidParams, QStringLiteral("unknown radio %1").arg(radio)};
        setRadio(radio, params.value(QLatin1String("enabled")).toBool());
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
