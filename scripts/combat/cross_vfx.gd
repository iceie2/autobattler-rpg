extends Node2D
class_name CrossVFX
## Cross's holy light (2026-09-25). "just a happy lemur knight healing people":
## warm gold, soft and generous, never harsh. Replaces the shared HOLY_LIGHT burst
## (Reed and Vail used the same one) with two effects of his own.
##
##   BLESS     Absolution. A gold blessing leaves his raised mace, arcs to the
##             ally, and lands as a soft pillar of light: a ring, sparkles
##             spiralling up and a little gold cross popping over their head.
##             The heal lands on `land` (AutoBattleManager defers it to match).
##   JUDGMENT  Judgment. A thread of light finds the target from above while he
##             winds up, then a column of holy light SLAMS down on his mace
##             impact (`impact`), with a gold cross sigil burned into the ground,
##             rays, and sparks. A small ring marks where his mace hit.
##
## Two layers like BouncerInhaleVFX: ground marks at z 1 (over the grass, under
## units — JuneVFX.GROUND_Z), light at z 20 (over every unit). Battle clock:
## delta * time_scale, 0 while paused.

enum Mode { BLESS, JUDGMENT }

const GOLD := Color(1.0, 0.82, 0.36)
const WARM := Color(1.0, 0.93, 0.66)
const WHITE := Color(1.0, 0.99, 0.94)
const OUTLINE := Color(0.09, 0.07, 0.12)

var mode: Mode = Mode.BLESS
var caster: Node2D = null
var target: Node2D = null
var launch := 0.3          # BLESS: leaves the mace
var land := 0.6            # BLESS: reaches the ally
var impact := 0.79         # JUDGMENT: mace hits the ground
var end_time := 1.6

var _t := 0.0
var _from := Vector2.ZERO  # cached so a caster that dies mid-cast doesn't strand it
var _tgt := Vector2.ZERO
var _tgt_h := 60.0
var _mace_hit := Vector2.ZERO
var _ground: Node2D = null
var _seeds: Array = []

class _GroundLayer extends Node2D:
	var fx = null
	func _draw() -> void:
		if fx: fx._draw_ground(self)

func setup(p_mode: Mode, p_caster: Node2D, p_target: Node2D) -> void:
	mode = p_mode
	caster = p_caster
	target = p_target
	top_level = true
	z_as_relative = false
	z_index = 20
	global_position = Vector2.ZERO
	end_time = (land + 1.0) if mode == Mode.BLESS else (impact + 1.1)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 24:
		_seeds.append(rng.randf())
	_ground = _GroundLayer.new()
	_ground.fx = self
	_ground.top_level = true
	_ground.z_as_relative = false
	_ground.z_index = 1
	add_child(_ground)
	_track()

func _clock() -> float:
	var src: Node2D = caster if caster and is_instance_valid(caster) else target
	var bm = src.get("battle_manager") if src and is_instance_valid(src) else null
	if bm == null:
		return 1.0
	if bm.get("paused"):
		return 0.0
	return float(bm.get("time_scale")) if bm.get("time_scale") != null else 1.0

func _feet(u: Node2D) -> Vector2:
	var p: Vector2 = u.global_position
	if u.has_method("ground_offset"):
		p.y += float(u.ground_offset())
	return p

func _track() -> void:
	if caster and is_instance_valid(caster):
		var m = caster.get("model3d")
		if m:
			_from = m.bone_canvas_position("weapon_r") + (m.bone_canvas_position("head_end") - m.bone_canvas_position("Hips")) * 0.35
			_mace_hit = _feet(caster) + Vector2(0, -2)
		else:
			_from = caster.global_position + Vector2(0, -40)
			_mace_hit = _feet(caster)
	if target and is_instance_valid(target):
		_tgt = _feet(target)
		var hh = target.get("_sprite_half_h")
		_tgt_h = float(hh) * 2.0 if hh != null else 60.0

func _process(delta: float) -> void:
	_t += delta * _clock()
	if _t >= end_time:
		queue_free()
		return
	if _t < (land if mode == Mode.BLESS else impact):
		_track()             # follow them until the light arrives, then stay put
	queue_redraw()
	_ground.queue_redraw()

# ── helpers ─────────────────────────────────────────────────────────────────

func _glow(ci: CanvasItem, c: Vector2, r: float, col: Color, layers: int = 6) -> void:
	for i in range(layers, 0, -1):
		var f := float(i) / layers
		ci.draw_circle(c, r * f, Color(col, col.a * (1.0 - f) * 0.9))

func _ell(c: Vector2, r: Vector2, n: int = 44) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts

