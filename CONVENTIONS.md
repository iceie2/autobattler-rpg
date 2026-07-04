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
#    → must print "Battle round 1 started!" and no SCRIPT ERROR.

# 3. Ability probe (after touching ANY hero/monster kit):
"$GODOT" --headless --fixed-fps 30 res://scenes/arena.tscn -- --mode=probe
#    → JSON between ARENA_RESULT_BEGIN/END; "silent_abilities" must be 0.
#      If your new ability is legitimately untestable statically, add an
#      EXPECTED_SILENT entry (with an honest reason) in arena_main.gd.

# 4. Balance sim (after touching stats/numbers):
"$GODOT" --headless --fixed-fps 30 res://scenes/arena.tscn -- --mode=sim \
  --team=SABLE:3,RIOT:3 --enemy=wave:5 --runs=5 --seed=42
#    → compare win_rate/damage vs before your change.
```

A task is NOT done until the relevant checks above pass. Commit after each
verified task; never commit with a failing check.

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
| On-being-hit passives | `propagate_damage_links` + `take_damage` | RIOT/CROSS/RIFT/STITCH-link |
| On-move triggers | `update_unit_movements` | STATIC Live Wire, SEAR fire trail, field hazards |
| Skills / ultimates | `_use_skill` / `_use_ultimate` dispatch | one match arm per class |
| Enemy factories | `units/enemy_factory.gd` | register new enemies in `CODE_TO_TYPE` + `create_by_type` + WaveScaler dicts (`CODE_ROLE`, `CODE_IS_LARGE`, `UNIT_POWER`) |
| Wave composition / difficulty | `waves/wave_scaler.gd` | all statics — arena-testable |
| Boss rounds 10/20/30, elites 5/15/25 | `waves/wave_scaler.gd` (round numbers in `core/balance.gd`) | `boss_code_for`, `ELITE_POOL` |
| Economy knobs | `core/balance.gd` (values), formulas in `waves/wave_scaler.gd` + `economy/round_reward.gd` | cut ~55% on 2026-07-02, do not buff without playtest data |
| Relics | `relics/relic*.gd` | 25-relic pool, hooks throughout battle manager |
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
