#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Checks and updates astraOS translation files.

Every translatable string is written in English in QML with qsTr() (or
qsTranslate()/QT_TR_NOOP()); each component (an app, SysBoard, the
framework) keeps one i18n/<language>.json next to its sources.

  i18n.py check  [component...]     list missing and unused strings (exit 1 if any are missing)
  i18n.py update [component...]     add missing strings as "" (= English) and drop unused ones;
                                    en.json keeps the English plural forms ("%n items")

Without arguments every component in the tree is processed.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LANGUAGES = ["it"]

# qsTr("text"), qsTr("text", "disambiguation"), qsTr("%n items", "", count)
CALL = re.compile(r'\b(?:qsTr|QT_TR_NOOP)\(\s*"((?:[^"\\]|\\.)*)"(?:\s*,\s*"((?:[^"\\]|\\.)*)")?')
TRANSLATE = re.compile(r'\b(?:qsTranslate|QT_TRANSLATE_NOOP)\(\s*"[^"]*"\s*,\s*"((?:[^"\\]|\\.)*)"')


def components():
    out = {"framework": (os.path.join(ROOT, "frameworks"), os.path.join(ROOT, "frameworks", "i18n")),
           "sysboard": (os.path.join(ROOT, "sysboard"), os.path.join(ROOT, "sysboard", "i18n"))}
    apps = os.path.join(ROOT, "apps")
    for name in sorted(os.listdir(apps)):
        if os.path.exists(os.path.join(apps, name, "app.json")):
            out[name] = (os.path.join(apps, name), os.path.join(apps, name, "i18n"))
    return out


def unescape(s):
    return json.loads('"' + s + '"')


def plural(text):
    return "%n" in text


def strings(src):
    found = {}
    for base, _, files in os.walk(src):
        for f in files:
            if not f.endswith((".qml", ".js")):
                continue
            path = os.path.join(base, f)
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            for m in CALL.finditer(text):
                key = unescape(m.group(1))
                if m.group(2):
                    key += "|" + unescape(m.group(2))
                found.setdefault(key, os.path.relpath(path, ROOT))
            for m in TRANSLATE.finditer(text):
                found.setdefault(unescape(m.group(1)), os.path.relpath(path, ROOT))
    return found


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def main(argv):
    if not argv or argv[0] not in ("check", "update"):
        print(__doc__)
        return 2
    mode, wanted = argv[0], argv[1:]
    comps = components()
    missing_total = 0
    for name, (src, i18n) in comps.items():
        if wanted and name not in wanted:
            continue
        found = strings(src)
        if name == "framework":
            # The framework's own sources only (apps live elsewhere).
            found = {k: v for k, v in found.items() if not v.startswith("apps")}
        for lang in LANGUAGES:
            path = os.path.join(i18n, lang + ".json")
            table = load(path)
            missing = [k for k in found if not table.get(k)]
            unused = [k for k in table if k not in found]
            missing_total += len(missing)
            if mode == "check":
                for k in missing:
                    print(f"{name}/{lang}: missing {k!r} ({found[k]})")
                for k in unused:
                    print(f"{name}/{lang}: unused {k!r}")
            else:
                for k in missing:
                    table.setdefault(k, {"one": "", "other": ""} if plural(k) else "")
                for k in unused:
                    del table[k]
                if found or table:
                    os.makedirs(i18n, exist_ok=True)
                    with open(path, "w", encoding="utf-8", newline="\n") as fh:
                        json.dump(dict(sorted(table.items(), key=lambda kv: kv[0].lower())), fh,
                                  ensure_ascii=False, indent=4)
                        fh.write("\n")
                print(f"{name}/{lang}: {len(found)} strings, {len(missing)} untranslated, {len(unused)} removed")
        if mode == "update":
            # en.json: only the plural forms of English sources ("%n items").
            path = os.path.join(i18n, "en.json")
            table = load(path)
            plurals = {k: table.get(k, {"one": k, "other": k}) for k in found if plural(k)}
            if plurals:
                os.makedirs(i18n, exist_ok=True)
                with open(path, "w", encoding="utf-8", newline="\n") as fh:
                    json.dump(dict(sorted(plurals.items(), key=lambda kv: kv[0].lower())), fh, ensure_ascii=False, indent=4)
                    fh.write("\n")
    return 1 if mode == "check" and missing_total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
