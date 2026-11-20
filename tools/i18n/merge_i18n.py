#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Merges the strings of a desktop build of an app (apps-desktop/<app>/i18n) over the mobile app's (apps/<app>/i18n) it shares
its files with (astra_add_desktop_app SHARE): the desktop ones win. Writes the result to the staged copy.

    merge_i18n.py <mobile i18n dir> <desktop i18n dir> <out dir>
"""
import io
import json
import os
import sys

mobile, desktop, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
names = set()
for d in (mobile, desktop):
    if os.path.isdir(d):
        names.update(f for f in os.listdir(d) if f.endswith(".json"))
for name in sorted(names):
    merged = {}
    for d in (mobile, desktop):
        path = os.path.join(d, name)
        if os.path.isfile(path):
            merged.update(json.load(io.open(path, encoding="utf-8")))
    io.open(os.path.join(out, name), "w", encoding="utf-8", newline="\n").write(json.dumps(merged, ensure_ascii=False, indent=4) + "\n")
