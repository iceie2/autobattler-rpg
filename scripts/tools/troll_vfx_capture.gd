extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")
# Deterministic Troll VFX captures. Runs WINDOWED.
# Run: godot --path . res://scenes/tools/troll_vfx_capture.tscn
const ZOOM := 2.6
const E := UnitBase.Element.NORMAL

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	RenderingServer.set_default_clear_color(Color(0.11, 0.10, 0.08))
	scale = Vector2(ZOOM, ZOOM)
	await _cast()
	await _regen_vs_smothered()
	await _enraged()
	print("TROLL_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2, code := "troll_normal"):
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

func _pin(fx: TrollVFX, t: float, tt := 1.0) -> void:
	fx.elapsed = t * fx.lifetime if is_finite(fx.lifetime) else t
	fx._t = tt; fx.set_process(false); fx.queue_redraw()

func _cast() -> void:
	_clear()
	for i in range(3):
		var t = _u(Vector2(90 + i * 145, 145))
		await get_tree().process_frame
		if t.health_bar: t.health_bar.hide()
		var fx := TrollVFX.new(); add_child(fx)
		fx.setup_point(TrollVFX.Mode.ENRAGE_CAST, t.global_position, E,
			AutoBattleManager.TROLL_REACH, 1.0)
		_pin(fx, [0.15, 0.45, 0.80][i])
	await _save("_troll_enrage_cast.png")

# The regen readout beside the moment its counterplay lands. Bars VISIBLE:
# also the evidence neither effect covers them.
func _regen_vs_smothered() -> void:
	_clear()
	var a = _u(Vector2(110, 150))
	var b = _u(Vector2(265, 150))
	await get_tree().process_frame
	var f1 := TrollVFX.new(); add_child(f1)
	f1.setup_on(TrollVFX.Mode.REGEN, a, E, AutoBattleManager.TROLL_REACH, 1.0)
	f1.global_position = a.global_position; f1.host = null
	_pin(f1, 0.0, 1.1)
	var f2 := TrollVFX.new(); add_child(f2)
	f2.setup_on(TrollVFX.Mode.SMOTHERED, b, E, AutoBattleManager.TROLL_REACH, 1.0)
	f2.global_position = b.global_position; f2.host = null
	_pin(f2, 0.35)
	await _save("_troll_regen_vs_smothered.png")

func _enraged() -> void:
	_clear()
	for i in range(2):
		var t = _u(Vector2(110 + i * 155, 150))
		await get_tree().process_frame
		if i == 0:
			continue          # left = unbuffed control
		var fx := TrollVFX.new(); add_child(fx)
		fx.setup_on(TrollVFX.Mode.ENRAGED, t, E, AutoBattleManager.TROLL_REACH, 1.0)
		fx.global_position = t.global_position; fx.host = null
		_pin(fx, 0.0, 1.3)
	await _save("_troll_enraged_vs_normal.png")
