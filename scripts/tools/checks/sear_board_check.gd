extends Node2D

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Sear's kit on a REAL BattleGrid over the REAL BackgroundLayer. The board is
# grass and his effects are ground-level, so anything judged against an empty
# clear colour proves nothing — that is exactly how a z-order fault and a
# green-on-green contrast fault both passed review on June.
#
# Runs WINDOWED (--headless renders empty PNGs).
# Run: godot --path . res://scenes/tools/sear_board_check.tscn
var OUT: String = CapturePaths.out("sear_board.png")

func _ready() -> void:
	get_window().size = Vector2i(1500, 950)
	RenderingServer.set_default_clear_color(Color(0.12, 0.13, 0.10))

	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(1)
	var grid := BattleGrid.new()
	add_child(grid)
	var mgr := AutoBattleManager.new()
	add_child(mgr)
	mgr.battle_grid = grid
	var fx := Node2D.new()
	add_child(fx)
	mgr.skill_effect_container = fx
	mgr.projectile_container = Node2D.new()
	add_child(mgr.projectile_container)
	await get_tree().process_frame

	var sear: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.SEAR,
		UnitBase.Element.FIRE, true)
	add_child(sear)
	sear.battle_manager = mgr
	sear.grid_position = Vector2i(3, 6)
	grid.place_unit(sear, sear.grid_position)
	sear.position = grid.to_global(grid.grid_to_world(sear.grid_position))

	var foes: Array = []
	for cell: Vector2i in [Vector2i(5, 2), Vector2i(6, 3), Vector2i(4, 3)]:
		var e: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.RIOT,
			UnitBase.Element.NORMAL, false)
		add_child(e)
		e.battle_manager = mgr
		e.grid_position = cell
		grid.place_unit(e, cell)
		e.position = grid.to_global(grid.grid_to_world(cell))
		foes.append(e)
	mgr.player_units = [sear]
	mgr.enemy_units = foes
	await get_tree().process_frame

	# Scorched Path: walk him across four tiles so the trail has real length, and
	# stagger the ages so the cooling is visible in one frame.
	var trail_cells := [Vector2i(3, 6), Vector2i(3, 5), Vector2i(4, 5), Vector2i(4, 4)]
	for i in trail_cells.size():
		sear.grid_position = trail_cells[i]
		mgr._on_unit_finished_step(sear)
		await get_tree().create_timer(0.55).timeout
	sear.position = grid.to_global(grid.grid_to_world(sear.grid_position))

	# Ignite on one enemy, then Conflagration to spread and detonate.
	mgr._sear_ignite(sear, [foes[2]])
	await get_tree().create_timer(0.25).timeout
	mgr._sear_conflagration(sear, foes)
	await get_tree().create_timer(0.30).timeout

	var burning: int = foes.filter(func(f): return f.burn_time > 0.0).size()
	print("SEAR_BOARD: trail_tiles=%d scorch_vfx=%d burning=%d burn_marks=%d"
		% [mgr.fire_trail.size(), mgr._sear_scorch_vfx.size(), burning,
		   mgr._sear_burn_marks.size()])
	assert(mgr.fire_trail.size() == trail_cells.size(),
		"SEAR_BOARD: %d trail tiles, expected %d" % [mgr.fire_trail.size(), trail_cells.size()])
	# The trail previously had no visual at all — assert one node per burning tile.
	assert(mgr._sear_scorch_vfx.size() == mgr.fire_trail.size(),
		"SEAR_BOARD: %d scorch visuals for %d burning tiles"
		% [mgr._sear_scorch_vfx.size(), mgr.fire_trail.size()])
	assert(burning == foes.size(), "SEAR_BOARD: Conflagration burned %d of %d" % [burning, foes.size()])
	assert(mgr._sear_burn_marks.size() == burning,
		"SEAR_BOARD: %d flame tells for %d burning units" % [mgr._sear_burn_marks.size(), burning])

	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT))
	assert(err == OK, "SEAR_BOARD: capture failed")
	print("SEAR_BOARD: ALL PASS -> ", OUT)
	get_tree().quit(0)
