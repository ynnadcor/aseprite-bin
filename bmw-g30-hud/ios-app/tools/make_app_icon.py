#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Draw the BMW Link app icon: a HUD-style turn arrow on a dark gradient.

Original artwork (no BMW logos or other trademarks). Output is a 1024x1024 RGB
PNG with no alpha channel, as App Store Connect requires; Xcode makes every
other size from it. Needs Pillow.

    python3 tools/make_app_icon.py BMWLinkApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
"""
import math
import sys

from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # draw at 4x, then downsample for smooth edges


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def main(out_path):
    n = SIZE * SS
    img = Image.new("RGB", (n, n))
    d = ImageDraw.Draw(img)

    top, bottom = (20, 52, 96), (5, 11, 22)
    for y in range(n):
        d.line([(0, y), (n, y)], fill=lerp(top, bottom, y / (n - 1)))

    arrow = (238, 246, 255)
    half = 75                       # half the shaft width
    x0, turn_y, radius = 340, 440, 150
    cx = x0 + radius                # centre of the quarter turn
    head_y = turn_y - radius
    outer = [(cx + (radius + half) * math.cos(math.radians(a)),
              turn_y + (radius + half) * math.sin(math.radians(a))) for a in range(180, 271)]
    inner = [(cx + (radius - half) * math.cos(math.radians(a)),
              turn_y + (radius - half) * math.sin(math.radians(a))) for a in range(270, 179, -1)]
    shaft = ([(x0 - half, 850)] + outer + [(570, head_y - half), (570, head_y + half)]
             + inner + [(x0 + half, 850)])
    d.polygon([(x * SS, y * SS) for x, y in shaft], fill=arrow)
    head = [(550, head_y - 165), (785, head_y), (550, head_y + 165)]
    d.polygon([(x * SS, y * SS) for x, y in head], fill=arrow)

    # Cyan "distance to turn" bar, as on a head-up display.
    d.rounded_rectangle([300 * SS, 890 * SS, 724 * SS, 918 * SS], radius=14 * SS, fill=(64, 200, 255))

    img.resize((SIZE, SIZE), Image.LANCZOS).save(out_path, optimize=True)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "AppIcon-1024.png")
