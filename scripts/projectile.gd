extends Node2D
class_name Projectile

var start_pos: Vector2
var target_pos: Vector2
var speed: float = 400.0
var damage: int = 0
var element: UnitBase.Element = UnitBase.Element.NORMAL
var target_unit = null
var caster = null          # tracks who fired this for damage_dealt attribution
var traveled_distance: float = 0.0
var total_distance: float = 0.0

# Visual
var projectile_size: float = 8.0
var projectile_color: Color = Color.WHITE

signal hit_target(target)

func _ready():
	if start_pos and target_pos:
		global_position = start_pos
		total_distance = start_pos.distance_to(target_pos)

func setup(from: Vector2, to: Vector2, dmg: int, elem: UnitBase.Element, target = null):
	start_pos = from
	target_pos = to
	damage = dmg
	element = elem
	target_unit = target
	# Don't set position here - wait until added to tree
	total_distance = from.distance_to(to)
	total_distance = from.distance_to(to)
	
	# Set color based on element
	projectile_color = get_element_color(elem)
	queue_redraw()

func _process(delta: float):
	if not start_pos or not target_pos:
		queue_free()
		return
	
	# Move towards target using global position
	var direction = (target_pos - global_position).normalized()
	var move_amount = speed * delta
	global_position += direction * move_amount
	traveled_distance += move_amount
	
	# Check if we've reached the target
	if traveled_distance >= total_distance or global_position.distance_to(target_pos) < 5.0:
		on_reach_target()

func on_reach_target():
	if target_unit and is_instance_valid(target_unit) and target_unit.has_method("take_damage"):
		var pre_hp: int = target_unit.current_hp
		target_unit.take_damage(damage, element)
		var actual: int = max(0, pre_hp - target_unit.current_hp)
		# Credit the damage back to whoever fired this projectile
		if caster and is_instance_valid(caster) and "damage_dealt" in caster:
			caster.damage_dealt += actual

	hit_target.emit(target_unit)
	queue_free()

func _draw():
	# Draw a simple circle projectile
	draw_circle(Vector2.ZERO, projectile_size, projectile_color)
	# Outline
	draw_arc(Vector2.ZERO, projectile_size, 0, TAU, 16, Color.WHITE, 1.5)

func get_element_color(elem: UnitBase.Element) -> Color:
	match elem:
		UnitBase.Element.FIRE:
			return Color(1.0, 0.3, 0.0)  # Orange-red
		UnitBase.Element.WATER:
			return Color(0.2, 0.5, 1.0)  # Blue
		UnitBase.Element.EARTH:
			return Color(0.6, 0.4, 0.2)  # Brown
		UnitBase.Element.AIR:
			return Color(0.8, 1.0, 1.0)  # Light cyan
		UnitBase.Element.LIGHTNING:
			return Color(1.0, 1.0, 0.3)  # Bright yellow
		UnitBase.Element.NORMAL:
			return Color(0.7, 0.7, 0.7)  # Grey
		_:
			return Color.WHITE
