extends Node2D
# Visual + wiring check for 3D Khagan (wave 10, 2026-10-02). Runs the REAL
# phase code on a real board (normal biome) and saves three moments side by
# side to captures/renders/normal/_khagan_phases.png:
#   1. mounted   -- khagan_phase1 (octopus riding the crab), 2x2
#   2. dismount  -- EnemyFactory.advance_khagan_phase(): stats/grid swap, the
#                   dismount beat, rebuild_sprite() onto khagan_phase2 (1x1)
#   3. possessed -- AutoBattleManager.start_khagan_possession(): the phase-2
#                   octopus CLINGING to the #2 damage dealer's head
# Prints which visual path each stage ended up on, so a silent 2D fallback is
# visible. Windowed (3D units need a real GPU):
#   GODOT --path . res://scenes/tools/khagan_capture.tscn
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

var mgr
var grid
var _shots: Array = []

func _ready() -> void:
	get_window().size = Vector2i(1180, 1000)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(10)
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

	var boss: VisualUnit = EnemyFactory.create_by_type("khagan")
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
	heroes[0].damage_dealt = 900       # #1
	heroes[1].damage_dealt = 600       # #2 -> the one Khagan seizes
	heroes[2].damage_dealt = 100
	mgr.enemy_units = [boss]
	mgr.player_units = heroes
	await get_tree().create_timer(0.8).timeout
	print("phase 1 visual: %s  canvas scale %s" % [_path(boss), boss.get_global_transform_with_canvas().get_scale()])
	# `-- --walkstrip`: 8 close-up frames of the mounted crab's walk cycle side
	# by side (gait review -- motion can't be judged from one still). Played as
	# the charge's scuttle, which is the walk clip at SCUTTLE_ANIM_SPEED.
	if "--walkstrip" in OS.get_cmdline_user_args():
		boss.set_meta("scuttle", true)
		await get_tree().create_timer(0.3).timeout
		var frames: Array = []
		for i in 8:
			await get_tree().create_timer(0.05).timeout
			await RenderingServer.frame_post_draw
			var full: Image = get_viewport().get_texture().get_image()
			var k: float = float(full.get_width()) / get_viewport().get_visible_rect().size.x
			var c: Vector2 = boss.get_global_transform_with_canvas().origin * k
			var fr: Image = full.get_region(Rect2i(int(c.x - 110 * k), int(c.y - 60 * k), int(220 * k), int(150 * k)))
			fr.resize(fr.get_width() * 2, fr.get_height() * 2, Image.INTERPOLATE_NEAREST)
			frames.append(fr)
		var fw: int = frames[0].get_width()
		var fh: int = frames[0].get_height()
		var strip := Image.create(fw * 4, fh * 2, false, frames[0].get_format())
		for i in frames.size():
			strip.blit_rect(frames[i], Rect2i(0, 0, fw, fh), Vector2i((i % 4) * fw, (i / 4) * fh))
		var outw: String = CapturePaths.out("_khagan_walkstrip.png")
		strip.save_png(outw)
		print("wrote %s" % outw)
		get_tree().quit(0)
		return
	# `-- --mounted`: just a close-up of the mounted body (tentacle wrap check).
	if "--mounted" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var full: Image = get_viewport().get_texture().get_image()
		var k: float = float(full.get_width()) / get_viewport().get_visible_rect().size.x
		var c: Vector2 = boss.get_global_transform_with_canvas().origin * k
		var crop: Image = full.get_region(Rect2i(int(c.x - 200 * k), int(c.y - 230 * k), int(400 * k), int(330 * k)))
		crop.resize(800, 660)
		var outm: String = CapturePaths.out("_khagan_mounted.png")
		crop.save_png(outm)
		print("wrote %s" % outm)
		get_tree().quit(0)
		return
	await _shot()

	# phase 1 -> 2, through the real code path
	boss.current_hp = 0
	var transformed: bool = EnemyFactory.advance_khagan_phase(boss)
	print("advance_khagan_phase -> %s, cell_size=%d" % [transformed, boss.cell_size])
	await get_tree().create_timer(1.4).timeout   # dismount beat + deferred sprite swap
	boss.position = mgr._world_pos_for(boss, boss.grid_position)
	print("phase 2 visual: %s" % _path(boss))
	await _shot()

	# phase 2 -> 3: possession of the #2 damage dealer
	mgr.start_khagan_possession(boss)
	boss.visible = false                         # its body dies for real here
	await get_tree().create_timer(1.2).timeout
	for h in heroes:
		print("  %s dmg=%d puppet=%s clinger=%s icon=%s" % [h.unit_name, h.damage_dealt,
			h.has_meta("khagan_puppet"),
			h.possession_model != null and h.possession_model.visible,
			h.possession_icon != null and h.possession_icon.visible])
	await _shot()

	var w: int = _shots[0].get_width()
	var h2: int = _shots[0].get_height()
	var sheet := Image.create(w * 3, h2, false, _shots[0].get_format())
	for k in _shots.size():
		sheet.blit_rect(_shots[k], Rect2i(0, 0, w, h2), Vector2i(k * w, 0))
	var out: String = CapturePaths.out("_khagan_phases.png")
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
