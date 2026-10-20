extends Node2D
class_name MawVFX
# The Drowned Maw's visual language: THE DEEP UNDER THE BOARD.
#
# Its body is a near-black teal anglerfish-toad with ONE light source -- the
# green lure on its head. So its water is the dark under the surface, and the
# only bright thing in any of its effects is that same lure-green. Deliberately
# not the Tidecaller's sapphire/foam (a reef warden) and not Nemi's bright wave.
#
# Abyssal Breach (owner design 2026-10-02), three one-shot modes:
#   STALK  -- while it is submerged: a dark body-sized shadow drifts under the
#             board with the glowing lure riding just above it, toward the hero
#             it is hunting. This IS the telegraph: you see where it will rise.
#   BREACH -- the 2x2 impact: murky water erupts, green glints thrown out.
#   PULSE  -- the follow-up shockwave across the 4x4: a dark ring with a lure-
#             green crest rolling out to the area's edge.

#   SPLASH -- where the body crosses the surface (going under, coming out):
#             rings spreading on the water + a ragged crown of dark spray.
#   BOIL   -- the half-second before it erupts: bubbles rising and popping over
#             the spot, the last "move NOW" tell.
enum Mode { STALK, BREACH, PULSE, SPLASH, BOIL }

const DEEP := Color(0.02, 0.06, 0.07)
const MURK := Color(0.07, 0.20, 0.20)
const LURE := Color(0.55, 1.0, 0.55)
# Surface foam: the one PALE colour, only where the body breaks the water --
# dark-on-dark spray was invisible on the water board (2026-10-02 capture).
const FOAM := Color(0.78, 0.92, 0.90)

var mode: Mode = Mode.STALK
var _from := Vector2.ZERO       # global
var _to := Vector2.ZERO         # global
var _size := 100.0              # px: shadow width (STALK), area half-width (BREACH/PULSE)
var _t := 0.0
var _life := 1.0
var _target = null              # STALK: the hero being hunted, followed live
var _aim_offset := Vector2.ZERO  # STALK: hero -> centre of the 2x2 it will rise through

func setup_stalk(from_world: Vector2, target, body_px: float, life: float,
		aim_offset: Vector2 = Vector2.ZERO) -> void:
	mode = Mode.STALK
	_from = from_world
	_target = target
	_aim_offset = aim_offset
	_to = target.global_position + aim_offset if target and is_instance_valid(target) else from_world
	_size = body_px
	_life = life
	z_index = 1                 # on the board, under every unit
	global_position = _from

func setup_burst(k: Mode, at_world: Vector2, half_px: float) -> void:
	mode = k
	_to = at_world
	_size = half_px
	_life = 0.55 if k == Mode.BREACH else 0.45
	z_index = 5
	global_position = at_world

func setup_surface(k: int, at_world: Vector2, size_px: float, life: float) -> void:
	mode = k
	_to = at_world
	_size = size_px
	_life = maxf(life, 0.2)
	z_index = 4
	global_position = at_world

## Where the shadow is right now -- the breach lands where the lure ends up.
func current_point() -> Vector2:
	return global_position

func _process(delta: float) -> void:
	_t += delta
	if mode == Mode.STALK:
		if _target and is_instance_valid(_target) and _target.current_hp > 0:
			_to = _target.global_position + _aim_offset
		var k: float = clampf(_t / _life, 0.0, 1.0)
		var e: float = k * k * (3.0 - 2.0 * k)
		global_position = _from.lerp(_to, e)
	if _t >= _life:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	match mode:
		Mode.STALK: _draw_stalk()
		Mode.BREACH: _draw_breach()
		Mode.PULSE: _draw_pulse()
		Mode.SPLASH: _draw_splash()
		Mode.BOIL: _draw_boil()

func _ellipse(c: Vector2, rx: float, ry: float, col: Color, n: int = 28) -> void:
	var pts := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)

func _ring(c: Vector2, rx: float, ry: float, col: Color, w: float, n: int = 36) -> void:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a: float = TAU * float(i) / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, w, true)

func _draw_stalk() -> void:
	var fade_in: float = clampf(_t / 0.25, 0.0, 1.0)
	var fade_out: float = clampf((_life - _t) / 0.15, 0.0, 1.0)
	var a: float = fade_in * fade_out
	var w: float = _size * 0.55
	var sway: float = sin(_t * 5.0) * 0.06
	# The body under the surface: layered soft ellipses so it reads as depth,
	# not as a flat decal.
	_ellipse(Vector2.ZERO, w * (1.15 + sway), w * 0.42, Color(DEEP.r, DEEP.g, DEEP.b, 0.22 * a))
	_ellipse(Vector2.ZERO, w * (0.95 + sway), w * 0.34, Color(DEEP.r, DEEP.g, DEEP.b, 0.30 * a))
	_ellipse(Vector2(0, -2), w * 0.70, w * 0.24, Color(MURK.r, MURK.g, MURK.b, 0.30 * a))
	# Wake ripples trailing behind the direction of travel.
	var dir: Vector2 = (_to - _from).normalized() if _to != _from else Vector2.DOWN
	for i in 3:
		var ph: float = fmod(_t * 1.6 + float(i) / 3.0, 1.0)
		var c: Vector2 = -dir * w * (0.5 + ph * 0.9)
		_ring(c, w * (0.3 + ph * 0.5), w * (0.12 + ph * 0.2),
				Color(LURE.r, LURE.g, LURE.b, 0.18 * (1.0 - ph) * a), 1.5)
	# The lure: the ONE light in the deep. Rides just ahead of the shadow and
	# bobs, with a soft glow and a bright core.
	var lp := dir * w * 0.55 + Vector2(0, -w * 0.18 + sin(_t * 6.0) * 3.0)
	var pulse: float = 0.75 + 0.25 * sin(_t * 9.0)
	draw_circle(lp, w * 0.30, Color(LURE.r, LURE.g, LURE.b, 0.10 * a * pulse))
	draw_circle(lp, w * 0.17, Color(LURE.r, LURE.g, LURE.b, 0.25 * a * pulse))
	draw_circle(lp, w * 0.08, Color(LURE.r, LURE.g, LURE.b, 0.95 * a))
	draw_circle(lp + Vector2(-1.5, -1.5), w * 0.03, Color(1, 1, 1, 0.9 * a))

