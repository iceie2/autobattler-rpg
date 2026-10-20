extends Node2D
class_name BearVFX

# The Bear's visual language: CLAW RAKES AND OPEN WOUNDS.
# Built from parallel gashes and running blood — hard diagonal strokes, unlike
# the Rat's drifting motes, the Slime's droplets or the Crab's flat facets.
#
# The headline gap this fills: Rending Swipe's bleed DOUBLES its tick rate while
# the victim is moving (BLEED_MOVE_MULT), which is a real and interesting
# decision — stand and fight, or keep repositioning and bleed out twice as fast.
# That was completely invisible: no bleed visual of any kind existed, so neither
# the bleed NOR the thing that makes it interesting was ever communicated.
# BLEED below is persistent AND visibly intensifies while the target moves.

enum Mode { SWIPE_WINDUP, SWIPE_IMPACT, BLEED, FURY }

const BLOOD := Color(0.72, 0.10, 0.12)
const DARK := Color(0.26, 0.03, 0.05)
const HOT := Color(1.0, 0.55, 0.45)

static func body_colors(element: int) -> Array[Color]:
	match element:
		UnitBase.Element.FIRE: return [Color("352725"), Color("be6239")]
		UnitBase.Element.WATER: return [Color("244956"), Color("6eabb7")]
		UnitBase.Element.EARTH: return [Color("50422b"), Color("9f8852")]
		UnitBase.Element.AIR: return [Color("657d74"), Color("b4cec0")]
		UnitBase.Element.LIGHTNING: return [Color("433852"), Color("9b80bb")]
	return [Color("514d43"), Color("8c8775")]

var _element: int = UnitBase.Element.NORMAL

var mode: Mode = Mode.SWIPE_IMPACT
var elapsed := 0.0
var lifetime := 0.45
var host = null
var reach := 88.0
var intensity := 0.0         # BLEED: 0 = standing, 1 = moving (double rate)
var rage := 0.0              # FURY: 0..1 across the +0%..+30% ramp
var ground_y := 46.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _drops: Array = []

func _ready() -> void:
	_rng.seed = int(get_instance_id()) & 0x7fffffff
	for i in range(10):
		_drops.append(Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.0, 1.0),
			_rng.randf_range(0.6, 1.5)))

func setup_point(kind: Mode, world_pos: Vector2, size: float, life: float) -> void:
	mode = kind
	global_position = world_pos
	reach = size
	lifetime = life
	z_index = 4
	queue_redraw()

func setup_on(kind: Mode, unit, size: float, life: float) -> void:
	if unit and bool(unit.get_meta("bear", false)):
		_element = unit.current_element
	mode = kind
	host = unit
	reach = size
	lifetime = life
	z_index = 3
	if unit and "shape_size" in unit:
		ground_y = float(unit.shape_size) * 0.72
	queue_redraw()

func set_intensity(v: float) -> void:
	intensity = clampf(v, 0.0, 1.0)
	queue_redraw()

func set_rage(v: float) -> void:
	rage = clampf(v, 0.0, 1.0)
	queue_redraw()

func _process(delta: float) -> void:
	if host and is_instance_valid(host) and host.has_method("_battle_clock"):
		delta *= host._battle_clock()
	elapsed += delta
	_t += delta
	if host != null:
		if not is_instance_valid(host):
			queue_free()
			return
		global_position = host.global_position
	if elapsed >= lifetime:
		queue_free()
	else:
		queue_redraw()

# Three parallel gashes at a diagonal — the unmistakable claw read. Dark rim
# under a hot core so they stay legible on any body colour.
func _rakes(origin: Vector2, len: float, spread: float, a: float, w: float) -> void:
	var dir := Vector2(0.80, 0.60)
	var perp := dir.orthogonal()
	for i in range(3):
		var off: Vector2 = perp * (float(i) - 1.0) * spread
		var p0: Vector2 = origin + off - dir * len * 0.5
		var p1: Vector2 = origin + off + dir * len * 0.5
		draw_line(p0, p1, Color(DARK.r, DARK.g, DARK.b, a), w + 2.2)
		draw_line(p0, p1, Color(BLOOD.r, BLOOD.g, BLOOD.b, a), w)

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	match mode:
		Mode.SWIPE_WINDUP: _draw_windup(t)
		Mode.SWIPE_IMPACT: _draw_impact(t)
		Mode.BLEED:        _draw_bleed()
		Mode.FURY:         _draw_fury()
	if mode in [Mode.SWIPE_WINDUP, Mode.SWIPE_IMPACT]:
		LizardVFX.draw_accent(self, _element, Vector2(12, -reach * 0.08), reach * 0.10, _t, 0.65 * (1.0 - t))

