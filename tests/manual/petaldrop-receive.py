#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Manual test of PetalDrop's receiving side against a running astrad (scripts/dev-desktop.sh):

    python3 tests/manual/petaldrop-receive.py out/desktop

It plays a stranger on the network: sets "petaldrop.receive" to "everyone", offers two files over TCP, answers the
system dialog the way the user would (through dialogs.answer), sends the files, and checks they arrived with the
right contents in Download/PetalDrop, that a corrupted file is refused, and that "mydevices" refuses a stranger.
"""
import hashlib
import json
import os
import socket
import sys
import time

root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "out/desktop")
SOCK = os.path.join(root, "dev/socket/astrad")


def rpc(method, params=None):
    s = socket.socket(socket.AF_UNIX)
    s.connect(SOCK)
    s.sendall((json.dumps({"id": 1, "method": method, "params": params or {}}) + "\n").encode())
    f = s.makefile()
    while True:
        m = json.loads(f.readline())
        if m.get("id") == 1:
            s.close()
            return m.get("result", m.get("error"))


def port():
    return rpc("petaldrop.state")["port"]


def readline(f):
    return json.loads(f.readline())


def offer(files, tamper=False, answer="accept"):
    c = socket.create_connection(("127.0.0.1", port()), timeout=15)
    f = c.makefile("rb")
    meta = [{"name": n, "size": len(d)} for n, d in files]
    c.sendall((json.dumps({"type": "offer", "from": {"id": "rtest", "name": "Test stranger", "kind": "phone"}, "files": meta}) + "\n").encode())
    if answer is not None:
        # The system dialog: the user presses a button.
        for _ in range(100):
            pending = rpc("dialogs.pending")
            if pending:
                d = pending[0]
                rpc("dialogs.answer", {"id": d["id"], "button": answer})
                break
            time.sleep(0.1)
        else:
            raise SystemExit("no dialog appeared")
    reply = readline(f)
    if reply["type"] != "accept":
        return reply, None, c
    for n, d in files:
        sha = hashlib.sha256(d).hexdigest()
        if tamper:
            sha = "0" * 64
        c.sendall((json.dumps({"type": "file", "name": n, "size": len(d), "sha256": sha}) + "\n").encode())
        c.sendall(d)
    c.sendall(b'{"type":"done"}\n')
    return reply, readline(f), c


ok = True


def check(name, cond):
    global ok
    print(("ok   " if cond else "FAIL ") + name)
    ok = ok and cond


dest = os.path.join(root, "data/media/0/Download/PetalDrop")
rpc("settings.set", {"key": "petaldrop.receive", "value": "everyone"})
time.sleep(0.5)
data = [("hello.txt", b"hello from a stranger\n"), ("big.bin", os.urandom(300000))]
reply, done, c = offer(data)
check("a stranger's offer is accepted when the user says yes", reply["type"] == "accept" and done and done["type"] == "done")
for n, d in data:
    p = os.path.join(dest, n)
    check(f"{n} arrived with its contents", os.path.exists(p) and open(p, "rb").read() == d)
c.close()

reply, _, c = offer([("no.txt", b"x")], answer="decline")
check("and refused when the user says no", reply["type"] == "decline")
check("nothing was written", not os.path.exists(os.path.join(dest, "no.txt")))
c.close()

reply, done, c = offer([("bad.bin", b"corrupted in transit")], tamper=True)
check("a file whose checksum does not match is refused", done is not None and done["type"] == "error")
check("and removed", not os.path.exists(os.path.join(dest, "bad.bin")))
c.close()

rpc("settings.set", {"key": "petaldrop.receive", "value": "mydevices"})
time.sleep(0.5)
c = socket.create_connection(("127.0.0.1", port()), timeout=15)
c.sendall((json.dumps({"type": "offer", "from": {"id": "rtest", "name": "Stranger"}, "files": [{"name": "a", "size": 1}]}) + "\n").encode())
check("\"mydevices\" refuses a stranger without asking", readline(c.makefile("rb"))["type"] == "decline")
c.close()

print("all ok" if ok else "FAILED")
sys.exit(0 if ok else 1)
