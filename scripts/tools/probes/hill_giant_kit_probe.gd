extends Node

func _ready() -> void:
	var grid := BattleGrid.new()
	var mgr := AutoBattleManager.new()
	var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null)
	mgr.skill_effect_container = fx
	var giant := EnemyFactory.create_hill_giant()
	var near := EnemyFactory.create_goblin()
	var far := EnemyFactory.create_goblin()
	for u in [giant, near, far]:
		add_child(u); u.battle_manager = mgr
	near.is_player_unit = true; far.is_player_unit = true
	assert(grid.place_unit(giant, Vector2i(3, 1)))
	assert(grid.place_unit(near, Vector2i(5, 1))) # flush with the 2x2 body
	assert(grid.place_unit(far, Vector2i(6, 1)))
	giant.grid_position = Vector2i(3, 1)
	near.grid_position = Vector2i(5, 1)
	far.grid_position = Vector2i(6, 1)
	mgr.enemy_units = [giant]
	mgr.player_units = [near, far]
	assert(mgr._skill_trigger_ready(giant, mgr.player_units), "adjacent target must enable Boulder Smash")
	var near_before := near.current_hp
	var far_before := far.current_hp
	mgr._use_skill(giant, mgr.player_units, mgr.enemy_units)
	assert(near.current_hp == near_before, "Boulder Smash must wait for contact")
	mgr._tick_hill_giant_actions(AutoBattleManager.HILL_GIANT_SMASH_CONTACT + 0.01)
	assert(near.current_hp < near_before, "footprint-adjacent target was not hit")
	assert(far.current_hp == far_before, "target outside displayed footprint was hit")
	assert(giant.damage_dealt == near_before - near.current_hp, "smash damage accounting mismatch")
	print("HILL_GIANT_KIT_PROBE: ALL PASS")
	get_tree().quit(0)
