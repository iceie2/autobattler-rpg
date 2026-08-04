extends Node

# Visual harness for the unit details panel's SKILL section (2026-08-02).
# Boots the real game scene, recruits a hero, opens its details panel and
# screenshots it — the panel is wired into main_game's UI, so there is no
# cheaper way to render it faithfully.
#
#   godot --path . res://scenes/_details_capture.tscn -- --hero=STATIC
#
# Writes res://_details_check.png (a build artifact — don't commit it).
# Needs a real window, so no --headless.

func _ready() -> void:
	var hero := "STATIC"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hero="): hero = a.split("=")[1].to_upper()

	get_window().size = Vector2i(1920, 1080)
	var mg: Node = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	for i in range(30):
		await get_tree().process_frame

	var cls: int = -1
	for c in UnitFactory.get_all_classes():
		var probe := UnitFactory.create_unit(c, UnitFactory.element_for_class(c), true)
		var hit: bool = probe.get_class_name_string().to_upper() == hero
		probe.free()
		if hit:
			cls = c
			break
	if cls == -1:
		push_error("unknown hero %s" % hero)
		get_tree().quit()
		return

	mg.max_player_units = maxi(mg.max_player_units, 2)
	mg._recruit_hero(cls, UnitFactory.element_for_class(cls), {})
	for i in range(10):
		await get_tree().process_frame

	var heroes: Array = mg.player_units.filter(func(u): return u and is_instance_valid(u))
	if heroes.is_empty():
		push_error("recruit failed")
		get_tree().quit()
		return
	var u: UnitBase = heroes[0]
	u.set_level(8)

	# Open the details panel through whatever entry point main_game exposes.
	if mg.has_method("_show_unit_details"):
		mg._show_unit_details(u)
	elif mg.has_method("show_unit_details"):
		mg.show_unit_details(u)
	else:
		push_error("no details-panel entry point found on main_game")
		get_tree().quit()
		return

	# The wave-1 relic pick opens on top of everything and would cover the panel.
	if mg._relic_screen:
		mg._relic_screen.visible = false
	# Park the panel somewhere fully on-screen — it defaults to a position that
	# runs off the left edge in this harness's window.
	mg.unit_details_panel.position = Vector2(520, 90)

	for i in range(20):
		await get_tree().process_frame

	# The SKILL block sits below the fold — scroll to it, that's the whole point
	# of this capture.
	var sc := mg.unit_details_panel.get_node_or_null("Margin/ScrollContainer") as ScrollContainer
	if sc:
		var root := sc.get_node("Root") as Control
		var skill_row := root.get_node_or_null("SkillRow") as Control
		if skill_row:
			sc.scroll_vertical = int(skill_row.position.y) - 40
	for i in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://_details_check.png"))
	print("CAPTURED details — hero=%s level=%d MAG=%d ATK=%d"
		% [hero, u.level, u.magic_power, u.attack_damage])
	get_tree().quit()
