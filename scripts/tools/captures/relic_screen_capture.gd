extends Node
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")
# Fixture-only capture of the relic pick screen; never writes saves.
#   godot --path . res://scenes/tools/relic_screen_capture.tscn
# Three screens: the owner's 2026-09-28 overflow case, the longest descriptions
# (archetype pieces), and three short ones (the card's minimum height).
func _ready() -> void:
	var screen := RelicScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var cases := {
		"relic_screen_owner_case": ["c_std", "d_shield", "d_goldscale"],
		"relic_screen_longest": ["c_kindred", "b_kindling", "a_tinder"],
		"relic_screen_short": ["d_hp", "d_atk", "d_move"],
	}
	for name in cases:
		var offers: Array = []
		for rid in cases[name]:
			offers.append(Relic.by_id(rid))
		screen.present(offers, 1, 1)
		# Let the slot-machine reveal land before capturing.
		await get_tree().create_timer(3.0).timeout
		await _capture(name + ".png")
	get_tree().quit()

func _capture(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := CapturePaths.out(name)
	get_viewport().get_texture().get_image().save_png(path)
	print("RELIC_SCREEN_CAPTURE=" + path)
