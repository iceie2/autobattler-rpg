extends Node
class_name WaveScaler

enum Difficulty { EASY, NORMAL, HARD }
enum Role      { FRONT, BACK, BOSS }

# Total-power multiplier relative to the easy base wave.
# Easy base power × this mult = total power budget for Normal/Hard.
const DIFFICULTY_MULT: Array[float] = [1.0, 1.75, 3.5]

# ── Role registry ─────────────────────────────────────────────────────────────
# To add a new enemy: register its code here. That's it.
#   FRONT → rows 3 → 2  (melee, chargers)
#   BACK  → rows 0 → 1  (ranged, supports)
#   BOSS  → rows 1–2    (large/boss units, centered)
const CODE_ROLE: Dictionary = {
	"M":  Role.FRONT,  # Goblin
	"A":  Role.BACK,   # Goblin Archer
	"S":  Role.BACK,   # Goblin Shaman (Fire) — was plain "Goblin Shaman"
	"GSN": Role.BACK,  # Goblin Shaman (Normal)
	"GSW": Role.BACK,  # Goblin Shaman (Water)
	"GSE": Role.BACK,  # Goblin Shaman (Earth)
	"GSA": Role.BACK,  # Goblin Shaman (Air)
	"GSL": Role.BACK,  # Goblin Shaman (Lightning)
	"B":  Role.FRONT,  # Orc (Earth) — was "Orc Brute"
	"BN": Role.FRONT,  # Orc (Normal)
	"BF": Role.FRONT,  # Orc (Fire)
	"BW": Role.FRONT,  # Orc (Water)
	"BA": Role.FRONT,  # Orc (Air)
	"BL": Role.FRONT,  # Orc (Lightning)
	"G":  Role.BOSS,   # Hill Giant (2×2) — elite-tier now, still centered like a boss when placed
	"SL": Role.FRONT,  # Slime (Water) — was plain "Slime"
	"SLN": Role.FRONT, # Slime (Normal)
	"SLF": Role.FRONT, # Slime (Fire)
	"SLE": Role.FRONT, # Slime (Earth)
	"SLA": Role.FRONT, # Slime (Air)
	"SLL": Role.FRONT, # Slime (Lightning)
	"LZN": Role.BACK,  # Lizard (Normal) — far-range, barely moves
	"LZF": Role.BACK,  # Lizard (Fire)
	"LZW": Role.BACK,  # Lizard (Water)
	"LZE": Role.BACK,  # Lizard (Earth)
	"LZA": Role.BACK,  # Lizard (Air)
	"LZL": Role.BACK,  # Lizard (Lightning)
	"BRN": Role.FRONT, # Bear (Normal) — beefy tank
	"BRF": Role.FRONT, # Bear (Fire)
	"BRW": Role.FRONT, # Bear (Water)
	"BRE": Role.FRONT, # Bear (Earth)
	"BRA": Role.FRONT, # Bear (Air)
	"BRL": Role.FRONT, # Bear (Lightning)
	"TLN": Role.BACK,  # Troll (Normal) — ranged attack-speed support
	"TLF": Role.BACK,  # Troll (Fire)
	"TLW": Role.BACK,  # Troll (Water)
	"TLE": Role.BACK,  # Troll (Earth)
	"TLA": Role.BACK,  # Troll (Air)
	"TLL": Role.BACK,  # Troll (Lightning)
	"WUN": Role.FRONT, # Wind-Up Bot (Normal) — light melee striker
	"WUF": Role.FRONT, # Wind-Up Bot (Fire)
	"WUW": Role.FRONT, # Wind-Up Bot (Water)
	"WUE": Role.FRONT, # Wind-Up Bot (Earth)
	"WUA": Role.FRONT, # Wind-Up Bot (Air)
	"WUL": Role.FRONT, # Wind-Up Bot (Lightning)
	"SK": Role.FRONT,  # Skeleton
	"R":  Role.FRONT,  # Rat
	"TRI": Role.FRONT, # The Triarch (1×1 — opens in its melee phase)
	"SS": Role.FRONT,  # Stat Stealer (1×1 elite)
	"AH": Role.BOSS,   # Ant Hill (2×2 — stationary spawner)
	"KHA": Role.BOSS,  # Khagan (2×2 while mounted — phase 1)
	"HYN": Role.BOSS, "HYF": Role.BOSS, "HYW": Role.BOSS,   # Hydra (all 6 elements, 2×2 final boss)
	"HYE": Role.BOSS, "HYA": Role.BOSS, "HYL": Role.BOSS,
}

