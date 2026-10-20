extends Node2D
class_name LizardVFX

# The Lizard's visual language: a cold, precise MARKSMAN.
#
# Precision Shot now pierces the target's entire row, which makes the telegraph
# non-negotiable: a row-wide attack that shows nothing until it lands is exactly
# the "agency-removing" feel flagged in the boss-fairness notes. So the sequence
# is AIM (the row lights up, the player can still move) -> a real travelling bolt
# -> ROW_IMPACT along the line it promised. The footprint drawn is the footprint
# hit, cell for cell.
#
# Palette is cold cyan-white against a dark slit-pupil violet — distinct from
# Static's electric yellow, Nemi's warm water blue, the Rat's bile and the
# Wind-Up Bot's brass.

enum Mode { AIM, ROW_WARNING, ROW_IMPACT, COLD_BLOOD }

var COLD := Color(0.42, 0.82, 0.90)
var DEEP := Color(0.16, 0.24, 0.40)
var CORE := Color(0.88, 0.99, 1.0)
var element := UnitBase.Element.NORMAL

static func body_colors(elem: UnitBase.Element) -> Array[Color]:
	match elem:
		UnitBase.Element.FIRE: return [Color(0.24,0.20,0.18), Color(0.61,0.32,0.12), Color(0.9,0.28,0.04)]
		UnitBase.Element.WATER: return [Color(0.15,0.54,0.72), Color(0.48,0.82,0.84), Color(0.06,0.28,0.45)]
		UnitBase.Element.EARTH: return [Color(0.55,0.43,0.22), Color(0.81,0.70,0.41), Color(0.28,0.23,0.12)]
		UnitBase.Element.AIR: return [Color(0.58,0.80,0.65), Color(0.82,0.92,0.76), Color(0.28,0.52,0.40)]
		UnitBase.Element.LIGHTNING: return [Color(0.49,0.31,0.70), Color(0.74,0.64,0.85), Color(0.87,0.73,0.30)]
		_: return [Color(0.46,0.71,0.27), Color(0.70,0.85,0.44), Color(0.20,0.42,0.15)]

static func effect_colors(elem: UnitBase.Element) -> Array[Color]:
	if elem == UnitBase.Element.NORMAL:
		return [Color(0.42,0.82,0.90), Color(0.88,0.99,1.0)]
	return GoblinShamanVFX.element_colors(elem)

func _palette(elem: UnitBase.Element) -> void:
	element = elem
	var colors := effect_colors(elem)
	COLD = colors[0]
	CORE = colors[1]
	DEEP = COLD.darkened(0.65)

static func draw_accent(canvas: CanvasItem, elem: UnitBase.Element, pos: Vector2, size: float, time: float, alpha: float = 1.0) -> void:
	var core: Color = effect_colors(elem)[1]
	core.a = alpha
	match elem:
		UnitBase.Element.WATER:
			pos.y -= fmod(time * 20.0 + pos.x, 7.0)
			canvas.draw_arc(pos, size * 0.7, 0, TAU, 12, core, 1.3, true)
			canvas.draw_arc(pos + Vector2(-1,-1), size * 0.4, PI, PI * 1.5, 5, core, 1.0, true)
		UnitBase.Element.FIRE:
			var sway := sin(time * 18.0 + pos.x) * size * 0.25
			canvas.draw_colored_polygon(PackedVector2Array([pos + Vector2(-size * 0.6,size * 0.4), pos + Vector2(-size * 0.4,-size * 0.4), pos + Vector2(sway,-size * 1.5), pos + Vector2(size * 0.6,size * 0.2)]), Color(1,0.3,0.03,alpha))
			canvas.draw_line(pos, pos + Vector2(sway,-size * 0.6), core, 2.0, true)
		UnitBase.Element.EARTH:
			canvas.draw_colored_polygon(PackedVector2Array([pos + Vector2(-size * 0.6,0), pos + Vector2(-size * 0.2,-size * 0.7), pos + Vector2(size * 0.6,-size * 0.3), pos + Vector2(size * 0.3,size * 0.5)]), Color(0.76,0.59,0.3,alpha))
		UnitBase.Element.AIR:
			canvas.draw_arc(pos, size, time * 5, time * 5 + PI * 1.5, 12, core, 1.3, true)
		UnitBase.Element.LIGHTNING:
			canvas.draw_polyline(PackedVector2Array([pos + Vector2(-size * 0.3,-size), pos + Vector2(size * 0.4,0), pos + Vector2(-size * 0.4,0), pos + Vector2(size * 0.3,size)]), core, 1.5, true)
		_:
			canvas.draw_line(pos - Vector2(size * 0.6,0), pos + Vector2(size * 0.6,0), core, 1.5, true)

