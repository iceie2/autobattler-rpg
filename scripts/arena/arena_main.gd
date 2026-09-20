extends Node
# ══════════════════════════════════════════════════════════════════════════════
# ARENA HARNESS — headless battle simulator + per-class ability probe.
#
# Runs the REAL battle stack (BattleGrid + AutoBattleManager + real units from
# UnitFactory/EnemyFactory) inside a bare scene, no main_game.gd involved.
# This is the verification gate for balance and ability work: any change to a
# hero/monster kit should re-run the probe; any balance change should re-run
# sims and diff against the recorded baseline.
#
# USAGE (from autobattler-rpg/):
#   Probe every hero + enemy kit (skill / ult / passive fire-check):
#     godot --headless --fixed-fps 30 res://scenes/arena.tscn -- --mode=probe
#   Simulate battles:
#     godot --headless --fixed-fps 30 res://scenes/arena.tscn -- --mode=sim \
#       --team=SABLE:3,NEMI:3,RIOT:3 --enemy=wave:12 --runs=10 --seed=42
#   Power-rank every hero across level milestones (solo + paired sweep at each
#   level, then a combined ranked table averaged across levels):
#     godot --headless --fixed-fps 30 res://scenes/arena.tscn -- --mode=powerrank \
#       --levels=1,3,6,9 --runs=5
#   Enemy can be an explicit list too:  --enemy=goblin:3,orc_earth:5,hill_giant:4
#   Optional: --out=user://arena_result.json  --max-sim-seconds=120
#             --difficulty=normal|veteran|brutal (wave enemies only)
#             --element=FIRE (team-wide hero element override; default is each
#               hero's own fixed element)
#             --formation=default|front|clump|spread|split (sim mode only —
#               how the player team is laid out; see _PLAYER_FORMATIONS)
#
# Output: JSON printed between ARENA_RESULT_BEGIN / ARENA_RESULT_END lines
# (parse-friendly), plus optional --out file. Exit code 0 = ran clean,
# 1 = probe failures or sim errors.
#
# Design notes (landmines this deliberately avoids — see CONVENTIONS.md):
# - main_game.gd can't be instantiated outside its scene (autoload deps); the
#   arena re-implements ONLY its two battle-wiring duties: the died-handler
#   (array/grid cleanup) and the summon-handler (add to tree).
# - Factories return level-1 units; set_level() is applied by the CALLER
#   (phase-boss stat snapshots depend on this ordering).
# - Real frames drive the sim (projectiles/tweens/queue_free all need them);
#   --fixed-fps makes each frame a constant sim-step and uncaps wall speed.
# ══════════════════════════════════════════════════════════════════════════════

var grid: BattleGrid
var mgr: AutoBattleManager
var units_root: Node2D
var fx_root: Node2D
var proj_root: Node2D
var dmg_root: Node2D

var _sim_elapsed: float = 0.0
var _had_failures: bool = false

# Classes that are summon-fodder only — no kit of their own, probe skips them.
const MINION_CLASSES := [
	UnitBase.UnitClass.ZOMBIE, UnitBase.UnitClass.BAT, UnitBase.UnitClass.ANT,
]

