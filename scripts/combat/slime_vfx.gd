extends Node2D
class_name SlimeVFX

# The Slime's visual language: VISCOUS. Everything here is built from heavy
# droplets, sagging meniscus curves and rising bubbles — deliberately different
# SHAPES from the Rat's rising plague motes, because the two can share a screen
# and both sit in the green part of the palette.
#
# Colour comes from the unit's ELEMENT (the Slime ships in 6 variants and it IS
# its element), over a constant dark rim so a droplet stays readable on any body.
#
# Three gaps this fills, all flagged in the audit:
#   • Corrosive Goo resolved instantly with a generic SkillEffect.ABSORBED puff.
#   • The 3s weaken it applies had NO persistent visual at all — only `stun` is
#     in STATUS_ICON_SHEETS, so a debuffed hero looked completely normal.
#   • Split — a slime dying and becoming two — was rendered SILENTLY.

enum Mode { GOO_WINDUP, GOO_SPLAT, CORRODED, SPLIT }

const RIM := Color(0.10, 0.14, 0.09)
const SHEEN := Color(0.95, 1.0, 0.90)
# SynergyData.element_color(NORMAL) is a neutral light grey, which is correct for
# an abstract element chip but WRONG here: the Normal Slime's art is green, so
# grey halves tearing off it read as bubbles sitting ON the body rather than as
# the body coming apart (measured in the split capture). The other five variants
# already match their sprites, so only NORMAL is overridden.
const NORMAL_SLIME := Color(0.45, 0.78, 0.30)

static func _slime_tint(element: int) -> Color:
	if element == UnitBase.Element.NORMAL:
		return NORMAL_SLIME
	return SynergyData.element_color(element)

var mode: Mode = Mode.GOO_SPLAT
var elapsed := 0.0
var lifetime := 0.4
var host = null
var tint: Color = Color(0.55, 0.85, 0.35)
var reach := 80.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _blobs: Array = []

func _ready() -> void:
	# Fixed per-instance scatter so the goo does not boil between frames.
	_rng.seed = int(get_instance_id()) & 0x7fffffff
	for i in range(10):
		_blobs.append(Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0),
			_rng.randf_range(0.6, 1.6)))

func setup_point(kind: Mode, world_pos: Vector2, element: int, size: float, life: float) -> void:
	mode = kind
	global_position = world_pos
	tint = _slime_tint(element)
	reach = size
	lifetime = life
	z_index = 4
	queue_redraw()

func setup_windup(caster, element: int, size: float, life: float) -> void:
	mode = Mode.GOO_WINDUP
	host = caster
	tint = _slime_tint(element)
	reach = size
	lifetime = life
	z_index = 3
	queue_redraw()

# Persistent while the weaken actually runs — the manager frees it the frame
# weakened_time expires, so it can never outlive the mechanic.
func setup_corroded(victim, element: int, size: float) -> void:
	mode = Mode.CORRODED
	host = victim
	tint = _slime_tint(element)
	reach = size
	lifetime = INF
	z_index = 4
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	_t += delta
	if mode in [Mode.GOO_WINDUP, Mode.CORRODED]:
		if not (host and is_instance_valid(host)):
			queue_free()
			return
		global_position = host.global_position
	if elapsed >= lifetime:
		queue_free()
	else:
		queue_redraw()

# A heavy droplet: dark rim, element body, small offset sheen. The rim is what
# keeps it legible against a same-coloured slime or a bright hero.
func _drop(p: Vector2, r: float, a: float) -> void:
	draw_circle(p, r + 1.6, Color(RIM.r, RIM.g, RIM.b, a * 0.85))
	draw_circle(p, r, Color(tint.r, tint.g, tint.b, a))
	draw_circle(p + Vector2(-r * 0.3, -r * 0.35), r * 0.32, Color(SHEEN.r, SHEEN.g, SHEEN.b, a * 0.7))

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	match mode:
		Mode.GOO_WINDUP: _draw_windup(t)
		Mode.GOO_SPLAT:  _draw_splat(t)
		Mode.CORRODED:   _draw_corroded()
		Mode.SPLIT:      _draw_split(t)

# ── The slime swells and gathers goo before spitting ────────────────────────
func _draw_windup(t: float) -> void:
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * (0.34 + t * 0.22), Color(tint.r, tint.g, tint.b, 0.07 + t * 0.13))
	# Droplets pulled INWARD to the mouth — the gather, and the countdown.
	for i in range(_blobs.size()):
		var b: Vector3 = _blobs[i]
		var d := Vector2(b.x, b.y).normalized()
		var dist: float = r * (0.85 - t * 0.55)
		_drop(d * dist, 2.2 * b.z, 0.35 + 0.5 * t)
	# A swelling bead at the mouth: the thing about to be spat.
	_drop(Vector2(0, r * 0.05), 4.0 + 7.0 * t, 0.55 + 0.4 * t)

