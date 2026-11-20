#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Applies /data/ota/apply/system.tar (written and checked by astrad's update service). The tar holds
# system/ and Applications/. Unpacked first to /system.new and /Applications.new: if that fails nothing
# changes. Then the swap, which is a few renames; an interrupted swap is finished by the next start.
set -eu
APPLY=/data/ota/apply
STATE=$APPLY/state
log() { echo "astra-ota: $*" | tee -a /data/ota/log 2>/dev/null || echo "astra-ota: $*"; }

# A swap that was cut after the first rename: put the old tree back where it belongs, then try again.
[ -d /system.old ] && [ ! -d /system ] && mv /system.old /system
[ -d /Applications.old ] && [ ! -d /Applications ] && mv /Applications.old /Applications

rm -rf /system.new /Applications.new
mkdir /system.new /Applications.new
if ! tar -xf "$APPLY/system.tar" -C / --transform 's,^system,system.new,; s,^Applications,Applications.new,'; then
    log "unpacking failed, the system is as it was"
    rm -rf /system.new /Applications.new
    echo failed > "$STATE"
    exit 0
fi
[ -x /system.new/bin/astrad ] && [ -x /system.new/bin/sysboard ] || {
    log "the update has no astrad or SysBoard, not applying it"
    rm -rf /system.new /Applications.new
    echo failed > "$STATE"
    exit 0
}

echo applying > "$STATE"
rm -rf /system.old /Applications.old
mv /system /system.old
mv /system.new /system
if [ -d /Applications ]; then mv /Applications /Applications.old; fi
mv /Applications.new /Applications
# An installed system does not carry the recovery tools (the update's /Applications has them, it is the ISO's too).
[ -f /etc/astra/installed ] && sh /usr/lib/astra/remove-live-apps.sh / || true
rm -f "$APPLY/system.tar"
cp "$APPLY/ota.json" /system/ota.json 2>/dev/null || true
echo applied > "$STATE"
log "applied"
