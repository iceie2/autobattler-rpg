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

# ── SCORING THE BUDGET IN THE CURRENCY WE ACTUALLY MEASURE IN ─────────────────
# The difficulty budget used to be denominated in WaveScaler.UNIT_POWER — a hand
# set integer table written very early in the project. The THREAT number the
# player reads (and the arena reports) is score_unit() on INSTANTIATED units at
# the round's level. Those are two different currencies, so multiplying one
# never moved the other predictably. Measured over rounds 1-20 on 2026-09-19:
# nominal Veteran ×1.75 came out anywhere from ×1.17 to ×2.25, nominal Brutal
# ×3.5 from ×1.83 to ×5.37, and round 2 Brutal landed BELOW round 2 Veteran.
#
# They cannot be reconciled with a better constant table either: per-level growth
# is additive and PER CLASS (UnitBase.apply_stat_growth), and Balance's late
# multiplier scales HP and damage but not attack speed or resistance — so the
# ratio between any two units genuinely moves with the round.
#
# So the budget is priced by asking the real unit. This lives in WaveDirector
# rather than WaveScaler because instantiating is this layer's job; WaveScaler
# stays a pure static helper and receives the pricer as a Callable.
var _code_score_cache: Dictionary = {}    # "code:round" -> float

# What one body of `code` is worth at `round`, at the level it would actually
# spawn with. Mirrors generate_wave_spec's own level choice exactly — an elite on
# its home round is scored at elite_level, a boss at boss_level, everything else
# at the ordinary curve — or the price would not describe the unit that shows up.
func score_code(code: String, round: int) -> float:
	var key: String = "%s:%d" % [code, round]
	if _code_score_cache.has(key):
		return float(_code_score_cache[key])
	var score: float = 0.0
	var type_name: String = EnemyFactory.CODE_TO_TYPE.get(WaveScaler.original_code(code), "")
	if type_name != "":
		# The entry is built the SAME way the three branches of generate_wave_spec
		# build theirs. Anything less and the price describes a unit that never
		# spawns: pricing the Hill Giant at its elite statline while ordinary
		# waves spawn it demoted (HEAVY_STAT_MULT 0.6) made the budget overpay for
		# it by two thirds, and every Brutal wave that drew one came in 15-20%
		# under target — rounds 9, 11, 13, 14 and 16-19, all measured 2026-09-20.
		var entry: Dictionary = {"type": type_name, "code": code}
		if code.begins_with(WaveScaler.PAST_ELITE_PREFIX):
			entry["level"] = WaveScaler.past_elite_level(code, round)
			entry["past_elite"] = true
		elif WaveScaler.is_boss_round(round):
			entry["level"] = WaveScaler.boss_level(round) \
				if code == WaveScaler.boss_code_for(round) \
				else WaveScaler.enemy_level_for_round(round, false)
		elif WaveScaler.is_elite_round(round):
			entry["level"] = WaveScaler.elite_level(round) \
				if code in WaveScaler.ELITE_POOL or (code == "ANT" and WaveScaler.elite_code_for(round) == "AH") \
				else WaveScaler.enemy_level_for_round(round, false)
		else:
			# Ordinary wave: waves 1-10 spawn at level 1 (their compositions carry
			# the early curve), and a recurring elite is demoted to a heavy anchor.
			entry["level"] = 1 if round <= 10 \
				else WaveScaler.enemy_level_for_round(round, false)
			if code in WaveScaler.ELITE_POOL:
				entry["heavy"] = true
		var unit: VisualUnit = create_enemy_for_entry(entry, round)
		if unit:
			score = WaveScaler.score_unit(unit)
			unit.free()
	_code_score_cache[key] = score
	return score

