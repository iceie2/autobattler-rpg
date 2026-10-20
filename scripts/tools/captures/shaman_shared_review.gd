extends Node2D
const Paths = preload("res://scripts/tools/capture_paths.gd")

func _ready() -> void:
	get_window().size = Vector2i(1200, 780)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(Paths.cli_round(1))
	var forms := ["normal", "fire", "water", "earth", "air", "lightning"]
	for i in range(forms.size()):
		var label := Label.new()
		label.text = forms[i].capitalize()
		label.position = Vector2(100 + i * 185, 100)
		label.add_theme_font_size_override("font_size", 24)
		add_child(label)
		for row in range(3):
			var unit := EnemyFactory.create_by_type("goblin_shaman_" + forms[i])
			unit.position = Vector2(145 + i * 185, 270 + row * 200)
			add_child(unit)
			assert(unit.model3d != null, "Missing shared Shaman model")
			for clip in ["idle", "walk", "attack", "skill", "hurt", "death"]:
				assert(unit.model3d.has_animation(clip), "Missing clip: " + clip)
			if unit.health_bar: unit.health_bar.hide()
			unit.set_process(false)
			var clip: String = ["idle", "skill", "attack"][row]
			unit.model3d.play(clip, false)
			var player: AnimationPlayer = unit.model3d._anim
			player.seek(unit.model3d.animation_length(clip) * 0.5, true)
			player.advance(0.0)
			player.pause()
			if i == 0: print("REVIEW CLIP ", clip, " length ", unit.model3d.animation_length(clip), " current ", player.current_animation_position)
			var fx := GoblinShamanVFX.new()
			add_child(fx)
			if row == 0: fx.setup_aura(unit, unit.current_element, 55.0)
			else: fx.setup_impact(unit.position + Vector2(45, -25), unit.current_element, 1.0)
			fx.elapsed = 0.22
			fx.set_process(false)
	for i in range(6): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path: String = Paths.out("_shaman_shared_six_forms.png")
	assert(get_viewport().get_texture().get_image().save_png(path) == OK)
	print("SHAMAN_SHARED_REVIEW: ALL PASS ", path)
	get_tree().quit()
