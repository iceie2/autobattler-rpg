extends Node
# Isolated Skeleton kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/skeleton_kit_probe.tscn

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
	_test_bone_shield()
	_test_undying_once()
	_test_undying_announces()
	_test_shared_key_mobs_unchanged()
	if _fail.is_empty():
		print("SKELETON_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("SKELETON_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ultimate() -> void:
	var k := EnemyFactory.create_by_type("skeleton"); add_child(k)
	_check(k.ultimate_charge_max == 0,
		"Skeleton still inherits an ultimate pool (%d)" % k.ultimate_charge_max)
	_check(bool(k.get_meta("skeleton", false)), "skeleton marker meta missing")

func _test_bone_shield() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var k = _mk(mgr, s["grid"], EnemyFactory.create_by_type("skeleton"), Vector2i(3, 2), false)
	mgr.enemy_units = [k]; mgr.player_units = []
	var want: int = int(float(k.max_hp) * 0.25)
	mgr._use_skill(k, mgr.player_units, mgr.enemy_units)
	_check(k.current_shield == want,
		"shield is %d, description promises 25%% of %d = %d" % [k.current_shield, k.max_hp, want])

# Undying must fire exactly ONCE and leave the unit alive at 35% HP.
func _test_undying_once() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var k = _mk(mgr, s["grid"], EnemyFactory.create_by_type("skeleton"), Vector2i(3, 2), false)
	mgr.enemy_units = [k]; mgr.player_units = []
	var want: int = maxi(1, int(round(k.max_hp * 0.35)))
	k.current_hp = 1
	k.take_damage(9999, UnitBase.Element.NORMAL, null, true)
	_check(k.current_hp == want,
		"Undying left it at %d HP, description promises 35%% of %d = %d" % [k.current_hp, k.max_hp, want])
	_check(bool(k.get_meta("undying_used", false)), "undying_used was not recorded")
	# Second death must be real.
	k.take_damage(9999, UnitBase.Element.NORMAL, null, true)
	_check(k.current_hp <= 0,
		"Undying fired TWICE — the description says it reassembles once (hp %d)" % k.current_hp)

# The reassembly beat must actually be emitted — it was silent before.
func _test_undying_announces() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var k = _mk(mgr, s["grid"], EnemyFactory.create_by_type("skeleton"), Vector2i(3, 2), false)
	mgr.enemy_units = [k]; mgr.player_units = []
	var before: int = mgr.skill_effect_container.get_child_count()
	k.current_hp = 1
	k.take_damage(9999, UnitBase.Element.NORMAL, null, true)
	var after: int = mgr.skill_effect_container.get_child_count()
	_check(after > before,
		"reassembling spawned no visual — a unit standing back up must not be silent")
	_check(mgr.has_method("spawn_skeleton_reassemble"),
		"the reassemble hook is missing from the manager")

# boneshield is shared with the Stone Golem, Crystal Crab and Coral Husk.
func _test_shared_key_mobs_unchanged() -> void:
	for code in ["stone_golem", "crystal_crab", "coral_husk"]:
		var u := EnemyFactory.create_by_type(code); add_child(u)
		_check(str(u.get_meta("mob_skill", "")) == "skeleton_boneshield",
			"%s no longer shares skeleton_boneshield — probe is stale" % code)
		_check(not bool(u.get_meta("skeleton", false)),
			"%s was wrongly marked as the Skeleton and would gain the rib cage" % code)
	# And their shields still work.
	var s := _fresh(); var mgr = s["mgr"]
	var g = _mk(mgr, s["grid"], EnemyFactory.create_by_type("stone_golem"), Vector2i(3, 2), false)
	mgr.enemy_units = [g]; mgr.player_units = []
	mgr._use_skill(g, mgr.player_units, mgr.enemy_units)
	_check(g.current_shield > 0, "the Stone Golem's shield no longer applies")
