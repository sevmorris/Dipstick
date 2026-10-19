#!/usr/bin/env python3
"""make-appicon.py — generate the Dipstick app icon.

A dipstick: the ring you pull it out by, the blade with its two level marks,
and a drop of oil off the tip. It is folded down its centre the way the
sibling apps' glyphs are: orange on blue, lit on the left and in shade on the
right. The ground, the two planes and the geometry are PasswordGen's
tools/icon/make-appicon.py, whose colours were sampled from FilmStrip's icon,
so Dipstick sits on the same shelf as the other apps. A blade upright on the
fold puts the seam where the eye already reads a centre line.

The marks are slots cut into the blade, not bars across it. Bars that stood
out either side of the blade, under a ring, made the first pass a key, and
keys are KeyVault's; the two apps share a Dock. No gauge or needle either: the
menu bar shows status symbols, and a dial would read as one more of them.

The icon is for Finder, the DMG and the Applications folder. The menu bar
never shows it, since Dipstick is an LSUIElement app.

Geometry follows Apple's macOS grid: on a 1024 canvas the body is 824x824 with
a ~185 corner radius, inset 100 a side, which is where every sibling sits.

Everything is drawn at 4x and downsampled with Lanczos — PIL's polygons and
rounded rectangles are aliased, and the fold seam shows every jaggy at 1024.

Usage:
  python3 tools/icon/make-appicon.py [--out FILE]

Writes assets/AppIcon.icns, which build.sh and release.sh copy into the
bundle. Requires Pillow, and iconutil from the Xcode command line tools.
"""

import argparse
import math
import os
import subprocess
import sys
import tempfile

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
except ImportError:
    sys.exit("make-appicon: Pillow is required — pip install Pillow")

# ── Canvas ────────────────────────────────────────────────────────────────────
BASE = 1024          # the coordinate space every number below is written in
SS = 4               # supersampling factor
S = BASE * SS

BODY_INSET = 100     # Apple's grid: 824x824 body on a 1024 canvas
CORNER = 185

# The .iconset an .icns is built from: (point size, scale) -> file name.
ICONSET = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
           (256, 1), (256, 2), (512, 1), (512, 2)]

# ── Palette ───────────────────────────────────────────────────────────────────
# FilmStrip's ground, sampled down its left margin, as PasswordGen has it. It is
# not a straight ramp: it falls away quickly under the top edge and flattens
# toward the bottom, and a two-stop gradient between the same end colours reads
# visibly paler.
GROUND = [(100, (38, 104, 149)), (300, (18, 89, 137)), (500, (1, 77, 127)),
          (700, (0, 70, 116)), (924, (0, 64, 107))]
# The two planes either side of the fold, each a touch darker at the foot.
LIT = [(150, (252, 158, 72)), (874, (246, 145, 62))]
SHADE = [(150, (198, 95, 14)), (874, (190, 88, 10))]
GLYPH_SHADOW = (0, 18, 36)

# ── Glyph ─────────────────────────────────────────────────────────────────────
# Top to bottom: the ring, the blade under it with the two marks cut into it,
# and the drop. The glyph runs from TOP to the foot of the drop, centred on the
# canvas.
TOP = 160
RING_OUTER = 112     # radius
RING_BAND = 58       # about the blade's width, so the two read as one piece
BLADE_WIDTH = 108
TIP = 724            # the foot of the blade's rounded end
MARKS = (560, 634)   # centre of each mark
MARK_WIDTH = 60
MARK_HEIGHT = 24
DROP_TOP = 752       # its point
DROP_HEIGHT = 112    # point to foot: the foot is at 864, as far below the
DROP_WIDTH = 80      # centre as TOP is above it


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def px(v):
    """1024-space value -> supersampled pixels."""
    return int(round(v * SS))


def vertical_gradient(stops):
    """A full-canvas gradient through (y, colour) stops, flat beyond the ends."""
    column = Image.new("RGB", (1, BASE))
    for y in range(BASE):
        if y <= stops[0][0]:
            colour = stops[0][1]
        elif y >= stops[-1][0]:
            colour = stops[-1][1]
        else:
            for (y0, c0), (y1, c1) in zip(stops, stops[1:]):
                if y0 <= y <= y1:
                    colour = lerp(c0, c1, (y - y0) / (y1 - y0))
                    break
        column.putpixel((0, y), colour)
    return column.resize((S, S), Image.BILINEAR)


