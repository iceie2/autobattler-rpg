extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")
# Deterministic Bear VFX captures. Runs WINDOWED.
# Run: godot --path . res://scenes/tools/bear_vfx_capture.tscn
const ZOOM := 2.6

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	RenderingServer.set_default_clear_color(Color(0.11, 0.10, 0.08))
	scale = Vector2(ZOOM, ZOOM)
	await _pair(BearVFX.Mode.SWIPE_WINDUP, 0.85, "_bear_swipe_windup.png")
	await _pair(BearVFX.Mode.SWIPE_IMPACT, 0.30, "_bear_swipe_impact.png")
	await _bleed_states()
	await _fury_states()
	print("BEAR_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2, kind := 0):
	var u
	match kind:
		0: u = EnemyFactory.create_bear_normal()
		1: u = EnemyFactory.create_goblin()
		_: u = EnemyFactory.create_windup_bot_normal()
	u.position = pos; u.scale = Vector2(1.0, 1.0); add_child(u)
	return u

func _clear() -> void:
	for c in get_children(): c.free()

func _save(n: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

func _pin(fx: BearVFX, t: float, tt := 1.0) -> void:
	fx.elapsed = t * fx.lifetime if is_finite(fx.lifetime) else t
	fx._t = tt; fx.set_process(false); fx.queue_redraw()

func _pair(kind: BearVFX.Mode, t: float, n: String) -> void:
	_clear()
	var b = _u(Vector2(150, 132))
	var v = _u(Vector2(300, 132), 1)
	await get_tree().process_frame
	if b.health_bar: b.health_bar.hide()
	if v.health_bar: v.health_bar.hide()
	var fx := BearVFX.new(); add_child(fx)
	if kind == BearVFX.Mode.SWIPE_WINDUP:
		fx.setup_on(kind, b, AutoBattleManager.BEAR_REACH, 1.0)
		fx.global_position = b.global_position; fx.host = null
	else:
		fx.setup_point(kind, v.global_position, AutoBattleManager.BEAR_REACH, 1.0)
	_pin(fx, t)
	await _save(n)

# THE key still: standing vs moving. The bleed ticks twice as fast while the
# victim moves, and the visual has to make that difference obvious.
# Bars VISIBLE — also the evidence the bleed never covers them.
func _bleed_states() -> void:
	_clear()
	var labels := [0.0, 1.0]
	for i in range(2):
		var v = _u(Vector2(110 + i * 150, 140), 1)
		await get_tree().process_frame
		var fx := BearVFX.new(); add_child(fx)
		fx.setup_on(BearVFX.Mode.BLEED, v, AutoBattleManager.BEAR_REACH, 1.0)
		fx.global_position = v.global_position; fx.host = null
		fx.set_intensity(labels[i])
		_pin(fx, 0.0, 1.4)
	await _save("_bear_bleed_standing_vs_moving.png")

# Fury at 0 / mid / max of the missing-HP ramp.
func _fury_states() -> void:
	_clear()
	var ramps := [0.0, 0.5, 1.0]
	for i in range(3):
		var b = _u(Vector2(95 + i * 140, 140))
		await get_tree().process_frame
		var fx := BearVFX.new(); add_child(fx)
		fx.setup_on(BearVFX.Mode.FURY, b, AutoBattleManager.BEAR_REACH, 1.0)
		fx.global_position = b.global_position; fx.host = null
		fx.set_rage(ramps[i])
		_pin(fx, 0.0, 0.7 + float(i) * 0.8)
	await _save("_bear_fury_ramp.png")
