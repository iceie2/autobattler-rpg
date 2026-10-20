extends Node2D
class_name HillGiantVFX

# GB_* (2026-10-06): the round-5 elite's Groundbreaker loop -- the warning on
# the EXACT cells it will hit, the impact (cracked earth that stays for the whole
# stuck window, a dust ring, flung debris), dust puffs on each heave, and the
# debris pop when the club is yanked free.
enum Mode { SMASH_WARNING, SMASH_IMPACT, AUTO_IMPACT, GB_WARNING, GB_IMPACT, GB_PUFF, GB_YANK, SWING_WARNING }

var element := UnitBase.Element.EARTH
var mode := Mode.AUTO_IMPACT
var elapsed := 0.0
var lifetime := 0.5
var caster_unit = null
var footprint_size := 440.0
var footprint_points := PackedVector2Array()
# Battle clock (2026-10-06): an AutoBattleManager. Effects advance on ITS time --
# frozen while paused, sped up at 2x/4x -- so they stay locked to the combat
# timers that deal the damage. Without one they fall back to real time.
var clock = null
var cells: Array = []              # GB_*: one PackedVector2Array quad per cell, local
var _bits: Array = []
var _rng := RandomNumberGenerator.new()

func set_clock(mgr) -> void:
	clock = mgr

func setup_swing(unit, life: float) -> void:
	mode = Mode.SWING_WARNING
	caster_unit = unit
	element = unit.current_element
	lifetime = life
	z_index = 4

func setup_gb(kind: Mode, centre_world: Vector2, cell_quads_world: Array, life: float, size: float = 120.0, elem: UnitBase.Element = UnitBase.Element.EARTH) -> void:
	element = elem
	mode = kind
	global_position = centre_world
	lifetime = life
	footprint_size = size
	z_index = 1 if kind == Mode.GB_WARNING or kind == Mode.GB_IMPACT else 4
	cells = []
	for q in cell_quads_world:
		var local := PackedVector2Array()
		for p in q:
			local.append(p - centre_world)
		cells.append(local)
	_rng.seed = int(get_instance_id()) & 0x7fffffff
	for i in 22:
		_bits.append([_rng.randf() * TAU, _rng.randf_range(0.4, 1.0), _rng.randf_range(-1.0, 1.0)])
	queue_redraw()

func setup_warning(caster, size: float, life: float) -> void:
	mode = Mode.SMASH_WARNING
	caster_unit = caster
	element = caster.current_element
	footprint_size = size
	lifetime = life
	z_index = 0
	queue_redraw()

func setup_point(kind: Mode, world_pos: Vector2, size: float, life: float, elem: UnitBase.Element = UnitBase.Element.EARTH) -> void:
	element = elem
	mode = kind
	global_position = world_pos
	footprint_size = size
	lifetime = life
	z_index = 4
	queue_redraw()

func set_footprint_polygon(points: PackedVector2Array) -> void:
	footprint_points = points
	queue_redraw()

func _footprint() -> PackedVector2Array:
	if not footprint_points.is_empty():
		return footprint_points
	var half := footprint_size * 0.5
	return PackedVector2Array([Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])

