#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# USB networking for ADU (Astra Debugging Utility).
#
# Exposes one composite USB gadget with two network functions, so every
# computer finds a driver it already has:
#   usb0  RNDIS (Windows, Linux)   10.42.0.1/24
#   usb1  NCM   (macOS, Linux)     10.42.1.1/24
# and serves addresses to the computer with busybox udhcpd.
#
#   usb-gadget.sh start | stop

G=/sys/kernel/config/usb_gadget/astra
RUN=/run/adu

start() {
    grep -q configfs /proc/mounts || mount -t configfs none /sys/kernel/config
    mkdir -p "$G" "$RUN" || exit 1
    cd "$G" || exit 1

    echo 0x1d6b > idVendor      # Linux Foundation
    echo 0x0104 > idProduct     # Multifunction Composite Gadget
    echo 0x0100 > bcdDevice
    echo 0x0200 > bcdUSB
    echo 0xEF > bDeviceClass
    echo 0x02 > bDeviceSubClass
    echo 0x01 > bDeviceProtocol

    mkdir -p strings/0x409
    echo "astraOS" > strings/0x409/manufacturer
    echo "astraOS debugging" > strings/0x409/product
    serial=$(cat /sys/devices/soc0/serial_number 2>/dev/null)
    echo "${serial:-astra}" > strings/0x409/serialnumber

    # Microsoft OS descriptors: Windows binds RNDIS without a driver.
    echo 1 > os_desc/use
    echo 0xcd > os_desc/b_vendor_code
    echo MSFT100 > os_desc/qw_sign

    mkdir -p functions/rndis.usb0 functions/ncm.usb1
    echo RNDIS > functions/rndis.usb0/os_desc/interface.rndis/compatible_id
    echo 5162001 > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id

    mkdir -p configs/c.1/strings/0x409
    echo "ADU" > configs/c.1/strings/0x409/configuration
    echo 500 > configs/c.1/MaxPower
    [ -e configs/c.1/rndis.usb0 ] || ln -s functions/rndis.usb0 configs/c.1/
    [ -e configs/c.1/ncm.usb1 ] || ln -s functions/ncm.usb1 configs/c.1/
    [ -e os_desc/c.1 ] || ln -s configs/c.1 os_desc/

    udc=$(ls /sys/class/udc | head -n 1)
    [ -n "$udc" ] || { echo "usb-gadget: no USB device controller" >&2; exit 1; }
    echo "$udc" > UDC

    n=0
    for iface in usb0 usb1; do
        net="10.42.$n"
        for i in 1 2 3 4 5 6 7 8 9 10; do
            [ -e /sys/class/net/$iface ] && break
            sleep 0.2
        done
        ip addr flush dev $iface 2>/dev/null
        ip addr add $net.1/24 dev $iface
        ip link set $iface up
        cat > $RUN/udhcpd-$iface.conf <<EOF
start $net.2
end $net.10
interface $iface
max_leases 4
lease_file $RUN/leases-$iface
option subnet 255.255.255.0
EOF
        touch $RUN/leases-$iface
        udhcpd -f $RUN/udhcpd-$iface.conf &
        echo $! > $RUN/udhcpd-$iface.pid
        n=$((n + 1))
    done
}

stop() {
    for f in $RUN/udhcpd-*.pid; do
        [ -e "$f" ] && kill "$(cat "$f")" 2>/dev/null
        rm -f "$f"
    done
    [ -d "$G" ] || return 0
    echo "" > "$G/UDC" 2>/dev/null
    rm -f "$G/os_desc/c.1" "$G/configs/c.1/rndis.usb0" "$G/configs/c.1/ncm.usb1"
    rmdir "$G/configs/c.1/strings/0x409" "$G/configs/c.1" 2>/dev/null
    rmdir "$G/functions/rndis.usb0" "$G/functions/ncm.usb1" "$G/strings/0x409" "$G" 2>/dev/null
}

case "$1" in
    start) start ;;
    stop) stop ;;
    *) echo "usage: $0 start|stop" >&2; exit 2 ;;
esac
