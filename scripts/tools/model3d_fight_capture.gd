extends Node
## Records a real battle to a PNG frame sequence, for reviewing a 3D pawn's
## PRESENTATION in motion rather than in a still.
##
##   GODOT --path . res://scenes/tools/model3d_fight_capture.tscn -- --hero=CROSS
##   → user://_fight_capture/frame_0000.png ...   (assemble with ffmpeg)
##
## board_look.gd already stages the real board with 3D and 2D heroes on it, but
## it saves ONE frame — and the things this task changed (facing on a diagonal
## move, the flip at the moment a unit reverses, the contact shadow tracking the
## feet) only exist across time. A still cannot show a unit turning its back,
## which is the exact defect being fixed.
##
## Windowed on purpose: --headless uses the dummy renderer and every 3D
## character's SubViewport comes back empty.

const OUT_DIR := "user://_fight_capture"
const FPS := 20
const SECONDS := 10.0
## Two 3D pawns plus 2D heroes, so the frames show the new presentation against
## the sprite art it is supposed to match.
const MIX := ["CROSS", "NEMI", "CROSS", "SABLE", "RUSH"]

var mg = null
var _suppress_modals := false

## Modals are hidden in _process, which runs BEFORE the frame is drawn. Doing it
## after frame_post_draw (the obvious place, next to the grab) is one frame too
## late: the modal is already in the image being saved.
func _process(_d: float) -> void:
	if not _suppress_modals or mg == null:
		return
	if mg._level_up_screen and mg._level_up_screen.visible:
		mg._level_up_screen.hide()
	if mg._relic_screen and mg._relic_screen.visible:
		mg._relic_screen.hide()

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	Engine.max_fps = FPS

	var hero := "CROSS"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hero="):
			hero = a.substr(7).to_upper()

	mg = (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	for i in range(30):
		await get_tree().process_frame

	mg.max_player_units = 40
	var keys: PackedStringArray = UnitBase.UnitClass.keys()
	for cname in MIX:
		var cls: int = keys.find(hero if cname == "CROSS" else cname)
		if cls < 0:
			push_error("unknown hero '%s'" % cname)
			continue
		mg._recruit_hero(cls, UnitBase.Element.NORMAL, UnitFactory.generate_recruit_rolls())
		await get_tree().process_frame

	# Enough goblins that the fight actually fills SECONDS. Six level-3 ones
	# were wiped in ~4s and the capture spent its second half behind the
	# between-round level-up modal instead of on the board.
	for i in range(14):
		mg._place_enemy(EnemyFactory.create_goblin(400 if hero == "STITCH" else 40), false)

	# Same modal suppression board_look.gd does — a relic offer covers the board.
	if mg._relic_screen and mg._relic_screen.visible:
		mg._relic_screen.hide()
	mg.close_shop()
	if mg.difficulty_panel:
		mg.difficulty_panel.set_panel_visible(false)
	mg._pending_round_reward = {}
	for i in range(30):
		await get_tree().process_frame

	_suppress_modals = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if mg.auto_battle_manager:
		mg.auto_battle_manager.start_battle()

	var total: int = int((3.0 if hero == "STITCH" else SECONDS) * FPS)
	for i in range(total):
		# Stitch showcase: trigger the real gameplay entry points after units have
		# spread out, then rupture the visible network a moment later.
		if hero == "STITCH" and i == 10:
			var stitch = mg.auto_battle_manager.player_units.filter(
				func(u): return u.unit_class == UnitBase.UnitClass.STITCH).front()
			mg.auto_battle_manager._stitch_link(stitch, mg.auto_battle_manager.enemy_units)
		if hero == "STITCH" and i == 30:
			var stitch = mg.auto_battle_manager.player_units.filter(
				func(u): return u.unit_class == UnitBase.UnitClass.STITCH).front()
			mg.auto_battle_manager._stitch_unravel(stitch, mg.auto_battle_manager.enemy_units)
		# Bloodhound showcase: his ult charges too slowly to land inside a 10s
		# capture on its own, so arm Pounce on each copy, staggered — the leap,
		# the landing chop and the swipes all need to be on camera.
		if hero == "BLOODHOUND" and (i == 30 or i == 110):
			var hounds: Array = mg.auto_battle_manager.player_units.filter(
				func(u): return is_instance_valid(u) and u.current_hp > 0 \
					and u.unit_class == UnitBase.UnitClass.BLOODHOUND)
			if hounds.size() > (0 if i == 30 else 1):
				hounds[0 if i == 30 else 1].ultimate_ready = true
		await RenderingServer.frame_post_draw
		# Any between-round modal covers the whole board; this capture is about
		# what the pawns look like, so keep them off screen for its duration.
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(
			"%s/frame_%04d.png" % [OUT_DIR, i]))
	print("wrote %d frames to %s" % [total, OUT_DIR])
	get_tree().quit(0)
