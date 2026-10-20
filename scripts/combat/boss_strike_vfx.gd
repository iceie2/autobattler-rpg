extends Node2D
class_name BossStrikeVFX

# Boss SIGNATURE strikes (2026-09-28). Every Warrior-class boss used to cast the
# Warrior hero's Whirlwind — an area hit behind a single-target tooltip, drawn as
# the generic WHIRLWIND puff. The owner ruled signatures must do what their
# tooltips say (AutoBattleManager.BOSS_SIGNATURES), and each now draws its OWN
# strike in its body's palette, one distinct SHAPE per boss:
#   SHELL_SLAM  Khagan        — a shell-shaped shock ring slammed onto the target
#   CLEAVE      Triarch       — one broad steel crescent through the target
#   BITE        Drowned Maw   — glass-tooth jaws snapping shut, green lure flash
#   FAULT       Cloven Titan  — a glowing crack splitting the ground boss→target
#   BACKDRAFT   Emberhollow   — a furnace cone, white-hot core (VALUE, not orange)
#   SPIT        Ember Heart   — an ember lobbed in an arc
#   SUNDER      Arcfang       — yellow slit-lines (its eyes) closing like jaws
#   SWEEP       Gravekeeper   — a spade arc round the body + a green toll ring
#   CORNERSTONE Architect     — a square gold-glyph shockwave (area slam)

enum Style { SHELL_SLAM, CLEAVE, BITE, FAULT, BACKDRAFT, SPIT, SUNDER, SWEEP, CORNERSTONE }

const INK := Color(0.05, 0.05, 0.07)

var style: Style = Style.CLEAVE
var _from := Vector2.ZERO           # caster, global
var _targets: Array = []            # victim positions, global
var r := 80.0                       # caster body radius
var _t := 0.0
var _life := 0.45

func setup(s: Style, caster, target_positions: Array) -> void:
	style = s
	_from = caster.global_position
	_targets = target_positions
	r = MirrorVFX.body_r(caster)
	z_index = 6
	_life = 0.55 if s in [Style.SWEEP, Style.CORNERSTONE, Style.FAULT] else 0.42
	global_position = Vector2.ZERO
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	var k: float = _t / _life
	var from: Vector2 = to_local(_from)
	match style:
		Style.SWEEP:       _sweep(from, k); return
		Style.CORNERSTONE: _cornerstone(from, k); return
	for tp in _targets:
		var to: Vector2 = to_local(tp) + Vector2(0, -26)
		match style:
			Style.SHELL_SLAM: _shell_slam(to, k)
			Style.CLEAVE:     _cleave(from, to, k)
			Style.BITE:       _bite(to, k)
			Style.FAULT:      _fault(from, to, k)
			Style.BACKDRAFT:  _backdraft(from, to, k)
			Style.SPIT:       _spit(from, to, k)
			Style.SUNDER:     _sunder(to, k)

