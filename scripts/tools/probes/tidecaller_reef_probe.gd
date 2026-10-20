extends Node
# Tidecaller "Call of the Reef" eight-second cooldown probe,
# driving the REAL manager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/tidecaller_reef_probe.tscn

var _fail: Array = []

func _check(c: bool, m: String) -> void:
	if not c: _fail.append(m)

func _ready() -> void:
	var grid := BattleGrid.new(); var mgr := AutoBattleManager.new(); var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null); mgr.skill_effect_container = fx
	var tc: VisualUnit = EnemyFactory.create_by_type("tidecaller")
	tc.set_level(16)
	add_child(tc); tc.battle_manager = mgr; tc.is_player_unit = false
	assert(grid.place_unit(tc, Vector2i(4, 1))); tc.grid_position = Vector2i(4, 1)
	mgr.enemy_units = [tc]; mgr.player_units = []
	mgr.unit_summoned.connect(func(u): add_child(u); u.battle_manager = mgr)

	mgr._init_unit_timers()
	tc._update_reef_cooldown_bars()
	_check(tc.health_bar.ability_timers.size() == 2, "Reef Call and Tidal Ward bars are missing")
	_check(is_zero_approx(float(tc.health_bar.ability_timers[0][0])), "Reef bar did not start empty")
	mgr._tick_mob_passive(tc, [], mgr.enemy_units, 4.0)
	tc._update_reef_cooldown_bars()
	_check(is_equal_approx(float(tc.health_bar.ability_timers[0][0]), 0.5), "Reef bar did not show half cooldown at four seconds")
	mgr._init_unit_timers()
	_check(tc.ultimate_charge_max == 0 and not tc.has_meta("mob_ult"), "Reef Call still uses an ultimate pool")
	tc.take_damage(400, UnitBase.Element.NORMAL, null)
	_check(tc.ultimate_charge == 0 and not tc.ultimate_ready, "damage charged a removed ultimate")
	tc.current_mana = 0
	mgr._tick_mob_passive(tc, [], mgr.enemy_units, 7.9)
	_check(mgr.enemy_units.size() == 1, "Reef Call fired before eight seconds")
	mgr._tick_mob_passive(tc, [], mgr.enemy_units, 0.11)
	tc._update_reef_cooldown_bars()
	_check(float(tc.health_bar.ability_timers[0][0]) < 0.01, "Reef bar did not reset after summon")
	var husks := mgr.enemy_units.filter(func(u): return u.is_summoned and u.summon_owner == tc)
	_check(husks.size() == AutoBattleManager.REEF_CALL_COUNT, "first cast raised %d husks, want %d" % [husks.size(), AutoBattleManager.REEF_CALL_COUNT])
	for h in husks:
		_check(h.gold_reward == 0 and h.xp_reward == 0 and h.crystal_reward == 0, "summoned husk pays rewards")
		_check(h.level == tc.level, "husk level %d, want the caller's %d" % [h.level, tc.level])
	# Cap: more casts never exceed REEF_CALL_MAX_ALIVE.
	mgr._tick_mob_passive(tc, [], mgr.enemy_units, 7.8)
	_check(mgr.enemy_units.size() == 1 + AutoBattleManager.REEF_CALL_COUNT, "Reef Call repeated before its cooldown")
	mgr._tick_mob_passive(tc, [], mgr.enemy_units, 0.2)
	for i in 2: mgr._tick_mob_passive(tc, [], mgr.enemy_units, 8.0)
	husks = mgr.enemy_units.filter(func(u): return u.is_summoned and u.summon_owner == tc)
	_check(husks.size() == AutoBattleManager.REEF_CALL_MAX_ALIVE, "after 4 casts %d husks alive, cap is %d" % [husks.size(), AutoBattleManager.REEF_CALL_MAX_ALIVE])
	# Reset restores the full delay; timer casts never fire Mass Rejuvenation.
	mgr._init_unit_timers()
	_check(float(tc.get_meta("reef_call_cd")) == 8.0, "battle reset did not restore eight-second cooldown")
	tc._update_reef_cooldown_bars()
	_check(is_zero_approx(float(tc.health_bar.ability_timers[0][0])), "battle reset did not empty Reef bar")
	tc.current_hp = 100
	mgr._reef_call_tick(tc, 8.0)
	_check(tc.current_hp == 100, "Reef Call healed the Tidecaller — the WHITE_MAGE class arm leaked")

	if _fail.is_empty():
		print("TIDECALLER_REEF_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("TIDECALLER_REEF_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)
