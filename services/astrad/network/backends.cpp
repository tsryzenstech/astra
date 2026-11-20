// SPDX-License-Identifier: Apache-2.0
// The radios are always the real daemons over D-Bus. Without a daemon or
// the hardware a backend reports available() == false, and the UI shows the
// radio as unavailable: nothing is ever made up.
#include "backends.h"
#include "bluez.h"
#include "iwd.h"
#include "modemmanager.h"
#include "nm.h"

#include <astra/form.h>

namespace astrad::network {

WifiBackend *createWifi(QObject *parent)
{
    // astraOS Desktop runs on Debian, whose network daemon is NetworkManager (iwd is the phone's).
    if (astra::Form::isDesktop() || (!serviceRegistered(QStringLiteral("net.connman.iwd")) && NMWifi::daemonPresent()))
        return new NMWifi(parent);
    return new IwdWifi(parent);
}

BluetoothBackend *createBluetooth(QObject *parent)
{
    return new BluezBluetooth(parent);
}

CellularBackend *createCellular(QObject *parent)
{
    return new MMCellular(parent);
}

} // namespace astrad::network
