# CONVENTIONS.md — working guide for AI assistants and contributors

Read this BEFORE editing. It encodes the landmines and patterns this codebase
has already paid for. Written 2026-07-03 during the foundation session.
Godot 4.5, GDScript. Game: wave-based RPG autobattler.

---

## 1. Verification commands (run these, always)

From `autobattler-rpg/` (Godot binary path may differ per machine):

```sh
GODOT="/c/anything coding/Godot_v4.5.1-stable_mono_win64/Godot_v4.5.1-stable_mono_win64_console.exe"

# 1. Parse/registration check (after ANY script change):
"$GODOT" --headless --path . --import --quit
#    → must finish with no SCRIPT ERROR lines.

# 2. Boot smoke test (after gameplay/UI changes):
"$GODOT" --headless res://scenes/main_game.tscn --quit-after 150
#    → must finish with no SCRIPT ERROR.
#    NOTE (2026-09-19): this NO LONGER prints "Battle round 1 started!". With
#    main_game.MAP_MODE on, a run opens on the RUN MAP and no round begins until
#    the player picks a node — so a silent boot is the correct result now, and
#    the round-flow check moved to the map smoke (§3g). Set MAP_MODE = false to
#    get the old linear behaviour (and that line) back.

# 3. Ability probe (after touching ANY hero/monster kit):
"$GODOT" --headless --fixed-fps 30 res://scenes/arena.tscn -- --mode=probe
#    → JSON between ARENA_RESULT_BEGIN/END; "silent_abilities" must be 0.
#      If your new ability is legitimately untestable statically, add an
#      EXPECTED_SILENT entry (with an honest reason) in arena_main.gd.

# 3b. Round-start ceremony (after touching row bonuses / revives / round flow):
"$GODOT" --headless res://scenes/ceremony_smoke.tscn
#    → "CEREMONY_SMOKE: ALL PASS". The boot smoke stops at round 1 and never
#      reaches the between-round payout, so this drives it directly.

# 3c. Grid bookkeeping (after touching placement / removal / movement / death):
"$GODOT" --headless --fixed-fps 30 res://scenes/phantom_cell_test.tscn
#    → "PHANTOM_CELL_TEST: ALL PASS". Guards the stranded-cell class of bug:
#      occupied_cells entries left behind by a removal that missed become an
#      invisible wall that blocks movement but not ranged attacks. Remove units
#      with battle_grid.purge_unit(unit), NEVER remove_unit(unit.grid_position).

# 3c-bis. Roster integrity (after touching death / revive / roster arrays):
"$GODOT" --headless --fixed-fps 30 res://scenes/doc_revive_test.tscn
#    → "DOC_REVIVE_TEST: ALL PASS". Guards the two-roster class of bug:
#      main_game.player_units is the run's team, AutoBattleManager.player_units
#      is a per-fight copy rebuilt from the grid. Anything that moves a unit
#      between alive and dead MUST update both, or the hero is orphaned out of
#      the run — unclickable, stranded mid-board, missing from the save, and
#      eventually queue_free()'d by _clear_middle_row. Use the `died` /
#      `unit_revived` signals; never mutate one roster alone.

# 3g. Run map (after touching RunMap, the map screen, or round flow):
"$GODOT" --headless --fixed-fps 30 res://scenes/arena.tscn -- --mode=map
#    → "violations": [] over 2000 generated maps, and every walk must report
#      13 nodes / 10 waves. Checks reachability, no crossing edges (convergence
#      rows exempt), two intensities per battle row, one merchant per biome.
"$GODOT" --headless res://scenes/map_smoke.tscn
#    → "MAP_SMOKE: PASSED". Drives the REAL main_game through a whole biome and
#      asserts THE TWO-COUNTER RULE: a battle node advances battle_round by
#      exactly one (to the node's own round, at the node's own tier), an
#      interstitial node advances it by ZERO, and the save round-trips the map
#      with each node's reward type and item rarity intact.
"$GODOT" --path . res://scenes/_run_map_capture.tscn -- --biome=1 --seed=77 --steps=6
#    → two PNGs in captures/renders (fresh map / part-walked). Needs a window.

# 3d. Event catalog audit (after touching EventCatalog / event effects):
"$GODOT" --headless --fixed-fps 30 res://scenes/arena.tscn -- --mode=events
#    → "errors": [] and "warnings": []. Walks every event × choice × grade its
#      band can roll, at rounds 1/10/50/100, and fails on any effect key that
#      main_game._apply_event_effects doesn't implement (the catalog's
#      EFFECT_VERBS list is the contract). Also prints the payout table — read
#      it against --mode=goldcurve before calling an event's numbers balanced.

# 3e. Event effects end-to-end (after touching event verbs or the catalog):
"$GODOT" --headless res://scenes/event_smoke.tscn
#    → "EVENT_SMOKE: PASSED". --mode=events only checks the DATA; this one
#      instantiates the real main_game, recruits two heroes and pushes every
#      catalog choice through _apply_event_effects, asserting each verb
#      actually moves gold/HP/stats/bag/flags rather than silently no-opping.

# 3f. Event panel look (after touching event_panel layout):
"$GODOT" --path . res://scenes/_event_capture.tscn -- --event=the_crossroads --grade=S
#    → three PNGs in captures/renders (choices / reel mid-spin / outcome).
#      Needs a real window — no --headless.

# 4. Balance sim (after touching stats/numbers):
"$GODOT" --headless --fixed-fps 30 res://scenes/arena.tscn -- --mode=sim \
  --team=SABLE:3,RIOT:3 --enemy=wave:5 --runs=5 --seed=42
#    → compare win_rate/damage vs before your change.
```

