extends Node
# Autoload singleton — persists crystal wallet and upgrade levels across runs.

const SAVE_PATH := "user://progression.json"

var crystals: int = 0

# upgrade_levels maps upgrade key → current level (0 = not bought)
var upgrade_levels: Dictionary = {}

# ── Upgrade catalogue ─────────────────────────────────────────────────────────
# Each entry: { key, name, desc, max_level, effect_per_level }
# effect_per_level is used by the game to query the bonus value.
const UPGRADES: Array = [
	{
		"key":              "starting_gold",
		"name":             "Head Start",
		"desc":             "+5 gold at the start of every run per level.",
		"effect":           "Starting Gold +%d",
		"max_level":        20,
		"effect_per_level": 5,
	},
]

func _ready() -> void:
	load_data()

# ── Public API ────────────────────────────────────────────────────────────────

func get_level(key: String) -> int:
	return upgrade_levels.get(key, 0)

# Cost to purchase the next level of an upgrade (returns -1 if already maxed)
func next_cost(key: String) -> int:
	var lvl := get_level(key)
	var upgrade := _find(key)
	if upgrade.is_empty() or lvl >= upgrade["max_level"]:
		return -1
	# Exponential curve: base 10, multiplier 1.255, caps near 750 at level 19
	# Lv0→1: 10c  |  Lv4→5: 25c  |  Lv9→10: 77c  |  Lv14→15: 240c  |  Lv19→20: 749c
	return roundi(10.0 * pow(1.255, lvl))

func can_afford(key: String) -> bool:
	var cost := next_cost(key)
	return cost > 0 and crystals >= cost

func buy(key: String) -> bool:
	if not can_afford(key):
		return false
	crystals -= next_cost(key)
	upgrade_levels[key] = get_level(key) + 1
	save_data()
	return true

func add_crystals(amount: int) -> void:
	if amount <= 0:
		return
	crystals += amount
	save_data()

# Returns the total bonus value for an upgrade (level × per_level)
func get_bonus(key: String) -> int:
	var upgrade := _find(key)
	if upgrade.is_empty():
		return 0
	return get_level(key) * int(upgrade["effect_per_level"])

# Convenience helpers used by main_game.gd
func starting_gold_bonus() -> int:
	return get_bonus("starting_gold")

# ── Persistence ───────────────────────────────────────────────────────────────

func save_data() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify({
		"crystals":        crystals,
		"upgrade_levels":  upgrade_levels,
	}))

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	crystals        = int(parsed.get("crystals", 0))
	upgrade_levels  = parsed.get("upgrade_levels", {})

func _find(key: String) -> Dictionary:
	for u in UPGRADES:
		if u["key"] == key:
			return u
	return {}
