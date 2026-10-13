#!/usr/bin/env python3
"""Generates the background artwork for the macOS installer DMG.

    python3 tool/gen_dmg_background.py
        -> macos/dmg/background.tiff   (committed; consumed by scripts/package_macos.sh)

Same arrangement as tool/flatten_icon.dart: the generator lives in tool/, the
output is committed, and the build script only ever reads the committed file.
That keeps `scripts/package_macos.sh` free of a Pillow dependency — a release
build must not fail because a Python package is missing.

The output is a two-page TIFF (1x + 2x) because that is the only way Finder
takes a Retina DMG background: it draws the picture 1:1 in points with no
scaling, so a lone 640x400 PNG renders soft on every Mac sold in a decade.
`tiffutil -cathidpicheck` is what tags the second page as the @2x variant.

GEOMETRY IS LOAD-BEARING. These numbers must agree with the AppleScript block
in scripts/package_macos.sh:

    window bounds {200, 120, 840, 520}  ->  640 x 400 frame
    icon "scion.app"      at (160, 158)
    icon "Applications"   at (480, 158)

Finder anchors the background at the top-left of the *content* view and clips
whatever runs past it. With the toolbar hidden the title bar eats ~31pt, so the
bottom ~31px of this image is never seen — nothing meaningful goes below y=340.
That same 31pt is why ICON_Y looks high for a 400px canvas: the icons are
centred in the 369pt of content that is actually visible, not in the frame.
"""

import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

W, H = 640, 400
APP_X, APPS_X, ICON_Y = 160, 480, 158
CAPTION_Y = 300

# LIGHT, even though the app itself is dark (lib/main.dart is Color(0xFF1C1C1E)),
# and this is not a style preference. The moment a window has a background
# picture, Finder draws icon labels in near-black — in dark mode too, because it
# assumes any custom background is a light one. A dark background here renders
# "scion" and "Applications" as black-on-black. Verified by screenshotting a
# mounted DMG; do not "fix" this to match the product palette.
BG_TOP = (250, 250, 252)
BG_BOTTOM = (236, 236, 240)
ARROW = (154, 154, 162)
TEXT = (134, 134, 139)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "D-DIN-Regular.otf")
OUT_DIR = os.path.join(ROOT, "macos", "dmg")


def render(scale: int) -> Image.Image:
    """Draws the artwork at `scale`x. Everything is expressed in 1x units and
    multiplied through, so the 1x and 2x pages cannot drift apart."""
    w, h = W * scale, H * scale
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)

    # Vertical gradient, drawn a row at a time. Cheap, and at this size the
    # banding is well under one 8-bit step per row.
    for y in range(h):
        t = y / (h - 1)
        d.line(
            [(0, y), (w, y)],
            fill=tuple(
                round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)
            ),
        )

    # The arrow spans the gap between the two 128pt icons: they occupy
    # x 96..224 and x 416..544, so 250..394 sits clear of both.
    x0, x1 = 252 * scale, 392 * scale
    cy = ICON_Y * scale
    head_w, head_h, shaft_h = 30 * scale, 18 * scale, 9 * scale

    # The shaft runs a full shaft-width *past* the head's base and the head is
    # drawn over it. A rounded cap on the tail reads as deliberate; the same cap
    # at the head end shows as a pinch where the two shapes meet, so it gets
    # buried. At that depth the head is still ~12 units half-tall against the
    # shaft's 4.5, so nothing peeks out.
    d.rounded_rectangle(
        [x0, cy - shaft_h // 2, x1 - head_w + shaft_h, cy + shaft_h // 2],
        radius=shaft_h // 2,
        fill=ARROW,
    )
    d.polygon(
        [(x1 - head_w, cy - head_h), (x1, cy), (x1 - head_w, cy + head_h)],
        fill=ARROW,
    )

    # D-DIN is the product's typeface (see pubspec.yaml), so the installer is
    # set in it too. Absence is not fatal — the arrow already carries the
    # instruction and the text is reinforcement.
    try:
        font = ImageFont.truetype(FONT, 15 * scale)
        d.text(
            (w // 2, CAPTION_Y * scale),
            "Drag SCION Controller into your Applications folder",
            font=font,
            fill=TEXT,
            anchor="mm",
        )
    except OSError:
        print(f"warning: {FONT} not found — rendering without caption", file=sys.stderr)

    return img


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    one = os.path.join(OUT_DIR, "background.png")
    two = os.path.join(OUT_DIR, "background@2x.png")
    tiff = os.path.join(OUT_DIR, "background.tiff")

    render(1).save(one)
    render(2).save(two)

    # -cathidpicheck marks page 2 as the HiDPI representation of page 1 and
    # verifies it really is exactly 2x.
    subprocess.run(
        ["tiffutil", "-cathidpicheck", one, two, "-out", tiff], check=True
    )
    os.remove(one)
    os.remove(two)

    print(f"wrote {os.path.relpath(tiff, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
