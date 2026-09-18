extends Node2D
class_name StormGiantVFX

# The Storm Giant's visual language: A SLOW THUNDERHEAD AND ONE HEAVY FORK.
#
# Deliberately NOT Static's lightning. Static (the hero) is fast, thin, yellow
# and jagged — lots of small arcs. This is the opposite end of the same element:
# a dense slate cloud that BUILDS, then a single thick blue-white fork that
# falls once. Slow and heavy versus fast and busy, so a Storm Giant and a Static
# on the same board never read as the same effect.
#
# Sized for a 2x2 body — the biggest footprint in this project so far, so the
# cloud is drawn ABOVE the head and the ground flash below, leaving the middle
# (where a 2x2 health bar sits) clear.

enum Mode { CLAP_WINDUP, CLAP_IMPACT, GATHERING }

const SLATE := Color(0.30, 0.34, 0.44)
const BOLT := Color(0.80, 0.92, 1.0)
const CHARGE := Color(0.55, 0.78, 1.0)
const DARK := Color(0.08, 0.09, 0.14)

var mode: Mode = Mode.CLAP_IMPACT
var elapsed := 0.0
var lifetime := 0.5
var host = null
var reach := 150.0
var storm := 0.0             # GATHERING: 0..1 across the +0%..+50% ramp
var ground_y := 72.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _seeds: Array = []

func _ready() -> void:
	_rng.seed = int(get_instance_id()) & 0x7fffffff
	for i in range(8):
		_seeds.append(_rng.randf_range(-1.0, 1.0))

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

func set_storm(v: float) -> void:
	storm = clampf(v, 0.0, 1.0)
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

# A thunderhead: overlapping slate lobes, denser as it builds.
func _cloud(cy: float, w: float, density: float, a: float) -> void:
	var n: int = 3 + int(round(density * 3.0))
	for i in range(n):
		var f := (float(i) + 0.5) / float(n)
		var x: float = lerp(-w, w, f)
		var lobe: float = w * (0.30 + 0.22 * sin(f * PI)) * (0.8 + 0.3 * density)
		draw_circle(Vector2(x, cy + sin(_t * 0.8 + float(i)) * 2.0), lobe,
			Color(SLATE.r, SLATE.g, SLATE.b, a))

# One heavy fork, drawn as a jagged polyline with a dark rim under a bright core.
func _fork(from: Vector2, to: Vector2, jag: float, a: float, w: float) -> void:
	var pts := PackedVector2Array()
	var steps := 6
	for i in range(steps + 1):
		var f := float(i) / float(steps)
		var p: Vector2 = from.lerp(to, f)
		if i > 0 and i < steps:
			p.x += _seeds[i % _seeds.size()] * jag
		pts.append(p)
	draw_polyline(pts, Color(DARK.r, DARK.g, DARK.b, a * 0.9), w + 3.0)
	draw_polyline(pts, Color(CHARGE.r, CHARGE.g, CHARGE.b, a), w + 1.2)
	draw_polyline(pts, Color(BOLT.r, BOLT.g, BOLT.b, a), w * 0.45)

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	match mode:
		Mode.CLAP_WINDUP: _draw_windup(t)
		Mode.CLAP_IMPACT: _draw_impact(t)
		Mode.GATHERING:   _draw_gathering()

# ── The cloud gathers and the charge climbs ───────────────────────────────
# The tell is vertical: cloud thickens overhead, charge crawls DOWN toward the
# ground. Unmistakable from across a board and monotonically escalating.
func _draw_windup(t: float) -> void:
	var r := reach * 0.5
	var top: float = -ground_y - r * 1.05
	_cloud(top, r * (0.55 + 0.18 * t), t, 0.30 + 0.45 * t)
	# Charge feelers reaching down out of the cloud.
	for i in range(3):
		var x: float = (float(i) - 1.0) * r * 0.26
		var drop: float = (ground_y + r * 0.40) * t * 0.55
		draw_line(Vector2(x, top + r * 0.16), Vector2(x + _seeds[i] * 5.0, top + r * 0.16 + drop),
			Color(CHARGE.r, CHARGE.g, CHARGE.b, 0.35 + 0.45 * t), 2.0 + 1.6 * t)
	# Ground target flash brightening as the strike nears.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	draw_arc(Vector2.ZERO, r * (0.60 - 0.14 * t), 0.0, TAU, 26,
		Color(CHARGE.r, CHARGE.g, CHARGE.b, 0.25 + 0.50 * t), 2.0 + 2.0 * t)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ── One heavy fork comes down ─────────────────────────────────────────────
func _draw_impact(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	var top: float = -ground_y - r * 1.05
	_cloud(top, r * 0.72, 1.0, 0.45 * fade)
	# THE bolt — one thick fork, not a spray of little arcs.
	_fork(Vector2(0, top + r * 0.20), Vector2(0, ground_y), 9.0, fade, 5.0 * fade + 1.5)
	# Ground discharge spreading out along the floor.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	draw_circle(Vector2.ZERO, r * (0.25 + 0.55 * t), Color(CHARGE.r, CHARGE.g, CHARGE.b, 0.35 * fade))
	draw_arc(Vector2.ZERO, r * (0.25 + 0.85 * t), 0.0, TAU, 30,
		Color(BOLT.r, BOLT.g, BOLT.b, 0.9 * fade), 4.0 * fade + 1.0)
	for i in range(6):
		var a: float = float(i) * TAU / 6.0 + 0.3
		var d := Vector2(cos(a), sin(a))
		draw_line(d * r * 0.20, d * r * (0.40 + 0.65 * t),
			Color(CHARGE.r, CHARGE.g, CHARGE.b, 0.7 * fade), 2.4)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(Vector2(0, ground_y), (10.0 * fade + 3.0), Color(BOLT.r, BOLT.g, BOLT.b, fade))

# ── Persistent: the storm is building (+5% attack speed every 3s) ─────────
# The cloud literally thickens and the flicker quickens with the stack count, so
# "this one has been winding up for a while" is readable without a counter. Kept
# overhead and low-alpha — this sits for the whole fight on a 2x2 body.
func _draw_gathering() -> void:
	if storm <= 0.02:
		return
	var r := reach * 0.5
	var top: float = -ground_y - r * 1.05
	_cloud(top, r * (0.44 + 0.26 * storm), storm, 0.16 + 0.30 * storm)
	# Internal flicker: frequency AND count rise with the ramp.
	var n: int = 1 + int(round(storm * 3.0))
	for i in range(n):
		var phase: float = fposmod(_t * (0.8 + 2.2 * storm) + float(i) / float(n), 1.0)
		if phase > 0.30:
			continue
		var f: float = 1.0 - phase / 0.30
		var x: float = _seeds[i % _seeds.size()] * r * 0.34
		draw_line(Vector2(x, top - r * 0.10), Vector2(x + _seeds[(i + 3) % _seeds.size()] * 8.0, top + r * 0.16),
			Color(BOLT.r, BOLT.g, BOLT.b, 0.65 * f), 1.8 + 1.4 * storm)
	# A faint charge ring at the feet so the state is visible even if the cloud
	# is clipped by a unit standing in front.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	draw_arc(Vector2.ZERO, r * (0.34 + 0.14 * storm), 0.0, TAU, 24,
		Color(CHARGE.r, CHARGE.g, CHARGE.b, 0.16 + 0.30 * storm), 1.6 + 1.4 * storm)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
