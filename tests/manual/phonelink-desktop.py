#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Manual test of Phone Linker on the desktop side, against a running astrad (scripts/dev-desktop.sh) and a running
astra-cloud server (node server.js):

    python3 tests/manual/phonelink-desktop.py out/desktop http://<host>:<port>

The desktop signs in to a fresh AstraID (astrad's account.signIn, as a "desktop" device), a phone is played over
HTTP (a second device of the same account), they are linked (phonelink.link), and what the phone sends (a
notification, contacts, a photo) must show up on the desktop: in notifications.list, contacts.list and
Pictures/Phone.
"""
import base64
import json
import os
import socket
import sys
import time
import urllib.request
import uuid

root = os.path.abspath(sys.argv[1])
server = sys.argv[2].rstrip("/")
SOCK = os.path.join(root, "dev/socket/astrad")


def rpc(method, params=None, wait=20):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(wait)
    s.connect(SOCK)
    s.sendall((json.dumps({"id": 1, "method": method, "params": params or {}}) + "\n").encode())
    f = s.makefile()
    while True:
        m = json.loads(f.readline())
        if m.get("id") == 1:
            s.close()
            return m.get("result", m.get("error"))


def http(method, path, body=None, token=None):
    req = urllib.request.Request(server + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + token} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return {"error": e.read().decode(), "status": e.code}


ok = True


def check(name, cond):
    global ok
    print(("ok   " if cond else "FAIL ") + name)
    ok = ok and cond


email = f"pl-{uuid.uuid4().hex[:8]}@example.com"
state = rpc("account.signIn", {"server": server, "email": email, "password": "long-enough-pw", "register": True, "name": "Linker"})
check("the desktop signs in as a desktop", isinstance(state, dict) and state.get("signedIn") and state.get("kind") == "desktop")
phone = http("POST", "/api/auth/login", {"email": email, "password": "long-enough-pw", "device": {"name": "Test phone", "kind": "phone", "model": "t"}})
check("a phone of the same account exists", "token" in phone)

st = rpc("phonelink.refresh")
check("the desktop sees the phone as a candidate", any(c["id"] == phone["deviceId"] for c in st.get("candidates", [])))
st = rpc("phonelink.link", {"peer": phone["deviceId"]})
check("it links, and is enabled", st.get("linked") is True and st.get("enabled") is True)

http("POST", "/api/link/send", {"kind": "notification", "payload": {"app": "Messages", "title": "Hi from the phone", "body": "Hello"}}, phone["token"])
http("POST", "/api/link/send", {"kind": "contacts", "payload": {"contacts": [{"name": "Phone Linker Test", "phone": "+390123456789"}]}}, phone["token"])
png = base64.b64encode(bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000001e221bc330000000049454e44ae426082")).decode()
http("POST", "/api/link/send", {"kind": "photo", "payload": {"name": "pl-test.png", "data": png}}, phone["token"])

found = {}
for _ in range(40):
    time.sleep(0.5)
    found["notification"] = any("Hi from the phone" in n.get("title", "") for n in rpc("notifications.list"))
    found["contacts"] = any(c.get("name") == "Phone Linker Test" for c in rpc("contacts.list"))
    found["photo"] = os.path.exists(os.path.join(root, "data/media/0/Pictures/Phone/pl-test.png"))
    if all(found.values()):
        break
check("the phone's notification shows on the desktop", found["notification"])
check("its contacts are merged", found["contacts"])
check("its photo is in Pictures/Phone", found["photo"])

st = rpc("phonelink.unlink")
check("unlinking frees the desktop", st.get("linked") is False)
rpc("account.signOut")
print("all ok" if ok else "FAILED")
sys.exit(0 if ok else 1)
