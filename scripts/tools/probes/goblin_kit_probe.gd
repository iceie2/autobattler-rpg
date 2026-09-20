extends Node

var failures := 0
var grid: BattleGrid
var mgr: AutoBattleManager

func _ready() -> void:
	grid = BattleGrid.new()
	add_child(grid)
	mgr = AutoBattleManager.new()
	add_child(mgr)
	mgr.battle_grid = grid
	mgr.skill_effect_container = Node2D.new()
	mgr.projectile_container = Node2D.new()
	add_child(mgr.skill_effect_container)
	add_child(mgr.projectile_container)

	var goblins: Array[VisualUnit] = []
	for pos in [Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5)]:
		var g := EnemyFactory.create_goblin()
		g.is_player_unit = false
		add_child(g)
		grid.place_unit(g, pos)
		g.grid_position = pos
		g.position = grid.grid_to_world(pos)
		goblins.append(g)
	var dummy := UnitFactory.create_unit(UnitBase.UnitClass.RIOT, UnitBase.Element.NORMAL, true)
	dummy.max_hp = 50000
	dummy.current_hp = 50000
	dummy.movement_speed = 0
	add_child(dummy)
	grid.place_unit(dummy, Vector2i(4, 4))
	dummy.grid_position = Vector2i(4, 4)
	dummy.position = grid.grid_to_world(dummy.grid_position)

	mgr.start_battle()
	mgr.paused = true
	for g in goblins:
		mgr._tick_passive(g, mgr.player_units, mgr.enemy_units, 0.1)
		_check(is_equal_approx(float(g.get_meta("mob_aspd_bonus", -1.0)), 0.12),
			"three-Goblin pack should grant +12%%, got %s" % g.get_meta("mob_aspd_bonus", -1.0))
	_check(goblins[0].ultimate_charge_max == 0, "Goblin must not inherit an ultimate")
	_check(goblins[0].skill_description.contains("200% ATK"), "Shank description must match 2.0 coefficient")

	var caster := goblins[1]
	var before := dummy.current_hp
	mgr._use_skill(caster, mgr.player_units, mgr.enemy_units)
	mgr._tick_global_effects(0.49)
	_check(dummy.current_hp == before, "Shank dealt damage before contact")
	mgr._tick_global_effects(0.02)
	_check(dummy.current_hp < before, "Shank did not deal damage on contact")
	_check(caster.damage_dealt == before - dummy.current_hp, "Shank damage meter must credit actual HP loss")

	# A second cast interrupted during anticipation must not land.
	before = dummy.current_hp
	mgr._use_skill(caster, mgr.player_units, mgr.enemy_units)
	caster.stun_time = 1.0
	mgr._tick_global_effects(0.51)
	_check(dummy.current_hp == before, "stunned Shank should cancel")

	if failures == 0:
		print("GOBLIN_KIT_PROBE: ALL PASS")
		get_tree().quit(0)
	else:
		print("GOBLIN_KIT_PROBE: %d FAIL" % failures)
		get_tree().quit(1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("GOBLIN_KIT_PROBE FAIL: " + message)
