extends Node
class_name WaveData

# ── Enemy codes ───────────────────────────────────────────────────────────────
#  .  or  0  = empty cell
#  M         = Goblin (melee)
#  A         = Goblin Archer (ranged)
#  G         = Hill Giant (2×2 unit, anchored at this cell's top-left)
#
# ── Layout rules ─────────────────────────────────────────────────────────────
#  • Each row string is split by spaces; each token = one grid cell.
#  • Rows are automatically centred in the 22-wide battle grid.
#  • Up to 4 rows (enemy zone occupies grid rows 0–3).
#  • Shorter rows are fine — they just produce a narrower formation.
#  • An empty string "" means the whole row is unoccupied.
#
# ── Example (wave 1) ─────────────────────────────────────────────────────────
#   col:  0 1 2 3 4 5 6 7 8   (9 cols → starts at grid col 6, centred)
#   row0: . . . . . . . . .
#   row1: . . . . M M . . .   ← 2 goblins in centre
#   row2: . . . . . . . . .
#   row3: . . . . . . . . .

static func get_wave(round_number: int) -> Array:
	match round_number:
		1:  return WAVE_1
		2:  return WAVE_2
		3:  return WAVE_3
		_:  return []          # empty = use procedural spawning

# ── Round 1: two melee goblins ────────────────────────────────────────────────
const WAVE_1: Array = [
	". . . . . . . . .",
	". . . . M M . . .",
	". . . . . . . . .",
	". . . . . . . . .",
]

# ── Round 2: two goblins + archer behind them ─────────────────────────────────
const WAVE_2: Array = [
	". . . . . . . . .",
	". . . . M M . . .",
	". . . . . A . . .",
	". . . . . . . . .",
]

# ── Round 3: Hill Giant centre + flanking archers ─────────────────────────────
#  G occupies (col, row) as top-left of a 2×2 block.
#  The archers sit in row 2, one cell either side of the giant.
const WAVE_3: Array = [
	". . . . . . . . . .",
	". . . . . G . . . .",
	". . . . A . . A . .",
	". . . . . . . . . .",
]
