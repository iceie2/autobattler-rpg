extends Node2D
class_name PhoenixVFX

# The Ember Phoenix's visual language: EMBERS AND UPDRAFT. Built from rising
# sparks, a feathered plume arc and a hot white core — deliberately different
# from Sear/Ember's hero fire (which is broad flame) and from the Hellhound's
# burn, because this bird is a *forge* rather than a blaze.
#
# Fills three gaps from the audit:
#   • Cinder Lance resolved instantly with a generic SkillEffect.ARROW_RAIN.
#   • Its "Rekindle" regen (2% max HP/s) was completely invisible, so the
#     counterplay — hit it with Fire or Lightning to smother the embers — was
#     never communicated.
#   • Nothing told the player the regen was currently BLOCKED, which is the
#     moment the counterplay actually pays off.

enum Mode { LANCE_WINDUP, LANCE_IMPACT, REKINDLE, SMOTHERED }

const EMBER := Color(1.0, 0.52, 0.12)
const DEEP := Color(0.45, 0.10, 0.02)
const CORE := Color(1.0, 0.94, 0.72)
const ASH := Color(0.32, 0.30, 0.31)

var mode: Mode = Mode.LANCE_IMPACT
var elapsed := 0.0
var lifetime := 0.5
var host = null
var reach := 88.0
var _t := 0.0
var ground_y := 46.0           # foot line, set from the host at setup
var _rng := RandomNumberGenerator.new()
var _sparks: Array = []

func _ready() -> void:
	_rng.seed = int(get_instance_id()) & 0x7fffffff
	for i in range(12):
		_sparks.append(Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.0, 1.0),
			_rng.randf_range(0.6, 1.5)))

func setup_point(kind: Mode, world_pos: Vector2, size: float, life: float) -> void:
	mode = kind
	global_position = world_pos
	reach = size
	lifetime = life
	z_index = 4
	queue_redraw()

func setup_on(kind: Mode, unit, size: float, life: float) -> void:
	mode = kind
	host = unit
	reach = size
	lifetime = life
	z_index = 3
	if unit and "shape_size" in unit:
		ground_y = float(unit.shape_size) * 0.72
	queue_redraw()

func _process(delta: float) -> void:
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

func _spark(p: Vector2, r: float, a: float, col: Color = EMBER) -> void:
	draw_circle(p, r + 1.2, Color(DEEP.r, DEEP.g, DEEP.b, a * 0.7))
	draw_circle(p, r, Color(col.r, col.g, col.b, a))

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	match mode:
		Mode.LANCE_WINDUP: _draw_windup(t)
		Mode.LANCE_IMPACT: _draw_impact(t)
		Mode.REKINDLE:     _draw_rekindle()
		Mode.SMOTHERED:    _draw_smothered(t)

# ── It draws heat inward and the plume flares before the lance goes ─────────
func _draw_windup(t: float) -> void:
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * (0.40 + t * 0.30), Color(EMBER.r, EMBER.g, EMBER.b, 0.06 + t * 0.14))
	# Feathered plume: three arcs sweeping up and back, opening as it charges.
	for i in range(3):
		var spread: float = 0.35 + 0.22 * float(i) + t * 0.30
		var rad: float = r * (0.46 + 0.16 * float(i))
		draw_arc(Vector2.ZERO, rad, -PI * 0.5 - spread, -PI * 0.5 + spread, 16,
			Color(EMBER.r, EMBER.g, EMBER.b, (0.55 - 0.12 * float(i)) * (0.4 + 0.6 * t)), 2.6)
	# Sparks drawn IN toward the beak — the gather, and the countdown.
	for i in range(_sparks.size()):
		var s: Vector3 = _sparks[i]
		var d := Vector2(s.x, -s.y - 0.2).normalized()
		_spark(d * r * (0.95 - t * 0.60), 1.6 * s.z, 0.35 + 0.5 * t)
	_spark(Vector2.ZERO, 3.5 + 7.0 * t, 0.6 + 0.4 * t, CORE)