# ── The paw draws back ─────────────────────────────────────────────────────
func _draw_windup(t: float) -> void:
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * (0.30 + t * 0.22), Color(BLOOD.r, BLOOD.g, BLOOD.b, 0.05 + t * 0.10))
	# Claw arcs cocking back and widening — the tell.
	var pull: float = r * (0.30 + 0.34 * t)
	_rakes(Vector2(-pull * 0.6, -pull * 0.45), r * (0.35 + 0.30 * t),
		4.0 + 4.0 * t, 0.35 + 0.5 * t, 2.0 + 1.4 * t)
	draw_circle(Vector2.ZERO, 3.0 + 4.0 * t, Color(HOT.r, HOT.g, HOT.b, 0.35 + 0.35 * t))

# ── The rake lands and opens the wound ─────────────────────────────────────
func _draw_impact(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * (0.40 + 0.6 * t), Color(BLOOD.r, BLOOD.g, BLOOD.b, 0.18 * fade))
	# The three gashes sweep ACROSS and lengthen — one decisive stroke.
	_rakes(Vector2.ZERO, r * (0.7 + 0.8 * t), 9.0 + 5.0 * t, 0.95 * fade, 4.0 * fade + 1.2)
	for i in range(_drops.size()):
		var d: Vector3 = _drops[i]
		var dir := Vector2(d.x, -d.y).normalized()
		var p: Vector2 = dir * r * (0.25 + 0.85 * t) + Vector2(0, t * t * 24.0)
		draw_circle(p, (1.8 + d.z * 1.4) * fade, Color(BLOOD.r, BLOOD.g, BLOOD.b, 0.9 * fade))
	draw_circle(Vector2.ZERO, (10.0 * fade + 3.0), Color(HOT.r, HOT.g, HOT.b, 0.7 * fade))

# ── Persistent: the wound is open, and it reopens when they run ────────────
# `intensity` is driven from the victim's is_moving, which is exactly the flag
# BLEED_MOVE_MULT reads — so what the player sees IS the mechanic, not an
# approximation of it. Standing still visibly calms the bleed.
func _draw_bleed() -> void:
	var r := reach * 0.5
	var rate: float = 1.0 + intensity              # 1x standing, 2x moving
	# Wound marks on the body, brighter and wider open when reopened by movement.
	_rakes(Vector2(0, -r * 0.05), r * 0.46, 5.0 + 3.0 * intensity,
		0.45 + 0.40 * intensity, 2.0 + 1.6 * intensity)
	# Blood running down and pooling — drip rate literally doubles with the tick
	# rate, so "I am bleeding faster" is readable without a number.
	var n: int = 4 + int(round(intensity * 5.0))
	for i in range(n):
		var d: Vector3 = _drops[i % _drops.size()]
		var phase: float = fposmod(_t * 0.55 * rate + float(i) / float(n), 1.0)
		var x: float = d.x * r * 0.34
		var y: float = -r * 0.02 + phase * (ground_y + r * 0.10)
		draw_circle(Vector2(x, y), 1.5 + 1.4 * (1.0 - phase) * d.z,
			Color(BLOOD.r, BLOOD.g, BLOOD.b, (1.0 - phase) * (0.55 + 0.35 * intensity)))
	# A spatter pool at the feet that widens while they keep moving.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, r * (0.20 + 0.20 * intensity),
		Color(DARK.r, DARK.g, DARK.b, 0.30 + 0.25 * intensity))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ── Persistent: the Bear is enraged (aspd ramps with missing HP) ───────────
# Ground-anchored so it never fights the health bar, and it only appears once
# the ramp is actually meaningful.
func _draw_fury() -> void:
	if rage <= 0.05:
		return
	var r := reach * 0.5
	var pulse: float = 0.5 + 0.5 * sin(_t * (2.0 + 4.0 * rage))
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	draw_circle(Vector2.ZERO, r * (0.46 + 0.14 * rage),
		Color(BLOOD.r, BLOOD.g, BLOOD.b, (0.10 + 0.14 * rage) * (0.7 + 0.3 * pulse)))
	draw_arc(Vector2.ZERO, r * (0.46 + 0.14 * rage), 0.0, TAU, 26,
		Color(BLOOD.r, BLOOD.g, BLOOD.b, 0.35 + 0.40 * rage), 2.0 + 1.6 * rage)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Heat haze flicking up off the shoulders, faster the angrier it is.
	for i in range(4):
		var f: float = fposmod(_t * (0.7 + 1.1 * rage) + float(i) / 4.0, 1.0)
		var x: float = (float(i) - 1.5) * r * 0.26
		draw_circle(Vector2(x + sin(f * 6.0 + float(i)) * 3.0, r * 0.10 - f * r * 0.55),
			2.0 + 2.0 * (1.0 - f) * rage,
			Color(HOT.r, HOT.g, HOT.b, (1.0 - f) * 0.45 * rage))
