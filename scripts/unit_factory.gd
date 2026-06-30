extends Node
class_name UnitFactory

# Trait class mapping (for synergies)
const TRAIT_CLASS_MAP = {
	UnitBase.UnitClass.WARRIOR:    UnitBase.TraitClass.FIGHTER,
	UnitBase.UnitClass.RANGER:     UnitBase.TraitClass.RANGED,
	UnitBase.UnitClass.MONK:       UnitBase.TraitClass.FIGHTER,
	UnitBase.UnitClass.THIEF:      UnitBase.TraitClass.FIGHTER,
	UnitBase.UnitClass.BLACK_MAGE: UnitBase.TraitClass.MAGE,
	UnitBase.UnitClass.WHITE_MAGE: UnitBase.TraitClass.HEALER,
	UnitBase.UnitClass.RED_MAGE:   UnitBase.TraitClass.MAGE,
	UnitBase.UnitClass.BLOODHOUND: UnitBase.TraitClass.FIGHTER,
	UnitBase.UnitClass.BOUNCER:    UnitBase.TraitClass.TANK,
	UnitBase.UnitClass.HEADHUNTER: UnitBase.TraitClass.RANGED,
	UnitBase.UnitClass.SHAUNA:     UnitBase.TraitClass.FIGHTER,
	UnitBase.UnitClass.NEMI:       UnitBase.TraitClass.MAGE,
	UnitBase.UnitClass.SHEILDOR:   UnitBase.TraitClass.TANK,
	UnitBase.UnitClass.LORDEE:     UnitBase.TraitClass.FIGHTER,
	UnitBase.UnitClass.NECRO:      UnitBase.TraitClass.SUMMONER,
	# ── Roster expansion (design role → nearest synergy trait) ──
	UnitBase.UnitClass.DOC:        UnitBase.TraitClass.HEALER,   # Support
	UnitBase.UnitClass.RIOT:       UnitBase.TraitClass.TANK,     # Tank
	UnitBase.UnitClass.PASTOR:     UnitBase.TraitClass.MAGE,     # Support/Disruptor
	UnitBase.UnitClass.SABLE:      UnitBase.TraitClass.RANGED,   # Ranged Carry
	UnitBase.UnitClass.RUSH:       UnitBase.TraitClass.FIGHTER,  # Fighter
	UnitBase.UnitClass.STITCH:     UnitBase.TraitClass.MAGE,     # Disruptor
	UnitBase.UnitClass.COAL:       UnitBase.TraitClass.FIGHTER,  # Fighter
	UnitBase.UnitClass.JUNE:       UnitBase.TraitClass.HEALER,   # Support
	UnitBase.UnitClass.CROSS:      UnitBase.TraitClass.TANK,     # Tank
	UnitBase.UnitClass.SEAR:      UnitBase.TraitClass.MAGE,     # Magic Fighter
	UnitBase.UnitClass.EMBER:      UnitBase.TraitClass.RANGED,   # Ranged Carry
	UnitBase.UnitClass.RIFT:       UnitBase.TraitClass.MAGE,     # Magic Fighter
	UnitBase.UnitClass.ZOLT:       UnitBase.TraitClass.MAGE,     # Magic Carry
	UnitBase.UnitClass.LUMEN:      UnitBase.TraitClass.MAGE,     # Magic Carry
	UnitBase.UnitClass.STATIC:     UnitBase.TraitClass.MAGE,     # Disruptor
	UnitBase.UnitClass.REED:       UnitBase.TraitClass.HEALER,   # Support
	UnitBase.UnitClass.VAIL:       UnitBase.TraitClass.HEALER,   # Support
	UnitBase.UnitClass.SPORE:      UnitBase.TraitClass.MAGE,     # Magic Carry
	UnitBase.UnitClass.ZOMBIE:     UnitBase.TraitClass.FIGHTER,
	UnitBase.UnitClass.BAT:        UnitBase.TraitClass.FIGHTER,
}

