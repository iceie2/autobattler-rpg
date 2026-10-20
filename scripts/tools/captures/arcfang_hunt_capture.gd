extends Node2D

var manager: AutoBattleManager
var hunt: ArcfangHunt
var boss: VisualUnit
var heroes: Array = []

func _ready() -> void:
	get_window().size = Vector2i(1180, 1000)
	get_window().content_scale_size = Vector2i(1180, 1000)
	var bg := BackgroundLayer.new(); add_child(bg); bg.set_biome_from_round(60)
	var board := Node2D.new(); board.position = Vector2(140, 40); add_child(board)
	var grid := BattleGrid.new(); board.add_child(grid)
	manager = AutoBattleManager.new(); add_child(manager); manager.battle_grid = grid
	var fx := Node2D.new(); add_child(fx); manager.skill_effect_container = fx
	boss = EnemyFactory.create_arcfang(); boss.battle_manager = manager; board.add_child(boss)
	put(grid, boss, Vector2i(3, 2))
	for entry in [[UnitBase.UnitClass.RIOT, Vector2i(3, 4)], [UnitBase.UnitClass.SHAUNA, Vector2i(5, 6)], [UnitBase.UnitClass.DOC, Vector2i(4, 6)]]:
		var h := UnitFactory.create_unit(entry[0], UnitFactory.element_for_class(entry[0]), true)
		h.battle_manager = manager; board.add_child(h); put(grid, h, entry[1]); heroes.append(h)
	manager.enemy_units = [boss]; manager.player_units = heroes
	hunt = manager._arcfang_controller(boss, heroes)
	heroes[1].damage_dealt = 500
	await get_tree().create_timer(1.0).timeout
	hunt.tick(10, heroes); hunt.tick(1.1, heroes)
	await shot("arcfang_warning")
	hunt.tick(0.4, heroes)
	await shot("arcfang_thunder_run")
	boss.target_unit = heroes[1]; hunt.bite(heroes[1])
	boss.skill_cd_time = 3.0
	await shot("arcfang_thunderjaw")
	hunt.tick(0.61, heroes)
	boss.skill_cd_time -= 0.61
	await shot("arcfang_lightning_snap")
	hunt.tick(4, heroes)
	boss.skill_cd_time = 0.0
	await shot("arcfang_spent_storm")
	hunt.tick(2, heroes); boss.current_hp = int(boss.max_hp * 0.39)
	hunt.tick(2.5, heroes); hunt.tick(1.5, heroes); hunt.tick(4, heroes); hunt.tick(0.8, heroes)
	await shot("arcfang_last_howl")
	print("ARCFANG_CAPTURE: COMPLETE")
	get_tree().quit()

func put(grid: BattleGrid, u: UnitBase, cell: Vector2i) -> void:
	grid.place_unit(u, cell); u.grid_position = cell; u.position = manager._world_pos_for(u, cell)

func shot(label: String) -> void:
	await get_tree().create_timer(0.2).timeout
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://../captures/renders/lightning/%s.png" % label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../captures/renders/lightning"))
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
