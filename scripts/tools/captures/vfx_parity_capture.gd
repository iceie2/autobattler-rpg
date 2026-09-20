extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Side-by-side VFX parity check: one hero's effects against another's, on the
# SAME board, at the SAME zoom, with the SAME layout and a shared background
# control frame.
#
#   godot --path . res://scenes/tools/vfx_parity_capture.tscn [-- --round=N]
#
# WHY THIS EXISTS. "Is this hero's kit as strong as Zolt's?" was being answered
# by comparing each hero's own capture, and those are not comparable: Zolt's
# capture runs on a flat dark background at its own zoom, so a "differs from the
# background" mask catches most of his frame and almost none of a pale hero's on
# a pale board. The measured gap was an artefact of the two harnesses, not of
# the art. Anything that claims parity has to render both the same way.
#
# It is still only a LEGIBILITY measure — ink coverage and contrast against the
# board. It cannot tell you whether an effect reads as wind or as spaghetti.
# That judgement stays with a human.
const DEBUT_ROUND := 11
const ZOOM := 1.0

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	scale = Vector2(ZOOM, ZOOM)

	await _save_empty("_parity_control.png")
	# Four beats each, matched by ROLE so the comparison is like for like:
	# a passive/aura tick, a basic-attack impact, the skill, and the ultimate.
	await _vail_row("_parity_vail.png")
	await _zolt_row("_parity_zolt.png")
	print("VFX_PARITY_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _clear() -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()

func _save(n: String) -> void:
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

func _save_empty(n: String) -> void:
	_clear()
	await _save(n)

func _at(i: int) -> Vector2:
	return Vector2(150 + i * 120, 330)

func _vail_row(n: String) -> void:
	_clear()
	var kinds := [VailVFX.Mode.AURA_PULSE, VailVFX.Mode.GUST_IMPACT,
		VailVFX.Mode.UPDRAFT_LIFT, VailVFX.Mode.DOWNBURST_SLAM]
	var lives := [1.1, 0.34, 1.0, 0.70]
	for i in range(kinds.size()):
		var fx := VailVFX.new()
		add_child(fx)
		fx.setup_point(kinds[i], _at(i), lives[i])
		fx.elapsed = lives[i] * 0.55      # near each beat's peak
		fx.set_process(false)
		fx.queue_redraw()
	await _save(n)

func _zolt_row(n: String) -> void:
	_clear()
	var kinds := [ZoltVFX.Mode.STUN_RESIDUE, ZoltVFX.Mode.AUTO_IMPACT,
		ZoltVFX.Mode.ULT_MARK, ZoltVFX.Mode.ULT_STRIKE]
	var lives := [1.1, 0.36, 0.38, 0.90]
	for i in range(kinds.size()):
		var fx := ZoltVFX.new()
		add_child(fx)
		fx.setup_point(kinds[i], _at(i), lives[i])
		fx.elapsed = lives[i] * 0.55
		fx.set_process(false)
		fx.queue_redraw()
	await _save(n)
