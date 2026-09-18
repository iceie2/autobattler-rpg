extends Node

func _ready() -> void:
	var mgr := AutoBattleManager.new()
	var fx_root := Node2D.new()
	add_child(mgr)
	add_child(fx_root)
	mgr.skill_effect_container = fx_root
	var shaman := EnemyFactory.create_goblin_shaman_fire()
	var ally := EnemyFactory.create_goblin()
	add_child(shaman)
	add_child(ally)
	shaman.battle_manager = mgr
	ally.battle_manager = mgr
	shaman.grid_position = Vector2i(2, 2)
	ally.grid_position = Vector2i(4, 2)
	mgr.enemy_units = [shaman, ally]
	assert(shaman.current_hp == shaman.max_hp, "shaman must spawn at full HP")
	assert(not mgr._skill_trigger_ready(shaman, []), "Mend must not cast on a full-health formation")
	ally.current_hp = ally.max_hp - 40
	assert(mgr._skill_trigger_ready(shaman, []), "Mend must detect a wounded ally")
	var before := ally.current_hp
	mgr._use_mob_skill(shaman, "shaman_mend", [], mgr.enemy_units)
	assert(ally.current_hp == before, "Mend must not heal before its visual reaches the target")
	mgr._tick_shaman_mends(AutoBattleManager.SHAMAN_MEND_CONTACT + 0.01)
	var expected := mini(ally.max_hp, before + int(float(shaman.magic_power) * 1.5))
	assert(ally.current_hp == expected, "Mend formula/timing mismatch")
	assert(shaman.combat_healing_done == expected - before, "Mend must credit actual healing")
	print("GOBLIN_SHAMAN_KIT_PROBE: ALL PASS")
	get_tree().quit(0)
