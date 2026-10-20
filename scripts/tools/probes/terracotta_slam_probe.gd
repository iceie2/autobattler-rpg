extends Node
# Terracotta Colossus probe (2026-09-30 owner design): "Weight of Stone" is a
# RANGED boulder throw that grows with stacked armour and is aimed at the hero
# who has eroded it most; Water/Air hits erode armour, other elements don't.
# Drives the REAL manager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/terracotta_slam_probe.tscn

var _fail: Array = []

func _check(c: bool, m: String) -> void:
	if not c: _fail.append(m)

func _hero(mgr, grid, cell: Vector2i):
	var h: VisualUnit = EnemyFactory.create_by_type("goblin")
	add_child(h); h.battle_manager = mgr; h.is_player_unit = true
	assert(grid.place_unit(h, cell)); h.grid_position = cell
	h.max_hp = 9999999; h.current_hp = 9999999
	return h

func _land(mgr) -> void:
	# windup, then the flight (clamped to <= 0.9s)
	mgr._tick_terracotta_slams(AutoBattleManager.TERRACOTTA_SLAM_WINDUP + 0.05)
	mgr._tick_terracotta_slams(1.0)

func _ready() -> void:
	var grid := BattleGrid.new(); var mgr := AutoBattleManager.new(); var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null); mgr.skill_effect_container = fx
	var tc: VisualUnit = EnemyFactory.create_by_type("terracotta_colossus")
	add_child(tc); tc.battle_manager = mgr; tc.is_player_unit = false
	assert(grid.place_unit(tc, Vector2i(3, 0))); tc.grid_position = Vector2i(3, 0)
	tc.max_hp = 9999999; tc.current_hp = 9999999
	var near = _hero(mgr, grid, Vector2i(3, 2))     # adjacent
	var far = _hero(mgr, grid, Vector2i(7, 8))      # far side of the board
	mgr.enemy_units = [tc]; mgr.player_units = [near, far]

	_check(tc.skill_name == "Weight of Stone" and str(tc.get_meta("mob_skill", "")) == "terracotta_slam",
		"the Colossus has no Weight of Stone skill")
	_check(tc.skill_range >= 9, "it is a ranged skill but skill_range is only %d" % tc.skill_range)
	_check(mgr._skill_trigger_ready(tc, mgr.player_units), "throw not ready with heroes on the board")

	# Ranged: with nobody eroding it, it aims at the NEAREST hero...
	_check(mgr._terracotta_slam_target(tc, mgr.player_units) == near, "with no erosion it should target the nearest hero")
	# ...and the hero who erodes it most becomes the target, wherever they stand.
	tc.set_meta("terracotta_armor", 60.0)
	far.take_damage(1, UnitBase.Element.NORMAL, null)      # not a weakness
	tc.take_damage(1, UnitBase.Element.WATER, far)
	tc.take_damage(1, UnitBase.Element.AIR, far)
	tc.take_damage(1, UnitBase.Element.WATER, near)
	_check(mgr._terracotta_slam_target(tc, mgr.player_units) == far,
		"the hero with the most erosion hits (far, 2 vs 1) was not chosen")
	tc.take_damage(1, UnitBase.Element.AIR, near)
	tc.take_damage(1, UnitBase.Element.WATER, near)
	_check(mgr._terracotta_slam_target(tc, mgr.player_units) == near,
		"the target did not follow the eroder count once it changed (near 3 vs far 2)")
	# Non-weakness hits never count.
	var tally: Dictionary = tc.get_meta("tc_eroders", {})
	var before: int = int(tally.get(far.get_instance_id(), 0))
	tc.take_damage(1, UnitBase.Element.FIRE, far)
	_check(int(tc.get_meta("tc_eroders", {}).get(far.get_instance_id(), 0)) == before, "a Fire hit counted as a weakness hit")

	# Damage grows with stacked armour (aimed at `far`, across the board).
	tc.set_meta("tc_eroders", {far.get_instance_id(): 99})
	var dmg := {}
	for armor in [0.0, 160.0]:
		tc.set_meta("terracotta_armor", armor)
		far.current_hp = far.max_hp
		mgr._begin_terracotta_slam(tc, far)
		_check(bool(tc.get_meta("hill_giant_committed", false)), "no commit during the windup")
		_land(mgr)
		dmg[armor] = far.max_hp - far.current_hp
		_check(not bool(tc.get_meta("hill_giant_committed", true)), "commit flag stuck after the throw")
	_check(dmg[0.0] > 0, "the boulder at 0 armour did no damage (it should land across the board)")
	_check(dmg[160.0] > dmg[0.0] * 1.5, "throw at full armour (%d) is not clearly heavier than at none (%d)" % [dmg[160.0], dmg[0.0]])
	_check(near.current_hp == near.max_hp, "the boulder hit the wrong hero")

	# Erosion element rules, on the stack itself.
	tc.set_meta("terracotta_armor", 100.0)
	tc.take_damage(1, UnitBase.Element.FIRE, null)
	_check(is_equal_approx(float(tc.get_meta("terracotta_armor")), 100.0), "a Fire hit eroded the armour")
	tc.take_damage(1, UnitBase.Element.EARTH, null)
	_check(is_equal_approx(float(tc.get_meta("terracotta_armor")), 100.0), "its own element eroded it")
	tc.take_damage(1, UnitBase.Element.WATER, null)
	_check(is_equal_approx(float(tc.get_meta("terracotta_armor")), 100.0 - UnitBase.TERRACOTTA_ERODE_ARMOR), "a Water hit did not erode")
	tc.take_damage(1, UnitBase.Element.AIR, null)
	_check(is_equal_approx(float(tc.get_meta("terracotta_armor")), 100.0 - 2.0 * UnitBase.TERRACOTTA_ERODE_ARMOR), "an Air hit did not erode")
	tc.set_meta("terracotta_armor", 2.0)
	tc.take_damage(1, UnitBase.Element.WATER, null)
	_check(float(tc.get_meta("terracotta_armor")) >= 0.0, "erosion drove the stack negative")

	# Nothing to throw at.
	mgr.player_units = []
	_check(not mgr._skill_trigger_ready(tc, mgr.player_units), "throw ready with no heroes at all")

	if _fail.is_empty():
		print("TERRACOTTA_SLAM_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("TERRACOTTA_SLAM_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)
