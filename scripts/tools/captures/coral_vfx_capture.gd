extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   normal,air,water,earth
# Override with: -- --round=N
const DEBUT_ROUND := 16
# Deterministic Coral Husk VFX captures. Runs WINDOWED.
const ZOOM := 2.5

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	# Render over the REAL board: the arena is sunlit GRASS, and an effect
	# only verified against a dark clear colour has not been verified.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	scale = Vector2(ZOOM, ZOOM)
	await _strip(CoralVFX.Mode.CALCIFY, [0.15, 0.55, 0.92], "_coral_calcify.png", [])
	await _strip(CoralVFX.Mode.SLOW_TIDE, [0.0, 0.0, 0.0], "_coral_slow_tide_ramp.png", [0.0, 0.5, 1.0])
	print("CORAL_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2):
	var u = EnemyFactory.create_by_type("coral_husk")
	u.position = pos; u.scale = Vector2(1.0, 1.0); add_child(u)
	return u

func _save(n: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

# `tides` empty = one-shot mode pinned by elapsed; otherwise pin the ramp value.
func _strip(kind: CoralVFX.Mode, times: Array, name: String, tides: Array) -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()
	var n: int = tides.size() if tides.size() > 0 else times.size()
	for i in range(n):
		var h = _u(Vector2(110 + i * 140, 150))
		await get_tree().process_frame
		var fx := CoralVFX.new(); add_child(fx)
		fx.setup_on(kind, h, AutoBattleManager.CORAL_REACH, 1.0)
		fx.global_position = h.global_position; fx.host = null
		if tides.size() > 0:
			fx.set_tide(tides[i])
		else:
			fx.elapsed = times[i]
		fx._t = 1.1
		fx.set_process(false); fx.queue_redraw()
	await _save(name)