# Kits whose silence in a given probe phase is EXPECTED because the trigger
# condition can't occur in the static probe env. status becomes EXPECTED
# (with the reason) instead of SILENT. Keyed by hero-class name / enemy type.
# Keep this honest: only add entries after reading the implementation.
const EXPECTED_SILENT := {
	"NECRO":     {"passive": "Soul Harvest needs living summons nearby"},
	"NEMI":      {"ultimate": "Tidal Wave now travels the board over several seconds (_tick_nemi_tidal_waves); damage lands on later ticks, not within the single force-cast frame the probe measures"},
	"SEAR":      {"passive": "fire trail only spawns while moving"},
	"RUSH":      {"passive": "momentum builds from movement"},
	"HEADHUNTER": {"passive": "crit logic lives inside attack() — see on_hit",
		"ultimate": "Snipe now channels for HEADHUNTER_AIM_DURATION before firing (headhunter_aim_time gate in _tick_unit); damage lands via _headhunter_fire_snipe on a later tick, not within the single force-cast frame the probe measures"},
	"SHAUNA":    {"passive": "kite logic reacts to enemy proximity while moving"},
	"STITCH":    {
		"passive": "Threadguard converts transferred and rupture damage into shield",
		"ultimate": "Unravel resolves through a timed 0.75s rupture sequence",
	},
	# Kits verified in another probe phase — the _tick_passive phase is
	# rightfully a no-op for them (audited 2026-07-03, see balance journal):
	"SABLE":     {"passive": "Momentum is on-hit — verified in on_hit phase"},
	"COAL":      {"passive": "Stoke charges are on-hit — verified in on_hit phase"},
	"EMBER":     {"passive": "burn application is on-hit — verified in on_hit phase"},
	"ZOLT":      {"passive": "on-hit shock — verified in on_hit phase"},
	"LUMEN":     {"passive": "on-hit refraction — verified in on_hit phase"},
	"RIOT":      {"passive": "retaliation — verified in on_being_hit phase"},
	"CROSS":     {"passive": "retaliation heal — verified in on_being_hit phase"},
	"RIFT":      {"passive": "Backlash damage-redirect — verified in on_being_hit phase"},
	"STATIC":    {"passive": "Live Wire triggers on being ATTACKED (propagate_damage_links) — untestable statically, verify in sim"},
	# SHEILDOR "Guardian Aura" + VAIL "Far Winds" were design gaps (UI names
	# with no implementation) until 2026-07-03 — both implemented; the probe
	# now REQUIRES them to fire, so no entries here.
	# Basic mobs (2026-07-24): each now has a signature passive too, but they're
	# all CONDITIONAL — packs, low HP, nearby allies, or on-hit/on-death triggers a
	# lone-unit 3s passive probe can't exercise, so "silent here" is correct. See
	# _tick_mob_passive / _apply_on_hit_passives / VisualUnit.die().
	"goblin": {"passive": "Pack Courage needs other Goblins within 3 tiles — silent for a lone probe unit"},
	"goblin_archer": {"passive": "Focus Fire is on-hit (see on_hit result), not a per-frame passive"},
	"goblin_shaman_normal": {"passive": "Spirit Link aura needs nearby allies — silent for a lone probe unit"},
	"goblin_shaman_fire": {"passive": "Spirit Link aura needs nearby allies — silent for a lone probe unit"},
	"goblin_shaman_water": {"passive": "Spirit Link aura needs nearby allies — silent for a lone probe unit"},
	"goblin_shaman_earth": {"passive": "Spirit Link aura needs nearby allies — silent for a lone probe unit"},
	"goblin_shaman_air": {"passive": "Spirit Link aura needs nearby allies — silent for a lone probe unit"},
	"goblin_shaman_lightning": {"passive": "Spirit Link aura needs nearby allies — silent for a lone probe unit"},
	"orc_normal": {"passive": "Bloodrage triggers below 50% HP — silent at full HP in probe"},
	"orc_fire": {"passive": "Bloodrage triggers below 50% HP — silent at full HP in probe"},
	"orc_water": {"passive": "Bloodrage triggers below 50% HP — silent at full HP in probe"},
	"orc_earth": {"passive": "Bloodrage triggers below 50% HP — silent at full HP in probe"},
	"orc_air": {"passive": "Bloodrage triggers below 50% HP — silent at full HP in probe"},
	"orc_lightning": {"passive": "Bloodrage triggers below 50% HP — silent at full HP in probe"},
	"slime_normal": {"passive": "Split is on-death — not observable in the passive probe window"},
	"slime_fire": {"passive": "Split is on-death — not observable in the passive probe window"},
	"slime_water": {"passive": "Split is on-death — not observable in the passive probe window"},
	"slime_earth": {"passive": "Split is on-death — not observable in the passive probe window"},
	"slime_air": {"passive": "Split is on-death — not observable in the passive probe window"},
	"slime_lightning": {"passive": "Split is on-death — not observable in the passive probe window"},
	"lizard_normal": {"passive": "Cold Blood regen only shows on a damaged unit; probe unit is at full HP"},
	"lizard_fire": {"passive": "Cold Blood regen only shows on a damaged unit; probe unit is at full HP"},
	"lizard_water": {"passive": "Cold Blood regen only shows on a damaged unit; probe unit is at full HP"},
	"lizard_earth": {"passive": "Cold Blood regen only shows on a damaged unit; probe unit is at full HP"},
	"lizard_air": {"passive": "Cold Blood regen only shows on a damaged unit; probe unit is at full HP"},
	"lizard_lightning": {"passive": "Cold Blood regen only shows on a damaged unit; probe unit is at full HP"},
	"bear_normal": {"passive": "Fury ramps with missing HP — silent at full HP in probe"},
	"bear_fire": {"passive": "Fury ramps with missing HP — silent at full HP in probe"},
	"bear_water": {"passive": "Fury ramps with missing HP — silent at full HP in probe"},
	"bear_earth": {"passive": "Fury ramps with missing HP — silent at full HP in probe"},
	"bear_air": {"passive": "Fury ramps with missing HP — silent at full HP in probe"},
	"bear_lightning": {"passive": "Fury ramps with missing HP — silent at full HP in probe"},
	"troll_normal": {"passive": "Regeneration only shows on a damaged unit; probe unit is at full HP"},
	"troll_fire": {"passive": "Regeneration only shows on a damaged unit; probe unit is at full HP"},
	"troll_water": {"passive": "Regeneration only shows on a damaged unit; probe unit is at full HP"},
	"troll_earth": {"passive": "Regeneration only shows on a damaged unit; probe unit is at full HP"},
	"troll_air": {"passive": "Regeneration only shows on a damaged unit; probe unit is at full HP"},
	"troll_lightning": {"passive": "Regeneration only shows on a damaged unit; probe unit is at full HP"},
	"windup_bot_normal": {"passive": "Overclock ramps the aspd meta over battle time; not reflected in the probe hp/dmg world-state diff"},
	"windup_bot_fire": {"passive": "Overclock ramps the aspd meta over battle time; not reflected in the probe hp/dmg world-state diff"},
	"windup_bot_water": {"passive": "Overclock ramps the aspd meta over battle time; not reflected in the probe hp/dmg world-state diff"},
	"windup_bot_earth": {"passive": "Overclock ramps the aspd meta over battle time; not reflected in the probe hp/dmg world-state diff"},
	"windup_bot_air": {"passive": "Overclock ramps the aspd meta over battle time; not reflected in the probe hp/dmg world-state diff"},
	"windup_bot_lightning": {"passive": "Overclock ramps the aspd meta over battle time; not reflected in the probe hp/dmg world-state diff"},
	"skeleton": {"passive": "Undying is on-death — not observable in the passive probe window"},
	"rat": {"passive": "Infestation needs 2+ other Rats within 2 tiles — silent for a lone probe unit"},
	"hill_giant": {"passive": "no passive by design"},
	"triarch": {"passive": "phase mechanics live in die(), not passives"},
	"khagan": {"passive": "phase mechanics live in die(), not passives"},
	"hydra_normal": {"passive": "head-regrowth gates on HYDRA_REGROW_INTERVAL (20s) — longer than this probe's fixed 3-second passive window, so it's legitimately silent here; see _hydra_regrow_tick"},
	"hydra_fire": {"passive": "head-regrowth gates on HYDRA_REGROW_INTERVAL (20s) — longer than this probe's fixed 3-second passive window, so it's legitimately silent here; see _hydra_regrow_tick"},
	"hydra_water": {"passive": "head-regrowth gates on HYDRA_REGROW_INTERVAL (20s) — longer than this probe's fixed 3-second passive window, so it's legitimately silent here; see _hydra_regrow_tick"},
	"hydra_earth": {"passive": "head-regrowth gates on HYDRA_REGROW_INTERVAL (20s) — longer than this probe's fixed 3-second passive window, so it's legitimately silent here; see _hydra_regrow_tick"},
	"hydra_air": {"passive": "head-regrowth gates on HYDRA_REGROW_INTERVAL (20s) — longer than this probe's fixed 3-second passive window, so it's legitimately silent here; see _hydra_regrow_tick"},
	"hydra_lightning": {"passive": "head-regrowth gates on HYDRA_REGROW_INTERVAL (20s) — longer than this probe's fixed 3-second passive window, so it's legitimately silent here; see _hydra_regrow_tick"},
	"stat_stealer": {"passive": "kit is skill+ult only"},
	# Elemental elites (2026-07-27).
	# Ant Hill: PROBE-ENVIRONMENT limitation, not a broken kit (traced 2026-07-27).
	# The probe parks the enemy subject at cell (4,5), but _spawn_ant requires a
	# free cell passing _in_team_zone(), which for an enemy means y < 4. All ten of
	# its candidate offsets from y=5 land at y >= 4, so no ant can ever spawn here.
	# In a real wave the hill is placed in rows 1-2 (Role.BOSS) and spawns normally.
	# Verify this one in sim, not probe.
	"ant_hill": {"passive": "spawn cells are gated by _in_team_zone (enemy y<4) and the probe places the subject at y=5 — no legal spawn cell exists in the probe env; verified in sim instead"},
	# on_being_hit is PROBABILISTIC here, not absent: the probe lands one test hit
	# and the Warden's evasion can simply dodge it, leaving no world-state change.
	# It therefore flickers between OK and SILENT depending on where the RNG
	# stream happens to sit — adding any enemy earlier in the roster (the 2026-07-28
	# decade bosses did exactly this) is enough to flip it. Listed so the gate
	# stays meaningful; if evasion is ever removed, delete this line.
	"gale_warden": {"passive": "evasion is a flat equipment_passives stat rolled inside take_damage, not a per-frame passive — its kit is the Cyclone Shove skill",
		"on_being_hit": "evasion can dodge the probe's single test hit — genuinely intermittent, not a missing kit"},
	"tempest_conduit": {"passive": "no passive by design — its whole kit is the Chain Discharge skill (verified in the skill phase)"},
	"mirrorplate_warden": {"passive": "Mirrorplate is a reactive reflect read off the mob_reflect meta in propagate_damage_links — verified in the on_being_hit phase, not a per-frame passive"},
	# Beast tier (2026-07-24) — reuses orc_normal/bear_normal/hill_giant's exact
	# EXPECTED_SILENT reasons since these mobs reuse those same mob_passive keys.
	"ogre": {"passive": "Bloodrage (reused from Orc) triggers below 50% HP — silent at full HP in probe"},
	"minotaur": {"passive": "Savage Charge (reused from Bear's Fury) ramps with missing HP — silent at full HP in probe"},
	"gargoyle": {"passive": "Stone Skin (reused from Troll's Regeneration) only shows on a damaged unit; probe unit is at full HP"},
	"stone_golem": {"passive": "no passive by design"},
	# Earth-decade variety (2026-07-24, wave 31-40).
	"crystal_crab": {"passive": "Frenzied Clacking (reused from Bear's Fury) ramps with missing HP — silent at full HP in probe"},
	"root_walker": {"passive": "Nature's Blessing (reused from Goblin Shaman's Spirit Link) needs nearby allies — silent for a lone probe unit"},
	# Fire decade (2026-07-24, wave 41-50).
	"fire_giant": {"passive": "Forge Fury (reused from Orc's Bloodrage) triggers below 50% HP — silent at full HP in probe"},
	"hellhound": {"passive": "Hunting Pack (reused from Goblin's Pack Courage) needs other Hellhounds within 3 tiles — silent for a lone probe unit"},
	"ember_phoenix": {"passive": "Rekindle (reused from Troll's Regeneration) only shows on a damaged unit; probe unit is at full HP"},
	# Lightning decade (2026-07-24, wave 51-60).
	"storm_giant": {"passive": "Gathering Storm (reused from Wind-Up Bot's Overclock) ramps the aspd meta over battle time; not reflected in the probe hp/dmg world-state diff"},
	"storm_crow": {"passive": "Murder (reused from Goblin's Pack Courage) needs other Storm Crows within 3 tiles — silent for a lone probe unit"},
	# Air/Water decade anchors (2026-08-02, wave 11-20 / 21-30).
	"sky_wyvern": {"passive": "Wounded Dive (reused from Bear's Fury) ramps with missing HP — silent at full HP in probe"},
	"tidepool_horror": {"passive": "Deathgrip (reused from Goblin Archer's Focus Fire) is on-hit (see on_hit result), not a per-frame passive"},
	# on_being_hit added 2026-09-17: same probabilistic dodge already documented
	# for the Gale Warden. The Harpy's 12% Evasion can simply miss the probe's
	# single test hit, leaving no world-state change, so the gate reported an
	# intermittent phantom "1 silent" that moved with the RNG stream (the Warden's
	# own note already warns that the stream position alone is enough to flip it).
	"harpy": {"passive": "Windborne is a flat equipment_passives[\"Evasion\"] roll applied inside take_damage, not a per-frame passive — same shape as the Gale Warden's, which it foreshadows; its kit is the Talon Rake skill",
		"on_being_hit": "12% evasion can dodge the probe's single test hit — genuinely intermittent, not a missing kit"},
	"coral_husk": {"passive": "Slow Tide (reused from Wind-Up Bot's Overclock) ramps the aspd meta over battle time; not reflected in the probe hp/dmg world-state diff"},
	"gravekeeper": {"passive": "no per-frame passive by design — Grave Call is an on-DEATH hook on the OTHER side (gravekeeper meta → AutoBattleManager.gravekeeper_raise_shade, fired from VisualUnit.die()), and nothing dies in a passive probe window; verified instead by the dedicated shade test (raises detuned shades, caps at GRAVE_SHADE_MAX, shades never re-raise)"},
	"arcfang": {"passive": "Thunder Run fires on a ARCFANG_BLINK_INTERVAL (10s) timer — far longer than this probe's fixed 3-second passive window, so the first blink legitimately hasn't happened yet; verified instead by the dedicated blink test (2×2 body teleports beside the highest-damage hero, all 4 footprint cells stay registered)"},
	"emberhollow": {"passive": "its kit is the on-death revive gate (emberhollow_revive meta → AutoBattleManager.emberhollow_hearts_alive, checked in VisualUnit.die) — a passive window that never kills the subject can't see it; verified instead by the dedicated revive-gate test (revives at 50% with a Heart alive, stays down with both out, never twice)"},
	"ember_heart": {"passive": "no per-frame passive by design — its entire job is EXISTING, since Emberhollow's revive checks for a living Heart. Damage comes from the Cinder Spit skill (verified in the skill phase)"},
	"cloven_titan": {"passive": "its whole kit IS the on-death split (spawn_cloven_halves via the cloven_split meta in VisualUnit.die) — not observable in a passive window that never kills the subject, same as the slimes above; verified instead by the dedicated split test"},
	"skyrender": {"passive": "Cyclone Ascent opens with a SKYRENDER_GROUND_TIME (8s) grounded window — longer than this probe's fixed 3-second passive test, so the first ascent legitimately hasn't fired yet; verified instead by the wave-20 sim (melee-vs-ranged win-rate split)"},
}

# Set before add_child to force a mode without CLI args (tests use this).
var mode_override := ""

func _ready() -> void:
	# Defer the run one frame so the tree is fully up.
	await get_tree().process_frame
	var args := _parse_args()
	# Windowed launches (main menu ARENA button, or running the scene from the
	# editor) default to the interactive sandbox; headless CLI runs keep probe
	# as the default so every existing harness command is unchanged.
	var default_mode: String = "probe" if DisplayServer.get_name() == "headless" else "sandbox"
	var mode: String = mode_override if mode_override != "" else args.get("mode", default_mode)
	if mode == "sandbox":
		_build_sandbox()
		return   # interactive — no JSON dump, no quit
	var result: Dictionary
	match mode:
		"probe":
			result = await _run_probe(args)
		"sim":
			result = await _run_sims(args)
		"sweep":
			result = await _run_sweep(args)
		"powerrank":
			result = await _run_powerrank(args)
		"power":
			result = _run_power(args)
		"xpcurve":
			result = _run_xpcurve(args)
		"goldcurve":
			result = _run_goldcurve(args)
		"events":
			result = _run_events(args)
		"map":
			result = _run_map(args)
		_:
			result = {"error": "unknown mode '%s'" % mode}
			_had_failures = true
	var json := JSON.stringify(result, "  ")
	print("ARENA_RESULT_BEGIN")
	print(json)
	print("ARENA_RESULT_END")
	var out_path: String = args.get("out", "")
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f:
			f.store_string(json)
			f.close()
	get_tree().quit(1 if _had_failures else 0)

# Difficulty tiers were renamed 2026-08-07 (easy/normal/hard →
# normal/veteran/brutal). The rename SHIFTED meanings: "normal" used to be tier
# 1 and is now tier 0, so a stale `--difficulty=normal` in an old script or note
# would silently measure a different tier and quietly invalidate a comparison.
# Legacy names are therefore rejected LOUDLY rather than mapped.
const _DIFF_NAMES := {"normal": 0, "veteran": 1, "brutal": 2}
const _DIFF_LEGACY := {"easy": "normal", "medium": "veteran", "hard": "brutal"}

func _difficulty_from_args(args: Dictionary, fallback: String) -> int:
	var raw := String(args.get("difficulty", fallback)).to_lower()
	if _DIFF_NAMES.has(raw):
		return int(_DIFF_NAMES[raw])
	if _DIFF_LEGACY.has(raw):
		push_error(("arena: --difficulty=%s is a RETIRED tier name. Tiers are now "
			+ "normal/veteran/brutal; note that 'normal' shifted from tier 1 to "
			+ "tier 0, so do not blind-swap. You probably want '%s'.")
			% [raw, _DIFF_LEGACY[raw]])
		_had_failures = true
		return int(_DIFF_NAMES[_DIFF_LEGACY[raw]])
	push_error("arena: unknown --difficulty=%s (expected normal/veteran/brutal)" % raw)
	_had_failures = true
	return 0

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
		elif a.begins_with("--"):
			out[a.substr(2)] = "true"
	return out

