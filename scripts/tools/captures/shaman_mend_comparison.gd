extends Node2D
const Paths = preload("res://scripts/tools/capture_paths.gd")
var pairs: Array = []

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(Paths.cli_round(1))
	var names := ["normal", "fire", "water", "earth", "air", "lightning"]
	for i in range(names.size()):
		var origin := Vector2((i % 2) * 960, (i / 2) * 360)
		var panel := ColorRect.new()
		panel.color = Color(0.025, 0.04, 0.055, 0.54)
		panel.position = origin + Vector2(12, 12)
		panel.size = Vector2(936, 336)
		add_child(panel)
		var label := Label.new()
		label.text = names[i].capitalize() + " — Mend"
		label.position = origin + Vector2(35, 25)
		label.add_theme_font_size_override("font_size", 36)
		add_child(label)
		var caster := EnemyFactory.create_by_type("goblin_shaman_" + names[i])
		var ally := EnemyFactory.create_goblin()
		caster.position = origin + Vector2(190, 255)
		ally.position = origin + Vector2(730, 255)
		for unit in [caster, ally]:
			add_child(unit)
			unit.set_process(false)
			if unit.health_bar: unit.health_bar.hide()
		caster.model3d.play("skill", false)
		caster.model3d.face_direction(Vector2.RIGHT)
		ally.model3d.play("idle")
		var link := GoblinShamanVFX.new()
		add_child(link)
		link.setup_mend(caster, ally, caster.current_element, AutoBattleManager.SHAMAN_MEND_CONTACT)
		link.global_position = caster.global_position
		link.set_process(false)
		var impact := GoblinShamanVFX.new()
		add_child(impact)
		impact.setup_impact(ally.global_position, caster.current_element)
		impact.set_process(false)
		pairs.append({"caster": caster, "link": link, "impact": impact})
	for i in range(6): await get_tree().process_frame
	# Sample the actual engine model and VFX at battle-time coordinates. Slow
	# playback in the resulting review GIF exposes the 0.42-second contact beat.
	for frame in range(40):
		var time := float(frame) / 30.0
		for pair in pairs:
			var player: AnimationPlayer = pair.caster.model3d._anim
			if time < 0.84:
				player.play("skill", 0.0)
				player.seek(time / 0.84, true)
			else:
				player.play("idle", 0.0)
				player.seek(time - 0.84, true)
			player.advance(0.0)
			player.pause()
			pair.link.visible = time < 0.42
			pair.link.elapsed = time
			pair.link.queue_redraw()
			pair.impact.visible = time >= 0.42 and time < 0.84
			pair.impact.elapsed = maxf(0.0, time - 0.42)
			pair.impact.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = Paths.out("shaman_mend_frames/frame_%03d.png" % frame)
		assert(get_viewport().get_texture().get_image().save_png(path) == OK)
	print("SHAMAN_MEND_COMPARISON: ALL PASS")
	get_tree().quit()