```sh
# 4b. Threat calibration gate (after touching wave composition, enemy stats,
#     resistances, the filler budget or score_unit/score_spec):
"$GODOT" --headless --fixed-fps 30 res://scenes/arena.tscn --   --mode=threatcheck --from=1 --to=10 --difficulty=brutal --runs=20
#    → read "inversion_rate", NOT "inversions".
#
#      READ THE RATE, NOT THE COUNT. A raw inversion count is not comparable
#      between two runs: pairs that are near-ties on either axis are skipped, so
#      how many pairs are eligible depends on how saturated the measurement is.
#      A change that UNSATURATES the curve makes more pairs comparable and can
#      raise the count while the ordering genuinely improved. Measured
#      2026-09-22 on the effective-power rewrite: Normal went from 12 to 10
#      inversions while comparable pairs went 42 -> 39 — the count moved little,
#      the rate fell. The output carries `comparable_pairs` and
#      `saturated_cells` so this is visible rather than inferred.
#
#      RUN-TO-RUN VARIANCE IS REAL. Repeat every measurement at least twice.
#      Measured on the same seed and the same code: Normal reproduced exactly
#      (12/42 both passes) while Veteran gave 12/41 then 10/38. A difference of
#      one or two inversions is noise, not signal.
#      An inversion is a pair of waves where score_spec's ORDERING contradicts
#      measured difficulty — score says one is harder, the fight says the other
#      is. score_spec is a fast heuristic and is ALLOWED to be approximate; it is
#      not allowed to be backwards. A battle sim can never replace it (the prep
#      readout and the filler budget both need an answer in microseconds), so
#      this gate exists instead: the heuristic cannot rot silently the way it did
#      across the resistance pass and the 30→100 expansion. Measured 2026-09-21
#      before the gate existed: round 7 Brutal scored 6898, BELOW round 6's 7538,
#      and won 0% against round 6's 60%.
#
#      SATURATION WARNING — a low inversion count is not automatically good. If
#      most cells read 0% (or 100%) then hardness ties and the check has nothing
#      to compare. Biome 1 Brutal reports just 1 inversion against a FRESH cohort
#      purely because everything from wave 5 on is unwinnable for it. Land the
#      cohort mid-range before trusting the number:
#        --xpbonus=150 --slots=3 --hero-cap=20      (an invested account)
#      Same waves, invested cohort: 4 real inversions.
#
#      The team is derived from the same xpcurve math as --mode=xpcurve, so
#      "wave 9 Brutal" is measured against the roster a player walking that lane
#      would actually hold, not an arbitrary fixture.
```

