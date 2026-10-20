extends RefCounted
class_name GearCatalog

# The 36 item passives of the component equipment system. Design source:
# EQUIPMENT_GREEN_PAIRS.md (2026-09-25). Every magnitude is a CEILING on one
# shared saturating curve, value(L) = ceiling * (1 - e^(-L / TAU)), where L is
# the summed level of that passive across a hero's equipped items (1..24).
# Ceilings are the user-approved arena starting point; tune them here only.

const TAU := 8.0

# Grey component -> passive family. Armor/MR pool as Defense and the two regen
# stats pool as Regen for passive selection only; they keep their own stats.
const COMPONENT_FAMILY := {
	"hp": "HP", "atk": "ATK", "magic": "Magic", "cdr": "CDR", "aspd": "AS",
	"crit": "Crit", "res": "Defense", "magic_resist": "Defense",
	"hpregen": "Regen", "manaregen": "Regen",
}
const FAMILY_ORDER := ["HP", "ATK", "Magic", "CDR", "AS", "Crit", "Defense", "Regen"]

# Unordered family pair -> passive key (worksheet numbering in comments).
const PAIR_PASSIVE := {
	"HP+HP": "last_bastion", "HP+ATK": "lifesteal", "HP+Magic": "aftercast_ward",
	"HP+CDR": "second_wind", "HP+AS": "iron_rhythm", "HP+Crit": "desperation",
	"HP+Defense": "bulwark", "HP+Regen": "regeneration",
	"ATK+ATK": "overkill", "ATK+Magic": "arcane_conduit", "ATK+CDR": "hunters_reset",
	"ATK+AS": "cadence", "ATK+Crit": "deep_wound", "ATK+Defense": "sunder",
	"ATK+Regen": "blood_price",
	"Magic+Magic": "attunement", "Magic+CDR": "spell_echo", "Magic+AS": "spell_tempo",
	"Magic+Crit": "arcane_precision", "Magic+Defense": "mana_shield",
	"Magic+Regen": "empty_reservoir",
	"CDR+CDR": "battle_charge", "CDR+AS": "clockwork", "CDR+Crit": "precision_reset",
	"CDR+Defense": "spellguard", "CDR+Regen": "rest_cycle",
	"AS+AS": "battle_haste", "AS+Crit": "keen_rhythm", "AS+Defense": "riposte",
	"AS+Regen": "sustained_assault",
	"Crit+Crit": "critical_focus", "Crit+Defense": "counterstrike",
	"Crit+Regen": "vital_precision",
	"Defense+Defense": "thorns", "Defense+Regen": "recovery",
	"Regen+Regen": "equilibrium",
}

