extends Node

# Visual harness for the hero buy screen's card layout (2026-08-02).
# Boots the real game scene and opens the hero shop, so the cards render with
# their true reveal animation and theme.
#
#   godot --path . res://scenes/_heroshop_capture.tscn
#
# Writes user://_heroshop_check.png (a build artifact — don't commit it).
# Needs a real window, so no --headless.

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var mg: Node = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	for i in range(30):
		await get_tree().process_frame

	if mg._relic_screen:
		mg._relic_screen.visible = false

	var shop = mg._hero_shop
	if shop == null:
		push_error("no _hero_shop on main_game")
		get_tree().quit()
		return
	shop.open(999)

	# Cards reveal on a left-to-right slot-machine cascade; wait it out so the
	# capture shows landed values rather than mid-spin garbage.
	for i in range(260):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://_heroshop_check.png"))
	print("CAPTURED hero shop")
	get_tree().quit()
