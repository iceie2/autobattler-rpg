"""
Generates actual monster pixel-art sprites for goblin, goblin_archer, and hill_giant.

LPC walk/idle row group = 8  (animation_rows["walk"] = 8)
  Row 8  = north  y = 8*64  = 512
  Row 9  = west   y = 9*64  = 576
  Row 10 = south  y = 10*64 = 640
  Row 11 = east   y = 11*64 = 704

We fill ALL 4 direction rows with the same sprite so the unit stays
visible regardless of which way it walks.  Sheet height = 12*64 = 768.
"""

import os
from PIL import Image, ImageDraw

BASE = os.path.join(os.path.dirname(__file__), "..")
SPRITE_BASE = os.path.join(BASE, "assets", "sprites", "generated")

SHEET_W, SHEET_H = 576, 768   # 9*64 wide, 12*64 tall (covers rows 0-11)
FRAME = 64
WALK_ROW_GROUP = 8  # matches LPCGeneratedAnimData.animation_rows["walk"]

# ─── helpers ──────────────────────────────────────────────────────────────────

def new_sheet() -> Image.Image:
    return Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))

def place_all_directions(sheet: Image.Image, sprite: Image.Image, frame_x: int) -> None:
    """
    Paste the sprite into ALL 4 direction rows (north/west/south/east) at frame_x.
    This ensures the monster stays visible regardless of which way it faces.
    Directions: north=0, west=1, south=2, east=3  →  rows 8,9,10,11
    """
    for direction in range(4):
        row = WALK_ROW_GROUP + direction
        x = frame_x * FRAME
        y = row * FRAME
        sheet.paste(sprite, (x, y), sprite)

def circle(draw: ImageDraw.ImageDraw, cx: int, cy: int, r: int, fill, outline=None, lw: int = 2):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=outline, width=lw)

def poly(draw: ImageDraw.ImageDraw, pts: list, fill, outline=None, lw: int = 1):
    draw.polygon(pts, fill=fill, outline=outline)

def save(sheet: Image.Image, folder: str, variant: int) -> None:
    dest = os.path.join(SPRITE_BASE, folder, str(variant))
    os.makedirs(dest, exist_ok=True)
    path = os.path.join(dest, "single.png")
    sheet.save(path)
    print(f"  Saved {folder}/{variant}/single.png")


# ─── Goblin ───────────────────────────────────────────────────────────────────
#  Small hunched green creature, big eyes, fang, stubby limbs, bone club

GOBLIN_COLORS = [
    {"skin": (58, 140, 50), "dark": (30, 90, 30), "eye": (240, 220, 30), "pupil": (10,10,10)},
    {"skin": (45, 120, 40), "dark": (25, 75, 25), "eye": (255, 80, 30),  "pupil": (10,10,10)},
    {"skin": (80, 160, 65), "dark": (45, 105, 40), "eye": (200, 240, 50), "pupil": (10,10,10)},
]

