extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Boss signature strike captures (BossStrikeVFX, 2026-09-28). Runs WINDOWED.
# Run: godot --path . res://scenes/tools/boss_vfx_capture.tscn
# Three bosses per frame, each mid-strike on a goblin, on a board from one of
# their decades.
const ZOOM := 1.25

func _ready() -> void:
	get_window().size = Vector2i(1280, 640)
	var bg := BackgroundLayer.new()
	add_child(bg)
	CapturePaths.cli_round(30)
	scale = Vector2(ZOOM, ZOOM)
	bg.set_biome_from_round(30)
	await _row("_boss_strikes_a.png", [["khagan", BossStrikeVFX.Style.SHELL_SLAM, 0.3],
		["triarch", BossStrikeVFX.Style.CLEAVE, 0.25], ["drowned_maw", BossStrikeVFX.Style.BITE, 0.28]])
	bg.set_biome_from_round(50)
	await _row("_boss_strikes_b.png", [["cloven_titan", BossStrikeVFX.Style.FAULT, 0.28],
		["emberhollow", BossStrikeVFX.Style.BACKDRAFT, 0.2], ["ember_heart", BossStrikeVFX.Style.SPIT, 0.35]])
	bg.set_biome_from_round(60)
	await _row("_boss_strikes_c.png", [["arcfang", BossStrikeVFX.Style.SUNDER, 0.2],
		["gravekeeper", BossStrikeVFX.Style.SWEEP, 0.3], ["the_architect", BossStrikeVFX.Style.CORNERSTONE, 0.3]])
	print("BOSS_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2, code: String):
	var u = EnemyFactory.create_by_type(code)
	u.position = pos; add_child(u)
	u.z_index = 2   # real battles give units z 2+row (_update_depth); no manager here
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

func _row(fname: String, specs: Array) -> void:
	_clear()
	var pairs: Array = []
	for i in specs.size():
		var x: float = 150.0 + float(i) * 330.0
		var boss = _u(Vector2(x, 170), specs[i][0])
		var hero = _u(Vector2(x + 30.0, 330), "goblin")
		pairs.append([boss, hero])
	await get_tree().process_frame
	for i in specs.size():
		var fx := BossStrikeVFX.new(); add_child(fx)
		fx.setup(specs[i][1], pairs[i][0], [pairs[i][1].global_position])
		fx._t = float(specs[i][2]) * fx._life
		fx.set_process(false); fx.queue_redraw()
	await _save(fname)
