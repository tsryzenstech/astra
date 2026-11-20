#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Installs astraOS Desktop on a disk from the live system (astrad's installer service runs it as root; docs/DESKTOP.md).
#
#   install.sh --disk /dev/sdX                       erase the whole disk: GPT, BIOS boot (1 MiB), EFI (512 MiB), system
#   install.sh --root /dev/sdXN [--esp /dev/sdXM]    system on an existing partition (formatted), booting from the EFI partition
#                                                    given (kept as it is: other systems boot from it too) or none (BIOS)
#   --source DIR       what to copy (default: the live system's file system, /run/live/rootfs/filesystem.squashfs)
#   --user NAME        the Linux user that owns the home directory (default: astra)
#   --hostname NAME    (default: astra-desktop)
#   --dual             another system stays on the disk: GRUB shows its menu at every start (and finds the other systems);
#                      without it the system starts silently, with no menu
#   --bootdisk DISK    with --root and no EFI partition: the disk whose boot sector gets GRUB (BIOS)
#   --no-bootloader    do not install GRUB (tests)
#
# Prints "PROGRESS <percent> <what is being done>" lines; the last one is "PROGRESS 100 done", or "ERROR <message>"
# and a non zero exit status.
set -euo pipefail

DISK="" ROOT="" ESP="" BOOTDISK="" DUAL=0 SOURCE=/run/live/rootfs/filesystem.squashfs USERNAME=astra HOST=astra-desktop BOOT=1
while [ $# -gt 0 ]; do
    case "$1" in
        --disk) DISK=$2; shift 2 ;;
        --root) ROOT=$2; shift 2 ;;
        --esp) ESP=$2; shift 2 ;;
        --source) SOURCE=$2; shift 2 ;;
        --user) USERNAME=$2; shift 2 ;;
        --hostname) HOST=$2; shift 2 ;;
        --dual) DUAL=1; shift ;;
        --bootdisk) BOOTDISK=$2; shift 2 ;;
        --no-bootloader) BOOT=0; shift ;;
        *) echo "ERROR unknown option $1"; exit 2 ;;
    esac
done
TARGET=/mnt/astra-target
progress() { echo "PROGRESS $1 $2"; }
fail() { echo "ERROR $*"; exit 1; }
cleanup() {
    for m in dev/pts dev proc sys run boot/efi; do umount "$TARGET/$m" 2>/dev/null || true; done
    umount "$TARGET" 2>/dev/null || true
}
trap cleanup EXIT

[ -n "$DISK" ] || [ -n "$ROOT" ] || fail "no disk or partition given"
[ -d "$SOURCE" ] || fail "no system to copy ($SOURCE)"
for t in sfdisk mkfs.ext4 rsync; do command -v "$t" >/dev/null || fail "missing tool: $t"; done
partname() { case "$1" in *[0-9]) echo "${1}p$2" ;; *) echo "${1}$2" ;; esac; }
wait_for() { for _ in $(seq 1 50); do [ -b "$1" ] && return 0; sleep 0.2; done; fail "$1 did not appear"; }

# ---- 1. the disk ------------------------------------------------------------------------------------------
if [ -n "$DISK" ]; then
    [ -b "$DISK" ] || fail "$DISK is not a disk"
    progress 2 "Erasing $DISK"
    for p in $(lsblk -nrpo NAME "$DISK" | tail -n +2); do umount "$p" 2>/dev/null || true; done
    wipefs -a "$DISK" >/dev/null
    sfdisk -q "$DISK" <<LAYOUT
label: gpt
size=1M, type=21686148-6449-6E6F-744E-656564454649, name=bios
size=512M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name=EFI
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=astraOS
LAYOUT
    udevadm settle 2>/dev/null || true
    blockdev --rereadpt "$DISK" 2>/dev/null || true
    ESP=$(partname "$DISK" 2)
    ROOT=$(partname "$DISK" 3)
    wait_for "$ROOT"; wait_for "$ESP"
    progress 6 "Formatting"
    mkfs.vfat -F32 -n EFI "$ESP" >/dev/null
fi
[ -b "$ROOT" ] || fail "$ROOT is not a partition"
mkfs.ext4 -q -F -L astraOS "$ROOT"
progress 10 "Mounting"
mkdir -p "$TARGET"
mount "$ROOT" "$TARGET"
if [ -n "$ESP" ]; then
    mkdir -p "$TARGET/boot/efi"
    mount "$ESP" "$TARGET/boot/efi"
fi

# ---- 2. the system -----------------------------------------------------------------------------------------
progress 12 "Copying the system"
last=12
rsync -aHAXx --info=progress2 --no-inc-recursive \
      --exclude='/proc/*' --exclude='/sys/*' --exclude='/dev/*' --exclude='/run/*' --exclude='/tmp/*' \
      --exclude='/mnt/*' --exclude='/boot/efi/*' --exclude='/etc/fstab' --exclude='/etc/astra/live' \
      "$SOURCE"/ "$TARGET"/ 2>&1 | tr '\r' '\n' | while read -r line; do
    pct=$(echo "$line" | grep -oE '[0-9]+%' | head -1 | tr -d '%' || true)
    if [ -n "${pct:-}" ]; then
        p=$((12 + pct * 72 / 100))
        [ "$p" -gt "$last" ] && { last=$p; progress "$p" "Copying the system"; }
    fi
