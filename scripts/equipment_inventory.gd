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
		return hero_equipment[unit_id]
	return []

func _apply_equipment_bonuses(unit: UnitBase, item: EquipmentItem) -> void:
	# Apply stat bonuses
	unit.max_hp += item.stat_bonus.get("hp", 0)
	unit.current_hp = unit.max_hp
	unit.max_mana += item.stat_bonus.get("mana", 0)
	unit.current_mana = unit.max_mana
	unit.strength += item.stat_bonus.get("str", 0)
	unit.dexterity += item.stat_bonus.get("dex", 0)
	unit.intelligence += item.stat_bonus.get("int", 0)
	unit.resistance += item.stat_bonus.get("res", 0)
	unit.spirit += item.stat_bonus.get("spr", 0)

func _remove_equipment_bonuses(unit: UnitBase, item: EquipmentItem) -> void:
	# Remove stat bonuses
	unit.max_hp -= item.stat_bonus.get("hp", 0)
	unit.current_hp = mini(unit.current_hp, unit.max_hp)
	unit.max_mana -= item.stat_bonus.get("mana", 0)
	unit.current_mana = mini(unit.current_mana, unit.max_mana)
	unit.strength -= item.stat_bonus.get("str", 0)
	unit.dexterity -= item.stat_bonus.get("dex", 0)
	unit.intelligence -= item.stat_bonus.get("int", 0)
	unit.resistance -= item.stat_bonus.get("res", 0)
	unit.spirit -= item.stat_bonus.get("spr", 0)
