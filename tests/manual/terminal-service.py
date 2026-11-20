#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Manual test of astrad's terminal service (scripts/dev-desktop.sh running): opens a shell, runs a command, reads what
comes back, resizes, closes.   python3 tests/manual/terminal-service.py out/desktop"""
import base64, json, os, socket, sys, time

root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "out/desktop")
s = socket.socket(socket.AF_UNIX)
s.connect(os.path.join(root, "dev/socket/astrad"))
f = s.makefile()
n = 0


def call(method, params=None):
    global n
    n += 1
    s.sendall((json.dumps({"id": n, "method": method, "params": params or {}}) + "\n").encode())
    out = b""
    while True:
        m = json.loads(f.readline())
        if m.get("id") == n:
            return m.get("result", m.get("error"))
        if m.get("event") == "terminal.data":
            out += base64.b64decode(m["data"]["data"])


s.sendall((json.dumps({"id": 99, "method": "system.subscribe", "params": {"topics": ["terminal"]}}) + "\n").encode())
time.sleep(0.2)
tid = call("terminal.open", {"cols": 100, "rows": 30})["id"]
call("terminal.write", {"id": tid, "data": base64.b64encode(b"echo astra-$((6*7)); stty size; exit\n").decode()})
data = b""
s.settimeout(6)
try:
    while True:
        line = f.readline()
        if not line:
            break
        m = json.loads(line)
        if m.get("event") == "terminal.data":
            data += base64.b64decode(m["data"]["data"])
        elif m.get("event") == "terminal.exit":
            break
except socket.timeout:
    pass
text = data.decode(errors="replace")
ok = "astra-42" in text and "30 100" in text
print("ok   a shell answers (echo and stty size)" if ok else "FAIL " + repr(text[-300:]))
sys.exit(0 if ok else 1)
