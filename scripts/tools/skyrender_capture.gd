extends Node2D
# Visual check for 3D Skyrender (wave-20 boss, v002 spread-wing body, 2026-10-04).
# Real board (wave-20 biome), boss + three heroes, two moments side by side:
#   1. grounded  -- idle, wings held open
#   2. aloft     -- `skyrender_aloft` set: fly clip + the body lifted off the board
# Writes captures/renders/<biome>/_skyrender.png. Windowed (3D needs a GPU):
#   GODOT --path . res://scenes/tools/skyrender_capture.tscn
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

var mgr
var grid
var _shots: Array = []

func _ready() -> void:
	get_window().size = Vector2i(1180, 1000)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(20)
	var board := Node2D.new()
	board.position = Vector2(140, 40)
	add_child(board)
	grid = load("res://scripts/combat/battle_grid.gd").new()
	board.add_child(grid)
	mgr = load("res://scripts/combat/auto_battle_manager.gd").new()
	add_child(mgr)
	var fx := Node2D.new()
	fx.z_index = 3
	add_child(fx)
	mgr.battle_grid = grid
	mgr.skill_effect_container = fx
	await get_tree().process_frame

	# `-- --boss=<type>` (2026-10-05): any boss, grounded shot only -- the boss
	# audits reuse this board setup. Default is Skyrender's full sequence.
	var code := "skyrender"
	var round_n := 20
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--boss="):
			code = a.split("=")[1]
		if a.begins_with("--round="):
			round_n = int(a.split("=")[1])
	if round_n != 20:
		bg.set_biome_from_round(round_n)
	var boss: VisualUnit = EnemyFactory.create_by_type(code)
	boss.battle_manager = mgr
	board.add_child(boss)
	_put(boss, Vector2i(3, 1))
	var heroes: Array = []
	var spots := {UnitBase.UnitClass.BLOODHOUND: Vector2i(2, 6), UnitBase.UnitClass.RIOT: Vector2i(4, 6),
		UnitBase.UnitClass.SABLE: Vector2i(6, 7)}
	for cls in spots:
		var h: VisualUnit = UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
		h.can_be_dragged = false
		h.battle_manager = mgr
		board.add_child(h)
		_put(h, spots[cls])
		heroes.append(h)
	mgr.enemy_units = [boss]
	mgr.player_units = heroes
	await get_tree().create_timer(0.8).timeout
	print("%s visual: %s" % [code, ("3D " + boss.model3d.model_path.get_file()) if boss.model3d else "2D (fallback!)"])
	await _shot()
	if code != "skyrender":
		# Close-up of the body too, for judging the model at board size.
		await RenderingServer.frame_post_draw
		var full: Image = get_viewport().get_texture().get_image()
		var k: float = float(full.get_width()) / get_viewport().get_visible_rect().size.x
		var c: Vector2 = boss.get_global_transform_with_canvas().origin * k
		var crop: Image = full.get_region(Rect2i(int(c.x - 200 * k), int(c.y - 230 * k), int(400 * k), int(330 * k)))
		crop.resize(800, 660)
		var outc: String = CapturePaths.out("_%s_closeup.png" % code)
		crop.save_png(outc)
		var outb: String = CapturePaths.out("_%s.png" % code)
		_shots[0].save_png(outb)
		print("wrote %s and %s" % [outb, outc])
		get_tree().quit(0)
		return
	boss.set_meta("skyrender_aloft", true)
	await get_tree().create_timer(1.3).timeout
	await _shot()
	# 3-4: the aerial snatch -- end of the swoop, then mid-carry.
	heroes[1].damage_dealt = 9999
	mgr._skyrender_long_fall_begin(boss, heroes)
	await get_tree().create_timer(AutoBattleManager.LONG_FALL_SWOOP + 0.1).timeout
	await _shot()
	# In the beat held at the edge, just before the drop.
	await get_tree().create_timer(AutoBattleManager.LONG_FALL_GRAB + AutoBattleManager.LONG_FALL_CARRY).timeout
	await _shot()
	# 5: Storm Dive telegraph + a Downdraft beat on the same frame; 6: the crash.
	await get_tree().create_timer(3.0).timeout
	mgr._storm_dive_begin(boss, heroes)
	mgr._skyrender_downdraft(boss, heroes)
	await get_tree().create_timer(0.3).timeout
	await _shot()
	await get_tree().create_timer(AutoBattleManager.STORM_DIVE_TELEGRAPH - 0.3).timeout
	mgr._storm_dive_land(boss, heroes)
	boss.set_meta("skyrender_aloft", false)
	await get_tree().create_timer(0.15).timeout
	await _shot()

	var w: int = _shots[0].get_width()
	var h2: int = _shots[0].get_height()
	var sheet := Image.create(w * 2, h2 * 3, false, _shots[0].get_format())
	for k in _shots.size():
		sheet.blit_rect(_shots[k], Rect2i(0, 0, w, h2), Vector2i((k % 2) * w, (k / 2) * h2))
	var out: String = CapturePaths.out("_skyrender.png")
	sheet.save_png(out)
	print("wrote %s" % out)
	get_tree().quit(0)

func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	_shots.append(img)

func _put(u, c: Vector2i) -> void:
	grid.place_unit(u, c)
	u.grid_position = c
	u.position = mgr._world_pos_for(u, c)
