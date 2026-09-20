extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   normal,air,water,earth
# Override with: -- --round=N
const DEBUT_ROUND := 12
# Deterministic Gargoyle VFX captures. Runs WINDOWED.
const ZOOM := 2.2

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	# Render over the REAL board: the arena is sunlit GRASS, and an effect
	# only verified against a dark clear colour has not been verified.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	scale = Vector2(ZOOM, ZOOM)
	await _states()
	await _talon_scale()
	print("GARGOYLE_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2, code := "gargoyle"):
	var u = EnemyFactory.create_by_type(code)
	u.position = pos; u.scale = Vector2(1.0, 1.0); add_child(u)
	return u

func _save(n: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

# Plain / sealing seams / molten cracks. Bars visible.
func _states() -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()
	var modes := [-1, GargoyleVFX.Mode.STONE_SKIN, GargoyleVFX.Mode.CRACKED]
	for i in range(3):
		var g = _u(Vector2(120 + i * 160, 160))
		await get_tree().process_frame
		if modes[i] == -1:
			continue
		var fx := GargoyleVFX.new(); add_child(fx)
		fx.setup_on(modes[i], g, AutoBattleManager.GARGOYLE_REACH, 1.0)
		fx.global_position = g.global_position; fx.host = null
		fx.elapsed = 0.30 if modes[i] == GargoyleVFX.Mode.CRACKED else 0.0
		fx._t = 1.2
		fx.set_process(false); fx.queue_redraw()
	await _save("_gargoyle_stone_skin_vs_cracked.png")

# Same ability name as the Harpy => same visual, scaled to the heavier body.
func _talon_scale() -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()
	var codes := ["harpy", "gargoyle"]
	for i in range(2):
		var u = _u(Vector2(140 + i * 200, 160), codes[i])
		await get_tree().process_frame
		if u.health_bar: u.health_bar.hide()
		var fx := HarpyVFX.new(); add_child(fx)
		fx.setup_point(HarpyVFX.Mode.RAKE_IMPACT, u.global_position,
			u.get_meta("talon_vfx_reach", 84.0), 1.0)
		fx.elapsed = 0.30; fx._t = 1.0
		fx.set_process(false); fx.queue_redraw()
	await _save("_talon_harpy_vs_gargoyle_scale.png")
