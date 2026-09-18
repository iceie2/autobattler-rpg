extends Node

# Visual harness for the level-up screen's ability panel (2026-08-02).
# Captures the screen at rest and again with a perk card hovered, so the
# highlight-what-changed behaviour can be checked without launching a run.
#
#   godot --path . res://scenes/_levelup_capture.tscn -- --hero=STATIC --perk=magic
#
# Writes user://_levelup_rest.png and user://_levelup_hover.png (both gitignored
# build artifacts — delete them after looking, don't commit them).
#
# NOTE: needs a real window, so no --headless here. Any hero name from
# get_class_name_string() works; --perk accepts atk/magic/hp/res (the stats that
# appear in ability formulas) plus the rest, which should visibly do nothing.

func _ready() -> void:
	var hero := "STATIC"
	var perk_id := "magic"
	var synth_value := 8.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hero="): hero = a.split("=")[1].to_upper()
		if a.begins_with("--perk="): perk_id = a.split("=")[1]
		if a.begins_with("--value="): synth_value = float(a.split("=")[1])

	get_window().size = Vector2i(1920, 1080)

	var cls: int = -1
	for c in UnitFactory.get_all_classes():
		var u_probe := UnitFactory.create_unit(c, UnitFactory.element_for_class(c), true)
		var match_name: bool = u_probe.get_class_name_string().to_upper() == hero
		u_probe.free()
		if match_name:
			cls = c
			break
	if cls == -1:
		push_error("unknown hero %s" % hero)
		get_tree().quit()
		return

	var unit := UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
	unit.set_level(8)
	unit.perk_points = 1

	var screen: Node = (load("res://scenes/level_up_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	await get_tree().process_frame
	screen.present([unit])

	for i in range(90):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://_levelup_rest.png"))
	print("CAPTURED rest — hero=%s level=%d MAG=%d ATK=%d"
		% [hero, unit.level, unit.magic_power, unit.attack_damage])

	# Drive the hover path directly rather than faking mouse motion — the capture
	# is about what the panel renders, not about input routing.
	var offer: Dictionary = {}
	for o in screen._cur_offers:
		if str(o.get("id", "")) == perk_id:
			offer = o
			break
	if offer.is_empty():
		# Perk offers are a random roll, so the one we want to inspect often isn't
		# on the table. Synthesise it — the hover path only reads id/value/color,
		# and this harness is checking the panel's response, not the roll.
		offer = {"id": perk_id, "value": synth_value, "rolled_value": synth_value,
				 "color": Color(0.68, 0.35, 0.95)}
		print("perk '%s' not offered this roll — synthesising +%s for the hover shot"
			% [perk_id, synth_value])

	screen._on_perk_hover(offer)
	for i in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://_levelup_hover.png"))
	print("CAPTURED hover — perk=%s value=%s"
		% [perk_id, offer.get("rolled_value", offer.get("value", 0))])
	get_tree().quit()
