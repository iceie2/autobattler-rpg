extends Node

func _ready() -> void:
	var manager := AutoBattleManager.new()
	add_child(manager)
	var model_path := ""
	for form in ["normal","fire","water","earth","air","lightning"]:
		var u := EnemyFactory.create_by_type("lizard_" + form)
		add_child(u)
		u.battle_manager = manager
		assert(u.model3d != null)
		if model_path == "": model_path = u.model3d.model_path
		assert(u.model3d.model_path == model_path)
		for clip in ["idle","walk","attack","aim","skill","hurt","death"]:
			assert(u.model3d.has_animation(clip))
		var stats := [u.max_hp,u.attack_damage,u.attack_speed,u.resistance,u.hp_regen]
		var player: AnimationPlayer = u.model3d._anim
		var skeleton: Skeleton3D = u.model3d._model.find_child("Skeleton3D",true,false)
		var jaw := skeleton.find_bone("Jaw")
		var tail := skeleton.find_bone("Tail3")
		assert(jaw >= 0 and tail >= 0, "Must have creature jaw and tail rig")
		player.play("idle",0.0)
		player.seek(0,true)
		player.advance(0.0)
		var tail_start := skeleton.get_bone_pose_rotation(tail)
		player.seek(0.5,true)
		player.advance(0.0)
		assert(tail_start.angle_to(skeleton.get_bone_pose_rotation(tail)) > 0.01, "Tail should sway")
		var target := EnemyFactory.create_goblin()
		add_child(target)
		target.position = Vector2(200,0)
		for speed in [0.8,1.6,3.2]:
			manager.time_scale = speed
			u.play_lizard_aim(target)
			assert(is_equal_approx(player.speed_scale,u.model3d.animation_length("aim") * speed / AutoBattleManager.LIZARD_AIM_TIME))
			manager.battle_active = true
			manager.paused = true
			u._update_model3d_animation()
			assert(is_zero_approx(player.speed_scale))
			manager.paused = false
			manager.battle_active = false
		var fx := LizardVFX.new()
		add_child(fx)
		fx.setup_aim(u,AutoBattleManager.LIZARD_AIM_TIME)
		manager.time_scale = 1.6
		fx._process(0.1)
		assert(is_equal_approx(fx.elapsed,0.16))
		manager.battle_active = true
		manager.paused = true
		fx._process(0.1)
		assert(is_equal_approx(fx.elapsed,0.16))
		manager.paused = false
		manager.battle_active = false
		assert(stats == [u.max_hp,u.attack_damage,u.attack_speed,u.resistance,u.hp_regen], "Visual playback must not change stats")
		fx.free()
		target.free()
		u.free()
	print("LIZARD_MODEL_PROBE: ALL PASS (six forms, shared body, tail, clips, battle speeds, pause, unchanged stats)")
	get_tree().quit()