def draw_goblin(col: dict, bob: int = 0) -> Image.Image:
    """Draw a goblin at a slight vertical bob offset for walk animation."""
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s, dk, ey, pu = col["skin"], col["dark"], col["eye"], col["pupil"]

    b = bob  # vertical offset for animation

    # Shadow
    d.ellipse([18, 57, 46, 63], fill=(0, 0, 0, 60))

    # Legs
    d.rectangle([24, 44+b, 29, 55+b], fill=dk)
    d.rectangle([34, 44+b, 39, 55+b], fill=dk)
    # Feet
    d.ellipse([22, 53+b, 31, 58+b], fill=dk)
    d.ellipse([33, 53+b, 42, 58+b], fill=dk)

    # Body — hunched pear shape
    poly(d, [(20, 42+b), (44, 42+b), (46, 30+b), (34, 22+b), (30, 22+b), (18, 30+b)],
         fill=s, outline=dk, lw=1)

    # Left arm + club
    poly(d, [(20, 28+b), (13, 38+b), (11, 44+b), (15, 45+b), (18, 37+b), (22, 30+b)],
         fill=s, outline=dk, lw=1)
    # Club head
    poly(d, [(8, 40+b), (16, 44+b), (18, 52+b), (10, 50+b)],
         fill=(200, 190, 175), outline=(120, 110, 100), lw=1)

    # Right arm — dangling
    poly(d, [(44, 28+b), (51, 35+b), (50, 42+b), (46, 41+b), (47, 33+b), (42, 30+b)],
         fill=s, outline=dk, lw=1)

    # Head
    circle(d, 32, 18+b, 14, fill=s, outline=dk)

    # Ears
    poly(d, [(18, 14+b), (14, 6+b), (20, 11+b)], fill=s, outline=dk, lw=1)
    poly(d, [(46, 14+b), (50, 6+b), (44, 11+b)], fill=s, outline=dk, lw=1)

    # Eyes
    circle(d, 26, 16+b, 5, fill=ey, outline=(0, 0, 0))
    circle(d, 38, 16+b, 5, fill=ey, outline=(0, 0, 0))
    # Pupils
    circle(d, 27, 17+b, 2, fill=pu)
    circle(d, 39, 17+b, 2, fill=pu)
    # Eye shine
    circle(d, 25, 15+b, 1, fill=(255, 255, 255, 200))
    circle(d, 37, 15+b, 1, fill=(255, 255, 255, 200))

    # Nose
    d.ellipse([30, 21+b, 34, 24+b], fill=dk)

    # Fangs
    poly(d, [(29, 26+b), (27, 31+b), (31, 30+b)], fill=(240, 240, 220))
    poly(d, [(35, 26+b), (37, 31+b), (33, 30+b)], fill=(240, 240, 220))

    return img

def make_goblin_sheet(col_idx: int) -> Image.Image:
    col = GOBLIN_COLORS[col_idx]
    sheet = new_sheet()
    bobs = [0, -1, -2, -1, 0, 1, 2, 1, 0]
    for i, bob in enumerate(bobs):
        place_all_directions(sheet, draw_goblin(col, bob), i)
    return sheet


# ─── Goblin Archer ────────────────────────────────────────────────────────────
#  Like goblin but darker olive, no club — carries a bow, quiver on back

ARCHER_COLORS = [
    {"skin": (70, 110, 40), "dark": (40, 70, 25), "leather": (110, 75, 35),
     "bow": (140, 90, 40), "eye": (255, 160, 20), "pupil": (10,10,10)},
    {"skin": (55, 95, 35),  "dark": (30, 60, 20), "leather": (95, 65, 30),
     "bow": (120, 80, 35),  "eye": (220, 100, 20), "pupil": (10,10,10)},
    {"skin": (85, 130, 50), "dark": (50, 85, 30), "leather": (125, 85, 42),
     "bow": (155, 100, 48), "eye": (200, 220, 30), "pupil": (10,10,10)},
]

