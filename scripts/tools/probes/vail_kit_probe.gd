extends Node
# Isolated Vail kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/vail_kit_probe.tscn
#
# First HERO kit probe in the repo — every existing one under scripts/tools/
# probes/ builds its subject through EnemyFactory. Heroes come from
# UnitFactory.create_unit(class, element, is_player) instead, and they carry an
# ability registry (AbilityFormulas) the enemies do not, so the checks below
# assert against the REGISTRY rather than against literals. A probe that
# hard-codes 0.10 passes happily after someone retunes the registry to 0.12 and
# the level-up panel starts disagreeing with the fight, which is the exact
# failure the registry exists to prevent.

var _fail: Array = []

func _check(c: bool, m: String) -> void:
	if not c: _fail.append(m)

func _fresh() -> Dictionary:
	var grid := BattleGrid.new(); var mgr := AutoBattleManager.new(); var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null); mgr.skill_effect_container = fx
	return {"grid": grid, "mgr": mgr, "fx": fx}

func _mk(mgr, grid, u, cell: Vector2i, player: bool):
	add_child(u); u.battle_manager = mgr; u.is_player_unit = player
	assert(grid.place_unit(u, cell)); u.grid_position = cell
	return u

func _vail():
	return UnitFactory.create_unit(UnitBase.UnitClass.VAIL, UnitBase.Element.AIR, true)

# NOT one of the original seven classes (WARRIOR/RANGER/MONK/...). Those have
# no row in UnitFactory.CLASS_BASE_STATS, so create_unit() throws on the lookup
# and hands back null, and every assertion afterwards fails against a Nil with
# no hint as to why. Use a hero the stat table actually knows.
func _ally():
	return UnitFactory.create_unit(UnitBase.UnitClass.RUSH, UnitBase.Element.NORMAL, true)

func _foe():
	return UnitFactory.create_unit(UnitBase.UnitClass.SABLE, UnitBase.Element.NORMAL, false)

