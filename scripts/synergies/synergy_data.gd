extends RefCounted
class_name SynergyData

# Team-composition synergy definitions. Two tracks:
#   • Element synergies (unit.current_element) — rewards matching rolled elements.
#   • Trait synergies  (unit.trait_class)     — rewards stacking a role.
# Each synergy grants a stat bonus at two thresholds (t1 → t2). Bonuses are
# multipliers on the current stat, EXCEPT range_add which is a flat +N.
# Applied at battle start and reverted at battle end (see main_game), so they
# recompute cleanly every fight and never compound. Values are first-pass — the
# balance tuning happens later.

# stat: one of attack_damage / magic_power / resistance / max_hp / attack_speed
#       (multipliers), or "range_add" (flat int added to attack_range).
# need: [t1_count, t2_count] — team members of that element/trait to reach each tier.
const ELEMENT_SYN := {
	UnitBase.Element.NORMAL:    {"stat": "attack_damage", "t1": 1.10, "t2": 1.20, "need": [2, 3], "name": "Normal"},
	UnitBase.Element.FIRE:      {"stat": "attack_damage", "t1": 1.15, "t2": 1.30, "need": [2, 3], "name": "Fire"},
	UnitBase.Element.WATER:     {"stat": "max_hp",        "t1": 1.12, "t2": 1.22, "need": [2, 3], "name": "Water"},
	UnitBase.Element.EARTH:     {"stat": "resistance",    "t1": 1.20, "t2": 1.40, "need": [2, 3], "name": "Earth"},
	UnitBase.Element.AIR:       {"stat": "attack_speed",  "t1": 1.12, "t2": 1.25, "need": [2, 3], "name": "Air"},
	UnitBase.Element.LIGHTNING: {"stat": "magic_power",   "t1": 1.15, "t2": 1.30, "need": [2, 3], "name": "Lightning"},
}

const TRAIT_SYN := {
	UnitBase.TraitClass.TANK:    {"stat": "resistance",    "t1": 1.15, "t2": 1.35, "need": [2, 4], "name": "Tank"},
	UnitBase.TraitClass.MAGE:    {"stat": "magic_power",   "t1": 1.15, "t2": 1.35, "need": [2, 4], "name": "Mage"},
	UnitBase.TraitClass.FIGHTER: {"stat": "attack_damage", "t1": 1.15, "t2": 1.30, "need": [2, 4], "name": "Fighter"},
	UnitBase.TraitClass.RANGED:  {"stat": "range_add",     "t1": 1,    "t2": 2,    "need": [2, 3], "name": "Ranged"},
	UnitBase.TraitClass.HEALER:  {"stat": "max_hp",        "t1": 1.10, "t2": 1.20, "need": [1, 2], "name": "Healer"},
}

const STAT_LABEL := {
	"attack_damage": "ATK", "magic_power": "Magic", "resistance": "DEF",
	"max_hp": "HP", "attack_speed": "Atk Speed", "range_add": "Range",
}

# Human-readable bonus text for a given stat + value (e.g. "+15% ATK", "+2 Range").
static func bonus_desc(stat: String, val: float) -> String:
	var label: String = STAT_LABEL.get(stat, stat)
	if stat == "range_add":
		return "+%d %s" % [int(val), label]
	return "+%d%% %s" % [int(round((val - 1.0) * 100.0)), label]

static func element_color(elem: int) -> Color:
	match elem:
		UnitBase.Element.FIRE:      return Color(1.0, 0.45, 0.1)
		UnitBase.Element.WATER:     return Color(0.3, 0.7, 1.0)
		UnitBase.Element.EARTH:     return Color(0.75, 0.55, 0.25)
		UnitBase.Element.AIR:       return Color(0.75, 1.0, 1.0)
		UnitBase.Element.LIGHTNING: return Color(1.0, 1.0, 0.25)
		_:                          return Color(0.85, 0.85, 0.92)

static func trait_color(t: int) -> Color:
	match t:
		UnitBase.TraitClass.TANK:    return Color(0.85, 0.30, 0.30)
		UnitBase.TraitClass.MAGE:    return Color(0.6, 0.4, 1.0)
		UnitBase.TraitClass.FIGHTER: return Color(1.0, 0.72, 0.25)
		UnitBase.TraitClass.RANGED:  return Color(0.35, 0.85, 0.35)
		UnitBase.TraitClass.HEALER:  return Color(0.4, 0.9, 0.6)
		_:                           return Color(0.7, 0.7, 0.7)