# ── It lands and eats into them ─────────────────────────────────────────────
func _draw_splat(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * (0.45 + 0.6 * t), Color(tint.r, tint.g, tint.b, 0.22 * fade))
	# Splash crown: droplets thrown outward and DOWN, so it reads as heavy liquid
	# rather than an outward energy burst.
	for i in range(_blobs.size()):
		var b: Vector3 = _blobs[i]
		var d := Vector2(b.x, b.y).normalized()
		var p: Vector2 = d * r * (0.25 + 0.85 * t) + Vector2(0, t * t * 20.0)
		_drop(p, (2.0 + b.z * 1.8) * fade, 0.9 * fade)
	draw_circle(Vector2.ZERO, (16.0 * fade + 4.0), Color(tint.r, tint.g, tint.b, 0.55 * fade))
	draw_circle(Vector2.ZERO, (7.0 * fade + 2.0), Color(SHEEN.r, SHEEN.g, SHEEN.b, fade))

# ── Persistent: this unit is corroded and hitting softer ────────────────────
# Sits LOW on the body and drips downward, so it never competes with the health
# bar above or the status-icon row below.
func _draw_corroded() -> void:
	var r := reach * 0.5
	var pulse: float = 0.5 + 0.5 * sin(_t * 2.2)
	draw_circle(Vector2(0, r * 0.22), r * (0.40 + 0.04 * pulse),
		Color(tint.r, tint.g, tint.b, 0.10 + 0.05 * pulse))
	# Droplets sagging off the body on independent phases, each resetting at the
	# bottom — a continuous drip rather than a one-shot splash.
	for i in range(_blobs.size()):
		var b: Vector3 = _blobs[i]
		var phase: float = fposmod(_t * 0.5 + float(i) / float(_blobs.size()), 1.0)
		var x: float = b.x * r * 0.42
		var y: float = -r * 0.10 + phase * r * 0.62
		_drop(Vector2(x, y), 1.6 + 1.3 * (1.0 - phase) * b.z, (1.0 - phase) * 0.72)
	# A pitted meniscus clinging under the body: the "eaten into" read.
	var w := r * 0.46
	for i in range(5):
		var f := (float(i) + 0.5) / 5.0
		var px: float = lerp(-w, w, f)
		var sag: float = sin(f * PI) * 5.0
		draw_circle(Vector2(px, r * 0.22 + sag), 2.4 + sin(_t * 3.0 + float(i)) * 0.6,
			Color(tint.r, tint.g, tint.b, 0.55))

# ── Split: the body bursts and comes apart ─────────────────────────────────
# The one beat that had NOTHING. Two halves visibly tear away from a rupturing
# core, so "it became two" is legible without reading the unit list.
func _draw_split(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * (0.5 + 0.8 * t), Color(tint.r, tint.g, tint.b, 0.13 * fade))
	# A hard rupture flash on the first beat: without it the halves emerging from
	# behind the parent sprite read as bubbles ON the body rather than as the
	# body coming apart (measured in the first capture).
	if t < 0.35:
		var f: float = 1.0 - t / 0.35
		draw_circle(Vector2.ZERO, r * (0.30 + 0.5 * (1.0 - f)), Color(SHEEN.r, SHEEN.g, SHEEN.b, 0.8 * f))
	# The two halves pulling apart along the horizontal. They must travel CLEAR
	# of the parent silhouette — at the original 0.85r they stopped inside it.
	for s in [-1.0, 1.0]:
		var c := Vector2(s * r * (0.18 + 1.25 * t), sin(t * PI) * -10.0)
		draw_circle(c, (r * 0.34) * (0.6 + 0.4 * fade) + 2.0,
			Color(RIM.r, RIM.g, RIM.b, 0.8 * fade))
		draw_circle(c, (r * 0.34) * (0.6 + 0.4 * fade),
			Color(tint.r, tint.g, tint.b, 0.92 * fade))
		draw_circle(c + Vector2(-r * 0.10, -r * 0.12), r * 0.10,
			Color(SHEEN.r, SHEEN.g, SHEEN.b, 0.75 * fade))
	# Strands still connecting them mid-tear, and flung droplets.
	if t < 0.6:
		var strand: float = 1.0 - t / 0.6
		for i in range(3):
			var y: float = (float(i) - 1.0) * 5.0
			draw_line(Vector2(-r * (0.15 + 0.85 * t) * 0.6, y),
				Vector2(r * (0.15 + 0.85 * t) * 0.6, y),
				Color(tint.r, tint.g, tint.b, 0.55 * strand), 2.6 * strand + 0.6)
	for i in range(_blobs.size()):
		var b: Vector3 = _blobs[i]
		var d := Vector2(b.x, b.y).normalized()
		_drop(d * r * (0.3 + 1.0 * t) + Vector2(0, t * t * 26.0), 2.0 * b.z * fade, 0.85 * fade)