# Codes that occupy a 2×2 cell block
const CODE_IS_LARGE: Dictionary = {
	"G": true,
	"AH": true,
	"KHA": true,
	"HYN": true, "HYF": true, "HYW": true, "HYE": true, "HYA": true, "HYL": true,
}

# ── Power costs (rough unit strength used for budget system) ──────────────────
# Easy wave power is the baseline. Normal/Hard spend their leftover budget on
# random filler units pulled from FILLER_POOL (ordered strongest → weakest).
const UNIT_POWER: Dictionary = {
	"R":  15,   # Rat         — very cheap swarm
	"SL": 25, "SLN": 25, "SLF": 25, "SLE": 25, "SLA": 25, "SLL": 25,  # Slime (all 6 elements) — tanky but slow
	"SK": 25,   # Skeleton    — glass cannon
	"M":  30,   # Goblin      — basic melee
	"A":  30,   # Goblin Archer
	"S":  55, "GSN": 55, "GSW": 55, "GSE": 55, "GSA": 55, "GSL": 55,  # Goblin Shaman (all 6 elements)
	"LZN": 40, "LZF": 40, "LZW": 40, "LZE": 40, "LZA": 40, "LZL": 40,  # Lizard (all 6 elements) — far range + burst snipe, but barely moves and dies fast if rushed
	"TLN": 70, "TLF": 70, "TLW": 70, "TLE": 70, "TLA": 70, "TLL": 70,  # Troll (all 6 elements) — no direct damage, but a real attack-speed threat multiplier for the whole side
	"B":  95, "BN": 95, "BF": 95, "BW": 95, "BA": 95, "BL": 95,  # Orc (all 6 elements)
	"BRN": 100, "BRF": 100, "BRW": 100, "BRE": 100, "BRA": 100, "BRL": 100,  # Bear (all 6 elements) — beefiest 1×1 HP pool, but low damage output
	"WUN": 90, "WUF": 90, "WUW": 90, "WUE": 90, "WUA": 90, "WUL": 90,  # Wind-Up Bot (all 6 elements) — light melee striker, hit + stun
	"G":  300,  # Hill Giant  — elite-tier
	"TRI": 350, # The Triarch — 3-phase final boss
	"SS": 150,  # Stat Stealer — elite-tier
	"AH": 250,  # Ant Hill — elite-tier (tanky spawner; the ants are the real threat, uncounted here)
	"KHA": 300, # Khagan — wave-10 boss (mount-swap fight)
	"HYN": 400, "HYF": 400, "HYW": 400, "HYE": 400, "HYA": 400, "HYL": 400,  # Hydra — wave-30 final boss (all 6 elements)
}

# Ordered strong → weak. _fill_budget() prefers the top of this list.
const FILLER_POOL: Array[String] = [
	"G", "BRN", "BRF", "BRW", "BRE", "BRA", "BRL",
	"B", "BN", "BF", "BW", "BA", "BL",
	"S", "GSN", "GSW", "GSE", "GSA", "GSL", "TLN", "TLF", "TLW", "TLE", "TLA", "TLL",
	"WUN", "WUF", "WUW", "WUE", "WUA", "WUL",
	"LZN", "LZF", "LZW", "LZE", "LZA", "LZL", "A", "M", "SK",
	"SL", "SLN", "SLF", "SLE", "SLA", "SLL",
	"R",
]

# Row fill priority per role (row 0 = farthest back, row 3 = frontline)
const ROLE_ROWS: Dictionary = {
	Role.FRONT: [3, 2, 1, 0],
	Role.BACK:  [0, 1, 2, 3],
}

