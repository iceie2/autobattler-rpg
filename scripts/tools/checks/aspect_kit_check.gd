extends Node

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var world := Node2D.new()
	add_child(world)
	var grid := BattleGrid.new()
	world.add_child(grid)
	var m := AutoBattleManager.new()
	world.add_child(m)
	m.set_process(false)
	m.battle_grid = grid
	var u := EnemyFactory.create_aspect_devourer()
	world.add_child(u)
	u.battle_manager = m
	u.grid_position = Vector2i(3, 1)
	grid.place_unit(u, u.grid_position)
	u.position = m._world_pos_for(u, u.grid_position)
	var hero := UnitBase.new()
	hero.is_player_unit = true
	hero.max_hp = 100000; hero.current_hp = 100000
	world.add_child(hero)
	hero.grid_position = Vector2i(7, 6)
	grid.place_unit(hero, hero.grid_position)
	hero.position = m._world_pos_for(hero, hero.grid_position)
	m.enemy_units = [u]; m.player_units = [hero]
	if "--capture" in OS.get_cmdline_user_args():
		get_window().size = Vector2i(800, 650)
		u.position = Vector2(400, 410)
		hero.visible = false
		for element in AutoBattleManager.ASPECT_CYCLE:
			u.current_element = element
			m._sync_aspect_aura(u)
			for frame in 8: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://../captures/aspect-element-%d.png" % element)
		u.position = m._world_pos_for(u, u.grid_position)
	for element in AutoBattleManager.ASPECT_CYCLE:
		u.current_element = element
		assert(u.accepts_damage_element(element))
		for wrong in AutoBattleManager.ASPECT_CYCLE:
			if wrong == element: continue
			var hp := u.current_hp
			u.current_shield = 100
			u.take_damage(999, wrong, hero, true, 999)
			assert(u.current_hp == hp and u.current_shield == 100)
			u.current_shield = 0
			u.take_magic_damage(999, wrong, hero)
			assert(u.current_hp == hp)
		u.current_shield = 100
		u.take_damage(10, element, null, true)
		assert(u.current_shield == 90)
		u.current_shield = 0
		var hp := u.current_hp
		u.take_damage(10, element, null, true)
		assert(u.current_hp < hp)
		hp = u.current_hp
		u.take_magic_damage(100, element, null)
		assert(u.current_hp < hp)
		assert(AspectKit.description(u).contains("only takes"))
	AspectKit.reset(u)
	u.set_meta("aspect_t", 3.0)
	AspectKit.tick(m, u, [hero], 0.01)
	assert(u.get_meta("aspect_busy"))
	AspectKit.tick(m, u, [hero], AspectKit.TELL)
	AspectKit.tick(m, u, [hero], AspectKit.TRAVEL)
	var hp := hero.current_hp
	# Put the victim inside the fixed breath cone after the landing.
	var a: Dictionary = u.get_meta("aspect_action")
	hero.global_position = a.origin + a.direction * 110.0
	AspectKit.tick(m, u, [hero], AspectKit.BREATH_TELL)
	assert(hero.current_hp < hp and not u.get_meta("aspect_busy"))
	var count := 0
	for value in grid.occupied_cells.values():
		if value == u: count += 1
	assert(count == 4)
	# The mark stays fixed: moving away avoids landing damage, and the cone
	# stays fixed too, so a target behind it is safe.
	AspectKit.reset(u)
	u.set_meta("aspect_t", 3.0)
	AspectKit.tick(m, u, [hero], 0.01)
	hero.grid_position = Vector2i(-20, -20)
	hp = hero.current_hp
	AspectKit.tick(m, u, [hero], AspectKit.TELL)
	AspectKit.tick(m, u, [hero], AspectKit.TRAVEL)
	assert(hero.current_hp == hp)
	a = u.get_meta("aspect_action")
	hero.global_position = a.origin - a.direction * 110.0
	AspectKit.tick(m, u, [hero], AspectKit.BREATH_TELL)
	assert(hero.current_hp == hp)
	AspectKit.reset(u)
	assert(u.current_element == UnitBase.Element.NORMAL and u.get_meta("aspect_t") == 6.0)
	assert(u.get_meta("aspect_action").is_empty() and not u.get_meta("aspect_pounced"))
	for i in 6:
		m._tick_mob_passive(u, [hero], [u], 6.0)
		assert(u.current_element == AutoBattleManager.ASPECT_CYCLE[(i + 1) % 6])
	print("ASPECT_KIT_CHECK: ALL PASS")
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit()
