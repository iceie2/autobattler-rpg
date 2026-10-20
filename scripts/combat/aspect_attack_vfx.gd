extends Node2D
class_name AspectAttackVFX

var color := Color.WHITE
var direction := Vector2.DOWN
var reach := 70.0
var cone := false
var remaining := 1.0
var label: Label
var manager = null

func setup(point: Vector2, element: int, life: float, is_cone: bool, facing: Vector2, radius: float) -> void:
	global_position = point
	color = SynergyData.element_color(element)
	remaining = life; cone = is_cone; direction = facing; reach = radius
	z_index = 6
	label = Label.new()
	label.text = "ASPECT BREATH" if cone else "ASPECT POUNCE"
	label.position = Vector2(-55, -45)
	label.add_theme_color_override("font_color", color)
	add_child(label)

func _process(dt: float) -> void:
	# Match battle pause and speed, including arena simulations.
	var m = manager if is_instance_valid(manager) else null
	if m and (not m.battle_active or m.paused): return
	remaining -= dt * (m.time_scale if m else 1.0)
	if remaining <= 0.0: queue_free()
	queue_redraw()

func _draw() -> void:
	if cone:
		var points := PackedVector2Array([Vector2.ZERO])
		for i in 19:
			points.append(Vector2.from_angle(direction.angle() - PI / 6.0 + PI / 3.0 * i / 18.0) * reach)
		draw_colored_polygon(points, Color(color, 0.22))
		draw_polyline(points, color, 3.0)
	else:
		draw_circle(Vector2.ZERO, reach, Color(color, 0.2))
		draw_arc(Vector2.ZERO, reach, 0, TAU, 48, color, 3.0)
