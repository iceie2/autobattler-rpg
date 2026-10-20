"""Local, deterministic elemental stone palettes for the existing shared giant.
No geometry or original texture is overwritten; brown leather/rope is retained.
"""
from pathlib import Path
import numpy as np
from PIL import Image

root = Path(__file__).resolve().parents[2]
out = root / 'assets/3d pipeline/enemy/hill_giant'
a = np.asarray(Image.open(out / 'hill_giant_v002_Image_0.png').convert('RGB')).astype(float) / 255
r, g, b = a.transpose(2, 0, 1)
# Stone is low-chroma, leather and rope warm brown. Feather that boundary.
mask = np.clip(1 - np.maximum(r-b, 0) / .12, 0, 1)
lum = a @ np.array([.2126, .7152, .0722])
palettes = {'normal': (.70,.68,.64), 'fire': (.92,.40,.20),
            'water': (.30,.68,.86), 'earth': None,
            'air': (.64,.86,.74), 'lightning': (.65,.46,.90)}
for name, rgb in palettes.items():
    result = a if rgb is None else a*(1-mask[:,:,None]) + lum[:,:,None]*np.array(rgb)/.65*mask[:,:,None]
    Image.fromarray((np.clip(result,0,1)*255).astype('uint8')).save(out / f'giant_{name}_albedo.png')
print('Six shared-giant palettes written; original Earth texture and GLB preserved.')
