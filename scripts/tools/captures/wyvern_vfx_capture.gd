extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   air,lightning
# Override with: -- --round=N
const DEBUT_ROUND := 11
# Deterministic Sky Wyvern VFX captures. Runs WINDOWED.
const ZOOM := 1.8

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	# Render over the REAL board: the arena is sunlit GRASS, and an effect
	# only verified against a dark clear colour has not been verified.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	scale = Vector2(ZOOM, ZOOM)
	await _sting()
	await _venom_vs_disease()
	print("WYVERN_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2, code := "sky_wyvern"):
	var u = EnemyFactory.create_by_type(code)
	u.position = pos; add_child(u)
	return u

func _save(n: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n))
	assert(err == OK, "capture failed: " + n)
	print("  saved %s" % n)

func _sting() -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()
	var specs := [[WyvernVFX.Mode.STING_WINDUP, 0.85], [WyvernVFX.Mode.STING_IMPACT, 0.20],
		[WyvernVFX.Mode.WOUNDED_DIVE, 0.0]]
	var rages := [0.0, 0.0, 1.0]
	for i in range(specs.size()):
		var w = _u(Vector2(150 + i * 200, 230))
		await get_tree().process_frame
		if w.health_bar: w.health_bar.hide()
		var fx := WyvernVFX.new(); add_child(fx)
		if specs[i][0] == WyvernVFX.Mode.STING_IMPACT:
			fx.setup_point(specs[i][0], w.global_position, AutoBattleManager.WYVERN_REACH, 1.0)
		else:
			fx.setup_on(specs[i][0], w, AutoBattleManager.WYVERN_REACH, 1.0)
			fx.global_position = w.global_position; fx.host = null
		fx.set_rage(rages[i])
		fx.elapsed = specs[i][1]; fx._t = 1.2
		fx.set_process(false); fx.queue_redraw()
	await _save("_wyvern_sting_and_dive.png")

# The two bespoke DoT fictions side by side on identical victims: the Rat's
# plague drifts UP in soft motes, the Wyvern's venom runs DOWN in hard droplets.
func _venom_vs_disease() -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()
	for i in range(2):
		var v = _u(Vector2(200 + i * 240, 230), "goblin")
		await get_tree().process_frame
		var fx: Node2D
		if i == 0:
			var r := RatVFX.new()
			r.setup_disease(v, AutoBattleManager.RAT_BITE_REACH)
			r._spin = 1.3          # RatVFX animates on _spin, NOT _t
			fx = r
		else:
			var w := WyvernVFX.new()
			w.setup_on(WyvernVFX.Mode.VENOM, v, AutoBattleManager.RAT_BITE_REACH * 1.15, 1.0)
			w._t = 1.3
			fx = w
		add_child(fx)
		fx.global_position = v.global_position
		fx.set("host", null)
		fx.set_process(false); fx.queue_redraw()
	await _save("_dot_disease_vs_venom.png")
