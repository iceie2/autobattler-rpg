extends Node2D
## Renders a 3D-model hero on the real board next to 2D units, and drives it
## through the animation states VisualUnit actually triggers.
##
##   GODOT --path . res://scenes/tools/model3d_board_check.tscn
##   → user://_model3d_board.png
##
## Runs WINDOWED on purpose: --headless uses the dummy renderer and the
## SubViewport behind every 3D character would come back empty.
##
## This is the check that catches what the rig probe cannot — wrong on-board
## SIZE relative to the 2D roster, a character standing off its cell, a facing
## that points the wrong way down the board, or a one-shot that never settles
## back to idle.

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

## Heroes fight EVERY round 1-100, so unlike an enemy (which is gated to a few
## decades) a hero meets all six backdrops. Sweep them all:
##   for r in 1 11 21 31 41 51; do GODOT ... -- --hero=CROSS --round=$r; done
## Output lands in captures/renders/<biome>/_model3d_board_<hero>.png.
const DEFAULT_ROUND := 1
const ROW_Y := [190, 430, 660]

var _units: Array = []

func _ready() -> void:
	get_window().size = Vector2i(1180, 780)

	# The REAL board. This check's whole claim is "on the real board", but until
	# 2026-09-18 it rendered on the default clear colour — the same fault that
	# hid a contrast and a z-order bug in the enemy captures. A 3D hero lit and
	# scaled against empty space tells you nothing about whether it reads on
	# grass, sand, or the lightning decade's backdrop.
	var _round: int = CapturePaths.cli_round(DEFAULT_ROUND)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(_round)
	print("board check biome: ", CapturePaths.biome_of(_round), " (round ", _round, ")")
	await get_tree().process_frame

	# Row 1: the 3D hero in each state. Row 2: 2D heroes at the same scale, so a
	# size mismatch between the model and the existing roster is obvious.
	# WHICH hero is a command-line argument, defaulting to Bouncer only because
	# he was the reference conversion. It used to be hardcoded, which meant this
	# check always rendered Bouncer no matter which character you had just
	# converted — running it on Cross (2026-09-09) produced a clean-looking
	# board of the wrong hero.
	#     GODOT --path . res://scenes/tools/model3d_board_check.tscn -- --hero=CROSS
	var hero := UnitBase.UnitClass.BOUNCER
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hero="):
			var want := a.substr(7).to_upper()
			if UnitBase.UnitClass.has(want):
				hero = UnitBase.UnitClass[want]
			else:
				push_error("model3d_board_check: unknown hero '%s'" % want)
	print("board check hero: ", UnitBase.UnitClass.find_key(hero))

	# --monster=<sprite_folder> checks a converted ENEMY instead of a hero.
	# Enemies are built by EnemyFactory.create_by_type and identified by a
	# sprite_folder string, so neither UnitClass nor the hero path reaches them
	# — without this, a converted monster had no in-engine check at all.
	var monster := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--monster="):
			monster = a.substr(10)
	if monster != "":
		print("board check monster: ", monster)

	var states := ["idle", "walk", "attack", "hurt", "death"]
	for i in states.size():
		var u: VisualUnit = (_spawn_monster(monster, 140 + i * 210, ROW_Y[0])
				if monster != "" else _spawn(hero, 140 + i * 210, ROW_Y[0], true))
		if u:
			_units.append({"unit": u, "state": states[i]})

	var comparison := [UnitBase.UnitClass.NEMI, UnitBase.UnitClass.RUSH,
		UnitBase.UnitClass.SABLE, UnitBase.UnitClass.EMBER]
	for i in comparison.size():
		_spawn(comparison[i], 140 + i * 210, ROW_Y[1], true)

	# Enemy-side facing: the same model on the other team must turn to face back
	# down the board, not stay mirrored the player's way.
	if monster != "":
		_spawn_monster(monster, 140, ROW_Y[2])
	else:
		_spawn(hero, 140, ROW_Y[2], false)

	await get_tree().create_timer(0.6).timeout
	_drive_states()
	await get_tree().create_timer(0.9).timeout

	_report()
	_audit_roster()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	# Named per subject AND filed per biome, so a six-biome sweep leaves six
	# comparable files instead of overwriting one.
	var subject: String = monster if monster != "" else str(UnitBase.UnitClass.find_key(hero)).to_lower()
	var out_path: String = CapturePaths.out("_model3d_board_%s.png" % subject)
	img.save_png(out_path)
	print("\nwrote %s" % out_path)
	get_tree().quit(0)

