// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

class QProcess;

namespace astrad {

class LockSettingsService;
class SettingsService;

// Developer options and the ADU debugging daemon (adud).
//
// Developer options are unlocked from Settings > About > Architecture (7 taps)
// and need the lock screen PIN. USB debugging starts adud, which exposes a
// shell, file transfer and app installation to the "adu" tool on a computer,
// after the user authorizes that computer on the device.
//
//   developer.state
//   developer.setEnabled {on, pin}     (turning on requires the PIN)
//   developer.setUsbDebugging {on}, developer.setWireless {on}
//   developer.hosts, developer.revokeAuthorizations
class DeveloperService : public Service
{
    Q_OBJECT
public:
    DeveloperService(Server *server, SettingsService *settings, LockSettingsService *lock, QObject *parent = nullptr);
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

private:
    QJsonObject state() const;
    void applyDaemon();
    static QString keysPath();

    Server *m_server;
    SettingsService *m_settings;
    LockSettingsService *m_lock;
    QProcess *m_devDaemon = nullptr; // development trees: adud is our child
};

} // namespace astrad
