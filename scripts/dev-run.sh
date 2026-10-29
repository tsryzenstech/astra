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
if [ -z "$QT_DIR" ]; then
    for cand in /opt/astra-sdk/qt/6.8.3/gcc_64 /opt/Qt/6.8.3/gcc_64 "$HOME/Qt/6.8.3/gcc_64"; do
        if [ -d "$cand" ]; then
            QT_DIR="$cand"
            break
        fi
    done
fi

cmake -S "$SRC" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Debug ${QT_DIR:+-DCMAKE_PREFIX_PATH=$QT_DIR} >/dev/null
cmake --build "$BUILD"
cmake --install "$BUILD" --prefix "$ASTRA_ROOT" >/dev/null
mkdir -p "$ASTRA_ROOT"/{data,dev,vendor,product}
# Sockets on DrvFs (WSL /mnt/c/...) fail with ENOTSUP (95). Relocate dev/socket and run to tmpfs if needed.
if ! python3 -c "import socket; s = socket.socket(socket.AF_UNIX); s.bind('$ASTRA_ROOT/dev/.probe'); s.close()" 2>/dev/null; then
    rm -f "$ASTRA_ROOT/dev/.probe" 2>/dev/null || true
    DEV_TMP="/tmp/astra-${USER:-dev}"
    mkdir -p "$DEV_TMP/socket" "$DEV_TMP/run/astra/display"
    rm -rf "$ASTRA_ROOT/dev/socket" "$ASTRA_ROOT/run"
    ln -sfn "$DEV_TMP/socket" "$ASTRA_ROOT/dev/socket"
    ln -sfn "$DEV_TMP/run" "$ASTRA_ROOT/run"
else
    rm -f "$ASTRA_ROOT/dev/.probe"
    mkdir -p "$ASTRA_ROOT"/{dev/socket,run/astra/display}
fi

if [ -n "$QT_DIR" ]; then
    export LD_LIBRARY_PATH="$QT_DIR/lib:${LD_LIBRARY_PATH:-}"
    export QT_PLUGIN_PATH="$QT_DIR/plugins"
    export QML_IMPORT_PATH="$QT_DIR/qml:${QML_IMPORT_PATH:-}"
    export QML2_IMPORT_PATH="$QT_DIR/qml:${QML2_IMPORT_PATH:-}"
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
astrad_pid=$!
pids+=($astrad_pid)
sleep 0.5

while kill -0 "$astrad_pid" 2>/dev/null; do
    "$ASTRA_ROOT/system/bin/sysboard" || true
    sleep 0.3
    # If a detached sysboard was spawned (e.g. via Restart SysBoard), wait on it
    if pgrep -u "$UID" -x sysboard >/dev/null; then
        while pgrep -u "$UID" -x sysboard >/dev/null; do
            sleep 0.5
        done
    fi
    break
done
