extends Node2D
class_name KhaganKitVFX

# Khagan's kit (wave-10 boss, owner 2026-10-03). The dismount beat and the
# phase-3 possession have their own files; this is everything the kit DOES:
#
#   LANE      Sidestep Charge telegraph — the band of rows the crab is about to
#             sweep, lit across the board toward the edge it will run to, with
#             chevrons streaming in that direction. Grows bolder as it fills.
#   DASH      the sweep itself — a foam-and-sand wake along the path it ran.
#   GAZE      Dread Gaze — a violet stare from the rider's eye to a hero.
#   INK_SHOT  Ink Cloud in flight — a black-violet glob lobbed in an arc.
#   INK_POOL  the 3×3 puddle it bursts into; lingers for the blind.
#   ARMS      Eight Arms — a tentacle lash from the octopus to an extra victim.
#
# Palette: crab-shell orange for the mount, sea teal + violet ink for the rider.

# (The rider gripping the crab is in the model itself: khagan_phase1_v002.glb.)

enum Mode { LANE, DASH, GAZE, INK_SHOT, INK_POOL, ARMS }

const OUTLINE := Color(0.06, 0.05, 0.08)
const SHELL := Color(1.0, 0.52, 0.22)
const SHELL_LIT := Color(1.0, 0.82, 0.50)
const FOAM := Color(0.86, 0.95, 0.98)
const SAND := Color(0.82, 0.72, 0.52)
const DREAD := Color(0.70, 0.30, 1.0)
const DREAD_CORE := Color(1.0, 0.88, 0.40)
const INK := Color(0.10, 0.07, 0.18)
const INK_SHEEN := Color(0.45, 0.32, 0.75)
const TEAL := Color(0.30, 0.75, 0.72)

var mode: Mode = Mode.LANE
var _t := 0.0
var _life := 0.5
var _poly := PackedVector2Array()   # LANE / INK_POOL, local to this node
var _dir := 1.0                     # LANE: +1 sweeps right/down, -1 left/up
var _vertical := false              # LANE: charging up/down the board
var _from := Vector2.ZERO           # global
var _to := Vector2.ZERO             # global
var _host = null                    # GAZE / ARMS: follows the caster
var _victim = null
var _r := 60.0
var _blobs: Array = []              # INK_POOL / DASH scatter, rolled once
var _rng := RandomNumberGenerator.new()
var hold := false                   # LANE: stay lit past _life until the owner frees it

func _ready() -> void:
	_rng.seed = int(get_instance_id()) & 0x7fffffff

# `poly_global` is the band in world space; stored relative to `anchor`.
# `dir` is the grid direction of the charge: (±1,0) sideways, (0,±1) up/down the board.
func setup_lane(anchor: Vector2, poly_global: PackedVector2Array, dir: Vector2i, life: float) -> void:
	mode = Mode.LANE
	_life = life
	_vertical = dir.y != 0
	_dir = float(dir.y if _vertical else dir.x)
	z_index = 1
	global_position = anchor
	_poly = PackedVector2Array()
	for p in poly_global: _poly.append(p - anchor)

func setup_dash(from_world: Vector2, to_world: Vector2, r: float) -> void:
	mode = Mode.DASH
	_life = 1.0
	_r = r
	z_index = 1
	global_position = Vector2.ZERO
	_from = from_world; _to = to_world
	for i in 18:
		_blobs.append([_rng.randf(), _rng.randf_range(-1.0, 1.0), _rng.randf_range(0.5, 1.0)])

func setup_gaze(caster, victim, life: float) -> void:
	mode = Mode.GAZE
	_life = life
	_host = caster; _victim = victim
	_r = MirrorVFX.body_r(caster)
	z_index = 7
	global_position = Vector2.ZERO

func setup_ink_shot(from_world: Vector2, to_world: Vector2, flight: float) -> void:
	mode = Mode.INK_SHOT
	_life = flight
	z_index = 7
	global_position = Vector2.ZERO
	_from = from_world; _to = to_world

func setup_ink_pool(anchor: Vector2, poly_global: PackedVector2Array, life: float) -> void:
	mode = Mode.INK_POOL
	_life = life
	z_index = 1
	global_position = anchor
	_poly = PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly_global:
		var q: Vector2 = p - anchor
		_poly.append(q)
		lo = lo.min(q); hi = hi.max(q)
	for i in 14:
		_blobs.append([Vector2(_rng.randf_range(lo.x, hi.x), _rng.randf_range(lo.y, hi.y)),
			_rng.randf_range(10.0, 26.0), _rng.randf()])

