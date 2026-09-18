extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")
# Deterministic Minotaur VFX captures. Runs WINDOWED.
# Run: godot --path . res://scenes/tools/minotaur_vfx_capture.tscn
const ZOOM := 2.4

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	RenderingServer.set_default_clear_color(Color(0.11, 0.10, 0.08))
	scale = Vector2(ZOOM, ZOOM)
	await _gore()
	await _savage()
	print("MINOTAUR_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2, code := "minotaur"):
	var u = EnemyFactory.create_by_type(code)
	u.position = pos; u.scale = Vector2(0.95, 0.95); add_child(u)
	return u

func _clear() -> void:
	for c in get_children(): c.free()

func _save(n: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

func _pin(fx: MinotaurVFX, t: float, tt := 1.0) -> void:
	fx.elapsed = t * fx.lifetime if is_finite(fx.lifetime) else t
	fx._t = tt; fx.set_process(false); fx.queue_redraw()

# Windup escalating, then the horns going through — the tell has to escalate
# monotonically so one still cannot carry it.
func _gore() -> void:
	_clear()
	var specs := [[MinotaurVFX.Mode.GORE_WINDUP, 0.25], [MinotaurVFX.Mode.GORE_WINDUP, 0.90],
		[MinotaurVFX.Mode.GORE_IMPACT, 0.22], [MinotaurVFX.Mode.GORE_IMPACT, 0.65]]
	for i in range(specs.size()):
		var m = _u(Vector2(85 + i * 140, 160))
		await get_tree().process_frame
		if m.health_bar: m.health_bar.hide()
		var fx := MinotaurVFX.new(); add_child(fx)
		if specs[i][0] == MinotaurVFX.Mode.GORE_WINDUP:
			fx.setup_on(specs[i][0], m, AutoBattleManager.MINOTAUR_REACH, 1.0)
			fx.global_position = m.global_position; fx.host = null
		else:
			fx.setup_point(specs[i][0], m.global_position, AutoBattleManager.MINOTAUR_REACH, 1.0)
		_pin(fx, specs[i][1], 1.0)
	await _save("_minotaur_gore_rush.png")

# Savage Charge at 0 / mid / max. Bars VISIBLE — also the overlap evidence.
func _savage() -> void:
	_clear()
	var ramps := [0.0, 0.5, 1.0]
	for i in range(3):
		var m = _u(Vector2(110 + i * 160, 160))
		await get_tree().process_frame
		var fx := MinotaurVFX.new(); add_child(fx)
		fx.setup_on(MinotaurVFX.Mode.SAVAGE, m, AutoBattleManager.MINOTAUR_REACH, 1.0)
		fx.global_position = m.global_position; fx.host = null
		fx.set_rage(ramps[i])
		_pin(fx, 0.0, 0.6 + float(i) * 0.9)
	await _save("_minotaur_savage_ramp.png")
