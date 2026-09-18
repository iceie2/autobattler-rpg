extends Node2D
class_name GoblinShamanVFX

enum Mode { AURA, MEND_LINK, AUTO_IMPACT }

var mode := Mode.AUTO_IMPACT
var elapsed := 0.0
var lifetime := 0.45
var source = null
var target = null
var element := UnitBase.Element.FIRE
var radius := 345.0 # Three 115 px cells: the passive's real gameplay radius.

func setup_aura(owner, elem: UnitBase.Element, world_radius: float = 345.0) -> void:
	mode = Mode.AURA
	source = owner
	element = elem
	radius = world_radius
	z_index = 0
	queue_redraw()

func setup_mend(owner, recipient, elem: UnitBase.Element, life: float = 0.42) -> void:
	mode = Mode.MEND_LINK
	source = owner
	target = recipient
	element = elem
	lifetime = life
	z_index = 5
	queue_redraw()

func setup_impact(world_pos: Vector2, elem: UnitBase.Element, life: float = 0.42) -> void:
	mode = Mode.AUTO_IMPACT
	global_position = world_pos
	element = elem
	lifetime = life
	z_index = 4
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if mode == Mode.AURA:
		if not (source and is_instance_valid(source)):
			queue_free(); return
		global_position = source.global_position
		queue_redraw()
		return
	if mode == Mode.MEND_LINK:
		if not (source and is_instance_valid(source) and target and is_instance_valid(target)):
			queue_free(); return
		global_position = source.global_position
	if elapsed >= lifetime: queue_free()
	else: queue_redraw()

func _colors() -> Array[Color]:
	match element:
		UnitBase.Element.WATER: return [Color(0.08, 0.48, 0.75), Color(0.52, 0.94, 1.0)]
		UnitBase.Element.EARTH: return [Color(0.30, 0.58, 0.18), Color(0.80, 1.0, 0.42)]
		UnitBase.Element.AIR: return [Color(0.42, 0.76, 0.64), Color(0.90, 1.0, 0.84)]
		UnitBase.Element.LIGHTNING: return [Color(0.35, 0.28, 0.88), Color(0.92, 0.88, 1.0)]
		UnitBase.Element.NORMAL: return [Color(0.48, 0.66, 0.22), Color(0.92, 1.0, 0.56)]
		_: return [Color(0.80, 0.20, 0.04), Color(1.0, 0.82, 0.22)]

func _draw() -> void:
	var colors := _colors()
	var body: Color = colors[0]
	var core: Color = colors[1]
	if mode == Mode.AURA:
		var pulse := 0.5 + 0.5 * sin(elapsed * TAU * 0.8)
		draw_circle(Vector2.ZERO, radius, Color(body.r, body.g, body.b, 0.025 + pulse * 0.012))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(body.r, body.g, body.b, 0.16), 2.0)
		for i in range(8):
			var a := float(i) * TAU / 8.0 + elapsed * 0.35
			var p := Vector2(cos(a), sin(a)) * (30.0 + pulse * 5.0)
			draw_circle(p, 3.0, Color(core.r, core.g, core.b, 0.34))
		draw_circle(Vector2.ZERO, 30.0 + pulse * 5.0, Color(body.r, body.g, body.b, 0.07))
	elif mode == Mode.MEND_LINK:
		var t := clampf(elapsed / lifetime, 0.0, 1.0)
		var end: Vector2 = target.global_position - global_position
		var head: Vector2 = end * t
		var side: Vector2 = end.normalized().orthogonal()
		var points := PackedVector2Array()
		for i in range(13):
			var f := float(i) / 12.0
			points.append(head * f + side * sin(f * PI * 3.0 + elapsed * 20.0) * 5.0)
		draw_polyline(points, Color(body.r, body.g, body.b, 0.20), 12.0)
		draw_polyline(points, Color(core.r, core.g, core.b, 0.88), 5.0)
		draw_polyline(points, Color(1.0, 1.0, 0.82, 0.95), 1.8)
		draw_circle(head, 10.0, Color(body.r, body.g, body.b, 0.22))
		draw_circle(head, 4.0, core)
	else:
		var t := clampf(elapsed / lifetime, 0.0, 1.0)
		var fade := 1.0 - t
		draw_circle(Vector2.ZERO, 14.0 + 30.0 * t, Color(body.r, body.g, body.b, 0.14 * fade))
		draw_arc(Vector2.ZERO, 10.0 + 26.0 * t, 0.0, TAU, 28, Color(core.r, core.g, core.b, 0.72 * fade), 3.0)
		draw_circle(Vector2.ZERO, 5.0 * fade, Color(1.0, 1.0, 0.84, fade))
