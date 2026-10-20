extends Node2D
class_name TrollVFX

# The Troll's visual language: KNOTTED SINEW AND ROAR RINGS.
# Thick braided arcs and concentric shock rings — structurally distinct from the
# Bear's straight claw rakes, the Slime's droplets and the Rat's motes, so the
# two green-ish monsters can never be confused mid-fight. Colour follows the
# unit's ELEMENT (the Troll ships in 6 variants) over a constant bone-white
# highlight.
#
# Gaps this fills:
#   • Enrage applied a 10s attack-speed buff with a generic CHI_BURST and then
#     NOTHING — a buffed unit looked identical to an unbuffed one for 10 seconds.
#   • Regeneration (2% max HP/s) was invisible, so its counterplay — hit it with
#     Fire or Lightning to shut the regen off — was never communicated, and
#     neither was the moment that counterplay landed.

enum Mode { ENRAGE_CAST, ENRAGED, REGEN, SMOTHERED }

const BONE := Color(0.94, 0.93, 0.84)
const DARK := Color(0.12, 0.16, 0.12)
# NOT ash-grey. The Troll's sprite is grey-brown, so a grey pall drawn over it is
# invisible (measured: the first capture showed literally nothing on the
# smothered state). Pale cyan-white steam is the one thing that pops against that
# body, and "doused" is exactly the right fiction for Fire/Lightning shutting the
# regen off.
const QUENCH := Color(0.78, 0.95, 1.0)
const QUENCH_DEEP := Color(0.20, 0.42, 0.52)

var mode: Mode = Mode.ENRAGE_CAST
var elapsed := 0.0
var lifetime := 0.5
var host = null
var tint: Color = Color(0.45, 0.75, 0.40)
var _element: int = UnitBase.Element.NORMAL
var reach := 92.0
var ground_y := 46.0
var _t := 0.0

func _tint_for(element: int) -> Color:
	# NORMAL's element colour is a neutral grey; the Normal Troll's art is mossy,
	# so grey sinew would vanish on it (same trap the Slime hit).
	if element == UnitBase.Element.NORMAL:
		return Color(0.45, 0.72, 0.38)
	return SynergyData.element_color(element)

func setup_point(kind: Mode, world_pos: Vector2, element: int, size: float, life: float) -> void:
	_element = element
	mode = kind
	global_position = world_pos
	tint = _tint_for(element)
	reach = size
	lifetime = life
	z_index = 4
	queue_redraw()

func setup_on(kind: Mode, unit, element: int, size: float, life: float) -> void:
	_element = element
	mode = kind
	host = unit
	tint = _tint_for(element)
	reach = size
	lifetime = life
	z_index = 3
	if unit and "shape_size" in unit:
		ground_y = float(unit.shape_size) * 0.72
	queue_redraw()

func _process(delta: float) -> void:
	if host and is_instance_valid(host) and host.has_method("_battle_clock"):
		delta *= host._battle_clock()
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

# A braided sinew arc — two offset strands sharing a dark rim, so it reads as
# fibre rather than a smooth ring.
func _sinew(r: float, a0: float, a1: float, a: float, w: float) -> void:
	draw_arc(Vector2.ZERO, r, a0, a1, 18, Color(DARK.r, DARK.g, DARK.b, a * 0.8), w + 2.4)
	draw_arc(Vector2.ZERO, r, a0, a1, 18, Color(tint.r, tint.g, tint.b, a), w)
	draw_arc(Vector2.ZERO, r * 0.94, a0 + 0.12, a1 - 0.12, 14,
		Color(BONE.r, BONE.g, BONE.b, a * 0.5), maxf(w - 1.4, 1.0))

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	match mode:
		Mode.ENRAGE_CAST: _draw_cast(t)
		Mode.ENRAGED:     _draw_enraged()
		Mode.REGEN:       _draw_regen()
		Mode.SMOTHERED:   _draw_smothered(t)
	if mode == Mode.ENRAGE_CAST:
		LizardVFX.draw_accent(self, _element, Vector2(14, -reach * 0.1), reach * 0.10, _t, 0.65 * (1.0 - t))

