extends RefCounted
class_name HeroVerbs

# Verbs are the archetype layer (VD-16 BUILD_ARCHETYPES.md, VD-22
# ARCHETYPE_PIECES.md): a verb decides which archetype relics a team is
# offered and which heroes the shop leans toward once a seed is owned.
#
# Two kinds:
# - KIT verbs amplify a move heroes already have (BURN: Coal, Sear, Ember).
# - ELEMENT verbs (VD-22, owner 2026-09-29): every hero of an element carries
#   it. The element's damage type lives only in its relic pieces, so a run
#   that never takes the seed never sees it (unlike the 2026-08-02 scrap).
#   Fire's archetype is Burn; Normal is skipped (owner).
# The role tags in the worksheet are proposals and stay out until accepted.

const BURN := "burn"
const EARTH := "earth"
const LIGHTNING := "lightning"
const WATER := "water"
const AIR := "air"

const VERBS := {
	UnitBase.UnitClass.COAL:  [BURN],
	UnitBase.UnitClass.SEAR:  [BURN],
	UnitBase.UnitClass.EMBER: [BURN],
}

const ELEMENT_VERBS := {
	UnitBase.Element.EARTH: EARTH,
	UnitBase.Element.LIGHTNING: LIGHTNING,
	UnitBase.Element.WATER: WATER,
	UnitBase.Element.AIR: AIR,
}

# ROLE verbs (VD-22, owner 2026-09-30): every hero of a trait class carries
# it. Summoner (one hero, Necro) gets none.
const TANK := "tank"
const MAGE := "mage"
const FIGHTER := "fighter"
const RANGED := "ranged"
const HEALER := "healer"
const ROLE_VERBS := {
	UnitBase.TraitClass.TANK: TANK,
	UnitBase.TraitClass.MAGE: MAGE,
	UnitBase.TraitClass.FIGHTER: FIGHTER,
	UnitBase.TraitClass.RANGED: RANGED,
	UnitBase.TraitClass.HEALER: HEALER,
}

# Summons carry an element but are not heroes.
const NOT_HEROES := [UnitBase.UnitClass.ZOMBIE, UnitBase.UnitClass.BAT, UnitBase.UnitClass.ANT]

# An archetype is only worth seeding when the account can field 2+ of its
# heroes (BUILD_ARCHETYPES.md, seed rules).
const MIN_UNLOCKED_FOR_SEED := 2

# Verbs a hero CLASS carries: its kit verbs plus its natural element's verb.
# For offers and the shop, before a unit exists.
static func class_verbs(unit_class: int) -> Array:
	var out: Array = VERBS.get(unit_class, []).duplicate()
	if unit_class in NOT_HEROES:
		return out
	var ev = ELEMENT_VERBS.get(UnitFactory.element_for_class(unit_class))
	if ev != null:
		out.append(ev)
	var rv = _role_verb(unit_class)
	if rv != null:
		out.append(rv)
	return out

static func _role_verb(unit_class: int):
	if not UnitFactory.TRAIT_CLASS_MAP.has(unit_class):
		return null
	return ROLE_VERBS.get(UnitFactory.TRAIT_CLASS_MAP[unit_class])

# Verbs a live UNIT carries: element verbs follow its current element.
static func unit_verbs(u) -> Array:
	var out: Array = VERBS.get(u.unit_class, []).duplicate()
	if u.unit_class in NOT_HEROES or u.is_summoned:
		return out
	var ev = ELEMENT_VERBS.get(u.current_element)
	if ev != null:
		out.append(ev)
	var rv = _role_verb(u.unit_class)
	if rv != null:
		out.append(rv)
	return out

static func has_verb(unit_class: int, verb: String) -> bool:
	return verb in class_verbs(unit_class)

static func unit_has_verb(u, verb: String) -> bool:
	return verb in unit_verbs(u)

# Distinct hero TYPES carrying the verb among living units. Two Coals count
# once (loop rule 1), so "per X hero" pieces reward a spread, not copies.
static func count_types(units: Array, verb: String) -> int:
	var seen := {}
	for u in units:
		if u and is_instance_valid(u) and u.current_hp > 0 and unit_has_verb(u, verb):
			seen[u.unit_class] = true
	return seen.size()

# Every verb carried by at least one of these units.
static func verbs_on_team(units: Array) -> Array:
	var out: Array = []
	for u in units:
		if not (u and is_instance_valid(u)):
			continue
		for v in unit_verbs(u):
			if not v in out:
				out.append(v)
	return out

# Every hero class, kit or element, that carries at least one verb.
static func _verb_classes() -> Array:
	var out: Array = VERBS.keys()
	for cls in UnitFactory.NATURAL_ASPECT.keys() + UnitFactory.TRAIT_CLASS_MAP.keys():
		if not cls in out and not cls in NOT_HEROES:
			out.append(cls)
	return out

# Verbs this account can build: 2+ of the verb's heroes unlocked.
static func buildable_verbs() -> Array:
	var counts := {}
	for cls in _verb_classes():
		if Progression.is_hero_unlocked(cls):
			for v in class_verbs(cls):
				counts[v] = int(counts.get(v, 0)) + 1
	var out: Array = []
	for v in counts:
		if int(counts[v]) >= MIN_UNLOCKED_FOR_SEED:
			out.append(v)
	return out

# Hero-card label for a verb ("Burn").
static func verb_name(verb: String) -> String:
	return verb.capitalize()

# Heroes carrying a verb, by display name - "Coal, Sear, Ember".
static func hero_names(verb: String) -> String:
	var names: PackedStringArray = []
	for cls in _verb_classes():
		if verb in class_verbs(cls):
			names.append(String(UnitBase.UnitClass.keys()[cls]).capitalize())
	return ", ".join(names)
