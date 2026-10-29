// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"
#include "settingsservice.h"

#include <QJsonArray>

namespace astrad {

// Display modes (resolution, refresh rate) of the internal panel, read from
// DRM/KMS. The chosen mode ("display.mode" setting, "1080x2400@120") is
// written to /data/system/kms.json in the eglfs_kms format; SysBoard reads
// it when it starts, so a new mode applies after restarting the shell.
//   display.modes  -> [{width, height, refresh, preferred, current}]
//   display.info   -> {connector, output, width, height, refresh, physicalWidth, physicalHeight, modes}
class DisplayService : public Service
{
    Q_OBJECT
public:
    explicit DisplayService(SettingsService *settings, QObject *parent = nullptr);
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

private:
    void probe();
    void writeKmsConfig();

    SettingsService *m_settings;

    QJsonArray m_modes;
    QJsonObject m_info;
};

} // namespace astrad
