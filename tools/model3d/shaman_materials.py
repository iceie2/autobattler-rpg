"""Build masked elemental skin palettes; preserve the shared Goblin's leather."""
from pathlib import Path
import numpy as np
from PIL import Image
root=Path(__file__).resolve().parents[2]
out=root/'assets/3d pipeline/enemy/goblin_shaman'
im=Image.open(root/'assets/3d pipeline/enemy/goblin/goblin_v010_texture_0.png').convert('RGB').resize((1024,1024),Image.Resampling.LANCZOS)
a=np.asarray(im).astype(float)/255
r,g,b=a[:,:,0],a[:,:,1],a[:,:,2]
mask=np.clip((g-r-0.008)/0.045,0,1)*np.clip((g-b-0.012)/0.06,0,1)
lum=a@np.array([0.2126,0.7152,0.0722])
palettes={'normal':None,'fire':(0.24,0.23,0.24),'water':(0.24,0.68,0.82),'earth':(0.65,0.57,0.32),'air':(0.63,0.84,0.72),'lightning':(0.59,0.43,0.82)}
for name,rgb in palettes.items():
    result=a if rgb is None else a*(1-mask[:,:,None])+(lum[:,:,None]/0.49*np.array(rgb))*mask[:,:,None]
    Image.fromarray((np.clip(result,0,1)*255).astype('uint8')).save(out/f'shaman_{name}_albedo.png')
print('Six masked skin textures written; geometry remains shared.')
