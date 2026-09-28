extends Node
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")
# UI review harness; fixture state only, never writes progression or run saves.
func _ready() -> void:
	get_window().size = Vector2i(1440, 900)
	var state := RelicMilestoneState.new()
	state.pending = {"opening_1": true, "firststrike_2": true, "ladder_max_hp": true}
	state.unlocked = {"row_1": true}
	var screen := RelicMilestoneScreen.new()
	add_child(screen)
	screen.show_collection(state)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := CapturePaths.out("vd20_relic_milestones.png")
	get_viewport().get_texture().get_image().save_png(path)
	print("VD20_CAPTURE=" + path)
	get_tree().quit()