# key -> [display name, worksheet #, ceilings]. Ceiling keys are read by
# GearPassives; fixed (non-scaling) numbers live there beside their rule.
const PASSIVES := {
	"last_bastion": ["Last Bastion", 1, {"shield": 0.30}],
	"lifesteal": ["Lifesteal", 2, {"pct": 0.40}],
	"aftercast_ward": ["Aftercast Ward", 3, {"shield": 0.12}],
	"second_wind": ["Second Wind", 4, {"heal": 0.06}],
	"iron_rhythm": ["Iron Rhythm", 5, {"shield": 0.06}],
	"desperation": ["Desperation", 6, {"crit_step": 0.08}],
	"bulwark": ["Bulwark", 7, {}],
	"regeneration": ["Regeneration", 8, {"hp_pct_s": 0.01}],
	"overkill": ["Overkill", 9, {"pct": 0.50}],
	"arcane_conduit": ["Arcane Conduit", 10, {"atk_pct": 0.50}],
	"hunters_reset": ["Hunter's Reset", 11, {"sec": 1.5}],
	"cadence": ["Cadence", 12, {"aspd_stack": 0.06}],
	"deep_wound": ["Deep Wound", 13, {"cut": 0.40}],
	"sunder": ["Sunder", 14, {"shred_stack": 0.08}],
	"blood_price": ["Blood Price", 15, {"hp_pct": 0.04, "mana": 8.0}],
	"attunement": ["Attunement", 16, {"mp_pct": 0.60}],
	"spell_echo": ["Spell Echo", 17, {"chance": 0.30}],
	"spell_tempo": ["Spell Tempo", 18, {"aspd": 0.25}],
	"arcane_precision": ["Arcane Precision", 19, {"chance": 0.25}],
	"mana_shield": ["Mana Shield", 20, {"pct": 0.30}],
	"empty_reservoir": ["Empty Reservoir", 21, {"bonus": 0.40}],
	"battle_charge": ["Battle Charge", 22, {"charge": 45.0}],
	"clockwork": ["Clockwork", 23, {"dmg": 36.0}],
	"precision_reset": ["Precision Reset", 24, {"sec": 0.6}],
	"spellguard": ["Spellguard", 25, {"def": 20.0}],
	"rest_cycle": ["Rest Cycle", 26, {"hp_pct_s": 0.005, "mana_s": 3.0}],
	"battle_haste": ["Battle Haste", 27, {"rate": 0.127}],
	"keen_rhythm": ["Keen Rhythm", 28, {"pct": 0.30}],
	"riposte": ["Riposte", 29, {"slow": 0.25}],
	"sustained_assault": ["Sustained Assault", 30, {"hp_pct_s": 0.005, "mana_s": 3.0}],
	"critical_focus": ["Critical Focus", 31, {"crit_stack": 0.06, "critdmg": 0.5}],
	"counterstrike": ["Counterstrike", 32, {"crit": 0.40}],
	"vital_precision": ["Vital Precision", 33, {"hp_pct": 0.02, "mana": 6.0}],
	"thorns": ["Thorns", 34, {"pct": 0.35}],
	"recovery": ["Recovery", 35, {"hp_pct_s": 0.012, "mana_s": 5.0}],
	"equilibrium": ["Equilibrium", 36, {"pct": 0.80}],
}

static func curve(level: float) -> float:
	if level <= 0.0:
		return 0.0
	return 1.0 - exp(-level / TAU)

# Ceiling scaled to a level: GearCatalog.value("lifesteal", "pct", 4) -> ~0.157
static func value(key: String, field: String, level: float) -> float:
	var row: Array = PASSIVES.get(key, [])
	if row.is_empty():
		return 0.0
	return float(row[2].get(field, 0.0)) * curve(level)

# Shrinking values: start -> floor as L grows (Bulwark's cooldown).
static func shrink(start: float, floor_v: float, level: float) -> float:
	return floor_v + (start - floor_v) * exp(-maxf(level, 0.0) / TAU)

static func display_name(key: String) -> String:
	var row: Array = PASSIVES.get(key, [])
	return str(row[0]) if not row.is_empty() else key

static func number(key: String) -> int:
	var row: Array = PASSIVES.get(key, [])
	return int(row[1]) if not row.is_empty() else 0

static func family_pair_key(a: String, b: String) -> String:
	if FAMILY_ORDER.find(a) > FAMILY_ORDER.find(b):
		return b + "+" + a
	return a + "+" + b

# Passive granted by two grey components ("" if either is not a component).
static func passive_for_components(a: String, b: String) -> String:
	if not COMPONENT_FAMILY.has(a) or not COMPONENT_FAMILY.has(b):
		return ""
	return str(PAIR_PASSIVE.get(family_pair_key(COMPONENT_FAMILY[a], COMPONENT_FAMILY[b]), ""))

static func families_of(key: String) -> Array:
	for pair in PAIR_PASSIVE:
		if PAIR_PASSIVE[pair] == key:
			return str(pair).split("+")
	return []

static func _pct(v: float) -> String:
	return "%.1f%%" % (v * 100.0) if v < 0.1 else "%d%%" % roundi(v * 100.0)

