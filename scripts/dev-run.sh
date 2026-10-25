#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Runs astraOS (astrad + SysBoard + apps) in a window on a Linux desktop.
#
#   scripts/dev-run.sh                       build, install to out/root and run
#   QT_DIR=/opt/Qt/6.8.3/gcc_64 scripts/dev-run.sh
#   ASTRA_HEADLESS=1 scripts/dev-run.sh      run on a virtual X display (CI, screenshots)
#
# The whole filesystem is relocated under $ASTRA_ROOT (default out/root), so
# /system, /data, /dev/socket... are plain directories there. F12 acts as the
# power key. While running, scripts/dev-ctl.sh drives the UI (tap, swipe,
# screenshot).
set -euo pipefail

SRC=$(cd "$(dirname "$0")/.." && pwd)
BUILD=${BUILD:-$SRC/build/dev}
export ASTRA_ROOT=${ASTRA_ROOT:-$SRC/out/root}
QT_DIR=${QT_DIR:-}

cmake -S "$SRC" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Debug ${QT_DIR:+-DCMAKE_PREFIX_PATH=$QT_DIR} >/dev/null
cmake --build "$BUILD"
cmake --install "$BUILD" --prefix "$ASTRA_ROOT" >/dev/null
mkdir -p "$ASTRA_ROOT"/{data,dev/socket,run/astra/display,vendor,product}

if [ -n "$QT_DIR" ]; then
    export LD_LIBRARY_PATH="$QT_DIR/lib:${LD_LIBRARY_PATH:-}"
    export QT_PLUGIN_PATH="$QT_DIR/plugins"
fi
export ASTRA_WAYLAND_SOCKET=astra-0
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-$ASTRA_ROOT/run/astra/display}

pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null || true; }
trap cleanup EXIT

if [ "${ASTRA_HEADLESS:-0}" = 1 ]; then
    Xvfb :87 -screen 0 1280x1024x24 -nolisten tcp &
    pids+=($!)
    export DISPLAY=:87 QT_QPA_PLATFORM=xcb
    unset WAYLAND_DISPLAY
    sleep 1
fi

"$ASTRA_ROOT/system/bin/astrad" &
pids+=($!)
sleep 0.5
"$ASTRA_ROOT/system/bin/sysboard"
