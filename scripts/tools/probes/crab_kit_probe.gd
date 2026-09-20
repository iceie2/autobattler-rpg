extends Node
# Isolated Crystal Crab kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/crab_kit_probe.tscn

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
	_test_shield_numbers()
	_test_persistent_shell()
	_test_shell_break()
	_test_shared_key_mobs_unchanged()
	if _fail.is_empty():
		print("CRAB_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("CRAB_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ultimate() -> void:
	var c := EnemyFactory.create_crystal_crab(); add_child(c)
	_check(c.ultimate_charge_max == 0,
		"Crab still inherits an ultimate pool (%d) — free off-cooldown shells" % c.ultimate_charge_max)
	_check(bool(c.get_meta("crystal_crab", false)), "crab marker meta missing")

func _test_shield_numbers() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var c = _mk(mgr, s["grid"], EnemyFactory.create_crystal_crab(), Vector2i(3, 2), false)
	mgr.enemy_units = [c]; mgr.player_units = []
	var want: int = int(float(c.max_hp) * 0.25)
	mgr._use_skill(c, mgr.player_units, mgr.enemy_units)
	# Numbers must match the printed description exactly: 25% of max HP.
	_check(c.current_shield == want,
		"shield is %d, description promises 25%% of %d = %d" % [c.current_shield, c.max_hp, want])

func _test_persistent_shell() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var c = _mk(mgr, s["grid"], EnemyFactory.create_crystal_crab(), Vector2i(3, 2), false)
	mgr.enemy_units = [c]; mgr.player_units = []
	mgr._sync_crab_shell_vfx()
	_check(mgr._crab_shell_vfx.is_empty(), "unshielded crab already has a shell visual")
	mgr._use_skill(c, mgr.player_units, mgr.enemy_units)
	mgr._sync_crab_shell_vfx()
	_check(mgr._crab_shell_vfx.size() == 1,
		"a shielded crab has no persistent shell — it looks identical to an unshielded one")
	# Chipping the shield must thin the plates, not just keep them full.
	var full: float = mgr._crab_shell_vfx.values()[0].strength
	c.current_shield = int(c.current_shield / 4)
	mgr._sync_crab_shell_vfx()
	var thin: float = mgr._crab_shell_vfx.values()[0].strength
	_check(thin < full,
		"shell strength did not fall as the shield was chipped (%.2f -> %.2f)" % [full, thin])

func _test_shell_break() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var c = _mk(mgr, s["grid"], EnemyFactory.create_crystal_crab(), Vector2i(3, 2), false)
	mgr.enemy_units = [c]; mgr.player_units = []
	mgr._use_skill(c, mgr.player_units, mgr.enemy_units)
	mgr._sync_crab_shell_vfx()
	_check(mgr._crab_shell_vfx.size() == 1, "setup: no shell to break")
	c.current_shield = 0
	mgr._sync_crab_shell_vfx()
	_check(mgr._crab_shell_vfx.is_empty(),
		"shell visual survived the shield running out — it must end with the mechanic")
	_check(mgr._crab_shell_peak.is_empty(), "shell peak bookkeeping leaked after the break")

# Skeleton / Stone Golem / Coral Husk share the boneshield key and must be
# untouched — they keep the original instant HOLY_LIGHT burst and no shell.
func _test_shared_key_mobs_unchanged() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var cell := Vector2i(2, 2)
	for pair in [["Skeleton", EnemyFactory.create_skeleton()],
			["Stone Golem", EnemyFactory.create_stone_golem()],
			["Coral Husk", EnemyFactory.create_coral_husk()]]:
		var nm: String = pair[0]
		var m = pair[1]
		_check(str(m.get_meta("mob_skill", "")) == "skeleton_boneshield",
			"%s no longer uses the shared boneshield key — probe is stale" % nm)
		_check(not bool(m.get_meta("crystal_crab", false)),
			"%s was wrongly marked as the Crystal Crab and would gain the mineral shell" % nm)
		_mk(mgr, s["grid"], m, cell, false)
		cell.x += 1
		mgr.enemy_units.append(m)
		mgr._use_skill(m, [], mgr.enemy_units)
		_check(m.current_shield > 0, "%s's shield no longer applies" % nm)
	mgr._sync_crab_shell_vfx()
	_check(mgr._crab_shell_vfx.is_empty(),
		"a non-crab boneshield user got the crab's persistent shell visual")
