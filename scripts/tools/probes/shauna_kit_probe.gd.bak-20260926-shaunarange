extends Node

# Shauna Kite regression probe (2026-09-25 user report: "after she does her
# ability she stops shooting"). Drives the REAL AutoBattleManager._process
# against an unkillable melee chaser. The bug: Kite's 1s cooldown was up again
# by the time she landed, and skills are checked before autos, so she chained
# Kite until her 400 MP ran dry and the empowered shot never fired.
#
# Asserts: never two Kites without a shot between them, every post-Kite shot is
# the empowered one, and she keeps a real fire rate while being chased.
#
# Run: godot --headless --fixed-fps 30 res://scenes/tools/shauna_kit_probe.tscn
# Add --verbose-log after `--` for the per-second state table.

var _failures: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _mk(mgr, grid, unit, cell: Vector2i, player: bool):
	add_child(unit)
	unit.battle_manager = mgr
	unit.is_player_unit = player
	assert(grid.place_unit(unit, cell))
	unit.grid_position = cell
	return unit

func _fresh() -> Dictionary:
	var grid := BattleGrid.new()
	var mgr := AutoBattleManager.new()
	var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null)
	mgr.skill_effect_container = fx
	return {"grid": grid, "mgr": mgr}

func _shauna(mgr, grid, cell: Vector2i):
	return _mk(mgr, grid, UnitFactory.create_unit(UnitBase.UnitClass.SHAUNA, UnitBase.Element.FIRE, true), cell, true)

func _foe(mgr, grid, type: String, cell: Vector2i, sh):
	var e = _mk(mgr, grid, EnemyFactory.create_by_type(type), cell, false)
	e.target_unit = sh
	return e

func _move(grid, unit, cell: Vector2i) -> void:
	grid.remove_unit(unit.grid_position)
	assert(grid.place_unit(unit, cell))
	unit.grid_position = cell

# A runtime error aborts a test function SILENTLY, skipping its later checks —
# so every test bumps this as its last line and _ready requires all of them.
var _completed := 0
const TEST_COUNT := 5

