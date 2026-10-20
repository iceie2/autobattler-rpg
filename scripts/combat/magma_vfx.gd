extends Node2D
class_name MagmaVFX

# Eruption lights actual perspective-correct board tiles, ring by ring.
enum Mode { HEART, ERUPT }
const BASALT := Color(0.10, 0.06, 0.05)
const MAGMA := Color(1.0, 0.42, 0.08)
const WHITE_HOT := Color(1.0, 0.97, 0.85)
const WAVE_TIME := 0.4
const COOL_TIME := 0.8

var mode: Mode = Mode.HEART
var host = null
var bm = null
var r := 66.0
var heart_y := 0.0
var ground_y := 55.0
var charge := 0.0
var pulses := 0
var max_pulses := 8
var _t := 0.0
var _beat := 0.0
var _pips: Node2D = null
var _tiles: Array = []
var _reach := 1

static func radius_for_cell(origin: Vector2i, footprint: int, cell: Vector2i) -> int:
	var dx: int = maxi(0, maxi(origin.x - cell.x, cell.x - (origin.x + footprint - 1)))
	var dy: int = maxi(0, maxi(origin.y - cell.y, cell.y - (origin.y + footprint - 1)))
	return maxi(dx, dy)

static func max_radius(grid: BattleGrid, origin: Vector2i, footprint: int) -> int:
	if not is_instance_valid(grid):
		return 1
	var reach := 0
	for cell in [Vector2i.ZERO, Vector2i(grid.grid_width - 1, 0),
		Vector2i(0, grid.grid_height - 1), Vector2i(grid.grid_width - 1, grid.grid_height - 1)]:
		reach = maxi(reach, radius_for_cell(origin, footprint, cell))
	return maxi(1, reach)

func setup_heart(unit) -> void:
	mode = Mode.HEART
	host = unit
	bm = unit.battle_manager
	r = MirrorVFX.body_r(unit)
	global_position = unit.global_position
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	_pips = Node2D.new()
	_pips.use_parent_material = false
	_pips.z_as_relative = false
	_pips.z_index = 1
	add_child(_pips)
	_pips.draw.connect(_draw_pips)
	_sync_body_anchor()

func _sync_body_anchor() -> void:
	if not is_instance_valid(host):
		return
	global_position = host.global_position
	z_index = host.z_index + 1
	ground_y = host.ground_offset() if host.has_method("ground_offset") else r * 0.85
	# The 3D lava core is near the sprite centre, not above its head.
	if host is VisualUnit:
		heart_y = host._sprite_base_offset.y + host._sprite_half_h * 0.05

func setup_erupt(unit, _target_positions: Array, grid: BattleGrid = null) -> void:
	mode = Mode.ERUPT
	bm = unit.battle_manager
	if grid == null and is_instance_valid(bm):
		grid = bm.battle_grid
	z_as_relative = false
	z_index = 1 # Same ground layer as Spore: above board, below units.
	global_position = Vector2.ZERO
	if not is_instance_valid(grid):
		return
	_reach = max_radius(grid, unit.grid_position, unit.cell_size)
	for y in grid.grid_height:
		for x in grid.grid_width:
			var q := BoardPerspective.cell_quad(x, y, grid.grid_width, grid.grid_height, grid.cell_size)
			var local_quad := PackedVector2Array()
			for pt in q:
				local_quad.append(to_local(grid.to_global(pt)))
			var radius := radius_for_cell(unit.grid_position, unit.cell_size, Vector2i(x, y))
			_tiles.append({"quad": local_quad, "arrival": WAVE_TIME * float(radius) / float(_reach)})
	queue_redraw()

func set_wave_time(elapsed: float) -> void:
	_t = elapsed
	queue_redraw()

func set_state(c: float, p: int) -> void:
	charge = clampf(c, 0.0, 1.0)
	pulses = p

func _process(delta: float) -> void:
	if is_instance_valid(bm):
		if bm.paused:
			return
		delta *= bm.time_scale
	_t += delta
	_beat += delta * lerpf(1.0, 4.0, charge * charge)
	if mode == Mode.HEART:
		if not is_instance_valid(host) or host.current_hp <= 0:
			queue_free()
			return
		_sync_body_anchor()
		_pips.queue_redraw()
	elif _t >= WAVE_TIME + COOL_TIME:
		queue_free()
	queue_redraw()

func _draw() -> void:
	if mode == Mode.HEART:
		_draw_heart()
	else:
		_draw_erupt()

func _draw_heart() -> void:
	var thump: float = pow(maxf(0.0, sin(fposmod(_beat, 1.0) * PI)), 6.0)
	var final: float = clampf((charge - 0.8) / 0.2, 0.0, 1.0)
	var c := Vector2(0, heart_y)
	var rad: float = r * (0.04 + 0.025 * thump + 0.04 * final)
	draw_circle(c, rad * 2.0, Color(MAGMA.r, MAGMA.g, MAGMA.b, 0.12 + final * 0.12))
	draw_circle(c, rad, Color(WHITE_HOT.r, WHITE_HOT.g, WHITE_HOT.b, 0.25 + final * 0.55))

func _draw_pips() -> void:
	_pips.draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.38))
	for i in max_pulses:
		var ang: float = PI + PI * (float(i) + 0.5) / float(max_pulses)
		var p := Vector2(cos(ang), -sin(ang)) * r
		_pips.draw_circle(p, 6.0, BASALT)
		if i < pulses:
			_pips.draw_circle(p, 4.0, MAGMA.lerp(WHITE_HOT, float(i) / float(max_pulses)))

func _draw_erupt() -> void:
	for tile in _tiles:
		var age: float = _t - float(tile["arrival"])
		if age < 0.0 or age >= COOL_TIME:
			continue
		var heat: float = 1.0 - age / COOL_TIME
		var hot: Color = MAGMA.lerp(WHITE_HOT, pow(heat, 7.0))
		var outline: PackedVector2Array = tile["quad"].duplicate()
		outline.append(outline[0])
		draw_polyline(outline, Color(hot.r, hot.g, hot.b, 0.85 * heat), 2.0, true)
