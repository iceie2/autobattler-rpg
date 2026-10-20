# Tempest Conduit — Living Storm, wave 55

Updated 2026-10-06: starts with a head, four body sections and tail, then grows
through Storm Feast food pickups. The entire snake moves continuously, fires magic basic attacks from
its tail and leaves circuits in its wake. Any section is attackable; HP, stats,
statuses, kill credit and rewards belong to one UnitBase.

## Board and rendering

- Six initial, cardinally connected grid cells point to the same enemy. Combat
  range, target selection, homing projectiles and cell/radius/row damage can
  reach the body or tail. An AoE hits that one enemy once.
- Tempest's `phase_through_units` factory meta registers its entire body in
  BattleGrid's nonblocking `passing_cells` layer. It moves through occupied
  hero/enemy cells without pushing, overwriting or dealing contact damage.
  Heroes can also move into snake cells. Solid units retain their usual
  placement/pathfinding rules. `get_units_at` and `get_all_units` include both
  layers; combat collection deduplicates the shared HP owner even when every
  section overlaps a hero. Purge, phantom sweep and reset clean both layers.
- Each step shifts the head into a legal cardinal neighbor and each following
  section into its predecessor's old cell. Each section interpolates its own
  previous position. The old tail cell can be entered as it vacates.
- All body cells are validated together. Failed moves/displacements restore the
  entire footprint. Death purges every cell by owner identity.
- Right-clicking a section opens that enemy's existing live unit details;
  right-clicking a shared square cycles between its hero and Tempest.
  One HP bar follows the head; hit flash and damage text follow the hit section.
- The current model's armor/head meshes were split locally in Blender into
  `tempest_head_v004.glb`, four `tempest_body_N_v004.glb` files and
  `tempest_tail_v004.glb`. Each has seven rigid-skin clips. Bounds bones frame
  the actual geometry; a single root bone alone does not frame correctly in
  this project's Model3DSprite.
- Render-only children follow the owner. They never enter a combat roster.
  Added sections reuse the preserved body meshes; the animated tail stays last.
  Lightning links join adjacent sections. v001/v002/v003 and their sources
  remain preserved. No external generation service or credits were used.

## Fight loop and tuning

- Always active from the first combat tick. No mana or skill cooldown gate.
  Movement continues while warning channels charge, discharge VFX play and
  the tail fires. Roots, board edges and its own unvacated body restrict travel; slow
  and taunt remain connected to existing combat systems.
- Every 3 completed steps leaves a circuit along the tail's path. Marked cells
  warn for 1.1s, then deal 100% MAG once to each hero still on them.
- Every third circuit is Storm Surge: 6 steps, 1.4s warning, then 160% MAG on
  the new circuit plus the last two spent paths. Overlap never multiplies hits;
  surge consumes those spent paths. Trails have no continuous damage.
- Warnings use the shared Channel system with `blocks=false`. The next path
  is drawn independently while the previous circuit charges. Circuits follow
  the tail so each marked path follows the snake's wake.
- Tail basic bolts use 100% live MAG, outgoing damage multipliers, magic armor
  mitigation, current attack speed and range. Origin is the interpolated tail.
  Bolts respect combat pause and speed.
- Warning, travel, memory and cleanup use combat time. Death/fight reset clears
  all circuits and pending channels. Long forced displacements restart the
  uncharged path without changing an already announced warning's cells.
- Boss/elite incoming-stun immunity remains the enabled Balance test.
  Tenacity stats/formulas are preserved. Disabling the flag restores incoming
  stuns; a stun pauses travel and interrupts a pending circuit warning.
- Tempest is immune to Rift's Tear teleport (`rift_banish_immune` factory meta),
  while still taking Tear's magic damage. The six-cell body, in-flight movement
  and circuit warning remain intact. This is stated in Living Storm's tooltip;
  Tear still teleports ordinary enemies.
- **Storm Feast:** a gold/green food mote appears after 4 combat seconds. Tempest
  seeks it through the board, including occupied hero cells. Only a completed
  head arrival consumes food. The food never occupies a blocking cell or enters
  combat/reward rosters. New food appears 6 seconds after each meal.
