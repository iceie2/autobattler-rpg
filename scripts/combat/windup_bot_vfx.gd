extends Node2D
class_name WindUpBotVFX

# The Wind-Up Bot's clockwork visual language. Deliberately NOT a recolour of
# Static's arcs or Nemi's water — this bot is a wound spring, so every mode is
# built from the same three parts: a MAINSPRING SPIRAL, GEAR TEETH, and a
# WINDING KEY. The six elemental variants share all of that geometry and differ
# only in the accent colour (SynergyData.element_color), so a Fire bot and a
# Water bot read as the same machine with a different charge in it.
#
# Layering follows the house rule used by Static/Nemi/Hill Giant:
#   1. broad low-alpha glow  (where the effect reaches — element-tinted)
#   2. readable coloured body (the gears/spring — brass, the mechanism)
#   3. bright focal core      (the exact contact point — near-white)
#
# Footprints are honest: PUNCH_WINDUP and PUNCH_IMPACT are sized for a SINGLE
# melee cell, because Wind-Up Punch only ever hits one adjacent target. Nothing
# here paints area it cannot reach (the Hill Giant's 3x3 warning is the
# precedent for the opposite case).

enum Mode { PUNCH_WINDUP, PUNCH_IMPACT, AUTO_IMPACT, OVERCLOCK }

# Brass is the machine; it never changes between variants.
const BRASS := Color(0.85, 0.62, 0.22)
const BRASS_DARK := Color(0.42, 0.29, 0.10)
const CORE := Color(1.0, 0.96, 0.80)

static func body_color(element: int) -> Color:
	match element:
		UnitBase.Element.FIRE: return Color("b16c5c")
		UnitBase.Element.WATER: return Color("679dab")
		UnitBase.Element.EARTH: return Color("ad9971")
		UnitBase.Element.AIR: return Color("b2c5bb")
		UnitBase.Element.LIGHTNING: return Color("a094bd")
	return Color("a0b2b5")

var _element: int = UnitBase.Element.NORMAL

var mode: Mode = Mode.AUTO_IMPACT
var elapsed := 0.0
var lifetime := 0.5
var accent: Color = Color(0.85, 0.85, 0.92)
var caster_unit = null
var reach := 88.0              # world px — one melee cell for the punch modes

# OVERCLOCK only: 0..10 discrete +5% steps, drives cadence and brightness.
var oc_steps := 0
var _spin := 0.0
var _tick_flash := 0.0         # brief flare on each milestone click

func setup_point(kind: Mode, world_pos: Vector2, element: int, size: float, life: float) -> void:
	_element = element
	mode = kind
	global_position = world_pos
	accent = SynergyData.element_color(element)
	reach = size
	lifetime = life
	z_index = 4
	queue_redraw()

func setup_windup(caster, element: int, size: float, life: float) -> void:
	_element = element
	mode = Mode.PUNCH_WINDUP
	caster_unit = caster
	accent = SynergyData.element_color(element)
	reach = size
	lifetime = life
	z_index = 3
	queue_redraw()

# Persistent Overclock mechanism. Lives as long as the passive does — a
# persistent mechanic gets a persistent visual (house rule), so this is NOT a
# one-shot burst; the manager keeps one per bot and feeds it the stack count.
func setup_overclock(caster, element: int) -> void:
	mode = Mode.OVERCLOCK
	caster_unit = caster
	accent = SynergyData.element_color(element)
	lifetime = INF
	z_index = 3
	queue_redraw()

func set_overclock_steps(steps: int) -> void:
	if steps != oc_steps:
		# A milestone actually landed — flash the key so the +5% is READ, not
		# just silently applied (the whole passive was invisible before).
		_tick_flash = 1.0
	oc_steps = steps
	queue_redraw()

func _process(delta: float) -> void:
	if caster_unit and is_instance_valid(caster_unit) and caster_unit.has_method("_battle_clock"):
		delta *= caster_unit._battle_clock()
	elapsed += delta
	_tick_flash = maxf(0.0, _tick_flash - delta * 3.0)
	if mode in [Mode.PUNCH_WINDUP, Mode.OVERCLOCK]:
		if not (caster_unit and is_instance_valid(caster_unit)):
			queue_free()
			return
		global_position = caster_unit.global_position
	# Cadence: the mainspring turns faster the more wound it is. At 0 steps it
	# idles; at max it is visibly racing. This IS the passive's readout.
	if mode == Mode.OVERCLOCK:
		_spin += delta * (1.6 + float(oc_steps) * 0.62)
	else:
		_spin += delta * 3.0
	if elapsed >= lifetime:
		queue_free()
	else:
		queue_redraw()

