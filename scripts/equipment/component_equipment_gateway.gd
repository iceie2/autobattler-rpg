extends RefCounted
class_name ComponentEquipmentGateway

# ON since 2026-09-26 (user: route the new system into the game; arena tuning,
# cue review and icon art continue live). Saved runs retain their own mode, so
# a run started before the flip keeps the old equipment until it ends.
const ENABLE_FOR_NEW_RUNS := true
static var active_run: bool = false

# Item supply (owner 2026-09-29: "still tuned to when it took 3 to merge").
# Greys per tier went 3/9/27/81 -> 2/4/8/16, so the same drops reached every
# tier far sooner. 0.45 keeps BLUE arriving when it used to (4 / 0.45 ~= 9 old
# greys); green is a little slower, purple/gold still sooner. Scales the two
# unasked-for sources (enemy-held drops, item rewards); shop and event items
# are choices the player pays for, so they stay. Tune here only.
const ITEM_SUPPLY_MULT := 0.45

static func supply_mult() -> float:
	return ITEM_SUPPLY_MULT if active_run else 1.0

static func generate_item(round_number: int = 1,
		max_rarity: int = EquipmentItem.Rarity.RARE) -> EquipmentItem:
	if not active_run:
		return EquipmentManager.generate_item(round_number, max_rarity)
	var rarity: int = EquipmentManager._roll_rarity(round_number, max_rarity)
	return ComponentEquipmentRules.generate_item(round_number, rarity,
		ComponentEquipmentInventory.STAT_KEEP)

static func apply_to_unit(unit: UnitBase, item: EquipmentItem) -> void:
	EquipmentManager.apply_to_unit(unit, item)
	# Enemies carrying a dropped item get its stats only; item passives are a
	# hero mechanic and reach combat solely through the inventory's gear_levels.
	if item is ComponentEquipmentItem:
		unit.magic_resist += int(item.stat_bonus.get("magic_resist", 0))
		unit.ability_haste += int(item.stat_bonus.get("cdr", 0))
