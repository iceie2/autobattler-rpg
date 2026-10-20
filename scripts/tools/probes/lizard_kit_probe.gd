extends Node

# Isolated Lizard kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/lizard_kit_probe.tscn

var _fail: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail.append(msg)

func _fresh() -> Dictionary:
	var grid := BattleGrid.new()
	var mgr := AutoBattleManager.new()
	var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null)
	mgr.skill_effect_container = fx
	var shots := Node2D.new(); add_child(shots); mgr.projectile_container = shots
	return {"grid": grid, "mgr": mgr}

func _mk(mgr, grid, unit, cell: Vector2i, player: bool):
	add_child(unit)
	unit.battle_manager = mgr
	unit.is_player_unit = player
	assert(grid.place_unit(unit, cell))
	unit.grid_position = cell
	return unit

func _ready() -> void:
	_test_ranges_consistent()
	_test_no_accidental_ultimate()
	_test_range_gate()
	_test_shot_is_not_instant()
	await _test_row_pierce()
	_test_interrupt()
	_test_cold_blood()
	_test_phoenix_unchanged()

	if _fail.is_empty():
		print("LIZARD_KIT_PROBE: ALL PASS")
		get_tree().quit(0)
		return
	for f in _fail: print("FAIL: ", f)
	print("LIZARD_KIT_PROBE: %d FAILURE(S)" % _fail.size())
	get_tree().quit(1)

# A unit must never outrange its own signature — that silently makes the skill
# unusable at the distances it actually fights from.
func _test_ranges_consistent() -> void:
	var l := EnemyFactory.create_lizard_normal()
	add_child(l)
	_check(l.skill_range >= l.attack_range,
		"Lizard outranges its own Precision Shot (attack %d vs skill %d)"
			% [l.attack_range, l.skill_range])
	_check(l.skill_description.contains("row"),
		"description does not mention the row it now pierces: '%s'" % l.skill_description)

func _test_no_accidental_ultimate() -> void:
	var l := EnemyFactory.create_lizard_normal()
	add_child(l)
	_check(l.ultimate_charge_max == 0,
		"Lizard still inherits an ultimate pool (%d)" % l.ultimate_charge_max)

func _test_range_gate() -> void:
	# NOTE: distance here is Chebyshev (_rect_dist), so on a 9x9 board the
	# furthest any two cells can be is 8. The Lizard's range of 8 therefore
	# covers the ENTIRE board — there is no out-of-range case to test for it,
	# which is itself worth knowing (it never has to position or move).
	var s := _fresh(); var mgr = s["mgr"]
	var liz = _mk(mgr, s["grid"], EnemyFactory.create_lizard_normal(), Vector2i(0, 0), false)
	var corner = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(8, 8), true)
	mgr.enemy_units = [liz]; mgr.player_units = [corner]
	_check(mgr._skill_trigger_ready(liz, mgr.player_units),
		"Precision Shot did not trigger at range 8 (the board's maximum)")

	# The GATE itself is verified on a unit with a range that actually bounds:
	# the Ember Phoenix shares this skill key at range 4.
	var s2 := _fresh(); var mgr2 = s2["mgr"]
	var phx = _mk(mgr2, s2["grid"], EnemyFactory.create_ember_phoenix(), Vector2i(0, 0), false)
	var out = _mk(mgr2, s2["grid"], EnemyFactory.create_goblin(), Vector2i(8, 8), true)
	mgr2.enemy_units = [phx]; mgr2.player_units = [out]
	_check(not mgr2._skill_trigger_ready(phx, mgr2.player_units),
		"lizard_snipe fired at distance 8 from a unit whose skill_range is %d — the gate is not working"
			% phx.skill_range)
	var inn = _mk(mgr2, s2["grid"], EnemyFactory.create_goblin(), Vector2i(0, 3), true)
	mgr2.player_units = [inn, out]
	_check(mgr2._skill_trigger_ready(phx, mgr2.player_units),
		"lizard_snipe did not fire at a target inside skill_range")

func _test_shot_is_not_instant() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var liz = _mk(mgr, s["grid"], EnemyFactory.create_lizard_normal(), Vector2i(2, 1), false)
	var vic = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(2, 5), true)
	mgr.enemy_units = [liz]; mgr.player_units = [vic]
	var hp0: int = vic.current_hp
	mgr._use_skill(liz, mgr.player_units, mgr.enemy_units)
	_check(vic.current_hp == hp0, "Precision Shot dealt damage instantly on cast")
	_check(liz.get_meta("hill_giant_committed", false),
		"Lizard is not flagged committed while aiming — it would walk off mid-shot")
	# Still nothing at the end of the aim: the BOLT has only just launched.
	mgr._tick_lizard_aims(AutoBattleManager.LIZARD_AIM_TIME + 0.01)
	_check(vic.current_hp == hp0,
		"damage landed the instant the aim finished — the bolt must travel")
	_check(_count_bolts(mgr) >= 1,
		"no travelling bolt was spawned after the aim completed")

func _count_bolts(mgr) -> int:
	var n := 0
	for p in mgr.projectile_container.get_children():
		if p and is_instance_valid(p) and p.pierce_row >= 0:
			n += 1
	return n

