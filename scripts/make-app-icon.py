#!/usr/bin/env python3
"""Genereert het Inkline-app-icoon (placeholder) als PNG's voor de asset catalog.

Concept: inkt + regel. Een diepblauwe, afgeronde tegel met een lichte
basislijn (de "line") en een inktdruppel die er precies op landt, met links
een tekstcursor. Alles wordt met signed-distance-functies getekend en 3x3
gesupersampled, zodat het op elke grootte scherp is.

Gebruik:  python3 scripts/make-app-icon.py
Schrijft: App/Resources/Assets.xcassets/AppIcon.appiconset/*.png
"""

import math
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "App", "Resources", "Assets.xcassets", "AppIcon.appiconset")

INK_TOP = (0x16, 0x2A, 0x4F)
INK_BOTTOM = (0x0B, 0x16, 0x2B)
DROP_TOP = (0x5A, 0xC8, 0xFA)
DROP_BOTTOM = (0x2E, 0x7B, 0xE6)
LINE = (0xF2, 0xF4, 0xF8)
CARET = (0xFF, 0xB8, 0x4D)


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def over(dst, src, alpha):
    return tuple(round(dst[i] * (1 - alpha) + src[i] * alpha) for i in range(3))


def rounded_rect_sdf(x, y, half_w, half_h, radius):
    dx = abs(x) - (half_w - radius)
    dy = abs(y) - (half_h - radius)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    inside = min(max(dx, dy), 0.0)
    return outside + inside - radius


def drop_sdf(x, y, radius):
    """Klassieke inktdruppel: een bol met een punt naar boven."""
    if y <= 0:
        return math.hypot(x, y) - radius
    # Boven het midden loopt de vorm taps toe naar een punt.
    k = 1.0 - min(y / (radius * 2.05), 1.0)
    width = radius * (k ** 0.72)
    return abs(x) - width


def pixel(u, v):
    """Kleur voor genormaliseerde coordinaten in [-1, 1]; (0,0) is het midden."""
    tile = rounded_rect_sdf(u, v, 0.94, 0.94, 0.42)
    if tile > 0.004:
        return None  # transparant buiten de tegel

    base = mix(INK_TOP, INK_BOTTOM, (v + 1) / 2)

    # Zachte hooglicht linksboven.
    glow = max(0.0, 1.0 - math.hypot(u + 0.45, v + 0.5) / 1.25)
    color = over(base, (0x2C, 0x4C, 0x86), glow * 0.45)

    # Basislijn.
    line_y = 0.52
    line_half = 0.052
    if abs(v - line_y) < line_half and abs(u) < 0.70:
        edge = 1.0 - (abs(v - line_y) / line_half) ** 6
        color = over(color, LINE, 0.92 * edge)

    # Tekstcursor links, staand op de lijn.
    if -0.62 <= u <= -0.545 and -0.16 <= v <= line_y:
        color = over(color, CARET, 0.95)

    # Inktdruppel met de punt omhoog, rustend op de lijn.
    # De y-as wordt gespiegeld omdat v naar beneden loopt.
    d = drop_sdf(u - 0.10, -(v - 0.17), 0.345)
    if d < 0:
        t = min(1.0, max(0.0, (v + 0.45) / 1.0))
        drop = mix(DROP_TOP, DROP_BOTTOM, t)
        color = over(color, drop, 1.0)
        # Glans linksboven in de druppel.
        s = max(0.0, 1.0 - math.hypot(u + 0.02, v - 0.02) / 0.30)
        color = over(color, (0xFF, 0xFF, 0xFF), s * 0.38)

    return color


def render(size, samples=3):
    rows = []
    for py in range(size):
        row = bytearray()
        for px in range(size):
            r = g = b = a = 0.0
            for sy in range(samples):
                for sx in range(samples):
                    u = ((px + (sx + 0.5) / samples) / size) * 2 - 1
                    v = ((py + (sy + 0.5) / samples) / size) * 2 - 1
                    color = pixel(u, v)
                    if color is not None:
                        r += color[0]
                        g += color[1]
                        b += color[2]
                        a += 255
            n = samples * samples
            alpha = a / n
            if alpha > 0:
                covered = a / 255.0
                row += bytes((round(r / covered), round(g / covered),
                              round(b / covered), round(alpha)))
            else:
                row += bytes((0, 0, 0, 0))
        rows.append(bytes(row))
    return rows


def write_png(path, size):
    rows = render(size)
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(tag, data):
        payload = tag + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


SIZES = [16, 32, 64, 128, 256, 512, 1024]

CONTENTS = {
    "images": [
        {"size": "16x16", "idiom": "mac", "filename": "icon_16.png", "scale": "1x"},
        {"size": "16x16", "idiom": "mac", "filename": "icon_32.png", "scale": "2x"},
        {"size": "32x32", "idiom": "mac", "filename": "icon_32.png", "scale": "1x"},
        {"size": "32x32", "idiom": "mac", "filename": "icon_64.png", "scale": "2x"},
        {"size": "128x128", "idiom": "mac", "filename": "icon_128.png", "scale": "1x"},
        {"size": "128x128", "idiom": "mac", "filename": "icon_256.png", "scale": "2x"},
        {"size": "256x256", "idiom": "mac", "filename": "icon_256.png", "scale": "1x"},
        {"size": "256x256", "idiom": "mac", "filename": "icon_512.png", "scale": "2x"},
        {"size": "512x512", "idiom": "mac", "filename": "icon_512.png", "scale": "1x"},
        {"size": "512x512", "idiom": "mac", "filename": "icon_1024.png", "scale": "2x"},
    ],
    "info": {"version": 1, "author": "xcode"},
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for size in SIZES:
        path = os.path.join(OUT, "icon_%d.png" % size)
        write_png(path, size)
        print("geschreven:", os.path.relpath(path, os.path.join(HERE, "..")))
    import json
    with open(os.path.join(OUT, "Contents.json"), "w") as handle:
        json.dump(CONTENTS, handle, indent=2)
        handle.write("\n")


if __name__ == "__main__":
    main()
