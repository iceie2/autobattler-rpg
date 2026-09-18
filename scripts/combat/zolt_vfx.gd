extends Node2D
class_name ZoltVFX

# Zolt owns celestial storm lightning: blue-white cores, royal-blue corona,
# charcoal cloud mass, and restrained gold accents.
enum Mode { AUTO_MUZZLE, AUTO_IMPACT, CHAIN, ULT_MARK, ULT_STRIKE, STUN_RESIDUE }

const CORE := Color(0.92, 0.98, 1.0)
const BLUE := Color(0.16, 0.48, 1.0)
const DEEP := Color(0.08, 0.16, 0.52)
const GOLD := Color(1.0, 0.76, 0.22)
const CLOUD := Color(0.075, 0.09, 0.16)

var mode: Mode = Mode.AUTO_IMPACT
var elapsed := 0.0
var lifetime := 0.5
var target: Node2D = null
var chain_targets: Array = []

func setup_point(kind: Mode, world_pos: Vector2, life: float = 0.5, follow: Node2D = null) -> void:
	mode = kind
	global_position = world_pos
	lifetime = life
	target = follow
	z_index = 7
	queue_redraw()

func setup_chain(nodes: Array, life: float = 0.55) -> void:
	mode = Mode.CHAIN
	chain_targets = nodes.duplicate()
	lifetime = life
	if not chain_targets.is_empty() and chain_targets[0] and is_instance_valid(chain_targets[0]):
		global_position = chain_targets[0].global_position
	z_index = 7
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if target and is_instance_valid(target): global_position = target.global_position
	if elapsed >= lifetime:
		queue_free()
		return
	queue_redraw()

func _fade() -> float:
	return clampf((lifetime - elapsed) / minf(lifetime, 0.3), 0.0, 1.0)

func _bolt(from: Vector2, to: Vector2, width: float, alpha: float, seed: float = 0.0) -> void:
	var dir := to - from
	var side := dir.normalized().orthogonal()
	var points := PackedVector2Array()
	for i in range(10):
		var t := float(i) / 9.0
		var jitter := sin(seed + float(i) * 8.71 + elapsed * 43.0) * 9.0 * sin(t * PI)
		points.append(from.lerp(to, t) + side * jitter)
	draw_polyline(points, Color(DEEP.r, DEEP.g, DEEP.b, alpha * 0.55), width * 3.4)
	draw_polyline(points, Color(BLUE.r, BLUE.g, BLUE.b, alpha), width * 1.8)
	draw_polyline(points, Color(CORE.r, CORE.g, CORE.b, alpha), width)

func _draw() -> void:
	match mode:
		Mode.AUTO_MUZZLE: _draw_auto_muzzle()
		Mode.AUTO_IMPACT: _draw_auto_impact()
		Mode.CHAIN: _draw_chain()
		Mode.ULT_MARK: _draw_ult_mark()
		Mode.ULT_STRIKE: _draw_ult_strike()
		Mode.STUN_RESIDUE: _draw_stun_residue()

func _draw_auto_muzzle() -> void:
	var a := _fade()
	var t := elapsed / lifetime
	for i in range(6):
		var ang := float(i) * TAU / 6.0 + elapsed * 9.0
		draw_line(Vector2.ZERO, Vector2.from_angle(ang) * (14.0 + 28.0 * t), Color(BLUE.r, BLUE.g, BLUE.b, a), 3.0)
	draw_circle(Vector2.ZERO, 12.0 * a, Color(BLUE.r, BLUE.g, BLUE.b, 0.35 * a))
	draw_circle(Vector2.ZERO, 4.0, CORE)

