extends Node2D
const Paths = preload("res://scripts/tools/capture_paths.gd")
var family := "slime"
var pairs: Array = []

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--family="): family = arg.trim_prefix("--family=")
	get_window().size = Vector2i(1500, 900)
	get_window().content_scale_size = Vector2i(1500,900)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(Paths.cli_round(1))
	var forms := ["normal", "fire", "water", "earth", "air", "lightning"]
	if family not in ["slime","bear","windup_bot","orc","troll"]: forms = ["normal"]
	for i in range(forms.size()):
		var origin := Vector2((i % 2) * 750, (i / 2) * 300)
		var panel := ColorRect.new()
		panel.position = origin + Vector2(10,10)
		panel.size = Vector2(730,280)
		panel.color = Color(0.025,0.04,0.055,0.55)
		add_child(panel)
		var label := Label.new()
		label.text = family.capitalize() + " — " + str(forms[i]).capitalize()
		label.position = origin + Vector2(26,20)
		label.add_theme_font_size_override("font_size",28)
		add_child(label)
		var key: String = family + "_" + forms[i] if family in ["slime","bear","windup_bot","orc","troll"] else family
		var caster := EnemyFactory.create_by_type(key)
		var target := EnemyFactory.create_goblin()
		caster.position = origin + Vector2(190,200)
		target.position = origin + Vector2(565,200)
		for unit in [caster,target]:
			unit.scale = Vector2(2.0,2.0)
			add_child(unit)
			unit.set_process(false)
			if unit.health_bar: unit.health_bar.hide()
		assert(caster.model3d != null, "Missing 3D " + key)
		for clip in ["idle", "walk", "attack", "skill", "hurt", "death"]:
			assert(caster.model3d.has_animation(clip), key + " lacks " + clip)
		caster.model3d.face_direction(Vector2.RIGHT)
		var effect: Node2D
		match family:
			"slime":
				effect = SlimeVFX.new(); add_child(effect)
				effect.setup_point(SlimeVFX.Mode.GOO_SPLAT, target.position, caster.current_element, 88, 0.6)
			"bear":
				effect = BearVFX.new(); add_child(effect)
				effect.setup_point(BearVFX.Mode.SWIPE_IMPACT, target.position, 88, 0.6)
				effect._element = caster.current_element
			"windup_bot":
				effect = WindUpBotVFX.new(); add_child(effect)
				effect.setup_point(WindUpBotVFX.Mode.PUNCH_IMPACT, target.position, caster.current_element, 88, 0.6)
			"orc":
				effect = OrcVFX.new(); add_child(effect)
				effect.setup_point(OrcVFX.Mode.CRUSH_IMPACT, target.position, 88, 0.6)
				effect._element = caster.current_element
			"troll":
				effect = TrollVFX.new(); add_child(effect)
				effect.setup_point(TrollVFX.Mode.ENRAGE_CAST, caster.position, caster.current_element, 88, 0.6)
		if effect: effect.set_process(false)
		pairs.append({"caster":caster,"effect":effect})
	for i in range(6): await get_tree().process_frame
	var still := OS.get_cmdline_user_args().has("--still")
	for frame in range(1 if still else 40):
		var time := 0.5 if still else float(frame) / 24.0
		for pair in pairs:
			var player: AnimationPlayer = pair.caster.model3d._anim
			player.play("skill" if time < 0.8 else "idle",0.0)
			player.seek(time if time < 0.8 else time - 0.8,true)
			player.advance(0); player.pause()
			if pair.effect:
				pair.effect.visible = time >= 0.35 and time < 0.95
				pair.effect.elapsed = maxf(time - 0.35,0)
				pair.effect.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var file := "_%s_shared_forms.png" % family if still else "%s_shared_frames/frame_%03d.png" % [family,frame]
		assert(get_viewport().get_texture().get_image().save_png(Paths.out(file)) == OK)
	print("REGULAR_ENEMY_FORMS: ALL PASS ", family)
	get_tree().quit()
