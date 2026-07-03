extends Node
class_name EquipmentInventory

const MAX_ITEMS = 30  # Total inventory size (global)
const HERO_MAX_ITEMS = 6  # Max items per hero

var items: Array[EquipmentItem] = []
var hero_equipment: Dictionary = {}  # unit_id -> Array of EquipmentItem

signal inventory_changed
signal hero_equipment_changed(unit_id: String)

func add_item(item: EquipmentItem) -> bool:
	if items.size() >= MAX_ITEMS:
		return false
	items.append(item)
	inventory_changed.emit()
	return true

func remove_item(item: EquipmentItem) -> bool:
	if items.has(item):
		items.erase(item)
		inventory_changed.emit()
		return true
	return false

func apply_to_hero(item: EquipmentItem, unit: UnitBase) -> bool:
	var unit_id = unit.unit_name + "_" + str(unit.get_instance_id())

	if not hero_equipment.has(unit_id):
		hero_equipment[unit_id] = []

	var hero_items = hero_equipment[unit_id] as Array
	if hero_items.size() >= HERO_MAX_ITEMS:
		return false

	hero_items.append(item)
	if items.has(item):
		items.erase(item)

	_apply_equipment_bonuses(unit, item)
	inventory_changed.emit()
	hero_equipment_changed.emit(unit_id)
	return true

func remove_from_hero(item: EquipmentItem, unit: UnitBase) -> bool:
	var unit_id = unit.unit_name + "_" + str(unit.get_instance_id())

	if not hero_equipment.has(unit_id):
		return false

	var hero_items = hero_equipment[unit_id] as Array
	if hero_items.has(item):
		hero_items.erase(item)
		items.append(item)
		_remove_equipment_bonuses(unit, item)
		inventory_changed.emit()
		hero_equipment_changed.emit(unit_id)
		return true

	return false

func get_hero_equipment(unit: UnitBase) -> Array[EquipmentItem]:
	var unit_id = unit.unit_name + "_" + str(unit.get_instance_id())
	if hero_equipment.has(unit_id):
		var result: Array[EquipmentItem] = []
		result.assign(hero_equipment[unit_id])
		return result
	return []

func _apply_equipment_bonuses(unit: UnitBase, item: EquipmentItem) -> void:
	var hp_bonus: int = item.stat_bonus.get("hp", 0)
	unit.max_hp += hp_bonus
	unit.current_hp = mini(unit.current_hp + hp_bonus, unit.max_hp)

	var mana_bonus: int = item.stat_bonus.get("mana", 0)
	unit.max_mana += mana_bonus
	unit.current_mana = mini(unit.current_mana + mana_bonus, unit.max_mana)

	unit.attack_damage += item.stat_bonus.get("atk", 0)
	unit.magic_power += item.stat_bonus.get("magic", 0)
	unit.resistance += item.stat_bonus.get("res", 0)
	unit.attack_speed += item.stat_bonus.get("aspd", 0.0)
	unit.hp_regen += item.stat_bonus.get("hpregen", 0.0)
	unit.mana_regen += item.stat_bonus.get("manaregen", 0.0)

	if item.passive_effect != "":
		var existing: float = unit.equipment_passives.get(item.passive_effect, 0.0)
		unit.equipment_passives[item.passive_effect] = maxf(existing, item.effect_value)

func _remove_equipment_bonuses(unit: UnitBase, item: EquipmentItem) -> void:
	var hp_bonus: int = item.stat_bonus.get("hp", 0)
	unit.max_hp -= hp_bonus
	unit.current_hp = mini(unit.current_hp, unit.max_hp)

	var mana_bonus: int = item.stat_bonus.get("mana", 0)
	unit.max_mana -= mana_bonus
	unit.current_mana = mini(unit.current_mana, unit.max_mana)

	unit.attack_damage -= item.stat_bonus.get("atk", 0)
	unit.magic_power -= item.stat_bonus.get("magic", 0)
	unit.resistance -= item.stat_bonus.get("res", 0)
	unit.attack_speed -= item.stat_bonus.get("aspd", 0.0)
	unit.hp_regen -= item.stat_bonus.get("hpregen", 0.0)
	unit.mana_regen -= item.stat_bonus.get("manaregen", 0.0)

	_rebuild_passives(unit)

func _rebuild_passives(unit: UnitBase) -> void:
	unit.equipment_passives.clear()
	var unit_id: String = unit.unit_name + "_" + str(unit.get_instance_id())
	if not hero_equipment.has(unit_id):
		return
	for equipped_item in hero_equipment[unit_id]:
		if equipped_item.passive_effect != "":
			var existing: float = unit.equipment_passives.get(equipped_item.passive_effect, 0.0)
			unit.equipment_passives[equipped_item.passive_effect] = maxf(existing, equipped_item.effect_value)
