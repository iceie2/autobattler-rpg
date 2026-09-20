extends Node
# Isolated Coral Husk kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/coral_husk_kit_probe.tscn

var _fail: Array = []

func _check(c: bool, m: String) -> void:
	if not c: _fail.append(m)

func _fresh() -> Dictionary:
	var grid := BattleGrid.new(); var mgr := AutoBattleManager.new(); var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null); mgr.skill_effect_container = fx
	return {"grid": grid, "mgr": mgr}

func _mk(mgr, grid, u, cell: Vector2i, player: bool):
	add_child(u); u.battle_manager = mgr; u.is_player_unit = player
	assert(grid.place_unit(u, cell)); u.grid_position = cell
	return u

func _ready() -> void:
	_test_ultimate()
	_test_calcify()
	_test_slow_tide()
	_test_three_fictions_stay_separate()
	if _fail.is_empty():
		print("CORAL_HUSK_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("CORAL_HUSK_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ultimate() -> void:
	var h := EnemyFactory.create_by_type("coral_husk"); add_child(h)
	_check(h.ultimate_charge_max == 0,
		"Coral Husk still inherits an ultimate pool (%d)" % h.ultimate_charge_max)
	_check(bool(h.get_meta("coral_husk", false)), "coral_husk marker meta missing")

func _test_calcify() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var h = _mk(mgr, s["grid"], EnemyFactory.create_by_type("coral_husk"), Vector2i(3, 2), false)
	mgr.enemy_units = [h]; mgr.player_units = []
	var want: int = int(float(h.max_hp) * 0.25)
	var before: int = mgr.skill_effect_container.get_child_count()
	mgr._use_skill(h, mgr.player_units, mgr.enemy_units)
	_check(h.current_shield == want,
		"Calcify shield is %d, the shared boneshield gives 25%% of %d = %d"
			% [h.current_shield, h.max_hp, want])
	_check(mgr.skill_effect_container.get_child_count() > before,
		"Calcify spawned no visual")

# Same +5%/3s ramp as the Wind-Up Bot's Overclock, its own fiction and visual.
func _test_slow_tide() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var h = _mk(mgr, s["grid"], EnemyFactory.create_by_type("coral_husk"), Vector2i(3, 2), false)
	mgr.enemy_units = [h]; mgr.player_units = []
	h.set_meta("oc_time", 0.0)
	mgr._tick_passive(h, mgr.player_units, mgr.enemy_units, 0.0)
	_check(mgr._slow_tide_vfx.is_empty(), "a fresh Coral Husk already shows a risen tide")
	h.set_meta("oc_time", 15.0)
	mgr._tick_passive(h, mgr.player_units, mgr.enemy_units, 0.0)
	_check(absf(float(h.get_meta("oc_bonus", 0.0)) - 0.25) < 0.001,
		"at 15s the ramp is %.3f, expected +25%% (+5%% every 3s)"
			% float(h.get_meta("oc_bonus", 0.0)))
	_check(mgr._slow_tide_vfx.size() == 1, "a rising Slow Tide has no readout")
	var mid: float = mgr._slow_tide_vfx.values()[0].tide
	h.set_meta("oc_time", 30.0)
	mgr._tick_passive(h, mgr.player_units, mgr.enemy_units, 0.0)
	_check(absf(float(h.get_meta("oc_bonus", 0.0)) - 0.50) < 0.001,
		"the ramp did not cap at +50%% (%.3f)" % float(h.get_meta("oc_bonus", 0.0)))
	_check(mgr._slow_tide_vfx.values()[0].tide > mid,
		"the tide visual did not rise as the ramp climbed (%.2f then %.2f)"
			% [mid, mgr._slow_tide_vfx.values()[0].tide])

# THREE mobs now ride windup_overclock with three different fictions. Each must
# use its own readout and none may bleed into another.
func _test_three_fictions_stay_separate() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var husk = _mk(mgr, s["grid"], EnemyFactory.create_by_type("coral_husk"), Vector2i(1, 1), false)
	var bot = _mk(mgr, s["grid"], EnemyFactory.create_by_type("windup_bot_normal"), Vector2i(3, 1), false)
	var giant = _mk(mgr, s["grid"], EnemyFactory.create_by_type("storm_giant"), Vector2i(5, 1), false)
	mgr.enemy_units = [husk, bot, giant]; mgr.player_units = []
	for u in [husk, bot, giant]:
		u.set_meta("oc_time", 20.0)
		mgr._tick_passive(u, mgr.player_units, mgr.enemy_units, 0.0)
	_check(mgr._slow_tide_vfx.size() == 1,
		"expected exactly 1 Slow Tide readout, found %d" % mgr._slow_tide_vfx.size())
	_check(mgr._windup_oc_vfx.size() == 1,
		"expected exactly 1 clockwork Overclock badge, found %d" % mgr._windup_oc_vfx.size())
	_check(mgr._gathering_vfx.size() == 1,
		"expected exactly 1 Gathering Storm readout, found %d" % mgr._gathering_vfx.size())
	# And the three markers must be mutually exclusive.
	_check(not bool(bot.get_meta("coral_husk", false)), "the Wind-Up Bot was marked as a Coral Husk")
	_check(not bool(giant.get_meta("coral_husk", false)), "the Storm Giant was marked as a Coral Husk")
	_check(not bool(husk.get_meta("windup_bot", false)), "the Coral Husk was marked as a Wind-Up Bot")
	_check(not bool(husk.get_meta("storm_giant", false)), "the Coral Husk was marked as a Storm Giant")