# ── WHICH ONE BODY STANDS FOR THE WHOLE WAVE (the map node's silhouette) ──────
# The body type carrying the most TOTAL WEIGHT in the fight (its price times how
# many of it there are), priced by the same score the budget uses. score_unit
# already folds size in (a 2×2 gets ×2.5, the 3×3 Architect ×4.0), so a Giant
# outranks a goblin without any separate size rule.
#
# Two things this fixes, both owner-reported 2026-09-20:
#   * The old rule ranked by CELL SIZE, then head count, then whatever order the
#     authored table happened to list — so a wave-4 Veteran drew a goblin over a
#     Lizard, and even inside the base comp a lone Shaman lost to two goblins
#     despite being worth more.
#   * It read WaveData's authored base ONLY, so nothing a Veteran or Brutal tier
#     added could ever appear on the node. That was a deliberate trade when the
#     filler rolled fresh on every call (a card that changed each time you looked
#     is worse than one that under-sells), and it stopped being necessary the
#     moment the filler was pinned per run — this reads the REAL wave now, which
#     is the same wave the card's mini-board and the fight will show.
#
# Ties break on the code that sorts first, so the same wave always answers the
# same way rather than depending on Dictionary iteration order.
func lead_code(round: int, difficulty: int, wave_seed: int) -> String:
	return lead_of_spec(generate_wave_spec(round, difficulty, 9, -1, wave_seed), round)

# Same question asked of a spec you already have. Callers holding a spec must use
# THIS — regenerating with an unpinned seed answers about a different wave than
# the one in hand, which is exactly how the arena's first lead column came back
# naming bodies that were not in the roster beside it.
func lead_of_spec(spec: Array, round: int) -> String:
	var weights: Dictionary = {}
	for entry: Dictionary in spec:
		var code: String = String(entry.get("code", ""))
		var unit: VisualUnit = create_enemy_for_entry(entry, round)
		if unit:
			weights[code] = float(weights.get(code, 0.0)) + WaveScaler.score_unit(unit)
			unit.free()
	var best: String = ""
	var best_weight: float = -1.0
	for code: String in weights:
		# TOTAL WEIGHT, not the single biggest body (owner rule, 2026-09-20):
		# "1 enemy at 5000 power beats 2 at 2000 each but loses to 8 of 1k each."
		# What the node is warning you about is where the wave's mass actually
		# sits — a lone heavy in a swarm of goblins is not what kills you.
		var weight: float = float(weights[code])
		if weight > best_weight or (is_equal_approx(weight, best_weight) and code < best):
			best = code
			best_weight = weight
	return best
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
# wave_seed: the run's per-node pin for the Veteran/Brutal filler roll, minted by
# RunMap and carried on the node (see WaveScaler._filler_rng). It is the LAST
# parameter and defaults to 0 = "unpinned, roll freshly" on purpose: every
# existing caller — the arena harness, the tool checks, the pre-map save path —
# keeps its current meaning without being touched.
func generate_wave_spec(round: int, difficulty: int, grid_width: int,
		chosen_element: int = -1, wave_seed: int = 0) -> Array:
	var spec: Array = []

	# ── Boss rounds (10 / 20 / 30): a scaled boss + escalating adds. ──
	if WaveScaler.is_boss_round(round):
		var placed: Array = WaveScaler.build_boss_formation(round, difficulty, grid_width, chosen_element,
				wave_seed, score_code)
		var boss_lvl: int = WaveScaler.boss_level(round)
		var boss_code: String = WaveScaler.boss_code_for(round, chosen_element)
		for entry: Dictionary in placed:
			var code: String = entry["code"]
			var t: String = EnemyFactory.CODE_TO_TYPE.get(WaveScaler.original_code(code), "")
			if t == "":
				continue
			var lvl: int = boss_lvl if code == boss_code \
					else WaveScaler.enemy_level_for_round(round, false)
			spec.append({"type": t, "level": lvl, "pos": entry["pos"], "code": code})
		return _resolve_past_elites(spec, round)

	# ── Elite rounds (5 / 15 / 25): a mini-boss + light fodder support. ──
	if WaveScaler.is_elite_round(round):
		var placed: Array = WaveScaler.build_elite_formation(round, difficulty, grid_width,
				wave_seed, score_code)
		var elite_lvl: int = WaveScaler.elite_level(round)
		for entry: Dictionary in placed:
			var code: String = entry["code"]
			var t: String = EnemyFactory.CODE_TO_TYPE.get(WaveScaler.original_code(code), "")
			if t == "":
				continue
			var lvl: int = elite_lvl if code in WaveScaler.ELITE_POOL or code == "ANT" \
					else WaveScaler.enemy_level_for_round(round, false)
			spec.append({"type": t, "level": lvl, "pos": entry["pos"], "code": code})
		return _resolve_past_elites(spec, round)

	var formation_data: Array = WaveScaler.build_formation(round, difficulty, grid_width, wave_seed, score_code)

	if formation_data.is_empty():
		# Procedural round (round 11+): scaled by difficulty.
		var base_count: int = mini(3 + (round - 1) * 2, 10)
		var count: int = WaveScaler.procedural_count(base_count, difficulty)
		for i in range(count):
			var is_last := (i == count - 1)
			var lvl := WaveScaler.enemy_level_for_round(round, is_last)
			spec.append({"type": "random", "level": lvl})
		return _resolve_past_elites(spec, round)

	# Fixed waves 1-9 spawn at level 1 (their compositions carry the early curve).
	# Fixed waves 11+ ride the same level ramp the old procedural rounds used —
	# composition power AND unit level climb together (see WaveData's header).
	for entry: Dictionary in formation_data:
		var code: String = entry["code"]
		var type: String = EnemyFactory.CODE_TO_TYPE.get(WaveScaler.original_code(code), "")
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
	return _resolve_past_elites(spec, round)

