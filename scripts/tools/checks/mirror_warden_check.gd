extends Node2D

func _ready() -> void:
	var grid := BattleGrid.new(); add_child(grid)
	var m := AutoBattleManager.new(); add_child(m); m.set_process(false)
	m.battle_grid = grid
	m.skill_effect_container = Node2D.new(); add_child(m.skill_effect_container)
	var hero := UnitFactory.create_unit(UnitBase.UnitClass.SABLE)
	add_child(hero); hero.grid_position = Vector2i(4,5)
	hero.max_hp = 100000; hero.current_hp = hero.max_hp
	hero.attack_damage = 10000; hero.battle_manager = m
	assert(grid.place_unit(hero,hero.grid_position))
	hero.position = m._world_pos_for(hero,hero.grid_position)
	var boss := EnemyFactory.create_mirrorplate_warden()
	add_child(boss); boss.grid_position = Vector2i(4,2); boss.battle_manager = m
	assert(grid.place_unit(boss,boss.grid_position))
	boss.position = m._world_pos_for(boss,boss.grid_position)
	m.player_units = [hero]; m.enemy_units = [boss]
	MirrorWardenKit.reset(boss)
	var kit := m.mirror_warden_kit
	kit.passive(m,boss,m.player_units,2.1); kit.tick(m,0.1)
	assert(kit.tiles.size()==1)
	var callback: Callable = kit.tiles[0].callback
	var copy: UnitBase = kit.tiles[0].copy
	assert(is_instance_valid(copy) and copy.has_meta("mirror_copy"))
	assert(copy.movement_speed==0 and copy.skill_name=="" and copy.ultimate_name=="")
	assert(copy.attack_damage==MirrorWardenKit.echo_damage(hero,boss))
	var before := hero.current_hp
	hero.attacked.emit(boss); kit.tick(m,0.4)
	assert(hero.current_hp<before and copy.attack_damage<=int(boss.attack_damage*0.75))
	assert(MirrorWardenKit.reflect(boss)==0.15)
	boss.current_shield=100; boss.take_damage(100,0,null,true)
	assert(not MirrorWardenKit.broken(boss))
	boss.current_hp=boss.max_hp/2
	assert(MirrorWardenKit.reflect(boss)==0)
	kit.passive(m,boss,m.player_units,3.0)
	assert(boss.get_meta("warden_broken") and kit.casts.size()>0)
	if "--capture" in OS.get_cmdline_user_args():
		get_window().size=Vector2i(1200,1000)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../captures/warden-warning.png")
	before=hero.current_hp
	kit.tick(m,1.2)
	assert(hero.current_hp<before and kit.tiles.is_empty())
	assert(not hero.attacked.is_connected(callback))
	assert(grid.occupied_cells.values().count(copy)==0)
	boss.set_meta("warden_charge_t",0.0)
	kit.passive(m,boss,m.player_units,0.1)
	assert(boss.get_meta("warden_busy"))
	kit.tick(m,1.0)
	kit.tick(m,0.5)
	assert(not boss.get_meta("warden_busy"))
	assert(grid.occupied_cells.values().count(boss)==4)
	kit.clear(m)
	assert(kit.tiles.is_empty() and kit.casts.is_empty() and kit.echoes.is_empty())
	MirrorWardenKit.reset(boss)
	boss.current_hp=boss.max_hp
	assert(not MirrorWardenKit.broken(boss) and not boss.get_meta("warden_busy"))
	print("MIRROR_WARDEN_CHECK: ALL PASS")
	get_tree().quit()
