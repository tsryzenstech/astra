#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copies the Qt that astra was built with into the image's /system: the libraries the astra programs and the plugins
# need (found with ldd, so not the 1.5 GB of everything), the Qt plugins astra uses and the QML modules.
#   collect-qt.sh <rootfs> <Qt dir>
set -euo pipefail
ROOT=$1
QT=$2
LIB=$ROOT/system/lib
PLUG=$LIB/qt6/plugins
mkdir -p "$LIB" "$PLUG" "$ROOT/system/framework/qml"

# The plugins astra needs (wayland client and compositor, KMS, images, tls, multimedia, input context).
for d in platforms wayland-decoration-client wayland-graphics-integration-client wayland-graphics-integration-server wayland-shell-integration \
         imageformats iconengines tls multimedia egldeviceintegrations platforminputcontexts generic; do
    [ -d "$QT/plugins/$d" ] && { mkdir -p "$PLUG/$d"; cp -a "$QT/plugins/$d/." "$PLUG/$d/"; }
done
# Qt's QML modules (astra's own are already in /system/framework/qml).
cp -a "$QT/qml/." "$ROOT/system/framework/qml/"

# Every Qt library something needs, followed through ldd.
declare -A seen
queue=()
while IFS= read -r f; do queue+=("$f"); done < <(
    find "$ROOT/system" "$ROOT/Applications" -type f 2>/dev/null | while read -r f; do file -b "$f" | grep -q '^ELF' && echo "$f"; done)
while [ ${#queue[@]} -gt 0 ]; do
    f=${queue[0]}; queue=("${queue[@]:1}")
    while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        base=$(basename "$dep")
        [ -n "${seen[$base]:-}" ] && continue
        seen[$base]=1
        cp -L "$dep" "$LIB/$base"
        queue+=("$LIB/$base")
    done < <(LD_LIBRARY_PATH="$QT/lib:$LIB" ldd "$f" 2>/dev/null | awk -v qt="$QT/" 'index($3, qt) == 1 { print $3 }')
done
echo "collect-qt: ${#seen[@]} Qt libraries"
