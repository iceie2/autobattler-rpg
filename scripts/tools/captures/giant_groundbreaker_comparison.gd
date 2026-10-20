extends Node2D
const Paths = preload("res://scripts/tools/capture_paths.gd")
var forms: Array = []

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(Paths.cli_round(5))
	var elements := [UnitBase.Element.NORMAL, UnitBase.Element.FIRE, UnitBase.Element.WATER,
		UnitBase.Element.EARTH, UnitBase.Element.AIR, UnitBase.Element.LIGHTNING]
	for i in 6:
		var origin := Vector2((i % 2) * 960, (i / 2) * 360)
		var panel := ColorRect.new()
		panel.position = origin + Vector2(12, 12)
		panel.size = Vector2(936, 336)
		panel.color = Color(0.04, 0.055, 0.045, 0.85)
		add_child(panel)
		var label := Label.new()
		label.text = HillGiantVFX.element_name(elements[i]).capitalize() + " — Groundbreaker visual preview"
		label.position = origin + Vector2(24, 8)
		label.add_theme_font_size_override("font_size", 30)
		add_child(label)
		var phase := Label.new()
		phase.position = origin + Vector2(620, 58)
		phase.add_theme_font_size_override("font_size", 30)
		add_child(phase)
		var unit := EnemyFactory.create_hill_giant()
		unit.current_element = elements[i]
		unit.position = origin + Vector2(390, 220)
		unit.scale = Vector2(0.8, 0.8)
		add_child(unit)
		unit.set_process(false)
		if unit.health_bar: unit.health_bar.hide()
		unit.model3d.face_direction(Vector2.RIGHT)
		var at := origin + Vector2(490, 277)
		var quads: Array = []
		for row in 2:
			for col in 4:
				var p := at + Vector2((col - 1.5) * 48, (row - 0.5) * 23)
				quads.append(PackedVector2Array([p + Vector2(-24,-12), p + Vector2(24,-12), p + Vector2(24,12), p + Vector2(-24,12)]))
		var effects: Array = []
		for kind in [HillGiantVFX.Mode.GB_WARNING, HillGiantVFX.Mode.GB_IMPACT, HillGiantVFX.Mode.GB_PUFF, HillGiantVFX.Mode.GB_YANK]:
			var fx := HillGiantVFX.new()
			add_child(fx)
			var life: float = {HillGiantVFX.Mode.GB_WARNING: AutoBattleManager.GB_WINDUP,
				HillGiantVFX.Mode.GB_IMPACT: AutoBattleManager.GB_STUCK + AutoBattleManager.GB_YANK,
				HillGiantVFX.Mode.GB_PUFF: 0.45, HillGiantVFX.Mode.GB_YANK: 0.6}[kind]
			fx.setup_gb(kind, at, quads, life, 96.0, elements[i])
			fx.set_process(false)
			effects.append(fx)
		forms.append({"unit": unit, "effects": effects, "phase": phase})
	for i in 6: await get_tree().process_frame
	var wind := AutoBattleManager.GB_WINDUP
	var stuck := AutoBattleManager.GB_STUCK
	var yank := AutoBattleManager.GB_YANK
	for frame in range(ceil((wind + stuck + yank + 0.65) * 24.0)):
		var time := float(frame) / 24.0
		for form in forms:
			var player: AnimationPlayer = form.unit.model3d._anim
			var clip := "slam" if time < wind else ("stuck" if time < wind + stuck else ("yank" if time < wind + stuck + yank else "idle"))
			var local: float = time if clip == "slam" else (time - wind if clip == "stuck" else time - wind - stuck)
			var duration: float = wind if clip == "slam" else (stuck if clip == "stuck" else yank)
			player.play(clip, 0.0)
			player.seek(local / duration * form.unit.model3d.animation_length(clip) if clip != "idle" else local, true)
			player.advance(0.0)
			player.pause()
			form.phase.text = {"slam": "WINDUP → SLAM", "stuck": "IMPACT / STUCK · HEAVE", "yank": "YANK FREE", "idle": "RECOVERED"}[clip]
			var fx: Array = form.effects
			fx[0].visible = time < wind
			fx[0].elapsed = time
			fx[1].visible = time >= wind and time < wind + stuck + yank
			fx[1].elapsed = maxf(0, time - wind)
			var puff_time := fposmod(maxf(0, time - wind), AutoBattleManager.GB_PUFF_EVERY)
			fx[2].visible = clip == "stuck" and time - wind >= AutoBattleManager.GB_PUFF_EVERY and puff_time < 0.45
			fx[2].elapsed = puff_time
			fx[3].visible = time >= wind + stuck and time < wind + stuck + 0.6
			fx[3].elapsed = maxf(0, time - wind - stuck)
			for effect in fx: effect.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(Paths.out("giant_groundbreaker_frames/frame_%03d.png" % frame)) == OK)
	print("GIANT_GROUNDBREAKER_COMPARISON: ALL PASS")
	get_tree().quit()
