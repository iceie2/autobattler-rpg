extends Node2D

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# June's kit on a REAL BattleGrid, which is the only place her ground effects can
# be judged. The anim_preview harness parents its effect layer under a 2.5x
# scaled stage while its grid sits outside that stage, so anything converted
# through grid.to_global() — the Bloom field's cell quads — lands in the wrong
# place there. Same reason Rift's Collapse needed a real-grid test.
#
# Runs WINDOWED (--headless renders empty PNGs).
# Run: godot --path . res://scenes/tools/june_board_check.tscn
var OUT: String = CapturePaths.out("june_board.png")

func _ready() -> void:
	get_window().size = Vector2i(1500, 950)
	RenderingServer.set_default_clear_color(Color(0.12, 0.13, 0.10))

	# The REAL board art. Without it this scene renders June's ground effects
	# against an empty clear colour, which is exactly how a z-order bug that hid
	# them under the grass passed review (user report 2026-09-17). If it does not
	# read ON GRASS, it does not read.
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

	var june: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.JUNE,
		UnitBase.Element.EARTH, true)
	add_child(june)
	june.grid_position = Vector2i(3, 6)
	grid.place_unit(june, june.grid_position)
	june.position = grid.to_global(grid.grid_to_world(june.grid_position))

	# Two allies inside the aura radius, hurt so the regen pulse actually fires.
	var allies: Array = [june]
	for cell: Vector2i in [Vector2i(2, 5), Vector2i(4, 7)]:
		var a: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.RIOT,
			UnitBase.Element.NORMAL, true)
		add_child(a)
		a.grid_position = cell
		grid.place_unit(a, cell)
		a.position = grid.to_global(grid.grid_to_world(cell))
		a.current_hp = maxi(1, a.max_hp / 3)
		allies.append(a)

	# An enemy cluster for Bloom to centre on.
	var foes: Array = []
	for cell: Vector2i in [Vector2i(5, 2), Vector2i(6, 2), Vector2i(6, 3), Vector2i(4, 3)]:
		var e: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.RIOT,
			UnitBase.Element.NORMAL, false)
		add_child(e)
		e.grid_position = cell
		grid.place_unit(e, cell)
		e.position = grid.to_global(grid.grid_to_world(cell))
		foes.append(e)
	mgr.player_units = allies
	mgr.enemy_units = foes
	await get_tree().process_frame

	# Passive aura + a regen tick, the Root cuffs on one enemy, and the Bloom
	# band all live at once — the crowded case.
	june.set_meta("aura_tick_t", 0.0)
	mgr._tick_passive(june, foes, allies, 0.02)
	mgr._june_root(june, [foes[3]])
	mgr._june_bloom(june, foes)
	await get_tree().create_timer(0.6).timeout

	var cells: int = int(mgr.bloom_fields[0]["cells"].size()) if not mgr.bloom_fields.is_empty() else 0
	print("JUNE_BOARD: bloom fields=%d cells=%d  rooted=%d  aura=%d  cuffs=%d"
		% [mgr.bloom_fields.size(), cells,
		   foes.filter(func(f): return f.root_time > 0.0).size(),
		   mgr._june_auras.size(), mgr._june_root_cuffs.size()])
	assert(not mgr.bloom_fields.is_empty(), "JUNE_BOARD: Bloom spawned no field")
	assert(cells == AutoBattleManager.BLOOM_COLS * AutoBattleManager.BLOOM_ROWS,
		"JUNE_BOARD: field covers %d cells, expected %d" %
		[cells, AutoBattleManager.BLOOM_COLS * AutoBattleManager.BLOOM_ROWS])
	assert(mgr._june_auras.size() == 1, "JUNE_BOARD: aura lattice missing")
	# The aura is an OUTLINE of the healed cells, so both the cell membership and
	# the segment list matter — either being empty is an invisible aura that
	# still passes a "the node exists" check.
	var aura = mgr._june_auras.values()[0]
	var expected := 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var c: Vector2i = june.grid_position + Vector2i(dx, dy)
			if grid.is_valid_position(c) and june.grid_position.distance_to(c) <= 3.0:
				expected += 1
	print("JUNE_BOARD: aura cells=%d expected=%d outline_segments=%d"
		% [aura.aura_cell_count, expected, aura._aura_edges.size()])
	assert(aura.aura_cell_count == expected,
		"JUNE_BOARD: aura covers %d cells, heal reaches %d" % [aura.aura_cell_count, expected])
	assert(aura._aura_edges.size() > 0, "JUNE_BOARD: aura outline has no segments")
	assert(mgr._june_root_cuffs.size() > 0, "JUNE_BOARD: root cuffs missing")

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(ProjectSettings.globalize_path(OUT))
	assert(err == OK, "JUNE_BOARD: capture failed")
	print("JUNE_BOARD: ALL PASS -> ", OUT)
	get_tree().quit(0)
