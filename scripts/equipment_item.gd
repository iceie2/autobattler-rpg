extends Resource
class_name EquipmentItem

enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

var id: String  # Unique ID for this item instance
var name: String
var description: String
var rarity: Rarity

# Stat bonuses
var stat_bonus: Dictionary = {
	"hp": 0, "mana": 0,
	"str": 0, "dex": 0, "int": 0, "res": 0, "spr": 0
}

# Passive effect (if any)
var passive_effect: String = ""  # "lifesteal", "thorns", "haste", "regeneration", etc.
var effect_value: float = 0.0

# Display
var icon_color: Color

func _init(p_name: String, p_rarity: Rarity = Rarity.COMMON) -> void:
	id = "%s_%d" % [p_name.to_lower(), randi()]
	name = p_name
	rarity = p_rarity
	icon_color = _get_rarity_color(p_rarity)

func _get_rarity_color(r: Rarity) -> Color:
	match r:
		Rarity.COMMON:    return Color(0.7, 0.7, 0.7)
		Rarity.RARE:     return Color(0.3, 0.7, 1.0)
		Rarity.EPIC:     return Color(0.8, 0.3, 1.0)
		Rarity.LEGENDARY: return Color(1.0, 0.8, 0.0)
		_: return Color.WHITE

func get_rarity_name() -> String:
	match rarity:
		Rarity.COMMON:    return "Common"
		Rarity.RARE:     return "Rare"
		Rarity.EPIC:     return "Epic"
		Rarity.LEGENDARY: return "Legendary"
		_: return "Unknown"

func get_total_stat_bonus() -> int:
	return stat_bonus["hp"] + stat_bonus["mana"] + stat_bonus["str"] + stat_bonus["dex"] + \
		   stat_bonus["int"] + stat_bonus["res"] + stat_bonus["spr"]

func to_short_string() -> String:
	var bonus_str = []
	for stat in ["hp", "str", "dex", "int", "res"]:
		if stat_bonus.get(stat, 0) > 0:
			bonus_str.append("+%d %s" % [stat_bonus[stat], stat.to_upper()])
	return "%s (%s): %s" % [name, get_rarity_name(), ", ".join(bonus_str)]