var mode: Mode = Mode.AIM
var elapsed := 0.0
var lifetime := 0.5
var host = null
var row_points := PackedVector2Array()   # ROW_* : the row polygon, local space
var span := 900.0                        # ROW_IMPACT : lance length
var _spin := 0.0

func setup_aim(caster, life: float) -> void:
	mode = Mode.AIM
	host = caster
	_palette(caster.current_element)
	lifetime = life
	z_index = 3
	queue_redraw()

func setup_row(kind: Mode, world_origin: Vector2, points: PackedVector2Array, life: float, elem: UnitBase.Element = UnitBase.Element.NORMAL, clock_owner = null) -> void:
	mode = kind
	global_position = world_origin
	row_points = points
	host = clock_owner
	_palette(elem)
	lifetime = life
	z_index = 0 if kind == Mode.ROW_WARNING else 4
	queue_redraw()

# Persistent: Cold Blood is regenerating. A passive that only runs while the
# player IGNORES this unit has to be visible, or the counterplay ("go hit the
# backline") is never communicated.
func setup_cold_blood(unit) -> void:
	mode = Mode.COLD_BLOOD
	host = unit
	_palette(unit.current_element)
	lifetime = INF
	z_index = 3
	queue_redraw()

func _process(delta: float) -> void:
	if is_instance_valid(host) and host.has_method("_battle_clock"):
		delta *= host._battle_clock()
	elapsed += delta
	_spin += delta * 2.0
	if mode in [Mode.AIM, Mode.COLD_BLOOD]:
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
		Mode.AIM:         _draw_aim(t)
		Mode.ROW_WARNING: _draw_row_warning(t)
		Mode.ROW_IMPACT:  _draw_row_impact(t)
		Mode.COLD_BLOOD:  _draw_cold_blood()

# ── The Lizard lines up the shot ─────────────────────────────────────────────
# A reticle that CONVERGES: unambiguous, and the convergence itself is the
# countdown, so the player reads "how long do I have" without a bar.
func _draw_aim(t: float) -> void:
	var r: float = lerp(42.0, 13.0, t)
	draw_circle(Vector2.ZERO, r * 1.35, Color(COLD.r, COLD.g, COLD.b, 0.05 + 0.10 * t))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(COLD.r, COLD.g, COLD.b, 0.45 + 0.45 * t), 2.2)
	# Four crosshair ticks pulling inward with the reticle.
	for i in range(4):
		var a := float(i) * TAU / 4.0 + PI * 0.25
		var d := Vector2(cos(a), sin(a))
		draw_line(d * r * 1.5, d * r * 1.05,
			Color(COLD.r, COLD.g, COLD.b, 0.35 + 0.55 * t), 2.4)
	draw_circle(Vector2.ZERO, 2.5 + 3.5 * t, Color(CORE.r, CORE.g, CORE.b, 0.5 + 0.5 * t))
	for i in range(3):
		var angle := float(i) * TAU / 3.0 + elapsed
		draw_accent(self, element, Vector2(cos(angle), sin(angle)) * (r + 6.0), 5.0, elapsed, 0.55 + t * 0.3)