func setup_arms(caster, victim) -> void:
	mode = Mode.ARMS
	_life = 0.32
	_host = caster; _victim = victim
	z_index = 7
	global_position = Vector2.ZERO
	_r = _rng.randf_range(-1.0, 1.0)   # which way the lash curls

func _process(delta: float) -> void:
	_t += delta
	if _t >= _life and not hold:
		queue_free(); return
	queue_redraw()

func _draw() -> void:
	var k: float = clampf(_t / maxf(_life, 0.001), 0.0, 1.0)
	match mode:
		Mode.LANE: _draw_lane(k)
		Mode.DASH: _draw_dash(k)
		Mode.GAZE: _draw_gaze(k)
		Mode.INK_SHOT: _draw_ink_shot(k)
		Mode.INK_POOL: _draw_ink_pool(k)
		Mode.ARMS: _draw_arms(k)

func _draw_lane(k: float) -> void:
	if _poly.size() < 4:
		return
	# Pulse quickens as the windup fills — a ticking "it's coming".
	var pulse: float = 0.5 + 0.5 * sin(_t * lerpf(6.0, 22.0, k))
	var fill := SHELL
	fill.a = 0.16 + 0.26 * k + 0.10 * pulse
	draw_colored_polygon(_poly, fill)
	var edge := SHELL_LIT
	edge.a = 0.7 + 0.3 * k
	var closed := _poly.duplicate()
	closed.append(_poly[0])
	draw_polyline(closed, OUTLINE, 8.0)
	draw_polyline(closed, edge, 4.5)
	# Chevrons streaming toward the edge it will run to.
	var top_l: Vector2 = _poly[0]; var top_r: Vector2 = _poly[1]
	var bot_r: Vector2 = _poly[2]; var bot_l: Vector2 = _poly[3]
	# Chevrons stream along the charge axis; `h` is the band's width across it.
	var h: float = ((bot_l.y - top_l.y) + (bot_r.y - top_r.y)) * 0.5
	if _vertical:
		h = ((top_r.x - top_l.x) + (bot_r.x - bot_l.x)) * 0.5
	for i in 5:
		var f: float = fposmod(float(i) / 5.0 + _t * 0.45, 1.0)
		if _dir < 0.0: f = 1.0 - f
		var mid: Vector2
		if _vertical:
			mid = (top_l.lerp(bot_l, f) + top_r.lerp(bot_r, f)) * 0.5
		else:
			mid = (top_l.lerp(top_r, f) + bot_l.lerp(bot_r, f)) * 0.5
		var w: float = h * 0.26 * _dir
		var a: float = (0.55 + 0.45 * k) * sin(f * PI)
		var c := SHELL_LIT; c.a = a
		var pts := PackedVector2Array([mid + Vector2(-w, -h * 0.34), mid + Vector2(w * 0.7, 0),
			mid + Vector2(-w, h * 0.34)])
		if _vertical:
			pts = PackedVector2Array([mid + Vector2(-h * 0.34, -w), mid + Vector2(0, w * 0.7),
				mid + Vector2(h * 0.34, -w)])
		draw_polyline(pts, Color(OUTLINE, a), 12.0)
		draw_polyline(pts, c, 7.0)

func _draw_dash(k: float) -> void:
	var fade: float = 1.0 - k
	var d: Vector2 = _to - _from
	var n := Vector2(-d.y, d.x).normalized()
	# Wake: two foam lines either side of the path, peeling outward.
	for side in [-1.0, 1.0]:
		var off: Vector2 = n * side * _r * (0.55 + 0.4 * k)
		var c := FOAM; c.a = 0.75 * fade
		draw_line(_from + off, _to + off, Color(OUTLINE, 0.5 * fade), 6.0)
		draw_line(_from + off, _to + off, c, 3.0)
	for b in _blobs:
		var p: Vector2 = _from.lerp(_to, float(b[0])) + n * float(b[1]) * _r * 0.5 \
			+ Vector2(0, -24.0 * k * float(b[2]))
		var c := SAND; c.a = 0.8 * fade
		draw_circle(p, 9.0 * float(b[2]) * (1.0 + k), c)

func _eye_pos() -> Vector2:
	if _host and is_instance_valid(_host):
		return _host.global_position + Vector2(0, -_r * 1.15)
	return _from

