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
#   Enemy can be an explicit list too:  --enemy=goblin:3,orc_brute:5,hill_giant:4
#   Optional: --out=user://arena_result.json  --max-sim-seconds=120
#             --difficulty=easy|normal|hard (wave enemies only)
#             --element=FIRE (team-wide hero element, default NORMAL)
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
	"SEAR":      {"passive": "fire trail only spawns while moving"},
	"RUSH":      {"passive": "momentum builds from movement"},
	"HEADHUNTER": {"passive": "crit logic lives inside attack() — see on_hit"},
	"SHAUNA":    {"passive": "kite logic reacts to enemy proximity while moving"},
	"STITCH":    {"passive": "Loose Threads reacts to a linked ally taking damage"},
	"goblin": {"passive": "no kit yet"}, "goblin_archer": {"passive": "no kit yet"},
	"goblin_shaman": {"passive": "no kit yet"}, "orc_brute": {"passive": "no kit yet"},
	"slime": {"passive": "no kit yet"}, "skeleton": {"passive": "no kit yet"},
	"rat": {"passive": "no kit yet"}, "hill_giant": {"passive": "no passive by design"},
	"triarch": {"passive": "phase mechanics live in die(), not passives"},
	"khagan": {"passive": "phase mechanics live in die(), not passives"},
	"stat_stealer": {"passive": "kit is skill+ult only"},
}

func _ready() -> void:
	# Defer the run one frame so the tree is fully up.
	await get_tree().process_frame
	var args := _parse_args()
	var mode: String = args.get("mode", "probe")
	var result: Dictionary
	match mode:
		"probe":
			result = await _run_probe(args)
		"sim":
			result = await _run_sims(args)
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

func _on_arena_unit_died(u) -> void:
	if mgr:
		mgr.player_units.erase(u)
		mgr.enemy_units.erase(u)
	if grid and u and is_instance_valid(u):
		grid.remove_unit(u.grid_position)

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

# ── Team / enemy spec parsing ─────────────────────────────────────────────────

func _class_from_name(name: String) -> int:
	var keys: PackedStringArray = UnitBase.UnitClass.keys()
	var idx: int = keys.find(name.to_upper())
	return idx   # -1 if unknown (enum values are contiguous 0..N here)

func _element_from_name(name: String) -> int:
	var keys: PackedStringArray = UnitBase.Element.keys()
	var idx: int = keys.find(name.to_upper())
	return maxi(idx, 0)

# "SABLE:3,NEMI:2" → hero units with (seeded) recruit rolls, like real recruits.
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
		var u: VisualUnit = UnitFactory.create_unit(cls, element, true)
		UnitFactory.apply_recruit_rolls(u, UnitFactory.generate_recruit_rolls())
		if lvl > 1: u.set_level(lvl)
		out.append(u)
	return out

# "wave:12[:difficulty]" or "goblin:3,orc_brute:5" → enemy units (unplaced).
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