func _process(delta: float) -> void:
	if clock and is_instance_valid(clock):
		if bool(clock.get("paused")):
			return
		delta *= float(clock.get("time_scale"))
	elapsed += delta
	if mode == Mode.SMASH_WARNING or mode == Mode.SWING_WARNING:
		if not (caster_unit and is_instance_valid(caster_unit)):
			queue_free(); return
		global_position = caster_unit.global_position
	if elapsed >= lifetime: queue_free()
	else: queue_redraw()

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	if mode == Mode.SWING_WARNING:
		var color: Color = element_colors(element)[1]
		color.a = 0.25 + t * 0.5
		for i in 5:
			var p := Vector2(32.0 + i * 7.0, -25.0 - sin(t * PI) * 18.0 - i * 3.0)
			_element_mark(p, 3.5, color, float(i))
		return
	if mode >= Mode.GB_WARNING:
		_draw_gb(t)
		_draw_accents(t)
		return
	var fade := 1.0 - t
	_draw_accents(t)
	var earth: Color = element_colors(element)[0]
	var ochre: Color = element_colors(element)[1]
	if mode == Mode.SMASH_WARNING:
		var points := _footprint()
		# Strong compression beat: broad low-alpha ground pressure, an opaque
		# gameplay edge, then inward rings that accelerate toward contact.
		draw_colored_polygon(points, Color(earth.r, earth.g, earth.b, 0.075 + t * 0.095))
		draw_polyline(PackedVector2Array(Array(points) + [points[0]]),
			Color(ochre.r, ochre.g, ochre.b, 0.48 + t * 0.47), 4.0 + t * 3.0)
		var half := footprint_size * 0.5
		for ring_i in range(3):
			var ring_t := fposmod(t * 1.7 + float(ring_i) / 3.0, 1.0)
			var rr := half * (0.92 - ring_t * 0.68)
			draw_arc(Vector2.ZERO, rr, 0.0, TAU, 48,
				Color(ochre.r, ochre.g, ochre.b, (0.12 + 0.34 * t) * ring_t), 3.0)
		for i in range(4):
			var a := float(i) * TAU / 4.0 + PI * 0.25
			var end := Vector2(cos(a), sin(a)) * half * (0.35 + t * 0.5)
			draw_line(Vector2.ZERO, end, Color(ochre.r, ochre.g, ochre.b, 0.35 + t * 0.55), 4.0)
		draw_circle(Vector2.ZERO, 28.0 + 28.0 * t, Color(earth.r, earth.g, earth.b, 0.22 + t * 0.18))
		draw_circle(Vector2.ZERO, 9.0 + 8.0 * t, Color(1.0, 0.88, 0.46, 0.55 + t * 0.40))
	elif mode == Mode.SMASH_IMPACT:
		var points := _footprint()
		draw_colored_polygon(points, Color(earth.r, earth.g, earth.b, 0.15 * fade))
		draw_polyline(PackedVector2Array(Array(points) + [points[0]]),
			Color(ochre.r, ochre.g, ochre.b, 0.78 * fade), 6.0)
		# Two shock rings separate the actual contact from the cracked-earth residue.
		for ring_i in range(2):
			var ring_t := clampf(t * 1.35 - float(ring_i) * 0.16, 0.0, 1.0)
			draw_arc(Vector2.ZERO, footprint_size * (0.07 + 0.40 * ring_t), 0.0, TAU, 56,
				Color(1.0, 0.70, 0.22, (1.0 - ring_t) * 0.70), 8.0 * (1.0 - ring_t) + 2.0)
		for i in range(20):
			var a := float(i) * TAU / 20.0 + 0.17
			var dist := footprint_size * (0.10 + 0.40 * t)
			var p := Vector2(cos(a), sin(a)) * dist
			draw_line(p * 0.22, p, Color(0.24, 0.10, 0.025, 0.88 * fade), 7.0 * fade)
			draw_circle(p, (5.0 + float(i % 3) * 2.0) * fade,
				Color(ochre.r, ochre.g, ochre.b, 0.90 * fade))
		draw_circle(Vector2.ZERO, 86.0 * fade, Color(earth.r, earth.g, earth.b, 0.30 * fade))
		draw_circle(Vector2.ZERO, 34.0 * fade, Color(ochre.r, ochre.g, ochre.b, 0.48 * fade))
		draw_circle(Vector2.ZERO, 18.0 * fade, Color(1.0, 0.94, 0.64, fade))
	else:
		for ring_i in range(2):
			var ring_t := clampf(t * 1.5 - float(ring_i) * 0.20, 0.0, 1.0)
			draw_arc(Vector2.ZERO, 18.0 + 55.0 * ring_t, 0.0, TAU, 32,
				Color(ochre.r, ochre.g, ochre.b, (1.0 - ring_t) * 0.62), 6.0)
		for i in range(12):
			var a := float(i) * TAU / 12.0
			var p := Vector2(cos(a), sin(a)) * (16.0 + 48.0 * t)
			draw_line(Vector2.ZERO, p, Color(earth.r, earth.g, earth.b, 0.88 * fade), 7.0 * fade)
			draw_circle(p, 4.5 * fade, Color(ochre.r, ochre.g, ochre.b, 0.90 * fade))
		draw_circle(Vector2.ZERO, 34.0 + 28.0 * t, Color(earth.r, earth.g, earth.b, 0.22 * fade))
		draw_circle(Vector2.ZERO, 16.0 * fade, Color(ochre.r, ochre.g, ochre.b, 0.72 * fade))
		draw_circle(Vector2.ZERO, 7.0 * fade, Color(1.0, 0.94, 0.66, fade))


# ── Groundbreaker ─────────────────────────────────────────────────────────────
const GB_EARTH := Color(0.40, 0.24, 0.10)
const GB_OCHRE := Color(0.95, 0.66, 0.20)
const GB_DARK := Color(0.16, 0.09, 0.04)
const GB_DUST := Color(0.78, 0.68, 0.52)