func _resolve_past_elites(spec: Array, round: int) -> Array:
	for entry: Dictionary in spec:
		var code: String = str(entry.get("code", ""))
		if code.begins_with(WaveScaler.PAST_ELITE_PREFIX):
			entry["level"] = WaveScaler.past_elite_level(code, round)
			entry["past_elite"] = true
			entry["code"] = WaveScaler.original_code(code)
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
		# Owner correction: the round-5 Groundbreaker elite is FIRE.
		# Later Earth anchors still use the existing factory and demotion.
		if unit and type == "hill_giant" and (round == 5 or entry.get("past_elite", false)):
			unit.current_element = UnitBase.Element.FIRE
			unit.unit_name = "Fire Giant"

	# Role badge tag (2026-07-27) — stamped from the wave CODE here because this
	# is the only place that still knows it (the spec's "type" has already lost
	# the elemental-variant grouping the role tables are keyed on). Purely
	# cosmetic; VisualUnit._setup_role_badge reads it. Same classifier the prep
	# panel's dossier uses, so badge and dossier can never disagree.
	if unit:
		if type == "ant":
			unit.set_meta("ant_hill_guard", true)
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
		unit.tenacity = EnemyFactory.TENACITY_NORMAL   # sheds elite CC resistance too
		unit.gold_reward = 0
		unit.crystal_reward = 0
		unit.xp_reward = mini(unit.xp_reward, HEAVY_XP_CAP)
		unit.set_meta("wave_heavy", true)
		# The Groundbreaker loop is the round-5 elite's alone (owner 2026-10-06).
		if str(unit.get_meta("mob_skill", "")) == "hill_giant_smash":
			EnemyFactory.demote_hill_giant(unit)
	if unit and lvl > 1:
		unit.set_level(lvl)
	# Late-game stat multiplier (round 11+, see Balance) — applied AFTER
	# leveling so it scales the leveled stats. Keeps current/max HP ratio
	# (Khagan deliberately spawns at half HP).
	# Ant guards match the hill's combat summons, which scale by level alone.
	if unit and type != "ant" and not entry.get("past_elite", false) and round > Balance.ENEMY_LATE_SCALE_START_ROUND:
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
