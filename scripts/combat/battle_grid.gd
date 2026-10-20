extends Node2D
class_name BattleGrid

# Grid size - 9x9 grid (square cells)
@export var grid_width: int = 9
@export var grid_height: int = 9
@export var cell_size: int = 110

# Grid data structure
var grid_cells: Array = []
var occupied_cells: Dictionary = {}
# Nonblocking occupants share squares with solid units without replacing them.
var passing_cells: Dictionary = {}

# Visual
var grid_color: Color = Color(0.2, 0.2, 0.3, 0.5)
var highlight_color: Color = Color(0.4, 0.6, 0.8, 0.7)

signal cell_clicked(grid_pos: Vector2i)
signal unit_placed(unit, grid_pos: Vector2i)
signal unit_removed(grid_pos: Vector2i)

func _ready():
	initialize_grid()

func initialize_grid() -> void:
	grid_cells.clear()
	occupied_cells.clear()
	passing_cells.clear()
	
	for y in range(grid_height):
		var row = []
		for x in range(grid_width):
			row.append(null)
		grid_cells.append(row)
	
	queue_redraw()

func _draw():
	# Grid lines follow the same trapezoids the tiles are drawn as, so the lines
	# converge toward the far edge instead of staying a square lattice.
	for y in range(grid_height):
		for x in range(grid_width):
			var q := BoardPerspective.cell_quad(x, y, grid_width, grid_height, cell_size)
			draw_line(q[0], q[1], grid_color, 2.0)   # top
			draw_line(q[3], q[0], grid_color, 2.0)   # left
			if x == grid_width - 1:
				draw_line(q[1], q[2], grid_color, 2.0)
			if y == grid_height - 1:
				draw_line(q[2], q[3], grid_color, 2.0)

func world_to_grid(world_pos: Vector2) -> Vector2i:
	var local_pos = to_local(world_pos)
	# floori, NOT int() (2026-07-24): int() truncates TOWARD ZERO, so any point
	# left of / above the board (local -54px, say) mapped to cell 0 instead of
	# -1 — i.e. every off-board position on those two sides silently reported as
	# a real in-bounds cell, and is_valid_position() then happily approved it.
	# floori sends them to -1/-2/… so out-of-bounds actually reads as
	# out-of-bounds and drag placement rejects it.
	# Perspective-aware (see BoardPerspective): cells are trapezoids of differing
	# height, so a flat divide would target the wrong row/column everywhere
	# except the front of the board.
	return BoardPerspective.world_to_cell(local_pos, grid_width, grid_height, cell_size)

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return BoardPerspective.cell_centre(
		float(grid_pos.x), float(grid_pos.y), grid_width, grid_height, cell_size)

## How much a unit standing on `row` is scaled down by distance. 1.0 at the front
## of the board, BoardPerspective.FAR_SCALE at the back.
func row_scale(row: int) -> float:
	return BoardPerspective.row_scale(float(row), grid_height)

