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
	"S":  Role.BACK,   # Goblin Shaman
	"B":  Role.FRONT,  # Orc Brute
	"G":  Role.BOSS,   # Hill Giant (2×2)
	"SL": Role.FRONT,  # Slime
	"SK": Role.FRONT,  # Skeleton
	"R":  Role.FRONT,  # Rat
}

# Codes that occupy a 2×2 cell block
const CODE_IS_LARGE: Dictionary = {
	"G": true,
}

# ── Power costs (rough unit strength used for budget system) ──────────────────
# Easy wave power is the baseline. Normal/Hard spend their leftover budget on
# random filler units pulled from FILLER_POOL (ordered strongest → weakest).
const UNIT_POWER: Dictionary = {
	"R":  15,   # Rat         — very cheap swarm
	"SL": 25,   # Slime       — tanky but slow
	"SK": 25,   # Skeleton    — glass cannon
	"M":  30,   # Goblin      — basic melee
	"A":  30,   # Goblin Archer
	"S":  55,   # Goblin Shaman
	"B":  95,   # Orc Brute
	"G":  300,  # Hill Giant  — boss-tier
}

# Ordered strong → weak. _fill_budget() prefers the top of this list.
const FILLER_POOL: Array[String] = ["G", "B", "S", "A", "M", "SK", "SL", "R"]

# Row fill priority per role (row 0 = farthest back, row 3 = frontline)
const ROLE_ROWS: Dictionary = {
	Role.FRONT: [3, 2, 1, 0],
	Role.BACK:  [0, 1, 2, 3],
}

# ── Live unit scoring (for reward calculation and power display) ───────────────
static func score_unit(unit: UnitBase) -> float:
	var s: float = (float(unit.max_hp)       * 0.15
				  + float(unit.strength)     * 10.0
				  + float(unit.dexterity)    * 6.0
				  + float(unit.intelligence) * 8.0
				  + float(unit.resistance)   * 5.0)
	if unit.attack_range > 1:
		s *= 1.25
	if unit.cell_size == 2:
		s *= 2.5
	return s

static func gold_for_unit(unit: UnitBase) -> int:
	return maxi(5, int(score_unit(unit) * 0.04))

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
