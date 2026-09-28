extends Node
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")
# Fixture-only UI capture; never writes progression or run saves.
func _ready() -> void:
	get_window().size = Vector2i(1440, 900)
	var state := RelicMilestoneState.new()
	state.pending = {"opening_1": true, "execute_2": true, "ladder_max_hp": true}
	state.unlocked = {"row_1": true}
	var screen := RelicMilestoneScreen.new()
	add_child(screen)
	screen.show_collection(state)
	var style := "light" if UITheme.is_light() else "dark"
	await _capture("vd20_relic_milestones_" + style + ".png")
	screen._collection_tab.pressed.emit()
	await _capture("vd20_relic_collection_" + style + ".png")
	state.pending.clear()
	screen.show_collection(state)
	await _capture("vd20_relic_collection_empty_" + style + ".png")
	get_tree().quit()

func _capture(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := CapturePaths.out(name)
	get_viewport().get_texture().get_image().save_png(path)
	print("VD20_CAPTURE=" + path)
