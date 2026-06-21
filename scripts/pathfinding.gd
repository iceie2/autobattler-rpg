extends Node
class_name Pathfinding

# Simple A* pathfinding for the battle grid
static func find_path(start: Vector2i, goal: Vector2i, grid: BattleGrid, max_steps: int = 20) -> Array[Vector2i]:
	if not grid.is_valid_position(start) or not grid.is_valid_position(goal):
		return []
	
	# If goal is occupied, find path to adjacent cell
	var target_pos = goal
	if grid.is_cell_occupied(goal):
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
			# Skip occupied cells unless it's the goal
			if grid.is_cell_occupied(neighbor) and neighbor != goal:
				continue
			
			var tentative_g = g_score[current] + 1
			
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + heuristic(neighbor, target_pos)
				
				if neighbor not in open_set:
					open_set.append(neighbor)
	
	return []  # No path found

static func find_nearest_unoccupied_to_target(target: Vector2i, grid: BattleGrid) -> Vector2i:
	# Find nearest unoccupied cell adjacent to target
	var neighbors = get_all_neighbors(target)
	var best_pos = Vector2i(-1, -1)
	
	for neighbor in neighbors:
		if grid.is_valid_position(neighbor) and not grid.is_cell_occupied(neighbor):
			return neighbor  # Return first valid one
	
	return best_pos

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