# Natural aspect: the element that best scales each hero's kit. Aspect is rolled
# randomly at recruitment (any element is valid and never punished), but matching
# the natural aspect grants a small kit bonus — see UnitFactory.natural_aspect().
# Void-themed heroes have no matching element, so they home to NORMAL.
const NATURAL_ASPECT = {
	UnitBase.UnitClass.BOUNCER:    UnitBase.Element.NORMAL,
	UnitBase.UnitClass.HEADHUNTER: UnitBase.Element.AIR,
	UnitBase.UnitClass.SHAUNA:     UnitBase.Element.FIRE,
	UnitBase.UnitClass.NEMI:       UnitBase.Element.WATER,
	UnitBase.UnitClass.BLOODHOUND: UnitBase.Element.EARTH,
	UnitBase.UnitClass.SHEILDOR:   UnitBase.Element.EARTH,
	UnitBase.UnitClass.LORDEE:     UnitBase.Element.NORMAL,
	UnitBase.UnitClass.NECRO:      UnitBase.Element.NORMAL,
	UnitBase.UnitClass.DOC:        UnitBase.Element.WATER,
	UnitBase.UnitClass.RIOT:       UnitBase.Element.NORMAL,
	UnitBase.UnitClass.PASTOR:     UnitBase.Element.FIRE,
	UnitBase.UnitClass.SABLE:      UnitBase.Element.AIR,
	UnitBase.UnitClass.RUSH:       UnitBase.Element.LIGHTNING,
	UnitBase.UnitClass.STITCH:     UnitBase.Element.NORMAL,
	UnitBase.UnitClass.COAL:       UnitBase.Element.FIRE,
	UnitBase.UnitClass.JUNE:       UnitBase.Element.EARTH,
	UnitBase.UnitClass.CROSS:      UnitBase.Element.NORMAL,
	UnitBase.UnitClass.SEAR:      UnitBase.Element.FIRE,
	UnitBase.UnitClass.EMBER:      UnitBase.Element.FIRE,
	UnitBase.UnitClass.RIFT:       UnitBase.Element.NORMAL,
	UnitBase.UnitClass.ZOLT:       UnitBase.Element.LIGHTNING,
	UnitBase.UnitClass.LUMEN:      UnitBase.Element.AIR,
	UnitBase.UnitClass.STATIC:     UnitBase.Element.LIGHTNING,
	UnitBase.UnitClass.REED:       UnitBase.Element.WATER,
	UnitBase.UnitClass.VAIL:       UnitBase.Element.AIR,
	UnitBase.UnitClass.SPORE:      UnitBase.Element.EARTH,
}

# 1.0 normally; matched natural aspect grants +15% kit magnitude (no off-aspect penalty).
static func natural_aspect(unit: UnitBase) -> float:
	if NATURAL_ASPECT.get(unit.unit_class, UnitBase.Element.NORMAL) == unit.current_element:
		return 1.15
	return 1.0

