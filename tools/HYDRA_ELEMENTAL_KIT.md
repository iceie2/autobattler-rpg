# Wave 80 Hydra

The player picks Normal, Fire, Water, Earth, Air, or Lightning before fighting.
The existing base stats, HP pool, level scaling, and affinity system remain.
Balance numbers below are first cuts for playtesting.

## Head health

Three heads share the existing total HP in thirds. Crossing each threshold
permanently severs a head. Overkill carries through multiple heads. Shields
absorb hits before head HP. Healing is capped at the surviving heads' HP
capacity, so it cannot restore a severed head. The final sever wins even when
difficulty escorts survive. A new fight restores the three-head state.

The overhead HP bar consists of three separate head sections using the existing tiled HP artwork and green/yellow/red health colors. Severed sections remain empty. Model neck geometry collapses to the corresponding
stump through persistent skeleton overrides; casts cannot restore it.

Timed head regrowth and its ATK increase have been replaced. Base ATK stays
unchanged. Surviving heads determine bite targets and signature coverage.

## Moves and first-cut tuning

Shared Serpent Strike: each surviving head bites a different hero in melee
range for 120% current ATK, every 5s.

Elemental signature: first attempt at 3s, 10s cooldown, 0.9s anticipation,
0.5s recovery. Stuns interrupt anticipation. Damage uses current ATK and the
usual outgoing modifiers, affinities, armor, shields, and damage reporting.

| Element | Move | First-cut behavior |
| --- | --- | --- |
| Normal | Crushing Jaws | One target; 180% ATK plus 25 percentage points per additional surviving head; 0.8s stun. |
| Fire | Scorched Ground | Fixed 5-tile strip, half-width 0.7 tiles plus 0.2 per additional head; 120% ATK hit. Ground persists 3s, dealing 20% ATK/s as true Fire damage in 0.5s ticks. |
| Water | Undertow | Pulls one tile toward Hydra within 3 tiles plus 0.25 per additional head. Another 0.5s warning, then a 2-tile blast for 140% ATK. Occupied destinations block the pull. |
| Earth | Stonefangs | Marks surviving-head count plus one hero tile. Fixed-tile eruptions deal 125% ATK and root for 1.2s. Moving off the tile avoids the eruption. |
| Air | Gale Sweep | Fixed 70-degree cone, range 4 tiles plus 0.5 per additional head; 120% ATK and one-tile push where space permits. |
| Lightning | Forked Discharge | Marks the farthest hero. 150% ATK primary strike, then up to one chain jump per surviving head, within 2 tiles of each prior victim. Each jump retains 80% damage. No repeated victims. |

Control durations use the existing target-tenacity rules. Unit Details uses
the shared HydraKit description and damage calculation for live readouts.

## Animation and VFX

Each element has an authored signature clip with a different neck/body motion:
converging jaws, rear-and-exhale, inward gathering, crouch-and-erupt, lateral
sweep, or staggered electrical neck snaps. Each also has distinct anticipation
and impact geometry, including flame ground, water rings, stone spikes, wind
bands, and branching lightning.

Original v001 GLBs are preserved. v002 models append the new clips and retain
the original mesh, rig, textures, and existing clips. Rebuild them locally with
`tools/model3d/add_hydra_signatures.py`. No generation service is needed.

Gameplay and tuning: `scripts/combat/hydra_kit.gd`.
VFX: `scripts/combat/hydra_vfx.gd`.
Checks: `scenes/tools/hydra_kit_check.tscn`; pass `-- --capture` for rendered
move, head-health, and element-picker snapshots in the outer captures folder.
