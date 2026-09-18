extends Node
# Isolated Gargoyle kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/gargoyle_kit_probe.tscn

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
	_test_ultimate_and_shared_talon()
	_test_talon_rake_inherits_fixes()
	_test_stone_skin()
	_test_three_regen_fictions_stay_separate()
	if _fail.is_empty():
		print("GARGOYLE_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("GARGOYLE_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ultimate_and_shared_talon() -> void:
	var g := EnemyFactory.create_by_type("gargoyle"); add_child(g)
	_check(g.ultimate_charge_max == 0,
		"Gargoyle still inherits an ultimate pool (%d) — ~3.3 free Talon Rakes at 1000 HP"
			% g.ultimate_charge_max)
	# Name-match rule: same skill name as the Harpy => same visual, scaled.
	var h := EnemyFactory.create_by_type("harpy"); add_child(h)
	_check(g.skill_name == h.skill_name,
		"Gargoyle and Harpy skill names diverged — the shared-visual rationale is gone")
	var gr: float = g.get_meta("talon_vfx_reach", 0.0)
	_check(gr > 0.0, "Gargoyle never opted into the shared Talon Rake visual")
	_check(gr > h.get_meta("talon_vfx_reach", 0.0),
		"Gargoyle's talon is not scaled larger than the Harpy's (%.0f vs %.0f) despite a heavier body"
			% [gr, h.get_meta("talon_vfx_reach", 0.0)])

func _test_talon_rake_inherits_fixes() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var g = _mk(mgr, s["grid"], EnemyFactory.create_by_type("gargoyle"), Vector2i(2, 2), false)
	var far = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(8, 2), true)
	mgr.enemy_units = [g]; mgr.player_units = [far]
	_check(not mgr._skill_trigger_ready(g, mgr.player_units),
		"Talon Rake triggered on a distant target — it should inherit the melee gate")
	var v = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(3, 2), true)
	v.max_hp = 9999; v.current_hp = 9999
	mgr.player_units = [v, far]
	var hp0: int = v.current_hp
	mgr._use_skill(g, mgr.player_units, mgr.enemy_units)
	_check(v.current_hp == hp0, "Talon Rake dealt damage before its contact frame")
	mgr._tick_bear_swipes(AutoBattleManager.BEAR_SWIPE_CONTACT + 0.01)
	var removed: int = hp0 - v.current_hp
	_check(removed > 0, "Talon Rake never landed at contact")
	_check(g.damage_dealt == removed,
		"damage meter recorded %d but %d HP was removed" % [g.damage_dealt, removed])
	_check(v.bleed_time > 0.0, "Talon Rake did not open the bleed its description promises")

func _test_stone_skin() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var g = _mk(mgr, s["grid"], EnemyFactory.create_by_type("gargoyle"), Vector2i(2, 2), false)
	mgr.enemy_units = [g]; mgr.player_units = []
	g.current_hp = 400
	mgr._tick_passive(g, mgr.player_units, mgr.enemy_units, 0.1)
	_check(g.hp_regen_accum > 0.0, "Stone Skin did not regenerate while unblocked")
	_check(mgr._stone_skin_vfx.size() == 1,
		"Stone Skin is running with no readout — its fire/lightning counterplay stays invisible")
	# A FIRE hit must crack it.
	g.take_damage(10, UnitBase.Element.FIRE, null)
	_check(float(g.get_meta("troll_regen_block_t", 0.0)) > 0.0,
		"a Fire hit did not set the regen block — passive plumbing changed")
	mgr._tick_passive(g, mgr.player_units, mgr.enemy_units, 0.1)
	_check(mgr._stone_skin_vfx.is_empty(),
		"Stone Skin readout survived the crack — it must clear the moment regen stops")

# THREE mobs now ride troll_regen with three fictions. Each must use its own.
func _test_three_regen_fictions_stay_separate() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var garg = _mk(mgr, s["grid"], EnemyFactory.create_by_type("gargoyle"), Vector2i(1, 1), false)
	var troll = _mk(mgr, s["grid"], EnemyFactory.create_by_type("troll_normal"), Vector2i(3, 1), false)
	var phx = _mk(mgr, s["grid"], EnemyFactory.create_by_type("ember_phoenix"), Vector2i(5, 1), false)
	mgr.enemy_units = [garg, troll, phx]; mgr.player_units = []
	for u in [garg, troll, phx]:
		u.current_hp = int(u.max_hp * 0.5)
		mgr._tick_passive(u, mgr.player_units, mgr.enemy_units, 0.1)
	_check(mgr._stone_skin_vfx.size() == 1,
		"expected exactly 1 Stone Skin readout, found %d" % mgr._stone_skin_vfx.size())
	_check(mgr._troll_regen_vfx.size() == 1,
		"expected exactly 1 Troll Regeneration readout, found %d" % mgr._troll_regen_vfx.size())
	_check(mgr._rekindle_vfx.size() == 1,
		"expected exactly 1 Phoenix Rekindle readout, found %d" % mgr._rekindle_vfx.size())
	_check(not bool(troll.get_meta("gargoyle", false)), "the Troll was marked as a Gargoyle")
	_check(not bool(phx.get_meta("gargoyle", false)), "the Phoenix was marked as a Gargoyle")
	_check(not bool(garg.get_meta("troll", false)), "the Gargoyle was marked as a Troll")
