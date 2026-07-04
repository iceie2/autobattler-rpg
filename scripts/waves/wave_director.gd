class_name WaveDirector
extends RefCounted
# ══════════════════════════════════════════════════════════════════════════════
# Wave direction (extracted from main_game.gd, 2026-07-04 refactor).
# Generates wave SPECS ({"type", "level", "pos"?} dicts) and creates the enemy
# units they describe. Deliberately scene-independent (RefCounted, all context
# passed as arguments) so main_game AND the arena harness share the exact same
# wave logic — before this, scripts/arena/arena_main.gd carried a hand-copied
# duplicate that could silently drift from the live game.
#
# What stays in main_game: placement (_place_at/_place_enemy), held-item rolls,
# signal wiring — anything that touches the scene tree.
# ══════════════════════════════════════════════════════════════════════════════

# Elite picks are locked once per round: the spec generator runs more than once
# per round (round-start formation preview, then again when Ready is pressed),
# and without the lock each call re-rolled independently — the elite shown on
# the grid could differ from the one that actually spawned. Instance state, so
# a fresh WaveDirector (new scene/new run) naturally starts clean.
var locked_elite_code_by_round: Dictionary = {}

# Generate a wave specification (not instantiated units).
# Returns an array of {"type": String, "level": int, "pos"?: Vector2i} entries.
func generate_wave_spec(round: int, difficulty: int, grid_width: int) -> Array:
	var spec: Array = []

	# ── Boss rounds (10 / 20 / 30): a scaled boss + escalating adds. ──
	if WaveScaler.is_boss_round(round):
		var placed: Array = WaveScaler.build_boss_formation(round, difficulty, grid_width)
		var boss_lvl: int = WaveScaler.boss_level(round)
		var boss_code: String = WaveScaler.boss_code_for(round)
		for entry: Dictionary in placed:
			var code: String = entry["code"]
			var t: String = EnemyFactory.CODE_TO_TYPE.get(code, "")
			if t == "":
				continue
			var lvl: int = boss_lvl if code == boss_code \
					else WaveScaler.enemy_level_for_round(round, false)
			spec.append({"type": t, "level": lvl, "pos": entry["pos"]})
		return spec

	# ── Elite rounds (5 / 15 / 25): a mini-boss + light fodder support. ──
	if WaveScaler.is_elite_round(round):
		if not locked_elite_code_by_round.has(round):
			locked_elite_code_by_round[round] = \
					WaveScaler.ELITE_POOL[randi() % WaveScaler.ELITE_POOL.size()]
		var elite_code: String = locked_elite_code_by_round[round]
		var placed: Array = WaveScaler.build_elite_formation(round, difficulty, grid_width, elite_code)
		var elite_lvl: int = WaveScaler.elite_level(round)
		for entry: Dictionary in placed:
			var code: String = entry["code"]
			var t: String = EnemyFactory.CODE_TO_TYPE.get(code, "")
			if t == "":
				continue
			var lvl: int = elite_lvl if code in WaveScaler.ELITE_POOL \
					else WaveScaler.enemy_level_for_round(round, false)
			spec.append({"type": t, "level": lvl, "pos": entry["pos"]})
		return spec

	var formation_data: Array = WaveScaler.build_formation(round, difficulty, grid_width)

	if formation_data.is_empty():
		# Procedural round (round 11+): scaled by difficulty.
		var base_count: int = mini(3 + (round - 1) * 2, 10)
		var count: int = WaveScaler.procedural_count(base_count, difficulty)
		for i in range(count):
			var is_last := (i == count - 1)
			var lvl := WaveScaler.enemy_level_for_round(round, is_last)
			spec.append({"type": "random", "level": lvl})
		return spec

	for entry: Dictionary in formation_data:
		var type: String = EnemyFactory.CODE_TO_TYPE.get(entry["code"], "")
		if type != "":
			spec.append({"type": type, "level": 1, "pos": entry["pos"]})
	return spec

# Create the enemy described by one wave-spec entry. "random" = procedural
# hero-class unit with round-biased recruit rolls; everything else routes
# through EnemyFactory. Caller-side set_level ordering preserved (phase-boss
# stat snapshots depend on leveling AFTER factory creation — see CONVENTIONS).
func create_enemy_for_entry(entry: Dictionary, round: int) -> VisualUnit:
	var type: String = entry["type"]
	var lvl: int = entry.get("level", 1)
	var unit: VisualUnit = null
	if type == "random":
		unit = UnitFactory.create_random_class_unit(false)
		# Procedural enemy heroes get the same stat-roll grade system player
		# recruits have, biased upward by round (see WaveScaler.enemy_roll_bias).
		var bias: float = WaveScaler.enemy_roll_bias(round)
		UnitFactory.apply_recruit_rolls(unit, UnitFactory.generate_recruit_rolls(bias))
	else:
		unit = EnemyFactory.create_by_type(type)
	if unit and lvl > 1:
		unit.set_level(lvl)
	return unit

# Dry-run power estimate for a difficulty WITHOUT touching the battlefield —
# lets the difficulty panel show all 3 tiers' power side by side.
func estimate_wave_power(round: int, difficulty: int, grid_width: int) -> float:
	var spec: Array = generate_wave_spec(round, difficulty, grid_width)
	var total: float = 0.0
	for entry: Dictionary in spec:
		var unit: VisualUnit = create_enemy_for_entry(entry, round)
		if unit:
			total += WaveScaler.score_unit(unit)
			unit.free()
	return total