done
[ "${PIPESTATUS[0]}" = 0 ] || fail "copying the system failed"
mkdir -p "$TARGET"/{proc,sys,dev,run,tmp,mnt}
chmod 1777 "$TARGET/tmp"

# ---- 3. this machine ---------------------------------------------------------------------------------------
progress 86 "Setting up"
uuid=$(blkid -s UUID -o value "$ROOT")
{
    echo "UUID=$uuid  /  ext4  defaults,noatime  0 1"
    [ -n "$ESP" ] && echo "UUID=$(blkid -s UUID -o value "$ESP")  /boot/efi  vfat  umask=0077  0 2"
} > "$TARGET/etc/fstab"
echo "$HOST" > "$TARGET/etc/hostname"
sed -i "s/^127.0.1.1.*/127.0.1.1 $HOST/" "$TARGET/etc/hosts" 2>/dev/null || echo "127.0.1.1 $HOST" >> "$TARGET/etc/hosts"
rm -f "$TARGET/etc/machine-id" "$TARGET/var/lib/dbus/machine-id"
rm -rf "$TARGET/var/lib/astra/first-boot-done" "$TARGET/etc/astra/live"
mkdir -p "$TARGET/etc/astra"
date -u +%s > "$TARGET/etc/astra/installed"
# The user that owns the home directory (the shell has one user: the first in /home); no password: the session
# is SysBoard's, and the lock password is set in the setup of the first start.
chroot "$TARGET" getent passwd "$USERNAME" >/dev/null 2>&1 || \
    chroot "$TARGET" useradd -m -s /bin/bash -G video,render,input,audio,sudo,netdev "$USERNAME" 2>/dev/null || \
    chroot "$TARGET" useradd -m -s /bin/bash "$USERNAME" || fail "cannot create the user"
chroot "$TARGET" passwd -l "$USERNAME" >/dev/null 2>&1 || true
# The Linux programs listed as apps (browser, terminal) run as that user, not as the live user.
sed -i "s/\"astra-live\"/\"$USERNAME\"/" "$TARGET"/Applications/*.legacy.json 2>/dev/null || true
# A system that starts fresh: the setup wizard and the first-boot step run again.
rm -rf "$TARGET/data/system" "$TARGET/data/app" "$TARGET/data/data" "$TARGET/data/media" "$TARGET/data/ota"

# ---- 4. the bootloader --------------------------------------------------------------------------------------
if [ "$BOOT" = 1 ]; then
    progress 90 "Installing the bootloader"
    for m in dev dev/pts proc sys run; do mount --bind "/$m" "$TARGET/$m"; done
    if [ -n "$ESP" ]; then
        chroot "$TARGET" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=astraOS --recheck >/dev/null 2>&1 \
            || fail "cannot install the EFI bootloader"
        # Removable path too: firmware that forgets its boot entries still finds it.
        chroot "$TARGET" grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable >/dev/null 2>&1 || true
    fi
    BD=${DISK:-$BOOTDISK}
    if [ -n "$BD" ] && command -v grub-install >/dev/null; then
        chroot "$TARGET" grub-install --target=i386-pc "$BD" >/dev/null 2>&1 || echo "note: no BIOS bootloader (the disk boots with UEFI only)"
    fi
    # A quiet start: no text on the screen at any time (the boot animation, then the shell), and no menu.
    mkdir -p "$TARGET/etc/default"
    touch "$TARGET/etc/default/grub"
    sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/d; /^GRUB_TIMEOUT/d; /^GRUB_TERMINAL/d; /^GRUB_DISABLE_OS_PROBER/d; /^GRUB_RECORDFAIL/d' "$TARGET/etc/default/grub"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=0 systemd.show_status=false rd.systemd.show_status=false vt.global_cursor_default=0 plymouth.enable=0"' >> "$TARGET/etc/default/grub"
    if [ "$DUAL" = 1 ]; then
        # Another system on the disk: the menu is there at every start, with the other systems in it.
        printf 'GRUB_TIMEOUT=5
GRUB_TIMEOUT_STYLE=menu
GRUB_DISABLE_OS_PROBER=false
GRUB_DISTRIBUTOR="astraOS"
' >> "$TARGET/etc/default/grub"
    else
        # The only system: no menu, no text, it starts by itself.
        printf 'GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_RECORDFAIL_TIMEOUT=0
GRUB_DISABLE_OS_PROBER=true
' >> "$TARGET/etc/default/grub"
    fi
    progress 95 "Preparing the first start"
    chroot "$TARGET" update-initramfs -u >/dev/null 2>&1 || true
    chroot "$TARGET" update-grub >/dev/null 2>&1 || fail "update-grub failed"
fi
sync
progress 100 "done"
