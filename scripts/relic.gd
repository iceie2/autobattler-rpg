extends RefCounted
class_name Relic

# Run-wide passive picks offered via gacha at waves 1 / 11 / 21. Grades D–S
# (no F): even a D relic should feel like *something*, unlike an F stat roll.
# Each relic has a FIXED grade — the gacha rolls a grade per offer slot (odds
# skew toward higher grades on later waves), then draws a random relic OF that
# grade, so later picks surface inherently stronger effects.
#
# NOTE: the POOL below is a TEMPORARY placeholder so the system is testable
# end-to-end. The real, flavourful relic pool is a separate design pass — see
# the relic_system_design note in project memory for the locked spec.

# ── Gacha grade odds per relic-wave (each column sums to 100) ──────────────────
# Keyed by the wave the pick happens on. Each of the 3 offer slots rolls its
# grade independently off this table.
const WAVE_ODDS := {
	1:  {"D": 80, "C": 15, "B": 4,  "A": 1,  "S": 0},
	11: {"D": 20, "C": 55, "B": 20, "A": 5,  "S": 0},
	21: {"D": 5,  "C": 10, "B": 50, "A": 25, "S": 10},
}

# Waves that trigger a relic pick.
const RELIC_WAVES: Array[int] = [1, 11, 21]

# Weakest → strongest (used for the odds walk and for exhausted-tier fallback).
const GRADE_ORDER: Array[String] = ["D", "C", "B", "A", "S"]

# Reuse the shared gacha palette (grey→green→blue→purple→gold) so relic grades
# read the same as recruit-roll and level-up-perk grades.
static func grade_color(grade: String) -> Color:
	return UnitFactory.GRADE_COLORS.get(grade, Color(0.86, 0.86, 1.0))

# Icon file per relic (named by id, see assets/icons/Relics/<id>.png). Returns ""
# if the art isn't present so callers can fall back to a text chip.
const ICON_DIR := "res://assets/icons/Relics/"
static func icon_path(relic: Dictionary) -> String:
	var p: String = ICON_DIR + str(relic.get("id", "")) + ".png"
	return p if ResourceLoader.exists(p) else ""

