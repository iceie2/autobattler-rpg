extends Node2D
class_name SheildorVFX

enum Mode { BASH_IMPACT, AURA_LINK, BULWARK_LINK, BARRIER, LEAP, HEAL_PULSE,
	LEAP_WARNING, LEAP_LAND }

const CORE := Color(1.0, 0.96, 0.72)
const GOLD := Color(1.0, 0.58, 0.08)
const STEEL := Color(0.38, 0.68, 0.92)
const BURGUNDY := Color(0.48, 0.08, 0.18)

var mode: Mode
var elapsed := 0.0
var lifetime := 0.6
var source: Node2D = null
var target: Node2D = null
var from_world := Vector2.ZERO
var to_world := Vector2.ZERO

func setup_point(kind: Mode, world_pos: Vector2, life: float, follow: Node2D = null) -> void:
	mode = kind
	global_position = world_pos
	lifetime = life
	target = follow
	z_index = 7

func setup_pair(kind: Mode, from: Node2D, to: Node2D, life: float) -> void:
	mode = kind
	source = from
	target = to
	lifetime = life
	global_position = from.global_position if from and is_instance_valid(from) else Vector2.ZERO
	z_index = 7

func setup_leap(start: Vector2, finish: Vector2, life: float = 0.72) -> void:
	mode = Mode.LEAP
	from_world = start
	to_world = finish
	global_position = start
	lifetime = life
	z_index = 6

func refresh() -> void:
	elapsed = 0.0
	lifetime = 9999.0
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if mode == Mode.BARRIER:
		if not (target and is_instance_valid(target)) or target.current_hp <= 0 or target.current_shield <= 0:
			queue_free(); return
		global_position = target.global_position
	elif mode in [Mode.AURA_LINK, Mode.BULWARK_LINK]:
		if not (source and is_instance_valid(source) and target and is_instance_valid(target)):
			queue_free(); return
		global_position = source.global_position
	elif target and is_instance_valid(target):
		global_position = target.global_position
	if elapsed >= lifetime:
		queue_free(); return
	queue_redraw()

func _fade() -> float:
	return clampf((lifetime - elapsed) / minf(lifetime, 0.28), 0.0, 1.0)

func _shield_plate(center: Vector2, scale: float, alpha: float,
		yaw: float = 0.0, tilt: float = 0.0) -> void:
	# Project a flat plate at a simulated 3D yaw. The changing width, shear and
	# vertical squash make the orbit read as shields facing different directions
	# rather than five identical UI icons circling on one plane.
	var facing := cos(yaw)
	var width := maxf(0.18, absf(facing))
	var shear := sin(yaw) * 10.0
	var height := 1.0 - absf(tilt) * 0.22
	var raw := PackedVector2Array([
		Vector2(-22, -28), Vector2(22, -28), Vector2(27, 5),
		Vector2(0, 34), Vector2(-27, 5)])
	var pts := PackedVector2Array()
	for p in raw:
		var projected := Vector2(p.x * width + (p.y / 34.0) * shear, p.y * height)
		pts.append(center + projected * scale)
	draw_colored_polygon(pts, Color(STEEL.r, STEEL.g, STEEL.b, 0.13 * alpha))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[0]]),
		Color(GOLD.r, GOLD.g, GOLD.b, alpha), 4.0 * scale)
	var top := center + Vector2(-19.0 / 34.0 * shear, -19.0 * height) * scale
	var bottom := center + Vector2(20.0 / 34.0 * shear, 20.0 * height) * scale
	draw_line(top, bottom, CORE, 3.0 * scale)
	var cross_y := -2.0 * height
	draw_line(center + Vector2(-13.0 * width + cross_y / 34.0 * shear, cross_y) * scale,
		center + Vector2(13.0 * width + cross_y / 34.0 * shear, cross_y) * scale,
		CORE, 3.0 * scale)

func _draw() -> void:
	match mode:
		Mode.BASH_IMPACT: _draw_bash()
		Mode.AURA_LINK, Mode.BULWARK_LINK: _draw_link()
		Mode.BARRIER: _draw_barrier()
		Mode.LEAP: _draw_leap()
		Mode.HEAL_PULSE: _draw_heal()
		Mode.LEAP_WARNING: _draw_leap_warning()
		Mode.LEAP_LAND: _draw_leap_land()

func _draw_bash() -> void:
	var t := elapsed / lifetime
	var a := _fade()
	# Single-target contact: keep the complete silhouette inside roughly one
	# battlefield cell so it never reads as an AoE.
	_shield_plate(Vector2.ZERO, 0.48 + 0.12 * (1.0 - t), a)
	draw_circle(Vector2.ZERO, 12.0 + 12.0 * t,
		Color(CORE.r, CORE.g, CORE.b, 0.16 * a))
	draw_arc(Vector2.ZERO, 20.0 + 14.0 * t, 0.0, TAU, 28,
		Color(STEEL.r, STEEL.g, STEEL.b, 0.9 * a), 5.0 * a)
	for i in range(8):
		var ang := float(i) * TAU / 8.0
		var p := Vector2.from_angle(ang) * (26.0 + 14.0 * t)
		draw_line(p * 0.62, p, Color(GOLD.r, GOLD.g, GOLD.b, a), 2.5)

