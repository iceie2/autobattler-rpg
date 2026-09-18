extends Node2D
class_name RatVFX

# The Rat's visual language: PLAGUE, not fire.
#
# Its signature move applies a damage-over-time through the shared `burn`
# plumbing, and burn's only visual was a one-shot orange SkillEffect.BURN puff at
# cast time. That was wrong twice over: a disease that looks like fire reads as
# the wrong mechanic, and a THREE-SECOND effect with a 0.4s visual means the
# player watches damage numbers appear out of nowhere for the rest of it. DISEASE
# below is persistent for exactly as long as the DoT actually runs.
#
# Palette is deliberately sickly — desaturated bile green and jaundiced yellow —
# so it cannot be confused with Static's electric yellow, Nemi's water, the
# Wind-Up Bot's brass, or the fire it used to borrow.
#
# Layering follows the house rule: broad low-alpha haze, readable coloured body,
# bright focal core.

enum Mode { BITE_WINDUP, BITE_IMPACT, DISEASE, INFEST }

const BILE := Color(0.44, 0.62, 0.18)
const BILE_DARK := Color(0.13, 0.17, 0.05)
const SICK := Color(0.90, 0.92, 0.46)
const CORE := Color(0.93, 0.98, 0.72)

var mode: Mode = Mode.BITE_IMPACT
var elapsed := 0.0
var lifetime := 0.4
var host = null                 # unit this effect is anchored to (persistent modes)
var reach := 74.0
var pack_strength := 0.0        # INFEST: 0..1
var ground_y := 40.0            # INFEST: foot line, set from the host at setup
var _spin := 0.0
var _rng := RandomNumberGenerator.new()
var _seeds: Array = []

func _ready() -> void:
	# Fixed seed per instance so the mote scatter is stable frame to frame
	# (a fresh randf() every _draw would make the cloud boil).
	_rng.seed = int(get_instance_id()) & 0x7fffffff
	for i in range(14):
		_seeds.append(Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)))

func setup_point(kind: Mode, world_pos: Vector2, size: float, life: float) -> void:
	mode = kind
	global_position = world_pos
	reach = size
	lifetime = life
	z_index = 4
	queue_redraw()

func setup_windup(caster, size: float, life: float) -> void:
	mode = Mode.BITE_WINDUP
	host = caster
	reach = size
	lifetime = life
	z_index = 3
	queue_redraw()

# Persistent plague cloud. Lives as long as the DoT does — the manager frees it
# when burn_time runs out, which is why lifetime is infinite here.
func setup_disease(victim, size: float) -> void:
	mode = Mode.DISEASE
	host = victim
	reach = size
	lifetime = INF
	z_index = 4
	queue_redraw()

# Persistent pack marker. Infestation is a POSITIONAL buff, so the one thing the
# player needs to see is which rats are currently clustered — that is the whole
# counterplay ("break up the swarm" / "do not let them group").
func setup_infest(rat, size: float) -> void:
	mode = Mode.INFEST
	host = rat
	reach = size
	# Anchor the ring at the unit's FEET. A unit's origin sits around its middle,
	# so a small fixed offset left the ring floating at waist height (measured in
	# the first capture). shape_size * 0.72 is the same foot line the status-icon
	# row uses, so the ring lands on the ground for any body size.
	if rat and "shape_size" in rat:
		ground_y = float(rat.shape_size) * 0.72
	lifetime = INF
	z_index = 2
	queue_redraw()

func set_pack_strength(v: float) -> void:
	pack_strength = clampf(v, 0.0, 1.0)
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	_spin += delta * 1.5
	if mode in [Mode.BITE_WINDUP, Mode.DISEASE, Mode.INFEST]:
		if not (host and is_instance_valid(host)):
			queue_free()
			return
		global_position = host.global_position
	if elapsed >= lifetime:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	match mode:
		Mode.BITE_WINDUP: _draw_windup(t)
		Mode.BITE_IMPACT: _draw_bite(t)
		Mode.DISEASE:     _draw_disease()
		Mode.INFEST:      _draw_infest()

# ── Anticipation: the rat coils and bares its teeth ──────────────────────────
# Short and low — this is a 75hp skirmisher, not a siege engine. It needs just
# enough tell to be readable, not the Hill Giant's half-second commitment.
func _draw_windup(t: float) -> void:
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * (0.34 + t * 0.20), Color(BILE.r, BILE.g, BILE.b, 0.08 + t * 0.12))
	# Two fang arcs closing toward each other — the jaw opening to strike.
	var gap: float = (1.0 - t) * 0.9 + 0.12
	for s in [-1.0, 1.0]:
		var a0: float = -PI * 0.5 + s * gap
		draw_arc(Vector2.ZERO, r * 0.52, a0 - 0.5, a0 + 0.5, 12,
			Color(SICK.r, SICK.g, SICK.b, 0.45 + t * 0.45), 3.0 + t * 1.4)
	draw_circle(Vector2.ZERO, (5.0 + 5.0 * t), Color(CORE.r, CORE.g, CORE.b, 0.40 + t * 0.45))

