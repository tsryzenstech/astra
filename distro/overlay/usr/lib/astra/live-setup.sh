#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# The live (recovery) environment: a marker SysBoard looks for, the user that runs the browser and the terminal,
# and settings so that nothing asks anything (no setup, no lock).
set -eu
mkdir -p /run/astra
: > /run/astra/live
getent group media_rw >/dev/null || groupadd -g 1023 media_rw
getent passwd astra-live >/dev/null || useradd -m -s /bin/bash -G video,render,input,audio,netdev astra-live
passwd -l astra-live >/dev/null 2>&1 || true
mkdir -p /data/system
cat > /data/system/settings.json <<'JSON'
{
    "setup.done": true,
    "desktop.lock_timeout": 0,
    "display.screen_timeout": 0,
    "theme.mode": "dark"
}
JSON

# Unattended installation (tests, deployments): astra.autoinstall=/dev/vda on the kernel command line installs on that disk
# once the system is up, then powers off. astra.autoinstall.args=--root,/dev/vda4,--esp,/dev/vda2,--dual (commas for spaces) gives
# install.sh its own arguments instead (the dual boot test). The log is in /var/log/astra-autoinstall.log (and on the serial console).
ARGS=""
for arg in $(cat /proc/cmdline); do
    case "$arg" in
        astra.autoinstall.args=*) ARGS=$(echo "${arg#astra.autoinstall.args=}" | tr , ' ') ;;
    esac
done
for arg in $(cat /proc/cmdline); do
    case "$arg" in
        astra.autoinstall=*)
            disk=${arg#astra.autoinstall=}
            [ -n "$ARGS" ] || ARGS="--disk $disk"
            systemd-run --no-block --unit=astra-autoinstall /bin/sh -c "sleep 25; /usr/lib/astra/installer/install.sh $ARGS 2>&1 | tee /var/log/astra-autoinstall.log > /dev/ttyS0; echo AUTOINSTALL-FINISHED > /dev/ttyS0; systemctl poweroff"
            ;;
    esac
done
