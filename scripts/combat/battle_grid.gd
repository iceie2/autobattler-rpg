extends Node2D
class_name BattleGrid

# Grid size - 9x9 grid (square cells)
@export var grid_width: int = 9
@export var grid_height: int = 9
@export var cell_size: int = 110

# Grid data structure
var grid_cells: Array = []
var occupied_cells: Dictionary = {}

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
	
	for y in range(grid_height):
		var row = []
		for x in range(grid_width):
			row.append(null)
		grid_cells.append(row)
	
	queue_redraw()

func _draw():
	# Draw grid lines
	for x in range(grid_width + 1):
		var start = Vector2(x * cell_size, 0)
		var end = Vector2(x * cell_size, grid_height * cell_size)
		draw_line(start, end, grid_color, 2.0)

	for y in range(grid_height + 1):
		var start = Vector2(0, y * cell_size)
		var end = Vector2(grid_width * cell_size, y * cell_size)
		draw_line(start, end, grid_color, 2.0)

func world_to_grid(world_pos: Vector2) -> Vector2i:
	var local_pos = to_local(world_pos)
	# floori, NOT int() (2026-07-24): int() truncates TOWARD ZERO, so any point
	# left of / above the board (local -54px, say) mapped to cell 0 instead of
	# -1 — i.e. every off-board position on those two sides silently reported as
	# a real in-bounds cell, and is_valid_position() then happily approved it.
	# floori sends them to -1/-2/… so out-of-bounds actually reads as
	# out-of-bounds and drag placement rejects it.
	var grid_x = floori(local_pos.x / cell_size)
	var grid_y = floori(local_pos.y / cell_size)
	return Vector2i(grid_x, grid_y)

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * cell_size + cell_size / 2.0,
		grid_pos.y * cell_size + cell_size / 2.0
	)

func is_valid_position(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < grid_width and \
		   grid_pos.y >= 0 and grid_pos.y < grid_height

func is_cell_occupied(grid_pos: Vector2i) -> bool:
	return occupied_cells.has(grid_pos)

func place_unit(unit, grid_pos: Vector2i) -> bool:
	var size: int = unit.cell_size if "cell_size" in unit else 1
	# Validate all cells first
	for dy in range(size):
		for dx in range(size):
			var p := grid_pos + Vector2i(dx, dy)
			if not is_valid_position(p) or is_cell_occupied(p):
				return false
	# Register all cells
	for dy in range(size):
		for dx in range(size):
			var p := grid_pos + Vector2i(dx, dy)
			occupied_cells[p] = unit
			grid_cells[p.y][p.x] = unit
	unit_placed.emit(unit, grid_pos)
	return true

func remove_unit(grid_pos: Vector2i) -> void:
	if not is_cell_occupied(grid_pos):
		return
	var unit = occupied_cells[grid_pos]
	# Remove all cells belonging to this unit
	var to_erase: Array[Vector2i] = []
	for pos in occupied_cells:
		if occupied_cells[pos] == unit:
			to_erase.append(pos)
	for pos in to_erase:
		occupied_cells.erase(pos)
		grid_cells[pos.y][pos.x] = null
	unit_removed.emit(grid_pos)

func get_unit_at(grid_pos: Vector2i):
	if is_cell_occupied(grid_pos):
		return occupied_cells[grid_pos]
	return null

func clear_grid() -> void:
	occupied_cells.clear()
	initialize_grid()

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var grid_pos = world_to_grid(event.position)
		if is_valid_position(grid_pos):
			cell_clicked.emit(grid_pos)