# ── Environment lifecycle ─────────────────────────────────────────────────────

func _build_env() -> void:
	grid = BattleGrid.new()
	add_child(grid)
	units_root = Node2D.new();  add_child(units_root)
	fx_root    = Node2D.new();  add_child(fx_root)
	proj_root  = Node2D.new();  add_child(proj_root)
	dmg_root   = Node2D.new();  add_child(dmg_root)
	mgr = AutoBattleManager.new()
	add_child(mgr)
	mgr.initialize(grid, null)
	mgr.skill_effect_container = fx_root
	mgr.projectile_container = proj_root
	mgr.unit_summoned.connect(_on_arena_summon)

func _teardown_env() -> void:
	# Stop the sim FIRST so no _process tick runs against freed nodes.
	if mgr: mgr.battle_active = false
	for n in [mgr, units_root, fx_root, proj_root, dmg_root, grid]:
		if n and is_instance_valid(n):
			n.queue_free()
	mgr = null; grid = null; units_root = null
	fx_root = null; proj_root = null; dmg_root = null
	# Let queue_free actually process before the next run builds fresh state.
	await get_tree().process_frame
	await get_tree().process_frame

# Mirrors main_game's battle-wiring duties (minus economy/UI/loot):
func _wire_unit(u: VisualUnit) -> void:
	units_root.add_child(u)
	u.battle_manager = mgr
	u.damage_text_container = dmg_root
	u.died.connect(_on_arena_unit_died.bind(u))

# Death ledger for the current run (2026-08-07). A tester run showed the arena
# scoring a WIN for three level-1 heroes against the 970k-HP wave-100 Architect
# while the live game wiped a full team on the same fight — so "the enemy list
# emptied" is NOT trustworthy evidence that the player killed anything. Every
# death now records the HP the unit held when it left the board: a unit leaving
# with current_hp > 0 was removed by a mechanic, not killed, and that is a
# harness bug the sim must refuse to score. See _validate_run().
var _deaths: Array = []

func _on_arena_unit_died(u) -> void:
	if u and is_instance_valid(u):
		_deaths.append({
			"name": u.unit_name,
			"side": "player" if u.is_player_unit else "enemy",
			"hp_at_death": u.current_hp,
			"max_hp": u.max_hp,
		})
	if mgr:
		mgr.player_units.erase(u)
		mgr.enemy_units.erase(u)
	if grid and u and is_instance_valid(u):
		grid.purge_unit(u)

func _on_arena_summon(u: UnitBase) -> void:
	# Manager already appended it to the right army + placed it on the grid.
	units_root.add_child(u)
	u.damage_text_container = dmg_root
	u.died.connect(_on_arena_unit_died.bind(u))

# Place a unit at the first free cell scanning the given rows left→right.
func _place_in_rows(u: VisualUnit, rows: Array) -> bool:
	for y in rows:
		for x in range(grid.grid_width):
			var p := Vector2i(x, y)
			if grid.place_unit(u, p):
				u.grid_position = p
				var w: Vector2 = grid.grid_to_world(p)
				if u.cell_size == 2:
					w += Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
				u.position = w
				return true
	return false

func _place_player(u: VisualUnit) -> bool:
	return _place_in_rows(u, [grid.grid_height - 1, grid.grid_height - 2,
							  grid.grid_height - 3, grid.grid_height - 4])

func _place_enemy(u: VisualUnit) -> bool:
	return _place_in_rows(u, [0, 1, 2, 3])

# ── Player formations (sim mode, --formation=) ────────────────────────────────
# Added 2026-07-27 to answer a design question empirically: does WHERE the
# player puts their team actually change outcomes? Targeting is nearest-enemy
# (AutoBattleManager._choose_target), so geometry is the player's only implicit
# targeting lever — if these formations all win at the same rate, that lever is
# decorative and no boss mechanic can lean on it.
#
# Player zone is the bottom 4 rows (5-8 on the 9×9 grid); row 5 is the FRONT
# (closest to the enemy half), row 8 the back. Note the pre-existing default
# fills BACK-first, so an unspecified sim has the whole team hugging row 8.
const _FORMATION_ROWS := {
	"default": [8, 7, 6, 5],   # legacy behaviour — back rows first, left→right
	"front":   [5, 6, 7, 8],   # everyone shoved forward into contact
	"clump":   [6, 7, 5, 8],   # tight centre block (worst case for AoE/chains)
	"spread":  [5, 7, 6, 8],   # maximum separation (best case for AoE/chains)
	# Bottom-RIGHT corner (2026-08-03). Added while chasing the large-unit
	# "shuffles forever, never attacks" bug: a hero pinned here can only be
	# approached from the west/north, the two sides where a 2×2 unit's top-left
	# origin sits 2 cells away while its body is already flush. Worth keeping —
	# it's the harshest corner case for any footprint/reach work.
	"corner":  [8, 7, 6, 5],
}
# Column order per formation. "clump" packs around centre; "spread" takes every
# other column first so no two units start adjacent.
const _FORMATION_COLS := {
	"default": [0, 1, 2, 3, 4, 5, 6, 7, 8],
	"front":   [0, 1, 2, 3, 4, 5, 6, 7, 8],
	"clump":   [4, 3, 5, 2, 6, 1, 7, 0, 8],
	"spread":  [0, 2, 4, 6, 8, 1, 3, 5, 7],
	"corner":  [8, 7, 6, 5, 4, 3, 2, 1, 0],
}

# Cell order for a formation, as a flat list of grid positions.
func _formation_cells(formation: String) -> Array:
	var rows: Array = _FORMATION_ROWS.get(formation, _FORMATION_ROWS["default"])
	var cols: Array = _FORMATION_COLS.get(formation, _FORMATION_COLS["default"])
	var cells: Array = []
	for y in rows:
		for x in cols:
			cells.append(Vector2i(x, y))
	return cells

func _place_at(u: VisualUnit, p: Vector2i) -> bool:
	if not grid.place_unit(u, p):
		return false
	u.grid_position = p
	var w: Vector2 = grid.grid_to_world(p)
	if u.cell_size == 2:
		w += Vector2(grid.cell_size * 0.5, grid.cell_size * 0.5)
	u.position = w
	return true

# Lay out the whole player team. "split" is the role-aware formation a thinking
# player would build by hand — melee up front, ranged/casters behind — and is
# the real test of whether skilled placement beats the naive default.
func _place_team(team: Array, formation: String) -> void:
	if formation == "split":
		var melee: Array = []
		var ranged: Array = []
		for u in team:
			if u.attack_range <= 1: melee.append(u)
			else:                   ranged.append(u)
		_fill_cells(melee,  _cells_for_rows([5, 6], _FORMATION_COLS["clump"]))
		_fill_cells(ranged, _cells_for_rows([8, 7], _FORMATION_COLS["clump"]))
		return
	_fill_cells(team, _formation_cells(formation))

func _cells_for_rows(rows: Array, cols: Array) -> Array:
	var cells: Array = []
	for y in rows:
		for x in cols:
			cells.append(Vector2i(x, y))
	return cells

# Place units into the given cell order; anything left over falls back to the
# default row scan so an oversized team never silently loses members.
func _fill_cells(units: Array, cells: Array) -> void:
	var i := 0
	for u in units:
		var placed := false
		while i < cells.size():
			var p: Vector2i = cells[i]
			i += 1
			if _place_at(u, p):
				placed = true
				break
		if not placed and not _place_player(u):
			push_error("no room for player unit")

# ── Team / enemy spec parsing ─────────────────────────────────────────────────

func _class_from_name(name: String) -> int:
	var keys: PackedStringArray = UnitBase.UnitClass.keys()
	var idx: int = keys.find(name.to_upper())
	return idx   # -1 if unknown (enum values are contiguous 0..N here)

# ELEMENT_UNSET means "let each hero use its own fixed element" — see _spawn_team.
const ELEMENT_UNSET := -1

func _element_from_name(name: String) -> int:
	if name.is_empty():
		return ELEMENT_UNSET
	var keys: PackedStringArray = UnitBase.Element.keys()
	var idx: int = keys.find(name.to_upper())
	return maxi(idx, 0)

# "SABLE:3,NEMI:2" → hero units with (seeded) recruit rolls, like real recruits.
# element: an explicit team-wide override, or ELEMENT_UNSET to give every hero
# its own natural element. UNSET is the default since the recruitment element
# roll was removed (2026-07-31) — before that the harness forced everything to
# NORMAL, which after the element-identity rework (2026-08-02) meant every
# "per-element" sim was silently testing an all-Normal team.
func _spawn_team(spec: String, element: int) -> Array:
	var out: Array = []
	for token in spec.split(",", false):
		var parts: PackedStringArray = token.strip_edges().split(":")
		var cls: int = _class_from_name(parts[0])
		if cls < 0:
			push_error("Unknown hero class '%s'" % parts[0])
			_had_failures = true
			continue
		var lvl: int = int(parts[1]) if parts.size() > 1 else 1
		var elem: int = element if element != ELEMENT_UNSET else UnitFactory.element_for_class(cls)
		var u: VisualUnit = UnitFactory.create_unit(cls, elem, true)
		UnitFactory.apply_recruit_rolls(u, UnitFactory.generate_recruit_rolls())
		if lvl > 1: u.set_level(lvl)
		out.append(u)
	return out

# "wave:12[:difficulty]" or "goblin:3,orc_earth:5" → enemy units (unplaced).
func _spawn_enemies(spec: String, difficulty: int) -> Array:
	var out: Array = []
	if spec.begins_with("wave:"):
		var parts: PackedStringArray = spec.split(":")
		var round: int = int(parts[1])
		out = _spawn_wave(round, difficulty)
	else:
		for token in spec.split(",", false):
			var parts: PackedStringArray = token.strip_edges().split(":")
			var u: VisualUnit = EnemyFactory.create_by_type(parts[0])
			if u == null:
				push_error("Unknown enemy type '%s'" % parts[0])
				_had_failures = true
				continue
			var lvl: int = int(parts[1]) if parts.size() > 1 else 1
			if lvl > 1: u.set_level(lvl)
			out.append(u)
	return out

# Waves come from the SAME WaveDirector the live game uses (2026-07-04
# refactor) — this used to be a hand-copied mirror of main_game's spec logic
# that could silently drift. A fresh director per call keeps elite-round picks
# independent across runs (matches a fresh run's behaviour).
func _spawn_wave(round: int, difficulty: int) -> Array:
	var director := WaveDirector.new()
	var out: Array = []
	for entry: Dictionary in director.generate_wave_spec(round, difficulty, grid.grid_width):
		var u: VisualUnit = director.create_enemy_for_entry(entry, round)
		if u:
			out.append(u)
	return out

