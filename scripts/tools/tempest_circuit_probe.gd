extends Node
var fails: Array[String] = []
var checks := 0
var mgr: AutoBattleManager
var grid: BattleGrid
var boss: VisualUnit
var foes: Array = []
var shots: Node2D

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: fails.append(msg)

func place(unit: UnitBase, cell: Vector2i) -> void:
	grid.purge_unit(unit)
	unit.grid_position = cell
	check(grid.place_unit(unit,cell), "Test placement succeeds")
	unit.position = grid.grid_to_world(cell)

func owned_cells() -> int:
	var n := 0
	for owners in grid.passing_cells.values():
		if owners.has(boss): n += 1
	return n

func check_body() -> void:
	check(owned_cells() == 6, "Exactly six cells, with no stale occupancy")
	check(boss.segment_cells.size() == 6, "Head + four body sections + tail")
	for i in 6:
		check(grid.get_units_at(boss.segment_cells[i]).has(boss), "Each section targets the shared HP owner")
		if i > 0:
			var d: Vector2i = boss.segment_cells[i]-boss.segment_cells[i-1]
			check(absi(d.x)+absi(d.y) == 1, "Body remains cardinally connected")

func advance(dt: float = 1.0/30.0) -> void:
	mgr._tick_tempest_circuits(dt)
	mgr._tick_unit(boss,dt)
	mgr.update_unit_movements(dt)
	# These tests resolve projectiles separately; avoid automatic visual ticks.
	for shot in shots.get_children():
		if shot is Projectile: shot.set_process(false)

func await_warning(circuit: TempestCircuit, wanted: int) -> void:
	for frame in 900:
		advance()
		if not circuit.charging_cells.is_empty() and circuit.count == wanted+1: break
	check(not circuit.charging_cells.is_empty() and circuit.count == wanted+1, "Circuit %d warns automatically" % wanted)