func _draw_breach() -> void:
	var k: float = _t / _life
	var a: float = 1.0 - k * k
	var r: float = _size * (0.5 + 0.7 * sqrt(k))
	_ellipse(Vector2.ZERO, r * 1.1, r * 0.5, Color(DEEP.r, DEEP.g, DEEP.b, 0.45 * a))
	_ring(Vector2.ZERO, r * 1.1, r * 0.5, Color(MURK.r * 2.0, MURK.g * 2.0, MURK.b * 2.0, 0.8 * a), 4.0)
	# Thrown water: dark droplets arcing up and out, a few catching lure-green.
	for i in 14:
		var ang: float = TAU * float(i) / 14.0 + 0.3
		var out: float = _size * (0.4 + 1.0 * k)
		var lift: float = sin(clampf(k * 1.3, 0.0, 1.0) * PI) * _size * (0.6 + 0.3 * float(i % 3))
		var p := Vector2(cos(ang) * out, sin(ang) * out * 0.5 - lift)
		var col: Color = LURE if i % 4 == 0 else MURK * 1.8
		draw_circle(p, 3.5 * a + 1.0, Color(col.r, col.g, col.b, a))

func _draw_pulse() -> void:
	var k: float = _t / _life
	var a: float = 1.0 - k
	var e: float = 1.0 - pow(1.0 - k, 3.0)
	var rx: float = _size * (0.35 + 0.65 * e)
	_ring(Vector2.ZERO, rx, rx * 0.5, Color(DEEP.r, DEEP.g, DEEP.b, 0.55 * a), 9.0)
	_ring(Vector2.ZERO, rx, rx * 0.5, Color(LURE.r, LURE.g, LURE.b, 0.65 * a), 2.5)

func _draw_splash() -> void:
	var k: float = _t / _life
	var a: float = 1.0 - k
	var w: float = _size * 0.6
	# rings rolling out across the surface, staggered
	for i in 3:
		var ph: float = clampf(k * 1.4 - float(i) * 0.22, 0.0, 1.0)
		if ph <= 0.0:
			continue
		var r: float = w * (0.6 + 0.9 * ph)
		_ring(Vector2.ZERO, r, r * 0.42, Color(FOAM.r, FOAM.g, FOAM.b, 0.75 * (1.0 - ph)), 3.0)
	# a dark churned patch where the body breaks the surface
	_ellipse(Vector2.ZERO, w * 0.95, w * 0.38, Color(DEEP.r, DEEP.g, DEEP.b, 0.35 * a))
	# ragged crown of spray: drops thrown up and out, falling back
	for i in 18:
		var ang: float = TAU * float(i) / 18.0 + float(i % 3) * 0.2
		var sp: float = 0.6 + 0.4 * float((i * 7) % 5) / 4.0
		var kk: float = clampf(k * 1.6 * sp, 0.0, 1.0)
		var up: float = sin(kk * PI) * w * (0.7 + 0.5 * float(i % 4) / 3.0)
		var p := Vector2(cos(ang) * w * (0.55 + 0.6 * kk), sin(ang) * w * (0.55 + 0.6 * kk) * 0.42 - up)
		var col: Color = LURE if i % 6 == 0 else FOAM
		draw_circle(p, (4.5 - 2.0 * kk) + 1.0, Color(col.r, col.g, col.b, 0.95 * (1.0 - kk)))

func _draw_boil() -> void:
	var k: float = _t / _life
	var w: float = _size * 0.6
	_ellipse(Vector2.ZERO, w * (0.7 + 0.3 * k), w * (0.28 + 0.12 * k), Color(DEEP.r, DEEP.g, DEEP.b, 0.30 + 0.25 * k))
	# bubbles: each rises a little, swells, pops; more and faster as it nears
	for i in 16:
		var cyc: float = 0.18 + 0.12 * float(i % 4) / 3.0
		var ph: float = fmod(_t / cyc + float(i) * 0.37, 1.0)
		if float(i) / 16.0 > 0.35 + 0.65 * k:
			continue
		var ang: float = float(i) * 2.399
		var rr: float = w * 0.75 * sqrt(fmod(float(i) * 0.618, 1.0))
		var p := Vector2(cos(ang) * rr, sin(ang) * rr * 0.4 - ph * 6.0)
		var rad: float = 1.5 + 3.5 * ph
		draw_arc(p, rad, 0.0, TAU, 12, Color(0.6, 0.85, 0.8, 0.8 * (1.0 - ph)), 1.3)
	_ring(Vector2.ZERO, w * (0.6 + 0.15 * sin(_t * 30.0)), w * 0.25, Color(LURE.r, LURE.g, LURE.b, 0.25 * k), 1.5)
