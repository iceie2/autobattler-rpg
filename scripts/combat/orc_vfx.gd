extends Node2D
class_name OrcVFX

# The Orc's visual language: OVERHEAD SLAM AND CRACKED GROUND.
# A heavy downward wedge plus radiating fracture lines — structurally distinct
# from the Bear's claw rakes, the Minotaur's forward horn thrust and the Wind-Up
# Bot's brass gears. Where those cut, gore and punch, this one DROPS weight.
#
# Palette is bone-white over near-black fractures rather than any warm colour:
# the Orc ships in 6 elemental variants and the shared body art is green, so a
# warm or green effect would disappear into it (this project has hit that trap
# five times). Bone-on-dark reads on every variant.
#
# Bloodrage is a BINARY threshold (below 50% HP), which is the most valuable
# thing here: it had no visual at all, so the moment an Orc became 20% stronger
# was completely silent. BERSERK_TRIGGER fires once on the crossing; ENRAGED
# persists for as long as the state holds.

enum Mode { CRUSH_WINDUP, CRUSH_IMPACT, BERSERK_TRIGGER, ENRAGED }

const BONE := Color(0.95, 0.94, 0.88)
const FRACTURE := Color(0.07, 0.06, 0.07)
const HEAT := Color(0.95, 0.28, 0.18)

var mode: Mode = Mode.CRUSH_IMPACT
var elapsed := 0.0
var lifetime := 0.5
var host = null
var reach := 100.0
var ground_y := 46.0
var _t := 0.0

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

