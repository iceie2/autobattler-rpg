extends RefCounted
class_name TempestCircuit

const STEPS := 3
const SURGE_STEPS := 6
const WARNING := 1.1
const SURGE_WARNING := 1.4
const DAMAGE_MULT := 1.0
const SURGE_DAMAGE_MULT := 1.6
const DISCHARGE_LIFE := 0.6
const FOOD_FIRST_DELAY := 4.0
const FOOD_RESPAWN_DELAY := 6.0
const FOOD_HEAL_PCT := 0.03
const FOOD_MOVE_PER_MEAL := 0.05
const NO_FOOD := Vector2i(-1,-1)
const DIRECTIONS := [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]

var manager: AutoBattleManager
var caster: UnitBase
var opponents: Array = []
var phase := "idle"
var trail: Array[Vector2i] = []
var charging_cells: Array[Vector2i] = []
var memory: Array = []
var flashes: Array = []
var count := 1
var steps_left := STEPS
var surge := false
var charging_surge := false
var clock := 0.0
var fx: TempestTrailVFX
var charging_fx: TempestTrailVFX
var target: UnitBase
var last_arrival := Vector2i(-1, -1)
var recent: Array[Vector2i] = []
var food_cell := NO_FOOD
var food_timer := FOOD_FIRST_DELAY
var food_fx: TempestFoodVFX
var food_flashes: Array[TempestFoodVFX] = []
var growth_pending := 0

static func feeding_description(unit: UnitBase) -> String:
	return "Storm Feast: a food mote appears after %.0fs, then %.0fs after each meal. The head seeks it; eating heals %.0f%% max HP, adds one body section and stacks +%.0f%% base movement speed for this battle. All sections share HP. Eaten: %d. Movement bonus: +%.0f%%. Current length: %d." % [FOOD_FIRST_DELAY,FOOD_RESPAWN_DELAY,FOOD_HEAL_PCT*100,FOOD_MOVE_PER_MEAL*100,unit.tempest_food_eaten,unit.tempest_move_bonus*100,maxi(6,unit.segment_cells.size())]

func _init(battle: AutoBattleManager, serpent: UnitBase) -> void:
	manager = battle
	caster = serpent

func begin(enemies: Array) -> void:
	opponents = enemies
	if phase != "idle" or not manager.battle_grid or caster.segment_cells.size() < 6: return
	phase = "laying"
	trail = [caster.segment_cells[-1]]
	last_arrival = caster.grid_position
	caster.set_meta("tempest_travelling", true)
	manager.unit_paths.erase(caster)
	fx = _new_fx(false)
	if not caster.is_moving: _step()

func _new_fx(is_surge: bool) -> TempestTrailVFX:
	if not manager.skill_effect_container: return null
	var node := TempestTrailVFX.new()
	manager.skill_effect_container.add_child(node)
	node.setup(manager.battle_grid, is_surge)
	return node

func tick(dt: float) -> void:
	clock += dt
	if not manager._is_alive(caster): clear(); return
	for item in memory:
		item["flash"] = maxf(0.0, float(item["flash"])-dt)
	for i in range(flashes.size()-1, -1, -1):
		flashes[i]["left"] -= dt
		if flashes[i]["left"] <= 0:
			if is_instance_valid(flashes[i]["fx"]): flashes[i]["fx"].queue_free()
			flashes.remove_at(i)
	if phase == "idle": begin(opponents)
	_tick_food(dt)
	if caster.stun_time > 0: _update_fx(); return
	if not caster.is_moving:
		if last_arrival != caster.grid_position:
			var delta := caster.grid_position-last_arrival
			if absi(delta.x)+absi(delta.y) != 1:
				on_displaced()
			else:
				last_arrival = caster.grid_position
				trail.append(caster.segment_cells[-1])
				steps_left -= 1
				recent.append(last_arrival)
				if recent.size() > 18: recent.pop_front()
		if food_cell != NO_FOOD and caster.grid_position == food_cell: _eat_food()
		if steps_left <= 0 and charging_cells.is_empty() and not caster.channel: _charge()
		_step()  # warning and tail casting never stop travel
	_update_fx()

func _legal(cell: Vector2i, shape: Array[Vector2i], growing: bool = false) -> bool:
	if not manager.battle_grid.is_valid_position(cell): return false
	if (shape if growing else shape.slice(0, shape.size()-1)).has(cell): return false
	if caster.get_meta("phase_through_units", false): return true
	var occupant = manager.battle_grid.get_unit_at(cell)
	return occupant == null or occupant == caster

# Simulate a moving tail to avoid steering the body into a dead end.
func _escape_depth(shape: Array[Vector2i], depth: int) -> int:
	if depth == 0: return 0
	var best := 0
	for direction in DIRECTIONS:
		var cell: Vector2i = shape[0] + direction
		if not _legal(cell, shape): continue
		var next: Array[Vector2i] = [cell]
		next.append_array(shape.slice(0, shape.size()-1))
		best = maxi(best, 1 + _escape_depth(next, depth-1))
		if best == depth: break
	return best

