#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Starts one connectivity daemon in the foreground (init supervises it).
# Distribution packages put the binaries in different places, so each is
# looked up; a daemon that is not installed sleeps forever instead of being
# restarted in a loop.
#
#   launch.sh prepare | dbus | polkitd | iwd | bluetoothd | modemmanager | rmtfs | pd-mapper | tqftpserv
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
    # Started together with the bus it needs.
    i=0
    while [ ! -S /run/dbus/system_bus_socket ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    # A controller without an address stays "unconfigured": BlueZ does not see it.
    # On phones the bootloader would hand one over; ours does not. It stays the same
    # across boots: the SoC's serial number, as a locally administered address.
    btmgmt=$(find_bin /system/bin/btmgmt)
    serial=$(cat /sys/devices/soc0/serial_number 2>/dev/null)
    if [ -n "$btmgmt" ] && [ -n "$serial" ]; then
        h=$(printf '%08x' "$serial")
        address="02:00:$(echo "$h" | cut -c1-2):$(echo "$h" | cut -c3-4):$(echo "$h" | cut -c5-6):$(echo "$h" | cut -c7-8)"
        (
            i=0
            while [ $i -lt 60 ]; do
                timeout 3 "$btmgmt" --index 0 public-addr "$address" > /dev/null 2>&1
                timeout 3 "$btmgmt" --index 0 info 2>/dev/null | grep -q "$address" && break
                sleep 1
                i=$((i + 1))
            done
        ) &
    fi
    exec "$bin" -n
    ;;
polkitd)
    # ModemManager asks PolicyKit before it does anything for a caller (to enable
    # the modem, to dial, to send a message). Without an answer it refuses all of
    # them. astrad calls as root, which PolicyKit always allows.
    bin=$(find_bin /system/lib/polkit-1/polkitd /system/libexec/polkitd /system/libexec/polkit-1/polkitd) || missing polkitd
    i=0
    while [ ! -S /run/dbus/system_bus_socket ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    mkdir -p /data/var/lib/polkit-1
    chown polkitd:polkitd /data/var/lib/polkit-1 2>/dev/null || chown 1061:1061 /data/var/lib/polkit-1 2>/dev/null || true
    exec "$bin" --no-debug
    ;;
modemmanager)
    bin=$(find_bin /system/bin/ModemManager /system/sbin/ModemManager) || missing ModemManager
    # After PolicyKit, which it looks for once, when it starts.
    i=0
    while [ -x /system/lib/polkit-1/polkitd ] && ! pidof polkitd > /dev/null 2>&1 && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
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
    # Not to the kernel log, where init points services: tried on the phone, with
    # the output there the sensor process still stalls, with it elsewhere it does
    # not. It also writes a line for each file it may not write, by the thousand.
    exec "$bin" -f /dev/fastrpc-adsp -d adsp -s -R "$root" > /dev/null 2>&1
    ;;
*)
    echo "usage: $0 prepare|dbus|polkitd|iwd|bluetoothd|modemmanager|rmtfs|pd-mapper|tqftpserv|pipewire|wireplumber|pipewire-pulse|hexagonrpcd" >&2
    exit 2
    ;;
esac
