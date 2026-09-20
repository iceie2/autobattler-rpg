extends Node
# Isolated Minotaur kit probe, driving the REAL AutoBattleManager.
# Units are built via create_by_type so they carry the affinity profile waves
# actually spawn with (see the memory note — the bare create_X() skips it).
# Run: godot --headless --fixed-fps 30 res://scenes/tools/minotaur_kit_probe.tscn

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
	_test_inherits_gore_rush_fixes()
	_test_gore_rush_committed()
	_test_savage_charge()
	_test_neighbours_unchanged()
	if _fail.is_empty():
		print("MINOTAUR_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("MINOTAUR_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ultimate() -> void:
	var m := EnemyFactory.create_by_type("minotaur"); add_child(m)
	_check(m.ultimate_charge_max == 0,
		"Minotaur still inherits an ultimate pool (%d) — ~2.5 free Gore Rushes at 750 HP" % m.ultimate_charge_max)
	_check(bool(m.get_meta("minotaur", false)), "minotaur marker meta missing")
	_check(str(m.get_meta("mob_skill", "")) == "windup_punch",
		"Gore Rush no longer rides windup_punch — probe is stale")
	_check(str(m.get_meta("mob_passive", "")) == "bear_fury",
		"Savage Charge no longer rides bear_fury — probe is stale")

# It should get the shared path's range gate for free.
func _test_inherits_gore_rush_fixes() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var m = _mk(mgr, s["grid"], EnemyFactory.create_by_type("minotaur"), Vector2i(2, 2), false)
	var far = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(8, 2), true)
	mgr.enemy_units = [m]; mgr.player_units = [far]
	_check(not mgr._skill_trigger_ready(m, mgr.player_units),
		"Gore Rush triggered on a target 6 tiles away — it should inherit the melee gate")
	var near = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(3, 2), true)
	mgr.player_units = [near, far]
	_check(mgr._skill_trigger_ready(m, mgr.player_units), "Gore Rush did not fire on an adjacent target")

func _test_gore_rush_committed() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var m = _mk(mgr, s["grid"], EnemyFactory.create_by_type("minotaur"), Vector2i(2, 2), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(3, 2), true)
	v.max_hp = 9999; v.current_hp = 9999
	mgr.enemy_units = [m]; mgr.player_units = [v]
	var hp0: int = v.current_hp
	mgr._use_skill(m, mgr.player_units, mgr.enemy_units)
	_check(v.current_hp == hp0, "Gore Rush dealt damage before its contact frame")
	mgr._tick_windup_punches(AutoBattleManager.WINDUP_PUNCH_CONTACT + 0.01)
	var removed: int = hp0 - v.current_hp
	_check(removed > 0, "Gore Rush never dealt damage at contact")
	_check(m.damage_dealt == removed,
		"damage meter recorded %d but %d HP was removed" % [m.damage_dealt, removed])
	# Its stun stays the shared 1.0s — the Wind-Up Bot's 1.5s + knock-up must NOT
	# have leaked onto it.
	_check(absf(v.stun_time - v.tenacity_scaled(1.0)) < 0.001,
		"Gore Rush stun is %.3fs — expected the unchanged 1.0s scaled by tenacity" % v.stun_time)
	_check(absf(v._toss_offset.y) < 0.01,
		"Gore Rush knocked the target airborne — that is the Wind-Up Bot's alone")

func _test_savage_charge() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var m = _mk(mgr, s["grid"], EnemyFactory.create_by_type("minotaur"), Vector2i(2, 2), false)
	mgr.enemy_units = [m]; mgr.player_units = []
	mgr._tick_passive(m, mgr.player_units, mgr.enemy_units, 0.1)
	_check(mgr._savage_vfx.is_empty(), "a full-HP Minotaur already shows Savage Charge")
	m.current_hp = int(m.max_hp * 0.25)
	mgr._tick_passive(m, mgr.player_units, mgr.enemy_units, 0.1)
	_check(absf(float(m.get_meta("mob_aspd_bonus", 0.0)) - 0.30) < 0.001,
		"Savage Charge is %.3f at low HP, description caps at +30 percent"
			% float(m.get_meta("mob_aspd_bonus", 0.0)))
	_check(mgr._savage_vfx.size() == 1, "a raging Minotaur has no Savage Charge readout")
	# And it must use ITS OWN readout, not the Bear's.
	_check(mgr._fury_vfx.is_empty(), "the Minotaur borrowed the Bear's Fury readout")
	m.current_hp = m.max_hp
	mgr._tick_passive(m, mgr.player_units, mgr.enemy_units, 0.1)
	_check(mgr._savage_vfx.is_empty(), "Savage Charge readout survived a full heal")

# The Minotaur shares windup_punch with the Wind-Up Bot + Storm Giant, and
# bear_fury with the Bear + Crystal Crab + Sky Wyvern. None may be dragged along.
func _test_neighbours_unchanged() -> void:
	for code in ["windup_bot_normal", "storm_giant"]:
		var u := EnemyFactory.create_by_type(code); add_child(u)
		_check(not bool(u.get_meta("minotaur", false)),
			"%s was wrongly marked as the Minotaur and would gain horn VFX" % code)
	var bot := EnemyFactory.create_by_type("windup_bot_normal"); add_child(bot)
	_check(bool(bot.get_meta("windup_bot", false)), "the Wind-Up Bot lost its own marker")
	for code2 in ["bear_normal", "crystal_crab", "sky_wyvern"]:
		var u2 := EnemyFactory.create_by_type(code2); add_child(u2)
		_check(not bool(u2.get_meta("minotaur", false)),
			"%s was wrongly marked as the Minotaur" % code2)
