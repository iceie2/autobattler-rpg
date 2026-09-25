extends RefCounted
class_name ComponentEquipmentRules

# Pure merge rules for the component equipment system (EQUIPMENT_GREEN_PAIRS.md,
# 2026-09-25). Only reached through ComponentEquipmentGateway; the old generator,
# inventory and item class stay in production while the switch is off.
#
#   grey   = one component, two stat rolls, no passive
#   green  = two greys; its passive comes from the pair's families (36 passives)
#   blue+  = two items of one tier; passives pool (same names add levels) and
#            the player removes levels until the pool fits the result's budget.

const COMPONENTS := ["hp", "atk", "magic", "cdr", "aspd", "crit", "res",
	"magic_resist", "hpregen", "manaregen"]
const FAMILY_NAME := {
	"hp": "Heart", "atk": "Sword", "magic": "Staff", "cdr": "Hourglass",
	"aspd": "Gauntlet", "crit": "Dagger", "res": "Shield", "magic_resist": "Ward",
	"hpregen": "Salve", "manaregen": "Chalice",
}
const COMPONENTS_BY_RARITY := [1, 2, 4, 8, 16]
# Passive LEVEL budget per tier (user decision: green 1, blue 2, purple 3, gold 4).
const PASSIVE_BUDGET := [0, 1, 2, 3, 4]
const FLOAT_STATS := ["aspd", "hpregen", "manaregen", "crit", "critdmg"]
const SAVE_SYSTEM := "components_v2"

static func create_common(family: String, stats: Dictionary = {}) -> ComponentEquipmentItem:
	if not family in COMPONENTS:
		return null
	var item := ComponentEquipmentItem.new(str(FAMILY_NAME[family]), EquipmentItem.Rarity.COMMON)
	item.composition[family] = 1
	for stat in stats:
		if item.stat_bonus.has(stat):
			item.stat_bonus[stat] = stats[stat]
	return item

# Two stat rolls per grey. cdr is Ability Haste (flat 3-6 per roll, not
# round-scaled, like crit). Regen rolls are provisional arena numbers.
static func _roll_value(family: String, round_number: int) -> Variant:
	var spread := 0.8 + randf() * 0.4
	match family:
		"crit": return snappedf(0.03 + randf() * 0.03, 0.01)
		"cdr": return randi_range(3, 6)
		"aspd": return snappedf((0.05 + round_number * 0.005) * spread, 0.01)
		"hpregen": return snappedf((0.3 + round_number * 0.03) * spread, 0.01)
		"manaregen": return snappedf((0.2 + round_number * 0.01) * spread, 0.01)
	var v := int((3.0 + round_number * 0.25) * spread)
	return v * 10 if family == "hp" else v

static func _roll_common(family: String, round_number: int) -> ComponentEquipmentItem:
	var stats: Dictionary = {}
	for i in range(2):
		stats[family] = stats.get(family, 0) + _roll_value(family, round_number)
	return create_common(family, stats)

# A direct higher-rarity drop is built from random legal greys, merging with
# random level removals, so it is indistinguishable from a player-made item.
static func generate_item(round_number: int = 1,
		rarity: int = EquipmentItem.Rarity.COMMON,
		stat_keep: float = 1.0) -> ComponentEquipmentItem:
	if rarity < EquipmentItem.Rarity.COMMON or rarity > EquipmentItem.Rarity.LEGENDARY:
		return null
	var tier: Array[ComponentEquipmentItem] = []
	for i in range(1 << rarity):
		tier.append(_roll_common(str(COMPONENTS.pick_random()), round_number))
	while tier.size() > 1:
		var next_tier: Array[ComponentEquipmentItem] = []
		for i in range(0, tier.size(), 2):
			next_tier.append(combine(tier[i], tier[i + 1], stat_keep,
				random_removals(tier[i], tier[i + 1])))
		tier = next_tier
	return tier[0]

# Most levels, first-merged wins ties (Dictionary keeps insertion order).
static func dominant_passive(levels: Dictionary) -> String:
	var best := ""
	var highest := 0
	for key in levels:
		if int(levels[key]) > highest:
			best = str(key)
			highest = int(levels[key])
	return best

static func dominant_family(composition: Dictionary) -> String:
	var best := ""
	var highest := -1
	for family in COMPONENTS:
		var count := int(composition.get(family, 0))
		if count > highest:
			best = family
			highest = count
	return best

static func can_combine(a: ComponentEquipmentItem, b: ComponentEquipmentItem) -> bool:
	if a == null or b == null or a == b or a.rarity != b.rarity:
		return false
	if a.rarity >= EquipmentItem.Rarity.LEGENDARY:
		return false
	for item in [a, b]:
		if item.component_count() != COMPONENTS_BY_RARITY[item.rarity] \
				or item.passive_level_count() != PASSIVE_BUDGET[item.rarity]:
			return false
	if a.rarity == EquipmentItem.Rarity.COMMON:
		return GearCatalog.passive_for_components(
			dominant_family(a.composition), dominant_family(b.composition)) != ""
	return true

# Passive levels both inputs offer, a's passives first. Greys offer the one
# passive their pair creates.
static func pooled_levels(a: ComponentEquipmentItem, b: ComponentEquipmentItem) -> Dictionary:
	if a.rarity == EquipmentItem.Rarity.COMMON:
		var key := GearCatalog.passive_for_components(
			dominant_family(a.composition), dominant_family(b.composition))
		return {key: 1} if key != "" else {}
	var pool: Dictionary = a.passive_levels.duplicate()
	for key in b.passive_levels:
		pool[key] = int(pool.get(key, 0)) + int(b.passive_levels[key])
	return pool

