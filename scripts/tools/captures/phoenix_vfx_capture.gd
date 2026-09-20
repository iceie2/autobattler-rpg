extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   normal,air,water,earth,fire,lightning
# Override with: -- --round=N
const DEBUT_ROUND := 4
# Deterministic Ember Phoenix VFX captures. Runs WINDOWED.
const ZOOM := 2.6
func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	# Render over the REAL board: the arena is sunlit GRASS, and an effect
	# only verified against a dark clear colour has not been verified.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	scale = Vector2(ZOOM, ZOOM)
	await _pair(PhoenixVFX.Mode.LANCE_WINDUP, 0.85, "_phoenix_lance_windup.png")
	await _pair(PhoenixVFX.Mode.LANCE_IMPACT, 0.28, "_phoenix_lance_impact.png")
	await _states()
	print("PHOENIX_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2, kind := 0):
	var u = EnemyFactory.create_ember_phoenix() if kind == 0 else EnemyFactory.create_goblin()
	u.position = pos; u.scale = Vector2(1.15, 1.15); add_child(u)
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

func _pin(fx: PhoenixVFX, t: float, tt := 1.0) -> void:
	fx.elapsed = t * fx.lifetime if is_finite(fx.lifetime) else t
	fx._t = tt; fx.set_process(false); fx.queue_redraw()

func _pair(kind: PhoenixVFX.Mode, t: float, n: String) -> void:
	_clear()
	var ph = _u(Vector2(150, 132))
	var v = _u(Vector2(292, 132), 1)
	await get_tree().process_frame
	if ph.health_bar: ph.health_bar.hide()
	if v.health_bar: v.health_bar.hide()
	var fx := PhoenixVFX.new(); add_child(fx)
	if kind == PhoenixVFX.Mode.LANCE_WINDUP:
		fx.setup_on(kind, ph, AutoBattleManager.PHOENIX_REACH, 1.0)
		fx.global_position = ph.global_position; fx.host = null
	else:
		fx.setup_point(kind, v.global_position, AutoBattleManager.PHOENIX_REACH, 1.0)
	_pin(fx, t)
	await _save(n)

# Rekindle (regen ON) beside Smothered (the counterplay landing). Bars VISIBLE
# so the stills double as evidence neither effect covers them.
func _states() -> void:
	_clear()
	var a = _u(Vector2(110, 140))
	var b = _u(Vector2(250, 140))
	await get_tree().process_frame
	var f1 := PhoenixVFX.new(); add_child(f1)
	f1.setup_on(PhoenixVFX.Mode.REKINDLE, a, AutoBattleManager.PHOENIX_REACH, 1.0)
	f1.global_position = a.global_position; f1.host = null
	_pin(f1, 0.0, 0.9)
	var f2 := PhoenixVFX.new(); add_child(f2)
	f2.setup_on(PhoenixVFX.Mode.SMOTHERED, b, AutoBattleManager.PHOENIX_REACH, 1.0)
	f2.global_position = b.global_position; f2.host = null
	_pin(f2, 0.35)
	await _save("_phoenix_rekindle_vs_smothered.png")
