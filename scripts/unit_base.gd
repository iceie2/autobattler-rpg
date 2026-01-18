extends Node2D
class_name UnitBase

# Element types
enum Element {
	NORMAL,
	FIRE,
	WATER,
	EARTH,
	AIR,
	LIGHTNING
}

# Class types
enum UnitClass {
	WARRIOR,
	RANGER,
	MONK,
	THIEF,
	BLACK_MAGE,
	WHITE_MAGE,
	RED_MAGE
}

# Unit identity
@export var unit_name: String = "Unit"
@export var unit_class: UnitClass = UnitClass.WARRIOR
@export var current_element: Element = Element.NORMAL
@export var level: int = 1

# Core stats
@export var max_hp: int = 100
@export var current_hp: int = 100
@export var max_mana: int = 50
@export var current_mana: int = 50

# Attributes
@export var strength: int = 10
@export var dexterity: int = 10
@export var intelligence: int = 10
@export var resistance: int = 10

# Movement and Combat
@export var movement_speed: int = 3
@export var attack_range: int = 1

# Movement interpolation
var is_moving: bool = false
var move_start_pos: Vector2 = Vector2.ZERO
var move_target_pos: Vector2 = Vector2.ZERO
var move_progress: float = 0.0
var target_grid_pos: Vector2i = Vector2i.ZERO

# Elemental Affinity - per element dictionaries
var offensive_affinity: Dictionary = {
	Element.NORMAL: 0.0,
	Element.FIRE: 0.0,
	Element.WATER: 0.0,
	Element.EARTH: 0.0,
	Element.AIR: 0.0,
	Element.LIGHTNING: 0.0
}

var defensive_affinity: Dictionary = {
	Element.NORMAL: 0.0,
	Element.FIRE: 0.0,
	Element.WATER: 0.0,
	Element.EARTH: 0.0,
	Element.AIR: 0.0,
	Element.LIGHTNING: 0.0
}

# Equipment slots
var equipped_weapon = null
var equipped_armor = null
var equipped_accessory = null

# Battle state
var grid_position: Vector2i = Vector2i.ZERO
var target_unit = null
var is_player_unit: bool = true
var battle_manager = null  # Reference to spawn projectiles
var damage_text_container: Node2D = null  # Reference to spawn damage text

# Derived stats
var attack_damage: int:
	get:
		return strength + int(dexterity * 0.5)

var magic_power: int:
	get:
		return intelligence + int(strength * 0.3)

var defense: int:
	get:
		return resistance + int(strength * 0.2)

func get_defense_multiplier(attacking_element: Element = Element.NORMAL) -> float:
	# damage_taken = base_damage * (1.0 - (defense_value / (defense_value + 100)))
	var def_value = defensive_affinity.get(attacking_element, 0.0)
	return 1.0 - (def_value / (def_value + 100.0))

func get_attack_multiplier(target_element: Element = Element.NORMAL) -> float:
	# Returns multiplier based on offensive affinity against target element
	var off_value = offensive_affinity.get(target_element, 0.0)
	return 1.0 + (off_value / 100.0)

# Signals
signal health_changed(current: int, maximum: int)
signal died()
signal element_changed(new_element: Element)
signal leveled_up(new_level: int)
signal attacked(target)
signal mana_changed(current: int, maximum: int)

func _ready():
	update_visuals()

func take_damage(amount: int, element: Element = Element.NORMAL) -> void:
	var modified_damage = calculate_damage_with_element(amount, element)
	# Apply defense reduction
	modified_damage = max(1, modified_damage - defense)
	# Apply defensive affinity against this element
	modified_damage = int(modified_damage * get_defense_multiplier(element))
	modified_damage = max(1, modified_damage)  # Minimum 1 damage
	
	# Spawn damage text
	spawn_damage_text(modified_damage, element)
	
	current_hp = max(0, current_hp - modified_damage)
	health_changed.emit(current_hp, max_hp)
	
	if current_hp <= 0:
		die()

func calculate_damage_with_element(base_damage: int, attacker_element: Element) -> int:
	# Elemental damage modifiers (simplified)
	var modifier = 1.0
	
	# Example: Fire beats Earth, Water beats Fire, etc.
	if attacker_element == Element.FIRE and current_element == Element.EARTH:
		modifier = 1.5
	elif attacker_element == Element.WATER and current_element == Element.FIRE:
		modifier = 1.5
	elif attacker_element == Element.EARTH and current_element == Element.LIGHTNING:
		modifier = 1.5
	elif attacker_element == Element.LIGHTNING and current_element == Element.WATER:
		modifier = 1.5
	
	return int(base_damage * modifier)

func heal(amount: int) -> void:
	current_hp = min(max_hp, current_hp + amount)
	health_changed.emit(current_hp, max_hp)

