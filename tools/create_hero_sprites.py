"""
Custom pixel-art sprites for Shauna (ranged carry) and Nemi (support disruptor).
Placed at all 4 direction rows (8-11) matching LPCGeneratedAnimData, with walk bob.
Sheet size: 576 × 768 (9 frames × 12 rows × 64px).
"""
import os
from PIL import Image, ImageDraw

BASE = os.path.join(os.path.dirname(__file__), "..")
SPRITE_BASE = os.path.join(BASE, "assets", "sprites", "generated")
FRAME, WALK_ROW_GROUP, SHEET_W, SHEET_H = 64, 8, 576, 768

def new_sheet(): return Image.new("RGBA", (SHEET_W, SHEET_H), (0,0,0,0))
def circle(d,cx,cy,r,fill,outline=None,lw=1): d.ellipse([cx-r,cy-r,cx+r,cy+r],fill=fill,outline=outline,width=lw)
def poly(d,pts,fill,outline=None,lw=1): d.polygon(pts,fill=fill,outline=outline)

def place_all(sheet, sprite, frame_x):
    for direction in range(4):
        sheet.paste(sprite, (frame_x*FRAME, (WALK_ROW_GROUP+direction)*FRAME), sprite)

def save(sheet, folder, variant):
    dest = os.path.join(SPRITE_BASE, folder, str(variant))
    os.makedirs(dest, exist_ok=True)
    sheet.save(os.path.join(dest, "single.png"))
    print(f"  Saved {folder}/{variant}/single.png")

# ── SHAUNA (Ranged Carry) ──────────────────────────────────────────────────────
# Teal/cyan color scheme, slim build, holds a bow
SHAUNA_COLORS = [
    {"skin":(210,170,130),"hair":(60,30,100),"armor":(20,140,160),"dark":(10,90,110),"eye":(80,220,200)},
    {"skin":(195,155,115),"hair":(180,80,20), "armor":(15,110,140),"dark":(8,70,95), "eye":(60,200,180)},
    {"skin":(225,185,145),"hair":(40,100,160),"armor":(25,160,175),"dark":(12,105,125),"eye":(100,240,220)},
]

