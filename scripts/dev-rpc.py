#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Calls a method of astrad in a development tree (scripts/dev-desktop.sh running) and prints the result.

    python3 scripts/dev-rpc.py out/desktop settings.set '{"key": "setup.done", "value": true}'
    python3 scripts/dev-rpc.py out/desktop activity.start '{"package": "com.astra.files"}'
"""
import json, os, socket, sys

root = os.path.abspath(sys.argv[1])
method = sys.argv[2]
params = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
s = socket.socket(socket.AF_UNIX)
s.connect(os.path.join(root, "dev/socket/astrad"))
f = s.makefile()
s.sendall((json.dumps({"id": 1, "method": method, "params": params}) + "\n").encode())
while True:
    line = f.readline()
    if not line:
        break
    m = json.loads(line)
    if m.get("id") == 1:
        print(json.dumps(m.get("result", m.get("error"))))
        break
