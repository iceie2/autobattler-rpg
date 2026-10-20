extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")
var manager: AutoBattleManager
var boss: VisualUnit
var circuit: TempestCircuit
var grid: BattleGrid

func label_at(text: String, pos: Vector2, size: int = 22) -> Label:
	var label := Label.new(); label.text = text; label.position = pos
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color(0.75,0.94,1.0))
	label.add_theme_constant_override("outline_size",4)
	label.add_theme_color_override("font_outline_color",Color(0.02,0.04,0.09))
	add_child(label)
	return label

func advance() -> void:
	manager._tick_tempest_circuits(1.0/30)
	manager._tick_unit(boss,1.0/30)
	manager.update_unit_movements(1.0/30)

func snap(file: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(CapturePaths.out(file))

func _ready() -> void:
	get_window().size = Vector2i(1180,800)
	get_window().content_scale_size = Vector2i(1180,800)
	var backdrop := ColorRect.new(); backdrop.size = Vector2(1180,800)
	backdrop.color = Color(0.025,0.045,0.075); add_child(backdrop)
	CapturePaths.cli_round(55)
	var bg := BackgroundLayer.new(); add_child(bg); bg.set_biome_from_round(55)
	bg.scale = Vector2.ONE * (78.0/110.0); bg.position = Vector2(36,60)
	grid = BattleGrid.new(); grid.cell_size = 78; grid.position = Vector2(36,60); add_child(grid)
	var units := Node2D.new(); grid.add_child(units)
	var effects := Node2D.new(); grid.add_child(effects)
	var shots := Node2D.new(); grid.add_child(shots)
	manager = AutoBattleManager.new(); add_child(manager)
	manager.battle_grid = grid; manager.skill_effect_container = effects; manager.projectile_container = shots
	boss = EnemyFactory.create_tempest_conduit(); units.add_child(boss)
	boss.battle_manager = manager; boss.grid_position = Vector2i(5,3)
	grid.place_unit(boss,boss.grid_position); boss.position = grid.grid_to_world(boss.grid_position)
	manager.enemy_units = [boss]
	var heroes: Array = []
	for cell in [Vector2i(4,5),Vector2i(2,6),Vector2i(6,6)]:
		var hero := UnitFactory.create_unit(UnitBase.UnitClass.CROSS,UnitBase.Element.NORMAL,true)
		units.add_child(hero); hero.grid_position = cell; hero.position = grid.grid_to_world(cell)
		grid.place_unit(hero,cell); hero.battle_manager = manager
		hero.max_hp = 100000; hero.current_hp = 100000; heroes.append(hero)
	manager.player_units = heroes
	label_at("TEMPEST CONDUIT · LIVING STORM",Vector2(36,14),28)
	var length_label := label_at("ONE SNAKE · SHARED HP",Vector2(775,130),25)
	label_at("Head\nBody sections\nTail",Vector2(790,180),23)
	label_at("Hit any section\nOne shared HP pool",Vector2(775,330),22)
	label_at("Always moving\nTail fires magic bolts\nCircuits follow the tail",Vector2(775,445),22)
	label_at("Every third circuit:\nSTORM SURGE\nRecharges the last two paths",Vector2(775,595),21)
	await get_tree().create_timer(0.3).timeout
	if "--feeding" in OS.get_cmdline_user_args():
		label_at("STORM FEAST\nFood heals 3% max HP\n+1 section · +5% movement",Vector2(775,700),19)
		boss.current_hp = boss.max_hp-3000; boss.hp_regen = 0
		length_label.text = "6 SECTIONS · 4.00 MOVE"
		advance(); circuit = manager._tempest_circuits[boss.get_instance_id()]
		for frame in 600:
			advance(); await get_tree().process_frame
			if circuit.food_cell != TempestCircuit.NO_FOOD: break
		await snap("tempest_food_target.png")
		for frame in 900:
			advance(); await get_tree().process_frame
			if boss.tempest_food_eaten == 1: break
		length_label.text = "%d SECTIONS · %.2f MOVE" % [boss.segment_cells.size(),boss.effective_movement_speed()]
		await snap("tempest_food_swallow.png")
		for frame in 900:
			advance(); await get_tree().process_frame
			if boss.tempest_food_eaten == 2: break
		length_label.text = "%d SECTIONS · %.2f MOVE" % [boss.segment_cells.size(),boss.effective_movement_speed()]
		await snap("tempest_food_grown.png")
		print("LIVING_STORM_CAPTURE: food, swallow and %d-section body saved" % boss.segment_cells.size())
		manager._clear_tempest_circuits(); get_tree().quit()
		return
	if "--pass-through" in OS.get_cmdline_user_args():
		var hero: VisualUnit = heroes[0]
		var shared := boss.grid_position + Vector2i.DOWN
		grid.purge_unit(hero); hero.grid_position = shared
		grid.place_unit(hero,shared); hero.position = grid.grid_to_world(shared)
		manager.start_unit_movement(boss,boss.grid_position,shared)
		for frame in 4:
			manager.update_single_unit_movement(boss,1.0/30)
			await get_tree().process_frame
		await snap("tempest_snake_passing_head.png")
		manager.update_single_unit_movement(boss,1)
		grid.purge_unit(hero); hero.grid_position = boss.segment_cells[3]
		grid.place_unit(hero,hero.grid_position); hero.position = grid.grid_to_world(hero.grid_position)
		await snap("tempest_snake_passing_body.png")
		print("LIVING_STORM_CAPTURE: shared head and body squares saved")
		get_tree().quit()
		return
	advance()
	circuit = manager._tempest_circuits[boss.get_instance_id()]
	await snap("tempest_snake_start.png")
	for cycle in range(1,4):
		for frame in 700:
			advance()
			await get_tree().process_frame
			if not circuit.charging_cells.is_empty() and circuit.count == cycle+1: break
		for frame in 15:
			advance()
			await get_tree().process_frame
		await snap("tempest_snake_warning.png" if cycle == 1 else ("tempest_snake_surge.png" if cycle == 3 else "tempest_snake_middle.png"))
		if cycle == 1:
			var hero: VisualUnit = heroes[0]
			for cell in circuit.warning_cells():
				if not grid.is_cell_occupied(cell):
					grid.purge_unit(hero); hero.grid_position = cell
					grid.place_unit(hero,cell); hero.position = grid.grid_to_world(cell)
					break
		for frame in 100:
			advance()
			await get_tree().process_frame
			if circuit.charging_cells.is_empty(): break
		if cycle == 1: await snap("tempest_snake_discharge.png")
	print("LIVING_STORM_CAPTURE: six-section snake start, warning, discharge, surge saved")
	manager._clear_tempest_circuits()
	get_tree().quit()