# ── SIM MODE ──────────────────────────────────────────────────────────────────

func _run_sims(args: Dictionary) -> Dictionary:
	var team_spec: String = args.get("team", "")
	var enemy_spec: String = args.get("enemy", "")
	if team_spec == "" or enemy_spec == "":
		_had_failures = true
		return {"error": "sim mode needs --team= and --enemy="}
	var runs: int = int(args.get("runs", "10"))
	var base_seed: int = int(args.get("seed", "1000"))
	var max_sim: float = float(args.get("max-sim-seconds", "120"))
	var element: int = _element_from_name(args.get("element", ""))
	var difficulty: int = _difficulty_from_args(args, "normal")
	var formation: String = String(args.get("formation", "default")).to_lower()
	var time_scale: float = float(args.get("time-scale", "1"))
	# --hero-cap=N lifts the fresh-profile hero level cap (default 10) so a sim
	# can field a real late-run team. Without it "--team=X:17" clamps to 10 and
	# every high-level result is a quiet lie. See Progression.hero_level_cap().
	Progression.hero_level_cap_override = int(args.get("hero-cap", "-1"))

	var run_results: Array = []
	var layout: Array = []
	var wins := 0
	var stalls := 0
	for i in range(runs):
		seed(base_seed + i)
		_build_env()
		var team: Array = _spawn_team(team_spec, element)
		var enemies: Array = _spawn_enemies(enemy_spec, difficulty)
		if team.is_empty() or enemies.is_empty():
			await _teardown_env()
			_had_failures = true
			return {"error": "empty team or enemy list — check specs"}
		for u in team:
			_wire_unit(u)
		_place_team(team, formation)
		# Snapshot the layout from the FIRST run only — _unit_stats() can't report
		# it afterwards (dead units are freed, so their grid_position is gone).
		if i == 0:
			for u in team:
				layout.append({"class": UnitBase.UnitClass.keys()[u.unit_class],
						"range": u.attack_range, "x": u.grid_position.x, "y": u.grid_position.y})
		_deaths = []
		var unplaced: Array = []
		for u in enemies:
			_wire_unit(u)
			# A dropped enemy used to only push_error and carry on — which scores
			# a free WIN, since the sim's verdict is "enemy list is empty". Large
			# (2×2 / 3×3) bodies are exactly the ones that fail to place, so the
			# boss rounds were the ones silently mis-scored. Fail the run instead.
			if not _place_enemy(u):
				push_error("no room for enemy unit: %s (cell_size %d)" % [u.unit_name, u.cell_size])
				unplaced.append(u.unit_name)
		mgr.set_time_scale(time_scale)
		mgr.start_battle()
		_sim_elapsed = 0.0
		while mgr.battle_active and _sim_elapsed < max_sim:
			await get_tree().process_frame
			_sim_elapsed += get_process_delta_time() * mgr.time_scale
		var stalled: bool = mgr.battle_active
		var player_won: bool = (not stalled) and mgr.enemy_units.is_empty() \
				and not mgr.player_units.is_empty()
		if stalled: stalls += 1
		elif player_won: wins += 1
		# Trust check (2026-08-07) — see _deaths. A "win" is only real if every
		# enemy that left the board was actually reduced to 0 HP and every enemy
		# was placed to begin with. Anything else is a harness artifact and is
		# reported as an explicit error, never as a result.
		var suspect: Array = []
		for d: Dictionary in _deaths:
			if String(d["side"]) == "enemy" and int(d["hp_at_death"]) > 0:
				suspect.append("%s left the board at %d/%d HP" % [
						d["name"], d["hp_at_death"], d["max_hp"]])
		if not unplaced.is_empty():
			suspect.append("enemies never placed: %s" % ", ".join(unplaced))
		if not suspect.is_empty():
			_had_failures = true

		run_results.append({
			"run": i, "seed": base_seed + i,
			"outcome": "invalid" if not suspect.is_empty() \
					else ("stall" if stalled else ("win" if player_won else "loss")),
			"invalid_reasons": suspect,
			"enemy_deaths": _deaths.filter(func(d): return String(d["side"]) == "enemy").size(),
			"sim_seconds": snappedf(_sim_elapsed, 0.1),
			"team": _unit_stats(team),
			"survivors_player": mgr.player_units.size(),
			"survivors_enemy": mgr.enemy_units.size(),
			# Per-hero first-contribution rows (2026-07-27) — the instrument for
			# the after-action report. Read BEFORE teardown; unlike _unit_stats
			# this survives heroes dying, since the manager snapshots it live.
			"after_action": mgr.after_action_rows(),
		})
		await _teardown_env()
	if stalls > 0:
		_had_failures = true   # a stall is always a bug worth looking at
	return {
		"mode": "sim", "team": team_spec, "enemy": enemy_spec,
		"formation": formation, "layout": layout,
		"runs": runs, "wins": wins, "losses": runs - wins - stalls,
		"stalls": stalls, "win_rate": snappedf(float(wins) / float(runs), 0.01),
		"results": run_results,
	}

func _unit_stats(units: Array) -> Array:
	var out: Array = []
	for u in units:
		if not (u and is_instance_valid(u)):
			out.append({"name": "?", "alive": false})
			continue
		out.append({
			"name": u.unit_name, "class": UnitBase.UnitClass.keys()[u.unit_class],
			"pos": [u.grid_position.x, u.grid_position.y],   # verify --formation actually landed
			"level": u.level, "alive": u.current_hp > 0 and not u._is_dying,
			"hp_pct": snappedf(float(u.current_hp) / maxf(float(u.max_hp), 1.0), 0.01),
			"damage_dealt": u.damage_dealt,
			"healing_done": u.combat_healing_done,
			"kills": u.kill_count,
		})
	return out

# ── POWER MODE ────────────────────────────────────────────────────────────────
# Battle-free difficulty dump: for each round in [from..to], build the REAL wave
# spec (WaveDirector — same levels, late-game mults and heavy-demotion the live
# game uses) and report body count + summed score_unit power. This is the
# instrument for the "fewer bodies, same power" retune — deterministic, no team,
# no calibration. Usage: -- --mode=power --from=1 --to=30 [--difficulty=normal|veteran|brutal]
func _run_power(args: Dictionary) -> Dictionary:
	var difficulty: int = _difficulty_from_args(args, "normal")
	var lo: int = int(args.get("from", "1"))
	var hi: int = int(args.get("to", "30"))
	var director := WaveDirector.new()
	var rows: Array = []
	for r in range(lo, hi + 1):
		var spec: Array = director.generate_wave_spec(r, difficulty, 9)
		var power: float = 0.0
		var bodies: int = 0
		var large: int = 0
		for entry: Dictionary in spec:
			var u: VisualUnit = director.create_enemy_for_entry(entry, r)
			if u:
				power += WaveScaler.score_unit(u)
				bodies += 1
				if u.cell_size >= 2:
					large += 1   # >= not ==, or the 3×3 Architect reports as small
				u.free()
		# Dossier fields (2026-07-27) — exactly what the prep-phase panel shows the
		# player, so the readout can be verified headlessly for all 100 rounds
		# instead of by clicking through the game.
		var profile: Dictionary = WaveScaler.threat_profile(spec)
		# WHICH bodies, not just how many. The counts alone can't answer "why does
		# that thing look wrong in the preview" — you need the roster.
		var codes: Dictionary = {}
		for entry: Dictionary in spec:
			var c: String = String(entry.get("code", entry.get("type", "?")))
			codes[c] = int(codes.get(c, 0)) + 1
		# What each distinct body in this wave is WORTH, and which one the map
		# draws as the node's silhouette. Without these the report can say a wave
		# came in light but not which body was mispriced, and the map's own
		# readout could not be checked headlessly at all.
		var prices: Dictionary = {}
		for c2: String in codes:
			prices[c2] = int(snappedf(director.score_code(c2, r), 1.0))
		rows.append({
			"round": r, "bodies": bodies, "large2x2": large,
			"power": int(snappedf(power, 1.0)),
			"name": WaveData.name_for(r),
			"roster": codes,
			"prices": prices,
			"lead": director.lead_of_spec(spec, r),
			"comp": "%d melee · %d ranged · %d support · %d large" % [
					profile["melee"], profile["ranged"], profile["support"], profile["large"]],
		})
	return {"mode": "power", "difficulty": difficulty, "rows": rows}

# ── XPCURVE MODE ──────────────────────────────────────────────────────────────
# Battle-free player-progression dump (2026-08-07). Board size IS player level
# (main_game._team_size_for_level), so the player-XP curve is the team-size dial
# — but nothing could measure where that curve actually lands over a full run,
# which is how the ceiling drifted out of spec twice. This walks the REAL wave
# specs, sums enemy xp_reward assuming full clears, and reports the level and
# team size the player would hold at each round.
#
# Assumes full clears (the design assumption for "most waves on Veteran/Brutal").
# Curve constants are args so a retune can be FITTED here before any file edit:
#   -- --mode=xpcurve --to=100 --difficulty=normal --growth=1.55 --xpbonus=500
func _run_xpcurve(args: Dictionary) -> Dictionary:
	var difficulty: int = _difficulty_from_args(args, "normal")
	var lo: int = int(args.get("from", "1"))
	var hi: int = int(args.get("to", "100"))
	# Defaults mirror the shipping constants so a bare run reports the STATUS QUO.
	var base: float = float(args.get("base", str(Balance.PLAYER_XP_BASE)))
	var growth: float = float(args.get("growth", str(Balance.PLAYER_XP_GROWTH)))
	var share: float = float(args.get("share", str(Balance.PLAYER_XP_SHARE)))
	# Crystal-tree player-XP nodes (%) and hero-slot nodes — the two dials that
	# separate a fresh account from a fully-invested one.
	var xpbonus: float = float(args.get("xpbonus", "0"))
	var slots: int = int(args.get("slots", "0"))
	var events: int = int(args.get("events", "0"))

	var director := WaveDirector.new()
	var xp: float = 0.0
	var to_level: float = base
	var level: int = 1
	var cum: float = 0.0
	var rows: Array = []
	var level_at: Dictionary = {}   # level -> first round reached
	for r in range(lo, hi + 1):
		var spec: Array = director.generate_wave_spec(r, difficulty, 9)
		var wave_xp: float = 0.0
		for entry: Dictionary in spec:
			var u: VisualUnit = director.create_enemy_for_entry(entry, r)
			if u:
				wave_xp += float(u.xp_reward)
				u.free()
		var gained: float = wave_xp * share * (1.0 + xpbonus / 100.0)
		cum += gained
		xp += gained
		# Level is uncapped (mirrors GameState.add_player_xp); only TEAM is clamped.
		while xp >= to_level:
			xp -= to_level
			level += 1
			to_level *= growth
			if not level_at.has(level):
				level_at[level] = r
		var team: int = mini(level + slots + events, Balance.MAX_TEAM_SIZE)
		rows.append({
			"round": r, "wave_xp": int(wave_xp), "gained": int(gained),
			"cum_xp": int(cum), "level": level, "to_next": int(to_level),
			"team": team,
		})
	return {
		"mode": "xpcurve", "difficulty": difficulty,
		"base": base, "growth": growth, "share": share,
		"xpbonus": xpbonus, "slots": slots, "events": events,
		"final_level": level, "final_team": rows[-1]["team"] if rows else 0,
		"level_at_round": level_at,
		"rows": rows,
	}