```sh
# 5. Ability numbers + description lint (after touching AbilityFormulas or any hero kit):
"$GODOT" --headless --path . res://scenes/formula_dump.tscn -- --level=10
#    → every hero's 3 abilities with resolved numbers; "0 slots with no terms"
#      and "DESC_LINT: ALL PASS".
#      Level 10 is the calibration anchor, so values there must match whatever
#      the ability produced before your change unless you MEANT to retune it.
```

```sh
# 6. 3D character import (after merging or replacing any character .glb):
#    FULL PIPELINE for converting a character to 3D: see ../3D_PIPELINE.md
py -3 tools/model3d/glb_merge_anims.py "assets/3d pipeline/hero/<name>/raw" "assets/3d pipeline/hero/<name>/<name>.glb"     --tex 1024 --harden-bones RightHand,LeftHand
#    --harden-bones is NOT optional for a Meshy rig with held/worn props. Its
#    auto-rigging bleeds forearm influence into the gloves (measured 45-49% of
#    glove verts sharing weight with the forearm), so they droop and lag instead
#    of moving rigidly with the hand. Inspect any rig with:
#      py -3 tools/model3d/glb_weights.py <file.glb> --bone RightHand
#    Hardening lives INSIDE the merge on purpose: as a separate patch step, the
#    next Meshy re-export would silently drop it.
"$GODOT" --headless --path . --import --quit
"$GODOT" --path . res://scenes/tools/model3d_probe.tscn -- model=res://"assets/3d pipeline/hero/<name>/<name>.glb"
#    → prints the node tree, bone count and every clip's length, and writes
#      user://_model3d_probe.png: one row per animation, 6 poses across the clip.
#      LOOK AT THE SHEET. A rig that imports without errors can still be limp
#      (no Skeleton3D → mesh doesn't deform) or mis-framed, and neither shows up
#      in the log. Runs WINDOWED on purpose — --headless uses the dummy renderer
#      and would write an empty sheet.
```

```sh
# 7. 3D hero on the board (after touching Model3DSprite or HERO_MODEL_PATHS):
"$GODOT" --path . res://scenes/tools/model3d_board_check.tscn -- --hero=<NAME> --round=1
#    → captures/renders/<biome>/_model3d_board_<hero>.png
#      --round selects the BIOME (1 normal, 11 air, 21 water, 31 earth, 41 fire,
#      51 lightning). Heroes fight every round 1-100, so they meet all six:
#      sweep `for r in 1 11 21 31 41 51` and compare, don't judge on one.
#      Until 2026-09-18 this check rendered on a flat clear colour despite
#      claiming "the real board" — a model lit against empty space tells you
#      nothing about whether it reads on the ground it fights on.
#    Contents: the 3D hero in idle/walk/attack/hurt/death,
#      a row of 2D heroes beneath it for size comparison, and an enemy-side copy
#      to check facing. Errors if a hero silently fell back to 2D art or if
#      plain_sprite isn't aimed at the model's inner sprite (which would leave
#      the procedural layers — flash, squash, Long Fall toss — not reaching it).
#      Windowed, same reason as check 6.

# 7b. 2.5D frame cost (before converting more heroes to 3D):
"$GODOT" --path . res://scenes/perf_probe.tscn -- --roster=BOUNCER
"$GODOT" --path . res://scenes/perf_probe.tscn -- --roster=RUSH
#    → 15 3D heroes vs 15 2D heroes in the real scene. Each 3D hero is its own
#      SubViewport, so this is THE number that decides whether per-unit 3D
#      viewports stay viable as the roster converts. Measured 2026-09-04:
#      indistinguishable (~13-15ms avg both ways, RTX 3080). Run BOTH — frame
#      times here are noisy, so a single run proves nothing.
```