# ── The row it is ABOUT to pierce ───────────────────────────────────────────
# Drawn from the real cell quads, so the highlight is the hit box, not an
# approximation of it.
func _draw_row_warning(t: float) -> void:
	if row_points.is_empty():
		return
	draw_colored_polygon(row_points, Color(COLD.r, COLD.g, COLD.b, 0.06 + t * 0.10))
	var outline := PackedVector2Array(Array(row_points) + [row_points[0]])
	draw_polyline(outline, Color(COLD.r, COLD.g, COLD.b, 0.42 + t * 0.48), 2.0 + t * 2.0)
	# A charge line sweeping along the row toward full lock.
	if row_points.size() >= 4:
		var a: Vector2 = row_points[0].lerp(row_points[3], 0.5)
		var b: Vector2 = row_points[1].lerp(row_points[2], 0.5)
		draw_line(a, a.lerp(b, t), Color(CORE.r, CORE.g, CORE.b, 0.30 + 0.45 * t), 2.0 + 2.5 * t)

# ── The bolt goes through ───────────────────────────────────────────────────
func _draw_row_impact(t: float) -> void:
	if row_points.is_empty():
		return
	var fade := 1.0 - t
	draw_colored_polygon(row_points, Color(COLD.r, COLD.g, COLD.b, 0.16 * fade))
	var outline := PackedVector2Array(Array(row_points) + [row_points[0]])
	draw_polyline(outline, Color(COLD.r, COLD.g, COLD.b, 0.72 * fade), 3.0)
	# The lance itself: a hard bright line down the middle of the row, with a
	# dark underline so it stays readable over pale sprites.
	if row_points.size() >= 4:
		var a: Vector2 = row_points[0].lerp(row_points[3], 0.5)
		var b: Vector2 = row_points[1].lerp(row_points[2], 0.5)
		draw_line(a, b, Color(DEEP.r, DEEP.g, DEEP.b, 0.85 * fade), 11.0 * fade + 2.0)
		draw_line(a, b, Color(COLD.r, COLD.g, COLD.b, 0.95 * fade), 6.0 * fade + 1.5)
		draw_line(a, b, Color(CORE.r, CORE.g, CORE.b, fade), 2.6 * fade + 1.0)
		# Splinters kicking off the line — the "pierced through" read.
		for i in range(10):
			var f := (float(i) + 0.5) / 10.0
			var p: Vector2 = a.lerp(b, f)
			var n := (b - a).normalized().orthogonal()
			var len: float = (10.0 + 14.0 * t) * (1.0 if i % 2 == 0 else -1.0)
			draw_line(p, p + n * len, Color(COLD.r, COLD.g, COLD.b, 0.75 * fade), 2.2)
			if i % 2 == 0: draw_accent(self, element, p + n * len, 6.0 * fade, elapsed, fade)

# ── Persistent: it is healing because you left it alone ─────────────────────
func _draw_cold_blood() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_spin * 1.3)
	var r: float = 20.0 + 3.0 * pulse
	var hub := Vector2(0, -6.0)
	draw_set_transform(hub, 0.0, Vector2.ONE)
	draw_circle(Vector2.ZERO, r * 1.3, Color(COLD.r, COLD.g, COLD.b, 0.05 + 0.04 * pulse))
	# Slow scale-plate chevrons closing over the body: regeneration, not a heal
	# burst — deliberately calm so it never reads as an incoming attack.
	for i in range(3):
		# (drawn bottom-up so the newest chevron is the brightest)
		var f: float = fposmod(_spin * 0.28 + float(i) / 3.0, 1.0)
		var y: float = 14.0 - f * 28.0
		var w: float = 15.0 * (1.0 - absf(y) / 20.0) + 4.0
		var a: float = (1.0 - f) * 0.5
		draw_line(Vector2(-w, y + 4.0), Vector2(0, y), Color(COLD.r, COLD.g, COLD.b, a), 2.2)
		draw_line(Vector2(0, y), Vector2(w, y + 4.0), Color(COLD.r, COLD.g, COLD.b, a), 2.2)
	draw_circle(Vector2.ZERO, 2.6 + 1.4 * pulse, Color(CORE.r, CORE.g, CORE.b, 0.45 + 0.30 * pulse))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
