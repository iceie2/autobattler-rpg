extends Node2D
class_name GoblinArcherVFX

var elapsed := 0.0
var lifetime := 0.48
var crippling := false

func setup(world_pos: Vector2, is_crippling: bool) -> void:
	global_position = world_pos
	crippling = is_crippling
	z_index = 4
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= lifetime: queue_free()
	else: queue_redraw()

func _draw() -> void:
	var t := elapsed / lifetime
	var a := 1.0 - t
	var body := Color(0.67, 0.27, 0.08) if not crippling else Color(0.34, 0.72, 0.10)
	var core := Color(1.0, 0.88, 0.40) if not crippling else Color(0.88, 1.0, 0.52)
	draw_circle(Vector2.ZERO, 18.0 + 22.0 * t, Color(body.r, body.g, body.b, 0.12 * a))
	for i in range(7):
		var ang := float(i) * TAU / 7.0 + 0.3
		var tip := Vector2(cos(ang), sin(ang)) * (10.0 + 30.0 * t)
		draw_line(Vector2.ZERO, tip, Color(body.r, body.g, body.b, 0.78 * a), 3.0 * a)
	draw_circle(Vector2.ZERO, 9.0 * a, Color(core.r, core.g, core.b, 0.32 * a))
	draw_circle(Vector2.ZERO, 3.5 * a, Color(core.r, core.g, core.b, a))
	if crippling:
		draw_arc(Vector2(0, 14), 22.0 + 8.0 * t, 0.0, TAU, 24,
			Color(0.52, 0.92, 0.18, 0.65 * a), 3.0)
