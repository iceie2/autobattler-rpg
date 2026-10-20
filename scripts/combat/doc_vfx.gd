extends Node2D
class_name DocVFX
## Doc's medicine (2026-09-26). Raccoon field medic, WATER element: liquid,
## droplets and rings (the element's language), plus one medic motif — the
## heartbeat line. Replaces the thin serum dots and the shared gold HOLY_LIGHT.
##
##   SERUM   Inject. A glowing dart of serum leaves the needle on `launch`, arcs to
##           the ally with a wobbling liquid trail, and splashes on `land`:
##           droplets, a ring, a "+" and a soft green glow rising off them.
##           AutoBattleManager heals on `land`.
##   PULSE   Field Surgery. On his plunge (`impact`) a ring bursts where the needle
##           hits the ground and a heartbeat trace (flat - spike - flat) races
##           along the ground to `target`; on `land` a gold-green surge rises there,
##           with a big heartbeat blip over them. Used once for a revive (big) or
##           once per ally for the no-one-down team heal (`small`).
##
## Ground marks at z 1 (under units, over the grass), light at z 20. Battle clock.

enum Mode { SERUM, PULSE }

const SERUM := Color(0.42, 1.0, 0.62)
const SERUM_DEEP := Color(0.10, 0.62, 0.42)
const WHITE := Color(0.96, 1.0, 0.97)
const GOLD := Color(1.0, 0.86, 0.40)
const OUTLINE := Color(0.06, 0.10, 0.10)

var mode: Mode = Mode.SERUM
var caster: Node2D = null
var target: Node2D = null          # unit, or null when aiming at `target_point`
var target_point := Vector2.ZERO   # used when there is no unit yet (revive cell)
var launch := 0.29
var land := 0.54
var impact := 0.54
var small := false
var end_time := 1.6

var _t := 0.0
var _from := Vector2.ZERO
var _foot := Vector2.ZERO          # caster feet (pulse start)
var _to := Vector2.ZERO            # target feet
var _h := 60.0                     # target height px
var _seeds: Array = []
var _ground: Node2D = null

class _GroundLayer extends Node2D:
	var fx = null
	func _draw() -> void:
		if fx: fx._draw_ground(self)

func setup(p_mode: Mode, p_caster: Node2D, p_target: Node2D, p_point := Vector2.ZERO) -> void:
	mode = p_mode
	caster = p_caster
	target = p_target
	target_point = p_point
	top_level = true
	z_as_relative = false
	z_index = 20
	global_position = Vector2.ZERO
	end_time = land + (0.9 if mode == Mode.SERUM else 1.2)
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
	var src: Node2D = caster if caster and is_instance_valid(caster) else null
	var bm = src.get("battle_manager") if src else null
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
		_foot = _feet(caster)
		var m = caster.get("model3d")
		if m:
			# the needle tip: the grip plus the syringe's length along the forearm line
			var grip: Vector2 = m.bone_canvas_position("weapon_r")
			var fore: Vector2 = grip - m.bone_canvas_position("RightForeArm")
			_from = grip + fore.normalized() * fore.length() * 0.9
		else:
			_from = caster.global_position + Vector2(0, -40)
	if target and is_instance_valid(target):
		_to = _feet(target)
		var hh = target.get("_sprite_half_h")
		_h = float(hh) * 2.0 if hh != null else 60.0
	elif target_point != Vector2.ZERO:
		_to = target_point

func _process(delta: float) -> void:
	_t += delta * _clock()
	if _t >= end_time:
		queue_free()
		return
	var lock := launch if mode == Mode.SERUM else impact
	if _t < lock:
		_track()           # follow the syringe until the shot leaves
	elif target and is_instance_valid(target):
		_to = _feet(target)   # keep landing on the unit if it moves (or is revived elsewhere)
	queue_redraw()
	_ground.queue_redraw()

func _glow(ci: CanvasItem, c: Vector2, r: float, col: Color, layers: int = 6) -> void:
	for i in range(layers, 0, -1):
		var f := float(i) / layers
		ci.draw_circle(c, r * f, Color(col, col.a * (1.0 - f) * 0.9))

