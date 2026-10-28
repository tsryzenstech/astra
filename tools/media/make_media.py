#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generates the stock wallpapers and sounds of astraOS.

  tools/media/make_media.py            writes into prebuilt/media/

Wallpapers are soft, vivid colour fields (1080 x 2400 JPEG); sounds are short
synthesized chimes (22.05 kHz mono WAV) so they are small and free of any
third-party rights. Needs numpy and Pillow.
"""
import math
import os
import wave

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "prebuilt", "media")
W, H = 1080, 2400

WALLPAPERS = {
    # name: background, [(x, y, radius, colour)] in fractions of the width/height
    "aurora": ("#050816", [(0.1, 0.2, 0.9, "#7B2FF7"), (0.9, 0.35, 0.8, "#00C9A7"), (0.4, 0.85, 0.9, "#1E3A8A")]),
    "sunset": ("#1A0510", [(0.2, 0.15, 0.8, "#FF7A00"), (0.85, 0.45, 0.85, "#FF2D8E"), (0.3, 0.9, 0.8, "#6A00F4")]),
    "ocean": ("#020B18", [(0.8, 0.1, 0.8, "#2F80FF"), (0.1, 0.55, 0.9, "#00B4D8"), (0.7, 0.95, 0.8, "#0A2463")]),
    "bloom": ("#14030C", [(0.5, 0.3, 0.95, "#FF4D6D"), (0.05, 0.8, 0.7, "#FFB020"), (0.95, 0.75, 0.7, "#B5179E")]),
    "mint": ("#03120D", [(0.15, 0.25, 0.85, "#34D058"), (0.9, 0.6, 0.8, "#00C9B1"), (0.35, 1.0, 0.7, "#0B6E4F")]),
}


def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


def wallpaper(bg, blobs):
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    img = np.tile(hex_rgb(bg), (H, W, 1))
    for bx, by, r, colour in blobs:
        d = np.sqrt((x - bx * W) ** 2 + (y - by * H) ** 2) / (r * W)
        a = np.clip(1 - d, 0, 1) ** 2.2 * 0.95
        img = img * (1 - a[..., None]) + hex_rgb(colour) * a[..., None]
    # A touch of grain avoids banding on OLED panels.
    rng = np.random.default_rng(7)
    img += rng.normal(0, 1.6, img.shape)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


SR = 22050

# name: (notes as (frequency Hz, start s, length s), total length s)
SOUNDS = {
    "alarms/Blossom": ([(784, 0.0, 0.5), (988, 0.18, 0.5), (1175, 0.36, 0.7), (988, 0.9, 0.45), (1319, 1.08, 0.8)], 2.0),
    "alarms/Daybreak": ([(523, 0.0, 0.6), (659, 0.25, 0.6), (784, 0.5, 0.6), (1047, 0.75, 1.0)], 2.0),
    "alarms/Pulse": ([(880, 0.0, 0.18), (880, 0.3, 0.18), (880, 0.6, 0.18), (1175, 0.9, 0.5)], 1.6),
    "ringtones/Orbit": ([(659, 0.0, 0.35), (880, 0.2, 0.35), (1319, 0.4, 0.5), (880, 0.8, 0.35), (1109, 1.0, 0.6)], 2.0),
    "ringtones/Nebula": ([(440, 0.0, 0.8), (554, 0.3, 0.8), (659, 0.6, 0.9), (880, 0.9, 1.0)], 2.2),
    "notifications/Pop": ([(1047, 0.0, 0.12), (1568, 0.07, 0.25)], 0.4),
    "notifications/Chime": ([(1319, 0.0, 0.3), (1760, 0.12, 0.45)], 0.7),
}


def chime(notes, length):
    t = np.arange(int(SR * length)) / SR
    out = np.zeros_like(t)
    for f, start, dur in notes:
        env_t = t - start
        mask = (env_t >= 0) & (env_t < dur + 0.6)
        e = np.where(mask, np.exp(-np.clip(env_t, 0, None) * 4.5 / max(dur, 0.1)) * np.clip(env_t * 200, 0, 1), 0)
        out += e * (np.sin(2 * math.pi * f * t) + 0.35 * np.sin(2 * math.pi * 2 * f * t) + 0.12 * np.sin(2 * math.pi * 3 * f * t))
    out /= max(1e-6, np.abs(out).max())
    return (out * 0.8 * 32767).astype(np.int16)


def main():
    os.makedirs(os.path.join(ROOT, "wallpapers"), exist_ok=True)
    for name, (bg, blobs) in WALLPAPERS.items():
        path = os.path.join(ROOT, "wallpapers", name + ".jpg")
        wallpaper(bg, blobs).save(path, quality=92, optimize=True, subsampling=0)
        print("wrote", os.path.relpath(path))
    for name, (notes, length) in SOUNDS.items():
        path = os.path.join(ROOT, "audio", name + ".wav")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(chime(notes, length).tobytes())
        print("wrote", os.path.relpath(path))


if __name__ == "__main__":
    main()