```sh
# 8. Hero recruitment (after touching ANY unit visual path or sprite loading):
"$GODOT" --headless --path . --fixed-fps 30 res://scenes/recruit_smoke.tscn
#    → "RECRUIT_SMOKE: ALL PASS (26 heroes)". Buying a hero is the only path
#      that puts an ARBITRARY class into the tree, so it's where a missing sheet
#      becomes a crash. The boot smoke only ever spawns the default roster and
#      will not catch this: on 2026-09-04 five heroes (bouncer/cross/pastor/
#      rush/static) crashed on recruit for weeks behind that gap.
```

```sh
# 9. Board perspective (after touching BoardPerspective, BattleGrid geometry,
#    or BackgroundLayer tile drawing):
"$GODOT" --headless --path . res://scenes/perspective_smoke.tscn
#    → "PERSPECTIVE_SMOKE: ALL PASS". Asserts world_to_grid(grid_to_world(c)) == c
#      for every cell, that rows tile the board with no seam and still sum to the
#      flat height, and that off-board points stay off-board. Cells are TRAPEZOIDS
#      now — a rounding slip here shows up only as "drag sometimes drops in the
#      wrong square", which no screenshot will reveal.
#    BoardPerspective.FAR_SCALE = 1.0 is the kill switch: it restores the flat
#    board exactly, and is the baseline to A/B against.
```

```sh
# 10. Stretch punch (after touching Model3DSprite's stretch bake or its bones):
"$GODOT" --path . res://scenes/tools/stretch_punch_check.tscn
#    → "STRETCH_PUNCH: ALL PASS" + user://_stretch_punch.png filmstrip
#      (top row stretch ON, bottom OFF). ASSERTS the hand actually gets further
#      from the shoulder, because every failure mode here is silent: a wrong
#      bone name, a missing track, or a bad track path just yields a normal
#      punch with no error. It has already caught two — a runtime
#      SkeletonModifier3D that lost to the AnimationPlayer, and a hand-built
#      track path ("Skeleton3D:RightArm" instead of "Armature/Skeleton3D:RightArm")
#      that resolved to nothing. Both measured exactly x1.00.
```

## 0. Where files go — CHECK BEFORE YOU CREATE

**Never invent a directory.** An established one almost always exists, and a
wrong guess propagates: `assets/3d pipeline/` already existed WITH the raw
Bouncer exports in it, was missed once, and produced a duplicate
`assets/models/boxing_bot/` plus ~450 MB of pointlessly imported source — and the
wrong path had already been written into the pipeline doc that 25 more characters
were going to follow.

| what | where |
|---|---|
| Raw 3D generator output | `assets/3d pipeline/hero/<name>/raw/` (**must hold a `.gdignore`**) |
| Merged runtime 3D model | `assets/3d pipeline/hero/<name>/<name>.glb` |
| 2D sprite sheets | `assets/sprites/heroes/<name>/` |
| Static hero / monster art | `assets/using/...` |
| Python asset tools | `tools/<area>/` |
| Dev-tool scripts / scenes | `scripts/tools/<bucket>/` + `scenes/tools/` |
|  ↳ one-off art captures | `scripts/tools/captures/` (`*_vfx_capture`, `*_capture`, `*_strip`) |
|  ↳ kit / behaviour probes | `scripts/tools/probes/` (`*_kit_probe`) |
|  ↳ board & state checks | `scripts/tools/checks/` (`*_check`, `*_board_check`) |
|  ↳ general dev tools | `scripts/tools/` top level (anim_preview, model3d_*, arena_*) |
| Throwaway capture PNGs | `../captures/renders/` — **via `CapturePaths.out("<thing>.png")`, never a hardcoded path** |