# Base stats for each class at level 1
const CLASS_BASE_STATS = {
	UnitBase.UnitClass.WARRIOR:    { "hp":1200,"mana":300, "str":15,"dex":8, "int":5, "res":12,"spr":5,  "move":2,"range":1, "off_affinity":30.0,"def_affinity":20.0 },
	UnitBase.UnitClass.RANGER:     { "hp":900, "mana":400, "str":10,"dex":16,"int":8, "res":7, "spr":7,  "move":3,"range":4, "off_affinity":40.0,"def_affinity":10.0 },
	UnitBase.UnitClass.MONK:       { "hp":1000,"mana":500, "str":12,"dex":12,"int":10,"res":10,"spr":12, "move":3,"range":1, "off_affinity":25.0,"def_affinity":25.0 },
	UnitBase.UnitClass.THIEF:      { "hp":800, "mana":350, "str":8, "dex":18,"int":10,"res":6, "spr":4,  "move":5,"range":1, "off_affinity":50.0,"def_affinity":5.0  },
	UnitBase.UnitClass.BLACK_MAGE: { "hp":700, "mana":800, "str":5, "dex":7, "int":18,"res":8, "spr":14, "move":2,"range":5, "off_affinity":60.0,"def_affinity":15.0 },
	UnitBase.UnitClass.WHITE_MAGE: { "hp":750, "mana":750, "str":6, "dex":8, "int":16,"res":12,"spr":16, "move":2,"range":5, "off_affinity":35.0,"def_affinity":30.0 },
	UnitBase.UnitClass.RED_MAGE:   { "hp":850, "mana":650, "str":10,"dex":10,"int":14,"res":10,"spr":11, "move":2,"range":5, "off_affinity":45.0,"def_affinity":20.0 },
	UnitBase.UnitClass.BLOODHOUND: { "hp":1100,"mana":400, "str":14,"dex":12,"int":6, "res":14,"spr":6,  "move":3,"range":1, "off_affinity":35.0,"def_affinity":25.0 },
	UnitBase.UnitClass.BOUNCER:    { "hp":1300,"mana":600, "str":8, "dex":6, "int":16,"res":16,"spr":12, "move":2,"range":2, "off_affinity":30.0,"def_affinity":35.0 },
	UnitBase.UnitClass.HEADHUNTER: { "hp":600, "mana":350, "str":14,"dex":20,"int":12,"res":5, "spr":5,  "move":3,"range":6, "off_affinity":55.0,"def_affinity":8.0  },
	UnitBase.UnitClass.SHAUNA:     { "hp":700, "mana":400, "str":12,"dex":20,"int":8, "res":6, "spr":6,  "move":3,"range":5, "off_affinity":50.0,"def_affinity":8.0  },
	UnitBase.UnitClass.NEMI:       { "hp":750,  "mana":600, "str":6, "dex":10,"int":18,"res":10,"spr":18, "move":2,"range":4, "off_affinity":35.0,"def_affinity":20.0 },
	UnitBase.UnitClass.SHEILDOR:   { "hp":1400, "mana":700, "str":10,"dex":8, "int":14,"res":18,"spr":14, "move":2,"range":1, "off_affinity":20.0,"def_affinity":40.0 },
	UnitBase.UnitClass.LORDEE:     { "hp":950,  "mana":500, "str":16,"dex":14,"int":10,"res":10,"spr":8,  "move":3,"range":1, "off_affinity":45.0,"def_affinity":15.0 },
	UnitBase.UnitClass.NECRO:      { "hp":800,  "mana":900, "str":5, "dex":7, "int":20,"res":8, "spr":16, "move":2,"range":4, "off_affinity":30.0,"def_affinity":15.0 },
	# ── Roster expansion ──────────────────────────────────────────────────────
	UnitBase.UnitClass.DOC:        { "hp":850,  "mana":750, "str":6, "dex":9, "int":16,"res":9, "spr":18, "move":3,"range":3, "off_affinity":30.0,"def_affinity":20.0 },
	UnitBase.UnitClass.RIOT:       { "hp":1500, "mana":500, "str":11,"dex":7, "int":8, "res":20,"spr":8,  "move":2,"range":1, "off_affinity":20.0,"def_affinity":40.0 },
	UnitBase.UnitClass.PASTOR:     { "hp":900,  "mana":650, "str":8, "dex":9, "int":15,"res":11,"spr":13, "move":2,"range":3, "off_affinity":40.0,"def_affinity":20.0 },
	UnitBase.UnitClass.SABLE:      { "hp":650,  "mana":350, "str":12,"dex":19,"int":9, "res":6, "spr":6,  "move":3,"range":6, "off_affinity":55.0,"def_affinity":8.0  },
	UnitBase.UnitClass.RUSH:       { "hp":820,  "mana":300, "str":15,"dex":18,"int":7, "res":8, "spr":6,  "move":6,"range":1, "off_affinity":45.0,"def_affinity":10.0 },
	UnitBase.UnitClass.STITCH:     { "hp":780,  "mana":700, "str":7, "dex":12,"int":16,"res":9, "spr":12, "move":2,"range":2, "off_affinity":40.0,"def_affinity":15.0 },
	UnitBase.UnitClass.COAL:       { "hp":1150, "mana":350, "str":17,"dex":11,"int":8, "res":13,"spr":6,  "move":3,"range":1, "off_affinity":45.0,"def_affinity":20.0 },
	UnitBase.UnitClass.JUNE:       { "hp":880,  "mana":700, "str":6, "dex":9, "int":14,"res":10,"spr":17, "move":2,"range":3, "off_affinity":30.0,"def_affinity":22.0 },
	UnitBase.UnitClass.CROSS:      { "hp":1450, "mana":550, "str":12,"dex":7, "int":10,"res":18,"spr":12, "move":2,"range":1, "off_affinity":25.0,"def_affinity":38.0 },
	UnitBase.UnitClass.SEAR:      { "hp":900,  "mana":600, "str":13,"dex":10,"int":16,"res":10,"spr":9,  "move":3,"range":2, "off_affinity":50.0,"def_affinity":15.0 },
	UnitBase.UnitClass.EMBER:      { "hp":640,  "mana":400, "str":10,"dex":18,"int":13,"res":6, "spr":7,  "move":3,"range":5, "off_affinity":55.0,"def_affinity":8.0  },
	UnitBase.UnitClass.RIFT:       { "hp":950,  "mana":650, "str":12,"dex":10,"int":16,"res":12,"spr":9,  "move":3,"range":2, "off_affinity":45.0,"def_affinity":22.0 },
	UnitBase.UnitClass.ZOLT:       { "hp":720,  "mana":850, "str":5, "dex":9, "int":20,"res":8, "spr":15, "move":2,"range":5, "off_affinity":60.0,"def_affinity":12.0 },
	UnitBase.UnitClass.LUMEN:      { "hp":700,  "mana":800, "str":5, "dex":11,"int":19,"res":7, "spr":13, "move":2,"range":5, "off_affinity":58.0,"def_affinity":10.0 },
	UnitBase.UnitClass.STATIC:     { "hp":820,  "mana":700, "str":7, "dex":11,"int":16,"res":10,"spr":12, "move":2,"range":3, "off_affinity":45.0,"def_affinity":18.0 },
	UnitBase.UnitClass.REED:       { "hp":860,  "mana":780, "str":6, "dex":8, "int":15,"res":11,"spr":18, "move":2,"range":4, "off_affinity":30.0,"def_affinity":25.0 },
	UnitBase.UnitClass.VAIL:       { "hp":820,  "mana":780, "str":6, "dex":10,"int":15,"res":9, "spr":18, "move":3,"range":4, "off_affinity":30.0,"def_affinity":18.0 },
	UnitBase.UnitClass.SPORE:      { "hp":780,  "mana":820, "str":5, "dex":9, "int":19,"res":9, "spr":14, "move":2,"range":4, "off_affinity":50.0,"def_affinity":18.0 },
	UnitBase.UnitClass.ZOMBIE:     { "hp":85,   "mana":0,   "str":6, "dex":4, "int":1, "res":5, "spr":1,  "move":2,"range":1, "off_affinity":20.0,"def_affinity":10.0 },
	UnitBase.UnitClass.BAT:        { "hp":55,   "mana":0,   "str":4, "dex":10,"int":1, "res":3, "spr":1,  "move":4,"range":1, "off_affinity":20.0,"def_affinity":5.0  },
}