# THE new mechanic: every opponent in the target's row is hit exactly once,
# and nobody outside it is touched.
func _test_row_pierce() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var liz = _mk(mgr, s["grid"], EnemyFactory.create_lizard_normal(), Vector2i(4, 1), false)
	# Three heroes abreast in row 5, one in row 6 as the control.
	var a = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(2, 5), true)
	var b = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(4, 5), true)
	var c = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(7, 5), true)
	var off = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(4, 6), true)
	for u in [a, b, c, off]:
		u.max_hp = 9999; u.current_hp = 9999
	mgr.enemy_units = [liz]; mgr.player_units = [a, b, c, off]

	var before := {}
	for u in [a, b, c, off]: before[u] = u.current_hp
	mgr.resolve_precision_shot(liz, 5, 100)

	for u in [a, b, c]:
		_check(u.current_hp < before[u],
			"hero at %s shares the pierced row but was not hit" % u.grid_position)
	_check(off.current_hp == before[off],
		"hero at %s is OUTSIDE the pierced row but was hit — footprint lies" % off.grid_position)
	# Exactly once each, and the meter is post-mitigation.
	var total_removed := 0
	for u in [a, b, c]: total_removed += before[u] - u.current_hp
	_check(liz.damage_dealt == total_removed,
		"damage meter recorded %d but %d HP was removed across the row"
			% [liz.damage_dealt, total_removed])
	var one: int = before[a] - a.current_hp
	_check(one > 0 and absf(float(total_removed) / 3.0 - float(one)) < 1.0,
		"a hero appears to have been hit more than once (per-hero %d, total %d)"
			% [one, total_removed])

	# A 2x2 body standing half in the row must still take it.
	var s2 := _fresh(); var mgr2 = s2["mgr"]
	var liz2 = _mk(mgr2, s2["grid"], EnemyFactory.create_lizard_normal(), Vector2i(0, 0), false)
	var giant = EnemyFactory.create_hill_giant()
	add_child(giant); giant.battle_manager = mgr2; giant.is_player_unit = true
	s2["grid"].place_unit(giant, Vector2i(4, 4)); giant.grid_position = Vector2i(4, 4)
	mgr2.enemy_units = [liz2]; mgr2.player_units = [giant]
	var ghp: int = giant.current_hp
	mgr2.resolve_precision_shot(liz2, 5, 100)   # giant occupies rows 4 AND 5
	_check(giant.current_hp < ghp,
		"a 2x2 unit occupying the row was missed — cell_size ignored")
	await get_tree().process_frame

func _test_interrupt() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var liz = _mk(mgr, s["grid"], EnemyFactory.create_lizard_normal(), Vector2i(2, 1), false)
	var vic = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(2, 5), true)
	mgr.enemy_units = [liz]; mgr.player_units = [vic]
	var hp0: int = vic.current_hp
	mgr._use_skill(liz, mgr.player_units, mgr.enemy_units)
	liz.stun_time = 3.0
	mgr._tick_lizard_aims(AutoBattleManager.LIZARD_AIM_TIME + 0.01)
	_check(vic.current_hp == hp0, "a stunned Lizard still fired — the telegraph is not a real window")
	_check(_count_bolts(mgr) == 0, "an interrupted aim still launched a bolt")
	_check(not liz.get_meta("hill_giant_committed", false),
		"interrupted aim left the Lizard permanently committed")

func _test_cold_blood() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var liz = _mk(mgr, s["grid"], EnemyFactory.create_lizard_normal(), Vector2i(2, 1), false)
	mgr.enemy_units = [liz]; mgr.player_units = []
	liz.current_hp = 100
	# Un-hit for 3s -> regen, and the readout appears.
	for i in range(40):
		mgr._tick_passive(liz, mgr.player_units, mgr.enemy_units, 0.1)
	_check(liz.hp_regen_accum > 0.0 or liz.current_hp > 100,
		"Cold Blood never regenerated after 4s without being hit")
	_check(mgr._cold_blood_vfx.size() == 1,
		"Cold Blood is regenerating with no visual — 'go hit the backline' is never communicated")
	# Take a hit -> it must switch off, and the readout with it.
	liz.take_damage(10, UnitBase.Element.NORMAL, null)
	mgr._tick_passive(liz, mgr.player_units, mgr.enemy_units, 0.1)
	_check(mgr._cold_blood_vfx.is_empty(),
		"Cold Blood readout survived a hit — it must clear the moment regen stops")

func _test_phoenix_unchanged() -> void:
	var p := EnemyFactory.create_ember_phoenix()
	add_child(p)
	_check(str(p.get_meta("mob_skill", "")) == "lizard_snipe",
		"Ember Phoenix no longer shares lizard_snipe — probe is stale")
	_check(not bool(p.get_meta("lizard_sniper", false)),
		"Ember Phoenix was wrongly marked as the row-piercing Lizard")
	_check(p.skill_range == p.attack_range,
		"Ember Phoenix range consistency changed (attack %d vs skill %d)"
			% [p.attack_range, p.skill_range])
