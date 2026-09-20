extends Node

# Isolated Rat kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/rat_kit_probe.tscn

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
	return {"grid": grid, "mgr": mgr}

func _mk(mgr, grid, unit, cell: Vector2i, player: bool):
	add_child(unit)
	unit.battle_manager = mgr
	unit.is_player_unit = player
	assert(grid.place_unit(unit, cell))
	unit.grid_position = cell
	return unit

func _ready() -> void:
	_test_no_accidental_ultimate()
	_test_bite_range_gate()
	_test_bite_is_committed()
	_test_bite_edge_cases()
	_test_disease_flavour()
	_test_auto_contact()
	_test_infestation()
	_test_shared_key_mobs_unchanged()

	if _fail.is_empty():
		print("RAT_KIT_PROBE: ALL PASS")
		get_tree().quit(0)
		return
	for f in _fail: print("FAIL: ", f)
	print("RAT_KIT_PROBE: %d FAILURE(S)" % _fail.size())
	get_tree().quit(1)

func _test_no_accidental_ultimate() -> void:
	var r := EnemyFactory.create_rat()
	add_child(r)
	_check(r.ultimate_charge_max == 0,
		"Rat still inherits an ultimate pool (%d) — it would re-fire Infected Bite off-cooldown"
			% r.ultimate_charge_max)
	r._charge_ultimate(9999)
	_check(not r.ultimate_ready, "Rat became ultimate_ready despite declaring no ultimate")

func _test_bite_range_gate() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var rat = _mk(mgr, s["grid"], EnemyFactory.create_rat(), Vector2i(2, 2), false)
	var far = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(7, 2), true)
	mgr.enemy_units = [rat]; mgr.player_units = [far]
	_check(not mgr._skill_trigger_ready(rat, mgr.player_units),
		"Infected Bite triggered on a target 5 tiles away — it must require melee adjacency")
	var near = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.player_units = [near, far]
	_check(mgr._skill_trigger_ready(rat, mgr.player_units),
		"Infected Bite did not trigger on an adjacent target")

func _test_bite_is_committed() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var rat = _mk(mgr, s["grid"], EnemyFactory.create_rat(), Vector2i(2, 2), false)
	var vic = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.enemy_units = [rat]; mgr.player_units = [vic]
	var hp0: int = vic.current_hp

	mgr._use_skill(rat, mgr.player_units, mgr.enemy_units)
	_check(vic.current_hp == hp0, "Infected Bite dealt damage before its contact frame")
	_check(vic.burn_time == 0.0, "Infected Bite applied its DoT before contact")

	mgr._tick_rat_bites(AutoBattleManager.RAT_BITE_CONTACT + 0.01)
	var removed: int = hp0 - vic.current_hp
	_check(removed > 0, "Infected Bite never dealt damage at contact")
	_check(rat.damage_dealt == removed,
		"damage meter recorded %d but %d HP was removed (raw would be %d)"
			% [rat.damage_dealt, removed, int(float(rat.attack_damage) * rat.skill_damage_multiplier)])
	_check(not rat.get_meta("hill_giant_committed", false),
		"committed flag never released after the bite landed")
	# DoT numbers must match the printed description: 35% ATK/s for 3s.
	_check(absf(vic.burn_dps - float(rat.attack_damage) * 0.35) < 0.01,
		"disease dps is %.2f, description promises 35%% of ATK (%.2f)"
			% [vic.burn_dps, float(rat.attack_damage) * 0.35])
	_check(absf(vic.burn_time - 3.0) < 0.01,
		"unpacked disease lasts %.2fs, description promises 3s" % vic.burn_time)