# A logarithmic-ish spiral, drawn as a polyline. The mainspring.
func _spring_points(turns: float, r0: float, r1: float, phase: float, segments: int = 56) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var f := float(i) / float(segments)
		var a := phase + f * TAU * turns
		var r: float = lerp(r0, r1, f)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

# Gear teeth around a hub — short radial stubs, the unmistakable clockwork read.
func _draw_gear(radius: float, teeth: int, phase: float, col: Color, width: float) -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, col, width)
	for i in range(teeth):
		var a := phase + float(i) * TAU / float(teeth)
		var d := Vector2(cos(a), sin(a))
		draw_line(d * radius, d * (radius + width * 2.1), col, width)

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	var fade := 1.0 - t
	if mode in [Mode.PUNCH_WINDUP, Mode.PUNCH_IMPACT, Mode.AUTO_IMPACT]:
		LizardVFX.draw_accent(self, _element, Vector2(9, -reach * 0.13), reach * 0.10, _spin, 0.65 * fade)
	match mode:
		Mode.PUNCH_WINDUP: _draw_windup(t)
		Mode.PUNCH_IMPACT: _draw_impact(t, fade, 1.0)
		Mode.AUTO_IMPACT:  _draw_impact(t, fade, 0.46)
		Mode.OVERCLOCK:    _draw_overclock()

# ── Anticipation: the spring winds TIGHTER as contact approaches ─────────────
# The tell is unambiguous and escalates monotonically, so a player can read
# "this one is about to land" from across a crowded board.
func _draw_windup(t: float) -> void:
	var half := reach * 0.5
	# 1. broad low-alpha element glow — the cell it is about to punch into.
	draw_circle(Vector2.ZERO, half * (0.55 + t * 0.45),
		Color(accent.r, accent.g, accent.b, 0.06 + t * 0.10))
	# 2. readable brass body: the mainspring coiling inward (r1 shrinks with t).
	var spring := _spring_points(2.6, half * 0.86, half * (0.34 - t * 0.20), -_spin * 1.3)
	draw_polyline(spring, Color(BRASS.r, BRASS.g, BRASS.b, 0.50 + t * 0.42), 3.0 + t * 2.2)
	# Counter-rotating gear pair: the mechanism under load.
	_draw_gear(half * (0.52 - t * 0.10), 8, _spin * 1.9,
		Color(BRASS.r, BRASS.g, BRASS.b, 0.45 + t * 0.45), 3.0)
	_draw_gear(half * (0.30 - t * 0.06), 6, -_spin * 2.7,
		Color(accent.r, accent.g, accent.b, 0.42 + t * 0.44), 2.6)
	# Ratchet ticks snapping toward the hub — the countdown to release.
	for i in range(6):
		var a := float(i) * TAU / 6.0 + _spin * 0.7
		var d := Vector2(cos(a), sin(a))
		var tick_t := fposmod(t * 2.2 + float(i) / 6.0, 1.0)
		draw_line(d * half * (0.88 - tick_t * 0.46), d * half * (0.96 - tick_t * 0.46),
			Color(BRASS.r, BRASS.g, BRASS.b, (0.30 + 0.50 * t) * (1.0 - tick_t)), 3.4)
	# 3. bright focal core, tightening to a point at release.
	draw_circle(Vector2.ZERO, (11.0 + 9.0 * t) * (1.0 - t * 0.35),
		Color(CORE.r, CORE.g, CORE.b, 0.48 + t * 0.48))

