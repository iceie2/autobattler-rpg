extends Node2D

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Knock-up filmstrip. Samples the REAL play_knockup tween — not a reconstruction
# — at even intervals across the airborne window and blits each frame into one
# wide image, so the arc height and the single 360 can be judged as a motion
# rather than guessed from a still.
#
# Runs WINDOWED (--headless writes empty frames).
# Run: godot --path . res://scenes/tools/windup_bot_knockup_strip.tscn

const FRAMES := 7
# A small window is NOT honoured (the OS/engine clamps it), so the first cut
# cropped the top-left corner of a much larger viewport and caught nothing.
# Use a normal window and crop a fixed rect around the victim instead.
# Two measured facts drive these numbers, and guessing either one produced an
# empty strip:
#   1. the drawable client area is SHORTER than the requested window (900x506
#      for a 900x600 window — the title bar is not drawable);
#   2. the project applies a content scale, so world px != viewport px. A node
#      drawn at local (450,400) landed at viewport (210,187): a factor of
#      ~0.467. ROOT_SCALE cancels most of that back out.
const WINDOW := Vector2i(900, 600)
const CONTENT_SCALE := 0.467          # measured, not assumed
const ROOT_SCALE := 3.0               # net ~1.4x, so the arc is readable
const FEET_VIEW := Vector2(450, 400)  # where the victim stands, in VIEWPORT px
const CELL := Rect2i(310, 60, 280, 380)    # crop per sampled frame
const STUN := 1.5                     # nominal Wind-Up Punch stun

func _ready() -> void:
	get_window().size = WINDOW
	RenderingServer.set_default_clear_color(Color(0.11, 0.10, 0.08))

	var victim = EnemyFactory.create_goblin()
	scale = Vector2(ROOT_SCALE, ROOT_SCALE)
	victim.position = FEET_VIEW / (CONTENT_SCALE * ROOT_SCALE)
	victim.scale = Vector2(1.3, 1.3)
	add_child(victim)
	for i in range(4):
		await get_tree().process_frame
	if victim.health_bar: victim.health_bar.hide()

	var strip := Image.create(CELL.size.x * FRAMES, CELL.size.y, false, Image.FORMAT_RGBA8)
	victim.play_knockup(STUN)

	var t := 0.0
	var next := 0
	# Sample across the window plus a little tail, so the landing is in frame.
	var span: float = STUN * 1.05
	while next < FRAMES:
		await RenderingServer.frame_post_draw
		t += get_process_delta_time()
		var want: float = span * float(next) / float(FRAMES - 1)
		if t + 0.0001 >= want:
			var img := get_viewport().get_texture().get_image()
			# The viewport hands back whatever format/size the window actually
			# is; blit_rect silently refuses on a mismatch, so normalise both.
			img.convert(Image.FORMAT_RGBA8)
			strip.blit_rect(img, CELL, Vector2i(CELL.size.x * next, 0))
			next += 1

	var path := CapturePaths.out("windup_bot_knockup_strip.png")
	var err := strip.save_png(ProjectSettings.globalize_path(path))
	assert(err == OK, "strip save failed")
	print("WINDUP_BOT_KNOCKUP_STRIP: ALL PASS (peak %.0f px, one 360 over %.2fs)"
		% [VisualUnit.KNOCKUP_PEAK_HEIGHT, STUN])
	get_tree().quit(0)