# ── GOLDCURVE MODE ──────────────────────────────────────────────────────────
# Mirrors _run_xpcurve's method for the gold economy (user's "gold price never
# scales" report). Walks every wave 1..100 with generate_wave_spec (no combat
# sim needed — battle-free), sums EXPECTED gold income per round using the same
# formula as WaveScaler.gold_drops_for_unit but with the coin-chance used as an
# expected value instead of randf() (so results are deterministic and repeatable
# across runs), plus ROUND_WIN_GOLD every round and crystal-tree gold nodes
# (Head Start flat/round, Bounty % chance/kill) as optional args. Reports
# cumulative gold and, for reference, cumulative HERO_COST if bought every round,
# so the two curves can be compared directly.
#   -- --mode=goldcurve --to=100 --difficulty=normal --headstart=10 --bounty=4
func _run_goldcurve(args: Dictionary) -> Dictionary:
	var difficulty: int = _difficulty_from_args(args, "normal")
	var lo: int = int(args.get("from", "1"))
	var hi: int = int(args.get("to", "100"))
	# Crystal-tree gold nodes, expressed in their catalogue units (levels), so a
	# fresh account (0,0) vs a maxed one (10,4) can both be measured.
	var headstart_levels: int = int(args.get("headstart", "0"))   # 0-10, +1 gold/round each
	var bounty_levels: int = int(args.get("bounty", "0"))         # 0-4, +25% bonus-coin chance each

	var director := WaveDirector.new()
	var cum_gold: float = 0.0
	var cum_hero_cost: int = 0
	var rows: Array = []
	for r in range(lo, hi + 1):
		var spec: Array = director.generate_wave_spec(r, difficulty, 9)
		var round_gold: float = 0.0
		for entry: Dictionary in spec:
			var u: VisualUnit = director.create_enemy_for_entry(entry, r)
			if u:
				round_gold += _expected_gold_for_unit(u, r, bounty_levels)
				u.free()
		round_gold += float(Balance.ROUND_WIN_GOLD)
		round_gold += float(headstart_levels)   # Head Start: +1 gold/round/level
		cum_gold += round_gold
		cum_hero_cost += Balance.HERO_COST
		rows.append({
			"round": r, "round_gold": round_gold, "cum_gold": int(cum_gold),
			"hero_cost": Balance.HERO_COST, "cum_hero_cost": cum_hero_cost,
			"affordable_heroes_this_round": int(round_gold / float(Balance.HERO_COST)),
			"surplus_vs_flat_cost": int(cum_gold) - cum_hero_cost,
		})
	return {
		"mode": "goldcurve", "difficulty": difficulty,
		"headstart_levels": headstart_levels, "bounty_levels": bounty_levels,
		"final_cum_gold": int(cum_gold), "final_cum_hero_cost": cum_hero_cost,
		"rows": rows,
	}

# ── MAP MODE ────────────────────────────────────────────────────────────────
# Generates a pile of run maps and asserts RunMap.validate() on every one, then
# reports what a player actually MEETS on an average walk.
#
# A map generator is exactly the kind of code that works for fifty seeds and
# then hands someone an unreachable node or a row with three identical fights,
# so the invariants (reachability, no crossing edges, two intensities per battle
# row, one merchant per biome, all ten waves present) are checked in bulk rather
# than eyeballed once. Rewards are NOT rolled here — structure is what's under
# test, and rolling would mint 30 throwaway items per map.
#   -- --mode=map                     (200 maps per biome, all 10 biomes)
#   -- --mode=map --maps=1000 --biome=3
func _run_map(args: Dictionary) -> Dictionary:
	var per_biome: int = int(args.get("maps", "200"))
	var only_biome: int = int(args.get("biome", "-1"))
	var biomes: Array = []
	if only_biome >= 0:
		biomes.append(only_biome)
	else:
		for b in range(Balance.VICTORY_ROUND / RunMap.WAVES_PER_BIOME):
			biomes.append(b)

	var violations: Array = []
	var generated: int = 0
	var type_counts: Dictionary = {}
	var tier_counts: Dictionary = {0: 0, 1: 0, 2: 0}
	var walk_lengths: Dictionary = {}
	var walk_battles: Dictionary = {}

	for b: int in biomes:
		for i in range(per_biome):
			var map := RunMap.generate(b, (b + 1) * 100000 + i + 1, false)
			generated += 1
			for v in map.validate():
				if violations.size() < 40:
					violations.append("biome %d seed %d: %s" % [b, i + 1, v])
			for row in map.rows:
				for n in row:
					var tn: String = RunMap.type_name(int(n["type"]))
					type_counts[tn] = int(type_counts.get(tn, 0)) + 1
					if int(n["type"]) == RunMap.NodeType.BATTLE:
						tier_counts[int(n["difficulty"])] = \
							int(tier_counts[int(n["difficulty"])]) + 1

			# Walk it greedily-at-random to prove a path exists end to end and
			# that it always fights exactly ten waves — the two-counter model's
			# central claim, checked rather than asserted in a comment.
			var steps: int = 0
			var battles: int = 0
			var node: Dictionary = {}
			while true:
				var options: Array = map.available_next()
				if options.is_empty():
					break
				node = options[randi() % options.size()]
				map.advance_to(String(node["id"]))
				steps += 1
				if RunMap.is_battle_node(node):
					battles += 1
				if steps > 50:
					violations.append("biome %d seed %d: walk did not terminate" % [b, i + 1])
					break
			walk_lengths[steps] = int(walk_lengths.get(steps, 0)) + 1
			walk_battles[battles] = int(walk_battles.get(battles, 0)) + 1
			# Every walk crosses one start plus ten fixed stages. Utility may
			# replace combat on ordinary stages; elite and boss remain mandatory.
			if steps != RunMap.WAVES_PER_BIOME + 1 and violations.size() < 40:
				violations.append("biome %d seed %d: walk took %d nodes, expected %d"
					% [b, i + 1, steps, RunMap.WAVES_PER_BIOME + 1])
			var floor_waves: int = 2
			if (battles > RunMap.WAVES_PER_BIOME or battles < floor_waves) 					and violations.size() < 40:
				violations.append("biome %d seed %d: walk fought %d waves, expected %d-%d"
					% [b, i + 1, battles, floor_waves, RunMap.WAVES_PER_BIOME])

	_had_failures = not violations.is_empty()
	return {
		"mode": "map",
		"maps_generated": generated,
		"biomes": biomes.size(),
		"violations": violations,
		"nodes_by_type": type_counts,
		"battle_nodes_by_tier": {"normal": tier_counts[0], "veteran": tier_counts[1],
			"brutal": tier_counts[2]},
		"walk_node_counts": walk_lengths,
		"walk_wave_counts": walk_battles,
	}

# ── EVENTS MODE ─────────────────────────────────────────────────────────────
# Static audit of the whole event catalog: every event × every choice × every
# grade its band can roll, at a sample of rounds. Asserts the catalog is
# internally consistent AND that every effect key it emits is one main_game
# actually implements (EventCatalog.EFFECT_VERBS) — the 2026-07-16 audit found
# three events whose text lied about their effects by reading them by hand, and
# that doesn't scale past ~30 events.
#
# Also prints the payout table (gold at C vs S, early vs late) so event economy
# can be eyeballed against the gold curve without playing.
#   -- --mode=events
#   -- --mode=events --rounds=1,25,75
func _run_events(args: Dictionary) -> Dictionary:
	var rounds: Array = []
	for tok in String(args.get("rounds", "1,10,50,100")).split(","):
		if tok.strip_edges() != "":
			rounds.append(int(tok))

	var errors: Array = []
	var warnings: Array = []
	var seen_ids: Dictionary = {}
	var rows: Array = []
	var defs: Array = EventCatalog.all_defs()

	for def: Dictionary in defs:
		var id: String = String(def.get("id", ""))
		if id == "":
			errors.append("a def has no id (title '%s')" % def.get("title", "?"))
			continue
		if seen_ids.has(id):
			errors.append("duplicate def id '%s'" % id)
		seen_ids[id] = true
		if String(def.get("title", "")) == "":
			errors.append("%s: empty title" % id)
		if String(def.get("desc", "")) == "":
			warnings.append("%s: empty description" % id)
		if int(def.get("weight", 0)) <= 0:
			errors.append("%s: weight must be > 0" % id)
		var choices: Array = def.get("choices", [])
		if choices.size() < 2:
			warnings.append("%s: only %d choice(s) — an event with one door isn't a decision"
				% [id, choices.size()])

		for ci in range(choices.size()):
			var ch: Dictionary = choices[ci]
			var where: String = "%s[%d]" % [id, ci]
			var kind: String = String(ch.get("kind", ""))
			if not kind in EventCatalog.KINDS:
				errors.append("%s: unknown kind '%s'" % [where, kind])
				continue
			var band: String = String(ch.get("band", EventGrade.DEFAULT_BAND))
			if not EventGrade.BANDS.has(band):
				errors.append("%s: unknown band '%s'" % [where, band])
				continue
			if String(ch.get("text", "")) == "":
				errors.append("%s: empty choice text" % where)
			if String(ch.get("preview", "")) == "":
				warnings.append("%s: no preview line — the button will read blank" % where)

			for r: int in rounds:
				var ctx: Dictionary = _event_probe_ctx(r)
				for grade: String in EventGrade.reel_pool(band):
					var res: Dictionary = EventCatalog.resolve_choice(ch, ctx, grade)
					var eff = res.get("effects", null)
					if not (eff is Dictionary):
						errors.append("%s @r%d/%s: effects is not a Dictionary" % [where, r, grade])
						continue
					if String(res.get("outcome", "")) == "":
						errors.append("%s @r%d/%s: empty outcome line" % [where, r, grade])
					for k in eff.keys():
						if not String(k) in EventCatalog.EFFECT_VERBS:
							errors.append("%s @r%d/%s: effect '%s' has no handler in main_game"
								% [where, r, grade, k])
					# Sanity on the two numbers a player feels most directly.
					if eff.has("gold") and int(eff["gold"]) == 0:
						warnings.append("%s @r%d/%s: gold effect resolves to 0" % [where, r, grade])
					if eff.has("hero_damage") and absf(float(eff["hero_damage"])) >= 1.0:
						errors.append("%s @r%d/%s: hero_damage would wipe the team" % [where, r, grade])

			# Payout table row: what this choice pays at its floor and ceiling.
			var pool: Array = EventGrade.reel_pool(band)
			var lo: String = String(pool[0])
			var hi: String = String(pool[pool.size() - 1])
			rows.append({
				"id": id, "choice": ci, "kind": kind, "band": band,
				"early_%s" % lo: EventCatalog.resolve_choice(ch, _event_probe_ctx(10), lo).get("outcome", ""),
				"early_%s" % hi: EventCatalog.resolve_choice(ch, _event_probe_ctx(10), hi).get("outcome", ""),
				"late_%s" % hi: EventCatalog.resolve_choice(ch, _event_probe_ctx(75), hi).get("outcome", ""),
			})

	# Eligibility sweep: which events can a PLAIN run (no flags, modest holdings)
	# actually see, and which are gated behind run state? A gated event isn't a
	# bug — but a gated event nobody can ever reach is.
	var reachable: Dictionary = {}
	for r in [1, 5, 10, 25, 50, 75, 100]:
		for def in EventCatalog.all_defs():
			if EventCatalog.is_eligible(def, _event_probe_ctx(r)):
				reachable[String(def.get("id", ""))] = true
	var gated: Array = []
	for def in defs:
		var gid: String = String(def.get("id", ""))
		if not reachable.has(gid):
			gated.append(gid)

	_had_failures = not errors.is_empty()
	return {
		"mode": "events",
		"events": defs.size(),
		"choices": rows.size(),
		"rounds_probed": rounds,
		"errors": errors,
		"warnings": warnings,
		"gated_behind_run_state": gated,
		"payouts": rows,
	}