func _c(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

func _shell_slam(to: Vector2, k: float) -> void:
	var SHELL := Color(0.45, 0.62, 0.72)
	var FOAM := Color(0.92, 0.98, 1.0)
	var a: float = 1.0 - k
	draw_set_transform(to + Vector2(0, 24), 0.0, Vector2(1.0, 0.45))
	for i in 2:
		var rr: float = 24.0 + 60.0 * k + float(i) * 14.0
		draw_arc(Vector2.ZERO, rr, 0, TAU, 40, _c(INK, 0.6 * a), 9.0)
		draw_arc(Vector2.ZERO, rr, 0, TAU, 40, _c(SHELL if i == 0 else FOAM, a), 4.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Hex plates of the shell stamped on the victim.
	for i in 6:
		var ang: float = TAU * float(i) / 6.0
		var p: Vector2 = to + Vector2(cos(ang), sin(ang)) * 16.0
		draw_circle(p, 6.0 * a + 1.0, _c(SHELL, a))

func _cleave(from: Vector2, to: Vector2, k: float) -> void:
	var STEEL := Color(0.86, 0.90, 0.96)
	var a: float = 1.0 - k * k
	var facing: float = (to - from).angle()
	var sweep: float = minf(1.0, k / 0.35)
	var start: float = facing - 1.3
	var span: float = 2.6 * sweep
	draw_arc(to, 40.0, start, start + span, 24, _c(INK, 0.8 * a), 16.0)
	draw_arc(to, 40.0, start, start + span, 24, _c(STEEL, a), 9.0)
	draw_arc(to, 40.0, start, start + span, 24, _c(Color.WHITE, a), 3.0)

func _bite(to: Vector2, k: float) -> void:
	var TOOTH := Color(0.90, 0.93, 0.82)
	var LURE := Color(0.55, 1.0, 0.35)
	var gum := Color(0.10, 0.25, 0.28)
	var close: float = minf(1.0, k / 0.3)
	var a: float = 1.0 - clampf((k - 0.5) / 0.5, 0.0, 1.0)
	draw_circle(to, 30.0 * (0.6 + 0.6 * k), _c(LURE, 0.25 * (1.0 - k)))
	for side in [-1.0, 1.0]:
		var jaw_y: float = side * (26.0 * (1.0 - close) + 4.0)
		draw_rect(Rect2(to + Vector2(-34, jaw_y - (6.0 if side < 0 else 0.0)), Vector2(68, 6)), _c(gum, a))
		for i in 6:
			var x: float = -28.0 + float(i) * 11.2
			var base: Vector2 = to + Vector2(x, jaw_y)
			var tip: Vector2 = base + Vector2(0, -side * 13.0)
			var tri := PackedVector2Array([base + Vector2(-5, 0), base + Vector2(5, 0), tip])
			draw_colored_polygon(tri, _c(INK, a))
			draw_colored_polygon(PackedVector2Array([base + Vector2(-3.5, 0), base + Vector2(3.5, 0), tip.lerp(base, 0.15)]), _c(TOOTH, a))

func _fault(from: Vector2, to: Vector2, k: float) -> void:
	var SEAM := Color(1.0, 0.62, 0.18)
	var HOT := Color(1.0, 0.92, 0.70)
	var grow: float = minf(1.0, k / 0.3)
	var a: float = 1.0 - clampf((k - 0.55) / 0.45, 0.0, 1.0)
	var g0: Vector2 = from + Vector2(0, r * 0.6)
	var g1: Vector2 = to + Vector2(0, 30)
	var d: Vector2 = g1 - g0
	var n: Vector2 = d.orthogonal().normalized()
	var pts := PackedVector2Array()
	for i in 13:
		var f: float = float(i) / 12.0 * grow
		var jag: float = (1.0 if i % 2 == 0 else -1.0) * 7.0 * sin(f * PI)
		pts.append(g0 + d * f + n * jag)
	draw_polyline(pts, _c(INK, 0.9 * a), 11.0)
	draw_polyline(pts, _c(SEAM, a), 5.0)
	draw_polyline(pts, _c(HOT, a), 1.8)
	if grow >= 1.0:
		for i in 5:
			var ang: float = -PI * 0.1 - PI * 0.8 * float(i) / 4.0
			var p: Vector2 = g1 + Vector2(cos(ang), sin(ang)) * (10.0 + 30.0 * k)
			draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), _c(Color(0.55, 0.55, 0.55), a))

func _backdraft(from: Vector2, to: Vector2, k: float) -> void:
	var MAGMA := Color(1.0, 0.45, 0.10)
	var WHITE := Color(1.0, 0.97, 0.86)
	var a: float = 1.0 - k
	var o: Vector2 = from + Vector2(0, -r * 0.35)
	var dir: Vector2 = (to - o).normalized()
	var n := dir.orthogonal()
	var reach: float = (to - o).length() * minf(1.0, k / 0.25) + 20.0
	var cone := PackedVector2Array([o, o + dir * reach + n * reach * 0.35, o + dir * reach * 1.08, o + dir * reach - n * reach * 0.35])
	draw_colored_polygon(cone, _c(MAGMA, 0.55 * a))
	var core := PackedVector2Array([o, o + dir * reach * 0.9 + n * reach * 0.14, o + dir * reach, o + dir * reach * 0.9 - n * reach * 0.14])
	draw_colored_polygon(core, _c(WHITE, 0.9 * a))