def draw_shauna(col, bob=0):
    img = Image.new("RGBA", (64,64), (0,0,0,0))
    d = ImageDraw.Draw(img)
    s,dk,ar,ey,hr = col["skin"],col["dark"],col["armor"],col["eye"],col["hair"]
    b = bob
    # Shadow
    d.ellipse([20,58,44,63], fill=(0,0,0,55))
    # Boots
    d.rectangle([24,50+b,29,60+b], fill=dk)
    d.rectangle([33,50+b,38,60+b], fill=dk)
    d.ellipse([22,57+b,31,63+b], fill=dk)
    d.ellipse([32,57+b,41,63+b], fill=dk)
    # Slim legs
    d.rectangle([25,42+b,29,52+b], fill=(ar[0]//2,ar[1]//2,ar[2]//2))
    d.rectangle([34,42+b,38,52+b], fill=(ar[0]//2,ar[1]//2,ar[2]//2))
    # Body — slim armour
    poly(d,[(22,42+b),(42,42+b),(44,30+b),(35,24+b),(29,24+b),(20,30+b)],fill=ar,outline=dk,lw=1)
    # Shoulder pauldron left
    poly(d,[(20,28+b),(14,33+b),(16,38+b),(20,36+b),(22,30+b)],fill=ar,outline=dk,lw=1)
    # Left arm holding bow
    poly(d,[(22,30+b),(14,38+b),(13,46+b),(17,47+b),(19,40+b),(24,32+b)],fill=s,outline=dk,lw=1)
    # Right arm pulling string
    poly(d,[(42,28+b),(50,32+b),(52,40+b),(48,42+b),(47,35+b),(40,30+b)],fill=s,outline=dk,lw=1)
    # Bow (vertical, left side)
    d.arc([6,22+b,18,52+b], start=270, end=90, fill=(140,90,40), width=3)
    # String
    d.line([(12,22+b),(50,36+b),(12,52+b)], fill=(220,210,180), width=1)
    # Arrow
    d.line([(12,38+b),(50,34+b)], fill=(160,120,60), width=2)
    poly(d,[(50,34+b),(53,31+b),(53,37+b)], fill=(200,200,200))
    # Head
    circle(d,32,17+b,13,s,dk)
    # Hair — short with bangs
    poly(d,[(19,12+b),(32,6+b),(45,12+b),(44,18+b),(32,10+b),(20,18+b)],fill=hr,outline=dk,lw=1)
    d.rectangle([19,12+b,23,20+b], fill=hr)  # side lock
    # Eyes — sharp, determined
    d.ellipse([24,15+b,31,20+b], fill=(40,30,30))
    d.ellipse([33,15+b,40,20+b], fill=(40,30,30))
    circle(d,27,17+b,3,ey)
    circle(d,36,17+b,3,ey)
    d.point([(26,16+b),(35,16+b)], fill=(255,255,255,220))
    # Nose & lips
    d.point([(31,21+b),(33,21+b)], fill=dk)
    d.line([(29,24+b),(35,24+b)], fill=(180,100,90), width=1)
    # Energy glow on bow hand
    circle(d,15,42+b,4,(ey[0],ey[1],ey[2],120))
    return img

def make_shauna_sheet(col_idx):
    col = SHAUNA_COLORS[col_idx]
    sheet = new_sheet()
    bobs = [0,-1,-2,-1,0,1,2,1,0]
    for i,bob in enumerate(bobs): place_all(sheet, draw_shauna(col,bob), i)
    return sheet

# ── NEMI (Support Disruptor) ────────────────────────────────────────────────────
# Orange/amber mystic, flowing robes, water orb staff
NEMI_COLORS = [
    {"skin":(220,175,135),"robe":(190,90,10),"dark":(120,55,5),"orb":(80,180,255),"hair":(30,20,80),"eye":(50,160,255)},
    {"skin":(205,160,120),"robe":(170,75,8), "dark":(105,45,4),"orb":(60,160,240),"hair":(80,50,10),"eye":(40,145,240)},
    {"skin":(235,190,150),"robe":(210,105,15),"dark":(135,65,7),"orb":(100,200,255),"hair":(20,15,60),"eye":(70,180,255)},
]

def draw_nemi(col, bob=0):
    img = Image.new("RGBA", (64,64), (0,0,0,0))
    d = ImageDraw.Draw(img)
    s,ro,dk,orb,hr,ey = col["skin"],col["robe"],col["dark"],col["orb"],col["hair"],col["eye"]
    b = bob
    # Shadow
    d.ellipse([18,58,46,63], fill=(0,0,0,55))
    # Robe — wide flowing base
    poly(d,[(16,62+b),(48,62+b),(50,40+b),(44,26+b),(20,26+b),(14,40+b)],fill=ro,outline=dk,lw=1)
    # Robe hem details
    d.line([(18,55+b),(46,55+b)], fill=dk, width=1)
    d.line([(16,48+b),(48,48+b)], fill=(ro[0]+20,ro[1]+10,ro[2]+5,120), width=1)
    # Inner robe lighter strip
    poly(d,[(30,62+b),(34,62+b),(36,40+b),(32,35+b),(28,40+b)],fill=(min(ro[0]+40,255),min(ro[1]+25,255),ro[2]+10))
    # Left arm extended with staff
    poly(d,[(20,28+b),(10,38+b),(8,46+b),(12,48+b),(14,40+b),(22,30+b)],fill=s,outline=dk,lw=1)
    # Staff
    d.line([(8,16+b),(10,52+b)], fill=(130,80,30), width=3)
    # Orb on staff top
    circle(d,8,12+b,8,(orb[0],orb[1],orb[2],180),outline=(min(orb[0]+40,255),min(orb[1]+40,255),255),lw=1)
    # Inner orb glow
    circle(d,8,12+b,4,(255,255,255,200))
    # Orb wave lines
    d.arc([2,8+b,14,18+b], start=200, end=340, fill=(200,230,255,180), width=1)
    # Right arm
    poly(d,[(44,28+b),(52,36+b),(52,44+b),(48,44+b),(48,38+b),(42,30+b)],fill=s,outline=dk,lw=1)
    # Head
    circle(d,32,17+b,13,s,dk)
    # Hair — long flowing, mystical
    poly(d,[(19,10+b),(32,4+b),(45,10+b),(48,22+b),(44,26+b),(20,26+b),(16,22+b)],fill=hr,outline=dk,lw=1)
    # Hair strands
    poly(d,[(44,18+b),(50,28+b),(46,30+b),(42,22+b)],fill=hr)
    poly(d,[(20,18+b),(14,30+b),(18,31+b),(22,22+b)],fill=hr)
    # Eyes — wide, magical
    d.ellipse([23,15+b,31,21+b], fill=(30,25,45))
    d.ellipse([33,15+b,41,21+b], fill=(30,25,45))
    circle(d,27,18+b,4,ey)
    circle(d,37,18+b,4,ey)
    circle(d,27,18+b,2,(255,255,255,180))
    circle(d,37,18+b,2,(255,255,255,180))
    # Nose & gentle smile
    d.point([(31,22+b),(33,22+b)], fill=dk)
    d.arc([27,23+b,37,28+b], start=0, end=180, fill=(200,120,100), width=1)
    # Ambient orb glow around staff tip
    d.ellipse([1,6+b,16,22+b], outline=(orb[0],orb[1],orb[2],80), width=1)
    return img

def make_nemi_sheet(col_idx):
    col = NEMI_COLORS[col_idx]
    sheet = new_sheet()
    bobs = [0,-1,-1,0,0,1,1,0,0]  # gentle float
    for i,bob in enumerate(bobs): place_all(sheet, draw_nemi(col,bob), i)
    return sheet

# ── Generate ───────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("Generating Shauna sprites...")
    for v in range(3): save(make_shauna_sheet(v), "shauna", v)
    print("Generating Nemi sprites...")
    for v in range(3): save(make_nemi_sheet(v), "nemi", v)
    print("\nDone!")
