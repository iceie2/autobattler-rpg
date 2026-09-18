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
	# Broad low-alpha heat bloom, the bottom layer of the three-layer build.
	draw_circle(Vector2(0, -r * 0.10), r * (0.30 + 0.26 * t),
		Color(EMBER.r, EMBER.g, EMBER.b, 0.05 + 0.10 * t))
	# The hammer arc it is winding through: a wedge sweeping up and back, drawn
	# as an arc so the direction of the coming swing is legible.
	var a0: float = -PI * 0.15 - t * 0.85
	var a1: float = a0 + 0.9
	draw_arc(Vector2(0, -r * 0.16), r * (0.46 + 0.10 * t), a0, a1, 18,
		Color(EMBER.r, EMBER.g, EMBER.b, 0.30 + 0.35 * t), 5.0)
	draw_arc(Vector2(0, -r * 0.16), r * (0.46 + 0.10 * t), a0, a1, 18,
		Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.45 + 0.50 * t), 2.0)
	# The head itself going white-hot at the end of the arc.
	var head := Vector2(0, -r * 0.16) + Vector2(cos(a0), sin(a0)) * r * (0.46 + 0.10 * t)
	draw_circle(head, r * 0.10 * (0.6 + 0.7 * t),
		Color(EMBER.r, EMBER.g, EMBER.b, 0.45 + 0.35 * t))
	draw_circle(head, r * 0.055 * (0.6 + 0.9 * t),
		Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.65 + 0.35 * t))
	# Sparks shed off the head as it heats.
	for i in range(4):
		var sd: Vector2 = _seeds[i]
		_spark(head + sd * r * 0.10, Vector2(sd.x, -absf(sd.y)).normalized(),
			r * 0.10 * t, 0.55 * t)

# ── Release: the head lands ─────────────────────────────────────────────────
func _draw_impact(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	# Struck-anvil flash, hottest on the first frames.
	draw_circle(Vector2.ZERO, r * (0.16 + 0.60 * t),
		Color(EMBER.r, EMBER.g, EMBER.b, 0.30 * fade))
	draw_circle(Vector2.ZERO, r * (0.10 + 0.26 * t) * fade,
		Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.95 * fade))
	# The hammer head buried at the point of contact.
	var wedge := PackedVector2Array([
		Vector2(-r * 0.20, -r * 0.16), Vector2(r * 0.20, -r * 0.16),
		Vector2(r * 0.13, r * 0.06), Vector2(-r * 0.13, r * 0.06)])
	draw_colored_polygon(wedge, Color(BASALT.r, BASALT.g, BASALT.b, 0.85 * fade))
	# A struck ring on the ground — squashed, so it sits ON the board rather than
	# hovering. Ground effects live above the board art, below the units.
	draw_set_transform(Vector2(0, ground_y * 0.35), 0.0, Vector2(1.0, 0.38))
	draw_arc(Vector2.ZERO, r * (0.24 + 0.85 * t), 0.0, TAU, 28,
		Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.75 * fade), 3.4 * fade + 1.0)
	draw_arc(Vector2.ZERO, r * (0.24 + 0.85 * t), 0.0, TAU, 28,
		Color(EMBER.r, EMBER.g, EMBER.b, 0.45 * fade), 6.0 * fade + 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Sparks thrown outward and upward, plus basalt chips knocked loose.
	for i in range(_seeds.size()):
		var sd: Vector2 = _seeds[i]
		var d := Vector2(sd.x, -sd.y * 0.8).normalized()
		var p: Vector2 = d * r * (0.20 + 0.75 * t)
		_spark(p, d, r * 0.13 * fade, 0.95 * fade)
		if i % 3 == 0:
			var cp: Vector2 = Vector2(sd.x * r * 0.42, -r * 0.05 + t * t * 30.0)
			draw_circle(cp, 2.6 * fade + 0.8, Color(BASALT.r, BASALT.g, BASALT.b, 0.9 * fade))

# ── Forge Fury crossing below 50% HP ────────────────────────────────────────
# A binary threshold that was previously SILENT: the giant simply became 20%
# stronger with nothing on screen. One-shot beat as it lights.
func _draw_trigger(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	draw_circle(Vector2(0, -r * 0.05), r * (0.30 + 0.70 * t),
		Color(EMBER.r, EMBER.g, EMBER.b, 0.30 * fade))
	draw_arc(Vector2(0, -r * 0.05), r * (0.30 + 0.70 * t), 0.0, TAU, 30,
		Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.85 * fade), 4.0 * fade + 1.0)
	# The forge taking: sparks blown straight up off the whole body.
	for i in range(_seeds.size()):
		var sd: Vector2 = _seeds[i]
		var p: Vector2 = Vector2(sd.x * r * 0.42, r * 0.20 - t * (r * 0.75 + 30.0) * sd.y)
		_spark(p, Vector2(sd.x * 0.35, -1.0).normalized(), r * 0.14 * fade, 0.9 * fade)

# ── Persistent: Forge Fury is running ───────────────────────────────────────
# Must survive a whole fight on screen without becoming noise, and must stay
# readable against a body that is ALREADY orange-cracked. So: no added orange
# glow on the body at all. Instead white-hot seams at the shoulders and a slow
# updraft of white sparks — brightness the idle art never reaches.
func _draw_fury() -> void:
	var r := reach * 0.5
	var pulse: float = 0.5 + 0.5 * sin(_t * 2.6)
	# Two white-hot shoulder seams. Short, bright, high on the body where nothing
	# else in the kit draws.
	for s in [-1.0, 1.0]:
		var a: Vector2 = Vector2(s * r * 0.16, -r * 0.30)
		var b: Vector2 = Vector2(s * r * 0.36, -r * 0.16)
		draw_line(a, b, Color(EMBER.r, EMBER.g, EMBER.b, 0.35 + 0.25 * pulse), 6.0)
		draw_line(a, b, Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.70 + 0.30 * pulse), 2.4)
	# A slow rising column of white sparks — the tell that reads even when the
	# giant is stationary and the body art is busy.
	for i in range(_seeds.size()):
		var sd: Vector2 = _seeds[i]
		var phase: float = fposmod(_t * 0.5 + float(i) / float(_seeds.size()), 1.0)
		var p: Vector2 = Vector2(sd.x * r * 0.30, r * 0.22 - phase * (r * 0.62))
		_spark(p, Vector2(sd.x * 0.3, -1.0).normalized(), r * 0.07,
			(1.0 - phase) * 0.75)
	# Heat working the ground at its feet.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.38))
	draw_arc(Vector2.ZERO, r * (0.30 + 0.03 * pulse), 0.0, TAU, 26,
		Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.28 + 0.22 * pulse), 2.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
