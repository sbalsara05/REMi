#!/usr/bin/env python3
"""Normalize MagicPointer LLM logos to white silhouettes on transparent (template-friendly)."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageOps

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "UI" / "Resources"
NAMES = ("llm-claude", "llm-chatgpt", "llm-gemini")
SIZE = 64


def to_monochrome(src: Path) -> None:
    img = Image.open(src).convert("RGBA")
    gray = ImageOps.grayscale(img)
    # Dark glyph on light bg, or light glyph on dark bg — keep high-contrast shape.
    mean = sum(gray.getdata()) / max(1, gray.width * gray.height)
    if mean > 128:
        gray = ImageOps.invert(gray)
    mask = gray.point(lambda p: 255 if p < 210 else 0)
    white = Image.new("RGBA", img.size, (255, 255, 255, 255))
    white.putalpha(mask)
    out = ImageOps.contain(white, (SIZE, SIZE), method=Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ox = (SIZE - out.width) // 2
    oy = (SIZE - out.height) // 2
    canvas.paste(out, (ox, oy), out)
    canvas.save(src, optimize=True)
    print(f"wrote {src}")


def main() -> None:
    for name in NAMES:
        path = RES / f"{name}.png"
        if not path.exists():
            raise SystemExit(f"missing {path}")
        to_monochrome(path)


if __name__ == "__main__":
    main()
