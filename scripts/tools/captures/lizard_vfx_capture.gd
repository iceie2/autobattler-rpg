extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   normal,air,water,earth,fire,lightning
# Override with: -- --round=N
const DEBUT_ROUND := 2

# Lizard VFX captures on a REAL BattleGrid — the row telegraph is built from the
# board's actual cell quads, so it can only be judged against the real board.
# Runs WINDOWED. Run: godot --path . res://scenes/tools/lizard_vfx_capture.tscn

func _ready() -> void:
	get_window().size = Vector2i(1500, 900)
	# Render over the REAL board: the arena is sunlit GRASS, and an effect
	# only verified against a dark clear colour has not been verified.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	var grid := BattleGrid.new()
	var mgr := AutoBattleManager.new()
	var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null)
	mgr.skill_effect_container = fx
	await get_tree().process_frame

	var liz := EnemyFactory.create_lizard_normal()
	add_child(liz); liz.battle_manager = mgr; liz.is_player_unit = false
	grid.place_unit(liz, Vector2i(4, 1)); liz.grid_position = Vector2i(4, 1)
	liz.position = grid.to_global(grid.grid_to_world(Vector2i(4, 1)))
	# Four heroes abreast in row 5 — exactly what the shot punishes.
	var row: Array = []
	for x in [1, 3, 5, 7]:
		var h := EnemyFactory.create_goblin()
		add_child(h); h.battle_manager = mgr; h.is_player_unit = true
		grid.place_unit(h, Vector2i(x, 5)); h.grid_position = Vector2i(x, 5)
		h.position = grid.to_global(grid.grid_to_world(Vector2i(x, 5)))
		row.append(h)
	# One hero OUTSIDE the row, to show the footprint is honest.
	var safe := EnemyFactory.create_goblin()
	add_child(safe); safe.battle_manager = mgr; safe.is_player_unit = true
	grid.place_unit(safe, Vector2i(4, 7)); safe.grid_position = Vector2i(4, 7)
	safe.position = grid.to_global(grid.grid_to_world(Vector2i(4, 7)))
	mgr.enemy_units = [liz]; mgr.player_units = row + [safe]
	await get_tree().process_frame

	await _shot("_lizard_aim_row_warning.png", func():
		var aim := LizardVFX.new(); fx.add_child(aim)
		aim.setup_aim(liz, 1.0); aim.global_position = liz.global_position
		aim.host = null; aim.elapsed = 0.75; aim.set_process(false); aim.queue_redraw()
		var warn := LizardVFX.new(); fx.add_child(warn)
		warn.setup_row(LizardVFX.Mode.ROW_WARNING, mgr._row_origin(5), mgr._row_polygon(5), 1.0)
		warn.elapsed = 0.75; warn.set_process(false); warn.queue_redraw())

	await _shot("_lizard_row_impact.png", func():
		var imp := LizardVFX.new(); fx.add_child(imp)
		imp.setup_row(LizardVFX.Mode.ROW_IMPACT, mgr._row_origin(5), mgr._row_polygon(5), 1.0)
		imp.elapsed = 0.22; imp.set_process(false); imp.queue_redraw())

	await _shot("_lizard_cold_blood.png", func():
		var cb := LizardVFX.new(); fx.add_child(cb)
		cb.setup_cold_blood(liz); cb.global_position = liz.global_position
		cb.host = null; cb._spin = 1.2; cb.set_process(false); cb.queue_redraw())

	print("LIZARD_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _shot(name: String, build: Callable) -> void:
	var fx := get_child(2)
	for c in fx.get_children(): c.free()
	build.call()
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(name))
	assert(err == OK, "capture failed: " + name)