# ── Relic pool ────────────────────────────────────────────────────────────────
# Each entry: id, name, grade, desc, effects[ {type, ...}, ... ] (a relic may
# stack several sub-effects, e.g. Glass Cannon = more damage + more damage taken).
#
# Per-unit effect types (applied to each hero, once, by RelicInventory):
#   stat_mult       {stat, value}          — multiply one stat
#   stat_mult_multi {stats:[...], value}   — multiply several stats
#   stat_add        {stat, value}          — add flat to one stat
#   element_mult    {stat, element, base, matched}
#                                          — multiply `stat` by `base` for all,
#                                            by `matched` if the unit's element ==
#                                            `element` (element is a UnitBase.Element)
#   lifesteal    {value}   — heal `value` fraction of damage dealt
#   outgoing     {value}   — multiply all outgoing damage
#   dmg_taken    {value}   — multiply all incoming damage
#   vs_boss      {value}   — extra outgoing multiplier vs boss enemies
#   ult_charge   {value}   — multiply ultimate charge rate
#   double_atk   {value}   — chance (0–1) to strike twice per attack
#   start_shield {value}   — battle-start shield = `value` fraction of max HP
#   regen_pct    {value}   — regenerate `value` fraction of max HP per second
#   free_ult     {}        — start each battle with the ultimate charged
#   revive       {value}   — cheat death once per battle, revive at `value` HP frac
#   on_kill_atk  {value}   — each kill permanently grants +`value` frac attack dmg
# Run-economy / meta effect types (scanned on the inventory, not per-unit):
#   gold_round   {value}   — +gold granted each round
#   shop_slots   {value}   — +N extra hero cards in the shop
const POOL: Array[Dictionary] = [
	# ── D — small, reliable nudges ──
	{"id": "d_hp",    "name": "Worn Talisman",  "grade": "D", "desc": "+12% team max HP",       "effects": [{"type": "stat_mult", "stat": "max_hp", "value": 1.12}]},
	{"id": "d_atk",   "name": "Chipped Fang",   "grade": "D", "desc": "+10% team attack damage","effects": [{"type": "stat_mult", "stat": "attack_damage", "value": 1.10}]},
	{"id": "d_mag",   "name": "Cracked Orb",    "grade": "D", "desc": "+12% team magic power",  "effects": [{"type": "stat_mult", "stat": "magic_power", "value": 1.12}]},
	{"id": "d_gold",  "name": "Cracked Coin",   "grade": "D", "desc": "+4 gold each round",     "effects": [{"type": "gold_round", "value": 4}]},
	{"id": "d_aspd",  "name": "Quickstep Charm","grade": "D", "desc": "+10% team attack speed", "effects": [{"type": "stat_mult", "stat": "attack_speed", "value": 1.10}]},

	# ── C — solid ──
	{"id": "c_hp",    "name": "Iron Charm",     "grade": "C", "desc": "+20% team max HP",        "effects": [{"type": "stat_mult", "stat": "max_hp", "value": 1.20}]},
	{"id": "c_atk",   "name": "Warblade",       "grade": "C", "desc": "+18% team attack damage", "effects": [{"type": "stat_mult", "stat": "attack_damage", "value": 1.18}]},
	{"id": "c_std",   "name": "Battle Standard","grade": "C", "desc": "+12% attack damage and +12% max HP", "effects": [{"type": "stat_mult", "stat": "attack_damage", "value": 1.12}, {"type": "stat_mult", "stat": "max_hp", "value": 1.12}]},
	{"id": "c_ledger","name": "Merchant's Ledger","grade": "C", "desc": "+8 gold each round, and the shop shows 4 heroes", "effects": [{"type": "gold_round", "value": 8}, {"type": "shop_slots", "value": 1}]},
	{"id": "c_tide",  "name": "Tidal Charm",    "grade": "C", "desc": "+6% max HP for all; Water units get +20% instead", "effects": [{"type": "element_mult", "stat": "max_hp", "element": UnitBase.Element.WATER, "base": 1.06, "matched": 1.20}]},

	# ── B — build-shaping ──
	{"id": "b_atk",   "name": "Warlord's Edge", "grade": "B", "desc": "+30% team attack damage", "effects": [{"type": "stat_mult", "stat": "attack_damage", "value": 1.30}]},
	{"id": "b_vamp",  "name": "Vampiric Sigil", "grade": "B", "desc": "Team heals 12% of the damage it deals", "effects": [{"type": "lifesteal", "value": 0.12}]},
	{"id": "b_shield","name": "Bulwark Crest",  "grade": "B", "desc": "Team starts each fight with a shield worth 15% of max HP", "effects": [{"type": "start_shield", "value": 0.15}]},
	{"id": "b_ult",   "name": "Overcharged Core","grade": "B", "desc": "Ultimates charge 25% faster", "effects": [{"type": "ult_charge", "value": 1.25}]},
	{"id": "b_ember", "name": "Emberheart",     "grade": "B", "desc": "+8% damage for all; Fire units get +25% instead", "effects": [{"type": "element_mult", "stat": "attack_damage", "element": UnitBase.Element.FIRE, "base": 1.08, "matched": 1.25}]},

	# ── A — powerful / conditional ──
	{"id": "a_glass", "name": "Glass Cannon",   "grade": "A", "desc": "Team deals +35% damage but takes +20% damage", "effects": [{"type": "outgoing", "value": 1.35}, {"type": "dmg_taken", "value": 1.20}]},
	{"id": "a_titan", "name": "Titan's Heart",  "grade": "A", "desc": "+45% max HP and regenerate 3% max HP per second", "effects": [{"type": "stat_mult", "stat": "max_hp", "value": 1.45}, {"type": "regen_pct", "value": 0.03}]},
	{"id": "a_exec",  "name": "Executioner",    "grade": "A", "desc": "+30% damage dealt to bosses", "effects": [{"type": "vs_boss", "value": 1.30}]},
	{"id": "a_twin",  "name": "Twin Fang",      "grade": "A", "desc": "20% chance for each attack to strike twice", "effects": [{"type": "double_atk", "value": 0.20}]},
	{"id": "a_storm", "name": "Stormcore",      "grade": "A", "desc": "+10% attack speed for all; Lightning units get +30% instead", "effects": [{"type": "element_mult", "stat": "attack_speed", "element": UnitBase.Element.LIGHTNING, "base": 1.10, "matched": 1.30}]},

	# ── S — run-defining ──
	{"id": "s_god",   "name": "Godshard",       "grade": "S", "desc": "+30% attack damage, magic power, and max HP", "effects": [{"type": "stat_mult_multi", "stats": ["attack_damage", "magic_power", "max_hp"], "value": 1.30}]},
	{"id": "s_chrono","name": "Chrono Core",    "grade": "S", "desc": "+40% team attack speed", "effects": [{"type": "stat_mult", "stat": "attack_speed", "value": 1.40}]},
	{"id": "s_over",  "name": "Overclocked",    "grade": "S", "desc": "Every hero starts each fight with their ultimate fully charged", "effects": [{"type": "free_ult"}]},
	{"id": "s_soul",  "name": "Soul Harvest",   "grade": "S", "desc": "Each kill permanently grants that hero +2% attack damage (stacks all run)", "effects": [{"type": "on_kill_atk", "value": 0.02}]},
	{"id": "s_phoenix","name": "Phoenix Pact",  "grade": "S", "desc": "Each hero cheats death once per fight, reviving at 40% HP", "effects": [{"type": "revive", "value": 0.40}]},
]

