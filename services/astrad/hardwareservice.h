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
    void setBrightness(double value);
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
    bool m_torchOn = false;
};

} // namespace astrad
