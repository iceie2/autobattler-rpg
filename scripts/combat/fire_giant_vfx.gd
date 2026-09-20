extends Node2D
class_name FireGiantVFX

# The Fire Giant's visual language: A FORGE HAMMER AND WHITE-HOT METAL.
#
# It rides `brute_crush` / `orc_rage` like the Orc and the Ogre, but its ability
# names are its own — "Molten Smash" and "Forge Fury", not "Crushing Blow" and
# "Bloodrage" — so by the name-match rule it gets its own fiction rather than the
# Orc's bone-white slam.
#
# PALETTE, and this one is the whole problem with this unit: the Fire Giant's
# sprite is DARK BASALT ALREADY COVERED IN GLOWING ORANGE MOLTEN CRACKS, plus
# orange flames at the shoulders. Orange lava is not a contrasting effect on this
# body — it is the body. Drawing Forge Fury as glowing orange cracks would be
# literally indistinguishable from its idle art, which is the eighth-and-worst
# instance of the trap this project keeps hitting.
#
# So the separation is VALUE, not hue. A forge does not make metal more orange,
# it drives it past orange to WHITE-HOT. That reads as a large brightness jump
# against both the dark basalt and its own mid-orange cracks, and it is exactly
# what the fiction already promises. Orange is demoted to a falloff colour only —
# never the readable layer.
#
# Shape separation from the Orc, which shares the key: the Orc DROPS weight
# (downward wedge + radiating ground fractures). This one SWINGS a hammer — an
# arc, a struck-anvil flash, and a directional spray of sparks.

enum Mode { SMASH_WINDUP, SMASH_IMPACT, FORGE_TRIGGER, FORGE_FURY }

# The readable layer: white-hot, barely tinted. Against mid-orange body cracks
# this separates on brightness even where the hue is close.
const WHITE_HOT := Color(1.0, 0.97, 0.88)
const EMBER := Color(1.0, 0.55, 0.15)   # falloff only, never the focal layer
const BASALT := Color(0.09, 0.07, 0.07)

var mode: Mode = Mode.SMASH_IMPACT
var elapsed := 0.0
var lifetime := 0.5
var host = null
var reach := 150.0
var ground_y := 72.0
var _t := 0.0
var _seeds: Array = []

# Vertical centre of the BODY relative to this node's origin.
#
# Measured, not assumed: on the real board a 2x2 giant's origin sits near its
# feet, so the first two passes drew the shoulder seams and the trigger ring
# around Vector2.ZERO and put both across its legs. The body spans roughly
# -1.45r to +0.35r, so its middle is about -0.6r.
func _body_c() -> float:
	return -reach * 0.5 * 0.60

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_instance_id()) & 0x7fffffff
	for i in range(12):
		_seeds.append(Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(0.2, 1.0)))

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

# A spark: a short white-hot streak, not a round mote. Struck metal throws
# LINES, which also keeps it clear of the Rat's and Wyvern's DoT particles.
func _spark(p: Vector2, dir: Vector2, len_px: float, a: float) -> void:
	draw_line(p, p + dir * len_px, Color(EMBER.r, EMBER.g, EMBER.b, a * 0.55), 2.6)
	draw_line(p, p + dir * len_px * 0.6, Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, a), 1.3)

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	match mode:
		Mode.SMASH_WINDUP:  _draw_windup(t)
		Mode.SMASH_IMPACT:  _draw_impact(t)
		Mode.FORGE_TRIGGER: _draw_trigger(t)
		Mode.FORGE_FURY:    _draw_fury()