def drop(d, cx):
    """The drop: a disc at the foot, and a point above it, joined along the
    two lines from the point that just touch the disc."""
    r = DROP_WIDTH / 2
    cy = DROP_TOP + DROP_HEIGHT - r
    d.ellipse([px(cx - r), px(cy - r), px(cx + r), px(cy + r)], fill=255)
    lean = math.asin(r / (cy - DROP_TOP))
    tx, ty = r * math.cos(lean), r * math.sin(lean)
    d.polygon([(px(cx), px(DROP_TOP)), (px(cx - tx), px(cy - ty)),
               (px(cx + tx), px(cy - ty))], fill=255)


def dipstick():
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    cx = BASE / 2

    # The ring, as a disc with its hole cut out once the blade is drawn.
    ring_cy = TOP + RING_OUTER
    d.ellipse([px(cx - RING_OUTER), px(ring_cy - RING_OUTER),
               px(cx + RING_OUTER), px(ring_cy + RING_OUTER)], fill=255)

    # The blade starts inside the ring's band, so the two join without a
    # seam, and ends in a rounded tip; only the tip is round.
    blade_top = ring_cy + RING_OUTER - RING_BAND / 2
    d.rounded_rectangle([px(cx - BLADE_WIDTH / 2), px(blade_top),
                         px(cx + BLADE_WIDTH / 2), px(TIP)],
                        radius=px(BLADE_WIDTH / 2), fill=255)
    d.rectangle([px(cx - BLADE_WIDTH / 2), px(blade_top),
                 px(cx + BLADE_WIDTH / 2), px(TIP - BLADE_WIDTH / 2)],
                fill=255)

    # The level marks, cut through the blade.
    for y in MARKS:
        d.rounded_rectangle([px(cx - MARK_WIDTH / 2), px(y - MARK_HEIGHT / 2),
                             px(cx + MARK_WIDTH / 2), px(y + MARK_HEIGHT / 2)],
                            radius=px(MARK_HEIGHT / 2), fill=0)

    inner = RING_OUTER - RING_BAND
    d.ellipse([px(cx - inner), px(ring_cy - inner),
               px(cx + inner), px(ring_cy + inner)], fill=0)

    drop(d, cx)
    return m


def build_master():
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    body = Image.new("L", (S, S), 0)
    ImageDraw.Draw(body).rounded_rectangle(
        [px(BODY_INSET), px(BODY_INSET),
         px(BASE - BODY_INSET), px(BASE - BODY_INSET)],
        radius=px(CORNER), fill=255)

    # ── Shadow ────────────────────────────────────────────────────────────────
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.putalpha(ImageChops.offset(body, 0, px(10))
                    .point(lambda v: v * 78 // 255))
    canvas = Image.alpha_composite(
        canvas, shadow.filter(ImageFilter.GaussianBlur(px(10))))

    # ── Ground ────────────────────────────────────────────────────────────────
    ground = vertical_gradient(GROUND).convert("RGBA")
    ground.putalpha(body)
    canvas = Image.alpha_composite(canvas, ground)

    # ── Glyph ─────────────────────────────────────────────────────────────────
    glyph = dipstick()

    # Its shadow falls down and to the right, and stays on the ground.
    cast = Image.new("RGBA", (S, S), GLYPH_SHADOW + (0,))
    cast.putalpha(ImageChops.offset(glyph, px(12), px(22))
                  .point(lambda v: v * 175 // 255))
    cast = cast.filter(ImageFilter.GaussianBlur(px(18)))
    cast.putalpha(ImageChops.multiply(cast.getchannel("A"), body))
    canvas = Image.alpha_composite(canvas, cast)

    # The fold: lit left of the vertical centre line, shade right of it.
    right = Image.new("L", (S, S), 0)
    ImageDraw.Draw(right).rectangle([px(BASE / 2), 0, S, S], fill=255)
    planes = Image.composite(vertical_gradient(SHADE), vertical_gradient(LIT),
                             right).convert("RGBA")
    planes.putalpha(glyph)
    return Image.alpha_composite(canvas, planes)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.normpath(
        os.path.join(here, "..", "..", "assets", "AppIcon.icns"))

    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=default_out,
                    help="the .icns file to write")
    args = ap.parse_args()

    if not os.path.isdir(os.path.dirname(os.path.abspath(args.out))):
        sys.exit(f"make-appicon: no such directory: {os.path.dirname(args.out)}")

    master = build_master()
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.mkdir(iconset)
        for points, scale in ICONSET:
            suffix = "@2x" if scale == 2 else ""
            size = points * scale
            name = f"icon_{points}x{points}{suffix}.png"
            master.resize((size, size), Image.LANCZOS).save(
                os.path.join(iconset, name), "PNG")
        subprocess.run(["iconutil", "-c", "icns", "-o", args.out, iconset],
                       check=True)
    print(f"  wrote {os.path.relpath(args.out)}")


if __name__ == "__main__":
    main()
