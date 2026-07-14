extends Node
class_name EquipmentManager

# Icon per item name — shared so any UI (inventory bag, item tooltips, the
# round-reward preview) can look up an item's icon without duplicating this map.
const ITEM_ICONS: Dictionary = {
	"Sword":       "res://assets/icons/64x64/fc1601.png",
	"Shield":      "res://assets/icons/64x64/fc2150.png",
	"Robe":        "res://assets/icons/64x64/fc2098.png",
	"Gloves":      "res://assets/icons/64x64/fc1985.png",
	"Ring":        "res://assets/icons/64x64/fc2135.png",
	"Cloak":       "res://assets/icons/64x64/fc2015.png",
	"Amulet":      "res://assets/icons/64x64/fc2055.png",
	"Boots":       "res://assets/icons/64x64/fc1948.png",
	"Axe":         "res://assets/icons/64x64/fc1770.png",
	"Staff":       "res://assets/icons/64x64/fc1720.png",
	"Bow":         "res://assets/icons/64x64/fc1580.png",
	"Plate Armor": "res://assets/icons/64x64/fc1920.png",
}

# Item templates. "primary" is the item's identity stat — it always gets the
# first stat point; remaining points roll onto random stats.
const ITEM_TEMPLATES = {
	"sword":  {"name": "Sword",       "primary": "atk"},
	"shield": {"name": "Shield",      "primary": "res"},
	"robe":   {"name": "Robe",        "primary": "magic"},
	"gloves": {"name": "Gloves",      "primary": "aspd"},
	"ring":   {"name": "Ring",        "primary": "hp"},
	"cloak":  {"name": "Cloak",       "primary": "res"},
	"amulet": {"name": "Amulet",      "primary": "mana"},
	"boots":  {"name": "Boots",       "primary": "aspd"},
	"axe":    {"name": "Axe",         "primary": "atk"},
	"staff":  {"name": "Staff",       "primary": "magic"},
	"bow":    {"name": "Bow",         "primary": "aspd"},
	"plate":  {"name": "Plate Armor", "primary": "res"},
}

# Stats whose values are small floats rather than whole numbers.
const FLOAT_STATS := ["aspd", "hpregen", "manaregen"]

# ── Points-budget system (matches the D/C/B/A/S grade table) ──────────────────
# Each rarity has a points budget. 1 stat roll = 1 point. A passive costs 2
# points and is only possible at RARE (blue) and above — so e.g. a Rare item
# (4 pts) is "4 stats" OR "2 stats + a passive".
const RARITY_POINTS := {
	EquipmentItem.Rarity.COMMON:    1,   # D
	EquipmentItem.Rarity.UNCOMMON:  2,   # C
	EquipmentItem.Rarity.RARE:      4,   # B
	EquipmentItem.Rarity.EPIC:      8,   # A
	EquipmentItem.Rarity.LEGENDARY: 10,  # S
}
const PASSIVE_COST := 2
const PASSIVE_MIN_RARITY := EquipmentItem.Rarity.RARE   # blue+
# Chance a RARE+ item spends 2 points on a passive (rises with rarity). Tunable.
const PASSIVE_CHANCE := {
	EquipmentItem.Rarity.RARE:      0.55,
	EquipmentItem.Rarity.EPIC:      0.70,
	EquipmentItem.Rarity.LEGENDARY: 0.85,
}

const PASSIVE_EFFECTS = [
	{"name": "Lifesteal", "desc": "Restore 15% of damage dealt as HP"},
	{"name": "Thorns", "desc": "Return 10% of damage taken"},
	{"name": "Haste", "desc": "+10% action speed"},
	{"name": "Regeneration", "desc": "+3 HP per turn"},
	{"name": "Spell Echo", "desc": "+20% magic power"},
	{"name": "Evasion", "desc": "+15% dodge chance"},
]

# Apply an item's stat bonuses directly onto a unit's live stats. Used for enemies
# that spawn already wielding a dropped item (see main_game.gd), which don't go
# through EquipmentInventory the way player heroes do.
static func apply_to_unit(unit: UnitBase, item: EquipmentItem) -> void:
	unit.max_hp += int(item.stat_bonus.get("hp", 0))
	unit.current_hp += int(item.stat_bonus.get("hp", 0))
	unit.max_mana += int(item.stat_bonus.get("mana", 0))
	unit.current_mana += int(item.stat_bonus.get("mana", 0))
	unit.attack_damage += int(item.stat_bonus.get("atk", 0))
	unit.magic_power += int(item.stat_bonus.get("magic", 0))
	unit.resistance += int(item.stat_bonus.get("res", 0))
	unit.attack_speed += item.stat_bonus.get("aspd", 0.0)
	unit.hp_regen += item.stat_bonus.get("hpregen", 0.0)
	unit.mana_regen += item.stat_bonus.get("manaregen", 0.0)
	if item.passive_effect != "":
		var existing: float = unit.equipment_passives.get(item.passive_effect, 0.0)
		unit.equipment_passives[item.passive_effect] = maxf(existing, item.effect_value)

