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
		# 2026-07-16 economy pair rework (user spec): converted from "+1 gold
		# once at run start" to "+1 gold after every round" — the cheap half of
		# the gold pair, with Bounty (per-kill) hard-gated behind it. Key stays
		# "starting_gold" for save compatibility.
		"key": "starting_gold", "name": "Head Start",
		"desc": "+1 gold after every round per level.",
		"effect": "Gold / Round +%d", "max_level": 10, "effect_per_level": 1,
	},
	{
		# The expensive half of the gold pair: far more total income (kills per
		# round beat rounds per round), locked until Head Start has a level.
		"key": "gold_per_kill", "name": "Bounty",
		"desc": "+1 gold dropped by every enemy kill per level.",
		"effect": "Gold / Kill +%d", "max_level": 5, "effect_per_level": 1,
		"cost_mult": 3.0, "requires": "starting_gold",
	},
	{
		# 2026-07-10 user correction: was +50/level, now +10/level.
		"key": "team_hp", "name": "Fortified",
		"desc": "+10 max HP to all heroes at the start of every run per level.",
		"effect": "Team HP +%d", "max_level": 20, "effect_per_level": 10,
	},
	{
		"key": "hero_slots", "name": "Roster Expansion",
		"desc": "+1 hero you can field per level (stacks with your player level).",
		"effect": "Hero Slots: %d", "max_level": 5, "effect_per_level": 1,
	},
	{
		# Warm Bench (2026-07-10): grows the sideboard — heroes bought past the
		# field cap wait here (see main_game's bench system, base size in
		# Balance.BENCH_BASE_SLOTS).
		"key": "bench_slots", "name": "Warm Bench",
		"desc": "+1 bench slot to store extra heroes per level.",
		"effect": "Bench Slots +%d", "max_level": 4, "effect_per_level": 1,
	},
	{
		# Cheap half of the crystal pair (2026-07-16, mirrors Head Start/Bounty).
		"key": "crystal_per_round", "name": "Crystal Tithe",
		"desc": "+1 crystal after every round per level.",
		"effect": "Crystals / Round +%d", "max_level": 10, "effect_per_level": 1,
	},
	{
		# Expensive per-kill half, gated behind Crystal Tithe (2026-07-16).
		"key": "crystal_drop", "name": "Crystal Surge",
		"desc": "+1 crystal dropped by every enemy per level.",
		"effect": "Crystal Drop +%d", "max_level": 10, "effect_per_level": 1,
		"cost_mult": 3.0, "requires": "crystal_per_round",
	},
	{
		# 2026-07-10: the 4 core root-branch upgrades are starting_gold/team_hp/
		# hero_slots/bonus_xp — crystal_drop above stays in the catalogue as a
		# regular (non-core) branch instead of being removed.
		"key": "bonus_xp", "name": "Quick Learner",
		"desc": "+25% XP earned by every hero from kills, per level.",
		"effect": "Bonus XP +%d%%", "max_level": 20, "effect_per_level": 25,
	},
	# ── Stat tree (2026-07-10) — one flat/percent bonus applied to every hero
	# at recruit time, same mechanism as team_hp above (see
	# main_game._apply_progression_bonuses). Numbers are a first pass, freely
	# invented per convention — tune after playtesting.
	{
		"key": "mana_well", "name": "Mana Well",
		"desc": "+10 max mana to all heroes per level.",
		"effect": "Max Mana +%d", "max_level": 20, "effect_per_level": 10,
	},
	{
		"key": "spellpower", "name": "Spellpower",
		"desc": "+2 magic power to all heroes per level.",
		"effect": "Magic Power +%d", "max_level": 20, "effect_per_level": 2,
	},
	{
		"key": "might", "name": "Might",
		"desc": "+2 attack damage to all heroes per level.",
		"effect": "Attack Damage +%d", "max_level": 20, "effect_per_level": 2,
	},
	{
		# 2026-07-16 defense split: Warding is the MAGIC armor node now (the
		# flavor fits); Bulwark below covers physical armor. Key kept for saves.
		"key": "warding", "name": "Warding",
		"desc": "+2 magic armor to all heroes per level.",
		"effect": "Magic Armor +%d", "max_level": 20, "effect_per_level": 2,
	},
	{
		"key": "bulwark", "name": "Bulwark",
		"desc": "+2 armor to all heroes per level.",
		"effect": "Armor +%d", "max_level": 20, "effect_per_level": 2,
	},
	{
		"key": "fleetfoot", "name": "Fleetfoot",
		"desc": "+0.02 attack speed to all heroes per level.",
		"effect": "Attack Speed +%.2f", "max_level": 20, "effect_per_level": 0.02, "is_float": true,
	},
	{
		"key": "vitality_flow", "name": "Vitality Flow",
		"desc": "+0.1 HP regen to all heroes per level.",
		"effect": "HP Regen +%.1f", "max_level": 20, "effect_per_level": 0.1, "is_float": true,
	},
	{
		"key": "mana_flow", "name": "Mana Flow",
		"desc": "+0.1 mana regen to all heroes per level.",
		"effect": "Mana Regen +%.1f", "max_level": 20, "effect_per_level": 0.1, "is_float": true,
	},
	{
		"key": "swiftness", "name": "Swiftness",
		"desc": "+1 movement speed to all heroes per level.",
		"effect": "Movement Speed +%d", "max_level": 5, "effect_per_level": 1,
	},
	{
		# Stored as whole percentage points (2 = 2%), divided by 100 wherever it's
		# actually applied to unit.crit_chance — keeps the shop display a plain
		# int like elemental_attunement below instead of a raw 0.02 fraction.
		"key": "lethality", "name": "Lethality",
		"desc": "+2% crit chance to all heroes per level.",
		"effect": "Crit Chance +%d%%", "max_level": 20, "effect_per_level": 2,
	},
	{
		"key": "killing_blow", "name": "Killing Blow",
		"desc": "+5% crit damage to all heroes per level.",
		"effect": "Crit Damage +%d%%", "max_level": 20, "effect_per_level": 5,
	},
	{
		"key": "elemental_attunement", "name": "Elemental Attunement",
		"desc": "+1% natural-aspect kit bonus per level (base bonus is 15%).",
		"effect": "Aspect Bonus +%d%%", "max_level": 20, "effect_per_level": 1,
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
	# cost_mult scales the whole curve for premium nodes (per-kill economy pair).
	return roundi(10.0 * pow(1.255, lvl) * float(upgrade.get("cost_mult", 1.0)))

# Hard prerequisite gate (2026-07-16): an upgrade with a "requires" key can't
# be bought until that prerequisite has at least 1 level.
func is_locked(key: String) -> bool:
	var req: String = _find(key).get("requires", "")
	return req != "" and get_level(req) == 0

func can_afford(key: String) -> bool:
	if is_locked(key):
		return false
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

# Returns the total bonus value for an upgrade (level × per_level), as an int.
# Only use this for int-typed stats — for anything marked "is_float": true in
# the catalogue (attack_speed/regen/crit/etc.), use get_bonus_float() instead,
# since this truncates to int.
func get_bonus(key: String) -> int:
	var upgrade := _find(key)
	if upgrade.is_empty():
		return 0
	return get_level(key) * int(upgrade["effect_per_level"])

# Float-precision version for small per-level increments (attack_speed,
# hp_regen/mana_regen, crit_chance/crit_damage) where int() truncation would
# zero out a sub-1.0 effect_per_level.
func get_bonus_float(key: String) -> float:
	var upgrade := _find(key)
	if upgrade.is_empty():
		return 0.0
	return float(get_level(key)) * float(upgrade["effect_per_level"])

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