# ── Live unit scoring (for reward calculation and power display) ───────────────
static func score_unit(unit: UnitBase) -> float:
	var s: float = (float(unit.max_hp)         * 0.15
				  + float(unit.attack_damage)  * 10.0
				  + float(unit.attack_speed)   * 60.0
				  + float(unit.magic_power)    * 8.0
				  + float(unit.resistance)     * 5.0)
	if unit.attack_range > 1:
		s *= 1.25
	if unit.cell_size == 2:
		s *= 2.5
	return s

# LEGACY (pre coin-drop economy) — kept only for anything still displaying a
# "gold value" for a unit. Kill gold now flows through gold_drops_for_unit.
static func gold_for_unit(unit: UnitBase) -> int:
	return maxi(2, int(score_unit(unit) * 0.018))

# Economy v3 (2026-07-03, per user): kills drop PHYSICAL coins on the field
# (collected by the round-end vacuum), max 1 gold per basic kill, and not
# guaranteed — the chance rises with the wave. Elites/bosses drop a fixed
# handful. Summons never drop (Ant Hill would be a gold printer otherwise).
static func gold_drops_for_unit(unit: UnitBase, round: int) -> int:
	if unit.is_summoned:
		return 0
	if unit.is_boss:
		return Balance.BOSS_COIN_DROP
	if unit.is_elite:
		return Balance.ELITE_COIN_DROP \
				+ (1 if round >= Balance.ELITE_COIN_LATE_BONUS_ROUND else 0)
	# EV-modeled 2026-07-03: hits the user's early curve (2nd hero ~wave 3,
	# 3rd ~wave 5, ~5 by wave 8-10 on Easy). Capped to soften the late-game
	# re-acceleration; the planned TFT-style player-level/team-size system is
	# the intended structural gate past wave ~12 (user's idea). Tune in balance.gd.
	var chance: float = clampf(
			Balance.COIN_CHANCE_BASE + float(round) * Balance.COIN_CHANCE_PER_ROUND,
			Balance.COIN_CHANCE_BASE, Balance.COIN_CHANCE_CAP)
	return 1 if randf() < chance else 0

static func crystals_for_unit(unit: UnitBase) -> int:
	var s := score_unit(unit)
	if s >= 800.0: return 2
	if s >= 400.0: return 1
	return 0

# ── Formation builder ─────────────────────────────────────────────────────────
# Returns Array of {"code": String, "pos": Vector2i} ready for spawn_enemies().
# Returns [] for procedural rounds (round 11+).
#
# Easy:         fixed wave from WaveData — no changes.
# Normal/Hard:  easy base guaranteed + random filler units up to the power budget.
#               Filler prefers 1 strong unit over several weak ones (70/30 bias).
static func build_formation(round: int, difficulty: int, grid_width: int = 9) -> Array:
	var base_counts: Dictionary = WaveData.get_wave(round)
	if base_counts.is_empty():
		return []

	if difficulty == Difficulty.EASY:
		return _auto_place(base_counts, grid_width)

	# Normal / Hard: start with easy base, add power-budget filler.
	var base_power: int = _count_power(base_counts)
	var mult: float = DIFFICULTY_MULT[difficulty]
	var total_budget: int = int(float(base_power) * mult)
	var remaining: int = total_budget - base_power

	var counts: Dictionary = base_counts.duplicate()
	var filler: Dictionary = _fill_budget(remaining)
	for code: String in filler:
		counts[code] = counts.get(code, 0) + filler[code]

	return _auto_place(counts, grid_width)

# Sum the power cost of a counts dictionary.
static func _count_power(counts: Dictionary) -> int:
	var total := 0
	for code: String in counts:
		total += UNIT_POWER.get(code, 30) * int(counts[code])
	return total

