"""
Creates enemy sprites by tinting existing LPC sheets.
- Goblin:        green hue shift on warrior sprite
- Goblin Archer: dark olive hue shift on archer sprite
- Hill Giant:    earthy grey-brown on warrior sprite (larger figure)
"""
import os, shutil
from PIL import Image, ImageEnhance, ImageFilter

BASE = os.path.join(os.path.dirname(__file__), "..")
SPRITE_BASE = os.path.join(BASE, "assets", "sprites", "generated")

def load_sheet(class_folder: str, variant: int = 0) -> Image.Image:
    path = os.path.join(SPRITE_BASE, class_folder, str(variant), "single.png")
    return Image.open(path).convert("RGBA")

def tint(img: Image.Image, r_mult: float, g_mult: float, b_mult: float) -> Image.Image:
    """Multiply each RGB channel by the given factors, keep alpha."""
    r, g, b, a = img.split()
    def scale(ch, m):
        return ch.point(lambda x: min(int(x * m), 255))
    return Image.merge("RGBA", (scale(r, r_mult), scale(g, g_mult), scale(b, b_mult), a))

def saturate(img: Image.Image, factor: float) -> Image.Image:
    rgb = img.convert("RGB")
    grey = rgb.convert("L").convert("RGB")
    blended = Image.blend(grey.convert("RGBA"), img, factor)
    return blended

def save_variants(img_base: Image.Image, folder: str,
                  tint_args: list, count: int = 3) -> None:
    for i in range(count):
        # Slightly vary brightness per variant so they look distinct
        bright = ImageEnhance.Brightness(img_base)
        variation = bright.enhance(0.88 + i * 0.08)
        out = tint(variation, *tint_args)
        dest_dir = os.path.join(SPRITE_BASE, folder, str(i))
        os.makedirs(dest_dir, exist_ok=True)
        out.save(os.path.join(dest_dir, "single.png"))
        print(f"  Saved {folder}/{i}/single.png")

# ── Goblin (warrior base, vivid green tint) ───────────────────────────────────
print("Generating Goblin sprites...")
warrior = load_sheet("warrior", 0)
save_variants(warrior, "goblin", [0.55, 1.25, 0.45])

# ── Goblin Archer (archer base, dark olive tint) ──────────────────────────────
print("Generating Goblin Archer sprites...")
archer = load_sheet("archer", 0)
save_variants(archer, "goblin_archer", [0.65, 0.90, 0.40])

# ── Hill Giant (warrior base, stone grey-brown, boosted contrast) ─────────────
print("Generating Hill Giant sprites...")
giant_base = load_sheet("warrior", 1)
# Desaturate slightly then push earthy tones
grey = ImageEnhance.Color(giant_base).enhance(0.45)   # mostly grey
giant = tint(grey, 0.88, 0.78, 0.60)                   # warm stone tint
# Boost contrast to look chunkier
giant = ImageEnhance.Contrast(giant).enhance(1.35)
# Save only 1 variant for the boss
dest = os.path.join(SPRITE_BASE, "hill_giant", "0")
os.makedirs(dest, exist_ok=True)
giant.save(os.path.join(dest, "single.png"))
print("  Saved hill_giant/0/single.png")

print("\nDone! Enemy sprites ready.")