# One-line effect text at level L, for tooltips and the merge menu.
static func describe(key: String, level: float) -> String:
	var L := level
	match key:
		"last_bastion": return "Once per fight, dropping below half HP grants a %s max-HP shield" % _pct(value(key, "shield", L))
		"lifesteal": return "Basic attacks heal %s of damage dealt" % _pct(value(key, "pct", L))
		"aftercast_ward": return "Casting a skill grants a %s max-HP shield (every 6s)" % _pct(value(key, "shield", L))
		"second_wind": return "Casting a skill heals %s max HP" % _pct(value(key, "heal", L))
		"iron_rhythm": return "Every 3rd hit grants a %s max-HP shield" % _pct(value(key, "shield", L))
		"desperation": return "+%s crit chance per missing 25%% HP" % _pct(value(key, "crit_step", L))
		"bulwark": return "Block one hit completely every %.1fs" % shrink(24.0, 6.0, L)
		"regeneration": return "Regenerate %s max HP per second" % _pct(value(key, "hp_pct_s", L))
		"overkill": return "Killing blows spill %s of excess damage to a nearby enemy" % _pct(value(key, "pct", L))
		"arcane_conduit": return "Skills deal an extra %s ATK as magic damage per target" % _pct(value(key, "atk_pct", L))
		"hunters_reset": return "Basic-attack kills cut skill cooldown by %.2fs" % value(key, "sec", L)
		"cadence": return "Hits while standing still stack +%s attack speed (max 5)" % _pct(value(key, "aspd_stack", L))
		"deep_wound": return "Anti-heal: attacks cut the target's healing by %s for 4s" % _pct(GearPassives.DEEP_WOUND_CUT)
		"sunder": return "Hits shred %s of armor and magic resist (max 5 stacks)" % _pct(value(key, "shred_stack", L))
		"blood_price": return "Kills heal %s max HP and restore %.1f mana" % [_pct(value(key, "hp_pct", L)), value(key, "mana", L)]
		"attunement": return "+%s Magic Power" % _pct(value(key, "mp_pct", L))
		"spell_echo": return "%s chance for a skill to repeat on its target" % _pct(value(key, "chance", L))
		"spell_tempo": return "Casting a skill grants +%s attack speed for 4s" % _pct(value(key, "aspd", L))
		"arcane_precision": return "Skill hits have a %s chance to deal 1.5x damage" % _pct(value(key, "chance", L))
		"mana_shield": return "%s of damage taken is paid with mana (1 mana = 2 dmg)" % _pct(value(key, "pct", L))
		"empty_reservoir": return "Skills deal up to +%s damage the emptier your mana" % _pct(value(key, "bonus", L))
		"battle_charge": return "Casting a skill grants %d ultimate charge" % roundi(value(key, "charge", L))
		"clockwork": return "Skills deal an extra %.1f x ln(1+casts) magic damage; the cast count persists" % value(key, "dmg", L)
		"precision_reset": return "Crits cut skill cooldown by %.2fs" % value(key, "sec", L)
		"spellguard": return "Casting grants +%d armor and MR for %.1fs (stacks)" % [roundi(value(key, "def", L)), 5.0 + 15.0 * curve(L)]
		"rest_cycle": return "While your skill recharges: %s max HP and %.1f mana per second" % [_pct(value(key, "hp_pct_s", L)), value(key, "mana_s", L)]
		"battle_haste": return "Kills grant %s x ln(1+kills) attack speed; kills persist, half lost on death" % _pct(value(key, "rate", L))
		"keen_rhythm": return "A crit makes your next attack %s sooner" % _pct(value(key, "pct", L))
		"riposte": return "Enemies that hit you attack %s slower for 3s" % _pct(value(key, "slow", L))
		"sustained_assault": return "For 2s after a hit: %s max HP and %.1f mana per second" % [_pct(value(key, "hp_pct_s", L)), value(key, "mana_s", L)]
		"critical_focus": return "Non-crits stack +%s crit chance (max 5); +%.2fx crit damage" % [_pct(value(key, "crit_stack", L)), value(key, "critdmg", L)]
		"counterstrike": return "Being hit grants +%s crit chance on your next attack" % _pct(value(key, "crit", L))
		"vital_precision": return "Crits heal %s max HP and restore %.1f mana (1/s)" % [_pct(value(key, "hp_pct", L)), value(key, "mana", L)]
		"thorns": return "Reflect %s of damage taken as true damage" % _pct(value(key, "pct", L))
		"recovery": return "Being hit grants %s max HP and %.1f mana per second for 3s" % [_pct(value(key, "hp_pct_s", L)), value(key, "mana_s", L)]
		"equilibrium": return "Convert %s of wasted HP/mana regen into the other" % _pct(value(key, "pct", L))
	return key
