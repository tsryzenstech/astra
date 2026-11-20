#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# The recovery tools (Installer, Disk Utility, the browser) are for the live system only: an installed astraOS does not list
# them (the Terminal stays). Run by the installer on the new system and by the update after it swaps /Applications.
# Usage: remove-live-apps.sh [ROOT]   (default /)
ROOT=${1:-}
for f in Installer.apkg DiskUtility.apkg Browser.legacy.json .icons/browser.svg; do
    rm -f "$ROOT/Applications/$f"
done
if [ -f "$ROOT/system/etc/priv-apps.txt" ]; then
    sed -i '/^com\.astra\.installer$/d; /^com\.astra\.diskutil$/d' "$ROOT/system/etc/priv-apps.txt"
fi
exit 0