# A middling run: enough gold/items/relics that holdings-gated events are
# eligible, no flags set (so callback events stay gated, which is correct —
# they're supposed to require an earlier choice).
func _event_probe_ctx(round_no: int) -> Dictionary:
	return {
		"round": round_no,
		"gold": 40 + round_no * 2,
		"team_size": 6, "team_max": 8, "bench": 2,
		"items": 4, "relics": 2, "dominant_element": 3,
		"flags": {},
	}

# EV version of WaveScaler.gold_drops_for_unit — same shape, but returns the
# expected value (float) instead of rolling randf(), and folds in the Bounty
# crystal-tree node (independent 25%/level chance at an extra coin on basic
# kills — see Progression.UPGRADES "gold_per_kill").
func _expected_gold_for_unit(unit: VisualUnit, round: int, bounty_levels: int) -> float:
	if unit.is_summoned:
		return 0.0
	if unit.is_boss:
		return float(Balance.BOSS_COIN_DROP)
	if unit.is_elite:
		return float(Balance.ELITE_COIN_DROP
				+ (1 if round >= Balance.ELITE_COIN_LATE_BONUS_ROUND else 0))
	# Fixed chance (2026-08-07: the ramp is gone from WaveScaler.gold_drops_for_unit
	# too — mirror it exactly here or this harness silently drifts from the game).
	var bonus_chance: float = clampf(float(bounty_levels) * 0.25, 0.0, 1.0)
	return Balance.COIN_CHANCE_BASE * (1.0 + bonus_chance)

# ── SWEEP MODE ────────────────────────────────────────────────────────────────
# Comparative kit-power measurement: every recruitable hero, level 3, run through
# two fixtures — (a) SOLO vs a small wave (raw solo strength; the user's "supports
# fare very poorly alone" signal), (b) PAIRED with a Riot tank anchor vs a medium
# wave (does the kit contribute when it has a frontline to work behind).
# Same seeds across heroes → differences are the hero, not the wave roll.

# Fixture difficulty is tuned so outcomes SPREAD (fixture v1 was so easy that
# 24/26 heroes hit 100% solo — useless for ranking). The pair wave is sized so
# the anchor ALONE loses most runs: a support's real value then shows up as
# win-rate lift over that baseline, not as damage (which undersells supports).
const SWEEP_SOLO_ENEMY := "goblin:4,goblin:4,goblin_archer:3"
const SWEEP_PAIR_ENEMY := "goblin:5,goblin:5,goblin_archer:4,goblin_shaman_fire:4"
const SWEEP_ANCHOR := "RIOT"

func _run_sweep(args: Dictionary) -> Dictionary:
	var runs: int = int(args.get("runs", "5"))
	var base_seed: int = int(args.get("seed", "5000"))
	var lvl: String = args.get("level", "3")
	var rows: Array = []
	# Baseline: how does the anchor fare completely alone vs the pair wave?
	var anchor_solo: Dictionary = await _run_sims({
		"team": "%s:%s" % [SWEEP_ANCHOR, lvl], "enemy": SWEEP_PAIR_ENEMY,
		"runs": str(runs), "seed": str(base_seed + 100), "max-sim-seconds": "90",
	})
	log_line("[sweep] anchor-alone baseline win=%.2f" % float(anchor_solo.get("win_rate", -1)))
	for cls in UnitFactory.get_all_classes():
		if cls in MINION_CLASSES:
			continue
		var cname: String = UnitBase.UnitClass.keys()[cls]
		# 60/90 sim-second caps: a solo fight that drags past 60s is already
		# "can't close a 1v4" — the stall itself is the data point.
		var solo: Dictionary = await _run_sims({
			"team": "%s:%s" % [cname, lvl], "enemy": SWEEP_SOLO_ENEMY,
			"runs": str(runs), "seed": str(base_seed), "max-sim-seconds": "60",
		})
		var paired: Dictionary = await _run_sims({
			"team": "%s:%s,%s:%s" % [cname, lvl, SWEEP_ANCHOR, lvl],
			"enemy": SWEEP_PAIR_ENEMY,
			"runs": str(runs), "seed": str(base_seed + 100), "max-sim-seconds": "90",
		})
		rows.append({
			"class": cname,
			"solo_win_rate": solo.get("win_rate", -1),
			"solo_stalls": solo.get("stalls", 0),
			"solo_avg": _sweep_averages(solo, cname),
			"paired_win_rate": paired.get("win_rate", -1),
			"paired_stalls": paired.get("stalls", 0),
			"paired_avg": _sweep_averages(paired, cname),
		})
		log_line("[sweep] %s solo=%.2f paired=%.2f" % [cname,
				float(solo.get("win_rate", -1)), float(paired.get("win_rate", -1))])
	return {"mode": "sweep", "runs_per_fixture": runs, "level": lvl,
			"solo_enemy": SWEEP_SOLO_ENEMY, "pair_enemy": SWEEP_PAIR_ENEMY,
			"anchor": SWEEP_ANCHOR,
			"anchor_alone_win_rate": anchor_solo.get("win_rate", -1),
			"rows": rows}

# Mean damage/healing/hp% for the SWEPT hero (not the anchor) across runs.
func _sweep_averages(sim_result: Dictionary, cname: String) -> Dictionary:
	var dmg := 0.0; var heal := 0.0; var hp := 0.0; var n := 0
	for run in sim_result.get("results", []):
		for u in run.get("team", []):
			if u.get("class", "") == cname:
				dmg += u.get("damage_dealt", 0)
				heal += u.get("healing_done", 0)
				hp += u.get("hp_pct", 0.0)
				n += 1
	if n == 0: return {}
	return {"dmg": int(dmg / n), "heal": int(heal / n),
			"end_hp_pct": snappedf(hp / n, 0.01)}

# ── POWER-RANK MODE ───────────────────────────────────────────────────────────
# Runs _run_sweep at every requested level milestone (default 1,3,6,9 — level 1
# is the recruit floor, the rest sample the growth curve without needing perk
# choices, which are player-driven and out of headless reach) and folds the
# per-level solo/paired win rates into one ranked table per hero, so "who's
# broken and at what point in progression" is a single command instead of N.
# NOTE: this only captures base stat growth from set_level() — it does NOT
# simulate perk-point choices from the level-up screen (those are player
# picks), so a hero whose real power depends heavily on a specific perk build
# will read weaker here than in actual play.
func _run_powerrank(args: Dictionary) -> Dictionary:
	var levels_str: String = args.get("levels", "1,3,6,9")
	var levels: Array = []
	for s in levels_str.split(","):
		var lvl := int(s.strip_edges())
		if lvl > 0:
			levels.append(lvl)
	if levels.is_empty():
		levels = [1, 3, 6, 9]

	var per_level: Dictionary = {}   # level (String) -> sweep result dict
	for lvl in levels:
		var sweep_args: Dictionary = args.duplicate()
		sweep_args["level"] = str(lvl)
		log_line("[powerrank] running sweep at level %d..." % lvl)
		per_level[str(lvl)] = await _run_sweep(sweep_args)

	# Fold per-level rows into one entry per class.
	var by_class: Dictionary = {}
	for lvl_key in per_level:
		for row in (per_level[lvl_key] as Dictionary).get("rows", []):
			var cname: String = row["class"]
			if not by_class.has(cname):
				by_class[cname] = {"class": cname, "by_level": {}}
			by_class[cname]["by_level"][lvl_key] = row

	var ranked: Array = []
	for cname in by_class:
		var entry: Dictionary = by_class[cname]
		var solo_sum := 0.0
		var paired_sum := 0.0
		var n := 0
		for lvl_key in entry["by_level"]:
			var row: Dictionary = entry["by_level"][lvl_key]
			solo_sum += float(row.get("solo_win_rate", 0.0))
			paired_sum += float(row.get("paired_win_rate", 0.0))
			n += 1
		var avg_solo: float = solo_sum / n if n > 0 else 0.0
		var avg_paired: float = paired_sum / n if n > 0 else 0.0
		entry["avg_solo_win_rate"] = snappedf(avg_solo, 0.01)
		entry["avg_paired_win_rate"] = snappedf(avg_paired, 0.01)
		# Paired weighted higher — solo strength alone rewards "can duo the
		# whole game," which is exactly the failure mode this mode exists to
		# catch, but paired is the more representative real-team scenario.
		entry["power_score"] = snappedf(avg_solo * 0.4 + avg_paired * 0.6, 0.01)
		ranked.append(entry)
	ranked.sort_custom(func(a, b): return a["power_score"] > b["power_score"])
	for i in range(ranked.size()):
		ranked[i]["rank"] = i + 1
		log_line("[powerrank] #%d %s  power=%.2f  (solo avg=%.2f, paired avg=%.2f)" % [
			i + 1, ranked[i]["class"], ranked[i]["power_score"],
			ranked[i]["avg_solo_win_rate"], ranked[i]["avg_paired_win_rate"]])

	return {"mode": "powerrank", "levels": levels, "ranked": ranked, "per_level": per_level}

func log_line(s: String) -> void:
	print(s)

# ── PROBE MODE ────────────────────────────────────────────────────────────────
# For every hero class and every enemy factory type: spawn it with dummies,
# force its passive / skill / ultimate, and diff observable world state.
# An empty diff = the ability did NOTHING observable = flagged.