func _ell(c: Vector2, r: Vector2, n: int = 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts

func _plus(ci: CanvasItem, p: Vector2, s: float, col: Color) -> void:
	var w := s * 0.42
	for rct in [Rect2(p + Vector2(-w * 0.5, -s), Vector2(w, s * 2)), Rect2(p + Vector2(-s, -w * 0.5), Vector2(s * 2, w))]:
		ci.draw_rect(rct.grow(maxf(1.5, s * 0.14)), Color(OUTLINE, col.a * 0.7))
	for rct in [Rect2(p + Vector2(-w * 0.5, -s), Vector2(w, s * 2)), Rect2(p + Vector2(-s, -w * 0.5), Vector2(s * 2, w))]:
		ci.draw_rect(rct, col)

## heartbeat trace from a to b: flat, then a sharp beat near the front, flat
func _ecg(ci: CanvasItem, a: Vector2, b: Vector2, head: float, amp: float, col: Color, w: float) -> void:
	var d := b - a
	var n := Vector2(-d.y, d.x).normalized()
	if n.y > 0.0:
		n = -n                      # spikes point up the screen
	var pts := PackedVector2Array()
	var steps := 48
	for i in steps + 1:
		var u := head * i / steps
		var k := u / maxf(head, 0.001)   # 0 at the start, 1 at the moving front
		var beat := 0.0
		var x := fposmod(u * 3.0, 1.0)   # three beats along the full line
		if x > 0.55 and x < 0.75:
			var q := (x - 0.55) / 0.2
			beat = (sin(q * TAU * 1.5) * (1.0 - q)) * 1.0
		pts.append(a + d * u + n * beat * amp * (0.4 + 0.6 * k))
	ci.draw_polyline(pts, Color(col, col.a * 0.18), w * 4.0, true)   # soft glow under the trace
	ci.draw_polyline(pts, Color(OUTLINE, col.a * 0.5), w + 3.0, true)
	ci.draw_polyline(pts, col, w, true)
	ci.draw_polyline(pts, Color(WHITE, col.a * 0.8), maxf(1.0, w * 0.35), true)

# ── ground ──────────────────────────────────────────────────────────────────

func _draw_ground(ci: CanvasItem) -> void:
	var foot := Vector2(_h * 0.5, _h * 0.18)
	if mode == Mode.SERUM:
		if _t < land:
			return
		var p := clampf((_t - land) / 0.5, 0.0, 1.0)
		for i in 2:
			var q := clampf(p * 1.4 - i * 0.25, 0.0, 1.0)
			if q > 0.0 and q < 1.0:
				ci.draw_polyline(_ell(_to, foot * (0.4 + 0.9 * q)), Color(SERUM, 0.8 * (1.0 - q)), 2.5 * (1.0 - q) + 1.0, true)
		return
	if _t < impact:
		return
	var e := _t - impact
	# burst where the needle hits the ground, just in front of him
	var hit := _foot + Vector2(0, -2)
	var bq := clampf(e / 0.4, 0.0, 1.0)
	if bq < 1.0:
		var r := foot * (0.6 if small else 1.0) * (0.3 + 1.1 * bq)
		ci.draw_polyline(_ell(hit, r), Color(OUTLINE, 0.35 * (1.0 - bq)), 6.0, true)
		ci.draw_polyline(_ell(hit, r), Color(SERUM, 0.9 * (1.0 - bq)), 3.0, true)
	# the heartbeat racing to the target, then fading
	var travel := maxf(land - impact, 0.05)
	var head := clampf(e / travel, 0.0, 1.0)
	var fade := 1.0 - clampf((e - travel - 0.2) / 0.5, 0.0, 1.0)
	if fade > 0.0:
		var col := SERUM.lerp(GOLD, 0.0 if small else 0.35)
		_ecg(ci, hit, _to, head, (10.0 if small else 22.0), Color(col, 0.95 * fade), 3.0 if small else 5.0)
		_glow(ci, hit.lerp(_to, head), 10.0 if small else 16.0, Color(WHITE, 0.8 * fade))
	# landing ring under them
	if _t >= land:
		var lq := clampf((_t - land) / 0.5, 0.0, 1.0)
		ci.draw_polyline(_ell(_to, foot * (0.5 + 0.9 * lq)), Color(GOLD if not small else SERUM, 0.9 * (1.0 - lq)), 3.0, true)
		var pts := _ell(_to, foot * 0.8, 28); pts.remove_at(pts.size() - 1)
		ci.draw_colored_polygon(pts, Color(SERUM, 0.18 * (1.0 - lq)))

# ── light ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if mode == Mode.SERUM:
		_draw_serum()
	else:
		_draw_pulse()

func _dart_pos(u: float) -> Vector2:
	var to := _to + Vector2(0, -_h * 0.55)
	var lift := maxf(24.0, _from.distance_to(to) * 0.22)
	return _from.lerp(to, u) + Vector2(0, -lift * 4.0 * u * (1.0 - u))

func _draw_serum() -> void:
	if _t < launch:
		# a bead of serum gathering on the needle
		var g := clampf((_t - launch + 0.15) / 0.15, 0.0, 1.0)
		if g > 0.0:
			_glow(self, _from, 8.0 * g, Color(SERUM, 0.9))
		return
	if _t < land:
		var u := clampf((_t - launch) / maxf(land - launch, 0.01), 0.0, 1.0)
		# liquid trail: a ribbon of beads that wobbles like it's poured
		for i in range(12, 0, -1):
			var uu := maxf(0.0, u - i * 0.03)
			var p := _dart_pos(uu) + Vector2(0, sin((uu * 18.0) + _t * 20.0) * 2.0)
			var k := 1.0 - float(i) / 12.0
			draw_circle(p, 1.5 + 3.5 * k, Color(SERUM_DEEP.lerp(SERUM, k), 0.35 + 0.5 * k))
		var head := _dart_pos(u)
		_glow(self, head, 14.0, Color(SERUM, 0.9))
		draw_circle(head, 4.5, WHITE)
		return
	var e := _t - land
	var a := 1.0 - clampf((e - 0.25) / 0.6, 0.0, 1.0)
	var chest := _to + Vector2(0, -_h * 0.55)
	if e < 0.18:
		_glow(self, chest, _h * (0.45 + e * 2.0), Color(WHITE, 0.85 * (1.0 - e / 0.18)))
	# droplets splashing off and falling
	for i in 12:
		var s: float = _seeds[i]
		var ang := -PI * (0.1 + 0.8 * float(_seeds[(i + 7) % 24]))
		var v := Vector2(cos(ang), sin(ang)) * _h * (0.8 + 0.9 * s)
		var tt := e * 1.2
		if tt > 0.8:
			continue
		var p := chest + v * tt + Vector2(0, _h * 2.2 * tt * tt)
		draw_circle(p, 2.5 * (1.0 - tt), Color(SERUM, 0.9 * (1.0 - tt / 0.8)))
	# soft green glow rising off them
	for i in 3:
		var ph := clampf(e * 1.1 - i * 0.15, 0.0, 1.0)
		if ph <= 0.0 or ph >= 1.0:
			continue
		_glow(self, _to + Vector2(0, -_h * (0.3 + ph * 0.9)), _h * 0.3 * (1.0 - ph * 0.5), Color(SERUM, 0.35 * (1.0 - ph)))
	# the "+"
	var pop := clampf(e / 0.16, 0.0, 1.0)
	var sc := (1.0 + 0.3 * sin(PI * pop)) * pop
	if a > 0.01 and sc > 0.01:
		_plus(self, _to + Vector2(0, -_h * 1.2 - e * 18.0), _h * 0.11 * sc, Color(SERUM, a))

func _draw_pulse() -> void:
	if _t < impact:
		return
	var e := _t - impact
	# the jolt at his needle
	if e < 0.2:
		_glow(self, _foot + Vector2(0, -6), (18.0 if small else 30.0) * (1.0 + e * 3.0), Color(WHITE, 0.9 * (1.0 - e / 0.2)))
	if _t < land:
		return
	var l := _t - land
	var a := 1.0 - clampf((l - 0.2) / 0.8, 0.0, 1.0)
	if small:
		_plus(self, _to + Vector2(0, -_h * 1.15 - l * 16.0), _h * 0.09 * clampf(l / 0.12, 0.0, 1.0), Color(SERUM, a))
		return
	# the surge they rise in: a soft column of green-gold light
	var grow := clampf(l / 0.15, 0.0, 1.0)
	var w := _h * 0.46
	for L in [[1.0, SERUM, 0.28], [0.6, GOLD, 0.38], [0.28, WHITE, 0.75]]:
		var ww: float = w * float(L[0])
		var col: Color = L[1]
		var la: float = float(L[2]) * a
		var top := _to + Vector2(0, -_h * 2.6 * (0.5 + 0.5 * grow))
		draw_polygon(PackedVector2Array([_to + Vector2(-ww, 0), _to + Vector2(ww, 0), top + Vector2(ww * 0.6, 0), top + Vector2(-ww * 0.6, 0)]),
			PackedColorArray([Color(col, la), Color(col, la), Color(col, 0.0), Color(col, 0.0)]))
	if l < 0.2:
		_glow(self, _to + Vector2(0, -_h * 0.5), _h * (0.8 + l * 3.0), Color(WHITE, 0.9 * (1.0 - l / 0.2)), 7)
	# the heartbeat blip over them: the trace draws on, holds, fades
	var bw := _h * 0.9
	var bc := _to + Vector2(0, -_h * 1.55)
	var draw_on := clampf(l / 0.3, 0.0, 1.0)
	var bpts := PackedVector2Array()
	var shape := [Vector2(-1.0, 0), Vector2(-0.35, 0), Vector2(-0.2, -0.25), Vector2(-0.05, 0.9),
		Vector2(0.1, -1.0), Vector2(0.25, 0.3), Vector2(0.35, 0), Vector2(1.0, 0)]
	var total := shape.size() - 1
	for i in shape.size():
		var f := float(i) / total
		if f > draw_on:
			var prev: Vector2 = shape[i - 1]
			var cur: Vector2 = shape[i]
			var fp := float(i - 1) / total
			var q := (draw_on - fp) / (f - fp)
			var pt: Vector2 = prev.lerp(cur, q)
			bpts.append(bc + Vector2(pt.x * bw * 0.5, -pt.y * _h * 0.28))
			break
		var sp: Vector2 = shape[i]
		bpts.append(bc + Vector2(sp.x * bw * 0.5, -sp.y * _h * 0.28))
	if bpts.size() >= 2:
		draw_polyline(bpts, Color(OUTLINE, 0.6 * a), 7.0, true)
		draw_polyline(bpts, Color(SERUM, a), 4.0, true)
		draw_polyline(bpts, Color(WHITE, 0.9 * a), 1.5, true)