# ── Anticipation: the hammer head heats and hauls back ───────────────────────
# The player has ORC_CRUSH_CONTACT to read this and act on it, so it has to be
# unmistakable and it has to grow.
func _draw_windup(t: float) -> void:
	var r := reach * 0.5
	var cy := _body_c()
	# Broad low-alpha heat bloom, the bottom layer of the three-layer build.
	draw_circle(Vector2(0, cy), r * (0.75 + 0.45 * t),
		Color(EMBER.r, EMBER.g, EMBER.b, 0.07 + 0.13 * t))
	# The hammer arc it is winding through, swung around the giant's SHOULDER and
	# scaled to its actual reach — the first pass drew this at a third of the
	# size, centred on the origin, so it landed as a white speck on the belt.
	var pivot := Vector2(0, cy - r * 0.30)
	var a0: float = -PI * 0.10 - t * 0.95
	var a1: float = a0 + 1.0
	var rad: float = r * (0.95 + 0.22 * t)
	draw_arc(pivot, rad, a0, a1, 22,
		Color(BASALT.r, BASALT.g, BASALT.b, 0.30 + 0.25 * t), 9.0)
	draw_arc(pivot, rad, a0, a1, 22,
		Color(EMBER.r, EMBER.g, EMBER.b, 0.35 + 0.40 * t), 6.0)
	draw_arc(pivot, rad, a0, a1, 22,
		Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.55 + 0.45 * t), 2.6)
	# The head itself going white-hot at the end of the arc.
	var head := pivot + Vector2(cos(a0), sin(a0)) * rad
	draw_circle(head, r * 0.22 * (0.6 + 0.7 * t),
		Color(EMBER.r, EMBER.g, EMBER.b, 0.50 + 0.35 * t))
	draw_circle(head, r * 0.12 * (0.6 + 0.9 * t),
		Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.75 + 0.25 * t))
	# Sparks shed off the head as it heats.
	for i in range(5):
		var sd: Vector2 = _seeds[i]
		_spark(head + sd * r * 0.20, Vector2(sd.x, -absf(sd.y)).normalized(),
			r * 0.24 * t, 0.70 * t)

# ── Release: the head lands ─────────────────────────────────────────────────
func _draw_impact(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	# Spawned at the TARGET, whose origin is also near its feet — so the flash
	# belongs up at chest height while the struck ring stays on the ground.
	var cy := _body_c() * 0.75
	# Struck-anvil flash, hottest on the first frames.
	draw_circle(Vector2(0, cy), r * (0.35 + 0.95 * t),
		Color(EMBER.r, EMBER.g, EMBER.b, 0.34 * fade))
	draw_circle(Vector2(0, cy), r * (0.22 + 0.45 * t) * fade,
		Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.95 * fade))
	# No hammer-head shape here. A filled wedge at the contact point read as a
	# grey CRATE sitting on the target's chest, and it was redundant anyway — the
	# giant's own sprite is already holding the maul. The flash, the struck ring
	# and the spark spray carry the impact.
	# A struck ring on the ground — squashed, so it sits ON the board rather than
	# hovering. Ground effects live above the board art, below the units.
	# A unit's origin sits at its HIP, not its feet (measured), so a ring drawn at
	# y=0 floats at thigh height. The soles are about +0.37r below the origin.
	draw_set_transform(Vector2(0, r * 0.37), 0.0, Vector2(1.0, 0.38))
	draw_arc(Vector2.ZERO, r * (0.45 + 1.35 * t), 0.0, TAU, 32,
		Color(BASALT.r, BASALT.g, BASALT.b, 0.45 * fade), 9.0 * fade + 2.0)
	draw_arc(Vector2.ZERO, r * (0.45 + 1.35 * t), 0.0, TAU, 32,
		Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.85 * fade), 4.0 * fade + 1.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Sparks thrown outward and upward, plus basalt chips knocked loose.
	for i in range(_seeds.size()):
		var sd: Vector2 = _seeds[i]
		var d := Vector2(sd.x, -sd.y * 0.8).normalized()
		var p: Vector2 = Vector2(0, cy) + d * r * (0.35 + 1.15 * t)
		_spark(p, d, r * 0.24 * fade, 0.95 * fade)
		if i % 3 == 0:
			var cp: Vector2 = Vector2(sd.x * r * 0.62, cy - r * 0.10 + t * t * 40.0)
			draw_circle(cp, 3.4 * fade + 1.0, Color(BASALT.r, BASALT.g, BASALT.b, 0.9 * fade))

