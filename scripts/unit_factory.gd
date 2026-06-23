extends Node
class_name UnitFactory

# Base stats for each class at level 1
const CLASS_BASE_STATS = {
	UnitBase.UnitClass.WARRIOR: {
		"hp": 1200,
		"mana": 300,
		"str": 15,
		"dex": 8,
		"int": 5,
		"res": 12,
		"move": 2,
		"range": 1,
		"off_affinity": 30.0,
		"def_affinity": 20.0
	},
	UnitBase.UnitClass.RANGER: {
		"hp": 900,
		"mana": 400,
		"str": 10,
		"dex": 16,
		"int": 8,
		"res": 7,
		"move": 3,
		"range": 4,
		"off_affinity": 40.0,
		"def_affinity": 10.0
	},
	UnitBase.UnitClass.MONK: {
		"hp": 1000,
		"mana": 500,
		"str": 12,
		"dex": 12,
		"int": 10,
		"res": 10,
		"move": 3,
		"range": 1,
		"off_affinity": 25.0,
		"def_affinity": 25.0
	},
	UnitBase.UnitClass.THIEF: {
		"hp": 800,
		"mana": 350,
		"str": 8,
		"dex": 18,
		"int": 10,
		"res": 6,
		"move": 5,
		"range": 1,
		"off_affinity": 50.0,
		"def_affinity": 5.0
	},
	UnitBase.UnitClass.BLACK_MAGE: {
		"hp": 700,
		"mana": 800,
		"str": 5,
		"dex": 7,
		"int": 18,
		"res": 8,
		"move": 2,
		"range": 5,
		"off_affinity": 60.0,
		"def_affinity": 15.0
	},
	UnitBase.UnitClass.WHITE_MAGE: {
		"hp": 750,
		"mana": 750,
		"str": 6,
		"dex": 8,
		"int": 16,
		"res": 12,
		"move": 2,
		"range": 5,
		"off_affinity": 35.0,
		"def_affinity": 30.0
	},
	UnitBase.UnitClass.RED_MAGE: {
		"hp": 850, "mana": 650,
		"str": 10, "dex": 10, "int": 14, "res": 10,
		"move": 2, "range": 5,
		"off_affinity": 45.0, "def_affinity": 20.0
	},
	UnitBase.UnitClass.BLOODHOUND: {
		"hp": 1100, "mana": 400,
		"str": 14, "dex": 12, "int": 6, "res": 14,
		"move": 3, "range": 1,
		"off_affinity": 35.0, "def_affinity": 25.0
	},
	UnitBase.UnitClass.BOUNCER: {
		"hp": 1300, "mana": 600,
		"str": 8, "dex": 6, "int": 16, "res": 16,
		"move": 2, "range": 2,
		"off_affinity": 30.0, "def_affinity": 35.0
	},
	UnitBase.UnitClass.HEADHUNTER: {
		"hp": 600, "mana": 350,
		"str": 14, "dex": 20, "int": 12, "res": 5,
		"move": 3, "range": 6,
		"off_affinity": 55.0, "def_affinity": 8.0
	},
	UnitBase.UnitClass.SHAUNA: {
		"hp": 700, "mana": 400,
		"str": 12, "dex": 20, "int": 8, "res": 6,
		"move": 3, "range": 5,
		"off_affinity": 50.0, "def_affinity": 8.0
	},
	UnitBase.UnitClass.NEMI: {
		"hp": 750, "mana": 600,
		"str": 6, "dex": 10, "int": 18, "res": 10,
		"move": 2, "range": 4,
		"off_affinity": 35.0, "def_affinity": 20.0
	},
}

static func create_unit(unit_class: UnitBase.UnitClass, element: UnitBase.Element = UnitBase.Element.NORMAL, is_player: bool = true) -> VisualUnit:
	var unit = VisualUnit.new()

	unit.unit_class = unit_class
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
	unit.skill_cooldown = unit.skill_cooldown_max  # start on cooldown

	return unit

static func create_random_unit(unit_class: UnitBase.UnitClass, element: UnitBase.Element = UnitBase.Element.NORMAL, is_player: bool = true) -> VisualUnit:
	return create_unit(unit_class, element, is_player)

static func create_random_class_unit(is_player: bool = true) -> VisualUnit:
	var classes = get_all_classes()
	var elements = get_all_elements()
	var random_class = classes[randi() % classes.size()] as UnitBase.UnitClass
	var random_element = elements[randi() % elements.size()] as UnitBase.Element
	return create_unit(random_class, random_element, is_player)

static func get_all_classes() -> Array:
	return [
		UnitBase.UnitClass.WARRIOR,
		UnitBase.UnitClass.RANGER,
		UnitBase.UnitClass.MONK,
		UnitBase.UnitClass.THIEF,
		UnitBase.UnitClass.BLACK_MAGE,
		UnitBase.UnitClass.WHITE_MAGE,
		UnitBase.UnitClass.RED_MAGE,
		UnitBase.UnitClass.BLOODHOUND,
		UnitBase.UnitClass.BOUNCER,
		UnitBase.UnitClass.HEADHUNTER,
		UnitBase.UnitClass.SHAUNA,
		UnitBase.UnitClass.NEMI,
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
