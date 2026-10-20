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
	if source and is_instance_valid(source) and source.has_method("_battle_clock"):
		delta *= source._battle_clock()
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

static func element_colors(elem: UnitBase.Element) -> Array[Color]:
	match elem:
		UnitBase.Element.WATER: return [Color(0.08, 0.48, 0.75), Color(0.52, 0.94, 1.0)]
		UnitBase.Element.EARTH: return [Color(0.30, 0.58, 0.18), Color(0.80, 1.0, 0.42)]
		UnitBase.Element.AIR: return [Color(0.42, 0.76, 0.64), Color(0.90, 1.0, 0.84)]
		UnitBase.Element.LIGHTNING: return [Color(0.35, 0.28, 0.88), Color(0.92, 0.88, 1.0)]
		UnitBase.Element.NORMAL: return [Color(0.48, 0.66, 0.22), Color(0.92, 1.0, 0.56)]
		_: return [Color(0.80, 0.20, 0.04), Color(1.0, 0.82, 0.22)]

# Elemental shape language supplements the palette; healing keeps its shared
# link/ring so every form still reads as the same support ability.
func _element_mark(pos: Vector2, size: float, color: Color, phase: float) -> void:
	match element:
		UnitBase.Element.FIRE:
			var sway := sin(phase * 3.0 + elapsed * 14.0) * size * 0.3
			var flame := PackedVector2Array([pos + Vector2(-size * 0.6, size * 0.4), pos + Vector2(-size * 0.7, -size * 0.2), pos + Vector2(-size * 0.25, -size * 0.8), pos + Vector2(sway, -size * 1.7), pos + Vector2(size * 0.55, -size * 0.55), pos + Vector2(size * 0.65, size * 0.2), pos + Vector2(0, size * 0.6)])
			draw_colored_polygon(flame, Color(1.0, 0.32, 0.04, color.a))
			draw_colored_polygon(PackedVector2Array([pos + Vector2(-size * 0.3, size * 0.3), pos + Vector2(sway * 0.5, -size * 0.8), pos + Vector2(size * 0.3, size * 0.3)]), color)
		UnitBase.Element.WATER:
			# Hollow bubbles with a highlight; rise separately from the ribbon.
			var bubble := pos + Vector2(sin(phase + elapsed * 7.0) * 2.0, -fmod(elapsed * 24.0 + phase * 2.0, 9.0))
			draw_circle(bubble, size * 0.7, Color(color.r, color.g, color.b, color.a * 0.12))
			draw_arc(bubble, size * 0.7, 0.0, TAU, 16, color, 1.4, true)
			draw_arc(bubble + Vector2(-size * 0.08, -size * 0.08), size * 0.42, PI, PI * 1.5, 6, Color(0.9, 1.0, 1.0, color.a), 1.5, true)
		UnitBase.Element.EARTH:
			var rock := PackedVector2Array([pos + Vector2(-size * 0.65, -size * 0.15), pos + Vector2(-size * 0.25, -size * 0.7), pos + Vector2(size * 0.55, -size * 0.4), pos + Vector2(size * 0.65, size * 0.3), pos + Vector2(-size * 0.2, size * 0.65)])
			draw_colored_polygon(rock, Color(0.65, 0.48, 0.22, color.a))
			draw_line(rock[1], rock[2], Color(1.0, 0.83, 0.46, color.a), 1.5, true)
		UnitBase.Element.AIR:
			var turn := phase + elapsed * 6.0
			draw_arc(pos, size * 0.85, turn, turn + PI * 1.4, 12, color, 1.5, true)
			draw_arc(pos + Vector2(size * 0.6, -size * 0.3), size * 0.5, turn + PI, turn + PI * 2.3, 10, Color(color.r, color.g, color.b, color.a * 0.5), 1.0, true)
		UnitBase.Element.LIGHTNING:
			draw_polyline(PackedVector2Array([pos + Vector2(-size * 0.3, -size), pos + Vector2(size * 0.4, -size * 0.1), pos + Vector2(-size * 0.4, size * 0.1), pos + Vector2(size * 0.3, size)]), color, 2.0, true)
		_:
			draw_line(pos - Vector2(size, 0), pos + Vector2(size, 0), color, 1.5, true)
			draw_line(pos - Vector2(0, size), pos + Vector2(0, size), color, 1.5, true)

func _draw() -> void:
	var colors := element_colors(element)
	var body: Color = colors[0]
	var core: Color = colors[1]
	if mode == Mode.AURA:
		var pulse := 0.5 + 0.5 * sin(elapsed * TAU * 0.8)
		draw_circle(Vector2.ZERO, radius, Color(body.r, body.g, body.b, 0.025 + pulse * 0.012))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(body.r, body.g, body.b, 0.16), 2.0)
		for i in range(8):
			var a := float(i) * TAU / 8.0 + elapsed * 0.35
			var p := Vector2(cos(a), sin(a)) * (30.0 + pulse * 5.0)
			_element_mark(p, 5.0, Color(core.r, core.g, core.b, 0.5), a)
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
		for i in range(5):
			var f := float(i + 1) / 6.0
			var accent_size := 4.5 if element == UnitBase.Element.NORMAL else 7.0
			var accent_pos := head * f + side * sin(f * PI * 3.0 + elapsed * 20.0) * 12.0
			_element_mark(accent_pos, accent_size, Color(core.r, core.g, core.b, 0.8), float(i) * 1.7 + elapsed * 3.0)
	else:
		var t := clampf(elapsed / lifetime, 0.0, 1.0)
		var fade := 1.0 - t
		draw_circle(Vector2.ZERO, 14.0 + 30.0 * t, Color(body.r, body.g, body.b, 0.14 * fade))
		draw_arc(Vector2.ZERO, 10.0 + 26.0 * t, 0.0, TAU, 28, Color(core.r, core.g, core.b, 0.72 * fade), 3.0)
		draw_circle(Vector2.ZERO, 5.0 * fade, Color(1.0, 1.0, 0.84, fade))
		for i in range(6):
			var angle := TAU * float(i) / 6.0 + elapsed
			_element_mark(Vector2(cos(angle), sin(angle)) * (12.0 + t * 30.0), 7.0 * fade, Color(core.r, core.g, core.b, fade), angle)
