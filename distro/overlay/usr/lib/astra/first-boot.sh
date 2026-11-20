#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Once, at the first start of an installed system (before the session): what depends on the machine.
#  - an NVIDIA GPU: the proprietary driver from Debian's non-free (with KMS on: SysBoard draws through KMS), unless
#    the open "nouveau" is wanted (touch /etc/astra/no-nvidia). It needs the network; without it nouveau is used,
#    and the step is tried again at the next start.
#  - the machine id and the host name's suffix.
# NOT TESTED on real hardware.
set -eu
DONE=/var/lib/astra/first-boot-done
mkdir -p /var/lib/astra /etc/astra
[ -e "$DONE" ] && exit 0

nvidia_gpu() { lspci -nn 2>/dev/null | grep -qiE 'VGA|3D|Display' && lspci -nn | grep -iE 'VGA|3D|Display' | grep -qi 'NVIDIA'; }

if nvidia_gpu && [ ! -e /etc/astra/no-nvidia ] && ! dpkg -s nvidia-driver >/dev/null 2>&1; then
    if getent hosts deb.debian.org >/dev/null 2>&1; then
        sed -i 's/^deb \(.*\) main$/deb \1 main contrib non-free non-free-firmware/' /etc/apt/sources.list 2>/dev/null || true
        apt-get update -qq || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq linux-headers-amd64 nvidia-driver firmware-misc-nonfree \
            && printf 'options nvidia-drm modeset=1 fbdev=1\n' > /etc/modprobe.d/astra-nvidia.conf \
            && update-initramfs -u \
            && touch /var/lib/astra/needs-reboot
    else
        echo "astra-first-boot: NVIDIA GPU found, but there is no network: using nouveau, trying again next start" >&2
        exit 0
    fi
fi

# A machine of its own.
[ -s /etc/machine-id ] || systemd-machine-id-setup
touch "$DONE"
[ -e /var/lib/astra/needs-reboot ] && { rm -f /var/lib/astra/needs-reboot; systemctl reboot; }
exit 0