func restore_mana(amount: int) -> void:
	current_mana = min(max_mana, current_mana + amount)
	mana_changed.emit(current_mana, max_mana)

func spend_mana(amount: int) -> bool:
	if current_mana >= amount:
		current_mana -= amount
		mana_changed.emit(current_mana, max_mana)
		return true
	return false

func change_element(new_element: Element) -> void:
	current_element = new_element
	element_changed.emit(new_element)
	update_visuals()

func level_up() -> void:
	level += 1
	
	# Stat increases vary by class
	match unit_class:
		UnitClass.WARRIOR:
			max_hp += 25
			strength += 3
			resistance += 2
		UnitClass.RANGER:
			max_hp += 15
			dexterity += 3
			strength += 2
		UnitClass.MONK:
			max_hp += 20
			strength += 2
			dexterity += 2
			resistance += 1
		UnitClass.THIEF:
			max_hp += 12
			dexterity += 4
			strength += 1
		UnitClass.BLACK_MAGE:
			max_hp += 10
			max_mana += 20
			intelligence += 4
		UnitClass.WHITE_MAGE:
			max_hp += 12
			max_mana += 18
			intelligence += 3
			resistance += 2
		UnitClass.RED_MAGE:
			max_hp += 15
			max_mana += 15
			intelligence += 2
			strength += 2
	
	current_hp = max_hp
	current_mana = max_mana
	leveled_up.emit(level)

func equip_weapon(weapon) -> void:
	equipped_weapon = weapon

func equip_armor(armor) -> void:
	equipped_armor = armor

func equip_accessory(accessory) -> void:
	equipped_accessory = accessory

func attack(target) -> void:
	if target and target.has_method("take_damage"):
		# Get target element for affinity calculation
		var target_element = target.current_element if target is UnitBase else Element.NORMAL
		var damage = int(attack_damage * get_attack_multiplier(target_element))
		
		# Ranged units use projectiles
		if attack_range > 1:
			spawn_projectile(target, damage)
		else:
			# Melee units apply damage immediately
			target.take_damage(damage, current_element)
		
		attacked.emit(target)

func spawn_projectile(target, damage: int) -> void:
	if not battle_manager:
		return
	
	var projectile = Projectile.new()
	var start_pos = global_position
	var end_pos = target.global_position if target else global_position
	
	projectile.setup(start_pos, end_pos, damage, current_element, target)
	
	# Add to scene tree through battle manager
	if battle_manager.has_method("add_projectile"):
		battle_manager.add_projectile(projectile)

func die() -> void:
	died.emit()
	queue_free()

func update_visuals() -> void:
	# Override in derived classes to update sprite/shape based on element
	pass

func get_element_color() -> Color:
	match current_element:
		Element.FIRE:
			return Color(1.0, 0.2, 0.0)  # Bright red-orange
		Element.WATER:
			return Color(0.0, 0.7, 1.0)  # Cyan/ice blue
		Element.EARTH:
			return Color(0.55, 0.35, 0.2)  # Brown
		Element.AIR:
			return Color(0.8, 1.0, 1.0)  # Light cyan/white
		Element.LIGHTNING:
			return Color(1.0, 1.0, 0.0)  # Yellow
		Element.NORMAL:
			return Color(0.6, 0.6, 0.6)  # Grey
		_:
			return Color(0.6, 0.6, 0.6)  # Grey default

func get_class_name_string() -> String:
	match unit_class:
		UnitClass.WARRIOR:
			return "Warrior"
		UnitClass.RANGER:
			return "Ranger"
		UnitClass.MONK:
			return "Monk"
		UnitClass.THIEF:
			return "Thief"
		UnitClass.BLACK_MAGE:
			return "Black Mage"
		UnitClass.WHITE_MAGE:
			return "White Mage"
		UnitClass.RED_MAGE:
			return "Red Mage"
		_:
			return "Unknown"

func get_element_name_string() -> String:
	match current_element:
		Element.FIRE:
			return "Fire"
		Element.WATER:
			return "Water"
		Element.EARTH:
			return "Earth"
		Element.AIR:
			return "Air"
		Element.LIGHTNING:
			return "Lightning"
		Element.NORMAL:
			return "Normal"
		_:
			return "Unknown"

func is_in_attack_range(target_pos: Vector2i) -> bool:
	var distance = grid_position.distance_to(target_pos)
	return distance <= attack_range

func get_distance_to(target_pos: Vector2i) -> float:
	return grid_position.distance_to(target_pos)

func spawn_damage_text(damage: int, element: Element) -> void:
	if not damage_text_container:
		return
	
	var damage_text = DamageText.new()
	# Spawn slightly above the unit
	var spawn_pos = global_position + Vector2(0, -20)
	damage_text.setup(damage, element, spawn_pos)
	damage_text_container.add_child(damage_text)
