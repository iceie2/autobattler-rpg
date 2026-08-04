extends Resource
class_name EquipmentItem

# 5-grade system matching relics / recruits / perks: D/C/B/A/S =
# Common(grey) / Uncommon(green) / Rare(blue) / Epic(purple) / Legendary(gold).
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

var id: String  # Unique ID for this item instance
var name: String
var description: String
var rarity: Rarity

# Stat bonuses (TFT-style independent stats)
var stat_bonus: Dictionary = {
	"hp": 0, "mana": 0,
	"atk": 0, "magic": 0, "res": 0, "aspd": 0.0, "hpregen": 0.0, "manaregen": 0.0,
	# Crit (2026-07-24): "crit" is a crit-CHANCE bonus in unit space (0.05 = +5%),
	# "critdmg" adds to the crit-damage multiplier (0.25 = +0.25x).
	"crit": 0.0, "critdmg": 0.0,
}

# Passive effects (2026-07-24: items can now carry multiple — combining no
# longer overwrites passives inherited from the inputs, see EquipmentManager.
# combine_items). Each entry: {"name": String, "value": float}.
var passives: Array = []

# Legacy single-passive accessors — kept because a lot of UI/save code only
# ever reads "the" passive off an item. Mirrors passives[0].
var passive_effect: String:
	get: return passives[0]["name"] if not passives.is_empty() else ""
var effect_value: float:
	get: return passives[0]["value"] if not passives.is_empty() else 0.0

# Per-passive display text. The rolled value IS the effect magnitude, so the
# blurb has to be built from it — a static "Restore 15% of damage dealt" line
# lies about a 0.27 roll (2026-08-02: fused items used to list bare passive
# NAMES with no numbers at all).
# Row = [format, kind]. kind: "pct" (value shown as a percentage),
# "hps" (value * 30 HP/sec, see AutoBattleManager._regen_tick).
const PASSIVE_DISPLAY := {
	"Lifesteal":    ["Heal for %s of the damage you deal with attacks", "pct"],
	"Thorns":       ["Reflect %s of damage taken back to the attacker", "pct"],
	"Haste":        ["+%s attack speed", "pct"],
	"Regeneration": ["Regenerate %s HP per second", "hps"],
	"Spell Echo":   ["+%s damage dealt (all sources)", "pct"],
	"Evasion":      ["%s chance to dodge an incoming hit", "pct"],
}

# "Lifesteal — Heal for 27% of the damage you deal with attacks"
static func describe_passive(p_name: String, p_value: float) -> String:
	var row: Array = PASSIVE_DISPLAY.get(p_name, [])
	if row.is_empty():
		return p_name
	var v: String
	match row[1]:
		"hps": v = "%.1f" % (p_value * 30.0)
		_:     v = "%d%%" % int(round(p_value * 100.0))
	return "%s — %s" % [p_name, row[0] % v]

# One fully-resolved line per passive on this item, for tooltips.
func get_passive_lines() -> Array:
	var lines: Array = []
	for p in passives:
		lines.append(describe_passive(str(p["name"]), float(p["value"])))
	return lines

func add_passive(p_name: String, p_value: float) -> void:
	for p in passives:
		if p["name"] == p_name:
			p["value"] = maxf(p["value"], p_value)
			return
	passives.append({"name": p_name, "value": p_value})

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
		Rarity.UNCOMMON:  return Color(0.35, 0.78, 0.35)
		Rarity.RARE:     return Color(0.3, 0.7, 1.0)
		Rarity.EPIC:     return Color(0.8, 0.3, 1.0)
		Rarity.LEGENDARY: return Color(1.0, 0.8, 0.0)
		_: return Color.WHITE

func get_rarity_name() -> String:
	match rarity:
		Rarity.COMMON:    return "Common"
		Rarity.UNCOMMON:  return "Uncommon"
		Rarity.RARE:     return "Rare"
		Rarity.EPIC:     return "Epic"
		Rarity.LEGENDARY: return "Legendary"
		_: return "Unknown"

func get_total_stat_bonus() -> float:
	return stat_bonus["hp"] + stat_bonus["mana"] + stat_bonus["atk"] + stat_bonus["magic"] + \
		   stat_bonus["res"] + stat_bonus["aspd"] + stat_bonus["hpregen"] + stat_bonus["manaregen"] + \
		   stat_bonus.get("crit", 0.0) + stat_bonus.get("critdmg", 0.0)

# All stat keys with a short label + whether they're a float (2026-07-18 fix:
# to_short_string used to list only hp/atk/magic/res with %d, so items whose
# only roll was mana or a float stat — attack speed / regens — displayed no
# stat at all, and floats truncated).
# Row = [stat_key, label, format]. format: "int" / "float" / "pct" (percentage,
# e.g. crit chance) / "mult" (multiplier delta, e.g. +0.25x crit damage).
const _STAT_DISPLAY := [
	["hp", "HP", "int"], ["mana", "MP", "int"], ["atk", "ATK", "int"],
	["magic", "MAG", "int"], ["res", "ARM", "int"],
	["aspd", "AS", "float"], ["hpregen", "HP/S", "float"], ["manaregen", "MP/S", "float"],
	["crit", "CRIT", "pct"], ["critdmg", "CRIT DMG", "mult"],
]

# Shared "+value LABEL" formatter for a _STAT_DISPLAY row so every UI (bag tooltip,
# shop tooltip) renders crit-as-% and crit-damage-as-x identically.
static func format_bonus(row: Array, v: float) -> String:
	match row[2]:
		"pct":   return "+%d%% %s" % [int(round(v * 100.0)), row[1]]
		"mult":  return "+%.2fx %s" % [v, row[1]]
		"float": return "+%.2f %s" % [v, row[1]]
		_:       return "+%d %s" % [int(v), row[1]]

func to_short_string() -> String:
	var bonus_str = []
	for row in _STAT_DISPLAY:
		var v: float = float(stat_bonus.get(row[0], 0))
		if v > 0.0:
			bonus_str.append(format_bonus(row, v))
	var suffix: String = ", ".join(bonus_str) if not bonus_str.is_empty() else "—"
	var out: String = "%s (%s): %s" % [name, get_rarity_name(), suffix]
	if not passives.is_empty():
		out += " | " + " | ".join(get_passive_lines())
	return out
