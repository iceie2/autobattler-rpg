extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Deterministic Spore VFX strips over the REAL board. Runs WINDOWED.
#   godot --path . res://scenes/tools/spore_vfx_capture.tscn [-- --round=N]
#
# Spore is the earth decade's carry (31-40), but his violet language has to
# hold on grass (round 1, where nature-on-nature is the hard case) as well.
# Four copies of each beat, frozen at different points of its lifetime.
# The passive haze is drawn on real board tiles (2026-10-04), so it is checked
# in a live battle, not here.
const DEBUT_ROUND := 31

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	await _save("_spore_fx_control.png")
	await _strip("puff", 0.75, "_spore_fx_burst_puff.png", 1.0)
	await _strip("puff", 0.75, "_spore_fx_release_pop.png", 1.45)
	await _strip("ring", 0.7, "_spore_fx_release_ring.png", 1.0)
	print("SPORE_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _clear() -> void:
	for c in get_children():
		if not c is BackgroundLayer:
			c.free()

func _save(n: String) -> void:
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

func _strip(kind: String, life: float, name: String, k: float) -> void:
	_clear()
	for i in range(4):
		var fx := SporeVFX.new()
		add_child(fx)
		var at := Vector2(160 + i * 115, 360)
		match kind:
			"puff": fx.setup_puff(at, k, null)
			"ring": fx.setup_ring(at, 70.0, null)
		fx.lifetime = life
		fx.elapsed = life * (float(i) + 0.5) / 4.0
		fx.set_process(false)
		fx.queue_redraw()
	await _save(name)
