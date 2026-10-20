extends Node

func _ready() -> void:
	var forms := ["normal", "fire", "water", "earth", "air", "lightning"]
	var manager := AutoBattleManager.new()
	add_child(manager)
	var body_path := ""
	for form in forms:
		var u := EnemyFactory.create_by_type("goblin_shaman_" + form)
		add_child(u)
		u.battle_manager = manager
		assert(u.model3d != null)
		if body_path == "": body_path = u.model3d.model_path
		assert(u.model3d.model_path == body_path, "Element must reuse shared geometry")
		for clip in ["idle", "walk", "attack", "skill", "hurt", "death"]:
			assert(u.model3d.has_animation(clip), "Missing Shaman animation")
		var settings: Dictionary = u.model3d.pbr_material_overrides["Material_1"]
		assert(settings.albedo_texture.resource_path.ends_with("shaman_" + form + "_albedo.png"))
		var skeleton: Skeleton3D = u.model3d._model.find_child("Skeleton3D", true, false)
		var arm_bone := skeleton.find_bone("RightArm")
		var player: AnimationPlayer = u.model3d._anim
		player.play("skill", 0.0)
		player.seek(0.0, true)
		player.advance(0.0)
		var start := skeleton.get_bone_pose_rotation(arm_bone)
		player.seek(0.5, true)
		player.advance(0.0)
		assert(start.angle_to(skeleton.get_bone_pose_rotation(arm_bone)) > 0.1, "Cast must visibly move")
		player.seek(1.0, true)
		player.advance(0.0)
		assert(start.angle_to(skeleton.get_bone_pose_rotation(arm_bone)) < 0.02, "Cast must return to idle")
		var ally := EnemyFactory.create_goblin()
		add_child(ally)
		ally.position = Vector2(100, 0)
		for speed in [0.8, 1.6, 3.2]:
			manager.time_scale = speed
			u.play_skill_attack(ally)
			assert(is_equal_approx(player.speed_scale, u.model3d.animation_length("skill") * speed / (AutoBattleManager.SHAMAN_MEND_CONTACT * 2.0)))
		var fx := GoblinShamanVFX.new()
		add_child(fx)
		fx.setup_mend(u, ally, u.current_element, AutoBattleManager.SHAMAN_MEND_CONTACT)
		manager.time_scale = 1.6
		fx._process(0.1)
		assert(is_equal_approx(fx.elapsed, 0.16), "VFX must follow combat speed")
		manager.battle_active = true
		manager.paused = true
		fx._process(0.1)
		assert(is_equal_approx(fx.elapsed, 0.16), "Paused VFX must freeze")
		manager.paused = false
		manager.battle_active = false
		fx.free()
		ally.free()
		u.free()
	print("SHAMAN_SHARED_PROBE: ALL PASS (six palettes, shared mesh, cast motion/return, speeds, paused VFX)")
	get_tree().quit()
