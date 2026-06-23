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
	RED_MAGE,
	BLOODHOUND,
	BOUNCER,
	HEADHUNTER,
	SHAUNA,
	NEMI
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

# XP / levelling
var current_xp: int = 0
var xp_to_level: int = 200

# Economy (set on enemy units; ignored for player units)
var gold_reward: int = 0
var crystal_reward: int = 0

# Multi-cell size (1 = normal 1×1, 2 = 2×2 boss)
var cell_size: int = 1

# ── Skill system (passive / active / ultimate) ────────────────────────────────
# Passive (always-on, evaluated each turn in AutoBattleManager)
var passive_name: String = ""

# Active (replaces old skill_ fields for new classes; old fields kept for legacy)
var skill_name: String = ""
var skill_damage_multiplier: float = 1.5
var skill_range: int = 2
var skill_cooldown_max: int = 4
var skill_cooldown: int = 0
var skill_mana_cost: int = 0      # 0 = free (legacy classes); >0 = costs mana

# Ultimate (charged by dealing and taking damage)
var ultimate_name: String = ""
var ultimate_damage_mult: float = 2.0
var ultimate_range: int = 3
var ultimate_charge: int = 0
var ultimate_charge_max: int = 300
var ultimate_ready: bool = false

# ── Combat state (per-unit tracking) ─────────────────────────────────────────
var damage_dealt: int = 0          # cumulative for damage meter
var stun_turns: int = 0            # skip action when > 0
var hit_counter: int = 0           # Headhunter: every-7th-crit / Shauna: every-3rd-true-dmg
var overdrive_turns: int = 0       # Shauna ultimate: extra attack per turn
var next_attack_boosted: bool = false  # Shauna active: next hit +50% DMG
var frenzy_active: bool = false    # Bloodhound passive
var rapid_fire_turns: int = 0      # Headhunter active duration remaining
var most_damage_dealer = null      # ref to unit that dealt most dmg to self
var damage_taken_from: Dictionary = {}   # unit → total damage dealt to self

# Battle state
var grid_position: Vector2i = Vector2i.ZERO
var target_unit = null
var is_player_unit: bool = true
var battle_manager = null
var damage_text_container: Node2D = null
var skill_effect_container: Node2D = null

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

func take_damage(amount: int, element: Element = Element.NORMAL, attacker = null, true_damage: bool = false) -> void:
	var modified_damage := calculate_damage_with_element(amount, element)
	if not true_damage:
		modified_damage = max(1, modified_damage - defense)
		modified_damage = int(modified_damage * get_defense_multiplier(element))
	modified_damage = max(1, modified_damage)
	
	# Spawn damage text
	spawn_damage_text(modified_damage, element)
	
	current_hp = max(0, current_hp - modified_damage)
	health_changed.emit(current_hp, max_hp)
	_charge_ultimate(modified_damage)
	# Track who dealt damage to us (for Bloodhound ultimate)
	if attacker != null:
		var prev: int = damage_taken_from.get(attacker, 0)
		damage_taken_from[attacker] = prev + modified_damage

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
	if not (target and target.has_method("take_damage")):
		return

	var target_element: Element = target.current_element if target is UnitBase else Element.NORMAL
	var damage := int(attack_damage * get_attack_multiplier(target_element))

	hit_counter += 1
	# Headhunter: every 7th hit = 3× crit
	if unit_class == UnitClass.HEADHUNTER and hit_counter % 7 == 0:
		damage = int(damage * 3.0)
	# Shauna: next attack boosted (+50%) from Kite active
	var is_boosted := next_attack_boosted
	if is_boosted:
		damage = int(damage * 1.5)
		next_attack_boosted = false
	# Shauna: every 3rd hit = true damage (bypass defence)
	var is_true_dmg := (unit_class == UnitClass.SHAUNA and hit_counter % 3 == 0)

	# Headhunter active bonus range already applied by battle manager

	if attack_range > 1:
		spawn_projectile(target, damage)
	else:
		var pre_hp: int = target.current_hp
		target.take_damage(damage, current_element, self, is_true_dmg)
		var actual: int = max(0, pre_hp - target.current_hp)
		damage_dealt += actual
		_charge_ultimate(actual / 2)

	attacked.emit(target)

func _charge_ultimate(amount: int) -> void:
	if ultimate_charge_max <= 0 or ultimate_ready:
		return
	ultimate_charge = min(ultimate_charge + amount, ultimate_charge_max)
	if ultimate_charge >= ultimate_charge_max:
		ultimate_ready = true

func grant_xp(amount: int) -> void:
	current_xp += amount
	while current_xp >= xp_to_level:
		current_xp -= xp_to_level
		xp_to_level = int(xp_to_level * 1.5)
		level_up()

func set_level(target_level: int) -> void:
	while level < target_level:
		level_up()

func spawn_projectile(target, damage: int) -> void:
	if not battle_manager:
		return

	var projectile := Projectile.new()
	var start_pos: Vector2 = global_position
	var end_pos:   Vector2 = target.global_position if target else global_position

	projectile.setup(start_pos, end_pos, damage, current_element, target)
	projectile.caster = self   # so on_reach_target can credit damage_dealt

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
		UnitClass.BLOODHOUND:
			return "Bloodhound"
		UnitClass.BOUNCER:
			return "Bouncer"
		UnitClass.HEADHUNTER:
			return "Headhunter"
		UnitClass.SHAUNA:
			return "Shauna"
		UnitClass.NEMI:
			return "Nemi"
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
