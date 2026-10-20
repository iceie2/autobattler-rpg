extends Node2D
# Groundbreaker / Stuck Club, on the REAL board (owner 2026-10-06). Drives the
# real manager loop (AutoBattleManager._begin_groundbreaker/_tick_groundbreakers)
# on the round-5 grass board with the 3D giant and heroes standing in his block,
# and writes four moments as a 2x2 sheet: mid-windup (telegraph), contact
# (impact + knockback), mid-stuck (Exposed badge), mid-yank.
#   GODOT --rendering-method gl_compatibility --path . res://scenes/tools/groundbreaker_capture.tscn
# Windowed (3D needs a GPU). Output: captures/renders/<biome>/_groundbreaker.png
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

var mgr
var grid
var _shots: Array = []
var _crops: Array = []
var _giant = null
var _ticking := false

func _ready() -> void:
	get_window().size = Vector2i(1180, 1000)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(5))
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

	var giant: VisualUnit = EnemyFactory.create_hill_giant()
	giant.battle_manager = mgr
	board.add_child(giant)
	_giant = giant
	_put(giant, Vector2i(3, 2))                     # south block = cols 2..5, rows 4..5
	var heroes: Array = []
	var spots := {UnitBase.UnitClass.RIOT: Vector2i(3, 4), UnitBase.UnitClass.BOUNCER: Vector2i(5, 5),
		UnitBase.UnitClass.SHAUNA: Vector2i(4, 8)}  # Shauna stands back, out of the block
	for cls in spots:
		var h: VisualUnit = UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
		h.can_be_dragged = false
		h.battle_manager = mgr
		board.add_child(h)
		_put(h, spots[cls])
		heroes.append(h)
	mgr.enemy_units = [giant]
	mgr.player_units = heroes
	await get_tree().create_timer(0.8).timeout

	giant.set_meta("gb_swings", AutoBattleManager.GB_SWINGS)
	giant.target_unit = heroes[0]
	mgr._use_skill(giant, heroes, [giant])
	_ticking = true
	await _wait(AutoBattleManager.GB_WINDUP * 0.75); await _shot()          # 1 windup
	await _wait(AutoBattleManager.GB_WINDUP * 0.25 + 0.12); await _shot()   # 2 contact
	print("after impact: giant armor %d / MR %d (base %d / %d), exposed %.2fs" % [giant.effective_armor(),
		giant.effective_magic_resist(), giant.resistance, giant.magic_resist, giant.exposed_time])
	await _wait(AutoBattleManager.GB_STUCK * 0.45); await _shot()           # 3 stuck
	await _wait(AutoBattleManager.GB_STUCK * 0.55 + AutoBattleManager.GB_YANK * 0.4); await _shot()  # 4 yank
	print("in yank: giant armor %d / MR %d, exposed %.2fs" % [giant.effective_armor(), giant.effective_magic_resist(),
		giant.exposed_time])

	var w: int = _shots[0].get_width()
	var h2: int = _shots[0].get_height()
	var sheet := Image.create(w * 2, h2 * 2, false, _shots[0].get_format())
	for k in _shots.size():
		sheet.blit_rect(_shots[k], Rect2i(0, 0, w, h2), Vector2i((k % 2) * w, (k / 2) * h2))
	var out: String = CapturePaths.out("_groundbreaker.png")
	sheet.save_png(out)
	var strip := Image.create(400 * _crops.size(), 400, false, _crops[0].get_format())
	for k in _crops.size():
		strip.blit_rect(_crops[k], Rect2i(0, 0, 400, 400), Vector2i(k * 400, 0))
	strip.save_png(CapturePaths.out("_groundbreaker_closeup.png"))
	print("wrote %s" % out)
	get_tree().quit(0)

func _process(delta: float) -> void:
	if _ticking:
		mgr._tick_groundbreakers(delta)
		for u in mgr.player_units + mgr.enemy_units:
			mgr._tick_statuses(u, delta)

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	# Close-up of the giant (pose check) before the sheet downscale.
	var k: float = float(img.get_width()) / get_viewport().get_visible_rect().size.x
	var c: Vector2 = _giant.get_global_transform_with_canvas().origin * k
	var crop: Image = img.get_region(Rect2i(int(c.x - 210 * k), int(c.y - 170 * k), int(420 * k), int(420 * k)))
	crop.resize(400, 400)
	_crops.append(crop)
	img.resize(img.get_width() / 2, img.get_height() / 2)
	_shots.append(img)

func _put(u, c: Vector2i) -> void:
	grid.place_unit(u, c)
	u.grid_position = c
	u.position = mgr._world_pos_for(u, c)
