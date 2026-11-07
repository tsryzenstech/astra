#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Starts one connectivity daemon in the foreground (init supervises it).
# Distribution packages put the binaries in different places, so each is
# looked up; a daemon that is not installed sleeps forever instead of being
# restarted in a loop.
#
#   launch.sh prepare | dbus | iwd | bluetoothd | modemmanager | rmtfs | pd-mapper | tqftpserv
#             pipewire | wireplumber | pipewire-pulse | hexagonrpcd

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
    mkdir -p /data/var/lib/dbus /run/dbus
    chown messagebus:messagebus /run/dbus 2>/dev/null || chown 1060:1060 /run/dbus 2>/dev/null || true
    chown messagebus:messagebus /data/var/lib/dbus 2>/dev/null || chown 1060:1060 /data/var/lib/dbus 2>/dev/null || true
    [ -f /data/var/lib/dbus/machine-id ] || cat /proc/sys/kernel/random/uuid | tr -d - > /data/var/lib/dbus/machine-id
    ln -sfn /data/var/lib/dbus/machine-id /run/machine-id
    ;;
dbus)
    bin=$(find_bin /system/bin/dbus-daemon) || missing dbus-daemon
    mkdir -p /run/dbus
    chown messagebus:messagebus /run/dbus 2>/dev/null || chown 1060:1060 /run/dbus 2>/dev/null || true
    chmod 0755 /run/dbus
    rm -f /run/dbus/system_bus_socket /run/dbus/dbus.pid
    exec "$bin" --system --nofork --nopidfile --nosyslog
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
    # It looks the partitions up where udev's persistent rules would put them.
    mkdir -p /dev/disk
    ln -sfn /dev/block/by-name /dev/disk/by-partlabel
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
pipewire|wireplumber|pipewire-pulse)
    # All three share one directory for their sockets, which apps connect to.
    bin=$(find_bin "/system/bin/$1") || missing "$1"
    mkdir -p /run/astra/audio/pulse /data/system/audio
    chmod 0755 /run/astra/audio /run/astra/audio/pulse
    export XDG_RUNTIME_DIR=/run/astra/audio PIPEWIRE_RUNTIME_DIR=/run/astra/audio
    export PULSE_RUNTIME_PATH=/run/astra/audio/pulse HOME=/data/system/audio
    # The sockets are for apps too, each with its own user.
    umask 000
    exec "$bin"
    ;;
hexagonrpcd)
    # The ADSP's sensor process asks the system for its files. Without an answer
    # it stalls, and the ADSP's watchdog takes the whole ADSP down every 40 s.
    [ -e /dev/fastrpc-adsp ] || missing "the ADSP"
    bin=$(find_bin /system/bin/hexagonrpcd) || missing hexagonrpcd
    root=$(ls -d /vendor/share/qcom/*/*/* 2>/dev/null | head -n 1)
    [ -n "$root" ] || missing "the DSP's files"
    exec "$bin" -f /dev/fastrpc-adsp -d adsp -s -R "$root"
    ;;
*)
    echo "usage: $0 prepare|dbus|iwd|bluetoothd|modemmanager|rmtfs|pd-mapper|tqftpserv|pipewire|wireplumber|pipewire-pulse|hexagonrpcd" >&2
    exit 2
    ;;
esac
