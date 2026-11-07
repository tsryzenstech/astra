#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Publishes astraOS's system apps on Market, so phones update them from there.

Each app in apps/CMakeLists.txt is packed as the system image packs it (same
revision: the commits that touched its folder, see cmake/AstraApp.cmake) and
uploaded as a new version when Market does not have that one yet. Uploads are
checked by astra cloud with the system apps' design rules (?system=1, admins only).

  ASTRA_CLOUD_URL=http://... ASTRA_CLOUD_TOKEN=... python3 tools/market/publish.py [app...]

ASTRA_CLOUD_TOKEN is an admin session token of astra cloud. Without it the apps
are only packed (into build/market), to check that they would be.
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "apkgtool"))
import apkgtool  # noqa: E402

OUT = os.path.join(ROOT, "build", "market")


def system_apps():
    text = open(os.path.join(ROOT, "apps", "CMakeLists.txt"), encoding="utf-8").read()
    return re.findall(r"^\s*astra_add_app\((\w+)", text, re.M)


def revision(app_dir):
    out = subprocess.run(["git", "rev-list", "--count", "HEAD", "--", "."], cwd=app_dir,
                         capture_output=True, text=True, check=True)
    return int(out.stdout.strip() or 0)


def request(method, path, body=None, content_type="application/json"):
    url = os.environ["ASTRA_CLOUD_URL"].rstrip("/") + path
    data = body if isinstance(body, (bytes, type(None))) else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": "Bearer " + os.environ["ASTRA_CLOUD_TOKEN"],
                                          "Content-Type": content_type, "User-Agent": "astra-publish"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, {}


def publish(app, manifest, apkg_path):
    pkg = manifest["package"]
    status, body = request("POST", "/api/dev/apps", {
        "package": pkg,
        "name": manifest["name"],
        "summary": manifest.get("description", "")[:140],
        "description": manifest.get("description", ""),
        "category": "astraOS",
        "website": "https://github.com/tsryzenstech/astra",
    })
    if status not in (200, 409):
        raise RuntimeError("%s: cannot create it on Market (%d %s)" % (pkg, status, body.get("error", "")))
    notes = urllib.parse.quote("%s %s" % (manifest["name"], manifest["version"]))
    with open(apkg_path, "rb") as f:
        status, body = request("PUT", "/api/dev/apps/%s/versions?system=1&notes=%s" % (pkg, notes), f.read(),
                               "application/octet-stream")
    if status == 409:
        return "already on Market"
    if status != 200:
        findings = "".join("\n    %s:%s %s %s" % (f.get("file"), f.get("line"), f.get("code"), f.get("message"))
                           for f in body.get("findings", []))
        raise RuntimeError("%s: upload refused (%d %s)%s" % (pkg, status, body.get("error", ""), findings))
    return "published %s (%d)" % (body.get("version"), body.get("versionCode"))


def main():
    wanted = sys.argv[1:] or system_apps()
    upload = bool(os.environ.get("ASTRA_CLOUD_TOKEN")) and bool(os.environ.get("ASTRA_CLOUD_URL"))
    os.makedirs(OUT, exist_ok=True)
    failed = 0
    for app in wanted:
        app_dir = os.path.join(ROOT, "apps", app)
        out = os.path.join(OUT, app + ".apkg")
        try:
            manifest, _, _ = apkgtool.pack(app_dir, out, revision(app_dir))
            result = publish(app, manifest, out) if upload else "packed"
            print("%-10s %s %s: %s" % (app, manifest["package"], manifest["version"], result))
        except Exception as e:  # one app's problem does not stop the others
            failed += 1
            print("%-10s FAILED: %s" % (app, e), file=sys.stderr)
    if not upload:
        print("ASTRA_CLOUD_URL/ASTRA_CLOUD_TOKEN not set: nothing uploaded")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