func _cell_centre(q: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in q: c += p
	return c / maxf(q.size(), 1)

func _draw_gb(t: float) -> void:
	var earth: Color = element_colors(element)[0]
	var ochre: Color = element_colors(element)[1]
	var dust: Color = GB_DUST.lerp(ochre, 0.35)
	match mode:
		Mode.GB_WARNING:
			# EXACTLY the cells that can take damage: each one filled and
			# outlined, pressure building toward contact (faster pulse, hotter edge).
			var pulse := 0.5 + 0.5 * sin(elapsed * lerpf(7.0, 22.0, t))
			for q in cells:
				draw_colored_polygon(q, Color(earth, 0.16 + 0.26 * t + 0.08 * pulse))
				var closed := PackedVector2Array(Array(q) + [q[0]])
				draw_polyline(closed, Color(GB_DARK, 0.75), 6.0)
				draw_polyline(closed, Color(ochre, 0.55 + 0.45 * t), 3.0)
				# A crack line already forming across each cell.
				var c := _cell_centre(q)
				draw_line(c - (q[1] - q[0]) * 0.25 * t, c + (q[2] - q[3]) * 0.25 * t,
					Color(GB_DARK, 0.5 * t), 3.0)
		Mode.GB_IMPACT:
			# Contact flash + dust ring in the first beat, then cracked earth that
			# stays for the whole stuck window and fades as it ends.
			var early := clampf(elapsed / 0.6, 0.0, 1.0)
			var fade := 1.0 if t < 0.8 else (1.0 - t) / 0.2
			for q in cells:
				draw_colored_polygon(q, Color(GB_DARK, 0.22 * fade))
				var c := _cell_centre(q)
				var e1: Vector2 = (q[1] - q[0]) * 0.42
				var e2: Vector2 = (q[3] - q[0]) * 0.42
				for k in 3:
					var a: Vector2 = c + e1 * (0.3 * float(k) - 0.3) + e2 * 0.15 * float(k - 1)
					var b: Vector2 = a + e1 * 0.55 + e2 * (0.35 if k % 2 == 0 else -0.35)
					draw_line(a, b, Color(GB_DARK, 0.85 * fade), 4.0)
					draw_line(a, b, Color(ochre, 0.35 * fade * (1.0 - early * 0.6)), 1.5)
			if early < 1.0:
				var rr: float = footprint_size * (0.25 + 1.1 * early)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
				draw_arc(Vector2.ZERO, rr, 0, TAU, 48, Color(dust, 0.85 * (1.0 - early)), 10.0 * (1.0 - early) + 2.0)
				draw_arc(Vector2.ZERO, rr * 0.7, 0, TAU, 48, Color(ochre, 0.6 * (1.0 - early)), 4.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_circle(Vector2.ZERO, footprint_size * 0.35 * (1.0 - early), Color(1.0, 0.92, 0.65, 0.7 * (1.0 - early)))
				# Debris: chunks thrown up and falling back.
				for b in _bits:
					var d := Vector2(cos(float(b[0])), sin(float(b[0])) * 0.5)
					var p: Vector2 = d * footprint_size * float(b[1]) * early + Vector2(0, -90.0 * float(b[1]) * sin(PI * early))
					var s: float = 4.0 + 5.0 * float(b[1])
					draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), Color(GB_DARK, 1.0 - early))
					draw_rect(Rect2(p - Vector2(s, s) * 0.3, Vector2(s, s) * 0.6), Color(earth.lightened(0.2), 1.0 - early))
		Mode.GB_PUFF:
			# A heave: dust squeezed out around the planted club.
			for b in _bits.slice(0, 8):
				var d := Vector2(cos(float(b[0])), sin(float(b[0])) * 0.45)
				var p: Vector2 = d * footprint_size * (0.2 + 0.6 * t) * float(b[1]) + Vector2(0, -20.0 * t)
				draw_circle(p, (8.0 + 10.0 * t) * float(b[1]), Color(dust, 0.55 * (1.0 - t)))
		Mode.GB_YANK:
			# The club rips out: a burst of clods and a dust plume straight up.
			for b in _bits:
				var d := Vector2(float(b[2]) * 0.6, -1.0).normalized()
				var p: Vector2 = d * 120.0 * float(b[1]) * t + Vector2(0, 160.0 * t * t)
				var s: float = 5.0 + 5.0 * float(b[1])
				draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), Color(GB_DARK, 1.0 - t))
			draw_circle(Vector2(0, -30.0 * t), 30.0 + 40.0 * t, Color(dust, 0.45 * (1.0 - t)))

static func element_name(elem: UnitBase.Element) -> String:
	return {UnitBase.Element.NORMAL: "normal", UnitBase.Element.FIRE: "fire",
		UnitBase.Element.WATER: "water", UnitBase.Element.EARTH: "earth",
		UnitBase.Element.AIR: "air", UnitBase.Element.LIGHTNING: "lightning"}.get(elem, "normal")

