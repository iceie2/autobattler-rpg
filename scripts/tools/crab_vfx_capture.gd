extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")
# Deterministic Crystal Crab VFX captures. Runs WINDOWED.
const ZOOM := 2.6
func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	RenderingServer.set_default_clear_color(Color(0.11, 0.10, 0.08))
	scale = Vector2(ZOOM, ZOOM)
	await _shell_states()
	await _form_and_break()
	print("CRAB_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _crab(pos: Vector2):
	var u = EnemyFactory.create_crystal_crab()
	u.position = pos; u.scale = Vector2(0.85, 0.85); add_child(u)
	return u

func _clear() -> void:
	for c in get_children(): c.free()

func _save(n: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

func _pin(fx: CrabVFX, t: float, tt := 1.0) -> void:
	fx.elapsed = t * fx.lifetime if is_finite(fx.lifetime) else t
	fx._t = tt; fx.set_process(false); fx.queue_redraw()

# Unshielded / full shell / chipped shell, side by side. Bars VISIBLE: this is
# also the evidence the shell never covers the health bar.
func _shell_states() -> void:
	_clear()
	var strengths := [-1.0, 1.0, 0.3]
	for i in range(3):
		var c = _crab(Vector2(85 + i * 175, 150))
		await get_tree().process_frame
		if strengths[i] < 0.0:
			continue
		var fx := CrabVFX.new(); add_child(fx)
		fx.setup_on(CrabVFX.Mode.SHELL_ACTIVE, c, AutoBattleManager.CRAB_REACH, 1.0)
		fx.global_position = c.global_position; fx.host = null
		fx.set_strength(strengths[i])
		_pin(fx, 0.0, 0.8 + float(i) * 0.9)
	await _save("_crab_shell_states.png")

func _form_and_break() -> void:
	_clear()
	var specs := [[CrabVFX.Mode.SHELL_FORM, 0.35], [CrabVFX.Mode.SHELL_FORM, 0.90],
		[CrabVFX.Mode.SHELL_BREAK, 0.25], [CrabVFX.Mode.SHELL_BREAK, 0.70]]
	for i in range(specs.size()):
		var c = _crab(Vector2(75 + i * 168, 150))
		await get_tree().process_frame
		if c.health_bar: c.health_bar.hide()
		var fx := CrabVFX.new(); add_child(fx)
		fx.setup_on(specs[i][0], c, AutoBattleManager.CRAB_REACH, 1.0)
		fx.global_position = c.global_position; fx.host = null
		_pin(fx, specs[i][1], 0.9)
	await _save("_crab_shell_form_break.png")
