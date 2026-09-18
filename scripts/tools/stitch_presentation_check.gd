extends Node2D
## Regression and native-size render for Stitch's doll-facing combat stance.
var failures: int = 0
var units: Array = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func spawn_at(x: float, y: float, caption: String) -> VisualUnit:
	var u: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.STITCH, UnitBase.Element.NORMAL, true)
	u.position = Vector2(x, y)
	add_child(u)
	u.set_process(false)
	u.set_physics_process(false)
	units.append(u)
	var label := Label.new()
	label.text = caption
	label.position = Vector2(x - 72, y + 105)
	add_child(label)
	return u

func _ready() -> void:
	get_window().size = Vector2i(1200, 650)
	get_window().content_scale_size = Vector2i(1200, 650)
	RenderingServer.set_default_clear_color(Color("27352e"))
	await get_tree().process_frame
	var u := spawn_at(100, 180, "Idle / ready")
	u._update_model3d_animation()
	var stance: float = u.model3d._pivot.rotation.y
	var target := Node2D.new()
	add_child(target)
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2(-1,-1), Vector2(1,-1)]:
		target.position = u.position + dir * 300
		u._on_attacked(target)
		check(is_equal_approx(u.model3d._pivot.rotation.y, stance), "Attack target changed casting angle")
		u.model3d._on_anim_finished("attack")
		u._update_model3d_animation()
		check(is_equal_approx(u.model3d._pivot.rotation.y, stance), "Idle snapped after attack")
	for dir in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		u.is_moving = true
		u.move_start_pos = Vector2.ZERO
		u.move_target_pos = dir * 100
		u.last_move_direction = dir
		u._update_model3d_animation()
		var expected: float = atan2(dir.x, dir.y) + deg_to_rad(u.model3d.clip_yaw_bias_deg.get("walk", 0.0))
		check(is_equal_approx(u.model3d._pivot.rotation.y, expected), "Walk did not follow travel")
	u.play_skill_oneshot()
	check(is_equal_approx(u.model3d._pivot.rotation.y, stance), "Skill retained walking angle")
	u.play_ult_oneshot()
	check(is_equal_approx(u.model3d._pivot.rotation.y, stance), "Ult retained walking angle")
	u.play_stitch_rupture_stab(0.3)
	check(is_equal_approx(u.model3d._pivot.rotation.y, stance), "Rupture retained walking angle")
	u.model3d._on_anim_finished("attack")
	u.is_moving = false
	u._update_model3d_animation()
	u.model3d._anim.seek(0.0, true)
	u.model3d._anim.pause()
	for i in range(5):
		var pawn := spawn_at(300 + 200 * i, 180, ["Ready", "Wind-up", "Stab", "Contact", "Recovery"][i])
		target.position = pawn.position + Vector2.UP * 300
		pawn._on_attacked(target)
		pawn.model3d._anim.seek([0.0,0.28,0.50,0.65,1.0][i], true)
		pawn.model3d._anim.pause()
	for i in range(4):
		var pawn := spawn_at(200 + 250 * i, 440, ["Walk north", "Walk east", "Link", "Unravel"][i])
		if i < 2:
			pawn.is_moving = true
			pawn.move_start_pos = Vector2.ZERO
			pawn.move_target_pos = Vector2(100, 100)
			pawn.last_move_direction = Vector2.UP if i == 0 else Vector2.RIGHT
			pawn._update_model3d_animation()
		elif i == 2:
			pawn.play_skill_oneshot()
		else:
			pawn.play_ult_oneshot()
		pawn.model3d._anim.seek(0.5, true)
		pawn.model3d._anim.pause()
	for pawn in units:
		var held: bool = pawn.model3d._current != "walk"
		check(pawn.model3d._weapon_nodes["Doll_Held"].visible == held, "Wrong teddy variant")
	if "--angle-review" in OS.get_cmdline_user_args():
		for i in range(6):
			units[i].model3d._pivot.rotation.y = deg_to_rad([0,30,90,150,180,210][i])
			units[i].model3d.play("attack")
			units[i].model3d._anim.seek(0.5, true)
			units[i].model3d._anim.pause()
	for i in range(5):
		await RenderingServer.frame_post_draw
	for i in range(units.size()):
		units[i].model3d._viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path("user://stitch_pose_%02d.png" % i))
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://stitch_presentation.png"))
	print("STITCH_PRESENTATION_MECHANICAL: ", "PASS" if failures == 0 else "FAIL", "; visual approval requires native-size review; screenshot: ", ProjectSettings.globalize_path("user://stitch_presentation.png"))
	get_tree().quit(failures)