- Each meal heals 3% of current max HP through the normal healing pipeline
  (including healing modifiers and the max-HP cap), earns one body section and
  adds 5% of base movement speed for this fight. Growth holds the tail on the
  next legal step, preserving interpolation and shared HP. If there is no room
  to retain the tail on that step, slithering continues until growth fits.
- Food bonuses add: 4.00 base speed becomes 4.20, then 4.40. They only affect
  movement. `UnitBase.effective_movement_speed()` combines food with existing
  slows/haste and reposition/frenzy speeds; both movement interpolation and
  live Unit Details use it. The live tooltip/kit show meals, bonus and length.
  Cleanup restores six sections and base speed and removes food/consume VFX.

Knobs: `scripts/combat/tempest_circuit.gd` constants `STEPS`, `SURGE_STEPS`,
`WARNING`, `SURGE_WARNING`, `DAMAGE_MULT`, `SURGE_DAMAGE_MULT`.
Food knobs are in that same controller: `FOOD_FIRST_DELAY`,
`FOOD_RESPAWN_DELAY`, `FOOD_HEAL_PCT`, `FOOD_MOVE_PER_MEAL`.
Tail MAG/APS/range and movement speed are the normal factory stats in
`EnemyFactory.create_tempest_conduit`. Keep skill/passive text aligned when
tuning. This pass establishes behavior; it does not certify final difficulty.

## Verification

- Targeted snake probe: 745 checks, including real tail-side melee damage,
  section homing, magic mitigation and tail origin, cell/row/wave AoE, one hit
  per owner, boundary rollback, connected interpolation, tail re-entry,
  continuous movement during warnings, independent autos at zero mana,
  circuit timing/memory/surge, extended travel, immunity/tenacity and cleanup.
  Tear additionally verifies damage with no Tempest teleport or movement/channel
  interruption, alongside an ordinary enemy that still teleports.
  Shared head/body cells verify melee damage, zero contact damage, hero movement
  into the body and cycling live inspection. A fully occupied 3x3 board verifies
  connected spawning, uninterrupted automatic travel, roster deduplication,
  both owners' independent removal and phantom cleanup without losing heroes.
- Godot import and main-game boot have no script errors. The project already
  reports four retained resources on some smoke-test exits.
- Phantom-cell and Doc revival regressions pass.
- Feeding probe: 921 checks covering opening delay, actual head pursuit and
  repeated meals, exact/clamped healing, additive speed, unchanged attack speed,
  model growth, stable animated tail, grown-section projectile/melee hits and
  shield absorption, longer-fight routing, and food/death/battle cleanup. The
  real main-game Unit Details is exercised with food stacks, a slow, expiry and
  reset; interpolation matches its displayed value. UI smoke also passes.
- Three real seven-hero level-36 wave-55 simulations completed without stalls.
  All three fixtures won; balance still needs owner playtesting.
- General arena probe marks the always-active skill EXPECTED when a forced
  recast has no new observable effect; the targeted probe covers its full loop.
  Existing Drowned Maw reaction and Magma Heart passive silent results remain.
- Actual lightning-board captures were inspected after correcting the initial
  camera framing issue.
  New `tempest_snake_passing_head.png` and `tempest_snake_passing_body.png`
  captures show shared squares using the real models.
  `tempest_food_target.png`, `tempest_food_swallow.png`, and
  `tempest_food_grown.png` show the food and two added sections.

Snapshots before this change: root `backups/tempest-snake-2026-10-05`.
Pass-through snapshots: root `backups/tempest-pass-through-2026-10-05`.
Feeding snapshots: root `backups/tempest-feeding-2026-10-05` (started before midnight).
Captures: root `captures/renders/lightning/tempest_snake_*.png`.
Rebuild: Blender `--background --python tools/model3d/build_tempest_snake_parts.py`
from the Godot project root, then import with Godot. The preserved v003 file is
the source for splitting the armor meshes.
For overlap captures, run `scenes/tools/tempest_living_capture.tscn` with
`-- --pass-through` using the compatibility renderer.
Use `-- --feeding` for food and growing-body captures.
