"""Builds the app icon, the logo image and the color sets in the asset catalog.

The source logo is a light-blue rounded square ("plate") on a white canvas. iOS draws its own
rounded corners, so the icon has to be a full-bleed square: this crops the largest square that
stays inside the plate's corners and scales it to 1024 x 1024 without alpha.

Usage: python -I scripts/make-app-icon.py <logo.png> <path/to/Assets.xcassets>
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

WHITE_THRESHOLD = 236  # a pixel whose darkest channel is below this is part of the plate
CORNER_MARGIN = 6  # extra pixels kept away from the rounded corners
ICON_SIZE = 1024
LOGO_SIZE = 512

CATALOG_INFO = {"author": "xcode", "version": 1}

# (light, dark) as 0xRRGGBB, matching Theme.accent and Theme.background.
COLOR_SETS = {
    "AccentColor": (0x4F86D0, 0x8DB8EA),
    "LaunchBackground": (0xF6F8FC, 0x0F141B),
}


def plate_box(ink):
    rows = np.flatnonzero(ink.any(axis=1))
    cols = np.flatnonzero(ink.any(axis=0))
    if rows.size == 0 or cols.size == 0:
        raise SystemExit("No logo found: the image is entirely white.")
    return int(cols[0]), int(rows[0]), int(cols[-1]), int(rows[-1])


def corner_inset(ink, box):
    """How far along each diagonal the plate starts, for the worst of the four corners."""
    left, top, right, bottom = box
    corners = [(left, top, 1, 1), (right, top, -1, 1), (left, bottom, 1, -1), (right, bottom, -1, -1)]
    worst = 0
    for x0, y0, dx, dy in corners:
        for step in range(min(right - left, bottom - top) // 2):
            x, y = x0 + dx * step, y0 + dy * step
            if ink[y - 3:y + 4, x - 3:x + 4].all():
                worst = max(worst, step)
                break
        else:
            raise SystemExit("Could not find the inside of the plate near a corner.")
    return worst


def color_set(light, dark):
    def entry(value, dark_mode):
        item = {
            "color": {
                "color-space": "srgb",
                "components": {
                    "alpha": "1.000",
                    "blue": f"0x{value & 0xFF:02X}",
                    "green": f"0x{(value >> 8) & 0xFF:02X}",
                    "red": f"0x{(value >> 16) & 0xFF:02X}",
                },
            },
            "idiom": "universal",
        }
        if dark_mode:
            item["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
        return item

    return {"colors": [entry(light, False), entry(dark, True)], "info": CATALOG_INFO}


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    source = Path(sys.argv[1])
    catalog = Path(sys.argv[2])

    image = Image.open(source).convert("RGB")
    pixels = np.asarray(image).astype(int)
    ink = pixels.min(axis=2) < WHITE_THRESHOLD
    box = plate_box(ink)
    left, top, right, bottom = box
    inset = corner_inset(ink, box) + CORNER_MARGIN
    side = min(right - left, bottom - top) + 1 - 2 * inset
    center_x = (left + right + 1) / 2
    center_y = (top + bottom + 1) / 2
    crop = (
        round(center_x - side / 2),
        round(center_y - side / 2),
        round(center_x - side / 2) + side,
        round(center_y - side / 2) + side,
    )
    for x, y in [(crop[0], crop[1]), (crop[2] - 1, crop[1]), (crop[0], crop[3] - 1), (crop[2] - 1, crop[3] - 1)]:
        if not ink[y, x]:
            raise SystemExit(f"Crop corner ({x}, {y}) falls outside the plate.")

    icon = image.crop(crop).resize((ICON_SIZE, ICON_SIZE), Image.Resampling.LANCZOS)
    icon_dir = catalog / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    icon.save(icon_dir / "AppIcon-1024.png", optimize=True)
    write_json(icon_dir / "Contents.json", {
        "images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": CATALOG_INFO,
    })

    logo_dir = catalog / "NookLogo.imageset"
    logo_dir.mkdir(parents=True, exist_ok=True)
    icon.resize((LOGO_SIZE, LOGO_SIZE), Image.Resampling.LANCZOS).save(logo_dir / "NookLogo.png", optimize=True)
    write_json(logo_dir / "Contents.json", {
        "images": [{"filename": "NookLogo.png", "idiom": "universal"}],
        "info": CATALOG_INFO,
    })

    for name, (light, dark) in COLOR_SETS.items():
        write_json(catalog / f"{name}.colorset" / "Contents.json", color_set(light, dark))
    write_json(catalog / "Contents.json", {"info": CATALOG_INFO})

    print(f"plate {box}, corner inset {inset}px, crop {crop} ({side}px) -> {ICON_SIZE}px icon")


if __name__ == "__main__":
    main()
