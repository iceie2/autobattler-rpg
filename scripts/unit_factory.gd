extends Node
class_name UnitFactory

const UNIT_SCENE = preload("res://scenes/Unit.tscn")
const LPC_ANIM_DATA_SINGLE_SPRITE_SCRIPT = preload("res://addons/addons/LPCAnimatedSprite/LPCAnimationDataSingleSprite.gd")
const SPRITES_BASE_PATH = "res://assets/sprites/lpc_male_animations_2026-01-10T02-53-57"
const CLASS_SPRITES_FOLDER = {
	UnitBase.UnitClass.WARRIOR: "Warrior",
	UnitBase.UnitClass.RANGER: "Ranger",
	UnitBase.UnitClass.MONK: "Monk",
	UnitBase.UnitClass.THIEF: "Thief",
	UnitBase.UnitClass.BLACK_MAGE: "Black_Mage",
	UnitBase.UnitClass.WHITE_MAGE: "White_Mage",
	UnitBase.UnitClass.RED_MAGE: "Red_Mage"
}

# Base stats for each class at level 1
const CLASS_BASE_STATS = {
	UnitBase.UnitClass.WARRIOR: {
		"hp": 120,
		"mana": 30,
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
		"hp": 90,
		"mana": 40,
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
		"hp": 100,
		"mana": 50,
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
		"hp": 80,
		"mana": 35,
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
		"hp": 70,
		"mana": 80,
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
		"hp": 75,
		"mana": 75,
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
		"hp": 85,
		"mana": 65,
		"str": 10,
		"dex": 10,
		"int": 14,
		"res": 10,
		"move": 2,
		"range": 5,
		"off_affinity": 45.0,
		"def_affinity": 20.0
	}
}

static func create_unit(unit_class: UnitBase.UnitClass, element: UnitBase.Element = UnitBase.Element.NORMAL, is_player: bool = true) -> VisualUnit:
	var unit = UNIT_SCENE.instantiate() as VisualUnit

	# Set class, element and ownership before the node is added to the scene tree
	unit.unit_class = unit_class
	unit.current_element = element
	unit.is_player_unit = is_player
	
	# Get base stats for this class
	var stats = CLASS_BASE_STATS[unit_class]
	
	# Apply stats
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
	
	# Set affinity values for all elements
	var base_off = stats["off_affinity"]
	var base_def = stats["def_affinity"]
	
	for elem in UnitBase.Element.values():
		unit.offensive_affinity[elem] = base_off
		unit.defensive_affinity[elem] = base_def
	
	# Set name
	unit.unit_name = unit.get_element_name_string() + " " + unit.get_class_name_string()
	
	# Configure spritesheets per-class so class-specific sprites (weapons, walk, etc.) load correctly
	var sprite_node = unit.get_node_or_null("LPCAnimatedSprite2D")
	if sprite_node:
		var class_folder = CLASS_SPRITES_FOLDER.get(unit_class, unit.get_class_name_string().replace(" ", "_"))
		var sprites_path = SPRITES_BASE_PATH + "/" + class_folder
		var use_single_spritesheet = false
		if unit_class == UnitBase.UnitClass.RANGER:
			var single_sheet_path = sprites_path + "/single.png"
			if FileAccess.file_exists(single_sheet_path):
				sprite_node.animation_data = LPC_ANIM_DATA_SINGLE_SPRITE_SCRIPT.new()
				use_single_spritesheet = true
		sprite_node.spritesheets_path = sprites_path
		if use_single_spritesheet:
			return unit

		# Auto-map required spritesheets to real PNGs in the class folder (check common paths and a top-level scan)
		var anim_data = sprite_node.animation_data
		if anim_data:
			var _mappings_changed = false
			for anim_name in anim_data.required_spritesheets.keys():
				var rel = str(anim_data.required_spritesheets[anim_name])
				var candidate = sprites_path + "/" + rel + ".png"
				if FileAccess.file_exists(candidate):
					continue
				# Try some common alternates
				var alt_list = [
					sprites_path + "/custom/" + anim_name + ".png",
					sprites_path + "/" + anim_name + ".png",
					sprites_path + "/custom/" + anim_name + "_128.png",
					sprites_path + "/" + anim_name + "_128.png"
				]
				var found_path = ""
				for a in alt_list:
					if FileAccess.file_exists(a):
						found_path = a
						break
					# Try some common filename variants (1h_, _oversize, combat)
					if found_path == "":
						var variants = ["1h_" + anim_name, "1h_" + anim_name + "_128", anim_name + "_oversize", anim_name + "_reverse_oversize", "combat", "1h_" + anim_name + "_south"]
						for v in variants:
							var p1 = sprites_path + "/standard/" + v + ".png"
							var p2 = sprites_path + "/custom/" + v + ".png"
							if FileAccess.file_exists(p1):
								found_path = p1
								break
							elif FileAccess.file_exists(p2):
								found_path = p2
								break
					# Recursive directory search fallback
					if found_path == "":
						found_path = UnitFactory._recursive_find_png(sprites_path, anim_name)
					# If we found a candidate, map it relative to sprites_path and try to infer frame size
					if found_path != "":
						var rel_path = found_path.substr(sprites_path.length() + 1, found_path.length())
						rel_path = rel_path.replace(".png", "")
						anim_data.required_spritesheets[anim_name] = rel_path
						_mappings_changed = true
						print("Auto-mapped '%s' -> '%s' for class %s" % [anim_name, rel_path, class_folder])
			# Refresh sprite frames if mappings changed
			if _mappings_changed and sprite_node.has_method("_refresh_sprites"):
				sprite_node._refresh_sprites()
		else:
			sprite_node.visible = false
	
	return unit

static func create_random_unit(unit_class: UnitBase.UnitClass, element: UnitBase.Element = UnitBase.Element.NORMAL, is_player: bool = true) -> VisualUnit:
	# Random single-class unit with optional element and ownership
	return create_unit(unit_class, element, is_player)

static func create_random_class_unit(is_player: bool = true) -> VisualUnit:
	# Randomly select both class and element
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
		UnitBase.UnitClass.RED_MAGE
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

# Recursively search for any PNG under a folder that contains the anim_name substring
static func _recursive_find_png(start_path: String, anim_name: String) -> String:
	var da = DirAccess.open(start_path)
	if not da:
		return ""
	da.list_dir_begin()
	var fname = da.get_next()
	while fname != "":
		if da.current_is_dir():
			if fname != "." and fname != "..":
				var sub = UnitFactory._recursive_find_png(start_path + "/" + fname, anim_name)
				if sub != "":
					da.list_dir_end()
					return sub
		else:
			if fname.to_lower().ends_with(".png") and fname.to_lower().find(anim_name) != -1:
				da.list_dir_end()
				return start_path + "/" + fname
		fname = da.get_next()
	da.list_dir_end()
	return ""