**Name things what the GAME calls them.** The hero is `bouncer`, so the model is
`bouncer.glb` — matching `assets/sprites/heroes/bouncer/`. Generator-side names
("boxing_bot", "Meshy_AI_orange_...") stay inside `raw/` and never reach a
runtime filename or a code path.

Raw generator output is SOURCE, not runtime: it belongs behind a `.gdignore` so
Godot neither imports it nor caches it. Only the merged file is loaded.

**Capture scripts: two ways to get the path wrong.** A literal
`"res://_x.png"` is the obvious one. The other is building it —
`"res://" + name`, or `"%s/%s" % [OUT_DIR, name]` with `const OUT_DIR := "res://"`.
Seven scripts used the second form and survived the 2026-09-18 literal sweep
untouched, then wrote 26 files straight back into the project root on the next
run. Grep for `"res://"` as a PREFIX, not just for whole-path literals.

**Debug renders never go under `res://`.** This table used to say "project root,
named `_<thing>.png`" and every new capture script copied its neighbour: by
2026-09-18 the root held 107 stray PNGs + 113 `.import` sidecars (14 MB), each
one also a permanent entry in a `.godot/` cache that had reached 2.1 GB. Nothing
referenced any of them. Anything under `res://` gets imported, so the only fix
that holds is writing outside the project:

```gdscript
var path := CapturePaths.out("june_vfx_aura.png")   # -> ../captures/renders/
get_viewport().get_texture().get_image().save_png(path)
```

`scripts/tools/capture_paths.gd` owns the destination — change it there, not in
the 40-odd call sites. A literal `"res://_*.png"` in a capture script is a bug.

**If the right home isn't obvious from the table above, ASK. Do not guess.**

A task is NOT done until the relevant checks above pass. Commit after each
verified task; never commit with a failing check.

## 1b. Hero ability numbers live in ONE place

`scripts/units/ability_formulas.gd` is the single source of truth for every hero
passive/active/ultimate number. Combat reads from it; the level-up screen reads
from it; that is why the panel can promise the player a number and have the
fight honour it.

**Never inline an ability coefficient in `auto_battle_manager.gd`.** Add a term
to the registry and read it back:

```gdscript
var dmg := _ab(caster, AF_ACTIVE, "dmg")        # int, the common case
var pct := _abf(caster, AF_PASSIVE, "reflect")  # float
AbilityFormulas.flat(UnitClass.STITCH, AF_ACTIVE, "share")  # no caster available
```

Every `text` template must make sense to a player who has never seen that hero:
say what the effect DOES, never just restate the ability's name ("Overdrive for
4s" is the anti-pattern) and never name another ability. `formula_dump`'s
DESC_LINT enforces both, plus a 68-char budget so nothing overflows its row in
the shop / level-up panel.

An ability whose numbers are not in the registry cannot appear on the level-up
panel — it will silently render blank. The formula is
`(base + ratio*STAT) * (1 + LVL_COEF*level)`, normalised so `CAL_LEVEL` (10, the
base hero level cap) is power-neutral against the pre-registry code. Damage,
heals and shields scale; proc chances, durations and CC deliberately do not.
Discrete effect counts and percentages may scale when they are explicitly a
hero's stat payoff. Stitch's Link is the precedent: MAG 0→500 floors network
size from 3→6 enemies and per-target sharing from 15%→30%, keeping the formula
panel and combat on the same whole targets and percentage points.

Mob and legacy base-class skills (WARRIOR/RANGER/MONK/…) are NOT in the registry
and still compute inline — they have no level-up screen, so they were left alone.

## 2. Landmines (each of these has already caused a real bug)

1. **`main_game.gd` cannot be instantiated outside its scene.** It hard-references
   autoloads (`Progression`) at parse-time-executed paths. Never `load(...).new()`
   it in a test. Test its logic only via the full scene boot, or better: extract
   pure logic into `class_name` statics (see WaveScaler) and test those.
