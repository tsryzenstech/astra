#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Before the session: the users and directories astra expects (the phone's init and rc files make them).
set -eu
getent group media_rw >/dev/null || groupadd -g 1023 media_rw
getent group astra-system >/dev/null || groupadd -r astra-system
getent passwd astra-system >/dev/null || useradd -r -g astra-system -d /data/system -s /usr/sbin/nologin astra-system
install -d -m 0755 /dev/socket /run/astra /run/astra/display
install -d -o astra-system -g astra-system -m 0770 /run/astra/display
install -d -m 0771 /data /data/system /data/app /data/data /data/media
# Shared storage (/sdcard) is the first user's home: group media_rw can read and write what apps with the
# Photos, videos and music permission may, as on the phone.
for home in /home/*; do
    [ -d "$home" ] || continue
    user=$(basename "$home")
    ln -sfn "$home" /data/media/0
    for d in Music Pictures Pictures/Screenshots Download Documents Movies Recordings DCIM; do
        install -d -o "$user" -g media_rw -m 2775 "$home/$d"
    done
    chgrp media_rw "$home" && chmod g+x "$home"
    break
done
