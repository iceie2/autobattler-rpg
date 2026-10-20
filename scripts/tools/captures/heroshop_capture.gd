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

	# --fitcheck: measure every hero's three ability rows against the room the
	# card leaves for them (2026-09-27 audit: Bouncer's kit overflowed). Prints
	# one line per hero and FIT/OVERFLOW; no screenshot.
	# --heroes=BOUNCER,DOC,NEMI: force these classes onto the cards.
	var args := OS.get_cmdline_user_args()
	if "--fitcheck" in args:
		var kit_room: float = shop.CARD_H - 313.0 - 10.0 - 46.0 - 50.0
		var worst := 0.0
		for c in UnitFactory.get_all_classes():
			if not VisualUnit.HERO_SPRITE_PATHS.has(c):
				continue
			var dummy := Button.new()
			shop.add_child(dummy)
			var u := UnitFactory.create_unit(c, UnitFactory.element_for_class(c), true)
			var used: float = shop._add_ability_rows(dummy, u, c, 0.0)
			print("FIT %-12s kit %.0f / room %.0f  %s" % [u.get_class_name_string(), used,
				kit_room, "OK" if used <= kit_room else "OVERFLOW"])
			worst = maxf(worst, used)
			u.free()
			dummy.queue_free()
		print("FITCHECK worst %.0f room %.0f" % [worst, kit_room])
		get_tree().quit()
		return
	for a in args:
		if a.begins_with("--heroes="):
			var names: PackedStringArray = a.split("=")[1].to_upper().split(",")
			for i in range(mini(names.size(), shop._offers.size())):
				for c in UnitFactory.get_all_classes():
					if shop._class_name(c).to_upper() == names[i]:
						shop._offers[i]["class"] = c
						shop._offers[i]["element"] = UnitFactory.element_for_class(c)
			shop._rebuild_all_cards(999)

	# Cards reveal on a left-to-right slot-machine cascade; wait it out so the
	# capture shows landed values rather than mid-spin garbage.
	for i in range(260):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://_heroshop_check.png"))
	print("CAPTURED hero shop")
	get_tree().quit()
