"""
Splits the combined LPC spritesheet (archer_0000.png) into individual
per-animation PNG files, placing them in the Ranger/standard/ folder
to match the Warrior sprite folder structure.

Standard LPC combined sheet layout (64x64 frames, 13 cols x 21 rows):
  spellcast : rows  0-3  (4 directions: N W S E, 7 frames each)
  thrust    : rows  4-7  (4 directions, 8 frames each)
  walk      : rows  8-11 (4 directions, 9 frames each)
  slash     : rows 12-15 (4 directions, 6 frames each)
  shoot     : rows 16-19 (4 directions, 13 frames each)
  hurt      : row  20    (south only,   6 frames)

Run from the autobattler-rpg project root:
  python tools/split_ranger_sprites.py
"""

from pathlib import Path
from PIL import Image

FRAME_SIZE = 64
COMBINED_SHEET = Path("assets/sprites/lpc_male_animations_2026-01-10T02-53-57/archer_0000.png")
OUTPUT_DIR = Path("assets/sprites/lpc_male_animations_2026-01-10T02-53-57/Ranger/standard")

# (animation_name, start_row, end_row_exclusive)
ANIMATIONS = [
    ("spellcast",  0,  4),
    ("thrust",     4,  8),
    ("walk",       8, 12),
    ("slash",     12, 16),
    ("shoot",     16, 20),
    ("hurt",      20, 21),
]

def split_sprites():
    if not COMBINED_SHEET.exists():
        print(f"ERROR: Combined sheet not found: {COMBINED_SHEET}")
        return

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(COMBINED_SHEET).convert("RGBA")
    sheet_w, sheet_h = sheet.size
    print(f"Loaded sheet: {sheet_w}x{sheet_h}")

    for anim_name, row_start, row_end in ANIMATIONS:
        y0 = row_start * FRAME_SIZE
        y1 = row_end   * FRAME_SIZE
        crop = sheet.crop((0, y0, sheet_w, y1))
        out_path = OUTPUT_DIR / f"{anim_name}.png"
        crop.save(out_path)
        rows = row_end - row_start
        print(f"  Saved {anim_name}.png  ({sheet_w}x{rows * FRAME_SIZE}  rows {row_start}-{row_end - 1})")

    # The system also looks for idle.png — use the walk sheet as a stand-in
    walk_path = OUTPUT_DIR / "walk.png"
    idle_path = OUTPUT_DIR / "idle.png"
    if walk_path.exists() and not idle_path.exists():
        Image.open(walk_path).save(idle_path)
        print("  Saved idle.png  (copy of walk)")

    # run.png stand-in
    run_path = OUTPUT_DIR / "run.png"
    if walk_path.exists() and not run_path.exists():
        Image.open(walk_path).save(run_path)
        print("  Saved run.png  (copy of walk)")

    print(f"\nDone! Files written to: {OUTPUT_DIR}")
    print("Move the Ranger folder into Godot and re-import if needed.")

if __name__ == "__main__":
    split_sprites()
