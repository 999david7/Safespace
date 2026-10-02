#!/usr/bin/env python3
"""Renders the Safespace app icon: a yellow padlock with a paper-white shackle on an ink tile,
over a faint halftone grid.

    python3 scripts/make-icon.py

Writes Resources/AppIcon.png (macOS), Resources/AppIcon-windows.png and the Windows app icons in
windows/src-tauri/icons/. Needs Pillow (`pip install pillow`). The images are committed, so building
the apps doesn't need this.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 4  # supersampling factor
SIZE = 1024 * SS

# The app's palette (Sources/Safespace/Views/Components.swift).
INK_TOP = (30, 30, 33)
INK_BOTTOM = (6, 6, 7)
INK = (11, 11, 12)
PAPER_TOP = (252, 252, 249)
PAPER_BOTTOM = (196, 196, 190)
SIGNAL_TOP = (255, 218, 64)
SIGNAL_BOTTOM = (232, 178, 0)


def blank(fill=0):
    return Image.new("L", (SIZE, SIZE), fill)


def gradient(top, bottom, y0, y1):
    """A full-canvas RGBA image going from `top` at y0 to `bottom` at y1 (clamped outside)."""
    ramp = Image.linear_gradient("L").resize((1, max(1, int(y1 - y0))))
    column = Image.new("L", (1, SIZE), 0)
    column.paste(255, (0, int(y1), 1, SIZE))
    column.paste(ramp, (0, int(y0)))
    mask = column.resize((SIZE, SIZE))
    return Image.composite(Image.new("RGBA", (SIZE, SIZE), bottom + (255,)), Image.new("RGBA", (SIZE, SIZE), top + (255,)), mask)


def layer(img, fill, mask):
    """Composites `fill` (a color or an RGBA image) onto `img` through `mask`."""
    if isinstance(fill, tuple):
        fill = Image.new("RGBA", (SIZE, SIZE), fill if len(fill) == 4 else fill + (255,))
    shaped = fill.copy()
    shaped.putalpha(ImageChops.multiply(fill.getchannel("A"), mask))
    return Image.alpha_composite(img, shaped)


def render(tile_inset, radius_ratio, shadow):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    inset = tile_inset * SS
    x0, y0, x1, y1 = inset, inset, SIZE - inset, SIZE - inset
    tile = x1 - x0
    radius = int(tile * radius_ratio)

    tile_mask = blank()
    ImageDraw.Draw(tile_mask).rounded_rectangle((x0, y0, x1, y1), radius=radius, fill=255)

    if shadow:
        drop = blank()
        ImageDraw.Draw(drop).rounded_rectangle((x0, y0 + 14 * SS, x1, y1 + 14 * SS), radius=radius, fill=110)
        img = layer(img, (0, 0, 0), drop.filter(ImageFilter.GaussianBlur(24 * SS)))

    img = layer(img, gradient(INK_TOP, INK_BOTTOM, y0, y1), tile_mask)

    # Halftone grid: dots that swell toward the lower right, a nod to the old icon and the print look.
    dots = blank()
    d = ImageDraw.Draw(dots)
    cols = 26
    pitch = tile / cols
    for r in range(cols):
        for c in range(cols):
            u, v = (c + 0.5) / cols, (r + 0.5) / cols
            weight = max(0.0, (u + v) / 2 - 0.25) / 0.75
            rad = pitch * 0.07 + pitch * 0.2 * weight
            cx, cy = x0 + (c + 0.5) * pitch, y0 + (r + 0.5) * pitch
            d.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), fill=int(18 + 30 * weight))
    img = layer(img, (255, 255, 255), ImageChops.multiply(dots, tile_mask))

    # Padlock geometry, in tile units.
    def tx(u):
        return x0 + u * tile

    def ty(v):
        return y0 + v * tile

    body = (tx(0.255), ty(0.455), tx(0.745), ty(0.805))
    body_radius = 0.075 * tile
    shackle_cx, shackle_cy = tx(0.5), ty(0.405)
    outer, thickness = 0.185 * tile, 0.072 * tile
    inner = outer - thickness

    shackle = blank()
    s = ImageDraw.Draw(shackle)
    s.ellipse((shackle_cx - outer, shackle_cy - outer, shackle_cx + outer, shackle_cy + outer), fill=255)
    s.ellipse((shackle_cx - inner, shackle_cy - inner, shackle_cx + inner, shackle_cy + inner), fill=0)
    s.rectangle((0, shackle_cy, SIZE, SIZE), fill=0)
    for side in (-1, 1):
        a, b = sorted((shackle_cx + side * outer, shackle_cx + side * inner))
        s.rectangle((a, shackle_cy - 1, b, body[1] + body_radius), fill=255)

    body_mask = blank()
    ImageDraw.Draw(body_mask).rounded_rectangle(body, radius=body_radius, fill=255)

    # Soft shadow under the whole lock.
    lock_shadow = ImageChops.lighter(shackle, body_mask).filter(ImageFilter.GaussianBlur(18 * SS))
    lock_shadow = ImageChops.offset(lock_shadow, 0, 16 * SS).point(lambda p: p * 0.55)
    img = layer(img, (0, 0, 0), ImageChops.multiply(lock_shadow, tile_mask))

    img = layer(img, gradient(PAPER_TOP, PAPER_BOTTOM, shackle_cy - outer, body[1]), shackle)
    # Shade the shackle's legs where they disappear into the body.
    seat = gradient((0, 0, 0), (255, 255, 255), body[1] - 0.06 * tile, body[1]).getchannel("R").point(lambda p: p * 0.45)
    img = layer(img, (40, 40, 38), ImageChops.multiply(seat, shackle))
    img = layer(img, gradient(SIGNAL_TOP, SIGNAL_BOTTOM, body[1], body[3]), body_mask)

    # A thin light edge along the top of the body, and a darker one along the bottom.
    edge = 3 * SS
    top_edge = ImageChops.subtract(body_mask, ImageChops.offset(body_mask, 0, edge))
    img = layer(img, (255, 244, 190, 150), top_edge)
    bottom_edge = ImageChops.subtract(body_mask, ImageChops.offset(body_mask, 0, -edge))
    img = layer(img, (150, 110, 0, 120), bottom_edge)

    # Keyhole: a circle over a tapered slot, cut in ink.
    keyhole = blank()
    k = ImageDraw.Draw(keyhole)
    kx, ky, kr = tx(0.5), ty(0.6), 0.047 * tile
    k.ellipse((kx - kr, ky - kr, kx + kr, ky + kr), fill=255)
    slot_bottom, half_top, half_bottom = ty(0.712), kr * 0.42, kr * 0.62
    k.polygon([(kx - half_top, ky), (kx + half_top, ky), (kx + half_bottom, slot_bottom), (kx - half_bottom, slot_bottom)], fill=255)
    k.ellipse((kx - half_bottom, slot_bottom - half_bottom * 0.5, kx + half_bottom, slot_bottom + half_bottom * 0.5), fill=255)
    img = layer(img, INK + (255,), keyhole)

    # Hairline rim so the tile holds its shape on dark backgrounds.
    rim = ImageChops.subtract(tile_mask, ImageChops.offset(tile_mask, 0, 2 * SS))
    img = layer(img, (255, 255, 255, 40), rim)

    return img.resize((1024, 1024), Image.LANCZOS)


def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print(f"wrote {path}")


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    resources = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "Resources"

    # macOS: Big Sur icon grid (824pt tile inside 1024, with a soft drop shadow).
    save(render(100, 0.225, True), resources / "AppIcon.png")

    # Windows: the tile fills the canvas, as taskbar and Start icons expect.
    windows = render(24, 0.20, False)
    save(windows, resources / "AppIcon-windows.png")
    icons = root / "windows" / "src-tauri" / "icons"
    for name, px in [("32x32.png", 32), ("128x128.png", 128), ("128x128@2x.png", 256), ("icon.png", 512)]:
        save(windows.resize((px, px), Image.LANCZOS), icons / name)
    windows.save(icons / "icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (256, 256)])
    print(f"wrote {icons / 'icon.ico'}")
