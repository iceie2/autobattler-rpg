extends Node2D
class_name HarpyVFX

# "Talon Rake" — thin curved talon slashes with a few shed feathers.
#
# Shares `bear_swipe` with the Bear, but the Bear's move is "Rending Swipe" and
# this is "Talon Rake", so by the name-match rule it gets its own look. The two
# are deliberately different SHAPES: the Bear's are three straight parallel
# gashes (a heavy paw); these are thin, curved, converging talon arcs (a fast
# grab). The Gargoyle's skill is ALSO named "Talon Rake", so it shares this one
# — see the `talon_vfx_reach` meta.

enum Mode { RAKE_WINDUP, RAKE_IMPACT }

const TALON := Color(0.92, 0.95, 0.99)
const SHADE := Color(0.10, 0.13, 0.18)
const PLUME := Color(0.62, 0.72, 0.86)

var mode: Mode = Mode.RAKE_IMPACT
var elapsed := 0.0
var lifetime := 0.42
var host = null
var reach := 84.0
var _t := 0.0
var _seeds: Array = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_instance_id()) & 0x7fffffff
	for i in range(6):
		_seeds.append(Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)))

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

# One curved talon arc — a shallow crescent, not a straight gash.
func _talon(centre: Vector2, radius: float, a0: float, sweep: float, a: float, w: float) -> void:
	draw_arc(centre, radius, a0, a0 + sweep, 12, Color(SHADE.r, SHADE.g, SHADE.b, a * 0.9), w + 2.2)
	draw_arc(centre, radius, a0, a0 + sweep, 12, Color(TALON.r, TALON.g, TALON.b, a), w)

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	match mode:
		Mode.RAKE_WINDUP: _draw_windup(t)
		Mode.RAKE_IMPACT: _draw_impact(t)

# ── Talons spread before the grab ─────────────────────────────────────────
func _draw_windup(t: float) -> void:
	var r := reach * 0.5
	for i in range(3):
		var a0: float = -PI * 0.75 + float(i) * 0.34 - t * 0.25
		_talon(Vector2.ZERO, r * (0.42 + 0.10 * t), a0, 0.55 + 0.25 * t, 0.35 + 0.45 * t, 2.0 + 1.0 * t)
	draw_circle(Vector2.ZERO, 2.5 + 3.0 * t, Color(TALON.r, TALON.g, TALON.b, 0.35 + 0.35 * t))

# ── The rake lands ────────────────────────────────────────────────────────
func _draw_impact(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	# Three CONVERGING curved slashes — the grab closing, not a flat swipe.
	for i in range(3):
		var a0: float = -PI * 0.85 + float(i) * 0.40 + t * 0.55
		_talon(Vector2(0, -r * 0.05), r * (0.46 + 0.42 * t), a0, 0.62,
			0.95 * fade, 3.4 * fade + 1.0)
	# A few shed feathers drifting off — the one soft element, so it does not
	# read as a metal weapon strike.
	for i in range(_seeds.size()):
		var sd: Vector2 = _seeds[i]
		var p: Vector2 = sd.normalized() * r * (0.30 + 0.80 * t) + Vector2(0, t * t * 14.0)
		var d := sd.normalized().orthogonal() * (5.0 + 3.0 * absf(sd.x))
		draw_line(p - d, p + d, Color(PLUME.r, PLUME.g, PLUME.b, 0.75 * fade), 2.0)
	draw_circle(Vector2.ZERO, (7.0 * fade + 2.0), Color(TALON.r, TALON.g, TALON.b, fade))