static func create_unit(unit_class: UnitBase.UnitClass, element: UnitBase.Element = UnitBase.Element.NORMAL, is_player: bool = true) -> VisualUnit:
	var unit = VisualUnit.new()

	unit.unit_class = unit_class
	unit.trait_class = TRAIT_CLASS_MAP.get(unit_class, UnitBase.TraitClass.FIGHTER)
	unit.current_element = element
	unit.is_player_unit = is_player

	var stats = CLASS_BASE_STATS[unit_class]
	unit.max_hp = stats["hp"]
	unit.current_hp = stats["hp"]
	unit.max_mana = stats["mana"]
	unit.current_mana = stats["mana"]
	unit.strength = stats["str"]
	unit.dexterity = stats["dex"]
	unit.intelligence = stats["int"]
	unit.resistance = stats["res"]
	unit.spirit = stats.get("spr", 5)
	unit.movement_speed = stats["move"]
	unit.attack_range = stats["range"]

	var base_off = stats["off_affinity"]
	var base_def = stats["def_affinity"]
	for elem in UnitBase.Element.values():
		unit.offensive_affinity[elem] = base_off
		unit.defensive_affinity[elem] = base_def

	unit.unit_name = unit.get_element_name_string() + " " + unit.get_class_name_string()

	# Random sprite variant (0–2) so same class looks different each spawn
	unit.sprite_variant = randi() % 3

	# Assign class skill
	match unit_class:
		UnitBase.UnitClass.WARRIOR:
			unit.skill_name = "Whirlwind"
			unit.skill_damage_multiplier = 1.2
			unit.skill_range = 1
			unit.skill_cooldown_max = 3
		UnitBase.UnitClass.RANGER:
			unit.skill_name = "Arrow Rain"
			unit.skill_damage_multiplier = 0.8
			unit.skill_range = 5
			unit.skill_cooldown_max = 4
		UnitBase.UnitClass.MONK:
			unit.skill_name = "Chi Burst"
			unit.skill_damage_multiplier = 1.0
			unit.skill_range = 2
			unit.skill_cooldown_max = 4
		UnitBase.UnitClass.THIEF:
			unit.skill_name = "Shadow Strike"
			unit.skill_damage_multiplier = 2.5
			unit.skill_range = 2
			unit.skill_cooldown_max = 5
		UnitBase.UnitClass.BLACK_MAGE:
			unit.skill_name = "Inferno"
			unit.skill_damage_multiplier = 2.0
			unit.skill_range = 5
			unit.skill_cooldown_max = 4
		UnitBase.UnitClass.WHITE_MAGE:
			unit.skill_name = "Holy Light"
			unit.skill_damage_multiplier = 0.0   # healing skill
			unit.skill_range = 99
			unit.skill_cooldown_max = 5
		UnitBase.UnitClass.RED_MAGE:
			unit.skill_name = "Chaos Bolt"
			unit.skill_damage_multiplier = 1.8
			unit.skill_range = 4
			unit.skill_cooldown_max = 3
		# ── New classes ───────────────────────────────────────────────────────
		UnitBase.UnitClass.BLOODHOUND:
			unit.passive_name = "Blood Frenzy"
			unit.skill_name = "Bite"
			unit.skill_damage_multiplier = 1.3
			unit.skill_range = 1
			unit.skill_cooldown_max = 3
			unit.skill_mana_cost = 50
			unit.ultimate_name = "Pounce"
			unit.ultimate_damage_mult = 2.5
			unit.ultimate_range = 8
			unit.ultimate_charge_max = 300
		UnitBase.UnitClass.BOUNCER:
			unit.passive_name = "Presence"
			unit.skill_name = "Slam"
			unit.skill_damage_multiplier = 1.0
			unit.skill_range = 2
			unit.skill_cooldown_max = 4
			unit.skill_mana_cost = 80
			unit.ultimate_name = "Gravity Drop"
			unit.ultimate_damage_mult = 1.5
			unit.ultimate_range = 4
			unit.ultimate_charge_max = 350
		UnitBase.UnitClass.HEADHUNTER:
			unit.passive_name = "Seventh Shot"
			unit.skill_name = "Rapid Fire"
			unit.skill_damage_multiplier = 1.0
			unit.skill_range = 8
			unit.skill_cooldown_max = 5
			unit.skill_mana_cost = 60
			unit.ultimate_name = "Snipe"
			unit.ultimate_damage_mult = 4.0
			unit.ultimate_range = 99
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.SHAUNA:
			unit.passive_name        = "Glass Cannon"
			unit.skill_name          = "Kite"
			unit.skill_damage_multiplier = 1.5
			unit.skill_range         = 1
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.ultimate_name       = "Overdrive"
			unit.ultimate_damage_mult = 0.0   # utility ult
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.NEMI:
			unit.passive_name        = "Resonance"
			unit.skill_name          = "Tide"
			unit.skill_damage_multiplier = 0.8
			unit.skill_range         = 4
			unit.skill_cooldown_max  = 3
			unit.skill_mana_cost     = 80
			unit.ultimate_name       = "Tidal Wave"
			unit.ultimate_damage_mult = 1.5
			unit.ultimate_charge_max = 450
		UnitBase.UnitClass.SHEILDOR:
			unit.passive_name        = "Guardian Aura"
			unit.skill_name          = "Iron Bulwark"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 2
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 80
			unit.ultimate_name       = "Guardian Leap"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 8
			unit.ultimate_charge_max = 350
		UnitBase.UnitClass.LORDEE:
			unit.passive_name        = "Feeding Frenzy"
			unit.skill_name          = "Ground Slam"
			unit.skill_damage_multiplier = 1.2
			unit.skill_range         = 2
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 70
			unit.ultimate_name       = "Parasite Lunge"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 6
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.NECRO:
			unit.passive_name        = "Soul Harvest"
			unit.skill_name          = "Raise Zombie"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 3
			unit.skill_cooldown_max  = 5
			unit.skill_mana_cost     = 120
			unit.ultimate_name       = "Bat Swarm"
			unit.ultimate_damage_mult = 0.6
			unit.ultimate_range      = 5
			unit.ultimate_charge_max = 500
		# ── Roster expansion ───────────────────────────────────────────────────
		UnitBase.UnitClass.DOC:
			unit.passive_name        = "Triage"
			unit.skill_name          = "Inject"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 4
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 70
			unit.ultimate_name       = "Field Surgery"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 450
		UnitBase.UnitClass.RIOT:
			unit.passive_name        = "Crowd Control"
			unit.skill_name          = "Shield Bash"
			unit.skill_damage_multiplier = 1.1
			unit.skill_range         = 1
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.ultimate_name       = "Kettle"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 350
		UnitBase.UnitClass.PASTOR:
			unit.passive_name        = "Righteous Fury"
			unit.skill_name          = "Sermon"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 4
			unit.skill_cooldown_max  = 5
			unit.skill_mana_cost     = 70
			unit.ultimate_name       = "Damnation"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.SABLE:
			unit.passive_name        = "Momentum"
			unit.skill_name          = "Bolt"
			unit.skill_damage_multiplier = 1.6
			unit.skill_range         = 7
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 50
			unit.ultimate_name       = "Headshot"
			unit.ultimate_damage_mult = 4.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.RUSH:
			unit.passive_name        = "Fleetfoot"
			unit.skill_name          = "Blitz"
			unit.skill_damage_multiplier = 1.1
			unit.skill_range         = 6
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.ultimate_name       = "Afterimage"
			unit.ultimate_damage_mult = 1.2
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.STITCH:
			unit.passive_name        = "Loose Threads"
			unit.skill_name          = "Link"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 6
			unit.skill_cooldown_max  = 5
			unit.skill_mana_cost     = 70
			unit.ultimate_name       = "Puppet"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 6
			unit.ultimate_charge_max = 450
		UnitBase.UnitClass.COAL:
			unit.passive_name        = "Smolder"
			unit.skill_name          = "Stoke"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 1
			unit.skill_cooldown_max  = 5
			unit.skill_mana_cost     = 50
			unit.ultimate_name       = "Meltdown"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 1
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.JUNE:
			unit.passive_name        = "Verdant Aura"
			unit.skill_name          = "Root"
			unit.skill_damage_multiplier = 0.4
			unit.skill_range         = 3
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.ultimate_name       = "Bloom"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.CROSS:
			unit.passive_name        = "Penance"
			unit.skill_name          = "Absolution"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 4
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.ultimate_name       = "Judgment"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 400
		UnitBase.UnitClass.SEAR:
			unit.passive_name        = "Scorched Path"
			unit.skill_name          = "Ignite"
			unit.skill_damage_multiplier = 1.2
			unit.skill_range         = 3
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.ultimate_name       = "Conflagration"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 420
		UnitBase.UnitClass.EMBER:
			unit.passive_name        = "Burning Arrows"
			unit.skill_name          = "Cinder Shot"
			unit.skill_damage_multiplier = 1.2
			unit.skill_range         = 5
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 50
			unit.ultimate_name       = "Wildfire"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 420
		UnitBase.UnitClass.RIFT:
			unit.passive_name        = "Backlash"
			unit.skill_name          = "Tear"
			unit.skill_damage_multiplier = 1.4
			unit.skill_range         = 5
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.ultimate_name       = "Collapse"
			unit.ultimate_damage_mult = 2.2
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 450
		UnitBase.UnitClass.ZOLT:
			unit.passive_name        = "Chain Lightning"
			unit.skill_name          = "Thunderstorm"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 6
			unit.skill_cooldown_max  = 6
			unit.skill_mana_cost     = 90
			unit.ultimate_name       = "Thunderhammer"
			unit.ultimate_damage_mult = 4.5
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 480
		UnitBase.UnitClass.LUMEN:
			unit.passive_name        = "Refraction"
			unit.skill_name          = "Refract"
			unit.skill_damage_multiplier = 0.9
			unit.skill_range         = 5
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.ultimate_name       = "Prism"
			unit.ultimate_damage_mult = 1.4
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 460
		UnitBase.UnitClass.STATIC:
			unit.passive_name        = "Live Wire"
			unit.skill_name          = "Tripwire"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 4
			unit.skill_cooldown_max  = 5
			unit.skill_mana_cost     = 60
			unit.ultimate_name       = "Grid"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 420
		UnitBase.UnitClass.REED:
			unit.passive_name        = "Wellspring"
			unit.skill_name          = "Cleanse"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 4
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 60
			unit.ultimate_name       = "Confluence"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 430
		UnitBase.UnitClass.VAIL:
			unit.passive_name        = "Far Winds"
			unit.skill_name          = "Updraft"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 99
			unit.skill_cooldown_max  = 5
			unit.skill_mana_cost     = 60
			unit.ultimate_name       = "Tailwind"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 420
		UnitBase.UnitClass.SPORE:
			unit.passive_name        = "Spore Cloud"
			unit.skill_name          = "Bloom"
			unit.skill_damage_multiplier = 0.0
			unit.skill_range         = 4
			unit.skill_cooldown_max  = 4
			unit.skill_mana_cost     = 50
			unit.ultimate_name       = "Release"
			unit.ultimate_damage_mult = 0.0
			unit.ultimate_range      = 99
			unit.ultimate_charge_max = 440
		UnitBase.UnitClass.ZOMBIE:
			unit.skill_name          = "Claw"
			unit.skill_damage_multiplier = 1.0
			unit.skill_range         = 1
			unit.skill_cooldown_max  = 3
			unit.skill_mana_cost     = 0
		UnitBase.UnitClass.BAT:
			unit.skill_name          = "Bite"
			unit.skill_damage_multiplier = 0.8
			unit.skill_range         = 1
			unit.skill_cooldown_max  = 2
			unit.skill_mana_cost     = 0
	# skill_cd_time is initialized by the battle manager (start on cooldown).

	return unit

