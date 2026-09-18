extends Node
# Isolated Harpy kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/harpy_kit_probe.tscn

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
	_test_ultimate_and_identity()
	_test_talon_rake_inherits_fixes()
	_test_evasion_is_announced()
	_test_evasion_still_bypassed_by_dots()
	_test_bear_keeps_its_own_look()
	if _fail.is_empty():
		print("HARPY_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("HARPY_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ultimate_and_identity() -> void:
	var h := EnemyFactory.create_by_type("harpy"); add_child(h)
	_check(h.ultimate_charge_max == 0,
		"Harpy still inherits an ultimate pool (%d)" % h.ultimate_charge_max)
	_check(h.get_meta("talon_vfx_reach", 0.0) > 0.0, "Harpy talon-VFX reach missing")
	_check(h.equipment_passives.get("Evasion", 0.0) > 0.0,
		"Harpy lost its Evasion — the whole 'survives by not being hit' identity")

func _test_talon_rake_inherits_fixes() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var h = _mk(mgr, s["grid"], EnemyFactory.create_by_type("harpy"), Vector2i(2, 2), false)
	var far = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(8, 2), true)
	mgr.enemy_units = [h]; mgr.player_units = [far]
	_check(not mgr._skill_trigger_ready(h, mgr.player_units),
		"Talon Rake triggered on a distant target — it should inherit the melee gate")
	var v = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(3, 2), true)
	v.max_hp = 9999; v.current_hp = 9999
	v.equipment_passives["Evasion"] = 0.0        # victim must not dodge the test hit
	mgr.player_units = [v, far]
	var hp0: int = v.current_hp
	mgr._use_skill(h, mgr.player_units, mgr.enemy_units)
	_check(v.current_hp == hp0, "Talon Rake dealt damage before its contact frame")
	mgr._tick_bear_swipes(AutoBattleManager.BEAR_SWIPE_CONTACT + 0.01)
	var removed: int = hp0 - v.current_hp
	_check(removed > 0, "Talon Rake never landed at contact")
	_check(h.damage_dealt == removed,
		"damage meter recorded %d but %d HP was removed" % [h.damage_dealt, removed])
	_check(v.bleed_time > 0.0, "Talon Rake did not open a bleed, but its description promises one")

# THE headline: a dodged hit used to produce literally nothing on screen.
func _test_evasion_is_announced() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var h = _mk(mgr, s["grid"], EnemyFactory.create_by_type("harpy"), Vector2i(2, 2), false)
	mgr.enemy_units = [h]; mgr.player_units = []
	h.equipment_passives["Evasion"] = 1.0        # force the dodge deterministically
	var before: int = mgr.skill_effect_container.get_child_count()
	var hp0: int = h.current_hp
	h.take_damage(50, UnitBase.Element.NORMAL, null)
	_check(h.current_hp == hp0, "a guaranteed dodge still took damage")
	_check(mgr.skill_effect_container.get_child_count() > before,
		"a dodged hit produced NO visual — indistinguishable from a bug")
	_check(mgr.has_method("spawn_evade"), "the evade hook is missing from the manager")

	# It is shared, so the Gale Warden (30% evasion) must get it too.
	var s2 := _fresh(); var mgr2 = s2["mgr"]
	var w = _mk(mgr2, s2["grid"], EnemyFactory.create_by_type("gale_warden"), Vector2i(2, 2), false)
	mgr2.enemy_units = [w]; mgr2.player_units = []
	_check(w.equipment_passives.get("Evasion", 0.0) > 0.0,
		"the Gale Warden lost its Evasion — probe is stale")
	w.equipment_passives["Evasion"] = 1.0
	var before2: int = mgr2.skill_effect_container.get_child_count()
	w.take_damage(50, UnitBase.Element.NORMAL, null)
	_check(mgr2.skill_effect_container.get_child_count() > before2,
		"the Gale Warden's dodge is still silent — the evade beat must be shared")

# Evasion deliberately does NOT apply to DoT/true damage. That must stay true,
# and must not spawn a phantom dodge either.
func _test_evasion_still_bypassed_by_dots() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var h = _mk(mgr, s["grid"], EnemyFactory.create_by_type("harpy"), Vector2i(2, 2), false)
	mgr.enemy_units = [h]; mgr.player_units = []
	h.equipment_passives["Evasion"] = 1.0
	var before: int = mgr.skill_effect_container.get_child_count()
	var hp0: int = h.current_hp
	h.take_damage(30, UnitBase.Element.NORMAL, null, true)   # true damage
	_check(h.current_hp < hp0, "true damage was dodged — evasion must not apply to DoTs")
	_check(mgr.skill_effect_container.get_child_count() == before,
		"true damage spawned a dodge visual despite not being dodgeable")

func _test_bear_keeps_its_own_look() -> void:
	var b := EnemyFactory.create_by_type("bear_normal"); add_child(b)
	_check(b.get_meta("talon_vfx_reach", 0.0) == 0.0,
		"the Bear opted into the talon look, but its move is 'Rending Swipe'")
	_check(bool(b.get_meta("bear", false)), "the Bear lost its own claw marker")
	# The Gargoyle's skill IS named Talon Rake, so it is expected to opt in during
	# its own pass. Recorded here so the intent is not lost.
	var g := EnemyFactory.create_by_type("gargoyle"); add_child(g)
	_check(g.skill_name == "Talon Rake",
		"the Gargoyle's skill is no longer named Talon Rake — the shared-visual plan is stale")
