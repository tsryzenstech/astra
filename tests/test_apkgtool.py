# SPDX-License-Identifier: Apache-2.0
"""Tests for tools/apkgtool (pack / verify / unpack / tamper detection)."""
import json
import os
import shutil
import sys
import tempfile
import unittest

SOURCE = os.environ.get("ASTRA_SOURCE_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(SOURCE, "tools", "apkgtool"))

import apkgtool  # noqa: E402


class ApkgToolTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.app = os.path.join(self.tmp, "app")
        os.makedirs(os.path.join(self.app, "qml"))
        os.makedirs(os.path.join(self.app, "widgets"))
        self.manifest = {
            "package": "org.example.hello", "name": "Hello", "version": "1.0", "versionCode": 3,
            "main": "qml/Main.qml", "icon": "icon.svg",
            "widgets": [{"id": "w", "name": "W", "qml": "widgets/W.qml", "size": "small"}],
        }
        self.write("app.json", json.dumps(self.manifest))
        self.write("qml/Main.qml", "import QtQuick\nItem {}\n" * 50)
        self.write("widgets/W.qml", "import QtQuick\nItem {}\n")
        self.write("icon.svg", "<svg/>")
        self.out = os.path.join(self.tmp, "hello.apkg")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def write(self, rel, text):
        with open(os.path.join(self.app, rel), "w") as f:
            f.write(text)

    def test_roundtrip(self):
        manifest, count, _ = apkgtool.pack(self.app, self.out)
        self.assertEqual(manifest["package"], "org.example.hello")
        self.assertEqual(count, 4)
        pkg = apkgtool.Package(self.out)
        pkg.verify()
        dest = os.path.join(self.tmp, "x")
        pkg.unpack(dest)
        with open(os.path.join(dest, "qml", "Main.qml")) as f:
            self.assertTrue(f.read().startswith("import QtQuick"))

    def test_reproducible(self):
        apkgtool.pack(self.app, self.out)
        with open(self.out, "rb") as f:
            first = f.read()
        apkgtool.pack(self.app, self.out)
        with open(self.out, "rb") as f:
            self.assertEqual(first, f.read())

    def test_tamper_detected(self):
        apkgtool.pack(self.app, self.out)
        with open(self.out, "rb") as f:
            blob = bytearray(f.read())
        blob[len(blob) // 2] ^= 0xFF
        with open(self.out, "wb") as f:
            f.write(blob)
        with self.assertRaises(apkgtool.ApkgError):
            apkgtool.Package(self.out).verify()

    def test_invalid_manifest(self):
        self.manifest["package"] = "NotValid"
        self.write("app.json", json.dumps(self.manifest))
        with self.assertRaises(apkgtool.ApkgError):
            apkgtool.pack(self.app, self.out)

    def test_missing_widget_file(self):
        os.remove(os.path.join(self.app, "widgets", "W.qml"))
        with self.assertRaises(apkgtool.ApkgError):
            apkgtool.pack(self.app, self.out)

    def test_system_apps_pack(self):
        apps = os.path.join(SOURCE, "apps")
        for name in sorted(os.listdir(apps)):
            if os.path.isfile(os.path.join(apps, name, "app.json")):
                out = os.path.join(self.tmp, name + ".apkg")
                apkgtool.pack(os.path.join(apps, name), out)
                apkgtool.Package(out).verify()


if __name__ == "__main__":
    unittest.main()
