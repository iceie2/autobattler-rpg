extends Node
class_name EquipmentManager

# Icon per item name — shared so any UI (inventory bag, item tooltips, the
# round-reward preview) can look up an item's icon without duplicating this map.
const ITEM_ICONS: Dictionary = {
	"Sword":       "res://assets/icons/64x64/fc1601.png",
	"Shield":      "res://assets/icons/64x64/fc2150.png",
	"Robe":        "res://assets/icons/64x64/fc2098.png",
	"Gloves":      "res://assets/icons/64x64/fc1985.png",
	"Ring":        "res://assets/icons/64x64/fc2135.png",
	"Cloak":       "res://assets/icons/64x64/fc2015.png",
	"Amulet":      "res://assets/icons/64x64/fc2055.png",
	"Boots":       "res://assets/icons/64x64/fc1948.png",
	"Axe":         "res://assets/icons/64x64/fc1770.png",
	"Staff":       "res://assets/icons/64x64/fc1720.png",
	"Bow":         "res://assets/icons/64x64/fc1580.png",
	"Plate Armor": "res://assets/icons/64x64/fc1920.png",
}

# Item templates. "primary" is the item's identity stat — it always gets the
# first stat point; remaining points roll onto random stats.
const ITEM_TEMPLATES = {
	"sword":  {"name": "Sword",       "primary": "atk"},
	"shield": {"name": "Shield",      "primary": "res"},
	"robe":   {"name": "Robe",        "primary": "magic"},
	"gloves": {"name": "Gloves",      "primary": "aspd"},
	"ring":   {"name": "Ring",        "primary": "hp"},
	"cloak":  {"name": "Cloak",       "primary": "res"},
	"amulet": {"name": "Amulet",      "primary": "mana"},
	"boots":  {"name": "Boots",       "primary": "aspd"},
	"axe":    {"name": "Axe",         "primary": "atk"},
	"staff":  {"name": "Staff",       "primary": "magic"},
	"bow":    {"name": "Bow",         "primary": "aspd"},
	"plate":  {"name": "Plate Armor", "primary": "res"},
}

# Stats whose values are small floats rather than whole numbers.
const FLOAT_STATS := ["aspd", "hpregen", "manaregen"]
# Crit stats (2026-07-24) roll on their own magnitude scale (percent chance /
# multiplier delta), independent of round so late-game items don't spike to 100%.
const CRIT_STATS := ["crit", "critdmg"]

# ── Equipment rework (2026-07-17 user spec, roll counts fixed 2026-07-24) ─────
# DROPPED items are stat-sticks only (rolls can repeat — "+attack speed ×2" is
# legal). Drops are 100% COMMON unless the Lucky Find crystal-shop upgrade
# grants better odds. Roll counts are set so a DROPPED item of a given rarity
# always has exactly as many stat rolls as a FUSED item of that rarity would
# (fusing 3 items sums their rolls, so each tier is 3x the one below) — a
# dropped green used to have fewer rolls AND no passive than a fused green,
# making drops strictly worse instead of just "passive-less."
# PASSIVES exist ONLY on combined gear: fusing 3 same-rarity items yields the
# next tier carrying ALL of their inherited passives (plus one fresh roll if
# none of the inputs had any yet, e.g. grey→green).
const RARITY_STAT_ROLLS := {
	EquipmentItem.Rarity.COMMON:    1,
	EquipmentItem.Rarity.UNCOMMON:  3,
	EquipmentItem.Rarity.RARE:      9,
	EquipmentItem.Rarity.EPIC:      27,
	EquipmentItem.Rarity.LEGENDARY: 81,
}

# Roll pool for the fresh passive a grey→green fusion grants. Display text lives
# in EquipmentItem.PASSIVE_DISPLAY (built from the rolled value, not static prose).
const PASSIVE_EFFECTS = [
	{"name": "Lifesteal"}, {"name": "Thorns"}, {"name": "Haste"},
	{"name": "Regeneration"}, {"name": "Spell Echo"}, {"name": "Evasion"},
]

# Apply an item's stat bonuses directly onto a unit's live stats. Used for enemies
# that spawn already wielding a dropped item (see main_game.gd), which don't go
# through EquipmentInventory the way player heroes do.
static func apply_to_unit(unit: UnitBase, item: EquipmentItem) -> void:
	unit.max_hp += int(item.stat_bonus.get("hp", 0))
	unit.current_hp += int(item.stat_bonus.get("hp", 0))
	unit.max_mana += int(item.stat_bonus.get("mana", 0))
	unit.current_mana += int(item.stat_bonus.get("mana", 0))
	unit.attack_damage += int(item.stat_bonus.get("atk", 0))
	unit.magic_power += int(item.stat_bonus.get("magic", 0))
	unit.resistance += int(item.stat_bonus.get("res", 0))
	unit.attack_speed += item.stat_bonus.get("aspd", 0.0)
	unit.hp_regen += item.stat_bonus.get("hpregen", 0.0)
	unit.mana_regen += item.stat_bonus.get("manaregen", 0.0)
	unit.crit_chance += item.stat_bonus.get("crit", 0.0)
	unit.crit_damage += item.stat_bonus.get("critdmg", 0.0)
	for p in item.passives:
		var existing: float = unit.equipment_passives.get(p["name"], 0.0)
		unit.equipment_passives[p["name"]] = maxf(existing, p["value"])