func _spawn_monster(type: String, x: int, y: int) -> VisualUnit:
	var u: VisualUnit = EnemyFactory.create_by_type(type)
	if not u:
		push_error("could not create monster %s" % type)
		return null
	u.position = Vector2(x, y)
	u.can_be_dragged = false
	add_child(u)
	return u

func _spawn(cls: int, x: int, y: int, player: bool) -> VisualUnit:
	var u: VisualUnit = UnitFactory.create_unit(cls, UnitBase.Element.NORMAL, player)
	if not u:
		push_error("could not create unit class %d" % cls)
		return null
	u.position = Vector2(x, y)
	u.can_be_dragged = false
	add_child(u)
	return u

## Push each copy into a different animation state through the SAME entry points
## gameplay uses, so this exercises the real code path rather than the model API.
func _drive_states() -> void:
	for e in _units:
		var u: VisualUnit = e["unit"]
		match e["state"]:
			"walk":
				u.is_moving = true
				u.move_start_pos = Vector2.ZERO
				u.move_target_pos = Vector2(100, 0)
				u.last_move_direction = Vector2(1, 0)
			"attack":
				u._play_oneshot("attack")
			"hurt":
				u._play_oneshot("hurt")
			"death":
				u.current_hp = 0
				u.die()

## Spawns EVERY hero and reports which visual path each ended up on. This is the
## check that would have caught the walk_south crash: five heroes were silently
## losing their animations and falling back to static art, and nothing in the
## normal smoke tests spawns the whole roster.
func _audit_roster() -> void:
	print("\n=== hero visual-path audit ===")
	var keys: PackedStringArray = UnitBase.UnitClass.keys()
	var counts := {"3d": 0, "animated": 0, "static": 0, "none": 0}
	for cls in UnitBase.UnitClass.values():
		if not (VisualUnit.HERO_MODEL_PATHS.has(cls) or VisualUnit.HERO_SPRITE_PATHS.has(cls)):
			continue
		var u: VisualUnit = UnitFactory.create_unit(cls, UnitBase.Element.NORMAL, true)
		if not u:
			continue
		add_child(u)
		var kind := "none"
		var detail := ""
		if u.model3d:
			kind = "3d"
			detail = ",".join(u.model3d.get_animation_list())
		elif u.animated_sprite:
			kind = "animated"
			detail = ",".join(u.animated_sprite.sprite_frames.get_animation_names())
		elif u.plain_sprite:
			kind = "static"
		counts[kind] += 1
		if kind == "none":
			push_error("%s built NO visual at all" % keys[cls])
		print("  %-12s %-8s %s" % [keys[cls], kind, detail])
		u.queue_free()
	print("  totals: %s" % counts)

func _report() -> void:
	print("=== 3D board check ===")
	for e in _units:
		var u: VisualUnit = e["unit"]
		if not is_instance_valid(u):
			continue
		var m: Model3DSprite = u.model3d
		if not m:
			push_error("%s has no model3d — it fell back to 2D art" % u.unit_name)
			continue
		var spr := m.get_sprite()
		print("  %-8s model=%-12s sprite_scale=%.3f offset=%s clip=%s"
			% [e["state"], u.unit_name, spr.scale.x, spr.position, m._current])
		if u.unit_class == UnitBase.UnitClass.STITCH:
			for prop_name in ["Doll_Held", "Needle_Held", "Doll_Stowed", "Needle_Stowed"]:
				var prop := m._find_by_name(m._model, prop_name) as MeshInstance3D
				if prop:
					print("    %-14s visible=%s global=%s aabb=%s skin=%s skeleton=%s"
						% [prop_name, prop.is_visible_in_tree(), prop.global_position,
						prop.get_aabb(), prop.skin != null, prop.skeleton])
				else:
					push_error("Stitch prop missing after import: " + prop_name)
		if spr != u.plain_sprite:
			push_error("plain_sprite is not aimed at the model's sprite — "
				+ "the procedural animation layers will not reach it")
