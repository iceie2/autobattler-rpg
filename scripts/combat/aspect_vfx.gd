extends Node2D
class_name AspectVFX

# The Aspect Devourer's visual language: IT WEARS WHAT IT ATE.
#
# Devour Aspect swaps its element every 6s, which changes what hurts it — the
# whole point of the fight — and the only tell was a line in the text log. Its
# shell already carries all six element sigils, so the readout is the CURRENT
# one lifted out and held over its head in that element's colour, with a ring
# draining toward the next swap and a matching glow at its feet.
# SWAP (one-shot): the old colour is sucked into its maw, the new one bursts out.

enum Mode { AURA, SWAP }

const OUTLINE := Color(0.05, 0.04, 0.07)

var mode: Mode = Mode.AURA
var host = null
var r := 60.0
var element := 0
var old_element := 0
var cycle_frac := 0.0        # AURA: 0 just swapped → 1 about to swap
var _t := 0.0
var _life := INF
var _ground: Node2D = null

func setup_aura(unit) -> void:
	mode = Mode.AURA
	host = unit
	z_index = 5
	r = MirrorVFX.body_r(unit)
	element = unit.current_element
	global_position = unit.global_position
	# Ground glow lives on its own low-z child so it sits UNDER the body
	# (drawn on this node it tinted the claws).
	_ground = Node2D.new()
	_ground.z_as_relative = false
	_ground.z_index = 1
	add_child(_ground)
	_ground.draw.connect(_draw_ground)

func setup_swap(unit, from_elem: int, to_elem: int) -> void:
	mode = Mode.SWAP
	_life = 0.6
	z_index = 6
	r = MirrorVFX.body_r(unit)
	old_element = from_elem
	element = to_elem
	global_position = unit.global_position

func set_state(elem: int, frac: float) -> void:
	element = elem
	cycle_frac = clampf(frac, 0.0, 1.0)

func _process(delta: float) -> void:
	_t += delta
	if host != null:
		if not is_instance_valid(host) or host.current_hp <= 0:
			queue_free(); return
		global_position = host.global_position
	if _t >= _life:
		queue_free()
	else:
		queue_redraw()
		if _ground: _ground.queue_redraw()

func _draw() -> void:
	if mode == Mode.AURA: _draw_aura()
	else: _draw_swap()

func _col(e: int) -> Color:
	return SynergyData.element_color(e)

func _draw_aura() -> void:
	var c: Color = _col(element)
	# Held sigil + countdown ring.
	var sc := Vector2(0, -r * 1.75 + sin(_t * 2.0) * 3.0)
	var rad: float = 17.0
	draw_circle(sc, rad + 4.0, OUTLINE)
	draw_circle(sc, rad, Color(0.12, 0.11, 0.15))
	draw_arc(sc, rad + 5.5, 0, TAU, 32, Color(0, 0, 0, 0.5), 4.0)
	draw_arc(sc, rad + 5.5, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - cycle_frac), 32, c, 3.0)
	sigil(self, element, sc, rad * 0.75, c)

func _draw_ground() -> void:
	var c: Color = _col(element)
	_ground.draw_set_transform(Vector2(0, r * 0.45), 0.0, Vector2(1.0, 0.38))
	_ground.draw_circle(Vector2.ZERO, r * 1.0, Color(c.r, c.g, c.b, 0.16 + 0.06 * sin(_t * 3.0)))
	_ground.draw_arc(Vector2.ZERO, r * 1.0, 0, TAU, 40, Color(c.r, c.g, c.b, 0.55), 3.0)

func _draw_swap() -> void:
	var k: float = _t / _life
	var maw := Vector2(r * 0.35, -r * 0.1)
	var oc: Color = _col(old_element)
	var nc: Color = _col(element)
	if k < 0.5:
		# The old aspect is gulped: motes converge on the maw.
		var g: float = k / 0.5
		for i in 10:
			var ang: float = TAU * float(i) / 10.0 + g * 2.0
			var p: Vector2 = maw + Vector2(cos(ang), sin(ang) * 0.7) * r * 1.3 * (1.0 - g)
			draw_circle(p, 5.0 * (1.0 - g) + 1.5, Color(oc.r, oc.g, oc.b, 0.9))
	else:
		# The new one bursts out from the body.
		var b: float = (k - 0.5) / 0.5
		draw_arc(Vector2(0, -r * 0.4), r * (0.3 + 1.2 * b), 0, TAU, 40, Color(OUTLINE.r, OUTLINE.g, OUTLINE.b, 0.6 * (1.0 - b)), 9.0)
		draw_arc(Vector2(0, -r * 0.4), r * (0.3 + 1.2 * b), 0, TAU, 40, Color(nc.r, nc.g, nc.b, 1.0 - b), 5.0)
		sigil(self, element, Vector2(0, -r * 0.5), 20.0 + 14.0 * b, Color(nc.r, nc.g, nc.b, 1.0 - b * 0.7))

# One glyph per element, drawn in code (shared shape language with the shell).
static func sigil(ci: CanvasItem, e: int, c: Vector2, s: float, col: Color) -> void:
	match e:
		UnitBase.Element.FIRE:
			# Three-tongued flame, points in angular order so it never self-intersects.
			var fp := PackedVector2Array()
			for q in [Vector2(0, 0.9), Vector2(0.55, 0.55), Vector2(0.65, 0.0), Vector2(0.45, -0.35),
					Vector2(0.5, -0.75), Vector2(0.2, -0.45), Vector2(0, -1.0), Vector2(-0.2, -0.5),
					Vector2(-0.45, -0.7), Vector2(-0.45, -0.3), Vector2(-0.65, 0.05), Vector2(-0.55, 0.55)]:
				fp.append(c + q * s)
			ci.draw_colored_polygon(fp, col)
		UnitBase.Element.WATER:
			var pts2 := PackedVector2Array([c + Vector2(0, -s)])
			for i in 11:
				var ang2: float = -PI * 0.15 + PI * 1.3 * float(i) / 10.0
				pts2.append(c + Vector2(cos(ang2), sin(ang2)) * s * 0.6 + Vector2(0, s * 0.25))
			ci.draw_colored_polygon(pts2, col)
		UnitBase.Element.EARTH:
			var hexp := PackedVector2Array()
			for i in 6:
				var ang3: float = TAU * float(i) / 6.0 + PI / 6.0
				hexp.append(c + Vector2(cos(ang3), sin(ang3)) * s * 0.8)
			ci.draw_colored_polygon(hexp, col)
		UnitBase.Element.AIR:
			var sp := PackedVector2Array()
			for i in 20:
				var f2: float = float(i) / 19.0
				var ang4: float = f2 * TAU * 1.4
				sp.append(c + Vector2(cos(ang4), sin(ang4)) * s * (0.15 + 0.7 * f2))
			ci.draw_polyline(sp, col, 3.0)
		UnitBase.Element.LIGHTNING:
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.2, -s), c + Vector2(-s * 0.45, s * 0.1),
				c + Vector2(0, s * 0.1), c + Vector2(-s * 0.2, s), c + Vector2(s * 0.45, -s * 0.1),
				c + Vector2(0, -s * 0.1)]), col)
		_:
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.85), c + Vector2(s * 0.7, 0),
				c + Vector2(0, s * 0.85), c + Vector2(-s * 0.7, 0)]), col)
