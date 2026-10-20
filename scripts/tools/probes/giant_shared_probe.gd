extends Node

func _ready() -> void:
	var director := WaveDirector.new()
	var elite := director.create_enemy_for_entry({"type": "hill_giant", "level": 1}, 5)
	assert(elite.current_element == UnitBase.Element.FIRE and elite.skill_name == "Groundbreaker")
	elite.free()
	var earth := director.create_enemy_for_entry({"type": "hill_giant", "heavy": true, "level": 1}, 31)
	assert(earth.current_element == UnitBase.Element.EARTH and earth.skill_name == "Boulder Smash")
	earth.free()
	var manager := AutoBattleManager.new()
	add_child(manager)
	manager.set_process(false)
	manager.battle_active = true
	var path := ""
	for elem in [UnitBase.Element.NORMAL, UnitBase.Element.FIRE, UnitBase.Element.WATER,
			UnitBase.Element.EARTH, UnitBase.Element.AIR, UnitBase.Element.LIGHTNING]:
		var u := EnemyFactory.create_hill_giant()
		u.current_element = elem
		u.battle_manager = manager
		add_child(u)
		u.set_process(false)
		assert(u.model3d != null)
		if path == "": path = u.model3d.model_path
		assert(u.model3d.model_path == path)
		assert(u.model3d.pbr_material_overrides.Material_0.albedo_texture.resource_path.ends_with("giant_%s_albedo.png" % HillGiantVFX.element_name(elem)))
		for clip in ["slam", "stuck", "yank", "attack"]:
			assert(u.model3d.has_animation(clip))
			var duration: float = {"slam": AutoBattleManager.GB_WINDUP, "stuck": AutoBattleManager.GB_STUCK, "yank": AutoBattleManager.GB_YANK, "attack": u.model3d.animation_length("attack")}[clip]
			u.play_giant_timed(clip, duration, "")
			for speed in [0.8, 1.6, 3.2]:
				manager.time_scale = speed
				u._sync_giant_clock()
				assert(is_equal_approx(u.model3d._anim.speed_scale, u.model3d.animation_length(clip) * speed / duration))
				manager.paused = true
				u._sync_giant_clock()
				assert(u.model3d._anim.speed_scale == 0.0)
				manager.paused = false
			var fx := HillGiantVFX.new()
			add_child(fx)
			fx.set_clock(manager)
			fx.setup_gb(HillGiantVFX.Mode.GB_IMPACT, Vector2.ZERO, [], 10.0, 120.0, elem)
			fx._process(0.1)
			assert(is_equal_approx(fx.elapsed, 0.32))
			manager.paused = true
			fx._process(0.1)
			assert(is_equal_approx(fx.elapsed, 0.32))
			manager.paused = false
			fx.free()
			# The actual AnimationPlayer freezes mid-phase, then resumes.
			manager.paused = true
			u._sync_giant_clock()
			var held: float = u.model3d._anim.current_animation_position
			for frame in 3: await get_tree().process_frame
			assert(is_equal_approx(held, u.model3d._anim.current_animation_position))
			manager.paused = false
			u._sync_giant_clock()
			for frame in 3: await get_tree().process_frame
			assert(u.model3d._anim.current_animation_position > held)
		u.cancel_giant_action()
		assert(u.model3d._current == "idle" and not u.model3d.is_oneshot_playing())
		u.free()
	for unit in [EnemyFactory.create_fire_giant(), EnemyFactory.create_storm_giant()]:
		add_child(unit)
		assert(unit.model3d != null and unit.model3d.model_path == path)
		assert(unit.skill_name in ["Molten Smash", "Thunderclap"])
		unit.free()
	print("GIANT_SHARED_PROBE: ALL PASS (six materials, shared geometry, wave-5 Fire, Earth demotion, unchanged Fire/Storm kits, phase clocks and pause)")
	get_tree().quit()
