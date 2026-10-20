# Enemy 3D batch 2 — 2026-10-03

Every remaining elite and boss except the Triarch is now 3D and wired in
`VisualUnit.MONSTER_MODEL_PATHS` (v001 candidates; delete a line to fall back
to the 2D sprite). Meshy balance **884 → 391** (owner lowered the floor to 100).

| wave | enemy | route | notes |
|---|---|---|---|
| 35 E | Terracotta Colossus | Meshy biped, grafted "brute" clips | |
| 40 B | Cloven Titan (+ halves) | Meshy biped, brute | halves reuse the model at 1×1 |
| 45 E | Magma Heart | Meshy biped, brute | |
| 50 B | Emberhollow + Ember Heart | biped, brute / static cage | |
| 55 E | Tempest Conduit | serpent rig | `scale` 1.5 |
| 60 B | Arcfang | quad rig | stride a bit stiff |
| 65 E | Ant Hill + Ant | procedural mound (static) / insect rig | mound `scale` .36 + `frame_grow` 2.4 |
| 75 E | Stat Stealer | Meshy biped, grafted "caster" clips | robe — watch for tearing |
| 80 B | Hydra ×6 elements | one body per element, hydra rig | 3 independent necks |
| 85 E | Mirrorplate Warden | quad rig | `scale` .7 |
| 90 B | Gravekeeper | Meshy biped, brute + shovel prop | |
| 95 E | Aspect Devourer | insect rig | `scale` .62 |
| 100 B | The Architect | Meshy biped, brute | marble reads bright |

**Not converted: Triarch (wave 70).** It has no art of its own — its three phases
borrow hero-class sprites — so a 3D version is a design decision, not a conversion.

## How it stayed cheap
- **Grafted clips** (`tools/model3d/assemble_biped.py`): Meshy's humanoid rig is
  the same 24 bones on every body and its clips are per-bone local rotations, so
  the Hill Giant's and Tidecaller's purchased clips play on every new Meshy rig.
  Verified on renders (feet stay planted). Saves ~12 credits per biped.
- **Ant Hill built procedurally** (`tools/model3d/make_ant_hill.py`) after the
  Meshy concept drew a dwarf standing beside a mound.

## Engine changes (`scripts/units/visual_unit.gd`, `model3d_sprite.gd`)
- `MONSTER_MODEL_PROPS` gains optional `"scale"` and `"frame_grow"` per monster —
  the knobs to use when tweaking sizes in playtests.
- `Model3DSprite.idle_bounds()` accessor.

## Rig tool (`tools/model3d/creature_rig.py`)
New kinds: `insect`, `serpent`, `static`, `hydra` (plus `octopus`, `crabrider`
from Khagan). Every custom rig now carries `BoundsTop`/`BoundsBase` marker bones:
the engine sizes models from bone ORIGINS, and domed bodies measured short and
rendered 2–3× too big. Gale Warden and both Khagan models were rebuilt with them.

## Gates
Import clean · arena probe `errors: 0` · one sim per elite/boss wave (35–100):
no script errors (outcomes are balance, not checked).
