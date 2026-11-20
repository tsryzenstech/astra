#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Builds the astraOS Desktop image: a Debian root file system with the astra tree on top, as a UEFI bootable
# disk image (docs/DESKTOP.md, "Image"). Run it as root on a Debian or Ubuntu machine (or in a container):
#
#   sudo distro/build.sh                         -> out/distro/astraOS-<version>-desktop.img
#   SUITE=trixie ARCH=amd64 sudo distro/build.sh
#   ASTRA_BUILD=/path/to/build sudo distro/build.sh   use an astra tree already built with -DASTRA_FORM=desktop
#
# NOT TESTED: this script was written with the rest of the desktop work but has never been run to the end,
# nor the image booted. Expect to fix things in it on the first run (see distro/README.md).
set -euo pipefail

SRC=$(cd "$(dirname "$0")/.." && pwd)
SUITE=${SUITE:-trixie}                # Debian stable ("bookworm" before trixie is released as stable)
ARCH=${ARCH:-amd64}
OUT=${OUT:-$SRC/out/distro}
IMG_SIZE=${IMG_SIZE:-8G}
QT_DIR=${QT_DIR:-/opt/astra-sdk/qt/6.8.3/gcc_64}
BUILD=${ASTRA_BUILD:-$SRC/build/distro}
ROOTFS=$OUT/rootfs

[ "$(id -u)" = 0 ] || { echo "run as root (mmdebstrap needs to mount things)"; exit 1; }
for tool in mmdebstrap cmake ninja sfdisk mkfs.vfat mkfs.ext4 losetup; do
    command -v "$tool" >/dev/null || { echo "missing: $tool (apt install mmdebstrap cmake ninja-build fdisk dosfstools e2fsprogs mount)"; exit 1; }
done
mkdir -p "$OUT"

# ---- 1. astra, built for the desktop --------------------------------------------------------------
if [ -z "${ASTRA_BUILD:-}" ]; then
    cmake -S "$SRC" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release -DASTRA_FORM=desktop \
          -DASTRA_STATIC_INIT=OFF -DCMAKE_PREFIX_PATH="$QT_DIR"
    cmake --build "$BUILD"
fi
VERSION=$(python3 -c "import json; v = json.load(open('$SRC/version.json')); print('%d.%d.%d' % (v['major'], v['minor'], v.get('patch', 0)))")

# ---- 2. the Debian root file system -----------------------------------------------------------------
PACKAGES=$(grep -v '^\s*#' "$SRC/distro/packages.list" | tr '\n' ',' | sed 's/,$//; s/,,*/,/g')
rm -rf "$ROOTFS"
mmdebstrap --variant=minbase --architectures="$ARCH" --components="main contrib non-free non-free-firmware" \
           --include="$PACKAGES" "$SUITE" "$ROOTFS" http://deb.debian.org/debian

# ---- 3. astra on top of it ----------------------------------------------------------------------------
# /system and /Applications come from cmake --install; /data is the state; /Users, /sdcard are the Mac-like names.
DESTDIR="$ROOTFS" cmake --install "$BUILD" --prefix /
install -d "$ROOTFS"/{data,Applications} "$ROOTFS/home"
ln -sfn home "$ROOTFS/Users"
ln -sfn data/media/0 "$ROOTFS/sdcard"
# Qt (the SDK's build) next to astra's libraries: the astra tree is self contained.
mkdir -p "$ROOTFS/system/lib/qt6"
cp -a "$QT_DIR/lib/." "$ROOTFS/system/lib/"
cp -a "$QT_DIR/plugins" "$ROOTFS/system/lib/qt6/plugins"
cp -a "$QT_DIR/qml/." "$ROOTFS/system/framework/qml/"

cp -a "$SRC/distro/overlay/." "$ROOTFS/"
chroot "$ROOTFS" systemctl enable astra-bootanim.service astra-session.service astra-ota-apply.service NetworkManager.service
chroot "$ROOTFS" systemctl set-default graphical.target
echo "astra-desktop" > "$ROOTFS/etc/hostname"
# The device properties the update service reads: this is a "desktop" device of the amd64 board.
cat > "$ROOTFS/system/etc/build.prop.d-desktop" <<PROPS
ro.product.device=desktop
ro.product.model=astraOS Desktop
ro.product.manufacturer=astra
ro.astra.form=desktop
ro.astra.ota.repo=${OTA_REPOSITORY:-tsryzenstech/astra_desktop}
PROPS
cat "$ROOTFS/system/etc/build.prop.d-desktop" >> "$ROOTFS/system/build.prop"
rm "$ROOTFS/system/etc/build.prop.d-desktop"

# ---- 4. the disk image (GPT: ESP + root) ------------------------------------------------------------------
IMG=$OUT/astraOS-$VERSION-desktop.img
truncate -s "$IMG_SIZE" "$IMG"
sfdisk "$IMG" <<LAYOUT
label: gpt
size=512M, type=U, name=ESP
type=L, name=astraOS
LAYOUT
LOOP=$(losetup --find --show --partscan "$IMG")
trap 'umount -R "$OUT/mnt" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true' EXIT
mkfs.vfat -F32 "${LOOP}p1"
mkfs.ext4 -q -L astraOS "${LOOP}p2"
mkdir -p "$OUT/mnt"
mount "${LOOP}p2" "$OUT/mnt"
mkdir -p "$OUT/mnt/boot/efi"
mount "${LOOP}p1" "$OUT/mnt/boot/efi"
cp -a "$ROOTFS/." "$OUT/mnt/"
cat > "$OUT/mnt/etc/fstab" <<FSTAB
LABEL=astraOS  /          ext4  defaults,noatime  0 1
PARTLABEL=ESP  /boot/efi  vfat  umask=0077        0 2
FSTAB
for d in dev proc sys run; do mount --bind "/$d" "$OUT/mnt/$d"; done
chroot "$OUT/mnt" grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable --no-nvram
chroot "$OUT/mnt" update-grub
echo "built $IMG"
