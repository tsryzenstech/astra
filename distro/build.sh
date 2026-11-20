#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Builds astraOS Desktop (docs/DESKTOP.md): a Debian root file system with the astra tree on top, as
#
#   sudo distro/build.sh iso          out/distro/astraOS-<version>-desktop.iso   a live ISO (BIOS and UEFI) that starts the
#                                     recovery environment: Install astraOS, Disk Utility, a browser, a terminal
#   sudo distro/build.sh ota          out/distro/astraOS-<version>-desktop-system.tar.gz and ota.json (the update, as on the phone)
#   sudo distro/build.sh rootfs       only the root file system, out/distro/rootfs
#
# Run it as root on Debian or Ubuntu (or WSL2: debootstrap, squashfs-tools, xorriso, grub-pc-bin, grub-efi-amd64-bin, mtools).
#   SUITE=trixie ARCH=amd64          ASTRA_BUILD=<dir>  use an astra tree already built with -DASTRA_FORM=desktop
#   QT_DIR=/opt/astra-sdk/qt/6.8.3/gcc_64              the Qt astra was built with (copied into /system/lib)
#   MIRROR=http://deb.debian.org/debian
# The build host's glibc must not be newer than the suite's (Ubuntu 24.04 is fine for trixie).
set -euo pipefail

