extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   normal,air,water,earth,lightning
# Override with: -- --round=N
const DEBUT_ROUND := 51
# Deterministic Storm Giant VFX captures. Runs WINDOWED.
# Run: godot --path . res://scenes/tools/storm_giant_vfx_capture.tscn
const ZOOM := 1.7

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	# Render over the REAL board: the arena is sunlit GRASS, and an effect
	# only verified against a dark clear colour has not been verified.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	scale = Vector2(ZOOM, ZOOM)
	await _clap()
	await _gathering()
	print("STORM_GIANT_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2, code := "storm_giant"):
	var u = EnemyFactory.create_by_type(code)
	u.position = pos; add_child(u)
	return u

func _clear() -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()

func _save(n: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

func _pin(fx: StormGiantVFX, t: float, tt := 1.0) -> void:
	fx.elapsed = t * fx.lifetime if is_finite(fx.lifetime) else t
	fx._t = tt; fx.set_process(false); fx.queue_redraw()

# Cloud gathering, then the single heavy fork landing.
func _clap() -> void:
	_clear()
	var specs := [[StormGiantVFX.Mode.CLAP_WINDUP, 0.30], [StormGiantVFX.Mode.CLAP_WINDUP, 0.92],
		[StormGiantVFX.Mode.CLAP_IMPACT, 0.16], [StormGiantVFX.Mode.CLAP_IMPACT, 0.55]]
	for i in range(specs.size()):
		var g = _u(Vector2(110 + i * 155, 250))
		await get_tree().process_frame
		if g.health_bar: g.health_bar.hide()
		var fx := StormGiantVFX.new(); add_child(fx)
		if specs[i][0] == StormGiantVFX.Mode.CLAP_WINDUP:
			fx.setup_on(specs[i][0], g, AutoBattleManager.STORM_GIANT_REACH, 1.0)
			fx.global_position = g.global_position; fx.host = null
		else:
			fx.setup_point(specs[i][0], g.global_position, AutoBattleManager.STORM_GIANT_REACH, 1.0)
		_pin(fx, specs[i][1])
	await _save("_storm_giant_thunderclap.png")

# The ramp at 0 / +25% / +50%. Bars VISIBLE — this is also the evidence the
# overhead thunderhead does not sit on a 2x2 unit's health bar.
func _gathering() -> void:
	_clear()
	var ramps := [0.0, 0.5, 1.0]
	for i in range(3):
		var g = _u(Vector2(140 + i * 200, 250))
		await get_tree().process_frame
		var fx := StormGiantVFX.new(); add_child(fx)
		fx.setup_on(StormGiantVFX.Mode.GATHERING, g, AutoBattleManager.STORM_GIANT_REACH, 1.0)
		fx.global_position = g.global_position; fx.host = null
		fx.set_storm(ramps[i])
		_pin(fx, 0.0, 0.10 + float(i) * 0.9)
	await _save("_storm_giant_gathering_ramp.png")
