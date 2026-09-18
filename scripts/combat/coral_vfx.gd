extends Node2D
class_name CoralVFX

# The Coral Husk's visual language: BRANCHING REEF GROWTH.
#
# Coral polyps sprouting in little forked branches, in salmon-pink over pale
# teal. Three separations were deliberate:
#   • the Crystal Crab's shell is flat straight FACETS — this is organic and
#     branching, so two shielding mobs never read alike;
#   • the Skeleton's shards are hard angular splinters, this is soft and knobbly;
#   • Nemi's water is flowing blue — reef pink is unmistakably not her.
#
# Calcify and Slow Tide are named differently from the keys they ride
# (skeleton_boneshield, windup_overclock), so per the name-match rule this gets
# its own language rather than a scaled copy of the owner's.

enum Mode { CALCIFY, SLOW_TIDE }

const CORAL := Color(0.96, 0.55, 0.48)
const TEAL := Color(0.38, 0.80, 0.78)
const DARK := Color(0.09, 0.18, 0.20)
const PALE := Color(0.98, 0.92, 0.86)

var mode: Mode = Mode.CALCIFY
var elapsed := 0.0
var lifetime := 0.5
var host = null
var reach := 92.0
var tide := 0.0              # SLOW_TIDE: 0..1 across the +0%..+50% ramp
var ground_y := 46.0
var _t := 0.0
var _seeds: Array = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_instance_id()) & 0x7fffffff
	for i in range(10):
		_seeds.append(rng.randf_range(-1.0, 1.0))

func setup_on(kind: Mode, unit, size: float, life: float) -> void:
	mode = kind
	host = unit
	reach = size
	lifetime = life
	z_index = 3
	if unit and "shape_size" in unit:
		ground_y = float(unit.shape_size) * 0.72
	queue_redraw()

func set_tide(v: float) -> void:
	tide = clampf(v, 0.0, 1.0)
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

# One coral branch: a short stem that forks twice, with a dark rim so it reads
# on any body colour.
func _branch(base: Vector2, dir: Vector2, len: float, a: float, w: float) -> void:
	var mid: Vector2 = base + dir * len * 0.55
	draw_line(base, mid, Color(DARK.r, DARK.g, DARK.b, a * 0.9), w + 2.0)
	draw_line(base, mid, Color(CORAL.r, CORAL.g, CORAL.b, a), w)
	for s in [-1.0, 1.0]:
		var fork: Vector2 = mid + dir.rotated(s * 0.6) * len * 0.45
		draw_line(mid, fork, Color(DARK.r, DARK.g, DARK.b, a * 0.9), w + 1.4)
		draw_line(mid, fork, Color(CORAL.r, CORAL.g, CORAL.b, a), w * 0.75)
		draw_circle(fork, w * 0.8, Color(PALE.r, PALE.g, PALE.b, a))

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	match mode:
		Mode.CALCIFY:   _draw_calcify(t)
		Mode.SLOW_TIDE: _draw_slow_tide()

# ── Calcify: reef crusts over the body ────────────────────────────────────
# Branches GROW outward over the cast, so the shell visibly accretes rather than
# popping into existence.
func _draw_calcify(t: float) -> void:
	var r := reach * 0.5
	var fade := 1.0 - t
	draw_circle(Vector2.ZERO, r * (0.40 + 0.14 * t), Color(TEAL.r, TEAL.g, TEAL.b, 0.10 + 0.12 * t))
	var n := 7
	for i in range(n):
		var a0: float = float(i) * TAU / float(n) + 0.2
		var d := Vector2(cos(a0), sin(a0))
		_branch(d * r * 0.34, d, r * 0.34 * t, 0.40 + 0.55 * t, 2.4)
	# A teal wash sweeping around as the crust sets.
	draw_arc(Vector2.ZERO, r * 0.50, _t * 1.4, _t * 1.4 + PI * 0.8, 16,
		Color(TEAL.r, TEAL.g, TEAL.b, 0.45 * (0.4 + 0.6 * t)), 2.6)
	if t > 0.80:
		var f: float = (t - 0.80) / 0.20
		draw_arc(Vector2.ZERO, r * 0.52, 0.0, TAU, 28,
			Color(PALE.r, PALE.g, PALE.b, 0.75 * (1.0 - f)), 2.4)

# ── Slow Tide: the reef creeps forward and speeds up ─────────────────────
# Same +5%/3s ramp as the Wind-Up Bot's Overclock, but the fiction is a rising
# tide, so it reads as water level rather than clockwork. Ground-anchored and
# low-alpha — it sits for the whole fight.
func _draw_slow_tide() -> void:
	if tide <= 0.02:
		return
	var r := reach * 0.5
	var swell: float = 0.5 + 0.5 * sin(_t * (1.0 + 2.4 * tide))
	# Tide line at the feet, rising up the body as the ramp climbs.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	draw_circle(Vector2.ZERO, r * (0.40 + 0.26 * tide),
		Color(TEAL.r, TEAL.g, TEAL.b, 0.10 + 0.16 * tide))
	draw_arc(Vector2.ZERO, r * (0.40 + 0.26 * tide), 0.0, TAU, 26,
		Color(TEAL.r, TEAL.g, TEAL.b, 0.30 + 0.35 * tide), 1.8 + 1.6 * tide)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The waterline creeping UP the body — the clearest read of "how far along".
	var line_y: float = ground_y - tide * (ground_y + r * 0.42)
	draw_line(Vector2(-r * 0.34, line_y), Vector2(r * 0.34, line_y),
		Color(TEAL.r, TEAL.g, TEAL.b, 0.30 + 0.35 * tide), 2.0 + 1.4 * tide)
	# Coral growth thickening along that line as the tide rises.
	var n: int = 1 + int(round(tide * 4.0))
	for i in range(n):
		var x: float = _seeds[i % _seeds.size()] * r * 0.30
		_branch(Vector2(x, line_y), Vector2(0, -1).rotated(_seeds[(i + 2) % _seeds.size()] * 0.5),
			r * (0.10 + 0.12 * tide) * (0.7 + 0.3 * swell), 0.35 + 0.40 * tide, 1.8)
