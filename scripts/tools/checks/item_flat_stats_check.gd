extends Node

# Same random rolls must yield the same item at every wave, in both systems.
func _ready() -> void:
	for sample in range(30):
		for rarity in range(5):
			seed(8100 + sample)
			var early := ComponentEquipmentRules.generate_item(1, rarity)
			seed(8100 + sample)
			var late := ComponentEquipmentRules.generate_item(100, rarity)
			assert(early.stat_bonus == late.stat_bonus, "Component stats changed with wave")
		for mode in [false, true]:
			ComponentEquipmentGateway.active_run = mode
			seed(8100 + sample)
			var early := ComponentEquipmentGateway.generate_item(1)
			seed(8100 + sample)
			var late := ComponentEquipmentGateway.generate_item(100)
			assert(early.stat_bonus == late.stat_bonus, "Gateway stats changed with wave")
		for rarity in range(5):
			seed(8100 + sample)
			var integer := EquipmentManager._roll_stat_value(rarity, 1)
			seed(8100 + sample)
			assert(integer == EquipmentManager._roll_stat_value(rarity, 100))
			seed(8100 + sample)
			var small := EquipmentManager._roll_float_stat_value(rarity, 1)
			seed(8100 + sample)
			assert(small == EquipmentManager._roll_float_stat_value(rarity, 100))
	var sword := ComponentEquipmentRules.create_common("atk", {"atk": 10})
	var restored := ComponentEquipmentRules.from_dict(ComponentEquipmentRules.to_dict(sword))
	assert(restored.stat_bonus["atk"] == 10, "Saved sword bonus changed")
	var unit := UnitBase.new()
	var before := unit.attack_damage
	ComponentEquipmentGateway.apply_to_unit(unit, restored)
	assert(unit.attack_damage == before + 10, "Combat did not receive exactly +10 attack")
	unit.free()
	print("ITEM_FLAT_STATS: ALL PASS")
	get_tree().quit()