func _draw_gaze(k: float) -> void:
	if not (_victim and is_instance_valid(_victim)):
		return
	var eye: Vector2 = _eye_pos()
	var tar: Vector2 = _victim.global_position + Vector2(0, -30)
	var a: float = sin(k * PI)
	# Beam: wide violet haze, then a thin hot core.
	draw_line(eye, tar, Color(DREAD, 0.25 * a), 18.0)
	draw_line(eye, tar, Color(DREAD, 0.7 * a), 6.0)
	draw_line(eye, tar, Color(DREAD_CORE, 0.9 * a), 2.0)
	# The eye opening on the rider.
	var open: float = clampf(k * 3.0, 0.0, 1.0)
	draw_circle(eye, 16.0, Color(OUTLINE, 0.8 * a))
	draw_circle(eye, 13.0, Color(DREAD, a))
	draw_rect(Rect2(eye + Vector2(-2.5, -9.0 * open), Vector2(5.0, 18.0 * open)), Color(DREAD_CORE, a))
	# Ring closing on the victim.
	var rr: float = lerpf(60.0, 24.0, k)
	draw_arc(tar, rr, 0, TAU, 28, Color(OUTLINE, 0.6 * a), 5.0)
	draw_arc(tar, rr, 0, TAU, 28, Color(DREAD, a), 2.5)

func _draw_ink_shot(k: float) -> void:
	var p: Vector2 = _from.lerp(_to, k) + Vector2(0, -sin(k * PI) * 140.0)
	# Shadow on the ground.
	draw_circle(_from.lerp(_to, k), 12.0, Color(0, 0, 0, 0.25))
	# Trail of droplets.
	for i in 5:
		var kk: float = maxf(0.0, k - 0.05 * float(i + 1))
		var q: Vector2 = _from.lerp(_to, kk) + Vector2(0, -sin(kk * PI) * 140.0)
		draw_circle(q, 9.0 - float(i) * 1.4, Color(INK, 0.8 - 0.14 * float(i)))
	draw_circle(p, 18.0, OUTLINE)
	draw_circle(p, 15.0, INK)
	draw_circle(p + Vector2(-5, -5), 5.0, INK_SHEEN)

func _draw_ink_pool(k: float) -> void:
	if _poly.size() < 4:
		return
	# Splash in fast, sit, then dry out over the last third.
	var a: float = clampf(_t / 0.15, 0.0, 1.0) * (1.0 if k < 0.66 else (1.0 - k) / 0.34)
	draw_colored_polygon(_poly, Color(INK, 0.45 * a))
	var closed := _poly.duplicate()
	closed.append(_poly[0])
	draw_polyline(closed, Color(INK_SHEEN, 0.7 * a), 2.5)
	for b in _blobs:
		var c: Vector2 = b[0]
		var rad: float = float(b[1]) * (0.8 + 0.2 * sin(_t * 3.0 + float(b[2]) * 6.0))
		draw_circle(c, rad, Color(INK, 0.75 * a))
		draw_circle(c + Vector2(-rad * 0.3, -rad * 0.3), rad * 0.25, Color(INK_SHEEN, 0.6 * a))

func _draw_arms(k: float) -> void:
	if not (_host and is_instance_valid(_host) and _victim and is_instance_valid(_victim)):
		return
	var a: Vector2 = _host.global_position + Vector2(0, -20)
	var b: Vector2 = _victim.global_position + Vector2(0, -24)
	var d: Vector2 = b - a
	var n := Vector2(-d.y, d.x).normalized() * _r
	var reach: float = clampf(k * 2.2, 0.0, 1.0)
	var fade: float = 1.0 if k < 0.6 else (1.0 - k) / 0.4
	var pts := PackedVector2Array()
	var steps := 12
	for i in steps + 1:
		var f: float = float(i) / float(steps) * reach
		pts.append(a + d * f + n * sin(f * PI) * d.length() * 0.28)
	draw_polyline(pts, Color(OUTLINE, fade), 11.0)
	draw_polyline(pts, Color(TEAL, fade), 7.0)
	# Suckers along the lash.
	for i in range(2, pts.size() - 1, 2):
		draw_circle(pts[i], 2.4, Color(FOAM, 0.85 * fade))
	if reach >= 1.0:
		draw_arc(b, 22.0 * (1.0 + k), 0, TAU, 20, Color(TEAL, fade * 0.8), 3.0)