def draw_goblin_archer(col: dict, bob: int = 0) -> Image.Image:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s, dk, lth, bw, ey, pu = col["skin"], col["dark"], col["leather"], col["bow"], col["eye"], col["pupil"]

    b = bob

    # Shadow
    d.ellipse([18, 57, 46, 63], fill=(0, 0, 0, 60))

    # Legs
    d.rectangle([24, 44+b, 29, 55+b], fill=dk)
    d.rectangle([34, 44+b, 39, 55+b], fill=dk)
    d.ellipse([22, 53+b, 31, 58+b], fill=dk)
    d.ellipse([33, 53+b, 42, 58+b], fill=dk)

    # Leather tunic body
    poly(d, [(20, 42+b), (44, 42+b), (46, 30+b), (34, 22+b), (30, 22+b), (18, 30+b)],
         fill=lth, outline=dk, lw=1)

    # Quiver on back (right side)
    d.rectangle([44, 22+b, 50, 38+b], fill=(130, 90, 45), outline=dk)
    for i in range(3):
        d.line([(45+i, 22+b), (45+i, 18+b)], fill=(180, 140, 60), width=1)

    # Right arm drawing bow
    poly(d, [(44, 28+b), (52, 32+b), (54, 40+b), (50, 41+b), (49, 34+b), (42, 30+b)],
         fill=s, outline=dk, lw=1)

    # Left arm pulling string
    poly(d, [(20, 28+b), (10, 35+b), (9, 42+b), (13, 43+b), (15, 36+b), (22, 30+b)],
         fill=s, outline=dk, lw=1)

    # Bow
    d.arc([52, 26+b, 62, 46+b], start=270, end=90, fill=bw, width=3)
    # Bow string
    d.line([(57, 26+b), (10, 37+b), (57, 46+b)], fill=(200, 200, 180), width=1)
    # Arrow
    d.line([(10, 37+b), (52, 32+b)], fill=(160, 120, 60), width=2)
    poly(d, [(52, 32+b), (55, 29+b), (55, 35+b)], fill=(180, 180, 180))

    # Head
    circle(d, 32, 18+b, 13, fill=s, outline=dk)

    # Hood
    poly(d, [(20, 14+b), (32, 4+b), (44, 14+b), (42, 18+b), (22, 18+b)],
         fill=lth, outline=dk, lw=1)

    # Ears
    poly(d, [(19, 15+b), (15, 7+b), (22, 12+b)], fill=s, outline=dk, lw=1)
    poly(d, [(45, 15+b), (49, 7+b), (42, 12+b)], fill=s, outline=dk, lw=1)

    # Eyes
    circle(d, 26, 17+b, 5, fill=ey, outline=(0,0,0))
    circle(d, 38, 17+b, 5, fill=ey, outline=(0,0,0))
    circle(d, 27, 18+b, 2, fill=pu)
    circle(d, 39, 18+b, 2, fill=pu)
    circle(d, 25, 16+b, 1, fill=(255,255,255,200))
    circle(d, 37, 16+b, 1, fill=(255,255,255,200))

    d.ellipse([30, 21+b, 34, 24+b], fill=dk)
    poly(d, [(30, 26+b), (28, 30+b), (32, 29+b)], fill=(240,240,220))
    poly(d, [(34, 26+b), (36, 30+b), (32, 29+b)], fill=(240,240,220))

    return img

def make_goblin_archer_sheet(col_idx: int) -> Image.Image:
    col = ARCHER_COLORS[col_idx]
    sheet = new_sheet()
    bobs = [0, -1, -2, -1, 0, 1, 2, 1, 0]
    for i, bob in enumerate(bobs):
        place_all_directions(sheet, draw_goblin_archer(col, bob), i)
    return sheet


# ─── Hill Giant ───────────────────────────────────────────────────────────────
#  Massive stone-grey brute filling a 64×64 frame (displayed 2x in game)

