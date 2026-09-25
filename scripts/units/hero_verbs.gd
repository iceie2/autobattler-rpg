extends RefCounted
class_name HeroVerbs

# Verbs are what a hero's kit DOES - the archetype layer (VD-16, see
# BUILD_ARCHETYPES.md). A build piece amplifies a verb heroes already have; it
# never hands a verb to a whole element (the 2026-08-02 element-status scrap).
#
# Only BURN is decided so far. The worksheet's other tags (Area, Lockdown,
# Aura, ...) are proposals and stay out of this table until the owner accepts
# them - a tag here changes which relics a team is offered.

const BURN := "burn"

const VERBS := {
	UnitBase.UnitClass.COAL:  [BURN],
	UnitBase.UnitClass.SEAR:  [BURN],
	UnitBase.UnitClass.EMBER: [BURN],
}

# An archetype is only worth seeding when the account can field 2+ of its
# heroes (BUILD_ARCHETYPES.md, seed rules).
const MIN_UNLOCKED_FOR_SEED := 2

static func has_verb(unit_class: int, verb: String) -> bool:
	return verb in VERBS.get(unit_class, [])

# Distinct hero TYPES carrying the verb among living units. Two Coals count
# once (loop rule 1), so Kindling rewards a spread of burners, not copies.
static func count_types(units: Array, verb: String) -> int:
	var seen := {}
	for u in units:
		if u and is_instance_valid(u) and u.current_hp > 0 and has_verb(u.unit_class, verb):
			seen[u.unit_class] = true
	return seen.size()

# Every verb carried by at least one of these units.
static func verbs_on_team(units: Array) -> Array:
	var out: Array = []
	for u in units:
		if not (u and is_instance_valid(u)):
			continue
		for v in VERBS.get(u.unit_class, []):
			if not v in out:
				out.append(v)
	return out

# Verbs this account can build: 2+ of the verb's heroes unlocked.
static func buildable_verbs() -> Array:
	var counts := {}
	for cls in VERBS:
		if Progression.is_hero_unlocked(cls):
			for v in VERBS[cls]:
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
	for cls in VERBS:
		if verb in VERBS[cls]:
			names.append(String(UnitBase.UnitClass.keys()[cls]).capitalize())
	return ", ".join(names)
