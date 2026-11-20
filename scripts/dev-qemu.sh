#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Boots an astraOS Desktop ISO (and a disk to install on) in QEMU, headless, with a USB keyboard and mouse, and a monitor
# socket to drive it: screenshots, keys, the mouse.
#
#   scripts/dev-qemu.sh start <iso> [disk.img] [extra kernel args]     (starts it in the background)
#   scripts/dev-qemu.sh shot <file.ppm>                                a screenshot
#   scripts/dev-qemu.sh key <qemu key>                                 e.g. down, ret, ctrl-alt-f2
#   scripts/dev-qemu.sh move <dx> <dy>                                 the mouse, relative
#   scripts/dev-qemu.sh click                                          left button down and up
#   scripts/dev-qemu.sh stop
#
# The work files are in $QEMU_DIR (default /tmp/astra-qemu). The serial console is $QEMU_DIR/serial.log.
set -euo pipefail

DIR=${QEMU_DIR:-/tmp/astra-qemu}
SOCK=$DIR/monitor.sock
mkdir -p "$DIR"
mon() {
    python3 - "$SOCK" "$1" <<'PY'
import socket, sys, time
c = socket.socket(socket.AF_UNIX)
c.connect(sys.argv[1])
time.sleep(0.2)
c.sendall((sys.argv[2] + "\n").encode())
time.sleep(0.3)
c.close()
PY
}

case "${1:-}" in
start)
    ISO=$2
    DISK=${3:-}
    APPEND=${4:-}
    ARGS=()
    # "-" as the ISO: boot the disk alone (an installed system).
    CD=(-cdrom "$ISO" -boot d)
    [ "$ISO" = "-" ] && CD=(-boot c)
    [ -n "$DISK" ] && ARGS+=(-drive "file=$DISK,if=virtio,format=raw")
    # Extra kernel arguments (astra.debug, astra.autoinstall=/dev/vda, ...) need the kernel outside the ISO.
    if [ -n "$APPEND" ]; then
        xorriso -osirrox on -indev "$ISO" -extract /live/vmlinuz "$DIR/vmlinuz" -extract /live/initrd.img "$DIR/initrd.img" >/dev/null 2>&1
        ARGS+=(-kernel "$DIR/vmlinuz" -initrd "$DIR/initrd.img"
               -append "boot=live components astra.live=1 quiet loglevel=0 systemd.show_status=false vt.global_cursor_default=0 $APPEND")
    fi
    ACCEL=tcg
    [ -w /dev/kvm ] && ACCEL=kvm
    rm -f "$SOCK"
    qemu-system-x86_64 -accel "$ACCEL" -m 4096 -smp 2 -vga std \
        "${CD[@]}" "${ARGS[@]}" \
        -usb -device usb-kbd -device usb-mouse \
        -display none -serial "file:$DIR/serial.log" \
        -monitor "unix:$SOCK,server,nowait" \
        -pidfile "$DIR/qemu.pid" -daemonize
    echo "started (accel $ACCEL); monitor $SOCK"
    ;;
shot) mon "screendump $2" ;;
key) mon "sendkey $2" ;;
type)
    # Types a text (letters, digits and the usual punctuation) with sendkey, on one connection.
    python3 - "$SOCK" "$2" <<'PY'
import socket, sys, time
names = {" ": "spc", "-": "minus", ".": "dot", "/": "slash", "|": "shift-backslash", "_": "shift-minus", ",": "comma",
         "=": "equal", ":": "shift-semicolon", ";": "semicolon", ">": "shift-dot", "<": "shift-comma", "*": "shift-8",
         "$": "shift-4", "\\": "backslash", "\n": "ret"}
c = socket.socket(socket.AF_UNIX)
c.connect(sys.argv[1])
time.sleep(0.3)
for ch in sys.argv[2]:
    c.sendall(("sendkey " + names.get(ch, "shift-" + ch.lower() if ch.isupper() else ch) + "\n").encode())
    time.sleep(0.08)
time.sleep(0.3)
c.close()
PY
    ;;
move) mon "mouse_move $2 $3" ;;
click) mon "mouse_button 1"; sleep 0.15; mon "mouse_button 0" ;;
stop) [ -f "$DIR/qemu.pid" ] && kill "$(cat "$DIR/qemu.pid")" || true ;;
*) sed -n 2,16p "$0"; exit 1 ;;
esac