SRC=$(cd "$(dirname "$0")/.." && pwd)
WHAT=${1:-iso}
SUITE=${SUITE:-trixie}
ARCH=${ARCH:-amd64}
MIRROR=${MIRROR:-http://deb.debian.org/debian}
OUT=${OUT:-$SRC/out/distro}
QT_DIR=${QT_DIR:-/opt/astra-sdk/qt/6.8.3/gcc_64}
BUILD=${ASTRA_BUILD:-$SRC/build/distro}
ROOTFS=$OUT/rootfs
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
mkdir -p "$OUT"

VERSION=$(python3 -c "import json; v = json.load(open('$SRC/version.json')); print('%d.%d.%d' % (v['major'], v['minor'], v.get('patch', 0)))")
CHANNEL=$(python3 -c "import json; print(json.load(open('$SRC/version.json')).get('channel', 'stable'))")

# ---- 1. astra, built for the desktop --------------------------------------------------------------------------
if [ -z "${ASTRA_BUILD:-}" ]; then
    cmake -S "$SRC" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release -DASTRA_FORM=desktop -DCMAKE_PREFIX_PATH="$QT_DIR"
    cmake --build "$BUILD"
fi

# ---- 2. the Debian root file system -----------------------------------------------------------------------------
if [ ! -f "$ROOTFS/.astra-base" ]; then
    rm -rf "$ROOTFS"
    PACKAGES=$(grep -v '^\s*#' "$SRC/distro/packages.list" | grep -v '^\s*$' | tr '\n' ',' | sed 's/,$//')
    if command -v mmdebstrap >/dev/null; then
        mmdebstrap --variant=minbase --architectures="$ARCH" --components="main contrib non-free non-free-firmware" \
                   --include="$PACKAGES" "$SUITE" "$ROOTFS" "$MIRROR"
    else
        debootstrap --variant=minbase --arch="$ARCH" --components=main,contrib,non-free,non-free-firmware \
                    --include="$PACKAGES" "$SUITE" "$ROOTFS" "$MIRROR"
    fi
    touch "$ROOTFS/.astra-base"
fi
mountpoints() { for d in dev dev/pts proc sys; do mount --bind "/$d" "$ROOTFS/$d" 2>/dev/null || true; done; }
umountpoints() { for d in dev/pts dev proc sys; do umount "$ROOTFS/$d" 2>/dev/null || true; done; }
trap umountpoints EXIT

# ---- 3. astra on top of it -----------------------------------------------------------------------------------------
# /system and /Applications come from cmake --install; /data is the state.
rm -rf "$ROOTFS/system" "$ROOTFS/Applications"
DESTDIR="$ROOTFS" cmake --install "$BUILD" --prefix /
install -d "$ROOTFS"/{data,home}
ln -sfn home "$ROOTFS/Users"
# Qt, the one astra was built with: only the libraries the astra programs and the plugins need, next to astra's own.
"$SRC/distro/collect-qt.sh" "$ROOTFS" "$QT_DIR"
cp -a "$SRC/distro/overlay/." "$ROOTFS/"
chmod +x "$ROOTFS"/usr/lib/astra/*.sh "$ROOTFS"/usr/lib/astra/installer/*.sh
find "$ROOTFS/system" -type f \( -name '*.so*' -o -perm -u+x \) -exec sh -c 'file -b "$1" | grep -q "^ELF" && strip --strip-unneeded "$1" 2>/dev/null' _ {} \; || true

mountpoints
chroot "$ROOTFS" systemctl enable astra-live.service astra-bootanim.service astra-session.service astra-first-boot.service \
                                 astra-ota-apply.service NetworkManager.service >/dev/null 2>&1 || true
chroot "$ROOTFS" systemctl set-default graphical.target
chroot "$ROOTFS" systemctl disable getty@tty1.service >/dev/null 2>&1 || true
echo astra-desktop > "$ROOTFS/etc/hostname"
printf '127.0.0.1 localhost\n127.0.1.1 astra-desktop\n' > "$ROOTFS/etc/hosts"
# The device properties the update service reads.
{
    echo "ro.product.device=desktop"
    echo "ro.product.model=astraOS Desktop"
    echo "ro.product.manufacturer=astra"
    echo "ro.astra.form=desktop"
    echo "ro.astra.ota.repo=${OTA_REPOSITORY:-tsryzenstech/astra_desktop}"
    echo "ro.astra.ota.channel=$([ "$CHANNEL" = stable ] && echo stable || echo prerelease)"
    echo "ro.astra.ota.time=$(date +%s)"
    echo "ro.astra.ota.tag=${OTA_TAG:-$VERSION}"
} >> "$ROOTFS/system/build.prop"
# The 'astra-live' account of the recovery environment, and the groups astra's permissions use as numbers.
chroot "$ROOTFS" sh -c 'getent group media_rw >/dev/null || groupadd -g 1023 media_rw; getent group graphics >/dev/null || groupadd -g 1003 graphics'

check_libs() {
    local missing
    missing=$(chroot "$ROOTFS" sh -c 'for b in /system/bin/sysboard /system/bin/astrad /system/bin/astra-app; do LD_LIBRARY_PATH=/system/lib ldd $b | grep "not found"; done' || true)
    if [ -n "$missing" ]; then echo "missing libraries in the image:"; echo "$missing"; exit 1; fi
}
check_libs

if [ "$WHAT" = rootfs ]; then umountpoints; echo "root file system: $ROOTFS"; exit 0; fi

# ---- the update (OTA) --------------------------------------------------------------------------------------------------
if [ "$WHAT" = ota ]; then
    umountpoints
    TAG=${OTA_TAG:-$VERSION}
    NAME=astraOS-$TAG-desktop-system.tar.gz
    tar -C "$ROOTFS" -cf "$OUT/system.tar" system Applications
    gzip -c "$OUT/system.tar" > "$OUT/$NAME"
    python3 - "$OUT" "$NAME" "$TAG" "$VERSION" "$CHANNEL" "$SRC" <<'PY'
import hashlib, json, os, subprocess, sys, time
out, name, tag, version, channel, src = sys.argv[1:]
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""): h.update(chunk)
    return h.hexdigest()
codename = json.load(open(os.path.join(src, "version.json"))).get("codename", "")
commit = subprocess.run(["git", "-C", src, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
packed, raw = os.path.join(out, name), os.path.join(out, "system.tar")
json.dump({"format": 1, "device": "desktop", "tag": tag, "version": version, "codename": codename,
           "channel": "prerelease" if "-rev" in tag else channel if channel != "stable" else "stable", "time": int(time.time()),
           "notes": [], "astra": commit,
           "files": {"system": {"name": name, "size": os.path.getsize(packed), "sha256": sha(packed),
                                "raw_size": os.path.getsize(raw), "raw_sha256": sha(raw)}}},
          open(os.path.join(out, "ota.json"), "w"), indent=2)
PY
    rm -f "$OUT/system.tar"
    echo "update: $OUT/$NAME and $OUT/ota.json"
    exit 0
fi

# ---- 4. the live ISO ---------------------------------------------------------------------------------------------------------
# The kernel and the live-boot initramfs are made in the root; the squashfs is what boots (and what the installer copies).
chroot "$ROOTFS" sh -c 'update-initramfs -u -k all' >/dev/null 2>&1 || chroot "$ROOTFS" update-initramfs -c -k all
umountpoints
ISO=$OUT/iso
rm -rf "$ISO"
mkdir -p "$ISO/live" "$ISO/boot/grub"
cp "$ROOTFS"/boot/vmlinuz-* "$ISO/live/vmlinuz"
cp "$ROOTFS"/boot/initrd.img-* "$ISO/live/initrd.img"
mksquashfs "$ROOTFS" "$ISO/live/filesystem.squashfs" -comp zstd -Xcompression-level 12 -noappend \
           -e proc sys dev run tmp boot/initrd.img-\* -quiet
cat > "$ISO/boot/grub/grub.cfg" <<'GRUB'
set timeout=3
set default=0
menuentry "astraOS Desktop: install or recover" {
    linux /live/vmlinuz boot=live components astra.live=1 quiet splash
    initrd /live/initrd.img
}
menuentry "astraOS Desktop: install or recover (safe graphics)" {
    linux /live/vmlinuz boot=live components astra.live=1 nomodeset
    initrd /live/initrd.img
}
GRUB
grub-mkrescue -o "$OUT/astraOS-$VERSION-desktop.iso" "$ISO" -- -volid ASTRAOS >/dev/null 2>&1
echo "ISO: $OUT/astraOS-$VERSION-desktop.iso ($(du -h "$OUT/astraOS-$VERSION-desktop.iso" | cut -f1))"
