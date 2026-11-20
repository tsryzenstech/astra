#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Manual test of PetalDrop's sending side against a running astrad (scripts/dev-desktop.sh):

    python3 tests/manual/petaldrop-send.py out/desktop

It plays a device nearby: announces itself with a beacon on localhost, listens, then asks astrad to send it two
files (petaldrop.peers, petaldrop.send) and checks what arrives: the offer, then each file with its SHA-256.
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


ok = True


def check(name, cond):
    global ok
    print(("ok   " if cond else "FAIL ") + name)
    ok = ok and cond


listener = socket.socket()
listener.bind(("127.0.0.1", 0))
listener.listen(1)
listener.settimeout(20)
port = listener.getsockname()[1]
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
beacon = json.dumps({"petal": 1, "id": "fake1", "name": "Fake desktop", "kind": "desktop", "port": port}).encode()

# Two files in the shared storage (an app may only share what it may read).
media = os.path.join(root, "data/media/0/Download")
os.makedirs(media, exist_ok=True)
files = {"one.txt": b"first file\n", "two.bin": os.urandom(250000)}
for n, d in files.items():
    open(os.path.join(media, n), "wb").write(d)

peer = None
for _ in range(50):
    udp.sendto(beacon, ("127.0.0.1", 47742))
    time.sleep(0.2)
    peers = rpc("petaldrop.peers")
    peer = next((p for p in peers if p["id"] == "fake1"), None)
    if peer:
        break
check("a device announcing itself is listed", peer is not None and peer["name"] == "Fake desktop" and peer["kind"] == "desktop")
if not peer:
    sys.exit(1)

sent = rpc("petaldrop.send", {"peer": "fake1", "files": [os.path.join(media, n) for n in files]})
check("send answers with a transfer id", isinstance(sent, dict) and "id" in sent)
conn, _ = listener.accept()
f = conn.makefile("rb")
offer = json.loads(f.readline())
check("the offer names the files", offer["type"] == "offer" and sorted(x["name"] for x in offer["files"]) == sorted(files))
check("and who sends them", offer["from"]["kind"] in ("phone", "desktop") and offer["from"]["id"])
conn.sendall(b'{"type":"accept"}\n')
got = {}
while True:
    h = json.loads(f.readline())
    if h["type"] == "done":
        break
    data = f.read(h["size"])
    got[h["name"]] = (data, h["sha256"])
check("every file arrives whole", all(got[n][0] == d for n, d in files.items()))
check("with its SHA-256", all(hashlib.sha256(got[n][0]).hexdigest() == got[n][1] for n in files))
conn.sendall(b'{"type":"done","count":2}\n')
time.sleep(0.5)
state = rpc("petaldrop.state")
tr = next((t for t in state["transfers"] if t["id"] == sent["id"]), None)
check("the transfer ends as done", tr is not None and tr["state"] == "done")

print("all ok" if ok else "FAILED")
sys.exit(0 if ok else 1)
