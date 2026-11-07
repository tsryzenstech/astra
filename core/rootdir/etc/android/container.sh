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
mkdir -p /data/var/lib/waydroid /run/waydroid
exec "$bin" -w container start
