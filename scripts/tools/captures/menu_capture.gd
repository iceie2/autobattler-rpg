extends Node
# Throwaway harness. Two modes controlled by SPRITE_CHECK below:
#  false → capture the main menu   (user://_menu_capture.png)
#  true  → spawn goblins + hill giant, capture their sprites (user://_sprite_check.png)
# Run with:  godot --path . res://scenes/_menu_capture.tscn
# Delete this + _menu_capture.tscn when done.

const SPRITE_CHECK := true

func _ready() -> void:
	if SPRITE_CHECK:
		await _sprite_check()
	else:
		await _menu_shot()

func _menu_shot() -> void:
	get_window().size = Vector2i(1920, 1080)
	var menu: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	for i in range(50):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("user://_menu_capture.png"))
	print("CAPTURED menu")
	get_tree().quit()

func _sprite_check() -> void:
	get_window().size = Vector2i(720, 320)
	var types := ["goblin", "goblin_archer", "hill_giant"]
	var x := 130
	for t in types:
		var u: VisualUnit = EnemyFactory.create_by_type(t)
		if u:
			u.position = Vector2(x, 200)
			add_child(u)
			print(t, " -> sprite_folder=", u.get_meta("sprite_folder") if u.has_meta("sprite_folder") else "<none>")
			x += 220
	for i in range(60):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("user://_sprite_check.png"))
	print("SPRITECHECK saved")
	get_tree().quit()
