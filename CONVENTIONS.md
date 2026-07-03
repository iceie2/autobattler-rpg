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

| Thing | File | Notes |
|---|---|---|
| Hero classes (enum, stats, growth, traits) | `unit_factory.gd` | `CLASS_BASE_STATS`, `CLASS_GROWTH_PER_LEVEL`, `TRAIT_CLASS_MAP` |
| Hero passives (per-frame) | `auto_battle_manager.gd` `_tick_passive` | aura-style ones throttle via `AURA_TICK_INTERVAL` meta pattern |
| Hero on-hit passives | `_apply_on_hit_passives` | ANT/COAL/EMBER/SABLE/ZOLT/LUMEN |
| On-being-hit passives | `propagate_damage_links` + `take_damage` | RIOT/CROSS/RIFT/STITCH-link |
| On-move triggers | `update_unit_movements` | STATIC Live Wire, SEAR fire trail, field hazards |
| Skills / ultimates | `_use_skill` / `_use_ultimate` dispatch | one match arm per class |
| Enemy factories | `enemy_factory.gd` | register new enemies in `CODE_TO_TYPE` + `create_by_type` + WaveScaler dicts (`CODE_ROLE`, `CODE_IS_LARGE`, `UNIT_POWER`) |
| Wave composition / difficulty | `wave_scaler.gd` | all statics — arena-testable |
| Boss rounds 10/20/30, elites 5/15/25 | `wave_scaler.gd` | `boss_code_for`, `ELITE_POOL` |
| Economy knobs | `ROUND_WIN_GOLD` (main_game), `gold_for_unit` (wave_scaler), RoundReward gold formula (round_reward.gd) | cut ~55% on 2026-07-02, do not buff without playtest data |
| Relics | `relic*.gd` | 25-relic pool, hooks throughout battle manager |
| Equipment | `equipment_*.gd` | combine = 3 same-rarity → next tier |
| Synergies | `synergy_data.gd`/`synergy_tracker.gd` | applied at battle start, reverted at end (`syn_backup` meta) |
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

- UI is built in code (StyleBoxFlat everywhere, no theme resource yet).
  Panels use the `_flat(bg, border, border_w, radius)` helper pattern.
- Monster/hero ability icons are PLANNED (assets incoming) — when building
  ability UI, always include an icon slot (TextureRect) next to the name,
  even if empty for now.
- Colors: dark navy panels (0.08-0.14 range bg), gacha grade colors for
  rarity, element colors via `get_element_color_hex`.

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
