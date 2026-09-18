extends Node2D

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Riot on the REAL board at native gameplay scale, beside a hero already using
# the 3D path. The pipeline doc is explicit that this is the check that matters:
# "a silhouette that reads at 720 px can be an unrecognisable lump at 138 px".
#
# Runs WINDOWED. Run: godot --path . res://scenes/tools/riot_board_check.tscn
var OUT: String = CapturePaths.out("riot_board.png")

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
	await get_tree().process_frame

	var roster := [
		[UnitBase.UnitClass.RIOT, Vector2i(3, 5)],
		[UnitBase.UnitClass.RIFT, Vector2i(5, 5)],
		[UnitBase.UnitClass.JUNE, Vector2i(2, 6)],
	]
	var made: Array = []
	for entry in roster:
		var u: VisualUnit = UnitFactory.create_unit(entry[0], UnitFactory.NATURAL_ASPECT[entry[0]], true)
		add_child(u)
		u.battle_manager = mgr
		u.grid_position = entry[1]
		grid.place_unit(u, entry[1])
		u.position = grid.to_global(grid.grid_to_world(entry[1]))
		made.append(u)
	mgr.player_units = made
	mgr.enemy_units = []
	await get_tree().create_timer(0.8).timeout

	var riot: VisualUnit = made[0]
	print("RIOT_BOARD: element=%s  model3d=%s  clips=%s"
		% [UnitBase.Element.keys()[riot.current_element],
		   riot.model3d != null,
		   riot.model3d.has_animation("attack") if riot.model3d else "n/a"])
	assert(riot.current_element == UnitBase.Element.LIGHTNING,
		"RIOT_BOARD: element is %s, expected LIGHTNING" % riot.current_element)
	assert(riot.model3d != null, "RIOT_BOARD: Riot fell back to 2D art — model path not wired")
	for clip in ["idle", "walk", "attack", "hurt", "death"]:
		assert(riot.model3d.has_animation(clip), "RIOT_BOARD: missing required clip '%s'" % clip)

	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT))
	assert(err == OK, "RIOT_BOARD: capture failed")
	print("RIOT_BOARD: ALL PASS -> ", OUT)
	get_tree().quit(0)
