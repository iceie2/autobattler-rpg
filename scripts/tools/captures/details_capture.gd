extends Node

# Visual harness for the unit details panel's SKILL section (2026-08-02).
# Boots the real game scene, recruits a hero, opens its details panel and
# screenshots it — the panel is wired into main_game's UI, so there is no
# cheaper way to render it faithfully.
#
#   godot --path . res://scenes/_details_capture.tscn -- --hero=STATIC
#
# Writes user://_details_check.png (a build artifact — don't commit it).
# Needs a real window, so no --headless.

func _ready() -> void:
	var hero := "STATIC"
	var enemy := ""   # --enemy=<EnemyFactory type>, e.g. drowned_maw (2026-09-25)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hero="): hero = a.split("=")[1].to_upper()
		if a.begins_with("--enemy="): enemy = a.split("=")[1]

	get_window().size = Vector2i(1920, 1080)
	var mg: Node = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	for i in range(30):
		await get_tree().process_frame

	if enemy != "":
		var e: UnitBase = EnemyFactory.create_by_type(enemy)
		if not e:
			push_error("unknown enemy %s" % enemy)
			get_tree().quit()
			return
		add_child(e)
		hero = enemy
		await _capture(mg, e)
		return

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
	await _capture(mg, u)

func _capture(mg: Node, u: UnitBase) -> void:
	var hero: String = u.unit_name

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
	# Relic milestone popup (VD-20) can also open over everything.
	for n in mg.find_children("*", "RelicMilestoneScreen", true, false):
		(n as CanvasLayer).visible = false
	# Keep the production opening position so captures reveal layout regressions.

	for i in range(20):
		await get_tree().process_frame

	# The SKILL block sits below the fold — scroll to it, that's the whole point
	# of this capture.
	# Found by type: since 2026-09-28 the title bar is pinned above the scroll
	# area, so the ScrollContainer is no longer a direct child of Margin.
	var found: Array = mg.unit_details_panel.find_children("*", "ScrollContainer", true, false)
	var sc: ScrollContainer = found[0] as ScrollContainer if not found.is_empty() else null
	# Two shots: the panel as it opens (top) and scrolled all the way down.
	for i in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://_details_check.png"))
	if sc:
		sc.scroll_vertical = 100000
	for i in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://_details_check_bottom.png"))
	print("CAPTURED details — hero=%s level=%d MAG=%d ATK=%d"
		% [hero, u.level, u.magic_power, u.attack_damage])
	get_tree().quit()
