extends EquipmentInventory
class_name ComponentEquipmentInventory

# New-system inventory. The production inventory remains available for old
# saves and while the feature flag is off.
const STAT_KEEP := 1.0  # Provisional until two-input arena tuning.

# removals: {passive_key: levels} chosen in the merge menu; must remove exactly
# ComponentEquipmentRules.levels_to_remove(a, b) levels.
func combine_components(sources: Array[EquipmentItem], removals: Dictionary = {}) -> ComponentEquipmentItem:
	if sources.size() != 2 or not (sources[0] is ComponentEquipmentItem) \
			or not (sources[1] is ComponentEquipmentItem):
		return null
	if not items.has(sources[0]) or not items.has(sources[1]):
		return null
	var result := ComponentEquipmentRules.combine(
		sources[0] as ComponentEquipmentItem,
		sources[1] as ComponentEquipmentItem, STAT_KEEP, removals)
	if result == null:
		return null
	for item in sources:
		items.erase(item)
	items.append(result)
	_log(sources, result, removals)
	inventory_changed.emit()
	if auto_combine:
		_auto_combine_sweep()
	return result

func _log(sources: Array[EquipmentItem], result: ComponentEquipmentItem, removals: Dictionary) -> void:
	var removed: Array = []
	for key in removals:
		for i in range(int(removals[key])):
			removed.append(key)
	fusion_log.append({
		"cap": ComponentEquipmentRules.PASSIVE_BUDGET[result.rarity],
		"available": result.passive_levels.keys(),
		"picked": removed,
		"was_a_choice": not removed.is_empty(),
		"from_rarity": sources[0].rarity,
		"to_rarity": result.rarity,
	})

# Auto-merge only performs merges that need no choice (user decision
# 2026-09-25): two IDENTICAL greys (HP+HP -> Last Bastion; added 2026-09-26 —
# mixed grey pairs pick a passive, so those stay manual / drag-to-combine), and
# green -> blue, greens sharing a passive first so blues come out focused.
# Anything that would open the merge menu stops.
func _auto_combine_sweep() -> void:
	while _auto_pair_identical_greys():
		pass
	while true:
		var greens: Array[ComponentEquipmentItem] = []
		for it in items:
			if it is ComponentEquipmentItem and it.rarity == EquipmentItem.Rarity.UNCOMMON:
				greens.append(it as ComponentEquipmentItem)
		if greens.size() < 2:
			return
		var pair: Array[ComponentEquipmentItem] = []
		for i in range(greens.size()):
			for j in range(i + 1, greens.size()):
				if greens[i].passive_levels.keys() == greens[j].passive_levels.keys():
					pair = [greens[i], greens[j]]
					break
			if not pair.is_empty():
				break
		if pair.is_empty():
			pair = [greens[0], greens[1]]
		if ComponentEquipmentRules.levels_to_remove(pair[0], pair[1]) > 0:
			return
		var result := ComponentEquipmentRules.combine(pair[0], pair[1], STAT_KEEP)
		if result == null:
			return
		items.erase(pair[0])
		items.erase(pair[1])
		items.append(result)
		var sources: Array[EquipmentItem] = [pair[0], pair[1]]
		_log(sources, result, {})
		inventory_changed.emit()

func _auto_pair_identical_greys() -> bool:
	var seen: Dictionary = {}
	for it in items:
		if it is ComponentEquipmentItem and it.rarity == EquipmentItem.Rarity.COMMON:
			var fam := ComponentEquipmentRules.dominant_family(it.composition)
			if seen.has(fam):
				var a: ComponentEquipmentItem = seen[fam]
				var result := ComponentEquipmentRules.combine(a, it, STAT_KEEP)
				if result == null:
					return false
				items.erase(a)
				items.erase(it)
				items.append(result)
				var sources: Array[EquipmentItem] = [a, it]
				_log(sources, result, {})
				inventory_changed.emit()
				return true
			seen[fam] = it
	return false

func _apply_equipment_bonuses(unit: UnitBase, item: EquipmentItem) -> void:
	super._apply_equipment_bonuses(unit, item)
	unit.magic_resist += int(item.stat_bonus.get("magic_resist", 0))
	unit.ability_haste += int(item.stat_bonus.get("cdr", 0))
	_rebuild_passives(unit)

func _remove_equipment_bonuses(unit: UnitBase, item: EquipmentItem) -> void:
	unit.magic_resist -= int(item.stat_bonus.get("magic_resist", 0))
	unit.ability_haste = maxi(0, unit.ability_haste - int(item.stat_bonus.get("cdr", 0)))
	super._remove_equipment_bonuses(unit, item)   # ends in _rebuild_passives

# Levels of each passive summed across the hero's equipped items (L = 1..24),
# plus the items themselves so run-persistent counters can be written back.
func _rebuild_passives(unit: UnitBase) -> void:
	unit.equipment_passives.clear()
	unit.gear_levels.clear()
	unit.gear_items.clear()
	var unit_id := unit.unit_name + "_" + str(unit.get_instance_id())
	if not hero_equipment.has(unit_id):
		return
	for item in hero_equipment[unit_id]:
		if not (item is ComponentEquipmentItem):
			continue
		unit.gear_items.append(item)
		for key in item.passive_levels:
			unit.gear_levels[key] = int(unit.gear_levels.get(key, 0)) + int(item.passive_levels[key])
