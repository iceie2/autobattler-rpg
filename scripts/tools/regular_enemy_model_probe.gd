extends Node
const SINGLE := ["goblin","goblin_archer","skeleton","rat","ogre","minotaur","gargoyle","stone_golem","crystal_crab","root_walker","fire_giant","hellhound","ember_phoenix","storm_giant","storm_crow","sky_wyvern","tidepool_horror","harpy","coral_husk"]
const SIX := ["goblin_shaman","orc","slime","lizard","bear","troll","windup_bot"]

func _ready() -> void:
	var keys: Array = SINGLE.duplicate()
	for family in SIX:
		var shared := ""
		for form in ["normal","fire","water","earth","air","lightning"]:
			var key: String = family + "_" + form
			var path: String = VisualUnit.MONSTER_MODEL_PATHS.get(key,"")
			assert(path != "", "Missing shared form " + key)
			if shared == "": shared = path
			assert(path == shared,"Multiple paid bodies in " + family)
			keys.append(key)
	for key in keys:
		var unit := EnemyFactory.create_by_type(key)
		var stats := [unit.max_hp,unit.attack_damage,unit.magic_power,unit.resistance,unit.magic_resist,unit.attack_speed,unit.skill_cooldown_max]
		add_child(unit)
		unit.set_process(false)
		assert(unit.model3d != null,"2D fallback: " + key)
		assert(stats == [unit.max_hp,unit.attack_damage,unit.magic_power,unit.resistance,unit.magic_resist,unit.attack_speed,unit.skill_cooldown_max],"Art changed stats: " + key)
		for clip in ["idle","walk","attack","hurt","death"]:
			assert(unit.model3d.has_animation(clip),key + " lacks " + clip)
		assert(unit.model3d._model_height > 0.1,"Broken camera bounds: " + key)
		if unit._regular_art_family() != "":
			assert(unit.model3d.has_animation("skill"),key + " lacks skill")
			assert(is_equal_approx(unit.combat_action_duration("attack"),0.3),"Art slowed attack: " + key)
			assert(is_equal_approx(unit.combat_action_duration("skill"),0.45),"Art slowed skill: " + key)
		unit.free()
	print("REGULAR_ENEMY_MODEL_PROBE: ALL PASS families=26 forms=61 shared_bodies=7")
	get_tree().quit()
