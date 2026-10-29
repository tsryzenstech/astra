#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Copies Market from its repository into apps/market (the bundled copy).

  python3 tools/market/update.py ../astra-market
"""
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
src = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "..", "astra-market"))
dst = os.path.join(ROOT, "apps", "market")
server = json.load(open(os.path.join(src, "config.json"), encoding="utf-8"))["server"].rstrip("/")
shutil.rmtree(os.path.join(dst, "qml"), ignore_errors=True)
shutil.copytree(os.path.join(src, "app", "qml"), os.path.join(dst, "qml"))
for f in ("app.json", "icon.svg"):
    shutil.copy(os.path.join(src, "app", f), dst)
if os.path.isdir(os.path.join(src, "app", "i18n")):
    shutil.rmtree(os.path.join(dst, "i18n"), ignore_errors=True)
    shutil.copytree(os.path.join(src, "app", "i18n"), os.path.join(dst, "i18n"))
with open(os.path.join(dst, "qml", "Server.js"), "w", encoding="utf-8", newline="\n") as f:
    f.write("// Generated from astra-market's config.json. Do not edit.\n.pragma library\n")
    f.write("var url = " + json.dumps(server) + "\n")
print("apps/market updated from", src, "server", server)