## soft vertical column: stacked quads, faint and wide -> bright and narrow,
## fading toward the top
func _pillar(ci: CanvasItem, base: Vector2, height: float, width: float, a: float) -> void:
	if a <= 0.01:
		return
	var layers := [[1.0, GOLD, 0.16], [0.62, GOLD, 0.26], [0.34, WARM, 0.45], [0.14, WHITE, 0.85]]
	for L in layers:
		var w: float = width * L[0]
		var col: Color = L[1]
		var la: float = L[2] * a
		var top := base + Vector2(0, -height)
		var pts := PackedVector2Array([base + Vector2(-w, 0), base + Vector2(w, 0), top + Vector2(w * 0.7, 0), top + Vector2(-w * 0.7, 0)])
		var cols := PackedColorArray([Color(col, la), Color(col, la), Color(col, 0.0), Color(col, 0.0)])
		ci.draw_polygon(pts, cols)

func _star(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	ci.draw_line(p + Vector2(-r, 0), p + Vector2(r, 0), col, maxf(1.0, r * 0.35), true)
	ci.draw_line(p + Vector2(0, -r * 1.3), p + Vector2(0, r * 1.3), col, maxf(1.0, r * 0.35), true)
	ci.draw_circle(p, r * 0.35, col)

## a latin cross (long foot), centred at p, `s` = half the arm span
func _cross_glyph(ci: CanvasItem, p: Vector2, s: float, col: Color, outline: bool) -> void:
	var w := s * 0.34
	var bars := [Rect2(p + Vector2(-w * 0.5, -s * 1.0), Vector2(w, s * 2.5)),
		Rect2(p + Vector2(-s, -s * 0.45), Vector2(s * 2.0, w))]
	if outline:
		for b in bars:
			ci.draw_rect(b.grow(maxf(1.5, s * 0.12)), Color(OUTLINE, col.a * 0.8))
	for b in bars:
		ci.draw_rect(b, col)

# ── ground layer ────────────────────────────────────────────────────────────

func _draw_ground(ci: CanvasItem) -> void:
	var foot := Vector2(_tgt_h * 0.55, _tgt_h * 0.20)       # ground ellipse per unit size
	if mode == Mode.BLESS:
		if _t < land:
			return
		var e := _t - land
		var p := clampf(e / 0.45, 0.0, 1.0)
		var a := 1.0 - clampf((e - 0.15) / 0.8, 0.0, 1.0)
		ci.draw_polyline(_ell(_tgt, foot * (0.5 + 0.9 * p)), Color(GOLD, 0.8 * (1.0 - p)), 3.0 + 3.0 * (1.0 - p), true)
		var pts := _ell(_tgt, foot * 0.9, 32); pts.remove_at(pts.size() - 1)
		ci.draw_colored_polygon(pts, Color(WARM, 0.22 * a))
	else:
		# the sigil: faint while the light searches, burned in on impact
		var pre := clampf((_t - (impact - 0.35)) / 0.35, 0.0, 1.0)
		var post := _t - impact
		var a := pre * 0.35 if post < 0.0 else 1.0 - clampf((post - 0.25) / 0.85, 0.0, 1.0)
		var big := foot * 1.35
		if a > 0.01:
			ci.draw_polyline(_ell(_tgt, big), Color(GOLD, 0.9 * a), 3.0, true)
			ci.draw_polyline(_ell(_tgt, big * 0.78), Color(WARM, 0.6 * a), 1.5, true)
			var pts := _ell(_tgt, big * 0.95, 32); pts.remove_at(pts.size() - 1)
			ci.draw_colored_polygon(pts, Color(GOLD, 0.16 * a))
			# cross laid flat on the ground (squashed to the board's perspective)
			ci.draw_set_transform(_tgt, 0.0, Vector2(1.0, big.y / big.x))
			_cross_glyph(ci, Vector2(0, big.x * 0.12), big.x * 0.42, Color(WARM, 0.9 * a), false)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# his own mace strike
		if post >= 0.0 and post < 0.5:
			var q := post / 0.5
			var mr := Vector2(_tgt_h * 0.5, _tgt_h * 0.18) * (0.3 + 1.0 * q)
			ci.draw_polyline(_ell(_mace_hit, mr), Color(OUTLINE, 0.35 * (1.0 - q)), 6.0, true)
			ci.draw_polyline(_ell(_mace_hit, mr), Color(GOLD, 0.9 * (1.0 - q)), 3.0, true)

# ── light layer ─────────────────────────────────────────────────────────────

func _draw() -> void:
	if mode == Mode.BLESS:
		_draw_bless()
	else:
		_draw_judgment()

func _arc_point(u: float) -> Vector2:
	var to := _tgt + Vector2(0, -_tgt_h * 0.55)
	var p := _from.lerp(to, u)
	var lift := maxf(40.0, _from.distance_to(to) * 0.35)
	return p + Vector2(0, -lift * 4.0 * u * (1.0 - u))

func _draw_bless() -> void:
	if _t < launch:
		return
	if _t < land:
		var u := clampf((_t - launch) / maxf(land - launch, 0.01), 0.0, 1.0)
		var ue := u * u * (3.0 - 2.0 * u)
		for i in range(10, 0, -1):            # trail of motes
			var uu := maxf(0.0, ue - i * 0.035)
			var a := (1.0 - float(i) / 10.0) * 0.8
			draw_circle(_arc_point(uu), 2.0 + 3.0 * (1.0 - float(i) / 10.0), Color(GOLD, a))
		var p := _arc_point(ue)
		_glow(self, p, 18.0, Color(GOLD, 0.9))
		draw_circle(p, 5.0, WHITE)
		return
	var e := _t - land
	var a := 1.0 - clampf((e - 0.2) / 0.75, 0.0, 1.0)
	# soft pillar on the ally
	var grow := clampf(e / 0.12, 0.0, 1.0)
	_pillar(self, _tgt, _tgt_h * 2.1 * (0.6 + 0.4 * grow), _tgt_h * 0.42, a)
	# landing flash
	if e < 0.2:
		_glow(self, _tgt + Vector2(0, -_tgt_h * 0.5), _tgt_h * (0.6 + e * 2.0), Color(WHITE, 0.9 * (1.0 - e / 0.2)))
	# sparkles spiralling up around them
	for i in 12:
		var s: float = _seeds[i]
		var ph := clampf(e * (0.9 + s * 0.6) - s * 0.15, 0.0, 1.0)
		if ph <= 0.0 or ph >= 1.0:
			continue
		var ang := TAU * (i / 12.0) + ph * 3.0
		var p := _tgt + Vector2(cos(ang) * _tgt_h * 0.42, sin(ang) * _tgt_h * 0.14 - ph * _tgt_h * 1.6)
		_star(self, p, 2.5 + 2.5 * (1.0 - ph), Color(WARM, (1.0 - ph) * a))
	# little gold cross popping over their head
	var pop := clampf(e / 0.18, 0.0, 1.0)
	var sc := (1.0 + 0.35 * sin(PI * pop)) * pop
	var ca := 1.0 - clampf((e - 0.45) / 0.45, 0.0, 1.0)
	if ca > 0.01 and sc > 0.01:
		var cp := _tgt + Vector2(0, -_tgt_h * 1.25 - e * 14.0)
		_glow(self, cp, _tgt_h * 0.28 * sc, Color(GOLD, 0.7 * ca))
		_cross_glyph(self, cp, _tgt_h * 0.12 * sc, Color(WARM, ca), true)

func _draw_judgment() -> void:
	var sky := _tgt + Vector2(0, -_tgt_h * 7.0)
	if _t < impact:
		# a thread of light finds the target from above and thickens
		var k := clampf((_t - (impact - 0.4)) / 0.4, 0.0, 1.0)
		if k <= 0.0:
			return
		var w := 1.5 + 4.0 * k * k
		draw_line(sky, _tgt, Color(GOLD, 0.25 * k), w * 3.0, true)
		draw_line(sky, _tgt, Color(WHITE, 0.7 * k), w, true)
		_glow(self, _tgt + Vector2(0, -_tgt_h * 0.4), _tgt_h * 0.4 * k, Color(GOLD, 0.6 * k))
		return
	var e := _t - impact
	# the column slams down: full width at once, then narrows and fades
	var a := 1.0 - clampf((e - 0.15) / 0.7, 0.0, 1.0)
	var width := _tgt_h * (0.95 - 0.45 * clampf(e / 0.5, 0.0, 1.0))
	_pillar(self, _tgt, _tgt_h * 7.0, width, a)
	draw_line(sky, _tgt, Color(WHITE, 0.9 * a), maxf(2.0, width * 0.10), true)
	# impact flash + rays at the ground
	if e < 0.25:
		var f := e / 0.25
		_glow(self, _tgt + Vector2(0, -_tgt_h * 0.4), _tgt_h * (1.0 + 1.6 * f), Color(WHITE, 1.0 - f), 8)
	var rays := clampf(1.0 - e / 0.45, 0.0, 1.0)
	if rays > 0.0:
		for i in 12:
			var ang := TAU * i / 12.0 + 0.13
			var dir := Vector2(cos(ang), sin(ang) * 0.4)
			var r0 := _tgt_h * 0.35
			var r1: float = _tgt_h * (0.9 + 0.8 * (1.0 - rays)) * (0.8 + 0.4 * float(_seeds[i]))
			draw_line(_tgt + dir * r0, _tgt + dir * r1, Color(WARM, 0.9 * rays), 2.5, true)
	# gold sparks thrown up, falling back
	for i in 16:
		var s: float = _seeds[i]
		var tt := e * (0.8 + 0.5 * s)
		if tt > 0.9:
			continue
		var ang: float = -PI * (0.15 + 0.7 * float(_seeds[(i + 5) % 24]))
		var v := Vector2(cos(ang), sin(ang)) * _tgt_h * (1.8 + 1.5 * s)
		var p := _tgt + v * tt + Vector2(0, _tgt_h * 3.2 * tt * tt)
		draw_circle(p, 2.0 + 2.0 * (1.0 - tt), Color(WARM, 1.0 - tt / 0.9))
