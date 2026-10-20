extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

var mgr: AutoBattleManager
var grid: BattleGrid
var board: Node2D
var boss: VisualUnit
var team: Array = []

func _ready() -> void:
	get_window().size = Vector2i(1180, 1120)
	get_window().content_scale_size = Vector2i(1180, 1120)
	board = Node2D.new(); board.position = Vector2(90, 75); add_child(board)
	var background := BackgroundLayer.new(); board.add_child(background)
	background.set_biome_from_round(1); background.set_enemy_zone_visible(false)
	grid = BattleGrid.new(); board.add_child(grid); grid.visible = false
	mgr = AutoBattleManager.new(); add_child(mgr); mgr.set_process(false)
	mgr.battle_grid = grid; mgr.time_scale = 1.0; mgr.battle_active = true
	var effects := Node2D.new(); add_child(effects); mgr.skill_effect_container = effects
	boss = EnemyFactory.create_triarch(); boss.battle_manager = mgr; board.add_child(boss)
	put(boss, Vector2i(4, 3)); mgr.enemy_units = [boss]
	for entry in [[UnitBase.UnitClass.RIOT, Vector2i(4, 4)], [UnitBase.UnitClass.SHAUNA, Vector2i(3, 4)], [UnitBase.UnitClass.DOC, Vector2i(5, 4)], [UnitBase.UnitClass.SABLE, Vector2i(4, 6)]]:
		var h := UnitFactory.create_unit(entry[0], UnitFactory.element_for_class(entry[0]), true)
		h.max_hp = 100000; h.current_hp = 100000
		h.battle_manager = mgr; board.add_child(h); put(h, entry[1]); team.append(h)
	mgr.player_units = team
	mgr.unit_summoned.connect(func(u): board.add_child(u))
	await get_tree().create_timer(0.8).timeout
	boss.target_unit = team[0]
	mgr._use_skill(boss, team); boss.play_generic_skill_action()
	await advance(0.34); await shot("knight_cleave_warning")
	await advance(0.03); await shot("knight_cleave_contact")
	mgr.triarch_kit.challenge(boss); await shot("knight_challenge")
	await change(1)
	boss.target_unit = team[0]
	mgr._use_skill(boss, team); boss.play_generic_skill_action()
	await advance(0.45); await shot("hunter_volley_telegraph")
	await advance(0.17); await shot("hunter_volley_impact")
	# Stage the real adjacency condition, then use the normal secondary dispatch.
	grid.purge_unit(boss); put(boss, Vector2i(4, 3))
	boss.action_time = 0.0
	assert(mgr.triarch_kit.secondary(boss, 0.01))
	await advance(0.3); await shot("hunter_disengage")
	await advance(0.31)
	await change(2)
	mgr._use_skill(boss, team); boss.play_generic_skill_action()
	await advance(1.1); await shot("core_meteor_telegraph")
	await advance(0.42); await shot("core_meteor_impact")
	boss.current_hp = boss.max_hp / 2
	mgr.triarch_kit.secondary(boss, 0.01)
	await advance(0.25); await shot("core_echoes")
	print("TRIARCH_CAPTURE: COMPLETE")
	mgr.triarch_kit.clear()
	get_tree().quit()

func put(u: UnitBase, cell: Vector2i) -> void:
	assert(grid.place_unit(u, cell)); u.grid_position = cell; u.position = grid.grid_to_world(cell)

func change(phase: int) -> void:
	boss.current_hp = 0; boss.die()
	await advance(0.4); await shot("change_%d_fall" % phase)
	await advance(0.7); await shot("change_%d_midair" % phase)
	await advance(0.65); await shot("change_%d_marker" % phase)
	await advance(0.44); await shot("change_%d_landing_card" % phase)

func advance(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		var dt := minf(get_process_delta_time(), seconds - elapsed)
		mgr.triarch_kit.tick(dt)
		boss.action_time = maxf(0.0, boss.action_time - dt)
		if boss.channel: mgr._tick_channel(boss, dt)
		elapsed += dt

func shot(label: String) -> void:
	# Freeze the real battle clock so VFX cannot drift while saving a snapshot.
	mgr.paused = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := CapturePaths.out("triarch_%s.png" % label)
	get_viewport().get_texture().get_image().save_png(path)
	print("TRIARCH_CAPTURE: ", path)
	mgr.paused = false
