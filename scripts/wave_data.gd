extends Node
class_name WaveData

# ── Enemy codes ───────────────────────────────────────────────────────────────
#  M  = Goblin (melee)
#  A  = Goblin Archer (ranged)
#  S  = Goblin Shaman (ranged magic)
#  B  = Orc Brute (heavy melee)
#  G  = Hill Giant (2×2 boss)
#
# To add a new enemy type:
#   1. Add its factory in enemy_factory.gd
#   2. Register its code + role in wave_scaler.gd CODE_ROLE dict
#   3. Add a spawn case in main_game.gd spawn_enemies()
#   4. Use the code in waves below
#
# ── Wave format ───────────────────────────────────────────────────────────────
# Each wave is just {code: count}. WaveScaler auto-places units by role:
#   FRONT role  → rows 3 → 2 (frontline, closest to player)
#   BACK role   → rows 0 → 1 (backline, farthest from player)
#   BOSS role   → rows 1–2 (centered)
# Units are spread evenly across the row. No manual positioning needed.

static func get_wave(round_number: int) -> Dictionary:
	match round_number:
		1:  return {"M": 2}
		2:  return {"M": 2, "A": 2}
		3:  return {"M": 4, "A": 2}
		4:  return {"M": 2, "A": 2, "S": 2}
		5:  return {"G": 1, "A": 2}
		6:  return {"M": 3, "S": 3}
		7:  return {"A": 2, "B": 2}
		8:  return {"G": 2, "S": 2}
		9:  return {"A": 3, "B": 3, "S": 2}
		10: return {"G": 2, "A": 2, "B": 2, "S": 2}
		_:  return {}   # round 11+: procedural escalation