# Spend `budget` on random filler units.
# 70% chance: pick the strongest affordable unit from FILLER_POOL.
# 30% chance: pick any affordable unit at random.
# Returns a counts dictionary.
static func _fill_budget(budget: int) -> Dictionary:
	var result: Dictionary = {}
	var safety := 0
	while budget > 0 and safety < 50:
		safety += 1
		# Build list of affordable units
		var affordable: Array[String] = []
		for code: String in FILLER_POOL:
			if UNIT_POWER.get(code, 9999) <= budget:
				affordable.append(code)
		if affordable.is_empty():
			break

		var pick: String
		if randf() < 0.7:
			pick = affordable[0]  # strongest affordable (FILLER_POOL is sorted strong→weak)
		else:
			pick = affordable[randi() % affordable.size()]

		result[pick] = result.get(pick, 0) + 1
		budget -= UNIT_POWER.get(pick, 30)

	return result

# ── Auto-placer ───────────────────────────────────────────────────────────────
# Places units by role: bosses centered first, then FRONT/BACK by row priority.
# All units in a row are spread evenly across free columns.
static func _auto_place(counts: Dictionary, grid_width: int) -> Array:
	var result: Array = []
	var occupied: Dictionary = {}   # Vector2i → true

	# --- 1. Collect and place 2×2 boss units first (centered) ---
	var boss_codes: Array = []
	for code: String in counts:
		if CODE_IS_LARGE.get(code, false):
			for _i in range(int(counts[code])):
				boss_codes.append(code)
	if not boss_codes.is_empty():
		result.append_array(_place_bosses(boss_codes, occupied, grid_width))

	# --- 2. Group regular units by role ---
	var by_role: Dictionary = {}
	for code: String in counts:
		if CODE_IS_LARGE.get(code, false):
			continue
		var role: int = CODE_ROLE.get(code, Role.FRONT)
		if not by_role.has(role):
			by_role[role] = []
		for _i in range(int(counts[code])):
			by_role[role].append(code)

	# --- 3. Fill rows in role-priority order ---
	for role: int in [Role.FRONT, Role.BACK]:
		if not by_role.has(role):
			continue
		var rows: Array = ROLE_ROWS.get(role, [3, 2, 1, 0])
		result.append_array(_fill_rows(by_role[role], rows, occupied, grid_width))

	return result

# Place N large (2×2) units, evenly spaced across boss rows (1–2).
static func _place_bosses(codes: Array, occupied: Dictionary, grid_width: int) -> Array:
	var result: Array = []
	var n := codes.size()
	# Valid anchor-x positions for 2-wide units (x and x+1 must be in-grid)
	var valid_x: Array = []
	for x in range(grid_width - 1):
		valid_x.append(x)
	var chosen_x: Array = _even_pick(valid_x, n)

	for i in range(codes.size()):
		var x: int = chosen_x[i]
		# Try row pairs top-to-bottom: [1,2] preferred, then [0,1], [2,3]
		for row_pair: Array in [[1, 2], [0, 1], [2, 3]]:
			var r0: int = row_pair[0]
			var r1: int = row_pair[1]
			var cells: Array = [
				Vector2i(x,   r0), Vector2i(x+1, r0),
				Vector2i(x,   r1), Vector2i(x+1, r1),
			]
			var clear := true
			for c: Vector2i in cells:
				if occupied.has(c):
					clear = false
					break
			if clear:
				for c: Vector2i in cells:
					occupied[c] = true
				result.append({"code": codes[i], "pos": Vector2i(x, r0)})
				break

	return result

# Fill a list of units across rows in priority order, evenly spacing per row.
static func _fill_rows(codes: Array, row_priority: Array, occupied: Dictionary, grid_width: int) -> Array:
	var result: Array = []
	var idx := 0

	for row: int in row_priority:
		if idx >= codes.size():
			break
		# Collect free columns in this row
		var free_cols: Array = []
		for x in range(grid_width):
			if not occupied.has(Vector2i(x, row)):
				free_cols.append(x)
		if free_cols.is_empty():
			continue
		# Take as many units as fit
		var take := mini(codes.size() - idx, free_cols.size())
		var row_codes: Array = codes.slice(idx, idx + take)
		idx += take
		# Spread them evenly across the free columns
		var chosen: Array = _even_pick(free_cols, row_codes.size())
		for i in range(row_codes.size()):
			var pos := Vector2i(chosen[i], row)
			result.append({"code": row_codes[i], "pos": pos})
			occupied[pos] = true

	return result

