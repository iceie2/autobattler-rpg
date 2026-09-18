extends Node
class_name EquipmentInventory

const MAX_ITEMS = 30  # Total inventory size (global)
# Heroes start with a single equipment slot; every "+1 Equipment" node bought in
# the crystal tree (family equipment_slot, 5 levels total) unlocks one more, so
# a fully-invested account caps out at 6 (2026-08-03 user spec).
const HERO_BASE_ITEMS = 1
const HERO_MAX_ITEMS = 6  # Hard ceiling once every crystal upgrade is bought

# Current per-hero equipment cap for this account.
func hero_item_cap() -> int:
	return clampi(HERO_BASE_ITEMS + Progression.get_bonus("+1 Equipment"), HERO_BASE_ITEMS, HERO_MAX_ITEMS)

var items: Array[EquipmentItem] = []
var hero_equipment: Dictionary = {}  # unit_id -> Array of EquipmentItem

# Auto-Combine toggle (2026-08-06 user spec): while on, every item picked up
# is checked against the bag and fused the moment 3 same-rarity items exist.
# Off by default so nothing is consumed without opting in.
var auto_combine: bool = false

# When a triple's passive candidates exceed the result's cap, the player still
# has a real choice to make (2026-08-06 follow-up) — the sweep pauses instead
# of silently auto-picking, and the UI is expected to call resolve_auto_pick()
# / cancel_auto_pick() once the player answers.
signal auto_combine_pick_needed(sources: Array, candidates: Array, cap: int)
var _pending_pick: bool = false

func set_auto_combine(enabled: bool) -> void:
	auto_combine = enabled
	if auto_combine and not _pending_pick:
		_auto_combine_sweep()

# One-shot sweep for the equipment panel's own "Auto" button — same pause-and-
# ask behavior as the persistent toggle, without turning the toggle on.
func run_auto_combine_once() -> void:
	if not _pending_pick:
		_auto_combine_sweep()

# Called by the UI once the player confirms which passives to keep on a
# paused fusion. Resumes sweeping the rest of the bag afterward.
func resolve_auto_pick(sources: Array[EquipmentItem], keep: Array) -> void:
	var combined: EquipmentItem = EquipmentManager.combine_items(sources, keep)
	if combined:
		log_fusion(sources, EquipmentManager.passive_cap(sources[0].rarity + 1),
				EquipmentManager.candidate_passives(sources), keep)
		for it in sources:
			items.erase(it)
		items.append(combined)
	_pending_pick = false
	inventory_changed.emit()
	if auto_combine:
		_auto_combine_sweep()

# Called by the UI if the player dismisses the pick without choosing — the
# triple is left untouched in the bag; sweeping resumes on the next pickup.
func cancel_auto_pick() -> void:
	_pending_pick = false

# Balance export (2026-08-05): one entry per fusion — {"cap", "available",
# "picked"} — read by RunHistory to see if testers engage with the passive-pick
# dialog or just default to whatever's auto-kept.
var fusion_log: Array = []

# Single logging point for EVERY fusion, wherever it happens (2026-08-07).
# The log used to be written only by the manual Fuse button, and only when the
# inputs offered passives — so auto-combine fusions and all Common→Uncommon
# fusions (three Commons have no passives at all, since passives exist only on
# combined gear) were invisible. A tester who fused dozens of items exported a
# log with ONE entry, which read as "nobody uses combining" when the truth was
# "the log can't see it". Every path calls this now.
func log_fusion(sources: Array, cap: int, candidates: Array, picked: Array) -> void:
	var available: Array = []
	for c in candidates:
		available.append(str(c["name"]))
	var from_rarity: int = (sources[0] as EquipmentItem).rarity if not sources.is_empty() else -1
	fusion_log.append({
		"cap": cap,
		"available": available,
		"picked": picked.duplicate(),
		# A fusion with no passive candidates is still a fusion — it just had
		# nothing to choose. Recording it is the whole point.
		"was_a_choice": candidates.size() > cap and cap > 0,
		"from_rarity": from_rarity,
		"to_rarity": from_rarity + 1,
	})

signal inventory_changed
signal hero_equipment_changed(unit_id: String)

