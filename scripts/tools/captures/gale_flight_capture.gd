extends Node2D
# Gale Warden flock in FLIGHT, on the REAL board (2026-10-06). A live fight —
# the real AutoBattleManager loop, 6 level-9 birds (Veteran) against a level-7
# team on the round-15 Air board — written as two sheets:
#   _gale_flight.png        8 frames, 0.5 s apart: circling / passes / dives
#   _gale_hunt.png          8 frames after a forced bird death: the mark, the
#                           flock converging, the countdown ring draining
# plus _gale_flight_closeup.png (one bird, 8 poses: bank, hover, flap).
#   GODOT --rendering-method gl_compatibility --path . res://scenes/tools/gale_flight_capture.tscn
# Windowed (3D needs a GPU). Output: captures/renders/<biome>/
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

var mgr
var grid
var board: Node2D
var _birds: Array = []
var _heroes: Array = []

func _ready() -> void:
	get_window().size = Vector2i(1180, 1000)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(15))
	board = Node2D.new()
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

	for i in 6:
		var b: VisualUnit = EnemyFactory.create_by_type("gale_warden")
		b.set_level(9)
		_add(b, Vector2i(1 + i + (i / 3), 1 + (i % 2)), false)
		_birds.append(b)
	var spots := {UnitBase.UnitClass.RIOT: Vector2i(2, 6), UnitBase.UnitClass.CROSS: Vector2i(5, 6),
		UnitBase.UnitClass.SABLE: Vector2i(1, 8), UnitBase.UnitClass.NEMI: Vector2i(4, 8),
		UnitBase.UnitClass.EMBER: Vector2i(7, 8)}
	for cls in spots:
		var h: VisualUnit = UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
		h.can_be_dragged = false
		h.set_level(7)
		_add(h, spots[cls], true)
		_heroes.append(h)
	await get_tree().create_timer(0.8).timeout
	mgr.start_battle()

	var flight: Array = []; var close: Array = []
	await _wait(1.5)
	for k in 8:
		await _wait(0.5)
		var pair: Array = await _shot(_birds[2])
		flight.append(pair[0]); close.append(pair[1])
	_sheet(flight, 4, "_gale_flight.png")
	_sheet(close, 8, "_gale_flight_closeup.png")
	_report("flight")

	# Force a death: the bird nearest Sable is shot down BY Sable.
	var sable: UnitBase = _heroes[2]
	var victim: UnitBase = null
	for b in _birds:
		if b.current_hp > 0 and (victim == null or mgr._unit_dist(b, sable) < mgr._unit_dist(victim, sable)):
			victim = b
	victim.take_damage(victim.current_hp + 99999, UnitBase.Element.NORMAL, sable, true)
	var hunt: Array = []; var mark_close: Array = []
	for k in 8:
		await _wait(0.45)
		var pair: Array = await _shot(sable)
		hunt.append(pair[0]); mark_close.append(pair[1])
	_sheet(hunt, 4, "_gale_hunt.png")
	_sheet(mark_close, 8, "_gale_hunt_closeup.png")
	_report("hunt")
	get_tree().quit(0)

func _add(u: VisualUnit, c: Vector2i, player: bool) -> void:
	u.is_player_unit = player
	u.battle_manager = mgr
	board.add_child(u)
	grid.place_unit(u, c)
	u.grid_position = c
	u.position = mgr._world_pos_for(u, c)
	# main_game's death duty: drop it from the rosters and the grid.
	u.died.connect(func():
		mgr.player_units.erase(u); mgr.enemy_units.erase(u); grid.purge_unit(u))

func _report(tag: String) -> void:
	var hunt: Dictionary = mgr.gale_hunt_info(false)
	var targets := {}
	for b in _birds:
		if is_instance_valid(b) and b.current_hp > 0 and b.target_unit:
			targets[b.target_unit.unit_name] = int(targets.get(b.target_unit.unit_name, 0)) + 1
	print("[%s] t=%.1f hunt=%s birds->%s heroes hp=%s" % [tag, mgr.battle_elapsed,
		("%s %.1fs" % [hunt["mark"].unit_name, hunt["t"]]) if not hunt.is_empty() else "none", targets,
		_heroes.map(func(h): return h.current_hp if is_instance_valid(h) else 0)])

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _shot(focus) -> Array:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var crop: Image = null
	if focus and is_instance_valid(focus):
		var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
		var c: Vector2 = focus.get_global_transform_with_canvas().origin * k
		var r := Rect2i(int(c.x - 120 * k), int(c.y - 150 * k), int(240 * k), int(240 * k))
		r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		crop = img.get_region(r)
		crop.resize(240, 240)
	img.resize(img.get_width() / 2, img.get_height() / 2)
	return [img, crop]

func _sheet(imgs: Array, cols: int, name: String) -> void:
	imgs = imgs.filter(func(i): return i != null)
	if imgs.is_empty():
		return
	var w: int = imgs[0].get_width(); var h: int = imgs[0].get_height()
	var rows: int = ceili(float(imgs.size()) / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, imgs[0].get_format())
	for k in imgs.size():
		sheet.blit_rect(imgs[k], Rect2i(0, 0, w, h), Vector2i((k % cols) * w, (k / cols) * h))
	var out: String = CapturePaths.out(name)
	sheet.save_png(out)
	print("wrote %s" % out)