# Pick n evenly-spaced items from a list (with margins — no edge-hugging).
# e.g. _even_pick([0..8], 3) → [2, 4, 6]
static func _even_pick(items: Array, n: int) -> Array:
	if n <= 0:
		return []
	if n >= items.size():
		return items.duplicate()
	var picked: Array = []
	for i in range(n):
		var t: float = float(i + 1) / float(n + 1)
		var idx := clampi(int(t * items.size()), 0, items.size() - 1)
		picked.append(items[idx])
	return picked

# ── Procedural round scaling (round 11+) ──────────────────────────────────────
static func procedural_count(base_count: int, difficulty: int) -> int:
	var mult: float = DIFFICULTY_MULT[difficulty]
	return mini(int(float(base_count) * mult), 32)

# ── Boss waves (rounds 10 / 20 / 30) ──────────────────────────────────────────
# A centered 2×2 Hill Giant boss plus escalating adds. Difficulty adds more
# muscle. Returns the same [{code, pos}] format as build_formation.
static func is_boss_round(round: int) -> bool:
	return round > 0 and round % Balance.BOSS_ROUND_INTERVAL == 0 \
			and round <= Balance.VICTORY_ROUND

# Boss tier: 1 at round 10, 2 at 20, 3 at 30.
static func boss_tier(round: int) -> int:
	return int(round / Balance.BOSS_ROUND_INTERVAL)

# Level the boss unit is set to — scales hard between the three encounters.
# Re-anchored 2026-07-12 to the run targets: Khagan (3) stays first-try
# beatable with no crystal upgrades; the Triarch (10) needs a stars-align
# no-upgrade run; the Hydra (18) is meant to be unbeatable without them.
# (Old 3/6/9 curve: arena sims had a frozen level-5 team killing the Hydra.)
static func boss_level(round: int) -> int:
	match boss_tier(round):
		1:  return 3
		2:  return 14
		_:  return 22

# Which boss code fights at a given round. Hill Giant was reclassified to an
# elite (2026-07-02, now spawns in rounds 5/15/25 instead — see is_elite_round).
# Wave 10: Khagan (mount-swap fight). Wave 20: The Triarch (3-phase fight).
# Wave 30: the Hydra — the true final boss, fighting as whichever element the
# player picked pre-battle (see main_game.gd's element-pick screen); defaults
# to Normal if no pick was ever recorded (e.g. the arena harness, which never
# shows that screen). chosen_element takes a UnitBase.Element value.
static func boss_code_for(round: int, chosen_element: int = -1) -> String:
	match boss_tier(round):
		1: return "KHA"
		2: return "TRI"
		_:
			match chosen_element:
				UnitBase.Element.FIRE:      return "HYF"
				UnitBase.Element.WATER:     return "HYW"
				UnitBase.Element.EARTH:     return "HYE"
				UnitBase.Element.AIR:       return "HYA"
				UnitBase.Element.LIGHTNING: return "HYL"
				_: return "HYN"   # NORMAL or unset

static func build_boss_formation(round: int, difficulty: int, grid_width: int = 9, chosen_element: int = -1) -> Array:
	var tier: int = boss_tier(round)
	var counts: Dictionary = {boss_code_for(round, chosen_element): 1}      # the boss
	counts["M"] = 2 + tier + difficulty                     # goblin fodder
	# Honor guard grows with the boss tier (2026-07-12: a lone boss just gets
	# focus-fired down by a full late-game roster — arena sims had 10 heroes
	# killing the Hydra in ~20s through its old 5-goblin escort). Trolls buff
	# the boss's attack speed, shamans heal it — real support, not fodder.
	if tier == 2:
		counts["B"]   = 1 + difficulty                      # orc bruisers
		counts["BRN"] = 2                                   # bear frontline
		counts["TLN"] = 2                                   # attack-speed buffers
		counts["GSN"] = 2                                   # shaman healers
	elif tier >= 3:
		counts["BRN"] = 2
		counts["BN"]  = 2
		counts["TLN"] = 2                                   # attack-speed buffers
		counts["GSN"] = 2
		counts["LZN"] = 2                                   # backline snipers
	return _auto_place(counts, grid_width)