2. **ripgrep/Grep tools do not see `main_game.gd`** (unknown encoding quirk).
   Use `bash grep` / `sed -n` for that file.
3. **Factories return level-1 units; the CALLER applies `set_level()`.**
   Multi-phase bosses (Triarch, Khagan) snapshot their base stats LAZILY on
   first phase-transform because external leveling happens after creation.
   Never snapshot stats inside a factory function.
4. **Float→int Variant truncation.** Setting an int-typed stat from a float
   silently truncates EVERY assignment. For per-tick fractional drains/regens,
   bank fractions in an accumulator (`hp_regen_accum`, `burn_accum`,
   `drain_accum` pattern in unit_base/auto_battle_manager) and apply whole
   units only.
5. **GDScript lambdas capture ints BY VALUE.** `count += 1` inside a
   signal-connected lambda increments a copy. Use arrays/dicts for mutable
   capture, or instance fields.
6. **`randi()`-dependent picks must be locked once per round** if the code can
   run more than once per round (wave specs are regenerated on preview AND on
   Ready). See `_locked_elite_code_by_round` in main_game.gd for the pattern.
7. **Death flow:** `unit.die()` → `died` signal → main_game (or arena) erases
   from `player_units`/`enemy_units` + `battle_grid.remove_unit()`. The manager
   itself only filters invalid refs. If you spawn units outside main_game, YOU
   must wire `died` cleanup (see arena `_on_arena_unit_died`).
8. **`die()` is also the phase-transform hook.** Triarch/Khagan/possession/
   Phoenix-Pact all intercept death in `VisualUnit.die()` BEFORE `_is_dying`.
   Order matters there — read it before adding another interception.
9. **Bare `SceneTree` test scripts can't see autoloads.** Fine for UnitBase/
   factories/AutoBattleManager; not for anything touching Progression/etc.
   The arena scene (`scenes/arena.tscn`) runs WITH autoloads — prefer it.
10. **Ranged `attack()` spawns projectiles that land frames later.** Any test
    asserting damage from a ranged attack must let frames pass (see arena
    `_settle()`).

## 3. Where things live / registration points

Folder layout (2026-07-04 reorg — scripts/ is categorized, nothing lives loose;
all cross-script references are class_name-based, so moving a file only breaks
`.tscn` ext_resource paths + the project.godot autoload, nothing in .gd code):

```
scripts/
  core/       main_game, game_state, progression, balance  <- TUNING KNOBS
  units/      unit_base, visual_unit, unit_factory, enemy_factory,
              health_bar, status_icon, lpc_generated_animation_data
  combat/     auto_battle_manager, battle_grid, pathfinding, projectile,
              skill_effect, textured_skill_effect, storm_hazard,
              damage_text, background_layer
  waves/      wave_scaler, wave_data, wave_director
  economy/    gold_coin, gold_coin_system, round_reward
  equipment/  equipment_item, equipment_inventory, equipment_manager
  relics/     relic, relic_inventory
  synergies/  synergy_data, synergy_tracker
  events/     event_blessing, event_generator
  ui/         every screen/panel + ui_theme (styleboxes/colors/fonts) +
              unit_details_controller
  arena/      headless test harness (probe/sim/sweep/perf/ui_smoke)
```

**`core/balance.gd` is the single tuning file** — run-economy scalars, spawn
cadence, combat baselines (crit/time-scale), boss/elite/relic round numbers.
Balance passes start THERE. Per-class stat/growth tables stay in unit_factory
(data tables, not knobs). Old call sites keep local aliases
(`const HERO_COST := Balance.HERO_COST`) so grep still finds the old names.

