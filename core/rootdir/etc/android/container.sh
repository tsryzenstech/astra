#!/system/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Runs Waydroid's container in the foreground (init's waydroid-container,
# started by astrad for MyDroid). The kernel parts it needs are modules on some
# phones: loaded first. A system without Waydroid sleeps instead of restarting.

bin=/system/bin/waydroid
[ -x "$bin" ] || { echo "android: waydroid is not installed" > /dev/kmsg; exec sleep 2147483647; }

for m in bridge veth nf_nat nf_conntrack xt_MASQUERADE iptable_nat ip6table_nat nft_masq overlay fuse; do
    modprobe -q "$m" 2>/dev/null
done
# Android's binder: as devices (built in) or binderfs.
if [ ! -e /dev/binder ] && grep -q binder /proc/filesystems; then
    mkdir -p /dev/binderfs
    mount -t binder binder /dev/binderfs 2>/dev/null
fi
# LXC needs the cgroup hierarchy.
if ! mountpoint -q /sys/fs/cgroup; then
    mount -t cgroup2 cgroup2 /sys/fs/cgroup 2>/dev/null
fi
mkdir -p /data/var/lib/waydroid /run/waydroid /run/waydroid/rootfs-mount
# LXC opens the container's root without following symbolic links, and /var
# and /usr are links here (to data/var and system): real paths for both the
# root and where LXC mounts it (tried on the phone: "Symbolic link loop").
# Waydroid writes this file again on "waydroid init" and upgrades.
cfg=/data/var/lib/waydroid/lxc/waydroid/config
if [ -f "$cfg" ]; then
    sed -i 's#^lxc.rootfs.path = /var/lib/waydroid#lxc.rootfs.path = /data/var/lib/waydroid#' "$cfg"
    grep -q '^lxc.rootfs.mount' "$cfg" || echo 'lxc.rootfs.mount = /run/waydroid/rootfs-mount' >> "$cfg"
fi
# The phone's own folders are Android's: pictures, videos, music, downloads and
# documents are the same files in both (a chat app picking a photo sees Gallery's).
# Android's shared storage is the folder "media/0" of its data, the phone's the same
# path in /data: each folder is mounted over its counterpart before the container starts.
astra_media=/data/media/0
droid_media=/data/var/lib/waydroid/data/media/0
if [ -d "$astra_media" ]; then
    for d in DCIM Pictures Movies Music Download Documents Recordings; do
        mkdir -p "$astra_media/$d" "$droid_media/$d" 2>/dev/null
        mountpoint -q "$droid_media/$d" || mount --bind "$astra_media/$d" "$droid_media/$d" 2>/dev/null
    done
fi
exec "$bin" -w container start