func _step() -> void:
	if caster.is_moving or caster.root_time > 0 or caster.movement_speed <= 0: return
	target = manager._choose_target(caster, opponents)
	var growing := growth_pending > 0
	if growing:
		var has_room := false
		for direction in DIRECTIONS:
			if _legal(caster.grid_position+direction, caster.segment_cells, true): has_room = true
		# Continue slithering until the tail opens room for the earned segment.
		if not has_room: growing = false
	var food_step := _food_next_step()
	var best := Vector2i(-1,-1)
	var score := -INF
	for direction in DIRECTIONS:
		var cell: Vector2i = caster.grid_position + direction
		if not _legal(cell, caster.segment_cells, growing): continue
		var next: Array[Vector2i] = [cell]
		next.append_array(caster.segment_cells if growing else caster.segment_cells.slice(0, caster.segment_cells.size()-1))
		var safety := _escape_depth(next, 5)
		var distance: float = target.grid_distance_to(cell) if manager._is_alive(target) else 3.0
		var value := float(safety)*30.0 - absf(distance-2.5)*2.0
		# Visit new ground, while keeping the fight near heroes.
		value -= float(recent.count(cell))*4.0
		value += Vector2(caster.last_move_direction).normalized().dot(Vector2(direction))*0.3
		if cell == food_step and safety == 5: value += 1000.0
		if value > score: score = value; best = cell
	if best != NO_FOOD:
		var before: int = caster.segment_cells.size()
		manager.start_unit_movement(caster, caster.grid_position, best, growing)
		if caster.segment_cells.size() > before: growth_pending -= 1

func _food_search() -> Dictionary:
	var start := caster.grid_position
	var previous := {start:start}
	var distance := {start:0}
	var queue: Array[Vector2i] = [start]
	var blocked := caster.segment_cells.slice(1, caster.segment_cells.size()-1)
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]; cursor += 1
		for direction in DIRECTIONS:
			var next: Vector2i = cell+direction
			if not manager.battle_grid.is_valid_position(next) or blocked.has(next) or previous.has(next): continue
			if not caster.get_meta("phase_through_units",false) and manager.battle_grid.is_cell_occupied(next) and manager.battle_grid.get_unit_at(next) != caster: continue
			previous[next] = cell; distance[next] = int(distance[cell])+1; queue.append(next)
	return {"previous":previous, "distance":distance}

func _food_next_step() -> Vector2i:
	if food_cell == NO_FOOD: return NO_FOOD
	var previous: Dictionary = _food_search()["previous"]
	if not previous.has(food_cell) or food_cell == caster.grid_position: return NO_FOOD
	var cell := food_cell
	while previous[cell] != caster.grid_position: cell = previous[cell]
	return cell

func _tick_food(dt: float) -> void:
	for i in range(food_flashes.size()-1,-1,-1):
		var burst := food_flashes[i]
		burst.advance(dt)
		if burst.finished(): burst.queue_free(); food_flashes.remove_at(i)
	if not caster.get_meta("tempest_feeding",false): return
	if is_instance_valid(food_fx): food_fx.advance(dt)
	if food_cell != NO_FOOD or growth_pending > 0: return
	food_timer -= dt
	if food_timer <= 0 and not caster.is_moving:
		_spawn_food()
		if food_cell == NO_FOOD: food_timer = 0.5

func _spawn_food() -> void:
	var search := _food_search()
	var candidates: Array[Vector2i] = []
	for cell in search["distance"]:
		var distance: int = search["distance"][cell]
		if distance >= 3 and distance <= 6 and not caster.segment_cells.has(cell): candidates.append(cell)
	if candidates.is_empty(): return
	food_cell = candidates[randi_range(0,candidates.size()-1)]
	if manager.skill_effect_container:
		food_fx = TempestFoodVFX.new(); manager.skill_effect_container.add_child(food_fx)
		food_fx.setup(manager.battle_grid,food_cell)
	manager.action_logged.emit("Storm Feast: a food mote appears for %s" % caster.unit_name,caster.is_player_unit)

func _eat_food() -> void:
	if food_cell == NO_FOOD or not manager._is_alive(caster): return
	caster.heal(maxi(1,roundi(caster.max_hp*FOOD_HEAL_PCT)),false,caster)
	caster.tempest_food_eaten += 1
	caster.tempest_move_bonus = caster.tempest_food_eaten*FOOD_MOVE_PER_MEAL
	growth_pending += 1
	if is_instance_valid(food_fx):
		food_fx.consume(); food_flashes.append(food_fx)
	food_fx = null; food_cell = NO_FOOD; food_timer = FOOD_RESPAWN_DELAY
	manager.action_logged.emit("%s eats Storm Feast: grows one section and gains 5%% movement speed (%d meals)" % [caster.unit_name,caster.tempest_food_eaten],caster.is_player_unit)