| Thing | File | Notes |
|---|---|---|
| Tuning knobs (economy, crit, rounds, pacing) | `core/balance.gd` | START HERE for balance changes |
| Hero classes (enum, stats, growth, traits) | `units/unit_factory.gd` | `CLASS_BASE_STATS`, `CLASS_GROWTH_PER_LEVEL`, `TRAIT_CLASS_MAP` |
| Hero passives (per-frame) | `combat/auto_battle_manager.gd` `_tick_passive` | aura-style ones throttle via `AURA_TICK_INTERVAL` meta pattern |
| Hero on-hit passives | `_apply_on_hit_passives` | ANT/COAL/EMBER/SABLE/ZOLT/LUMEN |
| On-being-hit passives | `propagate_damage_links` + `take_damage` | RIOT/CROSS/RIFT/STITCH-link/STATIC Live Wire (reflect) |
| On-move triggers | `update_unit_movements` | SEAR fire trail, field hazards |
| Skills / ultimates | `_use_skill` / `_use_ultimate` dispatch | one match arm per class |
| Enemy factories | `units/enemy_factory.gd` | register new enemies in `CODE_TO_TYPE` + `create_by_type` + WaveScaler dicts (`CODE_ROLE`, `CODE_IS_LARGE`, `UNIT_POWER`) |
| Wave composition / difficulty | `waves/wave_scaler.gd` | all statics — arena-testable |
| Boss rounds 10/20/30, elites 5/15/25 | `waves/wave_scaler.gd` (round numbers in `core/balance.gd`) | `boss_code_for`, `ELITE_POOL` |
| Economy knobs | `core/balance.gd` (values), formulas in `waves/wave_scaler.gd` + `economy/round_reward.gd` | cut ~55% on 2026-07-02, do not buff without playtest data |
| Relics | `relics/relic*.gd` | 25-relic pool, hooks throughout battle manager |
| Crystal shop upgrades (content) | `core/progression.gd` `UPGRADES` | name/desc/max_level/cost_mult/effect, keyed by `key` |
| Crystal shop tree (layout) | `data/crystal_tree.json` via `ui/crystal_tree.gd` | position/size/icon/parent/max_level — **do not hand-edit**: open the shop, press F9, drag, Save (`ui/crystal_tree_editor.gd`, dev builds only) |
| Node max level | tree JSON override, else `UPGRADES` | read `Progression.max_level(key)`, **never** `upgrade["max_level"]` — the tree can override it per node (omitted in JSON = inherit) |
| Equipment | `equipment/equipment_*.gd` | combine = 3 same-rarity → next tier |
| Synergies | `synergies/synergy_data.gd`/`synergy_tracker.gd` | applied at battle start, reverted at end (`syn_backup` meta) |
| UI theming | `ui/ui_theme.gd` | panel/button/slot styleboxes, text colors, font-size bump helpers (wired via each screen's `_lbl` factory) |
| Arena harness | `scripts/arena/arena_main.gd` | probe/sim/sweep modes |

## 4. Patterns to copy

- **Temporary stat changes**: back up in unit meta (`syn_backup` pattern),
  apply at battle start, revert at battle end. NEVER let battle-only buffs
  leak into between-round state.
- **Per-unit timers**: real-time float fields counted down with `dt` inside
  `_tick_unit`/`_tick_statuses`; reset them in `_init_unit_timers()` at battle
  start (add yours THERE or it leaks across battles).
- **New status effect**: field(s) on UnitBase + reset in `_init_unit_timers`
  + decay in `_tick_statuses` + (optional) icon via `_set_status_icon_active`.
- **Stat floors**: damage ≥ 1 (take_damage), effective attack speed clamped
  0.1–6.0 (`attacks_per_second`), movement_speed & attack_range ≥ 1 everywhere
  (exception: Ant Hill is deliberately movement 0).
- **Player-facing gacha grades**: grey/green/blue/purple/gold =
  D/C/B/A/S — reuse `UnitFactory.GRADE_COLORS` everywhere.
- **Time scaling**: all sim speed derives from `AutoBattleManager.time_scale`
  (baseline `BASE_TIME_SCALE = 0.9`); UI speed buttons multiply on top.

## 5. Balance philosophy (from the human's playtests — treat as ground truth)

- Real playtest signal lives in the balance journal (memory) — check it before
  inventing numbers. Current known outliers: Nemi/supports weak alone;
  Sable/Headhunter/Rush strong (base stats happen to fit their kits).
- Crit baseline: 0% chance, 2.0x damage. Elite tier at rounds 5/15/25,
  bosses 10/20/30 (Khagan @10, Triarch @20/30).
- Economy is deliberately stingy post-2026-07-02: target curve = 2nd hero
  ~wave 3, 3rd ~wave 5, 4th-5th by wave 10 (Easy). Don't loosen it casually.
- Theorycrafted numbers are FIRST CUTS — mark them for playtest confirmation
  in commit messages / the balance journal. Don't claim a target was "hit".

## 6. UI conventions

- Theme is "parchment and gold" (2026-07-03/04 pass) — panels/buttons/slots
  come from `UITheme` (`scripts/ui/ui_theme.gd`): `panel_box()`,
  `header_box()`, `slot_box()`, `style_button()`. USE THOSE for any new
  panel/button/slot; hand-rolled dark-navy `_flat()` boxes are the OLD look
  (some screens may still carry them — migrate on touch, don't add more).
- Fonts: project-wide default is LeagueGothic (set in project.godot
  `gui/theme/custom_font`); font-size bumps go through
  `UITheme.header_font()/body_font()`, wired via each screen's `_lbl()`
  label factory — route new labels through the factory or they miss the bump.
- Monster/hero ability icons are PLANNED (assets incoming) — when building
  ability UI, always include an icon slot (TextureRect) next to the name,
  even if empty for now.
- Colors: `UITheme.TEXT_HEADER/TEXT_BODY/TEXT_BTN` for text on parchment,
  gacha grade colors for rarity (`UnitFactory.GRADE_COLORS`), element colors
  via `get_element_color_hex`.
- Buttons in radio-style groups (e.g. difficulty picker): set
  `focus_mode = FOCUS_NONE` + an empty "focus" stylebox, or the last-clicked
  button keeps a lingering focus ring. Never `flat = true` on a button that
  should always show its stylebox (flat buttons only paint when
  hovered/pressed/focused).

## 7. Delegated-task template (for Sonnet/lesser models)

When handing a task to a smaller model, use this shape — it's the checker
that makes one-shots reliable:

```
TASK: <one concrete change>
FILES YOU MAY TOUCH: <explicit list — nothing else>
PATTERN TO FOLLOW: <file:line of an existing example to mirror>
DO NOT: improvise, refactor neighbors, or touch files outside the list.
VERIFY: <exact command(s) from section 1>
EXPECTED: <what the output must contain>
THEN: git add -A && git commit with message "<given message>"
IF ANY CHECK FAILS: git checkout -- . and report the error verbatim instead
of working around it.
```

## 8. Perf landmines (2026-07-04 lag investigation — measured, not guessed)

- **NEVER `print()` in per-frame battle code.** Four [Path] debug prints firing
  per blocked unit per frame cost ~45ms/frame at 29 units. Gate behind a
  `const *_DEBUG := false` (see PATH_DEBUG in auto_battle_manager.gd).
- **NEVER rebuild Control lists per unit-action.** Mark dirty, let main_game's
  4Hz throttle repaint, and early-return from rebuilders when
  `not container.is_visible_in_tree()`. The old per-action rebuilds cost
  100-165ms/frame at 15v14.
- Verify perf claims with `godot --headless res://scenes/perf_probe.tscn`
  (forces 15v14 in the real main_game scene, prints avg/p95/max frame ms).
- After ANY UI refactor run `godot --headless res://scenes/ui_smoke.tscn`
  (drives details panel/tooltips/sidebar paths the boot smoke never touches);
  must print `UI_SMOKE: ALL PASS`.
- F3 in-game toggles the FPS/frame-ms/node-count overlay.
