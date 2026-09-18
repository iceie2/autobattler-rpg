extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")
# Deterministic Harpy + shared-evade VFX captures. Runs WINDOWED.
const ZOOM := 2.5

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	RenderingServer.set_default_clear_color(Color(0.11, 0.10, 0.08))
	scale = Vector2(ZOOM, ZOOM)
	await _talon()
	await _evade()
	print("HARPY_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2, code := "harpy"):
	var u = EnemyFactory.create_by_type(code)
	u.position = pos; u.scale = Vector2(1.0, 1.0); add_child(u)
	return u

func _save(n: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

func _talon() -> void:
	for c in get_children(): c.free()
	var specs := [[HarpyVFX.Mode.RAKE_WINDUP, 0.85], [HarpyVFX.Mode.RAKE_IMPACT, 0.18],
		[HarpyVFX.Mode.RAKE_IMPACT, 0.55]]
	for i in range(specs.size()):
		var h = _u(Vector2(120 + i * 145, 150))
		await get_tree().process_frame
		if h.health_bar: h.health_bar.hide()
		var fx := HarpyVFX.new(); add_child(fx)
		if specs[i][0] == HarpyVFX.Mode.RAKE_WINDUP:
			fx.setup_on(specs[i][0], h, 84.0, 1.0)
			fx.global_position = h.global_position; fx.host = null
		else:
			fx.setup_point(specs[i][0], h.global_position, 84.0, 1.0)
		fx.elapsed = specs[i][1]; fx._t = 1.0
		fx.set_process(false); fx.queue_redraw()
	await _save("_harpy_talon_rake.png")

# The shared dodge beat, on BOTH users. Bars visible.
func _evade() -> void:
	for c in get_children(): c.free()
	var codes := ["harpy", "gale_warden"]
	for i in range(2):
		var u = _u(Vector2(130 + i * 180, 150), codes[i])
		await get_tree().process_frame
		var fx := EvadeVFX.new(); add_child(fx)
		fx.setup(u.global_position, AutoBattleManager.EVADE_REACH, 1.0, 1.0)
		fx.elapsed = 0.30
		fx.set_process(false); fx.queue_redraw()
	await _save("_evade_harpy_and_warden.png")
