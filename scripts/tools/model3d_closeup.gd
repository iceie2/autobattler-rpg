extends Node2D
## Close-up clip review for a 3D hero, on the real board, through VisualUnit.
##
##   GODOT --path . res://scenes/tools/model3d_closeup.tscn -- --hero=STATIC [--round=N]
##        [--clips=idle,walk,attack,skill,ult] [--scale=3] [--frames=8] [--step=0.15]
##   -> captures/renders/<biome>/_closeup_<hero>_f<N>.png, one per time sample
##
## Written for Static's simulated cable (2026-10-01): at 115 px the rope is
## 2 px wide and a single board-check frame cannot show whether it SWINGS. This
## renders each clip looping side by side at `--scale` x the shipped height and
## saves a frame every `--step` seconds, so motion is reviewable as a strip.
## Not the size gate — model3d_board_check stays the at-scale check.

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=")[1]
	return def

func _ready() -> void:
	var round_n: int = CapturePaths.cli_round(1)
	var hero_name := _arg("hero", "STATIC").to_upper()
	if not UnitBase.UnitClass.has(hero_name):
		push_error("model3d_closeup: unknown hero '%s'" % hero_name)
		get_tree().quit(1)
		return
	var hero: int = UnitBase.UnitClass[hero_name]
	var clips: PackedStringArray = _arg("clips", "idle,walk,attack,skill,ult").split(",")
	var scale_k := float(_arg("scale", "3"))
	var frames := int(_arg("frames", "8"))
	var step := float(_arg("step", "0.15"))
	# The project stretches a 1920x1080 canvas to the window, so lay out in
	# canvas units and make the window match for a 1:1 capture.
	get_window().size = Vector2i(1920, 1080)
	var col_w := int(1880.0 / clips.size())

	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(round_n)

	Model3DSprite.debug_style_override = {
		"render_resolution": int(128 * scale_k),
		"render_height": VisualUnit.MODEL_RENDER_H * scale_k,
		"outline_px": 2.5 * scale_k,
	}
	var units: Array = []
	for i in clips.size():
		var u: VisualUnit = UnitFactory.create_unit(hero, UnitBase.Element.NORMAL, true)
		u.position = Vector2(20 + col_w * (i + 0.5), 140 + 75 * scale_k)
		u.can_be_dragged = false
		u.set_meta("anim_preview_lock", true)
		add_child(u)
		units.append(u)
	Model3DSprite.debug_style_override = {}
	await get_tree().process_frame
	for i in clips.size():
		var m: Model3DSprite = (units[i] as VisualUnit).model3d
		if m == null:
			push_error("model3d_closeup: %s has no 3D model" % hero_name)
			continue
		if not m.play(clips[i], true):
			push_warning("model3d_closeup: no clip '%s'" % clips[i])
		var hb = units[i].get_node_or_null("HealthBar")
		if hb:
			hb.visible = false
	await get_tree().create_timer(0.4).timeout
	for f in frames:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var p := CapturePaths.out("_closeup_%s_f%d.png" % [hero_name.to_lower(), f])
		img.save_png(p)
		await get_tree().create_timer(step).timeout
	print("model3d_closeup: wrote %d frames (%s) to %s" % [frames, ",".join(clips),
		CapturePaths.out("").get_base_dir()])
	get_tree().quit(0)
