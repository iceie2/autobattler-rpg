extends Node2D

var grid: BattleGrid
var m: AutoBattleManager
var heroes: Array = []
var hydra: VisualUnit
var capture := false

func _ready() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	get_window().size = Vector2i(1200, 1000)
	grid = BattleGrid.new(); add_child(grid)
	m = AutoBattleManager.new(); add_child(m); m.set_process(false)
	m.battle_grid = grid
	m.skill_effect_container = Node2D.new(); add_child(m.skill_effect_container)
	for pos in [Vector2i(4,5),Vector2i(5,5),Vector2i(3,5),Vector2i(4,6)]:
		var hero := UnitFactory.create_unit(UnitBase.UnitClass.SABLE)
		hero.max_hp = 100000; hero.current_hp = 100000
		hero.unit_name = "Test hero"
		add_child(hero)
		hero.grid_position = pos; grid.place_unit(hero,pos)
		hero.position = m._world_pos_for(hero,pos)
		hero.battle_manager = m
		heroes.append(hero)
	m.player_units = heroes
	for element in 6:
		if hydra:
			m.hydra_kit.clear(); grid.purge_unit(hydra); hydra.free()
		hydra = EnemyFactory._create_hydra(element)
		add_child(hydra)
		hydra.grid_position = Vector2i(4,2); grid.place_unit(hydra,hydra.grid_position)
		hydra.position = m._world_pos_for(hydra,hydra.grid_position)
		hydra.battle_manager = m; m.enemy_units = [hydra]
		HydraKit.reset(hydra)
		assert(hydra.get_meta("hydra_heads") == 3)
		assert(hydra.model3d.has_animation(HydraKit.CLIPS[element]))
		var total := sum_hp()
		m.hydra_kit.begin(m,hydra,heroes)
		assert(hydra.get_meta("hydra_busy"))
		await photograph("hydra-%d-warning" % element)
		m.hydra_kit.tick(m,HydraKit.WINDUP)
		if element == UnitBase.Element.WATER: m.hydra_kit.tick(m,0.5)
		await photograph("hydra-%d-impact" % element)
		assert(sum_hp() < total, "signature must land damage: %d" % element)
		if element == UnitBase.Element.FIRE:
			total = sum_hp()
			m.hydra_kit.tick(m,0.5)
			assert(sum_hp() < total)
		m.hydra_kit.tick(m,1.0)
		assert(not hydra.get_meta("hydra_busy"))
		m.hydra_kit.clear()
		# Full shield absorption cannot sever a head.
		hydra.current_shield = 100
		hydra.take_damage(100,element,null,true)
		assert(hydra.current_hp == hydra.max_hp and hydra.get_meta("hydra_heads") == 3)
		await photograph("hydra-%d-three-heads" % element)
		hydra.take_damage(hydra.max_hp/3,element,null,true)
		assert(hydra.get_meta("hydra_heads") == 2 and hydra.health_bar.hydra_heads == 2)
		await photograph("hydra-%d-two-heads" % element)
		hydra.heal(99999)
		assert(hydra.get_meta("hydra_heads") == 2 and hydra.current_hp == HydraKit.health_cap(hydra))
		hydra.take_damage(hydra.max_hp/3,element,null,true)
		assert(hydra.get_meta("hydra_heads") == 1)
		await photograph("hydra-%d-one-head" % element)
		assert(HydraKit.description(hydra).contains("1/3 heads"))
		# Reset all state on the same model, restoring every collapsed neck.
		hydra.set_meta("hydra_head_pool_active",false)
		hydra.current_hp = hydra.max_hp
		HydraKit.reset(hydra)
		assert(hydra.get_meta("hydra_heads") == 3 and hydra.health_bar.hydra_heads == 3)
		m.hydra_kit.begin(m, hydra, heroes)
		total = sum_hp()
		hydra.take_damage(99999,element,null,true)
		assert(hydra.current_hp == 0 and hydra.get_meta("hydra_heads") == 0)
		m.hydra_kit.tick(m, 1.0)
		assert(m.hydra_kit.casts.is_empty() and sum_hp() == total)
		assert(grid.occupied_cells.values().count(hydra) == 4) # death cleanup owns purge
		# Restore the layout after pull/push to keep each variant deterministic.
		var positions := [Vector2i(4,5),Vector2i(5,5),Vector2i(3,5),Vector2i(4,6)]
		for i in heroes.size():
			grid.purge_unit(heroes[i]); heroes[i].grid_position = positions[i]
			assert(grid.place_unit(heroes[i],positions[i]))
			heroes[i].position = m._world_pos_for(heroes[i],positions[i])
	# Non-divisible total HP still has stable segment boundaries.
	assert(HydraKit.heads_for_hp(3201,4801) == 2)
	assert(HydraKit.heads_for_hp(1601,4801) == 1)
	var victory := {"count": 0, "won": false}
	m.battle_ended.connect(func(won): victory.count += 1; victory.won = won)
	var objective := EnemyFactory.create_hydra_normal()
	objective.unit_class = UnitBase.UnitClass.HYDRA
	objective.is_boss = true; objective.is_player_unit = false
	objective.max_hp = 300; objective.current_hp = 300
	objective.battle_manager = m; add_child(objective)
	HydraKit.reset(objective)
	var escort := EnemyFactory.create_by_code("M")
	escort.is_player_unit = false; add_child(escort)
	m.enemy_units = [objective, escort]
	m.battle_active = true
	objective.take_damage(99999, UnitBase.Element.NORMAL, null, true)
	m.check_battle_end()
	m.check_battle_end()
	assert(victory.count == 1 and victory.won and not m.battle_active)
	assert(escort.current_hp > 0) # last head wins even with difficulty escorts
	if capture:
		grid.visible = false
		for hero in heroes: hero.visible = false
		hydra.visible = false
		var picker := HydraElementScreen.new()
		add_child(picker); picker.present()
		await photograph("hydra-element-picker")
	print("HYDRA_KIT_CHECK: ALL PASS")
	get_tree().quit()

func sum_hp() -> int:
	var total := 0
	for v in heroes: total += v.current_hp
	return total

func photograph(name: String) -> void:
	if not capture: return
	var was_paused := m.paused
	var was_active := m.battle_active
	m.paused = true; m.battle_active = true
	for fx in m.skill_effect_container.get_children():
		if fx is HydraVFX:
			fx.elapsed = fx.duration * 0.4
			fx.queue_redraw()
	if hydra and hydra.model3d and hydra.get_meta("hydra_busy",false):
		hydra.model3d._anim.seek(0.4 if name.ends_with("warning") else 0.95, true)
	for frame in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://../captures/%s.png" % name)
	m.paused = was_paused; m.battle_active = was_active