# ── Contact: the fangs snap shut and the infection goes in ───────────────────
func _draw_bite(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * (0.42 + 0.55 * t), Color(BILE.r, BILE.g, BILE.b, 0.22 * fade))
	# Fang marks: two short converging gashes, the unmistakable bite read.
	for s in [-1.0, 1.0]:
		var dir := Vector2(s * 0.55, -0.83)
		draw_line(dir * r * 0.18, dir * r * (0.30 + 0.34 * t),
			Color(BILE_DARK.r, BILE_DARK.g, BILE_DARK.b, 0.92 * fade), 5.0 * fade + 1.0)
		draw_line(-dir * r * 0.18, -dir * r * (0.30 + 0.34 * t),
			Color(BILE_DARK.r, BILE_DARK.g, BILE_DARK.b, 0.92 * fade), 5.0 * fade + 1.0)
	# Infection spray — a few motes thrown clear, seeding the cloud that follows.
	for i in range(_seeds.size()):
		var p: Vector2 = _seeds[i] * r * (0.30 + 0.70 * t)
		draw_circle(p, (2.6 + float(i % 3)) * fade, Color(SICK.r, SICK.g, SICK.b, 0.85 * fade))
	draw_circle(Vector2.ZERO, (14.0 * fade + 3.0), Color(BILE.r, BILE.g, BILE.b, 0.50 * fade))
	draw_circle(Vector2.ZERO, (6.0 * fade + 2.0), Color(CORE.r, CORE.g, CORE.b, fade))

# ── Persistent: the victim is diseased, and stays visibly diseased ───────────
# Motes drift UPWARD off the body on a slow loop. Kept low-alpha and small: this
# can sit on several heroes at once and must never compete with health bars or
# damage numbers for attention.
func _draw_disease() -> void:
	var r := reach * 0.5
	# 1. broad, very low alpha sickly haze clinging to the body.
	var breathe: float = 0.5 + 0.5 * sin(_spin * 1.6)
	draw_circle(Vector2.ZERO, r * (0.52 + 0.06 * breathe),
		Color(BILE.r, BILE.g, BILE.b, 0.09 + 0.05 * breathe))
	# 2. readable body: motes rising and fading, each on its own phase.
	# Every mote carries a DARK rim under a pale core. Without it the cloud was
	# nearly invisible on a green-bodied victim (measured against a Goblin, which
	# is the most common early target there is) — a bile-green mote on bile-green
	# skin reads as nothing. The dark rim gives it an edge on ANY body colour,
	# which is the only way a status can be legible on an arbitrary sprite.
	for i in range(_seeds.size()):
		var phase: float = fposmod(_spin * 0.55 + float(i) / float(_seeds.size()), 1.0)
		var sx: float = _seeds[i].x * r * 0.46
		var sy: float = r * 0.34 - phase * r * 0.92
		var a: float = (1.0 - phase) * 0.78
		var p := Vector2(sx + sin(phase * 6.0 + float(i)) * 3.5, sy)
		var rad: float = 1.8 + 1.7 * (1.0 - phase)
		draw_circle(p, rad + 1.5, Color(BILE_DARK.r, BILE_DARK.g, BILE_DARK.b, a * 0.85))
		draw_circle(p, rad, Color(SICK.r, SICK.g, SICK.b, a))
	# 3. focal core: a dim pustular glow at the bite site, pulsing with the ticks.
	draw_circle(Vector2(0, r * 0.10), 4.0 + 1.6 * breathe,
		Color(BILE.r, BILE.g, BILE.b, 0.34 + 0.20 * breathe))

# ── Persistent: this rat is currently part of a swarm ───────────────────────
# Deliberately a GROUND ring rather than an overhead badge: Infestation is about
# where the rats are standing, so the tell belongs on the floor between them.
func _draw_infest() -> void:
	if pack_strength <= 0.0:
		return
	var r: float = reach * 0.5 * (0.72 + 0.28 * pack_strength)
	var a: float = 0.16 + 0.26 * pack_strength
	# Squashed to sit flat on the perspective board rather than standing upright.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, r, Color(BILE_DARK.r, BILE_DARK.g, BILE_DARK.b, a * 0.45))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(BILE.r, BILE.g, BILE.b, a + 0.18), 2.4)
	# Skittering ticks around the ring — more of them the bigger the swarm.
	var n: int = 4 + int(round(pack_strength * 5.0))
	for i in range(n):
		var ang: float = _spin * 0.9 + float(i) * TAU / float(n)
		draw_circle(Vector2(cos(ang), sin(ang)) * r * 0.86, 2.6,
			Color(SICK.r, SICK.g, SICK.b, a + 0.34))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
