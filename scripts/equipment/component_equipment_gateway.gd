extends RefCounted
class_name ComponentEquipmentGateway

# Flip only after the 36 passives (GearPassives), their cues, and arena tuning
# are verified. Saved runs retain their own mode regardless of this default.
const ENABLE_FOR_NEW_RUNS := false
static var active_run: bool = false

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