def draw_hill_giant(bob: int = 0) -> Image.Image:
    # Cyclops brute — one huge eye, fleshy olive skin, tusks, big fists.
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    b = bob
    skin    = (150, 138, 96)    # olive-tan brute skin
    skin_dk = (104, 94, 62)     # shading / outline
    skin_lt = (182, 168, 120)   # highlight
    sclera  = (236, 232, 216)
    iris    = (220, 150, 35)    # amber
    pupil   = (18, 14, 10)
    tooth   = (240, 236, 218)
    hair    = (58, 44, 30)
    loin    = (96, 70, 45)

    # Ground shadow
    d.ellipse([8, 58, 56, 64], fill=(0, 0, 0, 70))

    # Legs — stout
    poly(d, [(16, 48+b), (27, 48+b), (26, 62+b), (15, 62+b)], fill=skin_dk)
    poly(d, [(37, 48+b), (48, 48+b), (49, 62+b), (38, 62+b)], fill=skin_dk)
    # Feet
    d.ellipse([12, 58+b, 28, 64+b], fill=skin)
    d.ellipse([36, 58+b, 52, 64+b], fill=skin)
    # Loincloth
    poly(d, [(20, 43+b), (44, 43+b), (46, 52+b), (18, 52+b)], fill=loin, outline=(60, 44, 28))

    # Torso — broad, pot-bellied brute
    poly(d, [(10, 28+b), (54, 28+b), (56, 44+b), (50, 50+b), (14, 50+b), (8, 44+b)],
         fill=skin, outline=skin_dk, lw=1)
    d.ellipse([22, 34+b, 42, 48+b], fill=skin_lt)   # belly highlight
    d.line([(32, 30+b), (32, 38+b)], fill=skin_dk, width=1)

    # Left arm — big, hanging, fist
    poly(d, [(10, 28+b), (2, 36+b), (1, 48+b), (9, 50+b), (12, 40+b), (14, 30+b)],
         fill=skin, outline=skin_dk, lw=1)
    circle(d, 5, 50+b, 6, fill=skin_lt, outline=skin_dk)
    # Right arm — big, hanging, fist
    poly(d, [(54, 28+b), (62, 36+b), (63, 48+b), (55, 50+b), (52, 40+b), (50, 30+b)],
         fill=skin, outline=skin_dk, lw=1)
    circle(d, 59, 50+b, 6, fill=skin_lt, outline=skin_dk)

    # Short thick neck
    d.rectangle([26, 24+b, 38, 30+b], fill=skin_dk)

    # Head — large, low-set
    poly(d, [(14, 12+b), (18, 4+b), (32, 1+b), (46, 4+b), (50, 12+b),
             (50, 22+b), (44, 28+b), (20, 28+b), (14, 22+b)],
         fill=skin, outline=skin_dk, lw=1)
    # Ear nubs
    d.ellipse([11, 15+b, 17, 22+b], fill=skin, outline=skin_dk)
    d.ellipse([47, 15+b, 53, 22+b], fill=skin, outline=skin_dk)
    # Hair tuft
    poly(d, [(27, 3+b), (32, -2+b), (37, 3+b), (34, 4+b), (32, 1+b), (30, 4+b)], fill=hair)
    d.line([(24, 5+b), (22, 2+b)], fill=hair, width=2)
    d.line([(40, 5+b), (42, 2+b)], fill=hair, width=2)

    # Heavy brow ridge
    poly(d, [(18, 10+b), (46, 10+b), (44, 15+b), (20, 15+b)], fill=skin_dk)
    # Angry furrow
    d.line([(20, 9+b), (28, 13+b)], fill=skin_dk, width=2)
    d.line([(44, 9+b), (36, 13+b)], fill=skin_dk, width=2)

    # ── THE SINGLE BIG EYE ──
    circle(d, 32, 18+b, 9, fill=sclera, outline=skin_dk, lw=1)
    d.line([(24, 18+b), (28, 18+b)], fill=(200, 120, 110), width=1)   # bloodshot
    d.line([(36, 18+b), (40, 18+b)], fill=(200, 120, 110), width=1)
    circle(d, 32, 19+b, 5, fill=iris)
    circle(d, 32, 19+b, 2, fill=pupil)
    d.ellipse([29, 15+b, 32, 18+b], fill=(255, 255, 255, 210))        # glint

    # Nose bump under the eye
    poly(d, [(30, 24+b), (34, 24+b), (33, 27+b), (31, 27+b)], fill=skin_dk)

    # Wide grimace + upward tusks
    d.line([(22, 27+b), (42, 27+b)], fill=(50, 30, 25), width=2)
    poly(d, [(25, 28+b), (23, 22+b), (28, 27+b)], fill=tooth)
    poly(d, [(39, 28+b), (41, 22+b), (36, 27+b)], fill=tooth)

    return img

def make_hill_giant_sheet() -> Image.Image:
    sheet = new_sheet()
    bobs = [0, 0, -1, 0, 0, 0, -1, 0, 0]
    for i, bob in enumerate(bobs):
        place_all_directions(sheet, draw_hill_giant(bob), i)
    return sheet


# ─── Generate ─────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("Generating Goblin sprites...")
    for v in range(3):
        save(make_goblin_sheet(v), "goblin", v)

    print("Generating Goblin Archer sprites...")
    for v in range(3):
        save(make_goblin_archer_sheet(v), "goblin_archer", v)

    print("Generating Hill Giant sprite...")
    save(make_hill_giant_sheet(), "hill_giant", 0)

    print("\nDone! Custom monster sprites ready.")
