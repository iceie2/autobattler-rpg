extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   normal,air,water,earth,fire
# Override with: -- --round=N
const DEBUT_ROUND := 6
# Deterministic Skeleton VFX captures. Runs WINDOWED.
const ZOOM := 2.6

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	# Render over the REAL board: the arena is sunlit GRASS, and an effect
	# only verified against a dark clear colour has not been verified.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	scale = Vector2(ZOOM, ZOOM)
	await _strip(SkeletonVFX.Mode.REASSEMBLE, [0.10, 0.40, 0.70, 0.92], "_skeleton_reassemble.png")
	await _strip(SkeletonVFX.Mode.BONE_SHIELD, [0.15, 0.55, 0.90], "_skeleton_bone_shield.png")
	print("SKELETON_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2):
	var u = EnemyFactory.create_by_type("skeleton")
	u.position = pos; u.scale = Vector2(1.05, 1.05); add_child(u)
	return u

func _save(n: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

func _strip(kind: SkeletonVFX.Mode, times: Array, name: String) -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()
	for i in range(times.size()):
		var k = _u(Vector2(90 + i * 120, 150))
		await get_tree().process_frame
		var fx := SkeletonVFX.new(); add_child(fx)
		fx.setup_on(kind, k, AutoBattleManager.SKELETON_REACH, 1.0)
		fx.global_position = k.global_position; fx.host = null
		fx.elapsed = times[i]
		fx._t = 1.0
		fx.set_process(false); fx.queue_redraw()
	await _save(name)
