extends Node2D
class_name StaticVFX

# Static's signature VFX. Kept separate from SkillEffect.LIGHTNING so Zolt and
# other lightning users retain their own visual language.
enum Mode { TRIPWIRE, THUNDER_STRIKE, STUN_RESIDUE, AUTO_MUZZLE, AUTO_IMPACT, GRID }

const YELLOW := Color(1.0, 0.92, 0.18)
const CYAN := Color(0.12, 0.88, 1.0)
const VIOLET := Color(0.58, 0.22, 1.0)
const WHITE_HOT := Color(1.0, 1.0, 0.82)

var mode: Mode = Mode.AUTO_IMPACT
var elapsed := 0.0
var lifetime := 0.5
var source: Node2D = null
var target: Node2D = null
var grid: BattleGrid = null
var _pulse_age := 99.0
var _lockdown_flash := 0.0

func setup_pair(kind: Mode, from: Node2D, to: Node2D, life: float) -> void:
	mode = kind
	source = from
	target = to
	lifetime = life
	z_index = 4
	queue_redraw()

func setup_point(kind: Mode, world_pos: Vector2, life: float = 0.45) -> void:
	mode = kind
	global_position = world_pos
	lifetime = life
	z_index = 4
	queue_redraw()

func setup_grid(board: BattleGrid, life: float) -> void:
	mode = Mode.GRID
	grid = board
	lifetime = life
	position = Vector2.ZERO
	z_index = 0
	queue_redraw()

func pulse() -> void:
	_pulse_age = 0.0
	queue_redraw()

func lockdown() -> void:
	_lockdown_flash = 1.0
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	_pulse_age += delta
	_lockdown_flash = maxf(0.0, _lockdown_flash - delta * 2.2)
	if elapsed >= lifetime or (mode != Mode.GRID and target and not is_instance_valid(target)):
		queue_free()
		return
	if mode == Mode.TRIPWIRE and source and is_instance_valid(source):
		global_position = source.global_position
	elif mode == Mode.STUN_RESIDUE and target and is_instance_valid(target):
		global_position = target.global_position
	queue_redraw()

func _draw() -> void:
	match mode:
		Mode.TRIPWIRE: _draw_tripwire()
		Mode.THUNDER_STRIKE: _draw_thunder_strike()
		Mode.STUN_RESIDUE: _draw_stun_residue()
		Mode.AUTO_MUZZLE: _draw_auto_muzzle()
		Mode.AUTO_IMPACT: _draw_auto_impact()
		Mode.GRID: _draw_grid()

func _fade() -> float:
	return clampf(1.0 - elapsed / maxf(lifetime, 0.001), 0.0, 1.0)

func _draw_tripwire() -> void:
	if not (target and is_instance_valid(target)):
		return
	var to := target.global_position - global_position
	var length := to.length()
	if length < 1.0:
		return
	var dir := to / length
	var side := dir.orthogonal()
	# Throw -> taut snap -> discharge. The line grows during the first beat and
	# then vibrates around a straight cable instead of reading as a generic beam.
	var grow := clampf(elapsed / 0.16, 0.0, 1.0)
	var end := to * grow
	var pts := PackedVector2Array()
	var segments := 18
	for i in range(segments + 1):
		var f := float(i) / float(segments)
		var snap := sin(f * PI) * sin(elapsed * 48.0 + f * 20.0) * 7.0 * _fade()
		pts.append(end * f + side * snap)
	var a := _fade()
	draw_polyline(pts, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.30 * a), 10.0)
	draw_polyline(pts, Color(CYAN.r, CYAN.g, CYAN.b, 0.88 * a), 5.0)
	draw_polyline(pts, Color(YELLOW.r, YELLOW.g, YELLOW.b, a), 2.0)
	# A white-hot packet races down the now-taut wire.
	var packet_t := fmod(maxf(elapsed - 0.12, 0.0) * 3.2, 1.0)
	var packet := to * packet_t + side * sin(packet_t * PI) * 4.0
	draw_circle(packet, 9.0 * a, Color(CYAN.r, CYAN.g, CYAN.b, 0.25 * a))
	draw_circle(packet, 4.0 * a, WHITE_HOT)

