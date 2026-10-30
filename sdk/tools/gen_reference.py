#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Writes docs/sdk/REFERENCE.md from the sources of Astra.Controls (QML) and
Astra.Core (C++): every component and singleton with its properties,
signals and functions, and the comments written next to them.

  python3 sdk/tools/gen_reference.py
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONTROLS = os.path.join(ROOT, "frameworks", "qml", "controls")
CORE = os.path.join(ROOT, "frameworks", "qml", "core")
OUT = os.path.join(ROOT, "docs", "sdk", "REFERENCE.md")

# Components meant for the system shell only, left out of the SDK reference.
INTERNAL = {"BatteryGlyph", "CellularGlyph", "WifiGlyph", "WeatherGlyph", "PlaceholderApp", "Catalog", "PinEntry"}


def qml_component(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    doc, props, signals, funcs = [], [], [], []
    started = False
    for line in lines:
        s = line.strip()
        if not started:
            if s.startswith("//") and "SPDX" not in s:
                doc.append(s[2:].strip())
            elif re.match(r"^[A-Z][\w.]*\s*\{", s):
                started = True
            continue
        if line.startswith("    ") and not line.startswith("     "):
            m = re.match(r"(readonly\s+)?(default\s+)?property\s+(alias|[\w<>.]+)\s+(\w+)(\s*:\s*(.+?))?\s*(//\s*(.*))?$", s)
            if m and not m.group(4).startswith("_"):
                default = (m.group(6) or "").strip()
                props.append((m.group(4), m.group(3), "readonly" if m.group(1) else "", default if len(default) < 40 else "", m.group(8) or ""))
            m = re.match(r"signal\s+(\w+)\s*(\(.*?\))?\s*(//\s*(.*))?", s)
            if m:
                signals.append((m.group(1) + (m.group(2) or "()"), m.group(4) or ""))
            m = re.match(r"function\s+(\w+)\s*(\(.*?\))", s)
            if m and not m.group(1).startswith("_"):
                funcs.append(m.group(1) + m.group(2))
    return doc, props, signals, funcs


def core_singletons():
    out = []
    for name in sorted(os.listdir(CORE)):
        if not name.endswith(".h"):
            continue
        text = open(os.path.join(CORE, name), encoding="utf-8").read()
        for cls in re.finditer(r"((?://[^\n]*\n)*)class\s+(\w+)\s*:\s*public\s+(\w+)\s*\{(.*?)\n\};", text, re.S):
            body = cls.group(4)
            qml = re.search(r"QML_NAMED_ELEMENT\((\w+)\)", body)
            if not qml and "QML_ELEMENT" not in body:
                continue
            qml_name = qml.group(1) if qml else cls.group(2)
            if qml_name in ("Lock", "Developer", "Update"):
                continue
            doc = [l.strip()[2:].strip() for l in cls.group(1).strip().split("\n") if l.strip().startswith("//")]
            props, invokables = [], []
            for line in body.split("\n"):
                m = re.search(r"Q_PROPERTY\(([\w<>:, ]+?)\s+(\w+)\s+READ", line)
                if m:
                    comment = line.split("//", 1)[1].strip() if "//" in line else ""
                    props.append((m.group(2), m.group(1).strip(), comment))
                m = re.search(r"Q_INVOKABLE\s+(.+?\));\s*(//\s*(.*))?$", line.strip())
                if m:
                    sig = re.sub(r"\s+", " ", m.group(1))
                    sig = re.sub(r"\bconst\s+(\w+)\s*&", r"\1 ", sig).replace("  ", " ")
                    invokables.append((sig, m.group(3) or ""))
            base_state = cls.group(3) == "ServiceState"
            out.append((qml_name, doc, props, invokables, base_state, "QML_SINGLETON" in body))
    return out


def main():
    md = ["# astraOS SDK reference", "",
          "Generated from the sources by `sdk/tools/gen_reference.py`: do not edit by hand.", "",
          "```qml", "import QtQuick", "import Astra.Core       // the system: settings, apps, files, notifications...",
          "import Astra.Controls   // the UI: every app is built from these", "```", "",
          "## Astra.Controls", ""]
    for name in sorted(os.listdir(CONTROLS)):
        if not name.endswith(".qml") or name[:-4] in INTERNAL:
            continue
        doc, props, signals, funcs = qml_component(os.path.join(CONTROLS, name))
        md += [f"### {name[:-4]}", ""]
        if doc:
            md += [" ".join(d for d in doc if d) or "", ""]
        if props:
            md += ["| Property | Type | Default | |", "|---|---|---|---|"]
            for p, t, ro, default, comment in props:
                md.append(f"| `{p}` | {t}{' (read-only)' if ro else ''} | `{default}` | {comment} |" if default else
                          f"| `{p}` | {t}{' (read-only)' if ro else ''} | | {comment} |")
            md.append("")
        if signals:
            md += ["Signals: " + ", ".join(f"`{s}`" + (f" ({c})" if c else "") for s, c in signals), ""]
        if funcs:
            md += ["Functions: " + ", ".join(f"`{f}`" for f in funcs), ""]
    md += ["## Astra.Core", "",
           "Singletons backed by the system (astrad). Calls that need a permission ask the user the first time.", ""]
    for qml_name, doc, props, invokables, base_state, singleton in core_singletons():
        md += [f"### {qml_name}" + ("" if singleton else " (type)"), ""]
        if doc:
            md += [" ".join(doc), ""]
        if base_state:
            md += ["`state` (map, the service's state), `ready`, `revision`; `call(method, params, callback(result, error))`.", ""]
        if props:
            md += ["| Property | Type | |", "|---|---|---|"] + [f"| `{p}` | {t} | {c} |" for p, t, c in props] + [""]
        if invokables:
            md += ["| Function | |", "|---|---|"] + [f"| `{sig}` | {c} |" for sig, c in invokables] + [""]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(md).rstrip() + "\n")
    print(f"{OUT}: {len(md)} lines")


if __name__ == "__main__":
    main()