# ── Gacha rolling ─────────────────────────────────────────────────────────────

# Roll a grade for one offer slot off the given wave's odds.
static func roll_grade(wave: int) -> String:
	var odds: Dictionary = WAVE_ODDS.get(wave, WAVE_ODDS[1])
	var total := 0
	for w in odds.values():
		total += int(w)
	if total <= 0:
		return "D"
	var r := randi() % total
	var acc := 0
	for grade in GRADE_ORDER:
		acc += int(odds.get(grade, 0))
		if r < acc:
			return grade
	return "D"

# Roll `count` relic offers for a wave. Each slot rolls its grade independently,
# then draws a random relic of that grade. Never offers the same relic twice on
# one screen, and prefers relics the player doesn't already own.
static func roll_offers(wave: int, owned_ids: Array = [], count: int = 3) -> Array:
	var offers: Array = []
	var used_ids: Array = []
	for _i in range(count):
		var relic := _draw_one(wave, owned_ids, used_ids)
		if relic.is_empty():
			continue
		used_ids.append(relic["id"])
		offers.append(relic)
	return offers

# Roll a grade, then draw an unused relic of that grade. If the rolled grade is
# exhausted this screen, fan outward to adjacent grades so the slot still fills.
static func _draw_one(wave: int, owned_ids: Array, used_ids: Array) -> Dictionary:
	var grade := roll_grade(wave)
	for g in _grade_search_order(grade):
		var fresh: Array = []
		var owned: Array = []
		for relic in POOL:
			if relic["grade"] != g:
				continue
			if relic["id"] in used_ids:
				continue
			if relic["id"] in owned_ids:
				owned.append(relic)
			else:
				fresh.append(relic)
		var pick_from: Array = fresh if not fresh.is_empty() else owned
		if not pick_from.is_empty():
			return (pick_from[randi() % pick_from.size()] as Dictionary).duplicate(true)
	return {}

# Search the rolled grade first, then fan outward (nearer grades first) so an
# exhausted tier yields a neighbouring relic instead of an empty card.
static func _grade_search_order(grade: String) -> Array:
	var i := GRADE_ORDER.find(grade)
	if i == -1:
		return GRADE_ORDER.duplicate()
	var order: Array = [grade]
	var off := 1
	while order.size() < GRADE_ORDER.size():
		if i - off >= 0:
			order.append(GRADE_ORDER[i - off])
		if i + off < GRADE_ORDER.size():
			order.append(GRADE_ORDER[i + off])
		off += 1
	return order