# ── The lance lands ────────────────────────────────────────────────────────
func _draw_impact(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * (0.45 + 0.75 * t), Color(EMBER.r, EMBER.g, EMBER.b, 0.20 * fade))
	# A struck-anvil burst: a bright lance line plus sparks thrown UP and out,
	# so it reads as a forge strike rather than a generic fire puff.
	for i in range(_sparks.size()):
		var s: Vector3 = _sparks[i]
		var d := Vector2(s.x, -s.y).normalized()
		var p: Vector2 = d * r * (0.25 + 0.95 * t)
		_spark(p, (1.8 + s.z * 1.4) * fade, 0.9 * fade)
	draw_line(Vector2(0, r * 0.55), Vector2(0, -r * (0.35 + 0.5 * t)),
		Color(CORE.r, CORE.g, CORE.b, 0.85 * fade), 4.0 * fade + 1.0)
	draw_circle(Vector2.ZERO, (18.0 * fade + 4.0), Color(EMBER.r, EMBER.g, EMBER.b, 0.55 * fade))
	draw_circle(Vector2.ZERO, (8.0 * fade + 2.0), Color(CORE.r, CORE.g, CORE.b, fade))

# ── Persistent: the embers are lit and it is healing ───────────────────────
# ANCHORED AT THE FEET, not on the body. The Phoenix sprite is itself a mass of
# bright orange fire, so ember-coloured sparks drawn over it were completely
# invisible (measured: the first capture showed nothing at all on either state).
# A ground forge-ring reads because it sits on empty board, and rising motes are
# only drawn once they have cleared the silhouette.
func _draw_rekindle() -> void:
	var r := reach * 0.5
	var breathe: float = 0.5 + 0.5 * sin(_t * 1.8)
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.42))
	# Forge ring: a bright bed of coals under the bird.
	draw_circle(Vector2.ZERO, r * (0.62 + 0.05 * breathe),
		Color(DEEP.r, DEEP.g, DEEP.b, 0.34 + 0.10 * breathe))
	draw_arc(Vector2.ZERO, r * 0.62, 0.0, TAU, 28,
		Color(EMBER.r, EMBER.g, EMBER.b, 0.70 + 0.25 * breathe), 3.0)
	for i in range(8):
		var a: float = _t * 0.8 + float(i) * TAU / 8.0
		draw_circle(Vector2(cos(a), sin(a)) * r * 0.50, 2.8,
			Color(CORE.r, CORE.g, CORE.b, 0.55 + 0.35 * breathe))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Motes rising OUT of the ring, only above the body so they stay legible.
	for i in range(_sparks.size()):
		var sp: Vector3 = _sparks[i]
		var phase: float = fposmod(_t * 0.55 + float(i) / float(_sparks.size()), 1.0)
		var x: float = sp.x * r * 0.52 + sin(phase * 5.0 + float(i)) * 3.0
		var y: float = ground_y - phase * (ground_y + r * 0.95)
		_spark(Vector2(x, y), 1.4 + 1.2 * (1.0 - phase) * sp.z, (1.0 - phase) * 0.72, CORE)

# ── The counterplay landing: embers smothered, regen OFF ───────────────────
# Fires when a Fire or Lightning hit blocks the regen — the payoff for the only
# counterplay the passive has, previously silent. Deliberately a DENSE grey pall
# drawn OVER the body: against a sprite made of fire, desaturating it is the one
# thing that reads instantly, and it says "put out" without ambiguity.
func _draw_smothered(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	# Heavy ash covering the bird, settling downward as it fades.
	for i in range(3):
		var f := float(i) / 3.0
		draw_circle(Vector2(0, -r * 0.10 + f * r * 0.30 + t * 10.0),
			r * (0.52 - f * 0.10) * (0.75 + 0.35 * t),
			Color(ASH.r, ASH.g, ASH.b, (0.46 - f * 0.10) * fade))
	# Dying sparks fall instead of rising — the inverted read against Rekindle.
	for i in range(_sparks.size()):
		var sp: Vector3 = _sparks[i]
		var d := Vector2(sp.x, -sp.y).normalized()
		var pt: Vector2 = d * r * (0.20 + 0.40 * t) + Vector2(0, t * t * 30.0)
		_spark(pt, 1.6 * sp.z * fade, 0.75 * fade, ASH)
	# Smoke curls rising off the snuffed coals.
	for i in range(4):
		var bx: float = (float(i) - 1.5) * r * 0.26
		var by: float = ground_y - t * r * 0.7
		draw_circle(Vector2(bx + sin(_t * 2.0 + float(i)) * 4.0, by),
			(4.0 + 3.0 * t) , Color(ASH.r, ASH.g, ASH.b, 0.34 * fade))
	draw_arc(Vector2.ZERO, r * (0.34 + 0.34 * t), 0.0, TAU, 24,
		Color(ASH.r, ASH.g, ASH.b, 0.7 * fade), 2.8)
