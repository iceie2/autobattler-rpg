extends Node2D
class_name HillGiantVFX

enum Mode { SMASH_WARNING, SMASH_IMPACT, AUTO_IMPACT }

var mode := Mode.AUTO_IMPACT
var elapsed := 0.0
var lifetime := 0.5
var caster_unit = null
var footprint_size := 440.0
var footprint_points := PackedVector2Array()

func setup_warning(caster, size: float, life: float) -> void:
	mode = Mode.SMASH_WARNING
	caster_unit = caster
	footprint_size = size
	lifetime = life
	z_index = 0
	queue_redraw()

func setup_point(kind: Mode, world_pos: Vector2, size: float, life: float) -> void:
	mode = kind
	global_position = world_pos
	footprint_size = size
	lifetime = life
	z_index = 4
	queue_redraw()

func set_footprint_polygon(points: PackedVector2Array) -> void:
	footprint_points = points
	queue_redraw()

func _footprint() -> PackedVector2Array:
	if not footprint_points.is_empty():
		return footprint_points
	var half := footprint_size * 0.5
	return PackedVector2Array([Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])

func _process(delta: float) -> void:
	elapsed += delta
	if mode == Mode.SMASH_WARNING:
		if not (caster_unit and is_instance_valid(caster_unit)):
			queue_free(); return
		global_position = caster_unit.global_position
	if elapsed >= lifetime: queue_free()
	else: queue_redraw()

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	var fade := 1.0 - t
	var earth := Color(0.48, 0.26, 0.08)
	var ochre := Color(0.91, 0.61, 0.18)
	if mode == Mode.SMASH_WARNING:
		var points := _footprint()
		# Strong compression beat: broad low-alpha ground pressure, an opaque
		# gameplay edge, then inward rings that accelerate toward contact.
		draw_colored_polygon(points, Color(earth.r, earth.g, earth.b, 0.075 + t * 0.095))
		draw_polyline(PackedVector2Array(Array(points) + [points[0]]),
			Color(ochre.r, ochre.g, ochre.b, 0.48 + t * 0.47), 4.0 + t * 3.0)
		var half := footprint_size * 0.5
		for ring_i in range(3):
			var ring_t := fposmod(t * 1.7 + float(ring_i) / 3.0, 1.0)
			var rr := half * (0.92 - ring_t * 0.68)
			draw_arc(Vector2.ZERO, rr, 0.0, TAU, 48,
				Color(ochre.r, ochre.g, ochre.b, (0.12 + 0.34 * t) * ring_t), 3.0)
		for i in range(4):
			var a := float(i) * TAU / 4.0 + PI * 0.25
			var end := Vector2(cos(a), sin(a)) * half * (0.35 + t * 0.5)
			draw_line(Vector2.ZERO, end, Color(ochre.r, ochre.g, ochre.b, 0.35 + t * 0.55), 4.0)
		draw_circle(Vector2.ZERO, 28.0 + 28.0 * t, Color(earth.r, earth.g, earth.b, 0.22 + t * 0.18))
		draw_circle(Vector2.ZERO, 9.0 + 8.0 * t, Color(1.0, 0.88, 0.46, 0.55 + t * 0.40))
	elif mode == Mode.SMASH_IMPACT:
		var points := _footprint()
		draw_colored_polygon(points, Color(earth.r, earth.g, earth.b, 0.15 * fade))
		draw_polyline(PackedVector2Array(Array(points) + [points[0]]),
			Color(ochre.r, ochre.g, ochre.b, 0.78 * fade), 6.0)
		# Two shock rings separate the actual contact from the cracked-earth residue.
		for ring_i in range(2):
			var ring_t := clampf(t * 1.35 - float(ring_i) * 0.16, 0.0, 1.0)
			draw_arc(Vector2.ZERO, footprint_size * (0.07 + 0.40 * ring_t), 0.0, TAU, 56,
				Color(1.0, 0.70, 0.22, (1.0 - ring_t) * 0.70), 8.0 * (1.0 - ring_t) + 2.0)
		for i in range(20):
			var a := float(i) * TAU / 20.0 + 0.17
			var dist := footprint_size * (0.10 + 0.40 * t)
			var p := Vector2(cos(a), sin(a)) * dist
			draw_line(p * 0.22, p, Color(0.24, 0.10, 0.025, 0.88 * fade), 7.0 * fade)
			draw_circle(p, (5.0 + float(i % 3) * 2.0) * fade,
				Color(ochre.r, ochre.g, ochre.b, 0.90 * fade))
		draw_circle(Vector2.ZERO, 86.0 * fade, Color(earth.r, earth.g, earth.b, 0.30 * fade))
		draw_circle(Vector2.ZERO, 34.0 * fade, Color(ochre.r, ochre.g, ochre.b, 0.48 * fade))
		draw_circle(Vector2.ZERO, 18.0 * fade, Color(1.0, 0.94, 0.64, fade))
	else:
		for ring_i in range(2):
			var ring_t := clampf(t * 1.5 - float(ring_i) * 0.20, 0.0, 1.0)
			draw_arc(Vector2.ZERO, 18.0 + 55.0 * ring_t, 0.0, TAU, 32,
				Color(ochre.r, ochre.g, ochre.b, (1.0 - ring_t) * 0.62), 6.0)
		for i in range(12):
			var a := float(i) * TAU / 12.0
			var p := Vector2(cos(a), sin(a)) * (16.0 + 48.0 * t)
			draw_line(Vector2.ZERO, p, Color(earth.r, earth.g, earth.b, 0.88 * fade), 7.0 * fade)
			draw_circle(p, 4.5 * fade, Color(ochre.r, ochre.g, ochre.b, 0.90 * fade))
		draw_circle(Vector2.ZERO, 34.0 + 28.0 * t, Color(earth.r, earth.g, earth.b, 0.22 * fade))
		draw_circle(Vector2.ZERO, 16.0 * fade, Color(ochre.r, ochre.g, ochre.b, 0.72 * fade))
		draw_circle(Vector2.ZERO, 7.0 * fade, Color(1.0, 0.94, 0.66, fade))
