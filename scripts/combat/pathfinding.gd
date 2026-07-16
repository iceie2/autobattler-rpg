extends Node
class_name Pathfinding

# Simple A* pathfinding for the battle grid.
# Pass `mover` for units bigger than 1×1 (cell_size 2 = Hill Giant etc.): every
# searched cell is then treated as the unit's top-left ORIGIN and the whole
# footprint must fit. Before 2026-07-15 large units used a greedy one-stepper
# (_move_2x2_unit) whose perpendicular fallbacks ping-ponged them left/right
# forever when the direct approach was blocked — real A* detours instead.
static func find_path(start: Vector2i, goal: Vector2i, grid: BattleGrid, max_steps: int = 500, mover = null) -> Array[Vector2i]:
	if not grid.is_valid_position(start) or not grid.is_valid_position(goal):
		return []

	var footprint: int = _footprint_of(mover)

	# The goal cell is usually the target unit's own cell — path to the nearest
	# origin the mover can actually stand on instead.
	var target_pos = goal
	if footprint > 1:
		target_pos = find_nearest_free_origin(goal, grid, mover)
		if target_pos == Vector2i(-1, -1):
			return []  # No path possible
	elif grid.is_cell_occupied(goal):
		target_pos = find_nearest_unoccupied_to_target(goal, grid)
		if target_pos == Vector2i(-1, -1):
			return []  # No path possible

	var open_set: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0}
	var f_score: Dictionary = {start: heuristic(start, target_pos)}

	var iterations = 0
	while open_set.size() > 0 and iterations < max_steps:
		iterations += 1

		# Find node in open_set with lowest f_score
		var current = get_lowest_f_score(open_set, f_score)

		if current == target_pos:
			return reconstruct_path(came_from, current)

		open_set.erase(current)

		# Check all neighbors
		for neighbor in get_neighbors(current, grid):
			# Skip cells the mover can't stand on (1×1 keeps its old quirk of
			# allowing the goal cell itself as a pass-through).
			if footprint > 1:
				if not is_origin_free(neighbor, grid, mover):
					continue
			elif grid.is_cell_occupied(neighbor) and neighbor != goal:
				continue

			var tentative_g = g_score[current] + 1

			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + heuristic(neighbor, target_pos)

				if neighbor not in open_set:
					open_set.append(neighbor)

	return []  # No path found

static func _footprint_of(mover) -> int:
	return mover.cell_size if (mover != null and "cell_size" in mover) else 1

# Can `mover` stand with its top-left corner on `origin`? Cells occupied by the
# mover ITSELF count as free — a 2×2 unit stepping one cell overlaps most of
# its own current footprint.
static func is_origin_free(origin: Vector2i, grid: BattleGrid, mover) -> bool:
	var n: int = _footprint_of(mover)
	for dy in range(n):
		for dx in range(n):
			var p := origin + Vector2i(dx, dy)
			if not grid.is_valid_position(p):
				return false
			if grid.is_cell_occupied(p) and grid.get_unit_at(p) != mover:
				return false
	return true

# BFS outward from `goal` to the nearest origin whose whole footprint fits —
# the large-unit counterpart of find_nearest_unoccupied_to_target below.
static func find_nearest_free_origin(goal: Vector2i, grid: BattleGrid, mover) -> Vector2i:
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [goal]
	visited[goal] = true

	while queue.size() > 0:
		var current = queue.pop_front()
		if is_origin_free(current, grid, mover):
			return current
		for neighbor in get_all_neighbors(current):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			if grid.is_valid_position(neighbor):
				queue.append(neighbor)

	return Vector2i(-1, -1)

static func find_nearest_unoccupied_to_target(target: Vector2i, grid: BattleGrid) -> Vector2i:
	# BFS outward from target until we find an unoccupied cell
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [target]
	visited[target] = true

	while queue.size() > 0:
		var current = queue.pop_front()
		for neighbor in get_all_neighbors(current):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			if not grid.is_valid_position(neighbor):
				continue
			if not grid.is_cell_occupied(neighbor):
				return neighbor
			queue.append(neighbor)

	return Vector2i(-1, -1)

static func get_neighbors(pos: Vector2i, grid: BattleGrid) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	
	# 8-directional movement (including diagonals)
	var directions = [
		Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),  # Cardinal
		Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)  # Diagonal
	]
	
	for dir in directions:
		var neighbor = pos + dir
		if grid.is_valid_position(neighbor):
			neighbors.append(neighbor)
	
	return neighbors

static func get_all_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions = [
		Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)
	]
	
	for dir in directions:
		neighbors.append(pos + dir)
	
	return neighbors

static func heuristic(a: Vector2i, b: Vector2i) -> float:
	# Chebyshev distance (allows diagonal movement)
	return max(abs(a.x - b.x), abs(a.y - b.y))

static func get_lowest_f_score(open_set: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var lowest = open_set[0]
	var lowest_score = f_score.get(lowest, INF)
	
	for node in open_set:
		var score = f_score.get(node, INF)
		if score < lowest_score:
			lowest = node
			lowest_score = score
	
	return lowest

static func reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	
	while came_from.has(current):
		current = came_from[current]
		path.insert(0, current)
	
	return path
