extends Node

# Visual harness for the merge toast queue (2026-09-30): three hero merges and
# one equipment merge arriving together on the real board. Windowed + sandbox:
#   APPDATA=<scratch>/merge_profile godot --path . res://scenes/_merge_queue_capture.tscn
# Writes user://_mq_1.png (first playing, three parked), _mq_slide.png, _mq_2.png.

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("user://%s.png" % name))
	print("CAPTURED ", name)

func _hero_entry(cls: UnitBase.UnitClass, from_grade: String, to_grade: String) -> Array:
	var u := UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
	UnitFactory.apply_recruit_rolls(u, UnitFactory.generate_recruit_rolls())
	add_child(u)
	u.recruit_grade = from_grade
	var before := MergeResultScreen.snapshot(u)
	u.recruit_grade = to_grade
	u.attack_damage += 6
	u.max_hp += 40
	u.set_level(4)
	var out := [MergeResultScreen.info_of(u), before, MergeResultScreen.snapshot(u)]
	u.queue_free()
	return out

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
	var mgr: MergeToastQueue = mg._merge_toasts
	for spec in [[UnitBase.UnitClass.RIOT, "B", "A"], [UnitBase.UnitClass.DOC, "C", "B"],
			[UnitBase.UnitClass.BOUNCER, "A", "S"]]:
		var e := _hero_entry(spec[0], spec[1], spec[2])
		mgr.enqueue_hero(e[0], e[1], e[2])
	var pair: Array = []
	for i in range(300):
		var a := ComponentEquipmentRules.generate_item(12, 1)
		var b := ComponentEquipmentRules.generate_item(12, 1)
		if ComponentEquipmentRules.can_combine(a, b):
			pair = [a, b, ComponentEquipmentRules.combine(a, b, 1.0, ComponentEquipmentRules.random_removals(a, b))]
			break
	mgr.enqueue_equipment(pair[0], pair[1], pair[2])
	await get_tree().create_timer(0.7).timeout
	await _shot("_mq_1")
	# Wait for the next toast to take over (poll the queue length).
	var n: int = mgr.pending.size()
	while mgr.pending.size() == n:
		await get_tree().process_frame
	await get_tree().create_timer(0.09).timeout
	await _shot("_mq_slide")   # mid-slide: the parked card sliding into the centre
	await get_tree().create_timer(0.9).timeout
	await _shot("_mq_2")
	get_tree().quit()