func _run_probe(args: Dictionary) -> Dictionary:
	seed(int(args.get("seed", "7777")))
	var results: Array = []
	# Heroes — every recruitable class, probed from the player side.
	for cls in UnitFactory.get_all_classes():
		if cls in MINION_CLASSES:
			continue
		# Probed at the hero's OWN element (2026-08-02) — forcing NORMAL here meant
		# no hero ever applied its element signature, so the whole status layer was
		# invisible to the probe.
		var r: Dictionary = await _probe_one(
			func(): return UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true),
			true, UnitBase.UnitClass.keys()[cls], "hero")
		results.append(r)
	# Enemies — every factory type, probed from the enemy side.
	for type in EnemyFactory.CODE_TO_TYPE.values():
		var r: Dictionary = await _probe_one(
			func(): return EnemyFactory.create_by_type(type),
			false, type, "enemy")
		results.append(r)
	var fails := 0
	var warns := 0
	for r in results:
		for phase in ["skill", "ultimate", "passive", "on_hit", "on_being_hit"]:
			if r.get(phase, {}).get("status", "") == "SILENT":
				warns += 1
		if r.get("error", "") != "":
			fails += 1
	if fails > 0:
		_had_failures = true
	return {"mode": "probe", "probed": results.size(), "errors": fails,
			"silent_abilities": warns, "results": results}

func _probe_one(make_unit: Callable, subject_is_player: bool,
		label: String, kind: String) -> Dictionary:
	_build_env()
	var report := {"name": label, "kind": kind}

	var subject: VisualUnit = make_unit.call()
	if subject == null:
		await _teardown_env()
		return {"name": label, "kind": kind, "error": "factory returned null"}
	subject.is_player_unit = subject_is_player
	subject.set_level(3)   # mid-level so scaling abilities have real numbers

	# Dummies: one adjacent melee-range target, one at distance, two allies (one
	# stays alive so Link-style skills have a partner; one dies for revive ults).
	# Beefy so probe abilities don't one-shot them mid-diff.
	var d_near: VisualUnit = EnemyFactory.create_goblin()
	var d_far: VisualUnit  = EnemyFactory.create_goblin()
	var ally: VisualUnit   = EnemyFactory.create_goblin()
	var ally2: VisualUnit  = EnemyFactory.create_goblin()
	var ally3: VisualUnit  = EnemyFactory.create_goblin()
	for d in [d_near, d_far, ally, ally2, ally3]:
		d.max_hp = 50000; d.current_hp = 50000
		d.attack_damage = 1; d.movement_speed = 0
	d_near.is_player_unit = not subject_is_player
	d_far.is_player_unit = not subject_is_player
	ally.is_player_unit = subject_is_player
	ally2.is_player_unit = subject_is_player
	ally3.is_player_unit = subject_is_player
	d_near.unit_name = "DummyNear"; d_far.unit_name = "DummyFar"
	ally.unit_name = "DummyAlly"; ally2.unit_name = "DummyAlly2"
	ally3.unit_name = "DummyFallen"

	# Layout around mid-board: subject at (4,5); enemy dummies adjacent + 3 away;
	# allies adjacent. 2x2 subjects (hill giant etc.) auto-shift via place_unit.
	for pair in [[subject, Vector2i(4, 5)], [d_near, Vector2i(4, 4)],
			[d_far, Vector2i(4, 2)], [ally, Vector2i(3, 5)], [ally2, Vector2i(5, 6)],
			[ally3, Vector2i(3, 7)]]:
		var u: VisualUnit = pair[0]
		_wire_unit(u)
		if not grid.place_unit(u, pair[1]):
			# Cell blocked (2x2 overlap) — fall back to a row scan.
			var placed: bool = _place_player(u) if u.is_player_unit else _place_enemy(u)
			if not placed:
				await _teardown_env()
				return {"name": label, "kind": kind, "error": "placement failed"}
		else:
			u.grid_position = pair[1]
			u.position = grid.grid_to_world(pair[1])

	mgr.start_battle()
	mgr.paused = true   # freeze the sim; the probe drives everything directly

	var opponents: Array = mgr.enemy_units if subject_is_player else mgr.player_units
	var allies: Array = mgr.player_units if subject_is_player else mgr.enemy_units

	# Preconditions so conditional kits have something to react to:
	# subject well below half HP (frenzy thresholds sit at ~45%) + a recorded
	# damage source, a wounded ally (heal targets), and a fallen ally (revive
	# ults). ally2 stays at FULL health — Link-style skills need a healthy partner.
	# take_damage records the attacker (frenzy attribution) but resist/affinity
	# soften it unpredictably, so pin the final HP deterministically at 35%
	# (frenzy-style thresholds sit at ~45% of max).
	subject.take_damage(int(subject.max_hp * 0.2), UnitBase.Element.NORMAL, d_near)
	subject.current_hp = mini(subject.current_hp, int(subject.max_hp * 0.35))
	ally.take_damage(25000, UnitBase.Element.NORMAL, d_near)
	if subject_is_player:
		ally3.take_damage(99999999, UnitBase.Element.NORMAL, d_near)  # → fallen_allies
	subject.current_mana = subject.max_mana
	subject.skill_cd_time = 0.0
	subject.target_unit = d_near

	report["skill_name"] = subject.skill_name
	report["ultimate_name"] = subject.ultimate_name

	# ── Passive (normally 3 simulated seconds; Sheildor's first correctly
	# delayed Guardian Aura pulse requires crossing its stated 4s interval) ──
	var before: Dictionary = _world_snapshot()
	var passive_frames := 50 if subject.unit_class == UnitBase.UnitClass.SHEILDOR else 30
	for i in range(passive_frames):
		if not is_instance_valid(subject) or subject._is_dying: break
		mgr._tick_passive(subject, opponents, allies, 0.1)
	report["passive"] = _diff_report(before, _world_snapshot(), label, "passive")

	# ── On-hit passives (subject attacks the near dummy, real attack flow).
	#    Ranged attacks spawn a projectile that lands a few frames later, so
	#    every phase settles before its after-snapshot (mgr stays paused, so
	#    nothing else acts during the settle — only projectiles/frees process).
	before = _world_snapshot()
	subject.attack(d_near)
	# Sheildor's landed-hit package is deliberately queued to shield contact;
	# its manager-owned resolution invokes passives on that frame.
	if subject.unit_class != UnitBase.UnitClass.SHEILDOR:
		mgr._apply_on_hit_passives(subject, d_near, opponents)
	# 40 frames (not the default 20) — some ranged heroes now hold their
	# projectile at the muzzle for a beat before launch (PROJECTILE_MUZZLE_DELAY
	# in unit_base.gd, e.g. Headhunter's ~0.83s) so it leaves the gun on the
	# attack sheet's fire frame instead of the instant attack() fires. 20
	# frames @ 30fps (~0.67s) wasn't enough headroom for delay + travel time.
	await _settle(40)
	report["on_hit"] = _diff_report(before, _world_snapshot(), label, "on_hit")

	# ── On-being-hit passives (dummy attacks the subject: Riot/Cross retaliation,
	#    Stitch link propagation, thorns-style responses). Damage scales to what
	#    the subject can survive — it's already at ~35% HP from the preconditions.
	d_near.attack_damage = clampi(int(subject.current_hp * 0.4), 15, 300)
	before = _world_snapshot()
	d_near.attack(subject)
	await _settle()
	report["on_being_hit"] = _diff_report(before, _world_snapshot(), label, "on_being_hit")
	d_near.attack_damage = 1

	# ── Active skill ──
	if not (subject and is_instance_valid(subject)) or subject._is_dying:
		report["error"] = "subject died during probe preconditions"
	elif subject.skill_name == "":
		report["skill"] = {"status": "NO_KIT", "changes": []}
	else:
		subject.current_mana = subject.max_mana
		before = _world_snapshot()
		mgr._use_skill(subject, opponents, allies)
		# 60 frames = 2.0s of manager time. The default 20 (0.67s) predates the
		# move away from instant-damage skills: several signatures now telegraph
		# and then travel (the Lizard's Precision Shot aims for 0.85s BEFORE its
		# bolt even launches), and a settle shorter than the wind-up reports them
		# as silent — which would mean exempting the very abilities most worth
		# verifying. Widened so they are genuinely measured instead.
		await _settle(60)
		report["skill"] = _diff_report(before, _world_snapshot(), label, "skill")

	# ── Ultimate ──
	if not (subject and is_instance_valid(subject)) or subject._is_dying:
		pass   # error already recorded above
	elif subject.ultimate_name == "" and kind == "enemy":
		report["ultimate"] = {"status": "NO_KIT", "changes": []}
	else:
		before = _world_snapshot()
		mgr._use_ultimate(subject, opponents, allies)
		await _settle(30 if subject.unit_class == UnitBase.UnitClass.SHEILDOR else 20)
		report["ultimate"] = _diff_report(before, _world_snapshot(), label, "ultimate")

	await _teardown_env()
	return report

# Let in-flight projectiles land and queued frees process. The battle manager
# is paused during probes, so no unit acts autonomously during the settle.
func _settle(frames: int = 20) -> void:
	for i in range(frames):
		# The manager is deliberately paused during probes, so its normal _process
		# cannot advance manager-owned delayed abilities. Drive that clock here as
		# well as waiting for Node-owned projectiles/frees.
		if mgr:
			mgr._tick_global_effects(1.0 / 30.0)
		await get_tree().process_frame

# Snapshot every observable gameplay-relevant number in the env.
func _world_snapshot() -> Dictionary:
	var snap := {}
	var all_units: Array = (mgr.player_units + mgr.enemy_units) if mgr else []
	for u in all_units:
		if not (u and is_instance_valid(u)):
			continue
		snap[u.unit_name + "#" + str(u.get_instance_id())] = {
			"hp": u.current_hp, "mana": u.current_mana, "shield": u.current_shield,
			"dmg_dealt": u.damage_dealt, "healing": u.combat_healing_done,
			"pos": u.grid_position,
			# current_element is snapshotted (2026-07-27) so element SWAPS are
			# visible to the diff at all — without it the Aspect Devourer's whole
			# kit registered as SILENT despite firing correctly, and the Triarch/
			# Khagan/Hydra phase element changes were equally invisible.
			"element": u.current_element,
			"stun": u.stun_time > 0.0, "burn": u.burn_time > 0.0,
			"slow": u.slow_time > 0.0, "root": u.root_time > 0.0,
			"taunt": u.taunt_time > 0.0, "weak": u.weakened_time > 0.0,
			# Riptide (Drowned Maw) writes only this field, so without it here the
			# aura reads as a SILENT passive when it's actually working.
			"heal_cut": u.heal_cut_time > 0.0,
			# Same for the aloft state (Skyrender's Cyclone Ascent, and the
			# Architect's phase-0 reprise of it).
			"aloft": u.melee_untargetable_time > 0.0,
			"untargetable": u.untargetable_time > 0.0,
			"rapid": u.rapid_fire_time > 0.0, "overdrive": u.overdrive_time > 0.0,
			"aspd_buff": u.bonus_aspd_time > 0.0,
			"dmg_buff": u.outgoing_dmg_mult != 1.0,
			"spore": snappedf(u.spore_stacks, 0.1), "momentum": u.momentum_stacks,
			"drain": u.drain_time > 0.0,
			"atk": u.attack_damage, "magic": u.magic_power, "res": u.resistance,
			"aspd": snappedf(u.attack_speed, 0.001),
			"move": u.movement_speed, "range": u.attack_range,
			"crit_ch": snappedf(u.crit_chance, 0.001),
			"crit_dmg": snappedf(u.crit_damage, 0.01),
			"regen_bank": snappedf(u.hp_regen_accum, 0.01),
			"frenzy": u.frenzy_active,
			"stoke": u.stoke_charges,
			"meltdown": u.meltdown_time > 0.0,
			"linked": not u.link_group.is_empty(),
			"puppet": u.puppet_time > 0.0,
			"ult_charge": u.ultimate_charge,
			"presence": u.get_meta("presence_bonus", 0.0),
			"resonance": u.has_meta("resonance_buffed") or u.has_meta("resonance_debuffed"),
		}
	if mgr:
		snap["__mgr__"] = {
			"storms": mgr.storms.size(), "thorns": not mgr.bloom_fields.is_empty(),
			"grid_field": mgr.grid_field_time > 0.0,
			"fire_trail": mgr.fire_trail.size(),
			"n_player": mgr.player_units.size(), "n_enemy": mgr.enemy_units.size(),
			"fallen": mgr.fallen_allies.size(),
			"afterimage": mgr.afterimage_time > 0.0,
		}
	return snap