func _ready() -> void:
	# Heroes need one frame before UnitFactory.create_unit works: VisualUnit
	# resolves its sprite/model setup on entering the tree, and building one
	# synchronously inside _ready() returns null. The enemy probes get away
	# without this because EnemyFactory does not touch that path.
	await get_tree().process_frame
	_test_identity()
	_test_far_winds_haste_and_radius()
	_test_far_winds_does_not_stack_or_leak()
	_test_updraft_picks_most_wounded_and_lifts()
	_test_updraft_untargetable_is_honoured_by_targeting()
	_test_downburst_slows_whole_enemy_team()
	_test_downburst_slam_queue_drains()
	if _fail.is_empty():
		print("VAIL_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("VAIL_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_identity() -> void:
	var v = _vail(); add_child(v)
	_check(v.current_element == UnitBase.Element.AIR,
		"Vail is not AIR — her whole kit and VFX language assume it")
	_check(v.attack_range >= 4,
		"Vail's range dropped to %d; her attack clip is authored as a ranged cast" % v.attack_range)
	_check(v.ultimate_damage_mult == 0.0,
		"Downburst gained a damage multiplier — it is a pure control ultimate")

# ── Far Winds ────────────────────────────────────────────────────────────────

func _test_far_winds_haste_and_radius() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var v = _mk(mgr, s["grid"], _vail(), Vector2i(2, 2), true)
	var near = _mk(mgr, s["grid"], _ally(), Vector2i(3, 2), true)   # 1 tile
	var far = _mk(mgr, s["grid"], _ally(), Vector2i(8, 8), true)    # way outside
	mgr.player_units = [v, near, far]; mgr.enemy_units = []
	var want: float = AbilityFormulas.value_of(v, AbilityFormulas.PASSIVE, "aspd")
	_check(want > 0.0, "Far Winds has no aspd term in the registry")
	# One tick past the aura interval so the refresh fires.
	v.set_meta("aura_tick_t", 0.0)
	mgr._tick_passive(v, mgr.enemy_units, mgr.player_units, 0.016)
	_check(is_equal_approx(near.bonus_aspd_pct, want),
		"ally in radius got %.3f aspd, registry says %.3f" % [near.bonus_aspd_pct, want])
	_check(near.bonus_aspd_time > 0.0, "haste was applied with no duration — it expires instantly")
	_check(far.bonus_aspd_pct == 0.0,
		"ally at 8 tiles was hasted; Far Winds radius is %.1f"
			% AbilityFormulas.value_of(v, AbilityFormulas.PASSIVE, "radius"))
	_check(v.bonus_aspd_pct == 0.0, "Far Winds hasted Vail herself; it is an ALLY aura")

# The aura refreshes every tick forever. If it ever ADDED instead of taking a
# max, a two-minute fight would end with an ally at several hundred percent.
func _test_far_winds_does_not_stack_or_leak() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var v = _mk(mgr, s["grid"], _vail(), Vector2i(2, 2), true)
	var near = _mk(mgr, s["grid"], _ally(), Vector2i(3, 2), true)
	mgr.player_units = [v, near]; mgr.enemy_units = []
	var want: float = AbilityFormulas.value_of(v, AbilityFormulas.PASSIVE, "aspd")
	for i in range(40):
		v.set_meta("aura_tick_t", 0.0)
		mgr._tick_passive(v, mgr.enemy_units, mgr.player_units, 0.016)
	_check(is_equal_approx(near.bonus_aspd_pct, want),
		"Far Winds stacked to %.3f over 40 ticks (registry %.3f)" % [near.bonus_aspd_pct, want])

# ── Updraft ──────────────────────────────────────────────────────────────────

func _test_updraft_picks_most_wounded_and_lifts() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var v = _mk(mgr, s["grid"], _vail(), Vector2i(2, 2), true)
	var healthy = _mk(mgr, s["grid"], _ally(), Vector2i(3, 2), true)
	var hurt = _mk(mgr, s["grid"], _ally(), Vector2i(4, 2), true)
	hurt.current_hp = int(hurt.max_hp * 0.2)
	mgr.player_units = [v, healthy, hurt]; mgr.enemy_units = []
	mgr._vail_updraft(v, mgr.player_units)
	_check(hurt.untargetable_time > 0.0,
		"Updraft did not lift the most-wounded ally")
	_check(healthy.untargetable_time == 0.0,
		"Updraft lifted the HEALTHY ally instead of the wounded one")
	var regen: float = AbilityFormulas.value_of(v, AbilityFormulas.ACTIVE, "regen")
	_check(is_equal_approx(hurt.bonus_regen_amt, regen),
		"regen %.2f/s does not match the registry's %.2f" % [hurt.bonus_regen_amt, regen])
	_check(hurt.bonus_regen_time > 0.0, "regen was granted with no duration")
	# The regen must actually move HP, not just sit on the unit.
	# _regen_tick, NOT _tick_statuses: bonus_regen_amt is accumulated into
	# hp_regen_accum alongside base regen and the Titan's Heart relic, and only
	# converts to real HP once the accumulator passes 1.0.
	var hp0: int = hurt.current_hp
	for i in range(60):
		mgr._regen_tick(hurt, 1.0 / 60.0)
	_check(hurt.current_hp > hp0,
		"one second of Updraft regen healed nothing (%d -> %d)" % [hp0, hurt.current_hp])

# THE headline of the ability. If targeting ignores untargetable_time, the
# "untargetable" in her own tooltip is a lie and the lift is cosmetic.
func _test_updraft_untargetable_is_honoured_by_targeting() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var v = _mk(mgr, s["grid"], _vail(), Vector2i(2, 2), true)
	var victim = _mk(mgr, s["grid"], _ally(), Vector2i(3, 2), true)
	var hunter = _mk(mgr, s["grid"], _foe(), Vector2i(4, 2), false)
	mgr.player_units = [v, victim]; mgr.enemy_units = [hunter]
	var before = mgr.find_nearest_enemy(hunter, mgr.player_units)
	_check(before != null, "the hunter could not find any target before the lift")
	victim.untargetable_time = 2.0
	var after = mgr.find_nearest_enemy(hunter, mgr.player_units)
	_check(after != victim,
		"a lifted ally is still selected as a target — Updraft's untargetable does nothing")

# ── Downburst ────────────────────────────────────────────────────────────────

func _test_downburst_slows_whole_enemy_team() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var v = _mk(mgr, s["grid"], _vail(), Vector2i(2, 2), true)
	var foes := []
	for i in range(4):
		foes.append(_mk(mgr, s["grid"], _foe(), Vector2i(5 + i, 3), false))
	mgr.player_units = [v]; mgr.enemy_units = foes
	var hp_before: Array = []
	for f in foes: hp_before.append(f.current_hp)
	mgr._vail_downburst(v, mgr.enemy_units)
	for i in range(foes.size()):
		_check(foes[i].slow_time > 0.0,
			"enemy %d was not slowed — Downburst is supposed to hit the whole team" % i)
		_check(foes[i].current_hp == hp_before[i],
			"Downburst dealt damage to enemy %d; it is a pure control ultimate" % i)

# The slam is queued on a delay so it lands after its telegraph. A queue that
# never drains is a leak; one that drains on a freed unit is a crash.
func _test_downburst_slam_queue_drains() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var v = _mk(mgr, s["grid"], _vail(), Vector2i(2, 2), true)
	var foe = _mk(mgr, s["grid"], _foe(), Vector2i(5, 3), false)
	mgr.player_units = [v]; mgr.enemy_units = [foe]
	mgr._vail_downburst(v, mgr.enemy_units)
	_check(mgr._vail_slams.size() == 1,
		"Downburst queued %d slams for 1 enemy" % mgr._vail_slams.size())
	for i in range(40):
		mgr._tick_vail_slams(0.05)
	_check(mgr._vail_slams.is_empty(),
		"the slam queue still holds %d entries after 2s" % mgr._vail_slams.size())
