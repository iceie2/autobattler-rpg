extends Node
class_name AutoBattleManager

# References
var battle_grid: BattleGrid
var game_state: GameState
var projectile_container: Node2D  # Container for projectiles

# Battle state
var player_units: Array = []
var enemy_units: Array = []
var battle_active: bool = false
var battle_timer: float = 0.0
var action_delay: float = 0.5  # Time between actions (faster updates)

# Movement speed multiplier (higher = faster base movement)
var base_movement_speed: float = 0.5

# Unit movement paths
var unit_paths: Dictionary = {}  # unit -> Array[Vector2i]

signal battle_started()
signal battle_ended(player_won: bool)
signal unit_action(unit, action_type: String)

func _ready():
	pass

func initialize(grid: BattleGrid, state: GameState) -> void:
	battle_grid = grid
	game_state = state
	
	if game_state:
		game_state.auto_battle_started.connect(_on_auto_battle_started)

func _on_auto_battle_started() -> void:
	start_battle()

func start_battle() -> void:
	battle_active = true
	battle_timer = 0.0
	unit_paths.clear()
	collect_units()
	print("[Battle] Started — players: %d, enemies: %d" % [player_units.size(), enemy_units.size()])
	battle_started.emit()

func collect_units() -> void:
	player_units.clear()
	enemy_units.clear()

	if not battle_grid:
		print("[Battle] ERROR: battle_grid is null!")
		return

	print("[Battle] occupied_cells count: %d" % battle_grid.occupied_cells.size())
	for grid_pos in battle_grid.occupied_cells:
		var unit = battle_grid.get_unit_at(grid_pos)
		if unit and unit is UnitBase:
			unit.battle_manager = self
			if unit.is_player_unit:
				player_units.append(unit)
			else:
				enemy_units.append(unit)
		else:
			print("[Battle] Cell %s has non-unit or null: %s" % [grid_pos, unit])

func _process(delta: float) -> void:
	if not battle_active:
		return
	
	# Update all moving units
	update_unit_movements(delta)
	
	battle_timer += delta
	
	if battle_timer >= action_delay:
		battle_timer = 0.0
		execute_battle_turn()

func execute_battle_turn() -> void:
	# Player units move and attack
	for unit in player_units:
		if unit == null or not is_instance_valid(unit):
			continue
		var target = find_nearest_enemy(unit, enemy_units)
		if not target:
			print("[Battle] player unit has no target!")
			continue
		var dist = unit.grid_position.distance_to(target.grid_position)
		print("[Battle] player %s gpos=%s → target %s gpos=%s dist=%.1f range=%d moving=%s" % [
			unit.unit_name, unit.grid_position, target.unit_name, target.grid_position,
			dist, unit.attack_range, unit.is_moving])
		if unit.is_in_attack_range(target.grid_position):
			print("[Battle] player ATTACKING")
			unit.attack(target)
			unit_action.emit(unit, "attack")
			unit_paths.erase(unit)
		elif not unit.is_moving:
			print("[Battle] player MOVING")
			move_unit_towards_with_pathfinding(unit, target.grid_position)
			unit_action.emit(unit, "move")

	# Enemy units move and attack
	for unit in enemy_units:
		if unit == null or not is_instance_valid(unit):
			continue
		var target = find_nearest_enemy(unit, player_units)
		if not target:
			continue
		if unit.is_in_attack_range(target.grid_position):
			unit.attack(target)
			unit_action.emit(unit, "attack")
			unit_paths.erase(unit)
		elif not unit.is_moving:
			move_unit_towards_with_pathfinding(unit, target.grid_position)
			unit_action.emit(unit, "move")
	
	# Check battle end conditions
	check_battle_end()

func find_nearest_enemy(unit: UnitBase, enemies: Array) -> UnitBase:
	var nearest: UnitBase = null
	var min_distance: float = INF
	
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		
		var distance = unit.grid_position.distance_to(enemy.grid_position)
		if distance < min_distance:
			min_distance = distance
			nearest = enemy
	
	return nearest

func assign_preferred_target(unit: UnitBase, target: UnitBase) -> void:
	# This implements the "assign preferred target" from your flowchart
	unit.target_unit = target