func _draw_auto_impact() -> void:
	var a := _fade()
	var t := elapsed / lifetime
	for i in range(8):
		var ang := float(i) * TAU / 8.0 + sin(float(i) * 3.1) * 0.18
		var dir := Vector2.from_angle(ang)
		draw_line(dir * (5.0 + 8.0 * t), dir * (22.0 + 42.0 * t), Color(BLUE.r, BLUE.g, BLUE.b, a), 4.0 * a)
	draw_arc(Vector2.ZERO, 48.0 * t, 0.0, TAU, 28, Color(GOLD.r, GOLD.g, GOLD.b, 0.75 * a), 4.0)
	draw_circle(Vector2.ZERO, 10.0 * a, CORE)

func _draw_chain() -> void:
	var valid: Array[Node2D] = []
	for node in chain_targets:
		if node and is_instance_valid(node): valid.append(node)
	if valid.size() < 2: return
	var reveal := clampf(elapsed / 0.18, 0.0, 1.0)
	var a := _fade()
	for i in range(valid.size() - 1):
		var local_reveal := clampf(reveal * float(valid.size() - 1) - float(i), 0.0, 1.0)
		if local_reveal <= 0.0: continue
		var from := to_local(valid[i].global_position)
		var destination := to_local(valid[i + 1].global_position)
		var to := from.lerp(destination, local_reveal)
		_bolt(from, to, 3.0, a, float(i) * 11.0)
		if local_reveal > 0.85: draw_circle(destination, 15.0 * a, Color(BLUE.r, BLUE.g, BLUE.b, 0.3 * a))

func _draw_ult_mark() -> void:
	var a := _fade()
	var charge := clampf(elapsed / lifetime, 0.0, 1.0)
	var r := 72.0 - charge * 25.0
	draw_circle(Vector2.ZERO, 46.0, Color(DEEP.r, DEEP.g, DEEP.b, 0.13 * a))
	draw_arc(Vector2.ZERO, r, -PI * 0.5, PI * 1.5, 40, Color(GOLD.r, GOLD.g, GOLD.b, 0.85 * a), 5.0)
	for i in range(4):
		var ang := elapsed * 4.0 + float(i) * TAU / 4.0
		draw_circle(Vector2.from_angle(ang) * r, 5.0, CORE)

func _draw_ult_strike() -> void:
	var a := _fade()
	var slam := clampf(elapsed / 0.13, 0.0, 1.0)
	for i in range(7):
		var x := (float(i) - 3.0) * 38.0
		draw_circle(Vector2(x, -410.0 + absf(x) * 0.1), 70.0, Color(CLOUD.r, CLOUD.g, CLOUD.b, 0.72 * a))
	_bolt(Vector2(0, -430), Vector2(0, -430).lerp(Vector2.ZERO, slam), 9.0, a, 4.0)
	if slam > 0.96:
		var shock := clampf((elapsed - 0.12) / 0.55, 0.0, 1.0)
		var ia := (1.0 - shock) * a
		draw_circle(Vector2.ZERO, 48.0 * ia, Color(CORE.r, CORE.g, CORE.b, 0.68 * ia))
		draw_arc(Vector2.ZERO, 28.0 + 105.0 * shock, 0.0, TAU, 48, Color(GOLD.r, GOLD.g, GOLD.b, ia), 7.0 * ia)
		for i in range(8):
			var ang := float(i) * TAU / 8.0 + sin(float(i) * 6.7) * 0.15
			_bolt(Vector2.ZERO, Vector2.from_angle(ang) * (52.0 + 88.0 * shock), 1.5, ia, float(i))

func _draw_stun_residue() -> void:
	var a := minf(1.0, elapsed / 0.1) * _fade()
	for i in range(6):
		var ang := elapsed * 5.5 + float(i) * TAU / 6.0
		var p := Vector2(cos(ang) * 36.0, -30.0 + sin(ang) * 14.0)
		draw_line(p - Vector2(5, 7), p + Vector2(5, 7), Color(BLUE.r, BLUE.g, BLUE.b, a), 3.0)
		draw_circle(p, 3.0, Color(GOLD.r, GOLD.g, GOLD.b, a))