# How many levels the player must remove (0 = no menu).
static func levels_to_remove(a: ComponentEquipmentItem, b: ComponentEquipmentItem) -> int:
	var total := 0
	for v in pooled_levels(a, b).values():
		total += int(v)
	return maxi(0, total - PASSIVE_BUDGET[a.rarity + 1])

static func random_removals(a: ComponentEquipmentItem, b: ComponentEquipmentItem) -> Dictionary:
	var pool := pooled_levels(a, b)
	var removals: Dictionary = {}
	for i in range(levels_to_remove(a, b)):
		var keys: Array = []
		for key in pool:
			if int(pool[key]) - int(removals.get(key, 0)) > 0:
				keys.append(key)
		var pick: String = str(keys.pick_random())
		removals[pick] = int(removals.get(pick, 0)) + 1
	return removals

# removals = {passive_key: levels_removed}. It must remove exactly
# levels_to_remove(a, b) levels, or the merge is refused (returns null).
static func combine(a: ComponentEquipmentItem, b: ComponentEquipmentItem,
		stat_keep: float = 1.0, removals: Dictionary = {}) -> ComponentEquipmentItem:
	if not can_combine(a, b):
		return null
	var pool := pooled_levels(a, b)
	var removed := 0
	for key in removals:
		var n := int(removals[key])
		if n < 0 or n > int(pool.get(key, 0)):
			return null
		removed += n
	if removed != levels_to_remove(a, b):
		return null

	var merged_composition: Dictionary = a.composition.duplicate()
	for family in b.composition:
		merged_composition[family] = int(merged_composition.get(family, 0)) + int(b.composition[family])
	var result := ComponentEquipmentItem.new("?", a.rarity + 1)
	result.composition = merged_composition
	for stat in result.stat_bonus:
		var value := (float(a.stat_bonus.get(stat, 0)) + float(b.stat_bonus.get(stat, 0))) * stat_keep
		result.stat_bonus[stat] = snappedf(value, 0.01) if stat in FLOAT_STATS else int(value)
	for key in pool:
		var left := int(pool[key]) - int(removals.get(key, 0))
		if left > 0:
			result.passive_levels[key] = left
	# Persistent counters (#23 Clockwork casts, #27 Battle Haste kills): counts
	# add when both inputs carry the passive; removing the passive entirely
	# discards its count.
	for counter in ComponentEquipmentItem.COUNTERS:
		var key: String = ComponentEquipmentItem.COUNTERS[counter]
		if result.passive_levels.has(key):
			result.counters[counter] = int(a.counters.get(counter, 0)) + int(b.counters.get(counter, 0))
	refresh(result)
	return result

static func refresh(item: ComponentEquipmentItem) -> void:
	var top := dominant_passive(item.passive_levels)
	item.name = GearCatalog.display_name(top) if top != "" \
		else str(FAMILY_NAME.get(dominant_family(item.composition), "Item"))
	# item.passives stays EMPTY on purpose: the legacy combat hooks read
	# unit.equipment_passives by name ("Lifesteal", "Thorns", ...) and would
	# double-fire. New passives reach combat only through unit.gear_levels.
	item.passives.clear()
	item.description = "\n".join(item.get_passive_lines())

static func to_dict(item: ComponentEquipmentItem) -> Dictionary:
	return {
		"system": SAVE_SYSTEM,
		"id": item.id,
		"name": item.name,
		"rarity": int(item.rarity),
		"stat_bonus": item.stat_bonus.duplicate(true),
		"icon_color": item.icon_color,
		"composition": item.composition.duplicate(true),
		# Array of pairs, not a Dictionary: order decides the icon's centre on ties.
		"passive_levels": _ordered(item.passive_levels),
		"counters": item.counters.duplicate(true),
	}

static func _ordered(levels: Dictionary) -> Array:
	var out: Array = []
	for key in levels:
		out.append([key, int(levels[key])])
	return out

static func from_dict(data: Dictionary) -> ComponentEquipmentItem:
	if str(data.get("system", "")) != SAVE_SYSTEM:
		return null
	var rarity: int = int(data.get("rarity", -1))
	if rarity < EquipmentItem.Rarity.COMMON or rarity > EquipmentItem.Rarity.LEGENDARY:
		return null
	var composition: Dictionary = data.get("composition", {})
	for family in composition:
		if not family in COMPONENTS or int(composition[family]) <= 0:
			return null
	var item := ComponentEquipmentItem.new(str(data.get("name", "?")), rarity)
	item.id = str(data.get("id", item.id))
	item.composition = composition.duplicate(true)
	for pair in data.get("passive_levels", []):
		if not (pair is Array) or pair.size() != 2 or not GearCatalog.PASSIVES.has(str(pair[0])) \
				or int(pair[1]) <= 0:
			return null
		item.passive_levels[str(pair[0])] = int(pair[1])
	if item.component_count() != COMPONENTS_BY_RARITY[rarity] \
			or item.passive_level_count() != PASSIVE_BUDGET[rarity]:
		return null
	var stats: Dictionary = data.get("stat_bonus", {})
	for stat in stats:
		if item.stat_bonus.has(stat):
			item.stat_bonus[stat] = stats[stat]
	var counters: Dictionary = data.get("counters", {})
	for counter in counters:
		if ComponentEquipmentItem.COUNTERS.has(counter):
			item.counters[counter] = int(counters[counter])
	refresh(item)
	return item