func _diff_report(a: Dictionary, b: Dictionary, label: String = "", phase: String = "") -> Dictionary:
	var changes: Array = []
	for key in b:
		if not a.has(key):
			changes.append("%s appeared" % key)
			continue
		for field in b[key]:
			if a[key].get(field) != b[key][field]:
				changes.append("%s.%s: %s -> %s" % [key, field, a[key].get(field), b[key][field]])
	for key in a:
		if not b.has(key):
			changes.append("%s removed" % key)
	if changes.size() > 12:
		changes = changes.slice(0, 12) + ["...and %d more" % (changes.size() - 12)]
	if changes.is_empty():
		var expected: Dictionary = EXPECTED_SILENT.get(label, {})
		if expected.has(phase):
			return {"status": "EXPECTED", "reason": expected[phase], "changes": []}
		return {"status": "SILENT", "changes": []}
	return {"status": "OK", "changes": changes}

# ══════════════════════════════════════════════════════════════════════════════
# SANDBOX MODE (2026-07-05, user request) — interactive tester reachable from
# the main menu's ARENA button. Same env/spawn plumbing as sim mode, but with
# a visible board, a matchup form, and no quit-on-finish. Windowed default;
# headless CLI default stays probe (see _ready).
# ══════════════════════════════════════════════════════════════════════════════

var _sand_team_edit: LineEdit
var _sand_element_edit: LineEdit
var _sand_enemy_edit: LineEdit
var _sand_diff_opt: OptionButton
var _sand_status: Label
var _sand_fight_btn: Button
var _sand_menu_btn: Button
var _sand_busy := false
var _sand_leaving := false

# ── Biome preview (2026-07-28) ─────────────────────────────────────────────
# Flipping through all 10 decades by actually playing to wave 91 just to see
# the art was the whole complaint — this shows whatever BackgroundLayer would
# draw at wave (idx*10+1) without touching the battle/fight flow at all.
# Labels mirror arena_props.py's DECADES list (that's the source of truth for
# decade→biome naming; keep the two in sync by hand if it ever changes).
const _SAND_BIOME_LABELS := [
	"Grassland", "Skyreach (Air)", "Tidewater (Water)", "Caverns (Earth)",
	"Ashlands (Fire)", "Stormreach (Lightning)", "Warfront", "The Wastes",
	"The Abyss", "Apex",
]
var _sand_bg: BackgroundLayer
var _sand_biome_idx := 0
var _sand_biome_lbl: Label

func _build_sandbox() -> void:
	# Background is added independently of _build_env()/FIGHT — it must be
	# visible (and switchable) whether or not a battle is running. Position
	# (0,0) matches BattleGrid's own default position, same coordinate space
	# the fight board uses once FIGHT is pressed.
	_sand_bg = BackgroundLayer.new()
	add_child(_sand_bg)
	_sand_bg.position = Vector2.ZERO
	_sand_bg.set_biome_from_round(1)

	# Camera centers the 9x9 board (990px, centered at 495,495) in the space
	# right of the form panel — screen-space UI is unaffected by the camera.
	var cam := Camera2D.new()
	cam.position = Vector2(325, 495)
	add_child(cam)
	cam.make_current()

	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(330, 0)
	canvas.add_child(panel)

	var mg := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mg.add_theme_constant_override(k, 12)
	panel.add_child(mg)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	mg.add_child(vb)

	vb.add_child(_sand_lbl("ARENA SANDBOX", 22, UITheme.TEXT_HEADER))

	vb.add_child(_sand_lbl("Biome preview", 16, UITheme.TEXT_HEADER))
	var biome_row := HBoxContainer.new()
	biome_row.add_theme_constant_override("separation", 6)
	vb.add_child(biome_row)
	var prev_biome_btn := Button.new()
	prev_biome_btn.text = "◀"
	UITheme.style_button(prev_biome_btn)
	prev_biome_btn.pressed.connect(_sandbox_cycle_biome.bind(-1))
	biome_row.add_child(prev_biome_btn)
	_sand_biome_lbl = _sand_lbl("", 14, UITheme.TEXT_BODY)
	_sand_biome_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sand_biome_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	biome_row.add_child(_sand_biome_lbl)
	var next_biome_btn := Button.new()
	next_biome_btn.text = "▶"
	UITheme.style_button(next_biome_btn)
	next_biome_btn.pressed.connect(_sandbox_cycle_biome.bind(1))
	biome_row.add_child(next_biome_btn)
	_sandbox_update_biome_label()

	vb.add_child(_sand_lbl("Team — HERO:level, one per unit", 13, UITheme.TEXT_BODY))
	_sand_team_edit = LineEdit.new()
	_sand_team_edit.text = "SABLE:3,RIOT:3"
	vb.add_child(_sand_team_edit)

	vb.add_child(_sand_lbl("Team element (NORMAL/FIRE/WATER/…)", 13, UITheme.TEXT_BODY))
	_sand_element_edit = LineEdit.new()
	_sand_element_edit.text = "NORMAL"
	vb.add_child(_sand_element_edit)

	vb.add_child(_sand_lbl("Enemy — wave:N  or  goblin:2,orc_earth:3", 13, UITheme.TEXT_BODY))
	_sand_enemy_edit = LineEdit.new()
	_sand_enemy_edit.text = "wave:5"
	vb.add_child(_sand_enemy_edit)

	vb.add_child(_sand_lbl("Difficulty (wave enemies only)", 13, UITheme.TEXT_BODY))
	_sand_diff_opt = OptionButton.new()
	for d in ["Easy", "Normal", "Hard"]:
		_sand_diff_opt.add_item(d)
	vb.add_child(_sand_diff_opt)

	_sand_fight_btn = Button.new()
	_sand_fight_btn.text = "FIGHT"
	UITheme.style_button(_sand_fight_btn)
	_sand_fight_btn.pressed.connect(_sandbox_fight)
	vb.add_child(_sand_fight_btn)

	_sand_status = _sand_lbl("Pick a matchup and hit FIGHT.", 14, UITheme.TEXT_BODY)
	_sand_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sand_status.custom_minimum_size = Vector2(300, 0)
	vb.add_child(_sand_status)

	_sand_menu_btn = Button.new()
	_sand_menu_btn.text = "Back to Menu"
	UITheme.style_button(_sand_menu_btn)
	_sand_menu_btn.pressed.connect(_on_sandbox_menu_pressed)
	vb.add_child(_sand_menu_btn)

# A fight may still be mid-flight (_sandbox_fight's loop awaits up to 300s of
# process_frame ticks). Freeing this scene out from under that coroutine — via
# an immediate change_scene_to_file — resumes it next frame against freed
# nodes (mgr, _sand_status, ...) and crashes the engine. Signal the loop to
# stop and wait for it to actually exit before tearing down / changing scenes.
func _on_sandbox_menu_pressed() -> void:
	if _sand_leaving:
		return
	_sand_leaving = true
	_sand_menu_btn.disabled = true
	if mgr and is_instance_valid(mgr):
		mgr.battle_active = false
	while _sand_busy:
		await get_tree().process_frame
	await _teardown_env()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _sand_lbl(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.body_font(size))
	l.add_theme_color_override("font_color", col)
	return l

func _sandbox_cycle_biome(delta: int) -> void:
	var n := _SAND_BIOME_LABELS.size()
	_sand_biome_idx = ((_sand_biome_idx + delta) % n + n) % n
	_sand_bg.set_biome_from_round(_sand_biome_idx * 10 + 1)
	_sandbox_update_biome_label()

func _sandbox_update_biome_label() -> void:
	var lo := _sand_biome_idx * 10 + 1
	_sand_biome_lbl.text = "%s\n(waves %d-%d)" % [_SAND_BIOME_LABELS[_sand_biome_idx], lo, lo + 9]

func _sandbox_fight() -> void:
	if _sand_busy:
		return
	_sand_busy = true
	_sand_fight_btn.disabled = true
	_sand_status.text = "Fighting…"
	if mgr:   # tear down the previous run's board
		await _teardown_env()
	_build_env()
	var element: int = _element_from_name(_sand_element_edit.text.strip_edges())
	var difficulty: int = _sand_diff_opt.selected
	var team: Array = _spawn_team(_sand_team_edit.text.strip_edges(), element)
	var enemies: Array = _spawn_enemies(_sand_enemy_edit.text.strip_edges(), difficulty)
	if team.is_empty() or enemies.is_empty():
		_sand_status.text = "Bad spec — team or enemy list came up empty. Hero names are class names (see View Classes); enemies are factory codes or wave:N."
		for u in team + enemies:
			if is_instance_valid(u):
				u.queue_free()
		await _teardown_env()
		_sand_busy = false
		_sand_fight_btn.disabled = false
		return
	for u in team:
		_wire_unit(u)
		if not _place_player(u): push_error("no room for player unit")
	for u in enemies:
		_wire_unit(u)
		if not _place_enemy(u): push_error("no room for enemy unit")
	mgr.start_battle()
	var t := 0.0
	while mgr and is_instance_valid(mgr) and mgr.battle_active and t < 300.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	if mgr and is_instance_valid(mgr):
		if mgr.battle_active:
			mgr.battle_active = false
			_sand_status.text = "Stalled — stopped after 300s."
		else:
			var won: bool = mgr.enemy_units.is_empty() and not mgr.player_units.is_empty()
			_sand_status.text = "%s  ·  %.0fs  ·  %d ally / %d enemy left" % [
					"VICTORY" if won else "DEFEAT", t,
					mgr.player_units.size(), mgr.enemy_units.size()]
	_sand_busy = false
	_sand_fight_btn.disabled = false
