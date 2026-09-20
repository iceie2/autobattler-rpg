extends Node

# Visual harness for the event panel (2026-09-19 catalog/grade pass).
# Renders one catalog event three ways — the choices as offered, the grade reel
# mid-spin, and the outcome after it lands — so the new reel slot can be checked
# for layout (does it collide with the art? is it on the panel at all?) without
# rolling a real run and waiting for a 25% dice roll.
#
#   godot --path . res://scenes/_event_capture.tscn -- --event=the_crossroads --grade=S
#
# Writes three PNGs through CapturePaths (never into the project — see
# capture_paths.gd). NOTE: needs a real window, so no --headless.

const CapturePathsScript = preload("res://scripts/tools/capture_paths.gd")

func _ready() -> void:
	var event_id := "the_crossroads"
	var grade := "S"
	var round_no := 25
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--event="): event_id = a.split("=")[1]
		if a.begins_with("--grade="): grade = a.split("=")[1].to_upper()
		if a.begins_with("--round="): round_no = int(a.split("=")[1])

	get_window().size = Vector2i(1920, 1080)

	var ctx := {
		"round": round_no, "gold": 80, "team_size": 6, "team_max": 8,
		"items": 4, "relics": 2, "dominant_element": 3, "flags": {},
	}
	var event: EventBlessing = EventGenerator.build_by_id(event_id, ctx)
	if event == null:
		push_error("unknown event id '%s'" % event_id)
		get_tree().quit()
		return

	var panel := EventPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.show_event(event)
	for _i in range(20):
		await get_tree().process_frame
	await _shot("event_choices")

	# Resolve choice 0 exactly the way main_game does, then drive the reel.
	var choice = event.choices[0]
	var resolved: Dictionary = choice.resolve.call(ctx, grade)
	choice.effects = resolved.get("effects", {})
	choice.description = String(resolved.get("outcome", ""))
	panel.show_resolution(choice.description, true, grade, choice.band)

	# Mid-spin: early enough that the reel is still flashing candidates.
	for _i in range(8):
		await get_tree().process_frame
	await _shot("event_reel")

	# Landed: the reel has settled and the outcome line is up. The spin is 14
	# decelerating ticks (~0.9s wall clock), so this waits well past it — at 90
	# frames the first capture caught the reel still flashing and reported an
	# empty outcome line, which looked like a bug in the panel rather than in
	# the capture's timing.
	for _i in range(240):
		await get_tree().process_frame
	await _shot("event_outcome")

	print("CAPTURED %s at grade %s — outcome: %s" % [event_id, grade, choice.description])
	get_tree().quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	# out() already returns an absolute path outside res:// — see capture_paths.gd.
	var path: String = CapturePathsScript.out("%s.png" % name)
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("  -> %s%s" % [path, "" if err == OK else "  (SAVE FAILED)"])