func _draw_thunder_strike() -> void:
	# A huge sky-to-ground fork, anchored on the victim. The bolt slams in over
	# the opening 0.12s, blooms at contact, then leaves branching after-arcs.
	var slam := clampf(elapsed / 0.12, 0.0, 1.0)
	var a := _fade()
	var top := Vector2(0.0, -430.0)
	var strike_end := top.lerp(Vector2.ZERO, slam)
	var pts := PackedVector2Array()
	var segments := 14
	for i in range(segments + 1):
		var f := float(i) / float(segments)
		var fork := sin(float(i) * 7.31 + 1.7) * (26.0 * (1.0 - f) + 8.0)
		if i == 0 or i == segments:
			fork = 0.0
		pts.append(top.lerp(strike_end, f) + Vector2(fork, 0.0))
	draw_polyline(pts, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.38 * a), 30.0)
	draw_polyline(pts, Color(CYAN.r, CYAN.g, CYAN.b, 0.88 * a), 17.0)
	draw_polyline(pts, Color(YELLOW.r, YELLOW.g, YELLOW.b, a), 8.0)
	draw_polyline(pts, WHITE_HOT, 3.0)
	if slam >= 0.98:
		var impact_t := clampf((elapsed - 0.10) / 0.42, 0.0, 1.0)
		var impact_a := (1.0 - impact_t) * a
		draw_circle(Vector2.ZERO, 70.0 * impact_a, Color(CYAN.r, CYAN.g, CYAN.b, 0.22 * impact_a))
		draw_circle(Vector2.ZERO, 30.0 * impact_a, Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.88 * impact_a))
		draw_arc(Vector2.ZERO, 105.0 * impact_t, 0, TAU, 40,
			Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.85 * impact_a), 9.0 * impact_a)
		for i in range(12):
			var ang := float(i) * TAU / 12.0 + sin(float(i) * 4.2) * 0.18
			var reach := 48.0 + 92.0 * impact_t
			var mid := Vector2(cos(ang), sin(ang)) * reach * 0.52
			var side := Vector2(-sin(ang), cos(ang)) * sin(i * 3.7) * 13.0
			var end := Vector2(cos(ang), sin(ang)) * reach
			var branch := PackedVector2Array([Vector2.ZERO, mid + side, end])
			var col := YELLOW if i % 2 == 0 else CYAN
			draw_polyline(branch, Color(col.r, col.g, col.b, impact_a), 5.0 * impact_a)

func _draw_stun_residue() -> void:
	var a := minf(1.0, elapsed / 0.12) * minf(1.0, (lifetime - elapsed) / 0.25)
	var phase := elapsed * 8.0
	for ring in range(2):
		var r := 25.0 + ring * 9.0 + sin(phase + ring) * 3.0
		draw_arc(Vector2(0, -13), r, PI * 0.12, PI * 0.88, 18,
			Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.42 * a), 4.0)
	for i in range(5):
		var ang := phase + float(i) * TAU / 5.0
		var centre := Vector2(cos(ang) * 31.0, -27.0 + sin(ang) * 9.0)
		var fork := Vector2(cos(ang * 2.3), sin(ang * 2.3)) * 8.0
		draw_line(centre - fork, centre + fork, Color(CYAN.r, CYAN.g, CYAN.b, 0.85 * a), 3.0)
		draw_circle(centre, 2.5, Color(YELLOW.r, YELLOW.g, YELLOW.b, a))

func _draw_auto_muzzle() -> void:
	var t := elapsed / lifetime
	var a := _fade()
	for i in range(7):
		var ang := float(i) * TAU / 7.0 + elapsed * 9.0
		var reach := (12.0 + 28.0 * t) * (0.75 + float(i % 3) * 0.12)
		var p := Vector2(cos(ang), sin(ang)) * reach
		draw_line(Vector2.ZERO, p, Color(CYAN.r, CYAN.g, CYAN.b, 0.75 * a), 3.0)
	draw_circle(Vector2.ZERO, 16.0 * a, Color(YELLOW.r, YELLOW.g, YELLOW.b, 0.42 * a))
	draw_circle(Vector2.ZERO, 6.0 * a, WHITE_HOT)

