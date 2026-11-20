#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Runs astraOS Desktop (docs/DESKTOP.md) like scripts/dev-run.sh runs the phone: its own build tree
# (build/desktop) and filesystem root (out/desktop), so the two do not mix.
#
#   scripts/dev-desktop.sh                      a 1280x720 window
#   ASTRA_HEADLESS=1 scripts/dev-desktop.sh     on a virtual display; drive it with
#   ASTRA_ROOT=out/desktop scripts/dev-ctl.sh screenshot /tmp/desktop.png
set -euo pipefail
SRC=$(cd "$(dirname "$0")/.." && pwd)
export ASTRA_FORM=desktop
export BUILD=${BUILD:-$SRC/build/desktop}
export ASTRA_ROOT=${ASTRA_ROOT:-$SRC/out/desktop}
export ASTRA_XDISPLAY=${ASTRA_XDISPLAY:-88}   # the phone's dev display is :87
export ASTRA_XSCREEN=${ASTRA_XSCREEN:-1920x1080x24}
export ASTRA_WINDOW_WIDTH=${ASTRA_WINDOW_WIDTH:-1280} ASTRA_WINDOW_HEIGHT=${ASTRA_WINDOW_HEIGHT:-720}
exec "$SRC/scripts/dev-run.sh" "$@"
