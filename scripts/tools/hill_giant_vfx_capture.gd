extends Node2D

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	RenderingServer.set_default_clear_color(Color(0.11, 0.10, 0.08))
	await _capture(HillGiantVFX.Mode.AUTO_IMPACT, "_hill_giant_auto_impact.png")
	await _capture(HillGiantVFX.Mode.SMASH_WARNING, "_hill_giant_smash_warning.png")
	await _capture(HillGiantVFX.Mode.SMASH_IMPACT, "_hill_giant_smash_impact.png")
	print("HILL_GIANT_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _capture(kind: HillGiantVFX.Mode, file_name: String) -> void:
	for child in get_children(): child.free()
	var giant := EnemyFactory.create_hill_giant()
	giant.position = Vector2(550, 330)
	giant.scale = Vector2(1.25, 1.25)
	add_child(giant)
	await get_tree().process_frame
	if giant.health_bar: giant.health_bar.hide()
	var fx := HillGiantVFX.new()
	add_child(fx)
	if kind == HillGiantVFX.Mode.SMASH_WARNING:
		fx.setup_warning(giant, 440.0, 1.0)
		fx.global_position = giant.global_position
		fx.elapsed = 0.72
	else:
		var pos := giant.global_position + (Vector2(105, 25) if kind == HillGiantVFX.Mode.AUTO_IMPACT else Vector2.ZERO)
		fx.setup_point(kind, pos, 440.0 if kind == HillGiantVFX.Mode.SMASH_IMPACT else 90.0, 1.0)
		fx.elapsed = 0.28 if kind == HillGiantVFX.Mode.SMASH_IMPACT else 0.20
	fx.set_process(false)
	fx.queue_redraw()
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://" + file_name
	var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	assert(err == OK, "capture failed: " + path)
