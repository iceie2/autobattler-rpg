extends Node2D
# Visual check for the Drowned Maw's Abyssal Breach (2026-10-02): runs the REAL
# dive state machine on a real BattleGrid over the water BackgroundLayer and
# saves four moments side by side -- sinking, stalking (lure + shadow only),
# breaching, and the 4x4 pulse -- to captures/renders/water/_maw_breach.png.
# Windowed (3D units need a real GPU):
#   GODOT --path . res://scenes/tools/maw_breach_capture.tscn
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

var mgr
var grid
var boss
var players: Array = []
var _shots: Array = []

func _ready() -> void:
	get_window().size = Vector2i(1180, 1000)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(21)
	# Like the real game: board + units live under an OFFSET parent while the
	# effects layer does not -- the case that hid the boil's coordinate bug.
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

	boss = EnemyFactory.create_drowned_maw(14)
	board.add_child(boss)
	_put(boss, Vector2i(3, 0))
	var spots := {UnitBase.UnitClass.BLOODHOUND: Vector2i(4, 6), UnitBase.UnitClass.BOUNCER: Vector2i(5, 6),
		UnitBase.UnitClass.NEMI: Vector2i(3, 5), UnitBase.UnitClass.SABLE: Vector2i(1, 8)}
	for cls in spots:
		var h: VisualUnit = UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
		h.can_be_dragged = false
		board.add_child(h)
		_put(h, spots[cls])
		players.append(h)
	players[0].damage_dealt = 5000
	mgr.enemy_units = [boss]
	mgr.player_units = players
	await get_tree().create_timer(0.8).timeout

	boss.current_hp = int(boss.max_hp * 0.69)
	var sink: float = mgr.MAW_DIVE_SINK
	var under: float = sink + mgr.MAW_DIVE_STALK
	var plan := [0.15, 0.35, 0.55, 0.75, 0.95, sink + 1.0, under - 0.2,
		under + 0.08, under + 0.18, under + 0.28, under + 0.38, under + 0.5, under + 0.62, under + 0.85]
	var t := 0.0
	var i := 0
	while i < plan.size():
		await get_tree().process_frame
		var d: float = get_process_delta_time()
		t += d
		mgr._maw_dive_tick(boss, players, d)
		if t >= plan[i]:
			await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			img.resize(img.get_width() / 2, img.get_height() / 2)
			var crop: Image = img
			_shots.append(crop)
			print("shot %d at %.2fs state=%s" % [i, t, boss.get_meta("maw_dive_state", "")])
			i += 1
	var cols := 7
	var fw: int = _shots[0].get_width()
	var fh: int = _shots[0].get_height()
	var sheet := Image.create(fw * cols, fh * 2, false, _shots[0].get_format())
	for k in _shots.size():
		sheet.blit_rect(_shots[k], Rect2i(0, 0, fw, fh), Vector2i((k % cols) * fw, (k / cols) * fh))
	var out: String = CapturePaths.out("_maw_breach.png")
	sheet.save_png(out)
	print("wrote %s" % out)
	get_tree().quit(0)

func _put(u, c: Vector2i) -> void:
	grid.place_unit(u, c)
	u.grid_position = c
	u.position = mgr._world_pos_for(u, c)
