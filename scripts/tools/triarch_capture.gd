extends Node2D
# Visual + wiring check for the 3D Triarch (wave 70, 2026-10-03): runs the REAL
# advance_triarch_phase() twice on a real board and saves Knight -> Hunter ->
# Arcane Core side by side to captures/renders/<biome>/_triarch_phases.png.
# Windowed:  GODOT --path . res://scenes/tools/triarch_capture.tscn
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

var mgr
var grid
var _shots: Array = []

func _ready() -> void:
	get_window().size = Vector2i(1180, 1000)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(70)
	var board := Node2D.new()
	board.position = Vector2(140, 40)       # offset like the real game
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

	var boss: VisualUnit = EnemyFactory.create_by_type("triarch")
	boss.battle_manager = mgr
	board.add_child(boss)
	_put(boss, Vector2i(4, 1))
	var h: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.RIOT, UnitBase.Element.NORMAL, true)
	h.can_be_dragged = false
	board.add_child(h)
	_put(h, Vector2i(4, 6))
	mgr.enemy_units = [boss]
	mgr.player_units = [h]
	await get_tree().create_timer(0.8).timeout
	print("phase 1 visual: %s" % _path(boss))
	await _shot()
	for ph in [2, 3]:
		boss.current_hp = 0
		EnemyFactory.advance_triarch_phase(boss)
		await get_tree().create_timer(1.0).timeout
		print("phase %d visual: %s (%s)" % [ph, _path(boss), boss.unit_name])
		await _shot()

	var w: int = _shots[0].get_width()
	var h2: int = _shots[0].get_height()
	var sheet := Image.create(w * 3, h2, false, _shots[0].get_format())
	for k in _shots.size():
		sheet.blit_rect(_shots[k], Rect2i(0, 0, w, h2), Vector2i(k * w, 0))
	var out: String = CapturePaths.out("_triarch_phases.png")
	sheet.save_png(out)
	print("wrote %s" % out)
	get_tree().quit(0)

func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	_shots.append(img)

func _path(u: VisualUnit) -> String:
	if u.model3d:
		return "3D " + u.model3d.model_path.get_file()
	return "2D (fallback!)"

func _put(u, c: Vector2i) -> void:
	grid.place_unit(u, c)
	u.grid_position = c
	u.position = mgr._world_pos_for(u, c)
