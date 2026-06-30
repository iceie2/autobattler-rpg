extends Node
class_name EquipmentManager

# Item templates (base items that can be generated with random stats)
const ITEM_TEMPLATES = {
	"sword": {"name": "Sword", "base_stats": {"str": 5}},
	"shield": {"name": "Shield", "base_stats": {"res": 5}},
	"robe": {"name": "Robe", "base_stats": {"int": 5}},
	"gloves": {"name": "Gloves", "base_stats": {"dex": 5}},
	"ring": {"name": "Ring", "base_stats": {"spr": 3, "hp": 20}},
	"cloak": {"name": "Cloak", "base_stats": {"res": 3, "dex": 2}},
	"amulet": {"name": "Amulet", "base_stats": {"int": 3, "mana": 30}},
	"boots": {"name": "Boots", "base_stats": {"dex": 4}},
	"axe": {"name": "Axe", "base_stats": {"str": 7}},
	"staff": {"name": "Staff", "base_stats": {"int": 6, "mana": 40}},
	"bow": {"name": "Bow", "base_stats": {"dex": 6}},
	"plate": {"name": "Plate Armor", "base_stats": {"res": 8, "hp": 50}},
}

const PASSIVE_EFFECTS = [
	{"name": "Lifesteal", "desc": "Restore 15% of damage dealt as HP"},
	{"name": "Thorns", "desc": "Return 10% of damage taken"},
	{"name": "Haste", "desc": "+10% action speed"},
	{"name": "Regeneration", "desc": "+3 HP per turn"},
	{"name": "Spell Echo", "desc": "+20% magic power"},
	{"name": "Evasion", "desc": "+15% dodge chance"},
]

static func generate_item(round: int = 1) -> EquipmentItem:
	var templates = ITEM_TEMPLATES.keys()
	var template_key = templates[randi() % templates.size()]
	var template = ITEM_TEMPLATES[template_key]

	var rarity = _roll_rarity(round)
	var item = EquipmentItem.new(template["name"], rarity)
	item.description = "A powerful %s" % template["name"].to_lower()

	# Generate stats based on rarity
	var stat_roll_count = _get_stat_roll_count(rarity, round)
	var base_stats = template["base_stats"].duplicate()

	# Apply base stats
	for stat in base_stats:
		item.stat_bonus[stat] = base_stats[stat] * (1 + rarity * 0.3)

	# Roll additional random stats
	var available_stats = ["hp", "mana", "str", "dex", "int", "res", "spr"]
	for i in range(stat_roll_count):
		var stat = available_stats[randi() % available_stats.size()]
		var bonus = _roll_stat_value(rarity, round)
		item.stat_bonus[stat] += bonus

	# Chance to add passive effect (higher rarity = higher chance)
	if randf() < 0.2 + (rarity * 0.2):
		var passive = PASSIVE_EFFECTS[randi() % PASSIVE_EFFECTS.size()]
		item.passive_effect = passive["name"]
		item.description = passive["desc"]
		item.effect_value = 0.15 + randf() * 0.15  # 0.15-0.30

	return item

static func _roll_rarity(round: int) -> int:
	var roll = randf()
	var legendary_chance = 0.01 + (round * 0.01)
	var epic_chance = 0.10 + (round * 0.05)
	var rare_chance = 0.30 + (round * 0.10)

	if roll < legendary_chance:
		return EquipmentItem.Rarity.LEGENDARY
	elif roll < legendary_chance + epic_chance:
		return EquipmentItem.Rarity.EPIC
	elif roll < legendary_chance + epic_chance + rare_chance:
		return EquipmentItem.Rarity.RARE
	else:
		return EquipmentItem.Rarity.COMMON

static func _get_stat_roll_count(rarity: int, round: int) -> int:
	match rarity:
		EquipmentItem.Rarity.COMMON:    return 1
		EquipmentItem.Rarity.RARE:      return 2
		EquipmentItem.Rarity.EPIC:      return 3
		EquipmentItem.Rarity.LEGENDARY: return 4
		_: return 1

static func _roll_stat_value(rarity: int, round: int) -> int:
	var base_value = 3 + (round * 0.5)
	var roll = base_value * (0.8 + randf() * 0.4)
	var multiplier = 1.0 + (rarity * 0.3)
	return int(roll * multiplier)

# Combine 3 items of same rarity → upgrade to next rarity
static func combine_items(items: Array[EquipmentItem]) -> EquipmentItem:
	if items.size() < 3:
		return null

	var first = items[0]
	var combined = EquipmentItem.new(first.name + " (Enhanced)", first.rarity + 1)
	combined.description = first.description + " - enhanced from combination"

	for item in items:
		for stat in item.stat_bonus:
			combined.stat_bonus[stat] += item.stat_bonus[stat]

	# Average passive effect
	for item in items:
		if item.passive_effect != "":
			combined.passive_effect = item.passive_effect
			combined.effect_value = item.effect_value
			break

	return combined
