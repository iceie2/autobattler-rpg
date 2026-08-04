extends Node

# Visual harness for the equipment panel (2026-08-04 rework: item icons, the
# three-slot combine tray, and the passive-pick overlay).
# Boots the real game scene so the panel renders with its true theme.
#
#   godot --path . res://scenes/_equipment_capture.tscn
#
# Writes res://_equipment_check.png and res://_equipment_pick.png
# (build artifacts — don't commit them). Needs a real window, so no --headless.

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var mg: Node = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	for i in range(30):
		await get_tree().process_frame

	if mg._relic_screen:
		mg._relic_screen.visible = false

	var panel = mg._equipment_panel
	var inv = mg._equipment_inventory
	if panel == null or inv == null:
		push_error("no _equipment_panel / _equipment_inventory on main_game")
		get_tree().quit(); return

	# Stock the bag: a spread of commons (so the icon rows are visible) plus
	# three same-rarity greens to drive the combine tray. Greens are built by
	# fusing commons — dropped items are never green — so this mirrors how a real
	# bag reaches that state.
	for i in range(6):
		inv.add_item(EquipmentManager.generate_item(12, EquipmentItem.Rarity.COMMON))
	# Each green is forced to a DISTINCT passive. Left to chance, three draws from
	# the 6-type pool collide ~44% of the time, which drops the candidate count to
	# the Rare cap and correctly skips the pick prompt — fine in game, useless for
	# a capture that exists to photograph that prompt.
	var forced := ["Lifesteal", "Thorns", "Spell Echo"]
	var greens: Array[EquipmentItem] = []
	for g in range(3):
		var trio: Array[EquipmentItem] = []
		for k in range(3):
			trio.append(EquipmentManager.generate_item(12, EquipmentItem.Rarity.COMMON))
		var green := EquipmentManager.combine_items(trio)
		green.passives.clear()
		green.add_passive(forced[g], 0.08 + 0.02 * g)
		greens.append(green)
		inv.add_item(green)

	panel.open(inv, mg.player_units)
	# Turn on combine mode and load the tray so the new slots actually render.
	panel._toggle_combine_mode()
	for g in greens:
		panel._toggle_combine_selection(g)
	for i in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://_equipment_check.png"))
	print("CAPTURED equipment panel (combine tray loaded)")

	# Second shot: the passive-pick overlay. Three greens carry up to 3 distinct
	# passives while a Rare caps at 2, so this is the real over-cap path.
	panel._fuse_selected()
	for i in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://_equipment_pick.png"))
	print("CAPTURED passive pick (visible=%s)" % str(panel._pick_panel.visible))
	get_tree().quit()
