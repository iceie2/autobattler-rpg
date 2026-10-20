extends Node
# Merge toast queue (2026-09-30). Standalone (no main_game), but run it in the
# usual sandbox anyway: APPDATA=<scratch>/merge_profile godot --headless --path . res://scenes/merge_queue_check.tscn
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	if not OS.get_user_data_dir().contains("merge_profile"):
		print("MERGE_QUEUE: refusing to run outside a merge_profile APPDATA sandbox")
		get_tree().quit(2)
		return
	seed(5521)
	await _run_order()
	await _run_slide()
	await _run_cap()
	await _run_click_skip()
	print("MERGE_QUEUE: ", "ALL PASS" if failures.is_empty() else str(failures))
	for i in range(3): await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _hero_entry(cls: UnitBase.UnitClass) -> Array:
	var u := UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
	UnitFactory.apply_recruit_rolls(u, UnitFactory.generate_recruit_rolls())
	add_child(u)
	u.recruit_grade = "B"
	var before := MergeResultScreen.snapshot(u)
	u.recruit_grade = "A"
	u.attack_damage += 5
	u.max_hp += 20
	var out := [MergeResultScreen.info_of(u), before, MergeResultScreen.snapshot(u)]
	u.queue_free()   # like a hero consumed by a later merge: the queue must not need the live unit
	return out

func _pair() -> Array:
	for i in range(200):
		var a := ComponentEquipmentRules.generate_item(12, 1)
		var b := ComponentEquipmentRules.generate_item(12, 1)
		if ComponentEquipmentRules.can_combine(a, b):
			var r := ComponentEquipmentRules.combine(a, b, ComponentEquipmentInventory.STAT_KEEP,
				ComponentEquipmentRules.random_removals(a, b))
			if r != null:
				return [a, b, r]
	return []

func _wait_idle(mgr: MergeToastQueue, limit: float = 60.0) -> void:
	var waited := 0.0
	while (mgr.is_busy() or not mgr.pending.is_empty()) and waited < limit:
		await get_tree().process_frame
		waited += get_process_delta_time()