# Fracture lines radiating along the floor, squashed onto the perspective board.
func _fractures(n: int, len: float, a: float, w: float) -> void:
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	for i in range(n):
		var ang: float = float(i) * TAU / float(n) + 0.25
		var d := Vector2(cos(ang), sin(ang))
		var mid: Vector2 = d * len * 0.55 + d.orthogonal() * len * 0.12
		draw_polyline(PackedVector2Array([Vector2.ZERO, mid, d * len]),
			Color(FRACTURE.r, FRACTURE.g, FRACTURE.b, a), w + 1.6)
		draw_polyline(PackedVector2Array([Vector2.ZERO, mid, d * len]),
			Color(BONE.r, BONE.g, BONE.b, a * 0.75), w * 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	match mode:
		Mode.CRUSH_WINDUP:    _draw_windup(t)
		Mode.CRUSH_IMPACT:    _draw_impact(t)
		Mode.BERSERK_TRIGGER: _draw_berserk(t)
		Mode.ENRAGED:         _draw_enraged()

# ── It hauls the weight up ─────────────────────────────────────────────────
# The wedge RISES and the shadow beneath tightens — an unambiguous "something
# heavy is coming down here" that escalates monotonically.
func _draw_windup(t: float) -> void:
	var r := reach * 0.5
	# Ground shadow contracting = the telegraph of where it lands.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	draw_circle(Vector2.ZERO, r * (0.70 - 0.26 * t), Color(FRACTURE.r, FRACTURE.g, FRACTURE.b, 0.20 + 0.28 * t))
	draw_arc(Vector2.ZERO, r * (0.70 - 0.26 * t), 0.0, TAU, 26,
		Color(BONE.r, BONE.g, BONE.b, 0.35 + 0.45 * t), 2.0 + 1.6 * t)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The raised wedge, climbing as it winds up.
	var lift: float = r * (0.30 + 0.55 * t)
	var w: float = r * (0.30 + 0.10 * t)
	draw_line(Vector2(-w, -lift), Vector2(0, -lift - r * 0.20),
		Color(FRACTURE.r, FRACTURE.g, FRACTURE.b, 0.8), 6.0)
	draw_line(Vector2(w, -lift), Vector2(0, -lift - r * 0.20),
		Color(FRACTURE.r, FRACTURE.g, FRACTURE.b, 0.8), 6.0)
	draw_line(Vector2(-w, -lift), Vector2(0, -lift - r * 0.20),
		Color(BONE.r, BONE.g, BONE.b, 0.5 + 0.45 * t), 3.0)
	draw_line(Vector2(w, -lift), Vector2(0, -lift - r * 0.20),
		Color(BONE.r, BONE.g, BONE.b, 0.5 + 0.45 * t), 3.0)

# ── It comes down ──────────────────────────────────────────────────────────
func _draw_impact(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	_fractures(7, r * (0.55 + 0.75 * t), 0.9 * fade, 3.4 * fade + 1.0)
	# Shock ring travelling out along the floor.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	draw_arc(Vector2.ZERO, r * (0.25 + 0.95 * t), 0.0, TAU, 30,
		Color(BONE.r, BONE.g, BONE.b, 0.85 * fade), 4.0 * fade + 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The wedge buried at the contact point.
	var w: float = r * 0.30
	draw_line(Vector2(-w, -r * 0.30 * fade), Vector2.ZERO,
		Color(FRACTURE.r, FRACTURE.g, FRACTURE.b, 0.9 * fade), 6.0 * fade + 1.5)
	draw_line(Vector2(w, -r * 0.30 * fade), Vector2.ZERO,
		Color(FRACTURE.r, FRACTURE.g, FRACTURE.b, 0.9 * fade), 6.0 * fade + 1.5)
	draw_circle(Vector2.ZERO, (8.0 * fade + 2.0), Color(BONE.r, BONE.g, BONE.b, fade))

# ── The moment it drops below half and goes berserk ───────────────────────
# One-shot, fired on the threshold crossing. The whole point of a BINARY buff is
# that the flip is an event; without this the Orc silently became 20% stronger.
func _draw_berserk(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	# A hard outward shout ring plus heat flooding up the body.
	draw_arc(Vector2.ZERO, r * (0.30 + 1.10 * t), 0.0, TAU, 32,
		Color(HEAT.r, HEAT.g, HEAT.b, 0.9 * fade), 5.0 * fade + 1.2)
	draw_arc(Vector2.ZERO, r * (0.30 + 1.10 * t), 0.0, TAU, 32,
		Color(BONE.r, BONE.g, BONE.b, 0.55 * fade), 2.0 * fade + 0.6)
	for i in range(8):
		var a: float = float(i) * TAU / 8.0 + 0.2
		var d := Vector2(cos(a), sin(a))
		draw_line(d * r * (0.20 + 0.35 * t), d * r * (0.45 + 0.70 * t),
			Color(HEAT.r, HEAT.g, HEAT.b, 0.85 * fade), 3.4 * fade + 0.8)
	draw_circle(Vector2.ZERO, (14.0 * fade + 3.0), Color(HEAT.r, HEAT.g, HEAT.b, 0.7 * fade))
	draw_circle(Vector2.ZERO, (6.0 * fade + 2.0), Color(BONE.r, BONE.g, BONE.b, fade))

# ── Persistent: it is below half and hitting harder ───────────────────────
# Ground-anchored heat so it never fights the health bar, and deliberately calm
# compared with the trigger — this can sit for the rest of the fight.
func _draw_enraged() -> void:
	var r := reach * 0.5
	var pulse: float = 0.5 + 0.5 * sin(_t * 3.2)
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	draw_circle(Vector2.ZERO, r * (0.46 + 0.04 * pulse),
		Color(HEAT.r, HEAT.g, HEAT.b, 0.12 + 0.08 * pulse))
	draw_arc(Vector2.ZERO, r * 0.46, 0.0, TAU, 26,
		Color(HEAT.r, HEAT.g, HEAT.b, 0.40 + 0.25 * pulse), 2.2)
	# Radial ticks around the ring. Structure, not just colour: the Bear's bleed
	# pool is also a red shape at a unit's feet and they share waves (Bear rd 6,
	# Orc rd 7), so this needs to be distinguishable at a glance rather than
	# relying on hue alone.
	for i in range(8):
		var ta: float = float(i) * TAU / 8.0 + _t * 0.5
		var td := Vector2(cos(ta), sin(ta))
		draw_line(td * r * 0.34, td * r * (0.50 + 0.05 * pulse),
			Color(HEAT.r, HEAT.g, HEAT.b, 0.45 + 0.30 * pulse), 2.4)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Heat licking up off the shoulders.
	for i in range(4):
		var f: float = fposmod(_t * 1.1 + float(i) / 4.0, 1.0)
		var x: float = (float(i) - 1.5) * r * 0.24
		draw_circle(Vector2(x + sin(f * 5.0 + float(i)) * 3.0, r * 0.08 - f * r * 0.50),
			2.0 + 2.2 * (1.0 - f), Color(HEAT.r, HEAT.g, HEAT.b, (1.0 - f) * 0.45))