func check_battle_end() -> void:
	# Remove dead units
	player_units = player_units.filter(func(u): return u != null and is_instance_valid(u))
	enemy_units = enemy_units.filter(func(u): return u != null and is_instance_valid(u))
	
	if enemy_units.is_empty():
		end_battle(true)
	elif player_units.is_empty():
		end_battle(false)

func end_battle(player_won: bool) -> void:
	battle_active = false
	battle_ended.emit(player_won)
	
	if game_state:
		game_state.end_auto_battle()

func move_unit_towards_with_pathfinding(unit: UnitBase, target_pos: Vector2i) -> void:
	if not battle_grid:
		return
	
	var current_pos = unit.grid_position
	
	# Check if we need a new path or if target moved
	var needs_new_path = false
	if not unit_paths.has(unit):
		needs_new_path = true
	else:
		var cached_path = unit_paths[unit]
		# If path is empty or target moved significantly, recalculate
		if cached_path.is_empty():
			needs_new_path = true
		elif cached_path.size() > 0:
			var path_goal = cached_path[cached_path.size() - 1]
			# Recalculate if target moved more than 2 cells from path goal
			if path_goal.distance_to(target_pos) > 2:
				needs_new_path = true
	
	if needs_new_path:
		var new_path = Pathfinding.find_path(current_pos, target_pos, battle_grid)
		if new_path.is_empty():
			print("[Path] NO PATH from %s to %s" % [current_pos, target_pos])
			return
		if new_path.size() > 0 and new_path[0] == current_pos:
			new_path.remove_at(0)
		unit_paths[unit] = new_path
		print("[Path] found len=%d first=%s" % [new_path.size(), new_path[0] if new_path.size() > 0 else "EMPTY"])

	var path = unit_paths[unit]
	if path.is_empty():
		print("[Path] path empty after cache")
		return

	var next_pos = path[0]
	var occupied = battle_grid.is_cell_occupied(next_pos)
	if not battle_grid.is_valid_position(next_pos) or occupied:
		print("[Path] next_pos %s blocked (occupied=%s)" % [next_pos, occupied])
		unit_paths.erase(unit)
		return

	if not unit.is_moving:
		start_unit_movement(unit, current_pos, next_pos)

func add_projectile(projectile: Projectile) -> void:
	if projectile_container:
		projectile_container.add_child(projectile)

func start_unit_movement(unit: UnitBase, from_pos: Vector2i, to_pos: Vector2i) -> void:
	print("[Move] START %s → %s" % [from_pos, to_pos])
	unit.is_moving = true
	unit.move_start_pos = battle_grid.grid_to_world(from_pos)
	unit.move_target_pos = battle_grid.grid_to_world(to_pos)
	unit.move_progress = 0.0
	unit.target_grid_pos = to_pos

	battle_grid.remove_unit(from_pos)
	var placed = battle_grid.place_unit(unit, to_pos)
	unit.grid_position = to_pos
	print("[Move] placed=%s gpos_after=%s is_moving=%s" % [placed, unit.grid_position, unit.is_moving])

func update_unit_movements(delta: float) -> void:
	# Update all player units
	for unit in player_units:
		if unit and is_instance_valid(unit) and unit.is_moving:
			update_single_unit_movement(unit, delta)
	
	# Update all enemy units
	for unit in enemy_units:
		if unit and is_instance_valid(unit) and unit.is_moving:
			update_single_unit_movement(unit, delta)

func update_single_unit_movement(unit: UnitBase, delta: float) -> void:
	# Calculate movement speed based on unit's movement_speed stat
	# Higher movement_speed = faster interpolation
	var speed_multiplier = unit.movement_speed * base_movement_speed
	unit.move_progress += delta * speed_multiplier
	
	if unit.move_progress >= 1.0:
		# Movement complete
		unit.position = unit.move_target_pos
		unit.is_moving = false
		unit.move_progress = 0.0
		
		# Remove completed step from path
		if unit_paths.has(unit):
			var path = unit_paths[unit]
			if path.size() > 0:
				path.remove_at(0)
				if path.is_empty():
					unit_paths.erase(unit)
	else:
		# Interpolate position
		unit.position = unit.move_start_pos.lerp(unit.move_target_pos, unit.move_progress)
