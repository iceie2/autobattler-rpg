extends Node

# Isolated Slime kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/slime_kit_probe.tscn

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
	_test_no_accidental_ultimate()
	_test_range_gate()
	_test_goo_committed()
	_test_goo_edges()
	_test_corrosion_visual()
	_test_coal_unaffected()
	_test_split()
	if _fail.is_empty():
		print("SLIME_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("SLIME_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_no_accidental_ultimate() -> void:
	var s := EnemyFactory.create_slime_normal(); add_child(s)
	_check(s.ultimate_charge_max == 0,
		"Slime still inherits an ultimate pool (%d) — free off-cooldown Corrosive Goo" % s.ultimate_charge_max)

func _test_range_gate() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var sl = _mk(mgr, s["grid"], EnemyFactory.create_slime_normal(), Vector2i(2, 2), false)
	var far = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(8, 2), true)
	mgr.enemy_units = [sl]; mgr.player_units = [far]
	_check(not mgr._skill_trigger_ready(sl, mgr.player_units),
		"Corrosive Goo triggered on a target 6 tiles away — it must require melee adjacency")
	var near = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.player_units = [near, far]
	_check(mgr._skill_trigger_ready(sl, mgr.player_units), "Corrosive Goo did not fire on an adjacent target")

func _test_goo_committed() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var sl = _mk(mgr, s["grid"], EnemyFactory.create_slime_normal(), Vector2i(2, 2), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.enemy_units = [sl]; mgr.player_units = [v]
	mgr._use_skill(sl, mgr.player_units, mgr.enemy_units)
	_check(v.weakened_time == 0.0, "Corrosive Goo applied its weaken before the splat")
	_check(sl.get_meta("hill_giant_committed", false), "Slime not flagged committed while gathering goo")
	mgr._tick_slime_goos(AutoBattleManager.SLIME_GOO_CONTACT + 0.01)
	# Numbers must be EXACTLY as described: -25% outgoing for 3s.
	_check(absf(v.weakened_pct - 0.25) < 0.001,
		"weaken is %.3f, description promises -25%%" % v.weakened_pct)
	_check(absf(v.weakened_time - 3.0) < 0.01,
		"weaken lasts %.2fs, description promises 3s" % v.weakened_time)
	_check(str(v.weaken_flavor) == "corrosion", "weaken flavour is '%s'" % str(v.weaken_flavor))
	# And it must actually reduce outgoing damage.
	_check(v.outgoing_damage_multiplier() < 1.0,
		"weaken did not reduce the victim's outgoing damage (mult %.3f)" % v.outgoing_damage_multiplier())
	_check(not sl.get_meta("hill_giant_committed", false), "committed flag never released")

func _test_goo_edges() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var sl = _mk(mgr, s["grid"], EnemyFactory.create_slime_normal(), Vector2i(2, 2), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.enemy_units = [sl]; mgr.player_units = [v]
	mgr._use_skill(sl, mgr.player_units, mgr.enemy_units)
	sl.stun_time = 2.0
	mgr._tick_slime_goos(AutoBattleManager.SLIME_GOO_CONTACT + 0.01)
	_check(v.weakened_time == 0.0, "a stunned Slime still landed its goo — no counterplay window")
	_check(not sl.get_meta("hill_giant_committed", false), "interrupted goo left the Slime committed forever")

func _test_corrosion_visual() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var sl = _mk(mgr, s["grid"], EnemyFactory.create_slime_normal(), Vector2i(2, 2), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.enemy_units = [sl]; mgr.player_units = [v]
	mgr._use_skill(sl, mgr.player_units, mgr.enemy_units)
	mgr._tick_slime_goos(AutoBattleManager.SLIME_GOO_CONTACT + 0.01)
	mgr._sync_corroded_vfx()
	_check(mgr._corroded_vfx.size() == 1, "3s weaken has no persistent visual (%d)" % mgr._corroded_vfx.size())
	v.weakened_time = 0.0
	mgr._sync_corroded_vfx()
	_check(mgr._corroded_vfx.is_empty(), "corrosion visual outlived the weaken it represents")

# Coal's post-Meltdown burnout rides the SAME weaken timer and must stay visually
# untouched — it is a hero, and slime corrosion on it would be nonsense.
func _test_coal_unaffected() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var coal = _mk(mgr, s["grid"], UnitFactory.create_unit(UnitBase.UnitClass.COAL), Vector2i(2, 6), true)
	mgr.player_units = [coal]; mgr.enemy_units = []
	coal.weakened_pct = 0.4; coal.weakened_time = 3.0      # as _tick_passive sets it
	mgr._sync_corroded_vfx()
	_check(mgr._corroded_vfx.is_empty(),
		"Coal's own burnout rendered as Slime corrosion — the weaken flavour gate is not working")

func _test_split() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var sl = _mk(mgr, s["grid"], EnemyFactory.create_slime_normal(), Vector2i(4, 2), false)
	mgr.enemy_units = [sl]; mgr.player_units = []
	var before: int = mgr.enemy_units.size()
	mgr.spawn_slime_split(sl)
	_check(mgr.enemy_units.size() == before + 2,
		"Split produced %d children, expected 2" % (mgr.enemy_units.size() - before))
	for c in mgr.enemy_units:
		if c == sl: continue
		_check(c.max_hp == maxi(1, int(sl.max_hp * 0.4)),
			"child HP %d, expected 40%% of %d" % [c.max_hp, sl.max_hp])
		_check(not c.has_meta("mob_passive"), "a child kept mob_passive — it could split again")
		_check(c.has_meta("slime_split_child"), "child missing the re-split guard")
	# A child must NOT split again — one generation only.
	var child = null
	for c in mgr.enemy_units:
		if c != sl: child = c; break
	var n: int = mgr.enemy_units.size()
	mgr.spawn_slime_split(child)
	_check(mgr.enemy_units.size() == n, "a child split again — Split must be one generation only")
