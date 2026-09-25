extends EquipmentItem
class_name ComponentEquipmentItem

# New-system state. The production EquipmentItem class stays unchanged.
# composition counts grey ancestors; passive_levels maps GearCatalog passive
# keys to levels (insertion order matters: first-merged wins icon ties).
var composition: Dictionary = {}
var passive_levels: Dictionary = {}
# Run-persistent counters that live ON the item (they travel with it between
# heroes and add on merges). counter name -> passive that owns it.
const COUNTERS := {"clockwork_casts": "clockwork", "haste_kills": "battle_haste"}
var counters: Dictionary = {}

func get_passive_lines() -> Array:
	var lines: Array = []
	for key in passive_levels:
		var level: int = int(passive_levels[key])
		lines.append("%s Lv.%d — %s" % [GearCatalog.display_name(key), level,
			GearCatalog.describe(key, level)])
	if int(counters.get("clockwork_casts", 0)) > 0:
		lines.append("Clockwork casts: %d" % int(counters["clockwork_casts"]))
	if int(counters.get("haste_kills", 0)) > 0:
		lines.append("Battle Haste kills: %d" % int(counters["haste_kills"]))
	return lines

func to_short_string() -> String:
	var out := super.to_short_string()
	var extra: Array[String] = []
	if int(stat_bonus.get("magic_resist", 0)) > 0:
		extra.append("+%d MARM" % int(stat_bonus["magic_resist"]))
	var haste := int(stat_bonus.get("cdr", 0))
	if haste > 0:
		# Ability Haste reads as the cooldown cut it gives on its own.
		extra.append("+%d Haste (−%d%% cooldown)" % [haste,
			roundi(100.0 - 10000.0 / (100.0 + haste))])
	if not extra.is_empty():
		out += " | " + ", ".join(extra)
	var lines := get_passive_lines()
	if not lines.is_empty():
		out += "\n" + "\n".join(lines)
	return out

func _init(p_name: String, p_rarity: EquipmentItem.Rarity = EquipmentItem.Rarity.COMMON) -> void:
	super(p_name, p_rarity)
	stat_bonus["magic_resist"] = 0
	stat_bonus["ten"] = 0
	stat_bonus["cdr"] = 0

func component_count() -> int:
	var total := 0
	for count in composition.values():
		total += int(count)
	return total

func passive_level_count() -> int:
	var total := 0
	for level in passive_levels.values():
		total += int(level)
	return total
