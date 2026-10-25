#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generates the astraOS symbolic icon set (frameworks/qml/controls/icons).

Symbolic icons are white on a 24x24 grid so they can be tinted at runtime.
Weather glyphs are coloured, 48x48, and used by the home screen greeting
and the weather widgets.

Usage: python3 tools/icons/generate_icons.py
"""
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "frameworks", "qml", "controls", "icons")
W = "#FFFFFF"


def svg(body, size=24):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">{body}</svg>\n'


def stroke(d, w=2.0):
    return f'<path d="{d}" fill="none" stroke="{W}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>'


def fill(d, rule="nonzero"):
    return f'<path d="{d}" fill="{W}" fill-rule="{rule}"/>'


def rect(x, y, w, h, r):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{W}"/>'


def gear(teeth=8, ro=10.2, ri=7.6, hole=3.0):
    pts = []
    n = teeth * 4
    for i in range(n):
        a = 2 * math.pi * i / n - math.pi / 2
        r = ro if (i % 4) in (1, 2) else ri
        pts.append((12 + r * math.cos(a), 12 + r * math.sin(a)))
    d = "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in pts) + "Z"
    return stroke(d, 1.8) + f'<circle cx="12" cy="12" r="{hole}" fill="none" stroke="{W}" stroke-width="1.8"/>'


def rays(cx, cy, core, r_in, r_out, color, width, count=8):
    s = f'<circle cx="{cx}" cy="{cy}" r="{core}" fill="{color}"/>'
    for i in range(count):
        a = 2 * math.pi * i / count
        s += (f'<path d="M{cx + r_in * math.cos(a):.2f} {cy + r_in * math.sin(a):.2f}'
              f'L{cx + r_out * math.cos(a):.2f} {cy + r_out * math.sin(a):.2f}" '
              f'stroke="{color}" stroke-width="{width}" stroke-linecap="round"/>')
    return s


SPEAKER = "M3 9.2v5.6a1 1 0 0 0 1 1h3.3l4.6 3.8a.8.8 0 0 0 1.3-.6V5a.8.8 0 0 0-1.3-.6L7.3 8.2H4a1 1 0 0 0-1 1z"

SYMBOLIC = {
    "chevron-right": stroke("M9 4.5l7.5 7.5L9 19.5"),
    "chevron-down": stroke("M5 9l7 7 7-7", 2.2),
    "chevron-left": stroke("M15 4.5L7.5 12l7.5 7.5"),
    "settings": gear(),
    "edit": stroke("M11 4H6.5A2.5 2.5 0 0 0 4 6.5v11A2.5 2.5 0 0 0 6.5 20h11a2.5 2.5 0 0 0 2.5-2.5V13", 1.8)
    + stroke("M17.8 3.2a2 2 0 0 1 2.9 2.9L12.5 14.3 9 15l.7-3.5z", 1.8),
    "play": fill("M7 4.6v14.8a1.2 1.2 0 0 0 1.8 1L20.9 13a1.2 1.2 0 0 0 0-2L8.8 3.6A1.2 1.2 0 0 0 7 4.6z"),
    "pause": rect(5.5, 4, 4.5, 16, 1.4) + rect(14, 4, 4.5, 16, 1.4),
    "previous": rect(4, 5, 2.4, 14, 1.2)
    + fill("M20 6.1v11.8a1.1 1.1 0 0 1-1.7.9L9.2 12.9a1.1 1.1 0 0 1 0-1.8l9.1-5.9a1.1 1.1 0 0 1 1.7.9z"),
    "next": rect(17.6, 5, 2.4, 14, 1.2)
    + fill("M4 6.1v11.8a1.1 1.1 0 0 0 1.7.9l9.1-5.9a1.1 1.1 0 0 0 0-1.8L5.7 5.2A1.1 1.1 0 0 0 4 6.1z"),
    "lock": stroke("M8 10.5V8a4 4 0 0 1 8 0v2.5", 2.2) + rect(4.5, 10, 15, 11, 3),
    "flashlight": fill("M6.5 2.5h11v3.2l-2.6 4.3V20a2 2 0 0 1-2 2h-1.8a2 2 0 0 1-2-2V10L6.5 5.7z"
                       "M12 12.2a1.3 1.3 0 1 0 0 2.6 1.3 1.3 0 0 0 0-2.6z", "evenodd"),
    "camera": fill("M9.2 3.5h5.6a1.5 1.5 0 0 1 1.3.8L17 6h2a3 3 0 0 1 3 3v8.5a3 3 0 0 1-3 3H5a3 3 0 0 1-3-3V9"
                   "a3 3 0 0 1 3-3h2l.9-1.7a1.5 1.5 0 0 1 1.3-.8z"
                   "M12 9.2a4 4 0 1 0 0 8 4 4 0 0 0 0-8z"
                   "M12 11a2.2 2.2 0 1 1 0 4.4 2.2 2.2 0 0 1 0-4.4z", "evenodd"),
    "bluetooth": stroke("M6.5 7.5l11 9-5.5 5V2.5l5.5 5-11 9"),
    "location": fill("M12 2a7.5 7.5 0 0 0-7.5 7.5c0 5.4 6.2 11.8 6.9 12.5a.9.9 0 0 0 1.2 0"
                     "c.7-.7 6.9-7.1 6.9-12.5A7.5 7.5 0 0 0 12 2z"),
    "sound": fill(SPEAKER) + stroke("M16.2 8.8a4.5 4.5 0 0 1 0 6.4") + stroke("M19.2 5.8a8.8 8.8 0 0 1 0 12.4"),
    "volume": fill(SPEAKER) + stroke("M16.5 8.5a5 5 0 0 1 0 7", 2.2),
    "gamepad": fill("M7.5 6.5h9a5.5 5.5 0 0 1 5.4 6.5l-.7 3.7a2.8 2.8 0 0 1-4.8 1.4L14.6 16H9.4l-1.8 2.1"
                    "a2.8 2.8 0 0 1-4.8-1.4L2.1 13A5.5 5.5 0 0 1 7.5 6.5z"
                    "M7.3 9.6v1.6H5.7v1.5h1.6v1.6h1.5v-1.6h1.6v-1.5H8.8V9.6z"
                    "M16.2 9.7a1 1 0 1 0 0 2 1 1 0 0 0 0-2zM18.2 11.9a1 1 0 1 0 0 2 1 1 0 0 0 0-2z", "evenodd"),
    "cast": fill("M5 4h14a3 3 0 0 1 3 3v10a3 3 0 0 1-3 3h-6.2a9.8 9.8 0 0 0-9.8-9.6V7a3 3 0 0 1 3-3z")
    + stroke("M3 13.6a6.4 6.4 0 0 1 6.4 6.4", 1.9) + stroke("M3 17.2a2.8 2.8 0 0 1 2.8 2.8", 1.9),
    "focus": fill("M12 3.5a3.3 3.3 0 1 1 0 6.6 3.3 3.3 0 0 1 0-6.6z"
                  "M5.2 6.2a2.4 2.4 0 1 1 0 4.8 2.4 2.4 0 0 1 0-4.8zM18.8 6.2a2.4 2.4 0 1 1 0 4.8 2.4 2.4 0 0 1 0-4.8z"
                  "M12 12.2c3.8 0 6.6 1.9 6.6 4.6 0 1.4-1.2 2.4-3 2.4H8.4c-1.8 0-3-1-3-2.4 0-2.7 2.8-4.6 6.6-4.6z"
                  "M4.4 12.6c-.6.9-.9 1.9-.9 2.9 0 .5.1 1 .3 1.4C2.2 16.7 1 16 1 14.9c0-1.4 1.4-2.3 3.4-2.3z"
                  "M19.6 12.6c2 0 3.4.9 3.4 2.3 0 1.1-1.2 1.8-2.8 2 .2-.4.3-.9.3-1.4 0-1-.3-2-.9-2.9z"),
    "qr": stroke("M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4z", 1.9)
    + rect(14, 14, 2.4, 2.4, 0.5) + rect(17.6, 17.6, 2.4, 2.4, 0.5)
    + rect(17.6, 14, 2.4, 2.4, 0.5) + rect(14, 17.6, 2.4, 2.4, 0.5),
    "briefcase": fill("M9 6V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v1h3.5A2.5 2.5 0 0 1 21 8.5v9A2.5 2.5 0 0 1 18.5 20h-13"
                      "A2.5 2.5 0 0 1 3 17.5v-9A2.5 2.5 0 0 1 5.5 6zM10.8 5v1h2.4V5zM10.2 11.5v2h3.6v-2z", "evenodd"),
    "moon": fill("M20.5 14.6A8.7 8.7 0 0 1 9.4 3.5a.6.6 0 0 0-.8-.7A9.6 9.6 0 1 0 21.2 15.4a.6.6 0 0 0-.7-.8z"),
    "brightness": rays(12, 12, 4.0, 6.2, 8.8, W, 1.9),
    "search": stroke("M10.5 4a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13zM15.3 15.3L20 20", 2.2),
    "mic": rect(8.5, 2.5, 7, 12, 3.5) + stroke("M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"),
    "info": stroke("M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18z", 1.8) + stroke("M12 11v5.5")
    + f'<circle cx="12" cy="7.8" r="1.2" fill="{W}"/>',
    "trash": stroke("M4 6.5h16M9.5 6.5V4.8a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1v1.7"
                    "M6 6.5l.9 12.4a2 2 0 0 0 2 1.8h6.2a2 2 0 0 0 2-1.8L18 6.5", 1.8),
    "grid": rect(4, 4, 6.5, 6.5, 1.8) + rect(13.5, 4, 6.5, 6.5, 1.8)
    + rect(4, 13.5, 6.5, 6.5, 1.8) + rect(13.5, 13.5, 6.5, 6.5, 1.8),
    "close": stroke("M6 6l12 12M18 6L6 18", 2.2),
    "check": stroke("M5 12.5l4.5 4.5L19 7.5", 2.4),
    "plus": stroke("M12 5v14M5 12h14", 2.2),
    "minus": stroke("M5 12h14", 2.2),
    "notification": stroke("M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0", 1.8),
    "person": fill("M12 3.5a4 4 0 1 1 0 8 4 4 0 0 1 0-8z"
                   "M12 13.5c4.4 0 7.5 2.2 7.5 5 0 1.2-1 2-2.4 2H6.9c-1.4 0-2.4-.8-2.4-2 0-2.8 3.1-5 7.5-5z"),
}

YELLOW = "#FFC93C"
CLOUD = "M15 38h20a9 9 0 0 0 1.4-17.9A12 12 0 0 0 13.2 22.6 7.8 7.8 0 0 0 15 38z"
GRADIENT = ('<defs><linearGradient id="c" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/>'
            '<stop offset="1" stop-color="#D9DCE6"/></linearGradient></defs>')


def cloud(dy):
    return GRADIENT + f'<path d="{CLOUD}" fill="url(#c)" transform="translate(0 {dy})"/>'


WEATHER = {
    "weather-sunny": rays(24, 24, 9, 14.5, 20, YELLOW, 3.2),
    "weather-clear": '<path d="M34.5 29.5A13 13 0 0 1 18.5 13.5a1 1 0 0 0-1.3-1.2A15 15 0 1 0 35.7 30.8'
                     'a1 1 0 0 0-1.2-1.3z" fill="#FFE08A"/>',
    "weather-partly-cloudy": rays(30, 17, 7, 11.5, 15.5, YELLOW, 2.6)
    + GRADIENT + f'<path d="{CLOUD}" fill="url(#c)" transform="translate(-3 4)"/>',
    "weather-cloudy": cloud(-2),
    "weather-rainy": cloud(-7) + "".join(
        f'<path d="M{x} 36l-2 6" stroke="#6CB8FF" stroke-width="3" stroke-linecap="round"/>' for x in (17, 25, 33)),
    "weather-snowy": cloud(-7) + "".join(
        f'<circle cx="{x}" cy="{y}" r="2" fill="#FFFFFF"/>' for x, y in ((17, 37), (25, 41), (33, 37))),
    "weather-stormy": cloud(-7) + f'<path d="M26 31l-6 8h5l-3 7 8-10h-5l3-5z" fill="{YELLOW}"/>',
    "weather-foggy": "".join(f'<rect x="{x}" y="{y}" width="{w}" height="3.4" rx="1.7" fill="#E6E8EF"/>'
                             for x, y, w in ((8, 15, 32), (5, 22, 38), (10, 29, 30), (14, 36, 22))),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, body in SYMBOLIC.items():
        with open(os.path.join(OUT, f"{name}.svg"), "w", encoding="utf-8") as f:
            f.write(svg(body))
    for name, body in WEATHER.items():
        with open(os.path.join(OUT, f"{name}.svg"), "w", encoding="utf-8") as f:
            f.write(svg(body, 48))
    print(f"wrote {len(SYMBOLIC) + len(WEATHER)} icons to {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
