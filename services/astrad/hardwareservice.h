// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QTimer>

namespace astrad {

class SettingsService;

// Thin hardware abstraction over sysfs/rfkill:
//   battery    /sys/class/power_supply/<battery>/{capacity,status}
//   brightness /sys/class/backlight/<panel>/brightness   (ro.vendor.backlight)
//   torch      /sys/class/leds/<torch>/brightness         (ro.vendor.torch)
// Without the hardware a feature reports itself as absent.
class HardwareService : public Service
{
    Q_OBJECT
public:
    HardwareService(Server *server, SettingsService *settings, QObject *parent = nullptr);

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;
    QJsonObject battery() const;   // {present, level, charging, ...}

Q_SIGNALS:
    void batteryChanged(int level, bool charging);

private:
    QJsonObject state() const;
    void pollBattery();
    // The level shown: the charge counted from the current, corrected by the
    // voltage at rest (mainline's gauge maps the voltage linearly).
    int shownLevel(const QJsonObject &raw);
    // Charging from a wall charger at the rate it can give (the charger IC
    // starts at USB's 500 mA when it cannot tell what is plugged in).
    void tuneCharger();
    void setBrightness(double value);
    void writeBrightness();
    void setTorch(bool on);
    void notify(const QString &key, const QJsonValue &value);

    Server *m_server;
    SettingsService *m_settings;
    QTimer m_batteryTimer;
    QJsonObject m_lastBattery;
    QString m_backlight;
    QString m_torch;
    QString m_batteryDir;
    double m_brightness = 0.7;
    QTimer m_brightnessTimer;       // the last write: the next one waits for it
    bool m_brightnessPending = false;
    int m_writtenBrightness = -1;
    double m_soc = -1;         // the charge counted, %, -1 before the first reading
    int m_capacityMah = 4000;
    qint64 m_lastCount = 0;    // when the charge was last counted
    qint64 m_restSince = 0;    // since when the battery rests (little current)
    qint64 m_lastSave = 0;
    int m_notHost = 0;         // polls on a charger that is not a computer
    bool m_chargerTuned = false;
    bool m_torchOn = false;
};

} // namespace astrad
