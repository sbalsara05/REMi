#!/usr/bin/env python3
"""Label Foozle mouse spritesheet frames and regenerate mouseSpriteFrameCatalog.ts."""
from __future__ import annotations

import json
import os
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "librechat/client/public/assets/mouse-spritesheet.png"
OUT_TS = ROOT / "librechat/client/src/components/Icons/mouseSpriteFrameCatalog.ts"
OUT_ATLAS = ROOT / "librechat/client/public/assets/mouse-sprite-frame-guide.png"

FW, FH = 64, 48
ROW_NAMES = [
    "idle_lunge",
    "run",
    "jump",
    "double_jump",
    "light_dash",
    "edge_grab",
    "wall_slide",
    "light_attack_1",
    "light_attack_2",
    "light_attack_3",
    "heavy_attack",
    "hurt",
    "death",
]
ROW_LABELS = {
    0: ["lunge_0", "lunge_1", "lunge_2", "lunge_3", "lunge_4", "lunge_5", "lunge_6"],
    1: ["run_0", "run_1", "run_2", "run_3", "run_4", "run_5", "run_6", "run_7"],
    2: ["jump_0", "jump_1", "jump_2", "jump_3", "jump_4", "jump_5"],
    3: [
        "dj_stand",
        "dj_stride",
        "dj_roll_1",
        "dj_roll_2",
        "dj_roll_3",
        "dj_stand_2",
        "dj_stand_3",
        "dj_stand_low",
    ],
    4: ["dash_idle", "dash_1", "dash_2", "dash_3"],
    5: ["edge_0", "edge_1", "edge_2", "edge_3", "edge_4"],
    6: ["wall_0", "wall_1", "wall_2", "wall_3"],
}


def main() -> None:
    main_img = Image.open(MAIN).convert("RGBA")
    catalog: list[dict] = []
    cell_display = 80
    row_strips: list[Image.Image] = []

    for row in range(13):
        frames = []
        for col in range(15):
            cell = main_img.crop((col * FW, row * FH, (col + 1) * FW, (row + 1) * FH))
            bb = cell.getbbox()
            if not bb:
                break
            label = (
                ROW_LABELS[row][col]
                if row in ROW_LABELS and col < len(ROW_LABELS[row])
                else f"r{row}c{col}"
            )
            vp = {"w": bb[2] - bb[0], "h": bb[3] - bb[1], "ox": bb[0], "oy": bb[1]}
            frames.append({"col": col, "label": label, "viewport": vp})
        catalog.append({"row": row, "frameCount": len(frames), "frames": frames})

        strip = Image.new("RGBA", (len(frames) * cell_display, cell_display + 18), (40, 40, 40, 255))
        from PIL import ImageDraw

        draw = ImageDraw.Draw(strip)
        for i, fr in enumerate(frames):
            cell = main_img.crop(
                (fr["col"] * FW, row * FH, (fr["col"] + 1) * FW, (row + 1) * FH)
            )
            strip.paste(cell.resize((cell_display, cell_display), Image.NEAREST), (i * cell_display, 0))
            draw.text((i * cell_display + 2, cell_display + 2), f"{fr['col']}:{fr['label'][:10]}", fill=(255, 255, 0))
        row_strips.append(strip)

    atlas_h = sum(s.height for s in row_strips)
    atlas = Image.new("RGBA", (max(s.width for s in row_strips), atlas_h), (30, 30, 30, 255))
    y = 0
    for s in row_strips:
        atlas.paste(s, (0, y))
        y += s.height
    OUT_ATLAS.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT_ATLAS)

    lines = [
        "/** Auto-labeled Foozle mouse sheet frames (64×48 cells). Regenerate via scripts/label-mouse-spritesheet.py */",
        "",
        "export type FrameViewport = {",
        "  w: number;",
        "  h: number;",
        "  ox: number;",
        "  oy: number;",
        "};",
        "",
        "export type SheetFrameLabel = {",
        "  row: number;",
        "  col: number;",
        "  rowName: string;",
        "  label: string;",
        "  viewport: FrameViewport;",
        "};",
        "",
        f"export const MOUSE_SHEET_ROW_NAMES = {json.dumps(ROW_NAMES)} as const;",
        "",
        "export const MOUSE_SHEET_FRAMES: SheetFrameLabel[] = [",
    ]
    for row in catalog:
        rn = ROW_NAMES[row["row"]]
        for fr in row["frames"]:
            vp = fr["viewport"]
            lines.append(
                f"  {{ row: {row['row']}, col: {fr['col']}, rowName: '{rn}', label: '{fr['label']}', "
                f"viewport: {{ w: {vp['w']}, h: {vp['h']}, ox: {vp['ox']}, oy: {vp['oy']} }} }},"
            )
    lines += [
        "];",
        "",
        "export function getSheetFrame(row: number, col: number): SheetFrameLabel | undefined {",
        "  return MOUSE_SHEET_FRAMES.find((f) => f.row === row && f.col === col);",
        "}",
        "",
        "export function getSheetRowFrames(row: number): SheetFrameLabel[] {",
        "  return MOUSE_SHEET_FRAMES.filter((f) => f.row === row);",
        "}",
        "",
    ]
    OUT_TS.write_text("\n".join(lines))
    print(f"Wrote {OUT_TS} ({len(catalog)} rows)")
    print(f"Wrote {OUT_ATLAS}")


if __name__ == "__main__":
    main()
