extends Node

# Visual harness for hero merging (2026-09-28): the Merge Heroes panel and the
# merge beat on the real board. Needs a real window (no --headless). Run in a
# scratch profile so user:// (and the PNGs) land outside the owner's saves:
#
#   APPDATA=<scratch>/merge_profile godot --path . res://scenes/_merge_capture.tscn
#
# Writes user://_merge_panel.png, _merge_fx_1..4.png.

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://%s.png" % name))
	print("CAPTURED ", name)

func _ready() -> void:
	if not OS.get_user_data_dir().contains("merge_profile"):
		print("refusing to run outside a merge_profile APPDATA sandbox")
		get_tree().quit(2); return
	get_window().size = Vector2i(1920, 1080)
	var mg: Node = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	for i in range(30):
		await get_tree().process_frame
	for modal in [mg._relic_screen, mg._hero_shop, mg._run_map_screen]:
		if modal:
			modal.visible = false
	mg.game_state.current_state = GameState.State.PLAYER_TURN
	mg.max_player_units = 10
	for u in mg.player_units.duplicate():
		mg.player_units.erase(u); mg.battle_grid.purge_unit(u); u.queue_free()
	var cls := UnitBase.UnitClass.RIOT
	var el := UnitFactory.element_for_class(cls)
	for i in range(3):
		mg._recruit_hero(cls, el, UnitFactory.generate_recruit_rolls())
	mg._recruit_hero(UnitBase.UnitClass.DOC, UnitFactory.element_for_class(UnitBase.UnitClass.DOC),
		UnitFactory.generate_recruit_rolls())
	var a: VisualUnit = mg.player_units[0]
	var b: VisualUnit = mg.player_units[1]
	var c: VisualUnit = mg.player_units[2]
	a.recruit_grade = "B"; b.recruit_grade = "B"; c.recruit_grade = "C"   # c is a lesser copy
	a.set_level(6); c.set_level(3)
	mg._bench_unit(c)
	for i in range(10):
		await get_tree().process_frame

	mg._on_merge_pressed()
	for i in range(20):
		await get_tree().process_frame
	await _shot("_merge_panel")
	# The same panel with the lesser copy picked: a partial merge.
	mg._merge_panel._picked = [a, c]
	mg._merge_panel.refresh(mg.player_units, mg.bench_units)
	for i in range(10):
		await get_tree().process_frame
	await _shot("_merge_panel_partial")
	mg._merge_panel.visible = false

	# Field + field: b is pulled into a, then the burst.
	mg._try_merge_heroes(b, a)
	var times := [0.18, 0.30, 0.25, 0.45]
	for i in range(times.size()):
		await get_tree().create_timer(times[i]).timeout
		await _shot("_merge_fx_%d" % (i + 1))
	# Transformation toast (self-running): old grade, mid-transform, mid stats, final.
	while not mg._merge_toasts.is_busy():
		await get_tree().process_frame
	await get_tree().create_timer(0.45).timeout
	await _shot("_merge_toast_old")
	await get_tree().create_timer(0.45).timeout
	await _shot("_merge_toast_flash")
	await get_tree().create_timer(1.3).timeout
	await _shot("_merge_toast_stats")
	await get_tree().create_timer(2.6).timeout
	await _shot("_merge_toast_final")
	# Now the lesser copy: a partial merge into the (now A) hero.
	while mg._merge_toasts.is_busy():
		await get_tree().process_frame
	mg._try_merge_heroes(c, a)
	while not mg._merge_toasts.is_busy():
		await get_tree().process_frame
	await get_tree().create_timer(0.45).timeout
	await _shot("_merge_partial_start")
	await get_tree().create_timer(1.5).timeout
	await _shot("_merge_partial_end")
	get_tree().quit()