# ── The roar goes out ──────────────────────────────────────────────────────
func _draw_cast(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	# Concentric rings pushing outward — a bellow, not an explosion.
	for i in range(3):
		var rt: float = clampf(t * 1.4 - float(i) * 0.18, 0.0, 1.0)
		if rt <= 0.0:
			continue
		draw_arc(Vector2.ZERO, r * (0.25 + 0.95 * rt), 0.0, TAU, 30,
			Color(tint.r, tint.g, tint.b, (1.0 - rt) * 0.75), 3.4 * (1.0 - rt) + 1.0)
	_sinew(r * (0.34 + 0.20 * t), -PI * 0.85, -PI * 0.15, 0.85 * fade, 4.0 * fade + 1.0)
	draw_circle(Vector2.ZERO, (9.0 * fade + 3.0), Color(BONE.r, BONE.g, BONE.b, 0.8 * fade))

# ── Persistent: this unit is enraged and swinging faster ───────────────────
# A 10s buff that showed nothing. Sinew bands wrap the body and the cadence of
# the sweeping highlight tracks the haste, so "this one is hitting faster" is
# readable without watching the attack timer.
func _draw_enraged() -> void:
	var r := reach * 0.5
	var beat: float = 0.5 + 0.5 * sin(_t * 5.0)
	# Two braided bands around the torso.
	for i in range(2):
		var rr: float = r * (0.40 + 0.10 * float(i))
		var off: float = _t * (1.6 + 0.8 * float(i))
		_sinew(rr, off, off + PI * 0.75, 0.42 + 0.22 * beat, 2.6)
	# Upward flecks — effort coming off the body.
	for i in range(5):
		var f: float = fposmod(_t * 1.5 + float(i) / 5.0, 1.0)
		var x: float = (float(i) - 2.0) * r * 0.20
		draw_circle(Vector2(x, r * 0.10 - f * r * 0.60), 1.8 + 1.6 * (1.0 - f),
			Color(BONE.r, BONE.g, BONE.b, (1.0 - f) * 0.5))
	draw_circle(Vector2(0, r * 0.05), 3.0 + 2.0 * beat,
		Color(tint.r, tint.g, tint.b, 0.35 + 0.30 * beat))

# ── Persistent: it is knitting itself back together ───────────────────────
# Ground-anchored plus body-hugging strands, so it never fights the health bar.
func _draw_regen() -> void:
	var r := reach * 0.5
	var pulse: float = 0.5 + 0.5 * sin(_t * 1.6)
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	draw_circle(Vector2.ZERO, r * (0.44 + 0.05 * pulse),
		Color(tint.r, tint.g, tint.b, 0.09 + 0.06 * pulse))
	draw_arc(Vector2.ZERO, r * 0.44, 0.0, TAU, 24,
		Color(tint.r, tint.g, tint.b, 0.30 + 0.20 * pulse), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Strands knitting UP the body — wounds closing. Each carries a dark rim so
	# it stays readable on the Troll's own mottled grey-brown hide.
	for i in range(5):
		var f: float = fposmod(_t * 0.45 + float(i) / 5.0, 1.0)
		var y: float = ground_y - f * (ground_y + r * 0.62)
		var w: float = r * 0.32 * sin(f * PI)
		var a: float = (1.0 - f) * 0.85
		draw_line(Vector2(-w, y), Vector2(w, y), Color(DARK.r, DARK.g, DARK.b, a * 0.9), 5.0)
		draw_line(Vector2(-w, y), Vector2(w, y), Color(tint.r, tint.g, tint.b, a), 3.0)
		draw_line(Vector2(-w * 0.45, y), Vector2(w * 0.45, y),
			Color(BONE.r, BONE.g, BONE.b, a * 0.75), 1.6)

# ── The counterplay landing: Fire/Lightning shuts the regen off ───────────
# Previously silent, so the one thing a player can DO about this passive never
# confirmed itself. Ash over a desaturating body — the inverse of the green
# knitting above.
func _draw_smothered(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	# The regen ring on the ground visibly CRACKS and goes out — the absence of
	# the green ring is half the read.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	draw_arc(Vector2.ZERO, r * 0.44, 0.0, TAU, 24,
		Color(QUENCH_DEEP.r, QUENCH_DEEP.g, QUENCH_DEEP.b, 0.55 * fade), 2.4)
	for i in range(6):
		var ca: float = float(i) * TAU / 6.0 + 0.3
		var cd := Vector2(cos(ca), sin(ca))
		draw_line(cd * r * 0.30, cd * r * (0.44 + 0.18 * t),
			Color(QUENCH.r, QUENCH.g, QUENCH.b, 0.7 * fade), 2.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Steam boiling UP off the body: bright, cool, and unmistakable against the
	# Troll's warm grey-brown hide.
	for i in range(6):
		var f: float = clampf(t * 1.25 - float(i) * 0.09, 0.0, 1.0)
		if f <= 0.0:
			continue
		var x: float = (float(i) - 2.5) * r * 0.20 + sin(_t * 2.0 + float(i)) * 4.0
		var y: float = ground_y - f * (ground_y + r * 0.85)
		var rad: float = (5.0 + 7.0 * f) * (1.0 - f * 0.35)
		draw_circle(Vector2(x, y), rad + 1.6,
			Color(QUENCH_DEEP.r, QUENCH_DEEP.g, QUENCH_DEEP.b, (1.0 - f) * 0.45 * fade))
		draw_circle(Vector2(x, y), rad,
			Color(QUENCH.r, QUENCH.g, QUENCH.b, (1.0 - f) * 0.72 * fade))
	# Snapped strands: the knitting reversing.
	for i in range(4):
		var a2: float = float(i) * TAU / 4.0 + 0.4
		var d2 := Vector2(cos(a2), sin(a2))
		draw_line(d2 * r * 0.16, d2 * r * (0.30 + 0.28 * t),
			Color(QUENCH.r, QUENCH.g, QUENCH.b, 0.8 * fade), 2.8)
