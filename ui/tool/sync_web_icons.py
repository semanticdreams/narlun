#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

from PIL import Image


SOURCE_ICON = Path(__file__).resolve().parents[1] / "assets" / "icon.png"
WEB_DIR = SOURCE_ICON.parents[1] / "web"
PNG_OUTPUTS = {
    WEB_DIR / "icons" / "Icon-192.png": (192, 192),
    WEB_DIR / "icons" / "Icon-512.png": (512, 512),
    WEB_DIR / "icons" / "Icon-maskable-192.png": (192, 192),
    WEB_DIR / "icons" / "Icon-maskable-512.png": (512, 512),
}
FAVICON_OUTPUT = WEB_DIR / "favicon.ico"
FAVICON_SIZES = [(16, 16), (32, 32), (48, 48)]


def main() -> int:
    if not SOURCE_ICON.is_file():
        print(f"Missing source icon: {SOURCE_ICON}", file=sys.stderr)
        return 1

    with Image.open(SOURCE_ICON) as source:
        if source.width != source.height:
            print(
                (
                    "Source icon must be square to generate web icons cleanly: "
                    f"{SOURCE_ICON} is {source.width}x{source.height}"
                ),
                file=sys.stderr,
            )
            return 1

        source = source.convert("RGBA")
        for output_path, size in PNG_OUTPUTS.items():
            output_path.parent.mkdir(parents=True, exist_ok=True)
            resized = source.resize(size, Image.Resampling.LANCZOS)
            resized.save(output_path, format="PNG")

        FAVICON_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        source.save(FAVICON_OUTPUT, format="ICO", sizes=FAVICON_SIZES)

    print(f"Synced web icons from {SOURCE_ICON}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