# ── Release: the spring lets go ──────────────────────────────────────────────
# `scale_f` separates the signature punch from the lighter auto so the two are
# never confused, while keeping them the same visual family.
func _draw_impact(t: float, fade: float, scale_f: float) -> void:
	var half := reach * 0.5 * scale_f
	# 1. broad element glow, expanding.
	draw_circle(Vector2.ZERO, half * (0.5 + 0.7 * t),
		Color(accent.r, accent.g, accent.b, 0.20 * fade))
	# 2. brass body: the spring UNCOILING outward (mirror of the wind-up) plus
	#    a shock ring of gear teeth thrown off the hub.
	var spring := _spring_points(2.2, half * (0.10 + 0.22 * t), half * (0.38 + 0.80 * t), _spin * 2.2)
	draw_polyline(spring, Color(BRASS.r, BRASS.g, BRASS.b, 0.85 * fade), (4.5 * scale_f + 1.5) * fade)
	# The gear ring stays TIGHT around the hub while the teeth are thrown wide —
	# the two layers must not expand together or they merge into one flat ring
	# with no depth (which is exactly what the first cut looked like).
	_draw_gear(half * (0.18 + 0.34 * t), 10, _spin * 3.1,
		Color(BRASS.r, BRASS.g, BRASS.b, 0.70 * fade), 3.2 * scale_f + 1.0)
	# Escaping teeth — discrete chunks, not a particle mist, so the hit reads
	# as MECHANICAL rather than as the generic element puff it used to be.
	var teeth := int(12 * scale_f) + 6
	for i in range(teeth):
		var a := float(i) * TAU / float(teeth) + 0.21
		var d := Vector2(cos(a), sin(a))
		var p := d * half * (0.34 + 1.16 * t)
		draw_line(p * 0.78, p, Color(BRASS_DARK.r, BRASS_DARK.g, BRASS_DARK.b, 0.85 * fade),
			(4.0 * scale_f + 1.0) * fade)
		draw_circle(p, (3.2 * scale_f + 1.4) * fade,
			Color(accent.r, accent.g, accent.b, 0.88 * fade))
	# 3. bright focal core at the exact contact point.
	draw_circle(Vector2.ZERO, (26.0 * scale_f + 6.0) * fade,
		Color(BRASS.r, BRASS.g, BRASS.b, 0.46 * fade))
	draw_circle(Vector2.ZERO, (12.0 * scale_f + 4.0) * fade,
		Color(CORE.r, CORE.g, CORE.b, fade))

# ── Overclock: a winding key that visibly tightens over the fight ────────────
# Strong at max but deliberately bounded — this sits on up to three bots at once
# in wave 6, so it stays a compact badge on the body rather than a screen effect.
func _draw_overclock() -> void:
	if oc_steps <= 0 and _tick_flash <= 0.0:
		return
	var f := float(oc_steps) / 10.0          # 0..1 across the +0%..+50% ramp
	# Kept compact deliberately: the board's cells are 110px, so a badge much
	# wider than this reaches into the neighbouring unit's square — and wave 6
	# fields THREE of these bots at once.
	var r := 18.0 + 6.0 * f
	# Mounted on the chassis, upper LEFT, NOT overhead. Two measured constraints
	# rule the overhead position out: the health bar sits on the unit's vertical
	# axis at y = -(offset_y + bar_height) ~= -72 (VisualUnit sets offset_y 60),
	# so a centred badge of this radius lands straight on it; and the bot's own
	# winding-key art sticks out upper RIGHT. Left shoulder clears both, and a
	# gear bolted to the housing reads more like part of the machine than a
	# floating HUD element anyway.
	var hub := Vector2(-36.0, -4.0)
	draw_set_transform(hub, 0.0, Vector2.ONE)
	# 1. broad low-alpha element glow, brightening as it winds up.
	draw_circle(Vector2.ZERO, r * 1.25, Color(accent.r, accent.g, accent.b, 0.05 + 0.09 * f))
	# 2. brass body: the driving gear (spins faster with every step) and the
	#    mainspring coil filling in one arc per +5% — the stack count is
	#    COUNTABLE, not just "brighter".
	_draw_gear(r * 0.62, 8, _spin, Color(BRASS.r, BRASS.g, BRASS.b, 0.55 + 0.40 * f), 2.8)
	for i in range(oc_steps):
		var a0 := -PI * 0.5 + float(i) * TAU / 10.0
		draw_arc(Vector2.ZERO, r, a0 + 0.07, a0 + TAU / 10.0 - 0.07, 8,
			Color(accent.r, accent.g, accent.b, 0.80), 3.4)
	# The winding key itself — the identity silhouette, rotating with cadence.
	for i in range(2):
		var a := _spin + float(i) * PI
		var d := Vector2(cos(a), sin(a))
		draw_line(Vector2.ZERO, d * r * 0.46,
			Color(BRASS.r, BRASS.g, BRASS.b, 0.75 + 0.25 * f), 4.0)
		draw_circle(d * r * 0.46, 3.6, Color(BRASS.r, BRASS.g, BRASS.b, 0.85))
	# 3. focal core + the milestone click flare.
	draw_circle(Vector2.ZERO, 4.5 + 2.5 * f, Color(CORE.r, CORE.g, CORE.b, 0.65 + 0.35 * f))
	if _tick_flash > 0.0:
		draw_arc(Vector2.ZERO, r * (1.0 + (1.0 - _tick_flash) * 0.55), 0.0, TAU, 32,
			Color(CORE.r, CORE.g, CORE.b, 0.72 * _tick_flash), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