func _ready() -> void:
	grid = BattleGrid.new(); add_child(grid)
	mgr = AutoBattleManager.new(); add_child(mgr); mgr.battle_grid = grid
	var effects := Node2D.new(); grid.add_child(effects); mgr.skill_effect_container = effects
	shots = Node2D.new(); grid.add_child(shots); mgr.projectile_container = shots
	boss = EnemyFactory.create_tempest_conduit(); grid.add_child(boss); boss.battle_manager = mgr
	# The feeding probe covers growth; keep this six-section baseline fixture.
	boss.set_meta("tempest_feeding",false)
	place(boss,Vector2i(4,3))
	for cell in [Vector2i(1,0),Vector2i(4,6),Vector2i(7,7)]:
		var u := UnitBase.new(); grid.add_child(u)
		u.max_hp = 100000; u.current_hp = 100000; u.is_player_unit = true; u.battle_manager = mgr
		u.current_element = UnitBase.Element.NORMAL; u.hp_regen = 0; u.resistance = 0; u.magic_resist = 0
		place(u,cell); foes.append(u)
	mgr.collect_units()
	check(mgr.enemy_units.size() == 1, "Six cells collect as one enemy/reward")
	check_body()
	check(boss.model3d != null and boss.snake_body.parts.size() == 5, "All six separate models load")
	for clip in ["idle","walk","attack","skill","ult","hurt","death"]:
		check(boss.model3d.has_animation(clip), "Head has "+clip)
		for part in boss.snake_body.parts: check(part.has_animation(clip), "Body/tail has "+clip)
	check(mgr._unit_dist(foes[0],boss) == 1 and foes[0].grid_position.distance_to(boss.grid_position) > 3, "Tail range works when head is far away")
	check(mgr.find_nearest_enemy(foes[0],[boss]) == boss, "Tail selects its single owner")
	var hp: int = boss.current_hp
	foes[0].attack_range = 1; foes[0].attack_damage = 100; foes[0].skill_cd_time = 999
	mgr._tick_unit(foes[0],0.01)
	check(boss.current_hp < hp, "Real melee auto damages shared HP from beside the tail")
	hp = boss.current_hp
	mgr._explosion(foes[0],boss.segment_cells[-1],100,[boss],1.0)
	check(hp-boss.current_hp == 100, "Tail-centred AoE hits shared HP once")
	hp = boss.current_hp
	mgr.resolve_precision_shot(foes[0],0,100)
	check(boss.current_hp < hp and hp-boss.current_hp < 200, "Row intersecting only body/tail hits once")
	check(boss.overlaps_cells([boss.segment_cells[-1]]) and not boss.overlaps_cells([Vector2i(8,8)]), "Cell hazards intersect body/tail")
	check(boss.overlaps_cells({boss.segment_cells[-1]:true}), "Dictionary-backed ground hazards intersect body/tail")
	hp = boss.current_hp
	mgr._nemi_tidal_waves.append({"caster":foes[0], "dmg":100, "push":0, "cx":2, "dir_y":1, "edge_row":8, "cur_row":0.0, "speed":0.0, "hit":{}, "effect":null})
	mgr._tick_nemi_tidal_waves(0.1); mgr._tick_nemi_tidal_waves(0.1)
	check(boss.current_hp < hp and hp-boss.current_hp < 200, "Tidal wave intersects tail row and hits owner once")
	mgr._nemi_tidal_waves.clear()
	var before_shift := boss.segment_cells.duplicate()
	# Head destination is clear but a lower body cell would overlap this hero.
	place(foes[2],Vector2i(3,1))
	check(mgr.try_displace_unit(boss,Vector2i(3,3)), "Whole-body displacement can share an occupied body cell")
	check(grid.get_units_at(Vector2i(3,1)).has(boss) and grid.get_unit_at(Vector2i(3,1)) == foes[2], "Body overlap preserves the hero as a solid occupant")
	check(foes[2].grid_position == Vector2i(3,1), "Body never pushes the overlapped hero")
	check(mgr.try_displace_unit(boss,Vector2i(4,3)), "Shared-cell displacement returns safely")
	check(not mgr.try_displace_unit(boss,Vector2i(4,-1)), "Whole-body displacement still rejects board boundaries")
	check(boss.segment_cells == before_shift and owned_cells() == 6, "Rejected boundary displacement restores every section")
	place(foes[2],Vector2i(7,7))
	check(mgr.try_displace_unit(boss,Vector2i(4,4)), "Legal knockback moves whole snake")
	for i in 6: check(boss.segment_cells[i] == before_shift[i]+Vector2i.DOWN, "Knockback translates every section together")
	check(mgr.try_displace_unit(boss,Vector2i(4,3)), "Snake returns from displacement")

	# Atomic failed movement, real per-section interpolation, and tail re-entry.
	var old := boss.segment_cells.duplicate()
	mgr.start_unit_movement(boss,boss.grid_position,old[1])
	check(boss.segment_cells == old and not boss.is_moving, "Head cannot move into its own unvacated body")
	place(foes[2],Vector2i(4,4))
	var hero_pos: Vector2 = foes[2].position
	hp = foes[2].current_hp
	mgr.start_unit_movement(boss,boss.grid_position,Vector2i(4,4))
	check(boss.is_moving and boss.grid_position == foes[2].grid_position, "Head moves directly through a hero's occupied cell")
	check(foes[2].position == hero_pos and foes[2].current_hp == hp, "Passing through does not push or deal contact damage")
	check(grid.get_units_at(Vector2i(4,4)).has(boss) and grid.get_unit_at(Vector2i(4,4)) == foes[2], "Head and hero remain separate targetable occupants")
	check(grid.inspection_unit_at(Vector2i(4,4)) == foes[2] and grid.inspection_unit_at(Vector2i(4,4),foes[2]) == boss and grid.inspection_unit_at(Vector2i(4,4),boss) == foes[2], "Shared-square inspection cycles through both live units")
	check(mgr._unit_dist(foes[2],boss) == 0, "Shared-cell combat distance reaches Tempest")
	hp = boss.current_hp; foes[2].attack_damage = 100; foes[2].attack(boss)
	check(boss.current_hp < hp, "Hero can attack shared HP while underneath the head")
	mgr.update_single_unit_movement(boss,1)
	# Heroes can also walk into snake-only cells; the enemy is not a wall.
	var hero_from: Vector2i = foes[2].grid_position
	var shared_body: Vector2i = boss.segment_cells[1]
	check(not grid.is_cell_occupied(shared_body) and Pathfinding.is_origin_free(shared_body,grid,foes[2]), "Snake-only cells are free for hero movement")
	mgr.start_unit_movement(foes[2],hero_from,shared_body)
	mgr.update_single_unit_movement(foes[2],1)
	check(grid.get_unit_at(shared_body) == foes[2] and grid.get_units_at(shared_body).has(boss), "Hero movement into a body section preserves both occupants")
	grid.purge_unit(foes[2])
	check(grid.get_unit_at(shared_body) == boss, "Purging an overlapped hero preserves Tempest")
	place(foes[2],Vector2i(7,7))
	# Keep the per-section interpolation fixture on a fresh six-cell shape.
	grid.purge_unit(boss); boss.segment_cells.clear(); boss.segment_previous_cells.clear()
	place(boss,Vector2i(4,3)); old = boss.segment_cells.duplicate()
	check_body()
	mgr.start_unit_movement(boss,boss.grid_position,Vector2i(4,4))
	check(boss.segment_cells.slice(1) == old.slice(0,5), "Body follows head history")
	mgr.update_single_unit_movement(boss,0.25)
	var halfway := grid.to_global(grid.grid_to_world(old[5])).lerp(grid.to_global(grid.grid_to_world(old[4])),boss.move_progress)
	check(boss.section_canvas_position(5).is_equal_approx(halfway), "Tail interpolates its own previous cell")
	mgr.update_single_unit_movement(boss,1)
	check_body()
	grid.purge_unit(boss)
	boss.segment_cells = [Vector2i(3,3),Vector2i(3,2),Vector2i(2,2),Vector2i(1,2),Vector2i(1,3),Vector2i(2,3)]
	boss.grid_position = boss.segment_cells[0]; grid.place_unit(boss,boss.grid_position)
	mgr.start_unit_movement(boss,boss.grid_position,Vector2i(2,3))
	check(boss.is_moving and boss.grid_position == Vector2i(2,3), "Head can enter the simultaneously vacating tail cell")
	mgr.update_single_unit_movement(boss,1)
	check_body()
	grid.purge_unit(boss); boss.segment_cells.clear(); boss.segment_previous_cells.clear()
	place(boss,Vector2i(4,3))

	# Tail auto uses MAG, magic mitigation, APS and tail origin.
	boss.magic_power = 200; boss.attack_damage = 1; boss.current_element = UnitBase.Element.NORMAL
	foes[0].resistance = 999; foes[0].magic_resist = 0
	boss.attack_cooldown = 0
	mgr._tick_tempest_tail_auto(boss,foes)
	var bolt: Projectile = shots.get_child(shots.get_child_count()-1)
	check(bolt.is_magic and bolt.is_basic_auto and bolt.damage == 200, "Tail basic attack scales with MAG and is magic-typed")
	check(bolt.start_pos.is_equal_approx(boss.section_canvas_position(5)), "Bolt leaves tail, never head")
	var launch_point := bolt.global_position
	mgr.paused = true; bolt._process(0.2); mgr.paused = false
	check(bolt.global_position == launch_point, "Tail bolt respects combat pause")
	hp = foes[0].current_hp
	bolt.on_reach_target()
	check(hp-foes[0].current_hp == 200, "Magic auto ignores physical armor and uses magic mitigation")
	check(boss.attack_cooldown > 0, "Tail rate uses attack speed cooldown")
	place(foes[2],Vector2i(2,2))
	boss.taunt_source = foes[2]; boss.taunt_time = 2; boss.attack_cooldown = 0
	mgr._tick_tempest_tail_auto(boss,foes)
	var taunted_bolt: Projectile = shots.get_child(shots.get_child_count()-1)
	check(taunted_bolt.target_unit == foes[2], "Tail attack still honors taunt")
	boss.taunt_time = 0; boss.taunt_source = null; place(foes[2],Vector2i(7,7))
	foes[0].spawn_projectile(boss,100)
	var aimed: Projectile = shots.get_child(shots.get_child_count()-1)
	check(aimed.target_section == 5, "Hero projectile targets closest section")
	mgr.start_unit_movement(boss,boss.grid_position,Vector2i(4,4)); mgr.update_single_unit_movement(boss,0.25)
	check(aimed.live_target_position().is_equal_approx(boss.section_canvas_position(5)), "Homing follows selected section as it moves")
	mgr.update_single_unit_movement(boss,1)

	# No skill cast needed; movement and independent tail autos start at zero mana.
	boss.current_mana = 0; boss.skill_cd_time = 999; boss.attack_cooldown = 0
	mgr._tick_tempest_circuits(0.01)
	var circuit: TempestCircuit = mgr._tempest_circuits[boss.get_instance_id()]
	check(boss.is_moving, "Movement starts immediately with no mana/cooldown gate")
	await_warning(circuit,1)
	check(circuit.charging_cells.size() == TempestCircuit.STEPS+1, "Normal circuit has three reached steps")
	check(boss.channel != null and not boss.channel.blocks_actions and boss.is_moving, "Warning never stops head/body or tail auto")
	# Rift's Tear damages Tempest without teleporting, stopping its step, or
	# replacing the already announced circuit. Ordinary targets still banish.
	var rift := UnitBase.new(); rift.unit_class = UnitBase.UnitClass.RIFT
	rift.is_player_unit = true; rift.magic_power = 100; rift.battle_manager = mgr
	grid.add_child(rift); rift.position = foes[0].position
	var cells_before_tear := boss.segment_cells.duplicate()
	var previous_before_tear := boss.segment_previous_cells.duplicate()
	var position_before_tear := boss.position
	var progress_before_tear := boss.move_progress
	var channel_before_tear := boss.channel
	var warning_before_tear := circuit.warning_cells()
	hp = boss.current_hp
	mgr._rift_tear(rift,[boss])
	check(boss.current_hp < hp, "Immune Tempest still takes Tear magic damage")
	check(boss.segment_cells == cells_before_tear and boss.segment_previous_cells == previous_before_tear, "Tear never relocates any Tempest section")
	check(boss.position == position_before_tear and boss.move_progress == progress_before_tear and boss.is_moving, "Tear preserves the in-flight snake step")
	check(boss.channel == channel_before_tear and circuit.warning_cells() == warning_before_tear, "Tear preserves the active circuit warning")
	check_body()
	var normal := UnitBase.new(); normal.current_hp = 10000; normal.max_hp = 10000
	grid.add_child(normal); normal.battle_manager = mgr
	place(normal,Vector2i(8,8))
	mgr._rift_tear(rift,[normal])
	check(normal.grid_position != Vector2i(8,8) and grid.get_unit_at(normal.grid_position) == normal, "Tear still teleports an ordinary target")
	grid.purge_unit(normal); normal.free(); rift.free()
	var seen := {}
	var charging_moves := 0
	var auto_during_warning := false
	var initial_position := boss.position
	var initial_shots := shots.get_child_count()
	for frame in 20:
		advance()
		seen[boss.grid_position] = true
		if boss.position != initial_position: charging_moves += 1
		if shots.get_child_count() > initial_shots: auto_during_warning = true
	check(charging_moves > 15, "Body moves throughout discharge warning")
	check(auto_during_warning, "Tail fires during warning")
	# Put a hero on a vacated circuit cell, outside all body cells.
	var marked := Vector2i(-1,-1)
	for cell in circuit.warning_cells():
		if not grid.is_cell_occupied(cell): marked = cell; break
	check(marked != Vector2i(-1,-1), "Continuous snake vacates cells behind its tail")
	if marked != Vector2i(-1,-1):
		place(foes[0],marked)
		hp = foes[0].current_hp
		mgr._tick_channel(boss,boss.channel.remaining-0.01)
		check(foes[0].current_hp == hp, "Discharge waits for the entire warning duration")
		mgr._tick_channel(boss,0.02)
		check(foes[0].current_hp < hp, "Warning discharges onto promised cells")
		hp = foes[0].current_hp; circuit.tick(0.1)
		check(foes[0].current_hp == hp, "Trail has no continuous damage")
	else: mgr._tick_channel(boss,2)
	check(circuit.memory.size() == 1, "Spent circuit persists")
	place(foes[0],Vector2i(0,8))
	await_warning(circuit,2); mgr._tick_channel(boss,2)
	check(circuit.memory.size() == 2, "Exactly two normal paths remembered")
	await_warning(circuit,3)
	check(circuit.charging_surge and boss.channel.id == "Storm Surge", "Third circuit is Storm Surge")
	check(circuit.charging_cells.size() == TempestCircuit.SURGE_STEPS+1, "Surge lays six steps")
	var old_cell: Vector2i = circuit.memory[0]["cells"][0]
	check(circuit.warning_cells().has(old_cell), "Surge recharges old path")
	if not grid.is_cell_occupied(old_cell):
		place(foes[0],old_cell)
		hp = foes[0].current_hp
		circuit.memory.append({"cells":[old_cell], "fx":null, "flash":0.0})
		mgr._tick_channel(boss,2)
		check(hp-foes[0].current_hp == int(boss.magic_power*TempestCircuit.SURGE_DAMAGE_MULT), "Overlapping paths damage hero exactly once")
	else: mgr._tick_channel(boss,2)
	check(circuit.memory.is_empty(), "Surge consumes old paths")
	for frame in 1200:
		advance(); seen[boss.grid_position] = true
		if frame % 30 == 0: check_body()
	check(seen.size() >= 18, "Keeps travelling to varied cells for an extended battle")

	# Existing tenacity/stun immunity test remains active.
	var ten := boss.tenacity
	mgr.apply_stun(boss,2)
	check(boss.stun_time == 0 and boss.tenacity == ten, "Elite immunity does not erase tenacity")
	for frame in 300:
		advance()
		if boss.channel: break
	check(boss.channel != null, "Stun toggle tested during active warning")
	var immunity := Balance.BOSS_ELITE_STUN_IMMUNITY_TEST
	Balance.BOSS_ELITE_STUN_IMMUNITY_TEST = false
	mgr.apply_stun(boss,2); mgr._tick_channel(boss,0.01)
	check(boss.stun_time > 0 and boss.channel == null, "Disabling immunity restores tenacity-scaled stun and warning interruption")
	Balance.BOSS_ELITE_STUN_IMMUNITY_TEST = immunity
	boss.stun_time = 0
	boss.current_hp = 0; mgr._tick_tempest_circuits(0.1)
	check(mgr._tempest_circuits.is_empty() and circuit.memory.is_empty() and circuit.flashes.is_empty(), "Death clears all circuits")
	check(boss.channel == null, "Death cancels discharge warning")
	grid.purge_unit(boss)
	check(owned_cells() == 0, "Death purge removes every section")
	mgr._clear_tempest_circuits()
	check_dense_overlap()
	for msg in fails: print("TEMPEST: FAIL ",msg)
	print("TEMPEST: ALL PASS (%d checks)" % checks if fails.is_empty() else "TEMPEST: FAILED")
	get_tree().quit(0 if fails.is_empty() else 1)