# ── Gacha roll system ────────────────────────────────────────────────────────

# Roll per-stat bonuses for a recruit offer.
# Returns {"stats": {key: {flat, growth}}, "grade": "A", "avg_pct": 0.08}
static func generate_recruit_rolls() -> Dictionary:
	const PCT_STATS := ["hp", "mana", "str", "dex", "int", "res", "spr"]
	var stat_rolls: Dictionary = {}
	var total_flat := 0.0
	for key in PCT_STATS:
		var flat   := randf_range(-0.25, 0.30)
		var growth := randf_range(-0.08, 0.18)
		stat_rolls[key] = {"flat": flat, "growth": growth}
		total_flat += flat
	# SPD and RNG are integer rolls (small deltas feel big)
	stat_rolls["move"]  = {"flat": float(randi_range(-1, 1)),  "growth": 0.0, "is_int": true}
	stat_rolls["range"] = {"flat": float(randi_range(-1, 2)),  "growth": 0.0, "is_int": true}

	var avg := total_flat / float(PCT_STATS.size())
	var grade := "B"
	if   avg >= 0.15: grade = "S"
	elif avg >= 0.06: grade = "A"
	elif avg >= -0.03: grade = "B"
	elif avg >= -0.11: grade = "C"
	else:              grade = "D"
	return {"stats": stat_rolls, "grade": grade, "avg_pct": avg}


