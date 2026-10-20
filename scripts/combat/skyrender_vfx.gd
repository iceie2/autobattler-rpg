extends Node2D
class_name SkyrenderVFX

# Skyrender's Air flavour (wave-20 boss, owner 2026-10-04 -- "a cool concept
# but no flavor"). Palette is the v002 body's: slate feathers, silver edges,
# pale-cyan glow, on dark under-strokes so it survives the bright sky board.
#
#   WIND       persistent, a CHILD of the boss: wind streaks orbiting the body,
#              gentle when grounded, a fast gale while aloft.
#   GUST       take-off / landing: a flattened ring and streaks blown outward.
#   FEATHERS   a hit landing on it: feathers knocked loose, flutter down.
#   DIVE_MARK  Storm Dive telegraph: the landing area darkens under a growing
#              shadow, wind spiralling in toward the centre.
#   DOWNDRAFT  a wingbeat while aloft: wind lines slamming DOWN into the area.
#   IMPACT     Storm Dive landing: the crash ring, dust and a burst of feathers.

enum Mode { WIND, GUST, FEATHERS, DIVE_MARK, DOWNDRAFT, IMPACT }

const OUTLINE := Color(0.06, 0.07, 0.10)
const WIND := Color(0.82, 0.95, 1.0)
const GLOW := Color(0.55, 0.92, 1.0)
const SLATE := Color(0.30, 0.36, 0.46)
const SILVER := Color(0.85, 0.89, 0.93)
const SHADOW := Color(0.04, 0.05, 0.10)
const DUST := Color(0.85, 0.85, 0.80)

var mode: Mode = Mode.GUST
var _t := 0.0
var _life := 0.5
var _host = null
var _r := 80.0
var _poly := PackedVector2Array()
var _bits: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = int(get_instance_id()) & 0x7fffffff

func setup_wind(unit, r: float) -> void:
	mode = Mode.WIND
	_host = unit
	_life = INF
	_r = r
	z_index = 1
	position = Vector2(0, -r * 0.55)
	for i in 5:
		_bits.append([_rng.randf() * TAU, _rng.randf_range(0.8, 1.25), _rng.randf_range(-0.3, 0.3)])

func setup_burst(m: Mode, at: Vector2, r: float, life: float) -> void:
	mode = m
	_life = life
	_r = r
	z_index = 6
	global_position = at
	var n: int = 9 if m == Mode.FEATHERS else (14 if m == Mode.IMPACT else 10)
	for i in n:
		_bits.append([_rng.randf() * TAU, _rng.randf_range(0.5, 1.0), _rng.randf_range(-1.0, 1.0)])

# DIVE_MARK / DOWNDRAFT: an area given as a world-space polygon.
func setup_area(m: Mode, poly_global: PackedVector2Array, life: float) -> void:
	mode = m
	_life = life
	z_index = 1 if m == Mode.DIVE_MARK else 6
	var c := Vector2.ZERO
	for p in poly_global: c += p
	c /= maxf(poly_global.size(), 1)
	global_position = c
	_poly = PackedVector2Array()
	for p in poly_global:
		_poly.append(p - c)
		_r = maxf(_r, (p - c).length())
	for i in 12:
		_bits.append([_rng.randf() * TAU, _rng.randf_range(0.2, 1.0), _rng.randf()])

func _process(delta: float) -> void:
	_t += delta
	if mode == Mode.WIND:
		if not (_host and is_instance_valid(_host)) or _host.current_hp <= 0:
			queue_free(); return
	elif _t >= _life:
		queue_free(); return
	queue_redraw()

func _draw() -> void:
	var k: float = clampf(_t / maxf(_life, 0.001), 0.0, 1.0)
	match mode:
		Mode.WIND: _draw_wind()
		Mode.GUST: _draw_gust(k)
		Mode.FEATHERS: _draw_feathers(k, false)
		Mode.DIVE_MARK: _draw_dive_mark(k)
		Mode.DOWNDRAFT: _draw_downdraft(k)
		Mode.IMPACT:
			_draw_gust(k)
			_draw_feathers(k, true)

func _streak(c: Vector2, rx: float, ry: float, a0: float, span: float, w: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 9:
		var a: float = a0 + span * float(i) / 8.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, Color(OUTLINE, col.a * 0.5), w + 2.0, true)
	draw_polyline(pts, col, w, true)

func _draw_wind() -> void:
	var aloft: bool = bool(_host.get_meta("skyrender_aloft", false))
	var speed: float = 3.2 if aloft else 1.1
	var alpha: float = 0.75 if aloft else 0.35
	# Follows the body when it's lifted (aloft) or swooping.
	if _host.has_method("body_visual_offset"):
		position = Vector2(0, -_r * 0.55) + _host.body_visual_offset()
	for b in _bits:
		var a0: float = float(b[0]) + _t * speed * float(b[1])
		var rx: float = _r * float(b[1])
		var ry: float = rx * 0.38
		var col := WIND
		col.a = alpha * (0.6 + 0.4 * sin(_t * 2.0 + float(b[0])))
		_streak(Vector2(0, float(b[2]) * _r * 0.5), rx, ry, a0, 1.1, 2.5 if aloft else 1.8, col)