# ── Elite waves (rounds 5 / 15 / 25 — the gaps between boss rounds) ──────────
# A mini-boss (Hill Giant or Stat Stealer) plus light fodder support. Weaker
# than a full boss encounter, but a real step up from normal fodder.
const ELITE_ROUNDS: Array[int] = Balance.ELITE_ROUNDS   # tune in balance.gd
const ELITE_POOL: Array[String] = ["G", "SS", "AH"]   # Hill Giant, Stat Stealer, Ant Hill
# Fixed assignment (2026-07-15 user decision, replaces the random pool pick):
# each elite owns ONE round so its stats can be balanced against that round's
# team power instead of having to work at three different power levels.
const ELITE_BY_ROUND := {5: "G", 15: "AH", 25: "SS"}

static func is_elite_round(round: int) -> bool:
	return round in ELITE_ROUNDS

# Level for a non-boss/non-elite enemy in a given round. Extracted from
# main_game.gd (which now delegates here) so the arena harness shares the exact
# live-game curve. is_elite_slot = the legacy "last unit of a procedural wave
# gets elite-ish level" flag, NOT the round-5/15/25 elite tier.
static func enemy_level_for_round(round: int, is_elite_slot: bool) -> int:
	if is_elite_slot and round % 5 == 0:
		return mini(round / 5 + 2, 8)
	if is_elite_slot and round >= 4:
		return mini(round / 2, 5)
	if round <= 2: return 1
	if round <= 10:
		return 1 + randi() % mini(round / 2, 3)
	# Round 11+: level keeps climbing. Steepened 2026-07-12 (was (round-10)/2,
	# topping out ~13-15 by round 30) after arena sims showed a frozen 5-hero
	# level-5 team clearing wave 29 at 88% — nowhere near the run targets
	# (wave 20 = stars-align without crystal upgrades, wave 30 = impossible
	# without them). Now ~4-6 at round 11 up to ~19-21 by round 30.
	var floor_lvl: int = 3 + int(float(round - 10) * 0.8)
	return floor_lvl + randi() % 3

# How much to bias a procedural enemy hero's stat rolls (see
# UnitFactory.generate_recruit_rolls) toward higher grades as the run goes on.
# 0 through round 10 (matches the old flat behaviour); climbs to 0.5 by round
# 30 — pushes the average roll from a "B" up toward "A"/"S" by the late game,
# instead of every round-11+ enemy hero landing in the same grade band forever.
# Capped at 0.5 (not higher) so round 30 still has real variance — a bias that
# guarantees S every time removes the "did I get a scary roll" tension entirely.
static func enemy_roll_bias(round: int) -> float:
	return clampf(float(round - 10) / 20.0, 0.0, 1.0) * 0.5

# Elite level: a step above the regular mobs of its round (which follow
# enemy_level_for_round), a step below the next boss. Re-anchored 2026-07-12
# alongside the steeper round-11+ level curve — the old 2/4/6 would have made
# the wave-15/25 elites WEAKER than their own escort fodder.
static func elite_level(round: int) -> int:
	match ELITE_ROUNDS.find(round):
		0:  return 2    # round 5  — fodder is lvl 1-2
		1:  return 9    # round 15 — fodder is lvl 7-9
		_:  return 16   # round 25 — fodder is lvl 15-17

# The elite for a round is fixed by ELITE_BY_ROUND, so regenerating the spec
# (formation preview, then again on Ready) always yields the same pick — the
# old random pool needed a per-round lock cache in wave_director for that.
static func build_elite_formation(round: int, difficulty: int, grid_width: int = 9) -> Array:
	var code: String = ELITE_BY_ROUND.get(round, "G")
	var counts: Dictionary = {code: 1}
	counts["M"] = 1 + difficulty   # light fodder support
	return _auto_place(counts, grid_width)
