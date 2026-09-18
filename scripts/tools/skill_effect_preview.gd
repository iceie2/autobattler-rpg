extends Node2D
## Frame-strip preview of one SkillEffect type, so a procedural VFX can be
## judged before it is seen in a live battle.
##
##   GODOT --path . res://scenes/tools/skill_effect_preview.tscn -- --fx=SERUM_SPRAY
##   → user://_skill_effect_preview.png
##
## Every other VFX in skill_effect.gd was authored by running the game and
## watching for it to happen. That is fine for an effect that fires constantly
## and useless for one gated behind a heal trigger, and it gives no way to
## compare frames. This lays the effect's whole lifetime out in a row at a fixed
## time step, which is how the animation strips for the 3D clips are reviewed.

const OUT := "user://_skill_effect_preview.png"
const SHOTS := 6
const COLS := 3
const CELL := Vector2(430, 200)
const FROM := Vector2(40, 130)
const TO := Vector2(330, 110)

func _ready() -> void:
	# Grid, not a single column: a window taller than the desktop is silently
	# clamped by the OS and the capture comes back cropped (measured: a
	# 6x220 = 1320 px request produced a 292 px image).
	var rows: int = int(ceil(float(SHOTS) / COLS))
	get_window().size = Vector2i(int(CELL.x) * COLS, int(CELL.y) * rows)
	var kind := "SERUM_SPRAY"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fx="):
			kind = a.substr(5).to_upper()
	if not SkillEffect.Type.has(kind):
		push_error("skill_effect_preview: unknown type '%s'" % kind)
		get_tree().quit(1)
		return

	# One effect per row, each advanced to a different point in its lifetime, so
	# the strip reads left-to-right as the effect's own timeline.
	var fxs: Array = []
	for i in SHOTS:
		var fx := SkillEffect.new()
		add_child(fx)
		fx.position = Vector2(CELL.x * (i % COLS), CELL.y * (i / COLS))
		if kind == "SERUM_SPRAY":
			fx.setup_spray(FROM + fx.position, TO + fx.position)
		else:
			fx.setup(SkillEffect.Type[kind], TO + fx.position)
		# Freeze each one at its own phase: _process would run them all in step.
		fx.set_process(false)
		fx.elapsed = fx.lifetime * (float(i) + 0.5) / float(SHOTS)
		fx.queue_redraw()
		fxs.append(fx)

	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT)
	print("wrote ", OUT, "  ", kind, "  ", img.get_width(), "x", img.get_height())
	get_tree().quit()
