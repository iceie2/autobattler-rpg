extends Node

var fails: Array[String] = []
var checks := 0
var grid: BattleGrid
var manager: AutoBattleManager
var boss: VisualUnit
var heroes: Array = []
var shots: Node2D
var game
var save_existed := false
var save_backup := ""

func _exit_tree() -> void:
	if save_existed:
		var file := FileAccess.open(RunSave.PATH,FileAccess.WRITE)
		if file: file.store_string(save_backup)
	else: RunSave.clear()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails.append(message)

func advance(dt: float = 1.0/30.0) -> void:
	manager._tick_tempest_circuits(dt)
	manager._tick_unit(boss,dt)
	manager.update_unit_movements(dt)
	for shot in shots.get_children(): shot.set_process(false)

func check_body() -> void:
	var owned := 0
	for owners in grid.passing_cells.values():
		if owners.has(boss): owned += 1
	check(owned == boss.segment_cells.size(),"Growing body has no phantom cells")
	check(boss.snake_body.parts.size() == boss.segment_cells.size()-1,"Every added body section has a model")
	check(boss.segment_previous_cells.size() == boss.segment_cells.size(),"Growth retains interpolation for every section")
	var unique := {}
	for i in boss.segment_cells.size():
		var cell: Vector2i = boss.segment_cells[i]
		check(grid.is_valid_position(cell) and grid.get_units_at(cell).has(boss),"Each grown cell targets shared HP")
		check(not unique.has(cell),"Growing snake cannot overlap its own body")
		unique[cell] = true
		if i > 0:
			var delta: Vector2i = cell-boss.segment_cells[i-1]
			check(absi(delta.x)+absi(delta.y) == 1,"Growth stays cardinally connected")

func check_display(expected: float) -> void:
	game.show_unit_details(boss); game._details.refresh_live()
	var value: Label = game._details.combat_grid.get_node("CellMove/Value")
	check(value.text.contains("%.2f" % expected),"Live movement display agrees with combat's shared accessor")
	check(value.tooltip_text.contains("%d food eaten" % boss.tempest_food_eaten),"Live tooltip shows the current food stack count")
	check(game._details.skill_desc_lbl.text.contains("Storm Feast") and game._details.skill_desc_lbl.text.contains("Current length: %d" % boss.segment_cells.size()),"Live kit displays feeding and current body length")