static func generate_item(round: int = 1, max_rarity: int = EquipmentItem.Rarity.RARE) -> EquipmentItem:
	var templates = ITEM_TEMPLATES.keys()
	var template_key = templates[randi() % templates.size()]
	var template = ITEM_TEMPLATES[template_key]

	var rarity = _roll_rarity(round, max_rarity)
	var item = EquipmentItem.new(template["name"], rarity)
	item.description = "%s %s" % [item.get_rarity_name(), template["name"]]

	# Spend the rarity's points budget: 1 stat roll = 1 point; a passive (RARE+
	# only) costs 2 points. So a Rare (4-pt) item is 4 stats OR 2 stats + passive.
	var points: int = int(RARITY_POINTS.get(rarity, 1))

	if rarity >= PASSIVE_MIN_RARITY and points > PASSIVE_COST \
			and randf() < float(PASSIVE_CHANCE.get(rarity, 0.0)):
		var passive = PASSIVE_EFFECTS[randi() % PASSIVE_EFFECTS.size()]
		item.passive_effect = passive["name"]
		item.description = passive["desc"]
		item.effect_value = 0.15 + randf() * 0.15  # 0.15-0.30
		points -= PASSIVE_COST

	# First point always rolls the item's primary (identity) stat; the rest hit
	# random stats.
	var available_stats = ["hp", "mana", "atk", "magic", "res", "aspd", "hpregen", "manaregen"]
	var primary: String = template.get("primary", "atk")
	for i in range(points):
		var stat: String = primary if i == 0 else available_stats[randi() % available_stats.size()]
		if stat in FLOAT_STATS:
			item.stat_bonus[stat] += _roll_float_stat_value(rarity, round)
		else:
			var value: int = _roll_stat_value(rarity, round)
			# HP/mana rolls read as flat pools, not per-hit damage — a raw roll
			# feels negligible next to units with hundreds/thousands of HP, so
			# these two get a straight 10x on top of everything else (2026-07-09
			# user request).
			if stat in BIG_STATS:
				value *= BIG_STATS_MULT
			item.stat_bonus[stat] += value

	return item

const BIG_STATS: Array[String] = ["hp", "mana"]
const BIG_STATS_MULT := 10

static func _roll_rarity(round: int, max_rarity: int = EquipmentItem.Rarity.RARE) -> int:
	var roll = randf()
	var legendary_chance = 0.01 + (round * 0.01)
	var epic_chance      = 0.10 + (round * 0.05)
	var rare_chance      = 0.20 + (round * 0.06)
	var uncommon_chance  = 0.30 + (round * 0.05)

	# Clamp to the allowed ceiling (Legendary only from shops/events, never drops)
	if max_rarity < EquipmentItem.Rarity.LEGENDARY:
		legendary_chance = 0.0
	if max_rarity < EquipmentItem.Rarity.EPIC:
		epic_chance = 0.0
	if max_rarity < EquipmentItem.Rarity.RARE:
		rare_chance = 0.0
	if max_rarity < EquipmentItem.Rarity.UNCOMMON:
		uncommon_chance = 0.0

	if roll < legendary_chance:
		return EquipmentItem.Rarity.LEGENDARY
	elif roll < legendary_chance + epic_chance:
		return EquipmentItem.Rarity.EPIC
	elif roll < legendary_chance + epic_chance + rare_chance:
		return EquipmentItem.Rarity.RARE
	elif roll < legendary_chance + epic_chance + rare_chance + uncommon_chance:
		return EquipmentItem.Rarity.UNCOMMON
	else:
		return EquipmentItem.Rarity.COMMON

static func _roll_stat_value(rarity: int, round: int) -> int:
	var base_value = 3 + (round * 0.5)
	var roll = base_value * (0.8 + randf() * 0.4)
	var multiplier = 1.0 + (rarity * 0.3)
	return int(roll * multiplier)

# Small-magnitude version for attack_speed/hp_regen/mana_regen bonuses (0.05–0.3ish per roll).
static func _roll_float_stat_value(rarity: int, round: int) -> float:
	var base_value = 0.05 + (round * 0.01)
	var roll = base_value * (0.8 + randf() * 0.4)
	var multiplier = 1.0 + (rarity * 0.3)
	return snappedf(roll * multiplier, 0.01)

# Combine 3 items of same rarity → one item of the next rarity whose stats are
# the SUM of all three. Inherits the identity (name/icon) of the strongest input
# so bag icons (keyed by name) still resolve; the higher rarity conveys "upgraded".
static func combine_items(items: Array[EquipmentItem]) -> EquipmentItem:
	if items.size() < 3:
		return null

	# Base identity = the input with the biggest total stat bonus.
	var base = items[0]
	for item in items:
		if item.get_total_stat_bonus() > base.get_total_stat_bonus():
			base = item

	var combined = EquipmentItem.new(base.name, base.rarity + 1)
	combined.description = base.description

	for item in items:
		for stat in item.stat_bonus:
			combined.stat_bonus[stat] += item.stat_bonus[stat]

	# Keep a passive: prefer the base's, else the first input that has one.
	if base.passive_effect != "":
		combined.passive_effect = base.passive_effect
		combined.effect_value = base.effect_value
	else:
		for item in items:
			if item.passive_effect != "":
				combined.passive_effect = item.passive_effect
				combined.effect_value = item.effect_value
				break

	return combined
