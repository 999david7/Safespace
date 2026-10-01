#!/usr/bin/env python3
"""Renders the Safespace app icon: a halftone padlock with an orange keyhole on a paper tile.

    python3 scripts/make-icon.py            # writes Resources/AppIcon.png and Resources/AppIcon-windows.png

Needs Pillow (`pip install pillow`). The PNGs are committed, so building the apps doesn't need this.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SS = 4  # supersampling factor
ORANGE = (222, 132, 8)


def rounded_mask(size, box, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def lock_coverage(x, y):
    """Is the unit-space point (x, y) inside the padlock? (0,0) top-left, (1,1) bottom-right."""
    # Body: rounded rectangle.
    bx0, by0, bx1, by1, br = 0.0, 0.47, 1.0, 1.0, 0.08
    if bx0 <= x <= bx1 and by0 <= y <= by1:
        cx = min(max(x, bx0 + br), bx1 - br)
        cy = min(max(y, by0 + br), by1 - br)
        if (x - cx) ** 2 + (y - cy) ** 2 <= br * br:
            return True
    # Shackle: a thick arch whose legs run down into the body.
    cx, cy, outer, inner = 0.5, 0.34, 0.40, 0.19
    if y <= cy:
        d = math.hypot(x - cx, y - cy)
        return inner <= d <= outer
    if y <= by0 + 0.02:
        return (cx - outer <= x <= cx - inner) or (cx + inner <= x <= cx + outer)
    return False


def render(tile_inset, radius_ratio, shadow, out_path):
    size = 1024 * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inset = tile_inset * SS
    box = (inset, inset, size - inset, size - inset)
    tile = size - 2 * inset
    radius = int(tile * radius_ratio)

    if shadow:
        sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        sbox = (box[0], box[1] + 12 * SS, box[2], box[3] + 12 * SS)
        ImageDraw.Draw(sh).rounded_rectangle(sbox, radius=radius, fill=(0, 0, 0, 70))
        img = Image.alpha_composite(img, sh.filter(ImageFilter.GaussianBlur(26 * SS)))

    paper = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    img.paste(paper, (0, 0), rounded_mask(size, box, radius))
    draw = ImageDraw.Draw(img)
    # Hairline edge so the white tile reads on white backgrounds.
    draw.rounded_rectangle(box, radius=radius, outline=(0, 0, 0, 22), width=2 * SS)

    # Padlock area in pixels, centred on the tile.
    lock_w = tile * 0.46
    lock_h = tile * 0.55
    lx = size / 2 - lock_w / 2
    ly = size / 2 - lock_h / 2 - tile * 0.01

    cols = 31
    pitch = lock_w / cols
    rows = int(lock_h / pitch) + 1
    key_cx = lx + lock_w * 0.5
    key_cy = ly + lock_h * 0.735
    key_r = lock_w * 0.115
    halo = key_r + pitch * 1.1

    for r in range(rows):
        for c in range(cols):
            u = (c + 0.5) / cols
            v = (r + 0.5) * pitch / lock_h
            if v > 1 or not lock_coverage(u, v):
                continue
            px = lx + (c + 0.5) * pitch
            py = ly + (r + 0.5) * pitch
            if math.hypot(px - key_cx, py - key_cy) < halo:
                continue
            # Ink fades from the top of the shackle to the bottom of the body, slightly darker on the left.
            ink = 1.0 - 0.85 * v - 0.15 * u
            ink = max(0.10, min(1.0, ink))
            side = pitch * (0.22 + 0.52 * math.sqrt(ink))
            shade = int(20 + (1 - ink) * 150)
            half = side / 2
            draw.rectangle((px - half, py - half, px + half, py + half), fill=(shade, shade, shade, 255))

    draw.ellipse((key_cx - key_r, key_cy - key_r, key_cx + key_r, key_cy + key_r), fill=ORANGE + (255,))

    img = img.resize((1024, 1024), Image.LANCZOS)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    print(f"wrote {out_path}")


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "Resources"
    # macOS: Big Sur icon grid (824pt tile inside 1024, with a soft drop shadow).
    render(100, 0.225, True, out / "AppIcon.png")
    # Windows: the tile fills the canvas, as taskbar and Start icons expect.
    render(24, 0.20, False, out / "AppIcon-windows.png")
