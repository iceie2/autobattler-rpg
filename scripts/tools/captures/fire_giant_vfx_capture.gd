extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   normal,air,water,earth,fire,lightning
# Override with: -- --round=N
const DEBUT_ROUND := 6

# Deterministic Fire Giant VFX captures. Runs WINDOWED (--headless renders empty
# PNGs).
# Run: godot --path . res://scenes/tools/fire_giant_vfx_capture.tscn
#
# This one renders over the REAL BackgroundLayer, unlike every earlier enemy
# capture in this project. Those all used a dark clear colour, which is exactly
# the environment that hid a z-order fault and a contrast fault for June — the
# board is GRASS, and an effect that only reads on near-black has not been
# verified at all. The Fire Giant is the worst possible unit to get this wrong
# on: its body is dark basalt covered in glowing ORANGE cracks, so the usual
# warm-effect choice would vanish into the unit itself.
const ZOOM := 1.5

func _ready() -> void:
	get_window().size = Vector2i(1200, 700)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	scale = Vector2(ZOOM, ZOOM)
	await _smash()
	await _fury()
	print("FIRE_GIANT_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _clear() -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()

func _u(pos: Vector2):
	var u = EnemyFactory.create_by_type("fire_giant")
	u.position = pos
	add_child(u)
	return u

func _save(n: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(CapturePaths.out(n))
	assert(err == OK, "capture failed: " + n)
	print("  saved %s" % n)

# Anticipation and release, the two frames the player has to read.
func _smash() -> void:
	_clear()
	var specs := [[FireGiantVFX.Mode.SMASH_WINDUP, 0.85],
		[FireGiantVFX.Mode.SMASH_IMPACT, 0.18]]
	for i in range(specs.size()):
		var g = _u(Vector2(200 + i * 340, 260))
		await get_tree().process_frame
		if g.health_bar: g.health_bar.hide()
		var fx := FireGiantVFX.new()
		add_child(fx)
		if specs[i][0] == FireGiantVFX.Mode.SMASH_IMPACT:
			fx.setup_point(specs[i][0], g.global_position, AutoBattleManager.FIRE_GIANT_REACH, 1.0)
		else:
			fx.setup_on(specs[i][0], g, AutoBattleManager.FIRE_GIANT_REACH, 1.0)
			fx.global_position = g.global_position
			fx.host = null
		fx.elapsed = specs[i][1]
		fx._t = 1.2
		fx.set_process(false)
		fx.queue_redraw()
	await _save("_fire_giant_molten_smash.png")

# The threshold crossing and the sustained state, side by side with a plain
# giant so the "is this actually distinguishable from its idle art" question has
# an answer in the frame rather than in my opinion.
func _fury() -> void:
	_clear()
	var modes := [-1, FireGiantVFX.Mode.FORGE_TRIGGER, FireGiantVFX.Mode.FORGE_FURY]
	var times := [0.0, 0.30, 0.0]
	for i in range(modes.size()):
		var g = _u(Vector2(180 + i * 300, 260))
		await get_tree().process_frame
		if g.health_bar: g.health_bar.hide()
		if int(modes[i]) < 0:
			continue          # control: untouched sprite, for the contrast check
		var fx := FireGiantVFX.new()
		add_child(fx)
		fx.setup_on(modes[i], g, AutoBattleManager.FIRE_GIANT_REACH, 1.0)
		fx.global_position = g.global_position
		fx.host = null
		fx.elapsed = times[i]
		fx._t = 1.1
		fx.set_process(false)
		fx.queue_redraw()
	await _save("_fire_giant_forge_fury.png")