static func generate_item(round: int = 1, max_rarity: int = EquipmentItem.Rarity.RARE) -> EquipmentItem:
	var templates = ITEM_TEMPLATES.keys()
	var template_key = templates[randi() % templates.size()]
	var template = ITEM_TEMPLATES[template_key]

	var rarity = _roll_rarity(round, max_rarity)
	var item = EquipmentItem.new(template["name"], rarity)
	item.description = "%s %s" % [item.get_rarity_name(), template["name"]]

	# Dropped items NEVER roll passives (2026-07-17 rework) — passives come
	# exclusively from combining. Drops are pure stat sticks.
	var points: int = int(RARITY_STAT_ROLLS.get(rarity, 1))

	# First point always rolls the item's primary (identity) stat; the rest hit
	# random stats.
	var available_stats = ["hp", "mana", "atk", "magic", "res", "aspd", "hpregen", "manaregen", "crit", "critdmg"]
	var primary: String = template.get("primary", "atk")
	for i in range(points):
		var stat: String = primary if i == 0 else available_stats[randi() % available_stats.size()]
		if stat in CRIT_STATS:
			item.stat_bonus[stat] += _roll_crit_stat_value(stat, rarity)
		elif stat in FLOAT_STATS:
			item.stat_bonus[stat] += _roll_float_stat_value(rarity, round)
		else:
			var value: int = _roll_stat_value(rarity, round)
			# HP/mana rolls read as flat pools, not per-hit damage — a raw roll
			# feels negligible next to units with hundreds/thousands of HP, so
			# these two get a straight 10x on top of everything else (2026-07-09
			# user request).
			if stat in BIG_STATS:
				value *= BIG_STATS_MULT
			item.stat_bonus[stat] += value

	return item

const BIG_STATS: Array[String] = ["hp", "mana"]
const BIG_STATS_MULT := 10

# Drops are 100% COMMON out of the box (2026-07-17 rework). Epic+ never drops —
# those tiers exist only through combining.
#
# 2026-08-03: Lucky Find (loot_quality, one node giving +3% uncommon AND +1%
# rare) was retired for two separate upconversion families in the Armory spoke,
# so the two chances are now read independently instead of scaling together.
static func _roll_rarity(_round: int, max_rarity: int = EquipmentItem.Rarity.RARE) -> int:
	var rare_chance: float = 0.01 * float(Progression.get_bonus("loot_to_rare"))
	var uncommon_chance: float = 0.01 * float(Progression.get_bonus("loot_to_uncommon"))
	if max_rarity < EquipmentItem.Rarity.RARE:
		rare_chance = 0.0
	if max_rarity < EquipmentItem.Rarity.UNCOMMON:
		uncommon_chance = 0.0

	var roll = randf()
	if roll < rare_chance:
		return EquipmentItem.Rarity.RARE
	elif roll < rare_chance + uncommon_chance:
		return EquipmentItem.Rarity.UNCOMMON
	return EquipmentItem.Rarity.COMMON

# Fixed former wave-one range. Wave affects neither newly rolled nor held stats.
static func _roll_stat_value(rarity: int, _round: int) -> int:
	var base_value = 3.25
	var roll = base_value * (0.8 + randf() * 0.4)
	var multiplier = 1.0 + (rarity * 0.3)
	return int(roll * multiplier)

# Crit rolls: "crit" is crit CHANCE (0.03–0.06 base per roll → +3–6%, ×rarity),
# "critdmg" is the crit-damage multiplier delta (0.15–0.30 base → +0.15–0.30x,
# ×rarity). Round-independent — crit% shouldn't inflate into guaranteed-crit gear.
static func _roll_crit_stat_value(stat: String, rarity: int) -> float:
	var multiplier := 1.0 + (rarity * 0.3)
	if stat == "crit":
		return snappedf((0.03 + randf() * 0.03) * multiplier, 0.01)
	return snappedf((0.15 + randf() * 0.15) * multiplier, 0.01)

# Small-magnitude version for attack_speed/hp_regen/mana_regen bonuses.
# Fixed former wave-one range, like the integer stat rolls above.
static func _roll_float_stat_value(rarity: int, _round: int) -> float:
	var base_value = 0.055
	var roll = base_value * (0.8 + randf() * 0.4)
	var multiplier = 1.0 + (rarity * 0.3)
	return snappedf(roll * multiplier, 0.01)

