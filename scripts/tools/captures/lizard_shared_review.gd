extends Node2D
const Paths = preload("res://scripts/tools/capture_paths.gd")
var pairs: Array = []

func _ready() -> void:
	get_window().size = Vector2i(1920,1080)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(Paths.cli_round(1))
	var animated := not OS.get_cmdline_user_args().has("--still")
	var names := ["normal","fire","water","earth","air","lightning"]
	for i in range(names.size()):
		var origin := Vector2((i % 2) * 960,(i / 2) * 360)
		var panel := ColorRect.new()
		panel.position = origin + Vector2(12,12)
		panel.size = Vector2(936,336)
		panel.color = Color(0.025,0.04,0.055,0.54)
		add_child(panel)
		var label := Label.new()
		label.text = names[i].capitalize() + " — Precision Shot"
		label.position = origin + Vector2(30,20)
		label.add_theme_font_size_override("font_size",32)
		add_child(label)
		var caster := EnemyFactory.create_by_type("lizard_" + names[i])
		var target := EnemyFactory.create_goblin()
		caster.position = origin + Vector2(190,260)
		target.position = origin + Vector2(730,260)
		for unit in [caster,target]:
			add_child(unit)
			unit.set_process(false)
			if unit.health_bar: unit.health_bar.hide()
		assert(caster.model3d != null)
		for clip in ["idle","walk","attack","aim","skill","hurt","death"]:
			assert(caster.model3d.has_animation(clip))
		caster.model3d.face_direction(Vector2.RIGHT)
		var aim := LizardVFX.new()
		add_child(aim)
		aim.setup_aim(caster,AutoBattleManager.LIZARD_AIM_TIME)
		aim.global_position = caster.position
		var row := PackedVector2Array([Vector2(-185,-30),Vector2(185,-30),Vector2(185,30),Vector2(-185,30)])
		var warn := LizardVFX.new()
		add_child(warn)
		warn.setup_row(LizardVFX.Mode.ROW_WARNING,target.position,row,AutoBattleManager.LIZARD_AIM_TIME,caster.current_element)
		var impact := LizardVFX.new()
		add_child(impact)
		impact.setup_row(LizardVFX.Mode.ROW_IMPACT,target.position,row,0.42,caster.current_element)
		var bolt := Projectile.new()
		bolt.setup(caster.position,target.position,88,caster.current_element)
		bolt.is_lizard_bolt = true
		add_child(bolt)
		for effect in [aim,warn,impact,bolt]: effect.set_process(false)
		pairs.append({"caster":caster,"target":target,"aim":aim,"warn":warn,"impact":impact,"bolt":bolt})
	for i in range(6): await get_tree().process_frame
	for frame in range(50 if animated else 1):
		var time := float(frame) / 24.0 if animated else 0.55
		for pair in pairs:
			var player: AnimationPlayer = pair.caster.model3d._anim
			if time < 0.85:
				player.play("aim",0.0)
				player.seek(time / 0.85 * pair.caster.model3d.animation_length("aim"),true)
			elif time < 1.35:
				player.play("skill",0.0)
				player.seek(time-0.85,true)
			else:
				player.play("idle",0.0)
				player.seek(time-1.35,true)
			player.advance(0.0)
			player.pause()
			for key in ["aim","warn"]:
				pair[key].visible = time < 0.85
				pair[key].elapsed = time
				pair[key].queue_redraw()
			pair.bolt.visible = time >= 0.85 and time < 1.1
			pair.bolt.global_position = pair.caster.position.lerp(pair.target.position,clampf((time-0.85)/0.25,0,1))
			pair.bolt._sprite_anim_t = time
			pair.bolt.queue_redraw()
			pair.impact.visible = time >= 1.1 and time < 1.52
			pair.impact.elapsed = maxf(time-1.1,0)
			pair.impact.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = Paths.out("lizard_precision_frames/frame_%03d.png" % frame if animated else "_lizard_shared_six_forms.png")
		assert(get_viewport().get_texture().get_image().save_png(path) == OK)
	print("LIZARD_SHARED_REVIEW: ALL PASS")
	get_tree().quit()
