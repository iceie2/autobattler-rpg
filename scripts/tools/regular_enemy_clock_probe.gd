extends Node
const Roster = preload("res://scripts/tools/regular_enemy_model_probe.gd")

func _ready() -> void:
	var manager := AutoBattleManager.new()
	add_child(manager)
	manager.battle_active = true
	var target := EnemyFactory.create_goblin()
	add_child(target)
	target.set_process(false)
	target.position = Vector2(100,0)
	var keys: Array = Roster.SINGLE.duplicate()
	for family in Roster.SIX: keys.append(family + "_fire")
	var tested := 0
	for key in keys:
		var unit := EnemyFactory.create_by_type(key)
		add_child(unit)
		unit.set_process(false)
		unit.battle_manager = manager
		if unit._regular_art_family() == "":
			unit.free()
			continue
		manager.paused = false
		manager.time_scale = 1.0
		unit.play_skill_attack(target)
		unit._update_model3d_animation()
		var speed: float = unit.model3d._anim.speed_scale
		assert(speed > 0,"Stopped skill " + key)
		manager.paused = true
		unit._update_model3d_animation()
		assert(is_zero_approx(unit.model3d._anim.speed_scale),"Skill ignored pause " + key)
		manager.paused = false
		manager.time_scale = 2.0
		unit._update_model3d_animation()
		assert(is_equal_approx(unit.model3d._anim.speed_scale,speed*2),"Skill ignored battle pace " + key)
		assert(is_equal_approx(unit.combat_action_duration("skill"),0.45),"Clip changed recovery " + key)
		tested += 1
		unit.free()
	print("REGULAR_ENEMY_CLOCK_PROBE: ALL PASS families=",tested," pause/pace/recovery")
	get_tree().quit()
