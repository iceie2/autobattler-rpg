"""Encode the real Godot-rendered frames; playback slowed 2x for move review."""
from pathlib import Path
from PIL import Image
root = Path(__file__).resolve().parents[3]
folder = root / 'captures/renders/normal/giant_groundbreaker_frames'
frames = [Image.open(p).convert('RGB').resize((960,540), Image.Resampling.LANCZOS)
          for p in sorted(folder.glob('frame_*.png'))]
assert len(frames) == 102, f'Incomplete capture: {len(frames)} frames'
palette = Image.new('RGB', (960, 540 * 4))
for i, index in enumerate([0, 26, 30, 78]): palette.paste(frames[index], (0, i * 540))
palette = palette.quantize(colors=128)
frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
out = root / 'captures/renders/giant_groundbreaker_six_elements.gif'
frames[0].save(out, save_all=True, append_images=frames[1:], duration=84,
               loop=0, optimize=True)
print(out, len(frames), 'real engine frames')