func add_item(item: EquipmentItem) -> bool:
	if items.size() >= MAX_ITEMS:
		return false
	items.append(item)
	if auto_combine and not _pending_pick:
		_auto_combine_sweep()
	inventory_changed.emit()
	return true

# Fuse every triple of same-rarity bag items it can find, cascading upward
# (3 commons -> 1 uncommon can itself join 2 other uncommons, etc). Mixed item
# types within a triple are allowed — same rule EquipmentManager.combine_items
# already uses for manual Fuse. If a triple's passives exceed the result's
# cap, the sweep PAUSES and asks the UI to let the player choose (see
# auto_combine_pick_needed) instead of guessing for them.
func _auto_combine_sweep() -> void:
	while true:
		var by_rarity: Dictionary = {}
		for it in items:
			var r: int = it.rarity
			if r >= EquipmentItem.Rarity.LEGENDARY:
				continue
			if not by_rarity.has(r):
				by_rarity[r] = []
			by_rarity[r].append(it)

		var triple: Array = []
		for r in by_rarity:
			if (by_rarity[r] as Array).size() >= 3:
				triple = (by_rarity[r] as Array).slice(0, 3)
				break
		if triple.is_empty():
			return

		var sources: Array[EquipmentItem] = []
		for it in triple:
			sources.append(it as EquipmentItem)

		var cap: int = EquipmentManager.passive_cap(sources[0].rarity + 1)
		var candidates: Array = EquipmentManager.candidate_passives(sources)
		if candidates.size() > cap and cap > 0:
			_pending_pick = true
			auto_combine_pick_needed.emit(sources, candidates, cap)
			return

		var combined: EquipmentItem = EquipmentManager.combine_items(sources)
		if combined == null:
			return
		log_fusion(sources, cap, candidates, [])
		for it in sources:
			items.erase(it)
		items.append(combined)

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
	if hero_items.size() >= hero_item_cap():
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

# Move every item a hero has equipped back to the bag (used when selling a
# hero, 2026-07-17 — the loot isn't lost with the unit).
func return_all_from_hero(unit: UnitBase) -> void:
	var unit_id = unit.unit_name + "_" + str(unit.get_instance_id())
	if not hero_equipment.has(unit_id):
		return
	for item in (hero_equipment[unit_id] as Array).duplicate():
		items.append(item)
	hero_equipment.erase(unit_id)
	inventory_changed.emit()
	hero_equipment_changed.emit(unit_id)

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
	# "ten" is not rolled by any generator yet (2026-08-07) — wired here so gear
	# CAN carry tenacity, and so the add/remove pair stays symmetric the day it does.
	unit.tenacity += item.stat_bonus.get("ten", 0)
	unit.attack_speed += item.stat_bonus.get("aspd", 0.0)
	unit.hp_regen += item.stat_bonus.get("hpregen", 0.0)
	unit.mana_regen += item.stat_bonus.get("manaregen", 0.0)
	unit.crit_chance += item.stat_bonus.get("crit", 0.0)
	unit.crit_damage += item.stat_bonus.get("critdmg", 0.0)

	for p in item.passives:
		var existing: float = unit.equipment_passives.get(p["name"], 0.0)
		unit.equipment_passives[p["name"]] = maxf(existing, p["value"])

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
	unit.tenacity = maxi(0, unit.tenacity - item.stat_bonus.get("ten", 0))
	unit.attack_speed -= item.stat_bonus.get("aspd", 0.0)
	unit.hp_regen -= item.stat_bonus.get("hpregen", 0.0)
	unit.mana_regen -= item.stat_bonus.get("manaregen", 0.0)
	unit.crit_chance -= item.stat_bonus.get("crit", 0.0)
	unit.crit_damage -= item.stat_bonus.get("critdmg", 0.0)

	_rebuild_passives(unit)

func _rebuild_passives(unit: UnitBase) -> void:
	unit.equipment_passives.clear()
	var unit_id: String = unit.unit_name + "_" + str(unit.get_instance_id())
	if not hero_equipment.has(unit_id):
		return
	for equipped_item in hero_equipment[unit_id]:
		for p in equipped_item.passives:
			var existing: float = unit.equipment_passives.get(p["name"], 0.0)
			unit.equipment_passives[p["name"]] = maxf(existing, p["value"])