func _test_bite_edge_cases() -> void:
	# Interrupted mid-bite.
	var s := _fresh(); var mgr = s["mgr"]
	var rat = _mk(mgr, s["grid"], EnemyFactory.create_rat(), Vector2i(2, 2), false)
	var vic = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.enemy_units = [rat]; mgr.player_units = [vic]
	var hp0: int = vic.current_hp
	mgr._use_skill(rat, mgr.player_units, mgr.enemy_units)
	rat.stun_time = 2.0
	mgr._tick_rat_bites(AutoBattleManager.RAT_BITE_CONTACT + 0.01)
	_check(vic.current_hp == hp0, "a stunned Rat still landed its bite — no counterplay window")
	_check(vic.burn_time == 0.0, "an interrupted bite still applied its disease")
	_check(not rat.get_meta("hill_giant_committed", false),
		"interrupted bite left the Rat permanently committed (it would never act again)")

	# Target stepped out of reach.
	var s2 := _fresh(); var mgr2 = s2["mgr"]
	var rat2 = _mk(mgr2, s2["grid"], EnemyFactory.create_rat(), Vector2i(2, 2), false)
	var vic2 = _mk(mgr2, s2["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr2.enemy_units = [rat2]; mgr2.player_units = [vic2]
	var hp2: int = vic2.current_hp
	mgr2._use_skill(rat2, mgr2.player_units, mgr2.enemy_units)
	vic2.grid_position = Vector2i(8, 2)
	mgr2._tick_rat_bites(AutoBattleManager.RAT_BITE_CONTACT + 0.01)
	_check(vic2.current_hp == hp2, "target that left melee range during the bite was still hit")

func _test_disease_flavour() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var rat = _mk(mgr, s["grid"], EnemyFactory.create_rat(), Vector2i(2, 2), false)
	var vic = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.enemy_units = [rat]; mgr.player_units = [vic]
	mgr._use_skill(rat, mgr.player_units, mgr.enemy_units)
	mgr._tick_rat_bites(AutoBattleManager.RAT_BITE_CONTACT + 0.01)
	_check(str(vic.burn_flavor) == "disease",
		"Rat DoT flavour is '%s' — it would render as fire" % str(vic.burn_flavor))

	# The persistent cloud must exist while the DoT runs and be gone after.
	mgr._sync_disease_vfx()
	_check(mgr._disease_vfx.size() == 1,
		"no persistent disease visual while the DoT is running (%d)" % mgr._disease_vfx.size())
	vic.burn_time = 0.0
	mgr._sync_disease_vfx()
	_check(mgr._disease_vfx.is_empty(),
		"disease visual outlived the DoT it represents — it must end on the same frame")

	# A Hellhound shares the rat_bite key but must still read as FIRE.
	var s2 := _fresh(); var mgr2 = s2["mgr"]
	var hound = _mk(mgr2, s2["grid"], EnemyFactory.create_hellhound(), Vector2i(2, 2), false)
	var v2 = _mk(mgr2, s2["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr2.enemy_units = [hound]; mgr2.player_units = [v2]
	mgr2._use_skill(hound, mgr2.player_units, mgr2.enemy_units)
	mgr2._tick_rat_bites(AutoBattleManager.RAT_BITE_CONTACT + 0.01)
	_check(str(v2.burn_flavor) == "fire",
		"Hellhound's Searing Bite now reads as '%s' — it must stay fire" % str(v2.burn_flavor))

func _test_infestation() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var a = _mk(mgr, s["grid"], EnemyFactory.create_rat(), Vector2i(2, 2), false)
	var b = _mk(mgr, s["grid"], EnemyFactory.create_rat(), Vector2i(3, 2), false)
	var c = _mk(mgr, s["grid"], EnemyFactory.create_rat(), Vector2i(2, 3), false)
	mgr.enemy_units = [a, b, c]; mgr.player_units = []

	mgr._tick_passive(a, mgr.player_units, mgr.enemy_units, 0.1)
	_check(bool(a.get_meta("rat_disease_boost", false)),
		"3 adjacent rats did not trigger Infestation (needs 2+ others within 2 tiles)")
	_check(absf(float(a.get_meta("mob_dmg_bonus", 0.0)) - 0.15) < 0.001,
		"Infestation damage bonus is %.3f, description promises +15%%"
			% float(a.get_meta("mob_dmg_bonus", 0.0)))
	_check(mgr._infest_vfx.size() >= 1, "Infestation still has no visual — it is a POSITIONAL buff")

	# Packed disease must last 50% longer, per the passive description.
	var s2 := _fresh(); var mgr2 = s2["mgr"]
	var r1 = _mk(mgr2, s2["grid"], EnemyFactory.create_rat(), Vector2i(2, 2), false)
	var r2 = _mk(mgr2, s2["grid"], EnemyFactory.create_rat(), Vector2i(3, 2), false)
	var r3 = _mk(mgr2, s2["grid"], EnemyFactory.create_rat(), Vector2i(2, 3), false)
	var vic = _mk(mgr2, s2["grid"], EnemyFactory.create_goblin(), Vector2i(1, 2), true)
	mgr2.enemy_units = [r1, r2, r3]; mgr2.player_units = [vic]
	mgr2._tick_passive(r1, mgr2.player_units, mgr2.enemy_units, 0.1)
	mgr2._use_skill(r1, mgr2.player_units, mgr2.enemy_units)
	mgr2._tick_rat_bites(AutoBattleManager.RAT_BITE_CONTACT + 0.01)
	_check(absf(vic.burn_time - 4.5) < 0.01,
		"packed disease lasts %.2fs, expected 4.5s (3s +50%%)" % vic.burn_time)

	# Breaking the swarm must switch it back off.
	b.grid_position = Vector2i(8, 8); c.grid_position = Vector2i(8, 7)
	mgr._tick_passive(a, mgr.player_units, mgr.enemy_units, 0.1)
	_check(not bool(a.get_meta("rat_disease_boost", false)),
		"Infestation stayed on after the swarm scattered — breaking it up is the counterplay")
	_check(float(a.get_meta("mob_dmg_bonus", 0.0)) == 0.0,
		"Infestation damage bonus leaked after the swarm scattered")

func _test_auto_contact() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var rat = _mk(mgr, s["grid"], EnemyFactory.create_rat(), Vector2i(2, 2), false)
	var vic = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.enemy_units = [rat]; mgr.player_units = [vic]
	rat.crit_chance = 0.0
	var hp0: int = vic.current_hp
	rat.attack(vic)
	_check(vic.current_hp == hp0, "auto dealt damage before the lunge reached the target")
	mgr._tick_windup_autos(AutoBattleManager.WINDUP_AUTO_CONTACT + 0.01)
	var removed: int = hp0 - vic.current_hp
	_check(removed > 0, "auto never dealt damage at contact")
	_check(rat.damage_dealt == removed,
		"auto damage meter recorded %d but %d HP was removed" % [rat.damage_dealt, removed])
	# Delayed autos MUST be excluded from the immediate on-hit passive call.
	var src: String = FileAccess.get_file_as_string("res://scripts/combat/auto_battle_manager.gd")
	_check(src.count("and not _has_delayed_auto(unit)") == 2,
		"on-hit passives would double-apply for units with a delayed auto")

func _test_shared_key_mobs_unchanged() -> void:
	for pair in [["Hellhound", EnemyFactory.create_hellhound()],
			["Sky Wyvern", EnemyFactory.create_sky_wyvern()]]:
		var nm: String = pair[0]
		var m = pair[1]
		add_child(m)
		_check(str(m.get_meta("mob_skill", "")) == "rat_bite",
			"%s no longer uses the shared rat_bite key — probe is stale" % nm)
		_check(str(m.get_meta("dot_flavor", "fire")) != "disease",
			"%s was wrongly flavoured as the Rat's disease" % nm)
