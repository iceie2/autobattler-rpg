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

const COLD := Color(0.42, 0.82, 0.90)
const DEEP := Color(0.16, 0.24, 0.40)
const CORE := Color(0.88, 0.99, 1.0)

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
	lifetime = life
	z_index = 3
	queue_redraw()

func setup_row(kind: Mode, world_origin: Vector2, points: PackedVector2Array, life: float) -> void:
	mode = kind
	global_position = world_origin
	row_points = points
	lifetime = life
	z_index = 0 if kind == Mode.ROW_WARNING else 4
	queue_redraw()

# Persistent: Cold Blood is regenerating. A passive that only runs while the
# player IGNORES this unit has to be visible, or the counterplay ("go hit the
# backline") is never communicated.
func setup_cold_blood(unit) -> void:
	mode = Mode.COLD_BLOOD
	host = unit
	lifetime = INF
	z_index = 3
	queue_redraw()

func _process(delta: float) -> void:
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