# ── Forge Fury crossing below 50% HP ────────────────────────────────────────
# A binary threshold that was previously SILENT: the giant simply became 20%
# stronger with nothing on screen. One-shot beat as it lights.
func _draw_trigger(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	# Centred on the BODY and large enough to enclose it.
	var cy := _body_c()
	draw_circle(Vector2(0, cy), r * (0.70 + 1.05 * t),
		Color(EMBER.r, EMBER.g, EMBER.b, 0.34 * fade))
	draw_arc(Vector2(0, cy), r * (0.70 + 1.05 * t), 0.0, TAU, 34,
		Color(BASALT.r, BASALT.g, BASALT.b, 0.50 * fade), 9.0 * fade + 2.0)
	draw_arc(Vector2(0, cy), r * (0.70 + 1.05 * t), 0.0, TAU, 34,
		Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.95 * fade), 4.5 * fade + 1.5)
	# The forge taking: sparks blown straight up off the whole body.
	for i in range(_seeds.size()):
		var sd: Vector2 = _seeds[i]
		var p: Vector2 = Vector2(sd.x * r * 0.62, cy + r * 0.70 - t * (r * 1.60 + 30.0) * sd.y)
		_spark(p, Vector2(sd.x * 0.35, -1.0).normalized(), r * 0.20 * fade, 0.95 * fade)

# ── Persistent: Forge Fury is running ───────────────────────────────────────
# Must survive a whole fight on screen without becoming noise, and must stay
# readable against a body that is ALREADY orange-cracked. So: no added orange
# glow on the body at all. Instead white-hot seams at the shoulders and a slow
# updraft of white sparks — brightness the idle art never reaches.
func _draw_fury() -> void:
	var r := reach * 0.5
	var pulse: float = 0.5 + 0.5 * sin(_t * 2.6)
	# White-hot shoulder CAPS. These were straight seams first, which on the real
	# board read as two crossed sticks laid over the giant rather than as heat in
	# its own shoulders — an arc that follows the shoulder line reads as part of
	# the body instead of an object sitting on it.
	var cy := _body_c()
	for s in [-1.0, 1.0]:
		var c: Vector2 = Vector2(s * r * 0.42, cy - r * 0.34)
		var a0: float = -PI * 0.95 if s < 0.0 else -PI * 0.05
		var a1: float = a0 + (0.85 if s < 0.0 else -0.85)
		draw_arc(c, r * 0.30, minf(a0, a1), maxf(a0, a1), 16,
			Color(BASALT.r, BASALT.g, BASALT.b, 0.50), 11.0)
		draw_arc(c, r * 0.30, minf(a0, a1), maxf(a0, a1), 16,
			Color(EMBER.r, EMBER.g, EMBER.b, 0.55 + 0.30 * pulse), 7.5)
		draw_arc(c, r * 0.30, minf(a0, a1), maxf(a0, a1), 16,
			Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.90 + 0.10 * pulse), 3.4)
	# A slow rising column of white sparks spanning the WHOLE body — the tell
	# that reads even when the giant is stationary and its art is already busy.
	for i in range(_seeds.size()):
		var sd: Vector2 = _seeds[i]
		var phase: float = fposmod(_t * 0.5 + float(i) / float(_seeds.size()), 1.0)
		var p: Vector2 = Vector2(sd.x * r * 0.52, cy + r * 0.72 - phase * (r * 1.55))
		_spark(p, Vector2(sd.x * 0.3, -1.0).normalized(), r * 0.20,
			0.55 + (1.0 - phase) * 0.45)
	# Heat working the ground at its feet. A dark under-stroke first: pure white
	# on sunlit grass washes out, so every bright line needs something to sit on.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.38))
	draw_arc(Vector2.ZERO, r * (0.52 + 0.04 * pulse), 0.0, TAU, 30,
		Color(BASALT.r, BASALT.g, BASALT.b, 0.45), 6.0)
	draw_arc(Vector2.ZERO, r * (0.52 + 0.04 * pulse), 0.0, TAU, 30,
		Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.60 + 0.30 * pulse), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