func _draw_gust(k: float) -> void:
	var fade: float = 1.0 - k
	var rr: float = _r * (0.4 + 1.2 * k)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.36))
	draw_arc(Vector2.ZERO, rr, 0, TAU, 40, Color(OUTLINE, 0.5 * fade), 7.0)
	draw_arc(Vector2.ZERO, rr, 0, TAU, 40, Color(WIND, 0.9 * fade), 4.0)
	draw_arc(Vector2.ZERO, rr * 0.75, 0, TAU, 40, Color(GLOW, 0.6 * fade), 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for b in _bits:
		var d := Vector2(cos(float(b[0])), sin(float(b[0])) * 0.36)
		var p0: Vector2 = d * rr * 0.7
		var p1: Vector2 = d * (rr * 0.7 + 30.0 * float(b[1]))
		draw_line(p0, p1, Color(OUTLINE, 0.4 * fade), 5.0)
		draw_line(p0, p1, Color(WIND, 0.85 * fade), 2.5)

func _feather(c: Vector2, ang: float, len: float, a: float) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d.y, d.x)
	var pts := PackedVector2Array([c - d * len * 0.5, c + n * len * 0.18, c + d * len * 0.5, c - n * len * 0.18])
	draw_colored_polygon(pts, Color(OUTLINE, a))
	var inner := PackedVector2Array()
	for p in pts: inner.append(c + (p - c) * 0.78)
	draw_colored_polygon(inner, Color(SLATE, a))
	draw_line(c - d * len * 0.45, c + d * len * 0.45, Color(SILVER, a), 1.5)
	draw_circle(c + d * len * 0.42, len * 0.08, Color(GLOW, a))

func _draw_feathers(k: float, big: bool) -> void:
	var fade: float = 1.0 if k < 0.6 else (1.0 - k) / 0.4
	for b in _bits:
		var dirv := Vector2(cos(float(b[0])), sin(float(b[0])) * 0.6)
		var out: float = (_r * (1.3 if big else 0.9)) * float(b[1]) * (1.0 - pow(1.0 - k, 2.0))
		# Flutter: drift down and rock side to side after the burst.
		var p: Vector2 = dirv * out + Vector2(sin(_t * 9.0 + float(b[2]) * 4.0) * 6.0, 40.0 * k * k)
		var ang: float = float(b[0]) + sin(_t * 7.0 + float(b[2]) * 3.0) * 0.9
		_feather(p, ang, (22.0 if big else 15.0) * float(b[1]) + 6.0, fade)

func _draw_dive_mark(k: float) -> void:
	if _poly.size() < 4:
		return
	var pulse: float = 0.5 + 0.5 * sin(_t * lerpf(6.0, 20.0, k))
	draw_colored_polygon(_poly, Color(SHADOW, 0.18 + 0.30 * k + 0.08 * pulse))
	var closed := _poly.duplicate()
	closed.append(_poly[0])
	draw_polyline(closed, Color(OUTLINE, 0.7), 7.0)
	draw_polyline(closed, Color(GLOW, 0.55 + 0.45 * k), 3.5)
	# The diving body's shadow, swelling as it falls.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, _r * (0.25 + 0.5 * k), Color(SHADOW, 0.25 + 0.45 * k))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Wind spiralling in toward the centre.
	for b in _bits:
		var a0: float = float(b[0]) - _t * 3.0
		var rr: float = _r * (1.0 - fposmod(float(b[2]) + _t * 0.6, 1.0)) * 0.9
		_streak(Vector2.ZERO, rr, rr * 0.42, a0, 0.9, 2.0, Color(WIND, 0.6 * (0.4 + 0.6 * k)))

func _draw_downdraft(k: float) -> void:
	if _poly.size() < 4:
		return
	var fade: float = 1.0 - k
	draw_colored_polygon(_poly, Color(GLOW, 0.14 * fade))
	var closed := _poly.duplicate()
	closed.append(_poly[0])
	draw_polyline(closed, Color(WIND, 0.7 * fade), 2.5)
	# Lines of air slamming down from above into the area.
	for b in _bits:
		var x: float = (float(b[2]) * 2.0 - 1.0) * _r * 0.75
		var drop: float = lerpf(-160.0, 0.0, clampf(k * 1.6 * float(b[1]) + 0.2, 0.0, 1.0))
		var p0 := Vector2(x, drop - 60.0)
		var p1 := Vector2(x, drop)
		draw_line(p0, p1, Color(OUTLINE, 0.4 * fade), 5.0)
		draw_line(p0, p1, Color(WIND, 0.9 * fade), 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.36))
	draw_arc(Vector2.ZERO, _r * (0.3 + 0.8 * k), 0, TAU, 36, Color(WIND, 0.8 * fade), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
