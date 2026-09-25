extends Node

# Visual harness for the stat-bonus reward screen (2026-09-23), plus the relic
# picker for the cross-menu consistency pass.
#
#   godot --path . res://scenes/_reward_capture.tscn -- --count=3 --perk=regen --grade=B
#   godot --path . res://scenes/_reward_capture.tscn -- --screen=relic
#
# Writes user://_reward_<count>_rest.png and user://_reward_<count>_hover.png
# (or user://_relic_rest.png) — build artifacts, delete them after looking.
#
# NOTE: needs a real window, so no --headless here.

func _ready() -> void:
	var count := 3
	var perk_id := "regen"
	var grade := "B"
	var source := "victory"
	var screen_kind := "reward"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--count="): count = int(a.split("=")[1])
		if a.begins_with("--perk="): perk_id = a.split("=")[1]
		if a.begins_with("--grade="): grade = a.split("=")[1].to_upper()
		if a.begins_with("--source="): source = a.split("=")[1]
		if a.begins_with("--screen="): screen_kind = a.split("=")[1]

	get_window().size = Vector2i(1920, 1080)

	# Stand-in for the dimmed board so the modal isn't judged against pure black.
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.24, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	if screen_kind == "relic":
		await _capture_relic()
		get_tree().quit()
		return

	var units: Array = []
	var classes: Array = UnitFactory.get_all_classes()
	# Skip the legacy RPG classes at the front of the enum — pick real heroes.
	var hero_classes: Array = classes.filter(
		func(c): return VisualUnit.HERO_SPRITE_PATHS.has(c))
	for i in range(mini(count, hero_classes.size())):
		var c: int = hero_classes[(i * 3) % hero_classes.size()]
		var u := UnitFactory.create_unit(c, UnitFactory.element_for_class(c), true)
		u.set_level(1 + i % 4)
		add_child(u)
		u.visible = false
		units.append(u)

	var def: Dictionary = {}
	for p in LevelUpScreen.PERKS:
		if p.id == perk_id:
			def = p
	var mult := 1.0
	for g in LevelUpScreen.PERK_GRADE_TABLE:
		if g.grade == grade:
			mult = float(g.mult)
	var perk: Dictionary = LevelUpScreen.offer_at_grade(def, grade, mult)

	var screen := RoundRewardScreen.new()
	add_child(screen)
	await get_tree().process_frame
	screen.present({"type": RoundReward.Type.STAT_BONUS, "perk": perk}, units, source)

	for i in range(60):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://_reward_%d_rest.png" % count))
	print("CAPTURED rest count=%d perk=%s grade=%s" % [count, perk_id, grade])

	var grid: Node = screen.get("_unit_grid")
	if grid and grid.get_child_count() > 0:
		(grid.get_child(0) as Control).mouse_entered.emit()
	for i in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://_reward_%d_hover.png" % count))
	print("CAPTURED hover")

	# Mid-pick frame: the count-up / fade beat.
	if grid and grid.get_child_count() > 0:
		var before: float = units[0].get(perk_stat(perk)) if perk_stat(perk) != "" else 0.0
		(grid.get_child(0) as Button).pressed.emit()
		for i in range(24):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("user://_reward_%d_pick.png" % count))
		print("CAPTURED pick  %s: %s -> %s" % [perk_stat(perk), before, units[0].get(perk_stat(perk))])
	get_tree().quit()


func perk_stat(perk: Dictionary) -> String:
	var s: String = perk.get("stat", "")
	return "hp_regen" if s == "regen" else s


func _capture_relic() -> void:
	var screen := RelicScreen.new()
	add_child(screen)
	await get_tree().process_frame
	var offers: Array = []
	for i in range(3):
		var r: Dictionary = Relic.POOL[(i * 5) % Relic.POOL.size()].duplicate()
		r["grade"] = ["D", "B", "A"][i]
		offers.append(r)
	var charges := 1 if "--reroll" in OS.get_cmdline_user_args() else 0
	screen.present(offers, 1, charges)
	for i in range(360):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://_relic_rest_%d.png" % charges))
	print("CAPTURED relic")