static func element_colors(elem: UnitBase.Element) -> Array[Color]:
	match elem:
		UnitBase.Element.NORMAL: return [Color(0.40, 0.38, 0.34), Color(0.85, 0.81, 0.70)]
		UnitBase.Element.FIRE: return [Color(0.55, 0.18, 0.06), Color(1.0, 0.57, 0.20)]
		UnitBase.Element.WATER: return [Color(0.12, 0.35, 0.52), Color(0.50, 0.86, 1.0)]
		UnitBase.Element.AIR: return [Color(0.31, 0.49, 0.43), Color(0.78, 0.97, 0.88)]
		UnitBase.Element.LIGHTNING: return [Color(0.32, 0.22, 0.50), Color(0.81, 0.70, 1.0)]
		_: return [GB_EARTH, GB_OCHRE]

func _draw_accents(t: float) -> void:
	if mode == Mode.GB_WARNING: return
	var progress := clampf(elapsed / 0.65, 0.0, 1.0) if mode == Mode.GB_IMPACT else t
	var color: Color = element_colors(element)[1]
	color.a = (1.0 - progress) * 0.85
	for i in 7:
		var angle := float(i) * TAU / 7.0 + 0.23
		var p := Vector2(cos(angle), sin(angle) * 0.38) * footprint_size * (0.18 + progress * 0.48)
		p.y -= sin(progress * PI) * 23.0
		_element_mark(p, 3.5 + float(i % 3), color, angle)

func _element_mark(pos: Vector2, size: float, color: Color, phase: float) -> void:
	match element:
		UnitBase.Element.FIRE:
			var sway := sin(phase * 3.0 + elapsed * 14.0) * size * 0.3
			var flame := PackedVector2Array([pos + Vector2(-size * 0.6, size * 0.4), pos + Vector2(-size * 0.7, -size * 0.2), pos + Vector2(-size * 0.25, -size * 0.8), pos + Vector2(sway, -size * 1.7), pos + Vector2(size * 0.55, -size * 0.55), pos + Vector2(size * 0.65, size * 0.2), pos + Vector2(0, size * 0.6)])
			draw_colored_polygon(flame, Color(1.0, 0.32, 0.04, color.a))
			draw_colored_polygon(PackedVector2Array([pos + Vector2(-size * 0.3, size * 0.3), pos + Vector2(sway * 0.5, -size * 0.8), pos + Vector2(size * 0.3, size * 0.3)]), color)
		UnitBase.Element.WATER:
			# Hollow bubbles with a highlight; rise separately from the ribbon.
			var bubble := pos + Vector2(sin(phase + elapsed * 7.0) * 2.0, -fmod(elapsed * 24.0 + phase * 2.0, 9.0))
			draw_circle(bubble, size * 0.7, Color(color.r, color.g, color.b, color.a * 0.12))
			draw_arc(bubble, size * 0.7, 0.0, TAU, 16, color, 1.4, true)
			draw_arc(bubble + Vector2(-size * 0.08, -size * 0.08), size * 0.42, PI, PI * 1.5, 6, Color(0.9, 1.0, 1.0, color.a), 1.5, true)
		UnitBase.Element.EARTH:
			var rock := PackedVector2Array([pos + Vector2(-size * 0.65, -size * 0.15), pos + Vector2(-size * 0.25, -size * 0.7), pos + Vector2(size * 0.55, -size * 0.4), pos + Vector2(size * 0.65, size * 0.3), pos + Vector2(-size * 0.2, size * 0.65)])
			draw_colored_polygon(rock, Color(0.65, 0.48, 0.22, color.a))
			draw_line(rock[1], rock[2], Color(1.0, 0.83, 0.46, color.a), 1.5, true)
		UnitBase.Element.AIR:
			var turn := phase + elapsed * 6.0
			draw_arc(pos, size * 0.85, turn, turn + PI * 1.4, 12, color, 1.5, true)
			draw_arc(pos + Vector2(size * 0.6, -size * 0.3), size * 0.5, turn + PI, turn + PI * 2.3, 10, Color(color.r, color.g, color.b, color.a * 0.5), 1.0, true)
		UnitBase.Element.LIGHTNING:
			draw_polyline(PackedVector2Array([pos + Vector2(-size * 0.3, -size), pos + Vector2(size * 0.4, -size * 0.1), pos + Vector2(-size * 0.4, size * 0.1), pos + Vector2(size * 0.3, size)]), color, 2.0, true)
		_:
			draw_line(pos - Vector2(size, 0), pos + Vector2(size, 0), color, 1.5, true)
			draw_line(pos - Vector2(0, size), pos + Vector2(0, size), color, 1.5, true)