# Mirrors main_game._generate_wave_spec using the shared WaveScaler statics.
func _spawn_wave(round: int, difficulty: int) -> Array:
	var out: Array = []
	if WaveScaler.is_boss_round(round):
		var placed: Array = WaveScaler.build_boss_formation(round, difficulty, grid.grid_width)
		var boss_code: String = WaveScaler.boss_code_for(round)
		for entry: Dictionary in placed:
			var u: VisualUnit = EnemyFactory.create_by_code(entry["code"])
			if u == null: continue
			var lvl: int = WaveScaler.boss_level(round) if entry["code"] == boss_code \
					else WaveScaler.enemy_level_for_round(round, false)
			if lvl > 1: u.set_level(lvl)
			out.append(u)
		return out
	if WaveScaler.is_elite_round(round):
		var code: String = WaveScaler.ELITE_POOL[randi() % WaveScaler.ELITE_POOL.size()]
		var placed: Array = WaveScaler.build_elite_formation(round, difficulty, grid.grid_width, code)
		for entry: Dictionary in placed:
			var u: VisualUnit = EnemyFactory.create_by_code(entry["code"])
			if u == null: continue
			var lvl: int = WaveScaler.elite_level(round) if entry["code"] in WaveScaler.ELITE_POOL \
					else WaveScaler.enemy_level_for_round(round, false)
			if lvl > 1: u.set_level(lvl)
			out.append(u)
		return out
	var formation: Array = WaveScaler.build_formation(round, difficulty, grid.grid_width)
	if formation.is_empty():
		# Procedural round (11+): random hero-class enemies with biased rolls.
		var base_count: int = mini(3 + (round - 1) * 2, 10)
		var count: int = WaveScaler.procedural_count(base_count, difficulty)
		for i in range(count):
			var u: VisualUnit = UnitFactory.create_random_class_unit(false)
			var bias: float = WaveScaler.enemy_roll_bias(round)
			UnitFactory.apply_recruit_rolls(u, UnitFactory.generate_recruit_rolls(bias))
			var lvl: int = WaveScaler.enemy_level_for_round(round, i == count - 1)
			if lvl > 1: u.set_level(lvl)
			out.append(u)
		return out
	for entry: Dictionary in formation:
		var u: VisualUnit = EnemyFactory.create_by_code(entry["code"])
		if u: out.append(u)
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
	var element: int = _element_from_name(args.get("element", "NORMAL"))
	var difficulty: int = {"easy": 0, "normal": 1, "hard": 2}.get(
			String(args.get("difficulty", "easy")).to_lower(), 0)

	var run_results: Array = []
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
			if not _place_player(u): push_error("no room for player unit")
		for u in enemies:
			_wire_unit(u)
			if not _place_enemy(u): push_error("no room for enemy unit")
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
		run_results.append({
			"run": i, "seed": base_seed + i,
			"outcome": "stall" if stalled else ("win" if player_won else "loss"),
			"sim_seconds": snappedf(_sim_elapsed, 0.1),
			"team": _unit_stats(team),
			"survivors_player": mgr.player_units.size(),
			"survivors_enemy": mgr.enemy_units.size(),
		})
		await _teardown_env()
	if stalls > 0:
		_had_failures = true   # a stall is always a bug worth looking at
	return {
		"mode": "sim", "team": team_spec, "enemy": enemy_spec,
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
			"level": u.level, "alive": u.current_hp > 0 and not u._is_dying,
			"hp_pct": snappedf(float(u.current_hp) / maxf(float(u.max_hp), 1.0), 0.01),
			"damage_dealt": u.damage_dealt,
			"healing_done": u.combat_healing_done,
			"kills": u.kill_count,
		})
	return out

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
		var r: Dictionary = await _probe_one(
			func(): return UnitFactory.create_unit(cls, UnitBase.Element.NORMAL, true),
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
	subject.take_damage(int(subject.max_hp * 0.65), UnitBase.Element.NORMAL, d_near)
	ally.take_damage(25000, UnitBase.Element.NORMAL, d_near)
	if subject_is_player:
		ally3.take_damage(99999999, UnitBase.Element.NORMAL, d_near)  # → fallen_allies
	subject.current_mana = subject.max_mana
	subject.skill_cd_time = 0.0
	subject.target_unit = d_near

	report["skill_name"] = subject.skill_name
	report["ultimate_name"] = subject.ultimate_name

	# ── Passive (3 simulated seconds of _tick_passive) ──
	var before: Dictionary = _world_snapshot()
	for i in range(30):
		if not is_instance_valid(subject) or subject._is_dying: break
		mgr._tick_passive(subject, opponents, allies, 0.1)
	report["passive"] = _diff_report(before, _world_snapshot(), label, "passive")

	# ── On-hit passives (subject attacks the near dummy, real attack flow).
	#    Ranged attacks spawn a projectile that lands a few frames later, so
	#    every phase settles before its after-snapshot (mgr stays paused, so
	#    nothing else acts during the settle — only projectiles/frees process).
	before = _world_snapshot()
	subject.attack(d_near)
	mgr._apply_on_hit_passives(subject, d_near, opponents)
	await _settle()
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
		await _settle()
		report["skill"] = _diff_report(before, _world_snapshot(), label, "skill")

	# ── Ultimate ──
	if not (subject and is_instance_valid(subject)) or subject._is_dying:
		pass   # error already recorded above
	elif subject.ultimate_name == "" and kind == "enemy":
		report["ultimate"] = {"status": "NO_KIT", "changes": []}
	else:
		before = _world_snapshot()
		mgr._use_ultimate(subject, opponents, allies)
		await _settle()
		report["ultimate"] = _diff_report(before, _world_snapshot(), label, "ultimate")

	await _teardown_env()
	return report

# Let in-flight projectiles land and queued frees process. The battle manager
# is paused during probes, so no unit acts autonomously during the settle.
func _settle(frames: int = 20) -> void:
	for i in range(frames):
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
			"stun": u.stun_time > 0.0, "burn": u.burn_time > 0.0,
			"slow": u.slow_time > 0.0, "root": u.root_time > 0.0,
			"taunt": u.taunt_time > 0.0, "weak": u.weakened_time > 0.0,
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
			"linked": u.link_partner != null,
			"puppet": u.puppet_time > 0.0,
			"ult_charge": u.ultimate_charge,
			"presence": u.get_meta("presence_bonus", 0.0),
			"resonance": u.has_meta("resonance_buffed") or u.has_meta("resonance_debuffed"),
		}
	if mgr:
		snap["__mgr__"] = {
			"storms": mgr.storms.size(), "thorns": mgr.thorns_time > 0.0,
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
