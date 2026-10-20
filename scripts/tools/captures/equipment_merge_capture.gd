extends Node

# Visual harness for the equipment merge toast (2026-09-29). Needs a real
# window (no --headless) and a scratch profile:
#   APPDATA=<scratch>/merge_profile godot --path . res://scenes/_equipment_merge_capture.tscn
# Writes user://_equip_toast_{start,slide,flash,stats,final}.png

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://%s.png" % name))
	print("CAPTURED ", name)

func _ready() -> void:
	if not OS.get_user_data_dir().contains("merge_profile"):
		print("refusing to run outside a merge_profile APPDATA sandbox")
		get_tree().quit(2); return
	seed(9317)
	get_window().size = Vector2i(1920, 1080)
	var mg: Node = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	for i in range(30):
		await get_tree().process_frame
	for modal in [mg._relic_screen, mg._hero_shop, mg._run_map_screen]:
		if modal:
			modal.visible = false
	var inv: ComponentEquipmentInventory = mg._equipment_inventory
	inv.items.clear()
	inv.auto_combine = false
	var pair: Array = []
	for i in range(300):
		var a := ComponentEquipmentRules.generate_item(12, 1)
		var b := ComponentEquipmentRules.generate_item(12, 1)
		if ComponentEquipmentRules.can_combine(a, b):
			pair = [a, b]
			break
	inv.items.append(pair[0])
	inv.items.append(pair[1])
	var sources: Array[EquipmentItem] = [pair[0], pair[1]]
	inv.combine_components(sources, ComponentEquipmentRules.random_removals(pair[0], pair[1]))
	await get_tree().create_timer(0.55).timeout
	await _shot("_equip_toast_start")
	await get_tree().create_timer(0.55).timeout
	await _shot("_equip_toast_slide")
	await get_tree().create_timer(0.30).timeout
	await _shot("_equip_toast_flash")
	await get_tree().create_timer(1.10).timeout
	await _shot("_equip_toast_stats")
	await get_tree().create_timer(3.4).timeout
	await _shot("_equip_toast_passives")   # after the count-up: passives popped in
	await get_tree().create_timer(1.0).timeout
	await _shot("_equip_toast_final")
	get_tree().quit()