func _draw_auto_impact() -> void:
	var t := elapsed / lifetime
	var a := _fade()
	for i in range(9):
		var ang := float(i) * TAU / 9.0 + sin(float(i) * 2.7) * 0.22
		var inner := Vector2(cos(ang), sin(ang)) * (5.0 + 8.0 * t)
		var outer := Vector2(cos(ang), sin(ang)) * (18.0 + 38.0 * t)
		var col := YELLOW if i % 2 == 0 else CYAN
		draw_line(inner, outer, Color(col.r, col.g, col.b, a), 3.5 * a)
	draw_arc(Vector2.ZERO, 42.0 * t, 0, TAU, 28,
		Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.65 * a), 5.0 * a)
	draw_circle(Vector2.ZERO, 13.0 * a, WHITE_HOT)

func _draw_grid() -> void:
	if not grid:
		return
	var fade_in := clampf(elapsed / 0.22, 0.0, 1.0)
	var fade_out := clampf((lifetime - elapsed) / 0.35, 0.0, 1.0)
	var master := fade_in * fade_out
	var charge := clampf(elapsed / 2.0, 0.0, 1.0)
	var pulse := maxf(0.0, 1.0 - _pulse_age / 0.34)
	var line_alpha := master * (0.275 + charge * 0.30 + pulse * 0.475)
	# Each perspective cell is outlined so the art footprint exactly matches the
	# gameplay footprint; a translucent fill rolls across on each damage tick.
	for y in range(grid.grid_height):
		for x in range(grid.grid_width):
			var q := BoardPerspective.cell_quad(x, y, grid.grid_width, grid.grid_height, grid.cell_size)
			var poly := PackedVector2Array([q[0], q[1], q[2], q[3], q[0]])
			if pulse > 0.0:
				var wave := clampf(pulse - absf(float(y) / maxf(grid.grid_height - 1, 1) - (1.0 - pulse)) * 0.42, 0.0, 1.0)
				draw_colored_polygon(PackedVector2Array([q[0], q[1], q[2], q[3]]),
					Color(VIOLET.r, VIOLET.g, VIOLET.b, wave * 0.1625 * master))
			draw_polyline(poly, Color(CYAN.r, CYAN.g, CYAN.b, line_alpha), 3.0)
	# Charged nodes and short jumping forks make the grid feel energized rather
	# than like a static UI overlay. Density escalates during the channel.
	for y in range(grid.grid_height + 1):
		for x in range(grid.grid_width + 1):
			if (x + y) % 2 != 0 and charge < 0.75:
				continue
			var edge_y := mini(y, grid.grid_height - 1)
			var edge_x := mini(x, grid.grid_width - 1)
			var q := BoardPerspective.cell_quad(edge_x, edge_y, grid.grid_width, grid.grid_height, grid.cell_size)
			var p: Vector2
			if y == grid.grid_height:
				p = q[3] if x < grid.grid_width else q[2]
			else:
				p = q[0] if x < grid.grid_width else q[1]
			var flicker := 0.55 + 0.45 * sin(elapsed * 15.0 + x * 1.9 + y * 2.7)
			draw_circle(p, 2.5 + charge * 1.875, Color(YELLOW.r, YELLOW.g, YELLOW.b, master * flicker))
			if flicker > 0.82:
				var fork := Vector2(8.75 + charge * 10.0, -6.25) * (1.0 if (x + y) % 3 else -1.0)
				draw_line(p, p + fork, Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, master * 0.875), 2.5)
	if _lockdown_flash > 0.0:
		var board_h := BoardPerspective.row_top(grid.grid_height, grid.grid_height, float(grid.cell_size))
		draw_rect(Rect2(0, 0, grid.grid_width * grid.cell_size, board_h),
			Color(YELLOW.r, YELLOW.g, YELLOW.b, _lockdown_flash * 0.15), true)