func _charge() -> void:
	charging_cells = trail.duplicate()
	charging_surge = surge
	charging_fx = fx
	phase = "charging"
	manager.start_channel(caster, "Storm Surge" if charging_surge else "Close the Circuit",
		SURGE_WARNING if charging_surge else WARNING, _discharge,
		{"blocks":false, "color":TempestTrailVFX.ICE, "on_interrupt":func(_reason): _cancel_warning()})
	manager.unit_action.emit(caster, "skill")
	manager.action_logged.emit("%s charges %s while moving" % [caster.unit_name, "Storm Surge" if charging_surge else "its circuit"], caster.is_player_unit)
	# Immediately start the next path; the charging path has its own VFX.
	count += 1
	surge = count % 3 == 0
	steps_left = SURGE_STEPS if surge else STEPS
	trail = [caster.segment_cells[-1]]
	fx = _new_fx(surge)

func warning_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = charging_cells.duplicate()
	if charging_surge:
		for item in memory:
			for cell in item["cells"]:
				if not result.has(cell): result.append(cell)
	return result

func _discharge() -> void:
	if not manager._is_alive(caster): clear(); return
	var marked := warning_cells()
	var damage := maxi(1, int(caster.magic_power*(SURGE_DAMAGE_MULT if charging_surge else DAMAGE_MULT)))
	for enemy in opponents:
		if not manager._is_alive(enemy): continue
		var on_path := false
		for cell in enemy.combat_cells():
			if marked.has(cell): on_path = true; break
		if on_path:
			var before: int = enemy.current_hp
			enemy.take_magic_damage(damage, caster.current_element, caster)
			caster.damage_dealt += maxi(0, before-enemy.current_hp)
	if charging_surge:
		for item in memory: flashes.append({"cells":item["cells"], "fx":item["fx"], "left":DISCHARGE_LIFE})
		memory.clear()
		flashes.append({"cells":charging_cells.duplicate(), "fx":charging_fx, "left":DISCHARGE_LIFE})
	else:
		if memory.size() >= 2:
			var oldest: Dictionary = memory.pop_front()
			if is_instance_valid(oldest["fx"]): oldest["fx"].queue_free()
		memory.append({"cells":charging_cells.duplicate(), "fx":charging_fx, "flash":DISCHARGE_LIFE})
	manager.action_logged.emit("%s discharges %s!" % [caster.unit_name, "Storm Surge" if charging_surge else "its circuit"], caster.is_player_unit)
	charging_cells.clear()
	charging_fx = null
	phase = "laying"
	_update_fx()

func _update_fx() -> void:
	var p: float = caster.channel.progress() if is_instance_valid(caster) and caster.channel else 0.0
	if is_instance_valid(fx): fx.show_state(trail, "laying", 0, clock, caster.section_canvas_position(caster.segment_cells.size()-1))
	if is_instance_valid(charging_fx): charging_fx.show_state(charging_cells, "charging", p, clock, Vector2.ZERO)
	for item in memory:
		var state: String = "charging" if not charging_cells.is_empty() and charging_surge else ("discharge" if item["flash"] > 0 else "dormant")
		if is_instance_valid(item["fx"]): item["fx"].show_state(item["cells"], state, p, clock, Vector2.ZERO)
	for item in flashes:
		if is_instance_valid(item["fx"]): item["fx"].show_state(item["cells"], "discharge", 1-float(item["left"])/DISCHARGE_LIFE, clock, Vector2.ZERO)

func owns_turn() -> bool:
	return phase != "idle"

func on_displaced() -> void:
	# Teleports/pulls aren't snake steps. Restart only the uncharged tail path;
	# an already announced circuit still fires on its promised cells.
	last_arrival = caster.grid_position
	trail = [caster.segment_cells[-1]]
	steps_left = SURGE_STEPS if surge else STEPS
	if is_instance_valid(fx): fx.show_state(trail, "laying", 0, clock, caster.section_canvas_position(caster.segment_cells.size()-1))

func _cancel_warning() -> void:
	if is_instance_valid(charging_fx): charging_fx.queue_free()
	charging_fx = null
	charging_cells.clear()
	phase = "laying"

func clear() -> void:
	if is_instance_valid(caster):
		caster.set_meta("tempest_travelling", false)
		if caster.channel and caster.channel.id in ["Close the Circuit", "Storm Surge"]: manager.cancel_channel(caster, "storm ended")
	_cancel_warning()
	if is_instance_valid(fx): fx.queue_free()
	fx = null
	for item in memory + flashes:
		if is_instance_valid(item["fx"]): item["fx"].queue_free()
	memory.clear()
	flashes.clear()
	if is_instance_valid(food_fx): food_fx.queue_free()
	food_fx = null
	for burst in food_flashes:
		if is_instance_valid(burst): burst.queue_free()
	food_flashes.clear()
	food_cell = NO_FOOD; food_timer = FOOD_FIRST_DELAY; growth_pending = 0
	if is_instance_valid(caster): caster.reset_tempest_growth()
	trail.clear()
	phase = "idle"