func _ready() -> void:
	await get_tree().process_frame
	_test_far_melee_ignored()
	_test_ranged_dodge_leaves_range()
	_test_corner_slides_out()
	_test_boxed_in_skips()
	await _test_chase()
	_check(_completed == TEST_COUNT, "only %d of %d tests ran to the end (runtime error?)" % [_completed, TEST_COUNT])
	if _failures.is_empty():
		print("SHAUNA_KIT_PROBE: ALL PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("FAIL: ", f)
		print("SHAUNA_KIT_PROBE: %d FAILURE(S)" % _failures.size())
		get_tree().quit(1)

# A melee attacker 4 tiles out is not a threat yet; at 2 tiles it is.
func _test_far_melee_ignored() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var grid = s["grid"]
	var sh = _shauna(mgr, grid, Vector2i(4, 7))
	var gob = _foe(mgr, grid, "goblin", Vector2i(4, 3), sh)
	_check(not mgr._skill_trigger_ready(sh, [gob]), "Kite fired at a melee enemy 4 tiles away")
	_move(grid, gob, Vector2i(4, 5))
	_check(mgr._skill_trigger_ready(sh, [gob]), "Kite did not fire at a melee enemy 2 tiles away")
	_completed += 1

# A shooter that can reach her triggers Kite, and the hop lands out of its range.
func _test_ranged_dodge_leaves_range() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var grid = s["grid"]
	var sh = _shauna(mgr, grid, Vector2i(4, 4))
	var arc = _foe(mgr, grid, "goblin_archer", Vector2i(4, 1), sh)   # range 4, 3 tiles away
	_check(mgr._skill_trigger_ready(sh, [arc]), "Kite ignored a ranged enemy that can hit her")
	var dest: Vector2i = mgr._best_retreat_cell(sh, arc)
	_check(dest != Vector2i(-1, -1) and mgr._rect_dist(dest, 1, arc.grid_position, 1) > arc.attack_range,
		"ranged dodge did not leave the shooter's range (landed %s)" % dest)
	# Out of its range entirely: not a threat.
	_move(grid, arc, Vector2i(4, 0))
	_move(grid, sh, Vector2i(4, 6))
	_check(not mgr._skill_trigger_ready(sh, [arc]), "Kite fired at a shooter that cannot reach her")
	_completed += 1

# Corner with the attacker on the diagonal: no hop gains distance, so before
# 2026-09-25 she never Kited. Now she slides to a roomier cell.
func _test_corner_slides_out() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var grid = s["grid"]
	var sh = _shauna(mgr, grid, Vector2i(0, 0))
	var gob = _foe(mgr, grid, "goblin", Vector2i(1, 1), sh)
	_check(mgr._skill_trigger_ready(sh, [gob]), "cornered Shauna still refuses to Kite")
	var dest: Vector2i = mgr._best_retreat_cell(sh, gob)
	_check(dest != Vector2i(-1, -1) and mgr._open_neighbor_count(dest) > mgr._open_neighbor_count(Vector2i(0, 0)),
		"corner escape did not reach a roomier cell (landed %s)" % dest)
	_check(dest.distance_to(gob.grid_position) >= Vector2i(0, 0).distance_to(gob.grid_position) - 0.01,
		"corner escape moved closer to the attacker (landed %s)" % dest)
	_completed += 1

# Walled in on every side: no cell to go to, so she fights instead.
func _test_boxed_in_skips() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var grid = s["grid"]
	var sh = _shauna(mgr, grid, Vector2i(0, 0))
	var gob = _foe(mgr, grid, "goblin", Vector2i(1, 1), sh)
	_mk(mgr, grid, EnemyFactory.create_by_type("goblin"), Vector2i(1, 0), false)
	_mk(mgr, grid, EnemyFactory.create_by_type("goblin"), Vector2i(0, 1), false)
	_check(not mgr._skill_trigger_ready(sh, [gob]), "fully boxed-in Shauna wasted a Kite")
	_completed += 1

# Real chase through _process: never two Kites without a shot between them.
func _test_chase() -> void:
	var verbose := "--verbose-log" in OS.get_cmdline_user_args()
	var s := _fresh(); var mgr = s["mgr"]; var grid = s["grid"]

	var sh = _mk(mgr, grid, UnitFactory.create_unit(UnitBase.UnitClass.SHAUNA, UnitBase.Element.FIRE, true), Vector2i(4, 7), true)
	var dummy = _mk(mgr, grid, EnemyFactory.create_by_type("goblin"), Vector2i(4, 3), false)
	dummy.max_hp = 999999; dummy.current_hp = 999999
	mgr.player_units = [sh]; mgr.enemy_units = [dummy]

	# Action sequence: "K" = Kite, "S" = shot, "B" = shot that consumed the boost.
	var seq: Array[String] = []
	var boosted_before := [false]
	mgr.unit_action.connect(func(u, kind):
		if u != sh:
			return
		if kind == "attack":
			seq.append("B" if boosted_before[0] and not sh.next_attack_boosted else "S")
		elif kind == "skill":
			seq.append("K"))

	mgr.start_battle()
	var dt := 1.0 / 30.0
	const SECONDS := 20
	for sec in range(SECONDS):
		for f in range(30):
			boosted_before[0] = sh.next_attack_boosted
			mgr._process(dt / mgr.time_scale)
			dummy.current_hp = dummy.max_hp
		if verbose:
			print("t=%2d mp=%d pos=%s dummy=%s atkcd=%.2f skcd=%.2f boosted=%s" % [
				sec + 1, sh.current_mana, sh.grid_position, dummy.grid_position,
				sh.attack_cooldown, sh.skill_cd_time, sh.next_attack_boosted])

	var seq_str := "".join(seq)
	print("sequence: ", seq_str)
	var kites := seq_str.count("K")
	var shots := seq_str.count("S") + seq_str.count("B")
	_check(kites >= 3, "setup: Kite fired only %d times, so the chase never engaged her" % kites)
	_check(not seq_str.contains("KK"), "two Kites with no shot between them (the stall): %s" % seq_str)
	for i in range(seq_str.length() - 1):
		if seq_str[i] == "K" and seq_str[i + 1] != "B":
			_check(false, "shot after a Kite at step %d was not the empowered one: %s" % [i + 1, seq_str])
			break
	# 0.9 attacks/sec: a Kite costs roughly one swing, so being chased should
	# still leave well over a third of her unhindered fire rate.
	_check(shots >= int(SECONDS * 0.9 * 0.4),
		"only %d shots in %ds while chased (unhindered ~%d)" % [shots, SECONDS, int(SECONDS * 0.9)])
	print("chase: %d kites, %d shots" % [kites, shots])
	_completed += 1
