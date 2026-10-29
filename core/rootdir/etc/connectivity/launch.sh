#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Starts one connectivity daemon in the foreground (init supervises it).
# Distribution packages put the binaries in different places, so each is
# looked up; a daemon that is not installed sleeps forever instead of being
# restarted in a loop.
#
#   launch.sh prepare | dbus | iwd | bluetoothd | modemmanager | rmtfs | pd-mapper | tqftpserv

find_bin() {
    for p in "$@"; do
        [ -x "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

missing() {
    echo "connectivity: $1 is not installed" > /dev/kmsg
    exec sleep 2147483647
}

case "$1" in
prepare)
    # /etc is read-only: the resolver configuration lives in /run, where iwd
    # (through openresolv) and ModemManager bearers write it.
    : > /run/resolv.conf
    chmod 644 /run/resolv.conf
    [ -f /data/var/lib/dbus/machine-id ] || cat /proc/sys/kernel/random/uuid | tr -d - > /data/var/lib/dbus/machine-id
    ;;
dbus)
    bin=$(find_bin /system/bin/dbus-daemon) || missing dbus-daemon
    rm -f /run/dbus/system_bus_socket /run/dbus/dbus.pid
    exec "$bin" --system --nofork --nopidfile
    ;;
iwd)
    bin=$(find_bin /system/libexec/iwd /system/lib/iwd/iwd /system/bin/iwd) || missing iwd
    exec "$bin"
    ;;
bluetoothd)
    bin=$(find_bin /system/libexec/bluetooth/bluetoothd /system/lib/bluetooth/bluetoothd /system/bin/bluetoothd) || missing bluetoothd
    exec "$bin" -n
    ;;
modemmanager)
    bin=$(find_bin /system/bin/ModemManager /system/sbin/ModemManager) || missing ModemManager
    exec "$bin"
    ;;
rmtfs)
    # Needs the modem's shared memory and its UFS partitions (modemst1/2, fsg).
    [ -e /dev/qcom_rmtfs_mem1 ] || missing "the rmtfs memory region"
    bin=$(find_bin /system/bin/rmtfs) || missing rmtfs
    exec "$bin" -r -P -s
    ;;
pd-mapper)
    bin=$(find_bin /system/bin/pd-mapper) || missing pd-mapper
    exec "$bin"
    ;;
tqftpserv)
    bin=$(find_bin /system/bin/tqftpserv) || missing tqftpserv
    exec "$bin"
    ;;
*)
    echo "usage: $0 prepare|dbus|iwd|bluetoothd|modemmanager|rmtfs|pd-mapper|tqftpserv" >&2
    exit 2
    ;;
esac
