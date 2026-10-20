extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Drop-in check for NEW enemy art: renders one enemy type at real board scale on
# its biome, beside a Goblin for size reference, so a fresh sprite is judged in
# context rather than on a flat background. Runs WINDOWED.
# Run: godot --path . res://scenes/tools/enemy_art_capture.tscn -- --unit=tidepool_horror --round=25

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	var code := "goblin"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--unit="):
			code = a.split("=")[1]
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(1))
	var grid := BattleGrid.new()
	add_child(grid)
	var ref = EnemyFactory.create_by_type("goblin")
	var u = EnemyFactory.create_by_type(code)
	add_child(ref); add_child(u)
	ref.position = Vector2(330, 330)
	u.position = Vector2(560, 300)
	for i in range(4): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out("_art_%s.png" % code)) == OK, "capture failed")
	print("ENEMY_ART_CAPTURE: ALL PASS (%s, art=%s)" % [code, str(u.get_meta("sprite_folder", ""))])
	get_tree().quit(0)
