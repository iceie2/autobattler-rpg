extends RefCounted
class_name MerchantServices

# Rules are separate from the shop stock: services never reroll its rewards.
static func cost(kind: String, round_number: int, rarity: int = 0) -> int:
	var base := 0
	match kind:
		"reforge": base = Balance.MERCHANT_REFORGE_BASE + rarity * Balance.MERCHANT_RARITY_STEP
		"exchange": base = Balance.MERCHANT_EXCHANGE_BASE + rarity * Balance.MERCHANT_RARITY_STEP
		"enchant": base = Balance.MERCHANT_ENCHANT_BASE + rarity * Balance.MERCHANT_RARITY_STEP
		"training": base = Balance.MERCHANT_TRAINING_BASE
		"supplies": base = Balance.MERCHANT_SUPPLIES_BASE
	return maxi(1, roundi(base * ShopGenerator.round_scale(round_number)))

static func training_xp(unit: UnitBase) -> int:
	return maxi(1, roundi(unit.xp_to_level * Balance.MERCHANT_TRAINING_XP_FRACTION))

static func reforge(item: EquipmentItem, round_number: int) -> EquipmentItem:
	if item is ComponentEquipmentItem:
		var result := ComponentEquipmentRules.from_dict(ComponentEquipmentRules.to_dict(item))
		if result == null: return null
		for stat in result.stat_bonus: result.stat_bonus[stat] = 0
		# A component item contains 2 rolls per grey ancestor. Reroll those
		# families while retaining the exact composition and passive budget.
		for family in item.composition:
			for i in range(int(item.composition[family]) * 2):
				result.stat_bonus[family] += ComponentEquipmentRules._roll_value(str(family), round_number)
		ComponentEquipmentRules.refresh(result)
		return result
	var result := _roll_legacy(item.name, item.rarity, round_number)
	result.id = item.id
	result.description = item.description
	result.passives = item.passives.duplicate(true)
	return result

static func exchange(item: EquipmentItem, round_number: int) -> EquipmentItem:
	if item is ComponentEquipmentItem:
		return ComponentEquipmentRules.generate_item(round_number, item.rarity, ComponentEquipmentInventory.STAT_KEEP)
	# Legacy saves retain their own equipment economy and exact rarity.
	var template: Dictionary = EquipmentManager.ITEM_TEMPLATES.values().pick_random()
	return _roll_legacy(str(template["name"]), item.rarity, round_number)

static func _roll_legacy(name: String, rarity: int, round_number: int) -> EquipmentItem:
	var result := EquipmentItem.new(name, rarity)
	result.description = "%s %s" % [result.get_rarity_name(), result.name]
	var primary := "atk"
	for entry in EquipmentManager.ITEM_TEMPLATES.values():
		if entry["name"] == name:
			primary = str(entry["primary"])
			break
	var stats: Array = ["hp", "mana", "atk", "magic", "res", "aspd", "hpregen", "manaregen", "crit", "critdmg"]
	for i in range(EquipmentManager.RARITY_STAT_ROLLS[rarity]):
		var stat: String = primary if i == 0 else stats.pick_random()
		var value: float
		if stat in EquipmentManager.CRIT_STATS:
			value = EquipmentManager._roll_crit_stat_value(stat, rarity)
		elif stat in EquipmentManager.FLOAT_STATS:
			value = EquipmentManager._roll_float_stat_value(rarity, round_number)
		else:
			value = EquipmentManager._roll_stat_value(rarity, round_number)
			if stat in EquipmentManager.BIG_STATS: value *= EquipmentManager.BIG_STATS_MULT
		result.stat_bonus[stat] += value
	return result

static func modifier_choices(item: EquipmentItem) -> Array:
	var out: Array = []
	if item is ComponentEquipmentItem:
		for key in item.passive_levels:
			out.append({"key": str(key), "label": "Replace 1 level of " + GearCatalog.display_name(key)})
	else:
		if item.passives.size() < EquipmentManager.passive_cap(item.rarity):
			out.append({"key": "", "label": "Add a new modifier"})
		for passive in item.passives:
			out.append({"key": passive["name"], "label": "Replace " + str(passive["name"])})
	return out

static func enchant(item: EquipmentItem, replace_key: String) -> EquipmentItem:
	var valid := false
	for choice in modifier_choices(item):
		if choice["key"] == replace_key: valid = true
	if not valid: return null
	if item is ComponentEquipmentItem:
		var result := ComponentEquipmentRules.from_dict(ComponentEquipmentRules.to_dict(item))
		var pool := GearCatalog.PASSIVES.keys()
		pool.erase(replace_key)
		var key: String = str(pool.pick_random())
		result.passive_levels[replace_key] -= 1
		if result.passive_levels[replace_key] <= 0: result.passive_levels.erase(replace_key)
		result.passive_levels[key] = int(result.passive_levels.get(key, 0)) + 1
		for counter in ComponentEquipmentItem.COUNTERS:
			if not result.passive_levels.has(ComponentEquipmentItem.COUNTERS[counter]):
				result.counters.erase(counter)
		ComponentEquipmentRules.refresh(result)
		return result
	var result := EquipmentItem.new(item.name, item.rarity)
	result.id = item.id
	result.description = item.description
	result.stat_bonus = item.stat_bonus.duplicate(true)
	result.passives = item.passives.duplicate(true)
	var pool: Array = []
	for p in EquipmentManager.PASSIVE_EFFECTS:
		var present := false
		for old in item.passives:
			if old["name"] == p["name"]: present = true
		if not present: pool.append(p["name"])
	if pool.is_empty(): return null
	for i in range(result.passives.size() - 1, -1, -1):
		if result.passives[i]["name"] == replace_key: result.passives.remove_at(i)
	result.add_passive(str(pool.pick_random()), 0.05 + randf() * 0.10)
	return result