# ── Fusion economy (2026-08-04 rebalance, BALANCE_PLAN.md §1.7-1.8) ───────────
# Fusion used to be LOSSLESS: three items summed with no tax, so 27 commons
# concentrated into one Epic carrying all 27 rolls. Measured, that Epic was worth
# ~+47 atk and +1.3 aspd — roughly an 8x DPS multiplier, beating a fully maxed
# crystal-tree stat branch that costs ~7,300 crystals, for free.
#
# COMBINE_KEEP taxes each fusion. At 0.85 an Epic falls from 27 common-
# equivalents to ~16 (a ~40% cut) while every tier stays clearly better than its
# inputs (2.55x per fusion, not 3x) — combining still feels worth doing, which
# was the explicit design requirement.
const COMBINE_KEEP := 0.85

# Max DISTINCT passives an item may carry, by rarity. Before this cap, only 6
# passive types existed and add_passive() deduped by name taking the max, so
# every Epic converged on ~5 of 6 at near-max value — not merely too strong,
# but IDENTICAL every time, which meant there was no build to speak of.
# Capping turns "collect them all" into a choice.
const PASSIVE_CAP_BY_RARITY := {
	EquipmentItem.Rarity.COMMON:    0,
	EquipmentItem.Rarity.UNCOMMON:  1,
	EquipmentItem.Rarity.RARE:      2,
	EquipmentItem.Rarity.EPIC:      3,
	EquipmentItem.Rarity.LEGENDARY: 4,
}

static func passive_cap(rarity: int) -> int:
	return int(PASSIVE_CAP_BY_RARITY.get(rarity, 0))

# Every passive the inputs could contribute, best value per name, strongest
# first. The equipment page calls this to show the player what they're choosing
# BETWEEN before committing a fusion; combine_items() falls back to the top N of
# this same list when no explicit choice is supplied.
static func candidate_passives(items: Array) -> Array:
	var best: Dictionary = {}
	for item: EquipmentItem in items:
		for p in item.passives:
			var n: String = str(p["name"])
			best[n] = maxf(float(best.get(n, 0.0)), float(p["value"]))
	var out: Array = []
	for n: String in best:
		out.append({"name": n, "value": float(best[n])})
	out.sort_custom(func(a, b): return a["value"] > b["value"])
	return out

# Combine 3 items of same rarity → one item of the next rarity. Stats are the
# taxed sum of all three (see COMBINE_KEEP). Inherits the identity (name/icon) of
# the strongest input so bag icons (keyed by name) still resolve.
#
# keep_passives: names the player chose to carry forward. Empty = no choice made
# (headless callers, or the bag UI before the passive-pick screen exists), in
# which case the strongest candidates win up to the cap. Names that aren't
# actually available are ignored rather than trusted, so a stale UI selection
# can't invent a passive.
static func combine_items(items: Array[EquipmentItem], keep_passives: Array = []) -> EquipmentItem:
	if items.size() < 3:
		return null

	# Base identity = the input with the biggest total stat bonus.
	var base = items[0]
	for item in items:
		if item.get_total_stat_bonus() > base.get_total_stat_bonus():
			base = item

	var combined = EquipmentItem.new(base.name, base.rarity + 1)
	combined.description = base.description

	for item in items:
		for stat in item.stat_bonus:
			combined.stat_bonus[stat] += item.stat_bonus[stat]
	# Apply the fusion tax. Int-typed stats are re-floored so the bag keeps
	# showing whole numbers for hp/atk/res; the float stats (aspd/regens/crit)
	# keep their precision.
	for stat in combined.stat_bonus:
		var taxed: float = float(combined.stat_bonus[stat]) * COMBINE_KEEP
		if stat in FLOAT_STATS or stat in CRIT_STATS:
			combined.stat_bonus[stat] = snappedf(taxed, 0.01)
		else:
			combined.stat_bonus[stat] = int(taxed)

	# Passives carry forward from the inputs, now limited to the rarity's cap.
	var cap: int = passive_cap(combined.rarity)
	var candidates: Array = candidate_passives(items)
	if candidates.is_empty():
		# No input carried a passive (the grey→green case) — roll one fresh.
		# Values roll WEAK now (was 0.15-0.30): duplicates stack to max via
		# add_passive, so three different passives is broad-and-shallow while the
		# same passive three times is one strong effect. That's the decision the
		# old always-max convergence removed.
		if cap > 0:
			var passive = PASSIVE_EFFECTS[randi() % PASSIVE_EFFECTS.size()]
			combined.add_passive(passive["name"], 0.05 + randf() * 0.10)
	else:
		var chosen: Array = []
		# Honour the player's picks first, in their order, but only for passives
		# the inputs actually offer.
		for wanted: Variant in keep_passives:
			if chosen.size() >= cap:
				break
			for c: Dictionary in candidates:
				if c["name"] == str(wanted) and not (c in chosen):
					chosen.append(c)
					break
		# Fill any remaining slots with the strongest unchosen candidates.
		for c: Dictionary in candidates:
			if chosen.size() >= cap:
				break
			if not (c in chosen):
				chosen.append(c)
		for c: Dictionary in chosen:
			combined.add_passive(str(c["name"]), float(c["value"]))

	# Description is always rebuilt from the resolved passive lines so a fused
	# item spells out what each of its passives actually does at its rolled
	# value (2026-08-02 — it used to just list the names).
	combined.description = "\n".join(combined.get_passive_lines())

	return combined
