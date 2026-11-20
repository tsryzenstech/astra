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