func is_valid_position(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < grid_width and \
		   grid_pos.y >= 0 and grid_pos.y < grid_height

func is_cell_occupied(grid_pos: Vector2i) -> bool:
	# Movement/placement tests only solid occupants. Use get_units_at for hits
	# and inspection, or get_all_units when collecting the combat roster.
	return occupied_cells.has(grid_pos)

func place_unit(unit, grid_pos: Vector2i) -> bool:
	var size: int = unit.cell_size if "cell_size" in unit else 1
	var cells: Array[Vector2i] = []
	var passing: bool = bool(unit.get_meta("phase_through_units", false))
	if unit is UnitBase:
		if unit.get_meta("segmented_snake", false) and unit.segment_cells.is_empty():
			cells = [grid_pos]
			if not _extend_snake(cells, 6, passing): return false
		else: cells = unit.footprint_at(grid_pos)
	else:
		for dy in size:
			for dx in size: cells.append(grid_pos + Vector2i(dx, dy))
	# Validate the whole shape before writing ANY cell.
	for p in cells:
		if not is_valid_position(p) or (not passing and is_cell_occupied(p)): return false
	if unit is UnitBase:
		unit.combat_grid = self
		if unit.get_meta("segmented_snake", false):
			unit.segment_cells = cells
			if unit.segment_previous_cells.is_empty(): unit.segment_previous_cells = cells.duplicate()
	for p in cells:
		if passing:
			if not passing_cells.has(p): passing_cells[p] = []
			if not passing_cells[p].has(unit): passing_cells[p].append(unit)
		else:
			occupied_cells[p] = unit
			grid_cells[p.y][p.x] = unit
	unit_placed.emit(unit, grid_pos)
	return true

# Reserve a connected six-cell body at spawn, curling when a board edge or
# another solid unit blocks the straight tail. Passing snakes may share cells.
func _extend_snake(cells: Array[Vector2i], length: int, passing: bool = false) -> bool:
	if not is_valid_position(cells[-1]) or (not passing and is_cell_occupied(cells[-1])): return false
	if cells.size() == length: return true
	for direction in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
		var cell: Vector2i = cells[-1] + direction
		if cells.has(cell) or not is_valid_position(cell) or (not passing and is_cell_occupied(cell)): continue
		cells.append(cell)
		if _extend_snake(cells, length, passing): return true
		cells.pop_back()
	return false

func remove_unit(grid_pos: Vector2i) -> void:
	var unit = get_unit_at(grid_pos)
	if unit == null:
		return
	_erase_cells_of(unit)
	unit_removed.emit(grid_pos)

# Identity-based removal — clears every cell registered to `unit` no matter
# what its grid_position currently says.
#
# remove_unit(pos) is position-keyed, and that is only correct while a unit's
# grid_position matches its registered cells. Any place_unit() that fails (its
# return is ignored in several callers) breaks that tie, and then the
# position-keyed removal at death/despawn/sell silently NO-OPS: the dead unit's
# real cells stay in occupied_cells forever, pointing at a freed node. Nothing
# ever clears them — occupied_cells outlives the round — so they become an
# invisible wall that blocks MOVEMENT but not ranged attacks (which never
# consult occupancy). Exactly the failure already fixed once for Khagan's
# dismount (see EnemyFactory.advance_khagan_phase), only reachable from any
# unit, and it compounds across a run: 1×1 mobs still weave through the gaps,
# while a 2×2 boss needing a clear 2×2 origin gets pinned and stands there
# taking ranged fire (2026-08-07 user report, wave-50 Emberhollow).
#
# Prefer this over remove_unit(unit.grid_position) anywhere the unit is in hand.
func purge_unit(unit) -> void:
	if unit == null:
		return
	var anchor: Vector2i = unit.grid_position if "grid_position" in unit else Vector2i(-1, -1)
	if _erase_cells_of(unit) > 0:
		unit_removed.emit(anchor)

# Drops any cell whose occupant no longer exists (freed node) or is dead.
# Returns the number of cells reclaimed. Called at every battle start so a save
# that ALREADY accumulated phantom cells heals itself instead of staying stuck.
func sweep_phantoms() -> int:
	var to_erase: Array[Vector2i] = []
	for pos in occupied_cells:
		var u = occupied_cells[pos]
		# A freed Object is falsy in GDScript, so `not u` covers queue_free'd
		# nodes; is_instance_valid covers the rest.
		if not u or not is_instance_valid(u):
			to_erase.append(pos)
	for pos in to_erase:
		occupied_cells.erase(pos)
		grid_cells[pos.y][pos.x] = null
	var reclaimed := to_erase.size()
	for pos in passing_cells.keys():
		var live: Array = []
		for u in passing_cells[pos]:
			if u and is_instance_valid(u): live.append(u)
			else: reclaimed += 1
		if live.is_empty(): passing_cells.erase(pos)
		else: passing_cells[pos] = live
	return reclaimed

func _erase_cells_of(unit) -> int:
	var to_erase: Array[Vector2i] = []
	for pos in occupied_cells:
		if occupied_cells[pos] == unit:
			to_erase.append(pos)
	for pos in to_erase:
		occupied_cells.erase(pos)
		grid_cells[pos.y][pos.x] = null
	var removed := to_erase.size()
	for pos in passing_cells.keys():
		var owners: Array = passing_cells[pos]
		if owners.has(unit):
			owners.erase(unit)
			removed += 1
		if owners.is_empty(): passing_cells.erase(pos)
	return removed

func get_unit_at(grid_pos: Vector2i):
	var units := get_units_at(grid_pos)
	return units[0] if not units.is_empty() else null

func get_units_at(grid_pos: Vector2i) -> Array:
	var result: Array = []
	var solid = occupied_cells.get(grid_pos)
	if solid and is_instance_valid(solid): result.append(solid)
	for unit in passing_cells.get(grid_pos, []):
		if unit and is_instance_valid(unit) and not result.has(unit): result.append(unit)
	return result

# Cell lookup prefers a hero standing there; repeated inspection reaches the
# passing enemy too. Both retain their own effective live stats and HP.
func inspection_unit_at(grid_pos: Vector2i, current = null):
	var units := get_units_at(grid_pos)
	if units.is_empty(): return null
	var index: int = units.find(current)
	return units[(index+1) % units.size()]

func get_all_units() -> Array:
	var result: Array = []
	for unit in occupied_cells.values():
		if unit and is_instance_valid(unit) and not result.has(unit): result.append(unit)
	for owners in passing_cells.values():
		for unit in owners:
			if unit and is_instance_valid(unit) and not result.has(unit): result.append(unit)
	return result

func clear_grid() -> void:
	occupied_cells.clear()
	initialize_grid()

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var grid_pos = world_to_grid(event.position)
		if is_valid_position(grid_pos):
			cell_clicked.emit(grid_pos)
