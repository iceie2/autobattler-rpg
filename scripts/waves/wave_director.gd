class_name WaveDirector
extends RefCounted

# XP a demoted heavy-tier elite (G/AH/SS in a normal wave) awards. Capped to a
# strong-normal payout so a now-common Giant doesn't fountain XP like its
# round-5/15/25 elite form (130-200 xp) does. See create_enemy_for_entry.
const HEAVY_XP_CAP: int = 90

# Demoted heavies keep their elite SILHOUETTE (2×2, tanky) but not their elite
# STATLINE — "you already beat it, now it's a regular." Without this a lone
# level-scaled Hill Giant scores ~as much as an entire pre-retune wave, so any
# escort overshoots the difficulty target. 0.55 lands a Giant at roughly 4-5
# fodder-bodies of power: a real anchor, not a one-unit wave. Applied to the
# FULLY scaled stats (after level + late-mult) so it tracks the round curve.
const HEAVY_STAT_MULT: float = 0.6
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

# Generate a wave specification (not instantiated units).
# Returns an array of {"type": String, "level": int, "pos"?: Vector2i} entries.
# chosen_element: the player's pre-battle element pick for the wave-30 Hydra
# (a UnitBase.Element value; -1/unset defaults to Normal — see
# WaveScaler.boss_code_for). Irrelevant for every other round.
func generate_wave_spec(round: int, difficulty: int, grid_width: int, chosen_element: int = -1) -> Array:
	var spec: Array = []

	# ── Boss rounds (10 / 20 / 30): a scaled boss + escalating adds. ──
	if WaveScaler.is_boss_round(round):
		var placed: Array = WaveScaler.build_boss_formation(round, difficulty, grid_width, chosen_element)
		var boss_lvl: int = WaveScaler.boss_level(round)
		var boss_code: String = WaveScaler.boss_code_for(round, chosen_element)
		for entry: Dictionary in placed:
			var code: String = entry["code"]
			var t: String = EnemyFactory.CODE_TO_TYPE.get(code, "")
			if t == "":
				continue
			var lvl: int = boss_lvl if code == boss_code \
					else WaveScaler.enemy_level_for_round(round, false)
			spec.append({"type": t, "level": lvl, "pos": entry["pos"], "code": code})
		return spec

	# ── Elite rounds (5 / 15 / 25): a mini-boss + light fodder support. ──
	if WaveScaler.is_elite_round(round):
		var placed: Array = WaveScaler.build_elite_formation(round, difficulty, grid_width)
		var elite_lvl: int = WaveScaler.elite_level(round)
		for entry: Dictionary in placed:
			var code: String = entry["code"]
			var t: String = EnemyFactory.CODE_TO_TYPE.get(code, "")
			if t == "":
				continue
			var lvl: int = elite_lvl if code in WaveScaler.ELITE_POOL \
					else WaveScaler.enemy_level_for_round(round, false)
			spec.append({"type": t, "level": lvl, "pos": entry["pos"], "code": code})
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

	# Fixed waves 1-9 spawn at level 1 (their compositions carry the early curve).
	# Fixed waves 11+ ride the same level ramp the old procedural rounds used —
	# composition power AND unit level climb together (see WaveData's header).
	for entry: Dictionary in formation_data:
		var code: String = entry["code"]
		var type: String = EnemyFactory.CODE_TO_TYPE.get(code, "")
		if type == "":
			continue
		var lvl: int = 1 if round <= 10 else WaveScaler.enemy_level_for_round(round, false)
		# Heavy-tier demotion (2026-07-23): the round-5/15/25 elites (G/AH/SS) may
		# now recur as ordinary "heavy" anchors in later normal waves — cheaper
		# than a whole new enemy tier, and thematically "you beat it, now it's a
		# regular." Progression is linear within a run, so a wave-N comp can only
		# reference an elite whose own round (5/15/25) already passed. Flagged here,
		# demoted (no elite flag / no elite bounty) in create_enemy_for_entry.
		# "code" is carried through purely for readouts (WaveScaler.threat_profile
		# — the prep-phase wave dossier); nothing in unit creation reads it.
		var e: Dictionary = {"type": type, "level": lvl, "pos": entry["pos"], "code": code}
		if code in WaveScaler.ELITE_POOL:
			e["heavy"] = true
		spec.append(e)
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
	# Role badge tag (2026-07-27) — stamped from the wave CODE here because this
	# is the only place that still knows it (the spec's "type" has already lost
	# the elemental-variant grouping the role tables are keyed on). Purely
	# cosmetic; VisualUnit._setup_role_badge reads it. Same classifier the prep
	# panel's dossier uses, so badge and dossier can never disagree.
	if unit:
		var code: String = String(entry.get("code", ""))
		if code != "":
			unit.set_meta("role_tag", WaveScaler.role_tag_for_code(code))
	# Heavy-tier demotion: an elite creature (G/AH/SS) recurring as a normal wave
	# anchor keeps its statline/level scaling but sheds its elite identity — no
	# is_elite/is_boss flag (which would trigger the fixed elite coin bounty in
	# WaveScaler.gold_drops_for_unit) and no score-based crystal drop (gated via
	# the wave_heavy meta in WaveScaler.crystals_for_unit). XP is capped to a
	# strong-normal payout so a common Giant isn't an XP fountain.
	if unit and entry.get("heavy", false):
		unit.is_elite = false
		unit.is_boss  = false
		unit.gold_reward = 0
		unit.crystal_reward = 0
		unit.xp_reward = mini(unit.xp_reward, HEAVY_XP_CAP)
		unit.set_meta("wave_heavy", true)
	if unit and lvl > 1:
		unit.set_level(lvl)
	# Late-game stat multiplier (round 11+, see Balance) — applied AFTER
	# leveling so it scales the leveled stats. Keeps current/max HP ratio
	# (Khagan deliberately spawns at half HP).
	if unit and round > Balance.ENEMY_LATE_SCALE_START_ROUND:
		var hp_mult: float = Balance.enemy_late_hp_mult(round)
		var dmg_mult: float = Balance.enemy_late_dmg_mult(round)
		unit.max_hp        = maxi(1, int(unit.max_hp * hp_mult))
		unit.current_hp    = maxi(1, int(unit.current_hp * hp_mult))
		unit.attack_damage = maxi(1, int(unit.attack_damage * dmg_mult))
		unit.magic_power   = int(unit.magic_power * dmg_mult)
	# Heavy down-scale — applied LAST so it multiplies the fully round-scaled
	# stats (level + late-mult). Turns a boss-statline elite into a heavy anchor.
	if unit and entry.get("heavy", false):
		unit.max_hp        = maxi(1, int(unit.max_hp * HEAVY_STAT_MULT))
		unit.current_hp    = maxi(1, int(unit.current_hp * HEAVY_STAT_MULT))
		unit.attack_damage = maxi(1, int(unit.attack_damage * HEAVY_STAT_MULT))
		unit.magic_power   = int(unit.magic_power * HEAVY_STAT_MULT)
	return unit

# Dry-run power estimate for a difficulty WITHOUT touching the battlefield —
# lets the difficulty panel show all 3 tiers' power side by side.
func estimate_wave_power(round: int, difficulty: int, grid_width: int, chosen_element: int = -1) -> float:
	return score_spec(generate_wave_spec(round, difficulty, grid_width, chosen_element), round)

# Power of an ALREADY-generated spec. Split out from estimate_wave_power so the
# difficulty panel can score the exact spec the wave will use (main_game caches
# one per difficulty) instead of rolling a third independent one — the displayed
# power now matches the roster on the grid.
func score_spec(spec: Array, round: int) -> float:
	var total: float = 0.0
	for entry: Dictionary in spec:
		var unit: VisualUnit = create_enemy_for_entry(entry, round)
		if unit:
			total += WaveScaler.score_unit(unit)
			unit.free()
	return total
