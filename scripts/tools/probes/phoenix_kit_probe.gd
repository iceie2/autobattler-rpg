extends Node

# Isolated Ember Phoenix kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/phoenix_kit_probe.tscn

var _fail: Array = []

func _check(c: bool, m: String) -> void:
	if not c: _fail.append(m)

func _fresh() -> Dictionary:
	var grid := BattleGrid.new(); var mgr := AutoBattleManager.new(); var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null); mgr.skill_effect_container = fx
	var shots := Node2D.new(); add_child(shots); mgr.projectile_container = shots
	return {"grid": grid, "mgr": mgr}

func _mk(mgr, grid, u, cell: Vector2i, player: bool):
	add_child(u); u.battle_manager = mgr; u.is_player_unit = player
	assert(grid.place_unit(u, cell)); u.grid_position = cell
	return u

func _ready() -> void:
	_test_ranges_and_ultimate()
	_test_lance_not_instant()
	_test_lance_interrupt()
	_test_rekindle()
	_test_shared_keys_unchanged()
	if _fail.is_empty():
		print("PHOENIX_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("PHOENIX_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ranges_and_ultimate() -> void:
	var p := EnemyFactory.create_ember_phoenix(); add_child(p)
	_check(p.ultimate_charge_max == 0,
		"Phoenix still inherits an ultimate pool (%d) — free off-cooldown Cinder Lances" % p.ultimate_charge_max)
	_check(p.skill_range >= p.attack_range,
		"Phoenix outranges its own Cinder Lance (attack %d vs skill %d)" % [p.attack_range, p.skill_range])
	_check(bool(p.get_meta("phoenix", false)), "Phoenix marker meta missing")

func _test_lance_not_instant() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var ph = _mk(mgr, s["grid"], EnemyFactory.create_ember_phoenix(), Vector2i(2, 1), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(2, 4), true)
	v.max_hp = 9999; v.current_hp = 9999
	mgr.enemy_units = [ph]; mgr.player_units = [v]
	var hp0: int = v.current_hp
	mgr._use_skill(ph, mgr.player_units, mgr.enemy_units)
	_check(v.current_hp == hp0, "Cinder Lance dealt damage instantly on cast")
	_check(ph.get_meta("hill_giant_committed", false), "Phoenix not flagged committed while charging")
	mgr._tick_phoenix_lances(AutoBattleManager.PHOENIX_LANCE_CHARGE + 0.01)
	_check(v.current_hp == hp0, "damage landed the instant the charge ended — the bolt must travel")
	var bolts := 0
	for pr in mgr.projectile_container.get_children():
		if pr and is_instance_valid(pr) and pr.is_phoenix_lance: bolts += 1
	_check(bolts == 1, "expected 1 travelling Cinder Lance bolt, found %d" % bolts)
	_check(not ph.get_meta("hill_giant_committed", false), "committed flag never released after firing")

func _test_lance_interrupt() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var ph = _mk(mgr, s["grid"], EnemyFactory.create_ember_phoenix(), Vector2i(2, 1), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(2, 4), true)
	mgr.enemy_units = [ph]; mgr.player_units = [v]
	mgr._use_skill(ph, mgr.player_units, mgr.enemy_units)
	ph.stun_time = 3.0
	mgr._tick_phoenix_lances(AutoBattleManager.PHOENIX_LANCE_CHARGE + 0.01)
	var bolts := 0
	for pr in mgr.projectile_container.get_children():
		if pr and is_instance_valid(pr) and pr.is_phoenix_lance: bolts += 1
	_check(bolts == 0, "a stunned Phoenix still launched its lance — the charge is not a real window")
	_check(not ph.get_meta("hill_giant_committed", false), "interrupted charge left the Phoenix committed forever")

func _test_rekindle() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var ph = _mk(mgr, s["grid"], EnemyFactory.create_ember_phoenix(), Vector2i(2, 1), false)
	mgr.enemy_units = [ph]; mgr.player_units = []
	_check(str(ph.get_meta("mob_passive", "")) == "phoenix_rebirth", "Phoenix is not on phoenix_rebirth")
	# Lethal hit -> rebuild instead of death.
	ph.take_damage(ph.max_hp * 10, UnitBase.Element.NORMAL, null, true)
	_check(ph.current_hp >= 1 and not ph._is_dying, "Phoenix died on its first death")
	_check(ph.rebirth_time > 0.0 and ph.stun_time > 0.0, "rebuild window did not start")
	_check(mgr._rekindle_vfx.size() == 1, "rebuild has no visual")
	# Immune while rebuilding.
	var hp_mid: int = ph.current_hp
	ph.take_damage(ph.max_hp * 10, UnitBase.Element.NORMAL, null, true)
	_check(ph.current_hp == hp_mid and not ph._is_dying, "Phoenix took damage mid-rebuild")
	# Rebuild finishes at 25%.
	var goal: int = int(round(ph.max_hp * AutoBattleManager.PHOENIX_REBIRTH_HP))
	for i in 20:
		mgr._tick_passive(ph, mgr.player_units, mgr.enemy_units, AutoBattleManager.PHOENIX_REBIRTH_TIME / 10.0)
	_check(ph.rebirth_time <= 0.0, "rebuild never ended")
	_check(ph.current_hp == goal, "rebuilt to %d HP, expected %d (25%%)" % [ph.current_hp, goal])
	_check(mgr._rekindle_vfx.is_empty(), "rebuild visual outlived the rebuild")
	# Second death is real.
	ph.take_damage(ph.max_hp * 10, UnitBase.Element.NORMAL, null, true)
	_check(ph.current_hp <= 0, "Phoenix cheated death twice — must be once per fight")

# The Phoenix shares lizard_snipe with the Lizard and troll_regen with 6 Trolls
# + the Gargoyle. None of them may have been dragged along.
func _test_shared_keys_unchanged() -> void:
	var liz := EnemyFactory.create_lizard_normal(); add_child(liz)
	_check(not bool(liz.get_meta("phoenix", false)),
		"the Lizard was wrongly marked as a Phoenix — it would lose its row pierce")
	_check(bool(liz.get_meta("lizard_sniper", false)), "the Lizard lost its row-pierce marker")
	for mk in [["Normal Troll", EnemyFactory.create_troll_normal()],
			["Gargoyle", EnemyFactory.create_gargoyle()]]:
		var m = mk[1]; add_child(m)
		_check(not bool(m.get_meta("phoenix", false)),
			"%s was wrongly marked as a Phoenix and would gain ember VFX" % mk[0])
