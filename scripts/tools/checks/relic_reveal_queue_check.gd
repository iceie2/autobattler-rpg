extends Node

# Check (2026-09-30): end-of-run relic unlock cards stack on the right
# like merges, a click skips to the next card, input is only swallowed while busy.
# Run: APPDATA=<scratch> godot --path . res://scenes/relic_reveal_queue_check.tscn [-- --shot]

var fails := 0

func check(ok: bool, msg: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", msg])
	if not ok:
		fails += 1

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var q := MergeToastQueue.new()
	q.toast_layer = 120
	q.click_to_skip = true
	q.backlog_speeds = false
	add_child(q)
	await get_tree().process_frame
	var drained := [false]
	q.drained.connect(func(): drained[0] = true)

	for i in range(4):
		q.enqueue_relic(Relic.POOL[(i * 7) % Relic.POOL.size()])
	await get_tree().create_timer(0.6).timeout

	check(q.is_busy(), "first relic card is playing")
	check(q.pending.size() == 3, "3 more parked (got %d)" % q.pending.size())
	var offs: Array = []
	for e in q.pending:
		offs.append(int((e["toast"] as CanvasLayer).offset.x))
	check(offs == [500, 1000, 1500], "parked one slot apart to the right %s" % str(offs))
	check(q._root.mouse_filter == Control.MOUSE_FILTER_STOP, "busy queue swallows clicks")
	check(is_equal_approx((q.active as RelicUnlockReveal).speed, 1.0), "no backlog speed-up for relics")

	if "--shot" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("user://_relic_queue.png"))
		print("CAPTURED relic queue")

	# A click skips the centre card; the next slides in.
	var first: Node = q.active
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	q._on_root_input(click)
	await get_tree().create_timer(0.9).timeout
	check(q.active != null and q.active != first, "click moved on to the next relic")
	check(q.pending.size() == 2, "two left parked after one skip (got %d)" % q.pending.size())

	# Skip the rest; the queue drains and stops swallowing clicks.
	for i in range(3):
		q.skip_current()
		await get_tree().create_timer(0.9).timeout
	check(drained[0], "drained signal fired after the last card")
	check(not q.is_busy(), "queue idle")
	check(q._root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "idle queue lets clicks through again")

	print("RELIC_QUEUE: %s" % ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit(0 if fails == 0 else 1)