# Even a completely occupied board cannot box the snake in. All heroes retain
# their solid cells, and roster collection includes Tempest exactly once.
func check_dense_overlap() -> void:
	var dense := BattleGrid.new(); dense.grid_width = 3; dense.grid_height = 3; add_child(dense)
	var battle := AutoBattleManager.new(); add_child(battle); battle.battle_grid = dense
	var heroes: Array = []
	for y in 3:
		for x in 3:
			var hero := UnitBase.new(); dense.add_child(hero); hero.is_player_unit = true
			hero.max_hp = 100000; hero.current_hp = 100000
			hero.grid_position = Vector2i(x,y); hero.position = dense.grid_to_world(hero.grid_position)
			check(dense.place_unit(hero,hero.grid_position), "Dense-board hero placement")
			heroes.append(hero)
	var snake := UnitBase.new(); dense.add_child(snake)
	snake.is_player_unit = false
	snake.set_meta("segmented_snake",true); snake.set_meta("phase_through_units",true)
	snake.grid_position = Vector2i(1,1); snake.position = dense.grid_to_world(snake.grid_position)
	snake.movement_speed = 4; snake.battle_manager = battle
	check(dense.place_unit(snake,snake.grid_position), "Six connected sections spawn on a fully occupied board")
	battle.collect_units()
	check(battle.enemy_units == [snake] and battle.player_units.size() == 9, "Fully overlapped snake collects once with every hero intact")
	var controller := TempestCircuit.new(battle,snake); controller.begin(heroes)
	var visited := {}
	for frame in 100:
		controller.tick(0.2)
		if snake.channel: battle._tick_channel(snake,0.2)
		battle.update_single_unit_movement(snake,0.2)
		visited[snake.grid_position] = true
	check(visited.size() >= 6, "Fully occupied board does not stop automatic continuous travel")
	for hero in heroes:
		check(dense.get_unit_at(hero.grid_position) == hero and hero.position == dense.grid_to_world(hero.grid_position), "Dense travel preserves every hero's solid cell and position")
	controller.clear()
	var shared: Vector2i = snake.segment_cells[0]
	var hero = dense.get_unit_at(shared)
	dense.purge_unit(snake)
	check(dense.get_units_at(shared) == [hero] and dense.occupied_cells.size() == 9 and dense.passing_cells.is_empty(), "Purging the overlapped snake preserves all heroes")
	check(dense.place_unit(snake,snake.grid_position), "Snake can be registered again after cleanup")
	var ordinary := UnitBase.new(); dense.add_child(ordinary)
	check(not dense.place_unit(ordinary,shared), "Ordinary units still cannot overwrite another hero")
	ordinary.free()
	snake.free()
	check(dense.sweep_phantoms() == 6 and dense.get_all_units().size() == 9 and dense.get_unit_at(shared) == hero, "Freed passing sections are swept without removing overlapped heroes")
	dense.clear_grid()
	check(dense.passing_cells.is_empty() and dense.occupied_cells.is_empty() and dense.get_all_units().is_empty(), "Battle reset clears both occupancy layers")
	battle.free(); dense.free()