func _ready() -> void:
	save_existed = FileAccess.file_exists(RunSave.PATH)
	if save_existed:
		var file := FileAccess.open(RunSave.PATH,FileAccess.READ)
		if file: save_backup = file.get_as_text()
	game = load("res://scenes/main_game.tscn").instantiate(); add_child(game)
	for frame in 30: await get_tree().process_frame
	seed(55)
	grid = BattleGrid.new(); add_child(grid)
	manager = AutoBattleManager.new(); add_child(manager); manager.battle_grid = grid
	var effects := Node2D.new(); grid.add_child(effects); manager.skill_effect_container = effects
	shots = Node2D.new(); grid.add_child(shots); manager.projectile_container = shots
	boss = EnemyFactory.create_tempest_conduit(); grid.add_child(boss)
	boss.battle_manager = manager; boss.grid_position = Vector2i(4,3)
	boss.hp_regen = 0; boss.current_hp = boss.max_hp-3000
	check(grid.place_unit(boss,boss.grid_position),"Feeding fixture placement")
	boss.position = grid.grid_to_world(boss.grid_position)
	for cell in [Vector2i(1,0),Vector2i(4,6),Vector2i(7,7)]:
		var hero := UnitBase.new(); grid.add_child(hero)
		hero.max_hp = 100000; hero.current_hp = 100000; hero.is_player_unit = true
		hero.grid_position = cell; hero.position = grid.grid_to_world(cell); hero.battle_manager = manager
		check(grid.place_unit(hero,cell),"Feeding fixture hero placement"); heroes.append(hero)
	manager.collect_units()
	advance()
	var circuit: TempestCircuit = manager._tempest_circuits[boss.get_instance_id()]
	var original_tail: Model3DSprite = boss.snake_body.parts[-1]
	check(circuit.food_cell == TempestCircuit.NO_FOOD,"Food waits for the opening delay")
	check_display(4.0)
	for frame in 180:
		advance()
		if circuit.food_cell != TempestCircuit.NO_FOOD: break
	check(circuit.food_cell != TempestCircuit.NO_FOOD and circuit.clock >= TempestCircuit.FOOD_FIRST_DELAY,"Food appears on the combat timer")
	check(is_instance_valid(circuit.food_fx),"Food has a visible board mote")
	check(not boss.segment_cells.has(circuit.food_cell),"Food spawns outside the snake")
	check(manager.enemy_units == [boss] and grid.get_all_units().size() == 4,"Food creates no combat target, reward or blocking unit")
	var clock_before := circuit.clock
	var food_before := circuit.food_cell
	manager.paused = true; manager.battle_active = true; manager._process(1.0)
	check(circuit.clock == clock_before and circuit.food_cell == food_before,"Food and pursuit freeze when combat is paused")
	manager.paused = false; manager.battle_active = false
	# A body passing over the pickup cannot eat it; only the head can.
	circuit.food_cell = boss.segment_cells[1]
	circuit.tick(0)
	check(boss.tempest_food_eaten == 0,"Body/tail touching food cannot consume it")
	circuit.food_cell = food_before
	var visited := {}
	for frame in 900:
		advance(); visited[boss.grid_position] = true
		if boss.tempest_food_eaten == 1: break
	check(boss.tempest_food_eaten == 1,"Head naturally pursues and eats its food")
	check(boss.current_hp == boss.max_hp-3000+roundi(boss.max_hp*TempestCircuit.FOOD_HEAL_PCT),"Eating heals the stated max-HP percentage")
	check(boss.segment_cells.size() == 7,"One meal adds exactly one section")
	check(boss.snake_body.parts[-1] == original_tail,"Growth keeps the same animated tail")
	check(is_equal_approx(boss.effective_movement_speed(),4.2),"First meal adds precise 5% movement speed")
	check(is_equal_approx(boss.attacks_per_second,boss.attack_speed),"Food movement bonus does not alter attack speed")
	check(circuit.food_cell == TempestCircuit.NO_FOOD and circuit.food_flashes.size() == 1,"Swallowed mote is removed and plays one consume burst")
	check_body(); check_display(4.2)
	# The new tail cell remains a real shared-square melee/projectile target.
	var hero: UnitBase = heroes[0]
	var tail_cell: Vector2i = boss.segment_cells[-1]
	grid.purge_unit(hero); hero.grid_position = tail_cell; hero.position = grid.grid_to_world(tail_cell)
	check(grid.place_unit(hero,tail_cell),"Hero may share the longer snake's tail")
	check(manager._unit_dist(hero,boss) == 0,"Shared grown section is in melee range")
	boss.attack_cooldown = 0; manager._tick_tempest_tail_auto(boss,heroes)
	var bolt: Projectile = shots.get_child(shots.get_child_count()-1)
	check(bolt.start_pos.is_equal_approx(boss.section_canvas_position(6)),"Tail auto originates at the new last section")
	check(original_tail.is_oneshot_playing(),"Longer tail still animates its basic attack")
	hero.spawn_projectile(boss,100)
	var homing: Projectile = shots.get_child(shots.get_child_count()-1)
	check(homing.target_section == 6 and homing.live_target_position().is_equal_approx(boss.section_canvas_position(6)),"Hero homing can aim at the added tail section")
	var hp_before := boss.current_hp
	boss.current_shield = 1000; hero.attack_damage = 100; hero.attack(boss)
	check(boss.current_hp == hp_before and boss.current_shield < 1000,"Shielded hit on a grown section resolves once against the owner")
	boss.current_shield = 0; hero.attack(boss)
	check(boss.current_hp < hp_before,"Grown tail melee damages the shared HP pool")
	check_display(4.2)
	# A second real meal stacks additively and clamps healing at max HP.
	boss.current_hp = boss.max_hp-120
	for frame in 900:
		advance(); visited[boss.grid_position] = true
		if boss.tempest_food_eaten == 2: break
	check(boss.tempest_food_eaten == 2 and boss.segment_cells.size() == 8,"Respawned food produces a second independent growth")
	check(boss.current_hp == boss.max_hp,"Food healing cannot exceed max HP")
	check(is_equal_approx(boss.effective_movement_speed(),4.4),"Two meals are +10%, without compounding or integer rounding")
	check(visited.size() >= 8,"Feeding keeps moving across the board")
	check_body(); check_display(4.4)
	boss.slow_time = 2; boss.slow_pct = 0.25
	check(is_equal_approx(boss.effective_movement_speed(),3.3),"Food speed combines with the live slow modifier")
	check_display(3.3)
	boss.move_progress = 0
	manager.update_single_unit_movement(boss,0.1)
	check(is_equal_approx(boss.move_progress,3.3*manager.base_movement_speed*0.1),"Actual interpolation uses exactly the displayed movement speed")
	manager._tick_statuses(boss,2.1)
	check_display(4.4)
	# A longer fight exercises pursuit and tail-following as the body length
	# continues increasing, rather than stopping verification at two meals.
	var extended_visits := {}
	for frame in 2400:
		advance(); extended_visits[boss.grid_position] = true
		if frame % 120 == 0: check_body()
	check(boss.tempest_food_eaten >= 5 and boss.segment_cells.size() == 6+boss.tempest_food_eaten,"Repeated food stays collectible as the snake gets longer")
	check(extended_visits.size() >= 18,"Longer snake keeps travelling instead of trapping itself")
	check_display(boss.effective_movement_speed())
	# Round cleanup removes food and restores the base body/stat immediately.
	manager._clear_tempest_circuits()
	check(boss.tempest_food_eaten == 0 and boss.tempest_move_bonus == 0 and boss.segment_cells.size() == 6,"Round cleanup resets food stacks and growth")
	check(circuit.food_cell == TempestCircuit.NO_FOOD and circuit.food_fx == null and circuit.food_flashes.is_empty(),"Round cleanup removes pickup and consume effects")
	check_body(); check_display(4.0)
	# Bare damage dummies have no visual health bar; initialize the real boss.
	var saved_players := manager.player_units
	manager.player_units = []; manager._init_unit_timers(); manager.player_units = saved_players
	check_display(4.0)
	advance(); circuit = manager._tempest_circuits[boss.get_instance_id()]
	for frame in 180:
		advance()
		if circuit.food_cell != TempestCircuit.NO_FOOD: break
	check(circuit.food_cell != TempestCircuit.NO_FOOD,"Fresh battle starts a fresh feeding loop")
	boss.current_hp = 0; manager._tick_tempest_circuits(0.1)
	check(manager._tempest_circuits.is_empty() and circuit.food_fx == null and circuit.food_cell == TempestCircuit.NO_FOOD,"Death removes uneaten food and the controller")
	grid.purge_unit(boss)
	check(grid.passing_cells.is_empty() and grid.get_unit_at(hero.grid_position) == hero,"Longer snake death leaves overlapping heroes intact")
	for message in fails: print("TEMPEST_FEED: FAIL ",message)
	print("TEMPEST_FEED: ALL PASS (%d checks)" % checks if fails.is_empty() else "TEMPEST_FEED: FAILED")
	get_tree().quit(0 if fails.is_empty() else 1)
