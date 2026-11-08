#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Prints the package name of an APK (astrad's android service, for MyDroid).

An APK is a zip whose AndroidManifest.xml is in Android's binary XML: a string
pool, then the elements. The <manifest> element's "package" attribute is the
name Android installs the app under.

  apkinfo.py FILE.apk
"""
import struct
import sys
import zipfile

RES_STRING_POOL = 0x0001
RES_XML_START_ELEMENT = 0x0102
UTF8_FLAG = 1 << 8


def strings(data, off):
    _, header_size, _, count, _, flags, start, _ = struct.unpack_from("<HHIIIIII", data, off)
    offsets = struct.unpack_from("<%dI" % count, data, off + header_size)
    base = off + start
    out = []
    for o in offsets:
        p = base + o
        if flags & UTF8_FLAG:
            n = data[p]
            p += 2 if n & 0x80 else 1           # length in characters
            n = data[p]
            if n & 0x80:
                n = ((n & 0x7F) << 8) | data[p + 1]
                p += 2
            else:
                p += 1
            out.append(data[p:p + n].decode("utf-8", "replace"))
        else:
            n = struct.unpack_from("<H", data, p)[0]
            p += 2
            if n & 0x8000:
                n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", data, p)[0]
                p += 2
            out.append(data[p:p + 2 * n].decode("utf-16-le", "replace"))
    return out


def package(apk):
    with zipfile.ZipFile(apk) as z:
        data = z.read("AndroidManifest.xml")
    pool = []
    off = struct.unpack_from("<H", data, 2)[0]   # after the file header
    while off + 8 <= len(data):
        kind, _, size = struct.unpack_from("<HHI", data, off)
        if size < 8:
            break
        if kind == RES_STRING_POOL and not pool:
            pool = strings(data, off)
        elif kind == RES_XML_START_ELEMENT:
            name = struct.unpack_from("<I", data, off + 20)[0]
            attr_start, attr_size, attr_count = struct.unpack_from("<HHH", data, off + 24)
            if pool[name] == "manifest":
                for i in range(attr_count):
                    a = off + 16 + attr_start + i * attr_size
                    _, aname, raw = struct.unpack_from("<III", data, a)
                    if pool[aname] == "package" and raw != 0xFFFFFFFF:
                        return pool[raw]
                return ""
        off += size
    return ""


if __name__ == "__main__":
    try:
        print(package(sys.argv[1]))
    except Exception as e:  # not an APK, or damaged
        sys.exit("apkinfo: %s" % e)
