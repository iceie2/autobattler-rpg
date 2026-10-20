# Enemy 3D batch — 2026-10-02 (overnight)

Waves 5 / 15 / 20 / 25 / 30. Meshy balance **1100 → 932** (168 spent, floor 500
never approached). All five are wired in `VisualUnit.MONSTER_MODEL_PATHS` as v001
candidates. **Delete a line there to put any of them back on its 2D sprite.**

| wave | enemy | route | credits | state |
|---|---|---|---|---|
| 5 elite | Hill Giant | Meshy biped + stone-club prop | 46 | ready for review |
| 15 elite | Gale Warden (flock) | Meshy body + custom rig (`creature_rig.py --kind bird`) | 24 | ready for review |
| 20 boss | Skyrender | Meshy body + custom rig (bird, + `fly` loop) | 24 | ready for review |
| 25 elite | Tidecaller | Meshy biped | 41 | ⚠ skill + hurt tear (below) |
| 30 boss | Drowned Maw | Meshy body + custom rig (`--kind quad`, jaw + lure) | 24 | ready for review |
| (orc concept, parked) | | | 9 | unreviewed |

Review images: `<enemy>/review/` — board renders on the biomes each enemy
actually appears in (Hill Giant: all six), plus clip contact sheets for the
custom rigs.

## Decisions needed

1. **Tidecaller skill + hurt.** The arms were generated fused to the barrel body,
   so any clip that lifts an arm high drags the flank up with it (see
   `tidecaller/review/tidecaller_v001_skill_hurt_TEAR.png`). Weight fixes were
   tried (inboard clamp, rigid segments) and did not help; it is the mesh, not
   the weights. Proposal: swap to low-arm clips, **173 Slap Reaction** for hurt +
   a low-arm cast for skill = **6 credits**. Not spent — your rule is to ask
   before re-spending on an unusable result.
2. **Enemy presentation.** All five use the approved HERO presentation (native
   PBR, 256px, soft outline) via a new opt-in `"pbr": true` in
   `MONSTER_MODEL_PROPS`. The old toon path blew Tidecaller to neon and the
   club white. TOON comparison renders are kept as `*_TOON.png`. Should goblins
   move to PBR too?
3. **Skyrender aloft.** Its `fly` hover loop exists in the .glb but nothing plays
   it — the aloft window currently has no body change. Want it hooked up?
4. **Custom-rig look.** First use of procedural (scripted) clips. They are clean
   but simpler than mocap. If you like them, the same tool covers the other
   non-bipeds; Khagan needs two NEW kinds (octopus, crab) — not started.

## What changed in code

- `scripts/units/visual_unit.gd` — 5 `MONSTER_MODEL_PATHS` entries, 5
  `MONSTER_MODEL_PROPS` entries, and the `monster_pbr` opt-in in
  `_setup_model3d`. Hill Giant aliases `skill → ult` (Charged_Ground_Slam is
  NAME_MAPped to `ult` for Cross); no `NAME_MAP` change was needed.
- `tools/model3d/creature_rig.py` (new) — rig + clips for non-bipeds. Adds leaf
  `_end` bones because `Model3DSprite.character_bounds()` only measures bone
  ORIGINS; without them a body measures short and is scaled up ~1.5x.

## Gates

- Godot import: clean (one pre-existing UI UID-duplicate warning, unrelated).
- Arena probe: `errors: 0`.
- `skirt_stress`: Hill Giant all clips ≤ 2.03x. Tidecaller fails (see 1).
- `attach_prop_socket`: only `clip0` (Meshy rest) and the breathing `idle`
  flagged, same as every prior conversion.
- `anim_preview_smoke` only walks HERO_MODEL_PATHS, so it does not cover these.

## Gotchas found

- `meshy_api.py --out` is a DIRECTORY for image-to-3d/rig/animate/prop.
- Flat-colour props: the toon `tint` uniform double-lifts glTF linear colour,
  so props looked white. Moot under PBR, but the toon path still has it.
- Rebuild scripts: `hill_giant/review/rebuild_v001.sh`,
  `tidecaller/review/rebuild_v001.sh` (free, no Meshy calls).