# 3 hero merges + 1 equipment merge arriving in the same frame.
func _run_order() -> void:
	var mgr := MergeToastQueue.new()
	mgr.base_speed = 10.0
	add_child(mgr)
	var started: Array = []
	var backlog: Array = []
	var speeds: Array = []
	mgr.toast_started.connect(func(kind: String) -> void:
		started.append(kind)
		backlog.append(mgr.pending.size())
		speeds.append(mgr.active.speed))
	for cls in [UnitBase.UnitClass.RIOT, UnitBase.UnitClass.DOC, UnitBase.UnitClass.BOUNCER]:
		var e := _hero_entry(cls)
		mgr.enqueue_hero(e[0], e[1], e[2])
	var pair := _pair()
	check(not pair.is_empty(), "found an equipment pair")
	mgr.enqueue_equipment(pair[0], pair[1], pair[2])

	# The first plays at once, in the centre; the other three wait in the list.
	check(mgr.is_busy() and mgr.active is MergeResultScreen, "the first merge plays immediately")
	check(mgr.pending.size() == 3, "three merges wait behind it")
	# The waiting merges are the SAME cards as the playing one, parked to its right
	# (one slot each), dimmed; not a separate little list.
	check(mgr.pending[0]["toast"] is MergeResultScreen and mgr.pending[1]["toast"] is MergeResultScreen
		and mgr.pending[2]["toast"] is EquipmentMergeScreen, "waiting merges are real cards of the right kinds")
	var toast := mgr.active as MergeResultScreen
	check(toast.offset.x == 0.0, "the playing card is in the centre slot")
	var slots_ok := true
	for i in range(3):
		slots_ok = slots_ok and mgr.pending[i]["toast"].offset.x >= MergeToastQueue.SLOT_W * (i + 1)
	check(slots_ok, "waiting cards are parked one slot each to the right, in order")
	check(mgr.pending[0]["toast"].offset.x >= toast._panel.size.x, "the next card starts beyond the playing card's right edge")
	var dim: float = mgr.pending[0]["toast"]._panel.modulate.a
	check(dim > 0.5 and dim < 1.0, "parked cards are visible but dimmed")
	var vp := get_viewport().get_visible_rect().size
	check(absf(toast._panel.position.x + toast._panel.size.x * 0.5 - vp.x * 0.5) < 1.0, "the playing toast is centred")
	check(mgr._counter.visible and mgr._counter.text == "1 / 4", "the counter shows 1 / 4")

	# Nothing here may block the player.
	check(mgr._root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the queue root ignores the mouse")
	var blockers := 0
	for c in mgr.find_children("*", "Control", true, false):
		if (c as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
			blockers += 1
	check(blockers == 0, "no control anywhere in the queue can swallow a click (found %d)" % blockers)
	check(mgr.find_children("*", "BaseButton", true, false).is_empty(), "no buttons")

	# The backlog speeds the playing toast up.
	await get_tree().process_frame
	check(mgr.active.speed > mgr.base_speed, "a backlog plays the current toast faster")

	await _wait_idle(mgr)
	check(started == ["hero", "hero", "hero", "equipment"], "played strictly in order, hero then equipment (got %s)" % str(started))
	check(backlog == [0, 2, 1, 0], "the list shrinks one entry at a time (got %s)" % str(backlog))
	check(speeds.size() == 4 and speeds[2] > speeds[3] and absf(speeds[3] - mgr.base_speed) < 0.001,
		"speed eases back to normal as the list empties")
	check(not mgr._counter.visible and mgr.pending.is_empty() and not mgr.is_busy(), "counter hidden and queue idle at the end")
	mgr.queue_free()
	await get_tree().process_frame

# The next card slides from the right into the centre and the finished one goes.
func _run_slide() -> void:
	var mgr := MergeToastQueue.new()
	mgr.base_speed = 10.0
	add_child(mgr)
	var e1 := _hero_entry(UnitBase.UnitClass.RIOT)
	mgr.enqueue_hero(e1[0], e1[1], e1[2])
	var e2 := _hero_entry(UnitBase.UnitClass.DOC)
	mgr.enqueue_hero(e2[0], e2[1], e2[2])
	var first: Node = mgr.active
	var second: Node = mgr.pending[0]["toast"]
	check(first.offset.x == 0.0 and second.offset.x >= MergeToastQueue.SLOT_W, "the second card waits one slot to the right")
	var waited := 0.0
	while mgr.active != second and waited < 30.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(mgr.active == second, "the parked card became the playing card")
	check(second.offset.x > 0.0, "it starts its slide from the right")
	await get_tree().create_timer(MergeToastQueue.SLIDE_TIME + 0.12).timeout
	check(not is_instance_valid(second) or is_equal_approx(second.offset.x, 0.0), "the card slid to the centre")
	check(not is_instance_valid(first), "the finished card is gone")
	await _wait_idle(mgr)
	mgr.queue_free()
	await get_tree().process_frame

# Ten in a row: the speed-up is capped, and all of them still play.
func _run_cap() -> void:
	var mgr := MergeToastQueue.new()
	mgr.base_speed = 10.0
	add_child(mgr)
	var played: Array = []
	mgr.toast_started.connect(func(kind: String) -> void: played.append(kind))
	for i in range(10):
		var e := _hero_entry(UnitBase.UnitClass.RIOT)
		mgr.enqueue_hero(e[0], e[1], e[2])
	check(mgr.pending.size() == 9, "nine wait behind the first")
	await get_tree().process_frame
	check(is_equal_approx(mgr.active.speed, mgr.base_speed * MergeToastQueue.MAX_SPEEDUP), "speed-up is capped")
	await _wait_idle(mgr)
	check(played.size() == 10, "all ten played (%d)" % played.size())
	mgr.queue_free()
	await get_tree().process_frame

func _run_click_skip() -> void:
	var mgr := MergeToastQueue.new()
	add_child(mgr)
	var pair := _pair()
	mgr.enqueue_equipment(pair[0], pair[1], pair[2])
	var hero := _hero_entry(UnitBase.UnitClass.RIOT)
	mgr.enqueue_hero(hero[0], hero[1], hero[2])
	await get_tree().create_timer(0.15).timeout
	var first = mgr.active
	var second = mgr.pending[0]["toast"]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2.ZERO
	mgr._input(click)
	check(mgr.active == first, "outside click leaves the merge playing")
	click.position = first._card_a.get_global_transform_with_canvas() * (first._card_a.size * 0.5)
	click.button_index = MOUSE_BUTTON_RIGHT
	mgr._input(click)
	check(mgr.active == first, "right click leaves the merge playing")
	click.button_index = MOUSE_BUTTON_LEFT
	mgr._input(click)
	check(mgr.active == second and first.is_queued_for_deletion(), "item card click skips and advances the queue")
	first.skip()
	check(mgr.active == second, "repeated skip does not advance twice")
	# Click the next card while it is still sliding, with its CanvasLayer offset.
	click.position = second._card.get_global_transform_with_canvas() * (second._card.size * 0.5)
	mgr._input(click)
	check(not mgr.is_busy() and mgr.pending.is_empty(), "hero card click skips during the slide")
	await get_tree().create_timer(MergeToastQueue.SLIDE_TIME + 0.1).timeout
	check(not mgr.is_busy(), "slide callback cannot restart a skipped toast")
	mgr.queue_free()
	await get_tree().process_frame