# Apply rolls from generate_recruit_rolls() to a newly created unit.
static func apply_recruit_rolls(unit: UnitBase, rolls: Dictionary) -> void:
	var stats: Dictionary = rolls.get("stats", {})

	unit.max_hp         = maxi(1, int(unit.max_hp         * (1.0 + stats.get("hp",   {}).get("flat", 0.0))))
	unit.current_hp     = unit.max_hp
	unit.max_mana       = maxi(1, int(unit.max_mana       * (1.0 + stats.get("mana", {}).get("flat", 0.0))))
	unit.current_mana   = unit.max_mana
	unit.strength       = maxi(1, int(unit.strength       * (1.0 + stats.get("str",  {}).get("flat", 0.0))))
	unit.dexterity      = maxi(1, int(unit.dexterity      * (1.0 + stats.get("dex",  {}).get("flat", 0.0))))
	unit.intelligence   = maxi(1, int(unit.intelligence   * (1.0 + stats.get("int",  {}).get("flat", 0.0))))
	unit.resistance     = maxi(1, int(unit.resistance     * (1.0 + stats.get("res",  {}).get("flat", 0.0))))
	unit.spirit         = maxi(1, int(unit.spirit         * (1.0 + stats.get("spr",  {}).get("flat", 0.0))))
	unit.movement_speed = maxi(1, unit.movement_speed + int(stats.get("move",  {}).get("flat", 0.0)))
	unit.attack_range   = maxi(1, unit.attack_range   + int(stats.get("range", {}).get("flat", 0.0)))

	unit.recruit_rolls = rolls
	unit.recruit_grade = rolls.get("grade", "B")


