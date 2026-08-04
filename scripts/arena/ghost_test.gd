extends Node
# Regression test for the "dead heroes fight on as invisible ghosts" bug
# (2026-07-24). Deliberately wires deaths the way main_game USED to: the death
# handler only touches the grid, never the manager's own roster arrays. That is
# the worst case — it proves AutoBattleManager purges corpses by itself and no
# longer depends on VisualUnit.die() calling queue_free().
#
#   godot --headless --fixed-fps 30 res://scenes/ghost_test.tscn

var grid: BattleGrid
var mgr: AutoBattleManager
var units_root: Node2D

func _ready() -> void:
	await get_tree().process_frame
	var failures: Array[String] = []

	grid = BattleGrid.new()
	add_child(grid)
	units_root = Node2D.new()
	add_child(units_root)
	mgr = AutoBattleManager.new()
	add_child(mgr)
	mgr.initialize(grid, null)
	mgr.skill_effect_container = units_root
	mgr.projectile_container = units_root

	# One doomed hero vs a heavy enemy pack.
	var hero: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.NEMI, UnitBase.Element.NORMAL, true)
	_wire(hero)
	hero.grid_position = Vector2i(4, grid.grid_height - 1)
	grid.place_unit(hero, hero.grid_position)
	hero.position = grid.grid_to_world(hero.grid_position)

	for i in range(4):
		var e: VisualUnit = EnemyFactory.create_by_type("orc_earth")
		e.set_level(9)
		_wire(e)
		e.grid_position = Vector2i(3 + i, 1)
		grid.place_unit(e, e.grid_position)
		e.position = grid.grid_to_world(e.grid_position)

	mgr.start_battle()

	var elapsed := 0.0
	while mgr.battle_active and elapsed < 60.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time() * mgr.time_scale
		# INVARIANT: no unit in the manager's live rosters may be at 0 HP.
		for u in mgr.player_units + mgr.enemy_units:
			if u and is_instance_valid(u) and u.current_hp <= 0:
				failures.append("GHOST: %s is at 0 HP but still in the battle roster" % u.unit_name)
				mgr.battle_active = false
				break

	if mgr.battle_active:
		failures.append("STALL: battle never ended (%.1fs) — a corpse kept player_units non-empty" % elapsed)
	if not mgr.player_units.is_empty():
		failures.append("player_units not empty after the hero died: %d left" % mgr.player_units.size())
	# The hero node must still EXIST (parked for the round-end revival)…
	if not is_instance_valid(hero):
		failures.append("hero node was freed — round-end revival would have nothing to revive")
	else:
		# The death animation (and the fade tween that parks the node) is still
		# in flight when the last hero falls — the battle ends the same frame.
		# Give it a beat before asserting the node was parked.
		for _i in range(60):
			await get_tree().process_frame
		# …invisible, at 0 HP, and out of the fight.
		if hero.visible:
			failures.append("parked hero is still visible")
		if hero in mgr.player_units:
			failures.append("parked hero is still in mgr.player_units")
		# …and revive() must bring it fully back.
		hero.revive(0.10)
		var want: int = maxi(1, int(round(float(hero.max_hp) * 0.10)))
		if hero.current_hp != want:
			failures.append("revive(0.10) gave %d HP, expected %d" % [hero.current_hp, want])
		if not hero.visible:
			failures.append("revived hero is still invisible")
		if hero._is_dying:
			failures.append("revived hero still flagged _is_dying")

	if failures.is_empty():
		print("GHOST_TEST: ALL PASS (battle resolved in %.1fs)" % elapsed)
	else:
		for f in failures:
			print("GHOST_TEST FAIL: %s" % f)
	get_tree().quit(0 if failures.is_empty() else 1)

func _wire(u: VisualUnit) -> void:
	units_root.add_child(u)
	u.battle_manager = mgr
	# Deliberately NOT erasing from mgr.player_units/enemy_units — see header.
	u.died.connect(func():
		if grid and is_instance_valid(u):
			grid.remove_unit(u.grid_position))