func _spit(from: Vector2, to: Vector2, k: float) -> void:
	var EMBER := Color(1.0, 0.55, 0.15)
	var travel: float = minf(1.0, k / 0.6)
	var o: Vector2 = from + Vector2(0, -r * 0.4)
	var p: Vector2 = o.lerp(to, travel) + Vector2(0, -sin(travel * PI) * 50.0)
	if travel < 1.0:
		draw_circle(p, 9.0, INK)
		draw_circle(p, 6.5, EMBER)
		draw_circle(p, 3.0, Color(1, 0.95, 0.8))
	else:
		var sk: float = (k - 0.6) / 0.4
		draw_circle(to, 18.0 * (0.5 + sk), _c(EMBER, 0.6 * (1.0 - sk)))

func _sunder(to: Vector2, k: float) -> void:
	var SLIT := Color(1.0, 0.94, 0.25)
	var close: float = minf(1.0, k / 0.25)
	var a: float = 1.0 - clampf((k - 0.4) / 0.6, 0.0, 1.0)
	for side in [-1.0, 1.0]:
		for i in 4:
			var x: float = -21.0 + float(i) * 14.0
			var y0: float = side * (34.0 * (1.0 - close) + 2.0)
			var y1: float = y0 + side * 22.0
			draw_line(to + Vector2(x, y0), to + Vector2(x, y1), _c(INK, a), 8.0)
			draw_line(to + Vector2(x, y0), to + Vector2(x, y1), _c(SLIT, a), 4.0)

func _sweep(from: Vector2, k: float) -> void:
	var RUST := Color(0.55, 0.32, 0.20)
	var GHOST := Color(0.45, 1.0, 0.62)
	var a: float = 1.0 - k * k
	var c: Vector2 = from + Vector2(0, r * 0.3)
	var sweep: float = minf(1.0, k / 0.4)
	var rad: float = r * 1.35
	draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, rad, PI * 0.95, PI * 0.95 - PI * 1.9 * sweep, 40, _c(INK, 0.8 * a), 16.0)
	draw_arc(Vector2.ZERO, rad, PI * 0.95, PI * 0.95 - PI * 1.9 * sweep, 40, _c(GHOST, 0.5 * a), 10.0)
	draw_arc(Vector2.ZERO, rad, PI * 0.95, PI * 0.95 - PI * 1.9 * sweep, 40, _c(RUST, a), 4.0)
	# The toll: one green ring rolling out once the sweep completes.
	if k > 0.4:
		var tk: float = (k - 0.4) / 0.6
		draw_arc(Vector2.ZERO, rad * (1.0 + 0.6 * tk), 0, TAU, 48, _c(GHOST, 0.8 * (1.0 - tk)), 4.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _cornerstone(from: Vector2, k: float) -> void:
	var GOLD := Color(1.0, 0.88, 0.50)
	var MARBLE := Color(0.92, 0.94, 0.95)
	var a: float = 1.0 - k
	var c: Vector2 = from + Vector2(0, r * 0.35)
	var half: float = r * (0.7 + 1.3 * k)
	draw_set_transform(c, 0.0, Vector2(1.0, 0.5))
	var sq := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half), Vector2(-half, -half)])
	draw_polyline(sq, _c(INK, 0.8 * a), 14.0)
	draw_polyline(sq, _c(MARBLE, a), 8.0)
	draw_polyline(sq, _c(GOLD, a), 3.0)
	# Glyph ticks along each side.
	for side in 4:
		for i in 3:
			var f: float = (float(i) + 1.0) / 4.0
			var p0: Vector2 = sq[side].lerp(sq[side + 1], f)
			var inward: Vector2 = -p0.normalized() * 10.0
			draw_line(p0, p0 + inward, _c(GOLD, a), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