func _draw_link() -> void:
	var end := to_local(target.global_position)
	var grow := clampf(elapsed / 0.18, 0.0, 1.0)
	var a := _fade()
	var dir := end.normalized()
	var side := dir.orthogonal()
	var pts := PackedVector2Array()
	for i in range(13):
		var f := float(i) / 12.0
		pts.append(end * grow * f + side * sin(f * PI * 3.0 + elapsed * 10.0) * 4.0)
	draw_polyline(pts, Color(STEEL.r, STEEL.g, STEEL.b, 0.32 * a), 11.0)
	draw_polyline(pts, Color(GOLD.r, GOLD.g, GOLD.b, 0.9 * a), 4.0)
	var packet := end * clampf(elapsed / 0.32, 0.0, 1.0)
	_shield_plate(packet, 0.28, a)

func _draw_barrier() -> void:
	var intro := clampf(elapsed / 0.26, 0.0, 1.0)
	var pulse := 0.96 + sin(elapsed * 7.0) * 0.04
	var base_a := intro * (0.82 + sin(elapsed * 4.0) * 0.06)
	# A fast elliptical orbit sells an active bodyguard ward. Each plate turns
	# tangent to the orbit, producing edge-on, three-quarter and face-on views.
	for i in range(6):
		var ang := elapsed * 3.75 + float(i) * TAU / 6.0
		var depth := sin(ang)
		var p := Vector2(cos(ang) * 42.0, -8.0 + depth * 24.0) * pulse
		var depth_a := lerpf(0.45, 1.0, (depth + 1.0) * 0.5)
		var depth_scale := lerpf(0.29, 0.42, (depth + 1.0) * 0.5)
		_shield_plate(p, depth_scale, base_a * depth_a, ang + PI * 0.5, depth)

func _draw_leap() -> void:
	var delta := to_world - from_world
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	var a := _fade()
	var dir := delta.normalized()
	var side := dir.orthogonal()
	for i in range(5):
		var lane := (float(i) - 2.0) * 7.0
		var end := delta * minf(1.0, t * 1.8) + side * lane
		draw_line(side * lane, end, Color(GOLD.r, GOLD.g, GOLD.b, (0.2 + i * 0.12) * a), 4.0)
	if t > 0.35:
		var local_end := delta
		_shield_plate(local_end, 0.8 + 0.2 * (1.0 - t), a)
		draw_arc(local_end, 35.0 + 90.0 * t, 0, TAU, 38, Color(STEEL.r, STEEL.g, STEEL.b, 0.75 * a), 8.0 * a)

func _draw_leap_warning() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	var a := _fade()
	var radius := lerpf(34.0, 19.0, t)
	draw_arc(Vector2(0, 8), radius, 0.0, TAU, 28,
		Color(GOLD.r, GOLD.g, GOLD.b, 0.9 * a), 4.0)
	for i in range(4):
		var dir := Vector2.from_angle(float(i) * PI * 0.5)
		draw_line(dir * (radius + 9.0), dir * radius,
			Color(CORE.r, CORE.g, CORE.b, a), 4.0)

func _draw_leap_land() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	var a := _fade()
	var center := Vector2(0, 12)
	draw_circle(center, 18.0 + 24.0 * t, Color(GOLD.r, GOLD.g, GOLD.b, 0.12 * a))
	draw_arc(center, 20.0 + 42.0 * t, PI, TAU, 28,
		Color(STEEL.r, STEEL.g, STEEL.b, 0.8 * a), 6.0 * a)
	for i in range(5):
		var x := (float(i) - 2.0) * 13.0
		draw_line(center + Vector2(x * 0.55, 0), center + Vector2(x, 12.0 + 18.0 * t),
			Color(GOLD.r, GOLD.g, GOLD.b, a), 3.0)

func _draw_heal() -> void:
	var t := elapsed / lifetime
	var a := _fade()
	draw_arc(Vector2.ZERO, 12.0 + 48.0 * t, 0, TAU, 30, Color(0.55, 1.0, 0.62, 0.8 * a), 5.0)
	for i in range(4):
		var p := Vector2((float(i) - 1.5) * 11.0, 18.0 - 45.0 * t - absf(float(i) - 1.5) * 5.0)
		draw_circle(p, 4.0 * a, Color(CORE.r, CORE.g, CORE.b, a))
