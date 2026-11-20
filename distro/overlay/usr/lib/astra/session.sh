#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# astraOS Desktop session: astrad (root, like on the phone), then SysBoard as the system user with the
# groups of the devices it needs (what sysboard.rc says on the phone: graphics input video audio media_rw).
# When SysBoard ends the session ends and systemd starts it again (Restart=always).
set -eu
export XDG_RUNTIME_DIR=/run/astra/display
export HOME=/data/system
export QT_PLUGIN_PATH=/system/lib/qt6/plugins
export QML_IMPORT_PATH=/system/framework/qml
export QML2_IMPORT_PATH=/system/framework/qml
export LD_LIBRARY_PATH=/system/lib
export QT_QPA_PLATFORM=eglfs QT_QPA_EGLFS_INTEGRATION=eglfs_kms QT_QPA_EGLFS_KMS_ATOMIC=1 QT_QPA_EGLFS_HIDECURSOR=1

/system/bin/astrad &
ASTRAD=$!
trap 'kill "$ASTRAD" 2>/dev/null || true' EXIT TERM INT
# astrad listens once it has scanned /Applications.
i=0
while [ ! -S /dev/socket/astrad ] && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done

# Another user than root: SysBoard is the system user, with the groups of the display, input and audio.
exec setpriv --reuid=astra-system --regid=astra-system --groups=video,render,input,audio,media_rw \
     /system/bin/sysboard
