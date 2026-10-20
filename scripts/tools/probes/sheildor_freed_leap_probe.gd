extends Node2D

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func fighter(mgr: AutoBattleManager, grid: BattleGrid, cell: Vector2i) -> UnitBase:
	var unit := UnitBase.new()
	unit.unit_class = UnitBase.UnitClass.SHEILDOR
	unit.is_player_unit = true
	unit.max_hp = 1000; unit.current_hp = 1000
	unit.grid_position = cell
	add_child(unit)
	unit.battle_manager = mgr
	unit.position = mgr._world_pos_for(unit, cell)
	check(grid.place_unit(unit, cell), "fixture placement succeeds")
	return unit

func _ready() -> void:
	var grid := BattleGrid.new()
	var mgr := AutoBattleManager.new()
	add_child(grid); add_child(mgr)
	mgr.initialize(grid, null)
	var caster := fighter(mgr, grid, Vector2i(2, 6))
	var target := fighter(mgr, grid, Vector2i(5, 6))
	mgr._sheildor_guardian_leap(caster, [caster, target], [])
	grid.purge_unit(target); target.free()
	mgr._tick_sheildor_leaps(0.1)
	check(mgr._sheildor_leaps.is_empty() and not caster.get_meta("sheildor_leaping"), "freed target during tell cancels safely and releases caster")
	target = fighter(mgr, grid, Vector2i(5, 6))
	mgr._sheildor_guardian_leap(caster, [caster, target], [])
	grid.purge_unit(caster); caster.free()
	mgr._tick_sheildor_leaps(0.1)
	check(mgr._sheildor_leaps.is_empty(), "freed caster during tell removes pending leap safely")
	caster = fighter(mgr, grid, Vector2i(2, 6))
	mgr._sheildor_guardian_leap(caster, [caster, target], [])
	mgr._tick_sheildor_leaps(AutoBattleManager.SHEILDOR_LEAP_TELL + 0.01)
	check(mgr._sheildor_leaps[0]["state"] == "travel", "live leap enters travel")
	grid.purge_unit(target); target.free()
	mgr._tick_sheildor_leaps(AutoBattleManager.SHEILDOR_LEAP_TRAVEL + 0.01)
	mgr._tick_sheildor_leaps(AutoBattleManager.SHEILDOR_LEAP_LAND_HOLD + 0.01)
	check(mgr._sheildor_leaps.is_empty() and caster.current_shield > 0 and not caster.get_meta("sheildor_leaping"), "target freed in flight still allows safe landing and self protection")
	check(grid.get_unit_at(caster.grid_position) == caster, "landing retains grid registration")
	target = fighter(mgr, grid, Vector2i(7, 6))
	caster.current_shield = 0
	mgr._sheildor_guardian_leap(caster, [caster, target], [])
	mgr._tick_sheildor_leaps(AutoBattleManager.SHEILDOR_LEAP_TELL + 0.01)
	mgr._tick_sheildor_leaps(AutoBattleManager.SHEILDOR_LEAP_TRAVEL + 0.01)
	mgr._tick_sheildor_leaps(AutoBattleManager.SHEILDOR_LEAP_LAND_HOLD + 0.01)
	check(caster.current_shield > 0 and target.current_shield > 0, "live leap still protects both units")
	mgr._sheildor_guardian_leap(caster, [caster, target], [])
	grid.purge_unit(caster); caster.free()
	mgr._finish_sheildor_leap(mgr._sheildor_leaps[0])
	check(mgr._sheildor_leaps.is_empty(), "direct finish tolerates a freed caster")
	for message in failures: print("FAIL: ", message)
	print("SHEILDOR_FREED_LEAP_PROBE: ", "ALL PASS" if failures.is_empty() else str(failures.size()) + " FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)