static func create_random_unit(unit_class: UnitBase.UnitClass, element: UnitBase.Element = UnitBase.Element.NORMAL, is_player: bool = true) -> VisualUnit:
	return create_unit(unit_class, element, is_player)

static func create_random_class_unit(is_player: bool = true) -> VisualUnit:
	var classes = get_all_classes()
	var elements = get_all_elements()
	var random_class = classes[randi() % classes.size()] as UnitBase.UnitClass
	var random_element = elements[randi() % elements.size()] as UnitBase.Element
	return create_unit(random_class, random_element, is_player)

# Recruitable hero pool. The 7 legacy RPG classes (Warrior/Ranger/Monk/Thief/
# Black/White/Red Mage) were retired from recruitment — they live on only as the
# stat/skill templates EnemyFactory reuses, so their enum + implementations stay.
static func get_all_classes() -> Array:
	return [
		# Original 8 custom heroes
		UnitBase.UnitClass.BLOODHOUND,
		UnitBase.UnitClass.BOUNCER,
		UnitBase.UnitClass.HEADHUNTER,
		UnitBase.UnitClass.SHAUNA,
		UnitBase.UnitClass.NEMI,
		UnitBase.UnitClass.SHEILDOR,
		UnitBase.UnitClass.LORDEE,
		UnitBase.UnitClass.NECRO,
		# Roster expansion (18)
		UnitBase.UnitClass.DOC,
		UnitBase.UnitClass.RIOT,
		UnitBase.UnitClass.PASTOR,
		UnitBase.UnitClass.SABLE,
		UnitBase.UnitClass.RUSH,
		UnitBase.UnitClass.STITCH,
		UnitBase.UnitClass.COAL,
		UnitBase.UnitClass.JUNE,
		UnitBase.UnitClass.CROSS,
		UnitBase.UnitClass.SEAR,
		UnitBase.UnitClass.EMBER,
		UnitBase.UnitClass.RIFT,
		UnitBase.UnitClass.ZOLT,
		UnitBase.UnitClass.LUMEN,
		UnitBase.UnitClass.STATIC,
		UnitBase.UnitClass.REED,
		UnitBase.UnitClass.VAIL,
		UnitBase.UnitClass.SPORE,
	]

static func get_all_elements() -> Array:
	return [
		UnitBase.Element.NORMAL,
		UnitBase.Element.FIRE,
		UnitBase.Element.WATER,
		UnitBase.Element.EARTH,
		UnitBase.Element.AIR,
		UnitBase.Element.LIGHTNING
	]
