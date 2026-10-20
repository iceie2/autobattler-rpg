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
		"relic_screen_reroll_regression": ["b_critres", "b_overflow", "a_vamp"],
	}
	for name in cases:
		var offers: Array = []
		for rid in cases[name]:
			offers.append(Relic.by_id(rid))
		screen.present(offers, 1, 1)
		# Let the slot-machine reveal land before capturing.
		await get_tree().create_timer(3.0).timeout
		for card in screen._card_row.get_children():
			assert(is_equal_approx(card.size.y, screen._card_h), "Relic card retained an old height")
			assert(card.position.y + card.size.y + screen._card_row.position.y <= screen._reroll_btn.position.y, "Relic card overlaps reroll")
		assert(screen._reroll_btn.position.y + screen._reroll_btn.size.y <= screen._panel.size.y, "Relic reroll exceeds panel")
		await _capture(name + ".png")
	get_tree().quit()

func _capture(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := CapturePaths.out(name)
	get_viewport().get_texture().get_image().save_png(path)
	print("RELIC_SCREEN_CAPTURE=" + path)
