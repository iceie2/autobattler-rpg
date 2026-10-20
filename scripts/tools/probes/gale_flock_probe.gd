extends Node
# Gale Warden flock probe, driving the REAL manager.
#   2026-09-28: flock sizes, spread targeting, Scatter.
#   2026-10-06: continuous flight, Vengeful Flock (shared hunt), Cyclone Shove
#               target / range / contact timing / lockout, pause, grid ownership,
#               battle reset.
# Run: godot --headless --rendering-method gl_compatibility --fixed-fps 30 res://scenes/tools/gale_flock_probe.tscn

const DT := 1.0 / 30.0
var _fail: Array = []
var _checks := 0

func _check(c: bool, m: String) -> void:
	_checks += 1
	if not c: _fail.append(m)

func _fresh() -> Dictionary:
	var grid := BattleGrid.new(); var mgr := AutoBattleManager.new(); var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null); mgr.skill_effect_container = fx
	return {"grid": grid, "mgr": mgr, "fx": fx}

func _free(s: Dictionary) -> void:
	for k in ["mgr", "grid", "fx"]:
		s[k].queue_free()

func _mk(mgr, grid, u, cell: Vector2i, player: bool):
	add_child(u); u.battle_manager = mgr; u.is_player_unit = player
	assert(grid.place_unit(u, cell)); u.grid_position = cell
	u.position = grid.grid_to_world(cell)
	return u

func _bird(mgr, grid, cell: Vector2i):
	return _mk(mgr, grid, EnemyFactory.create_by_type("gale_warden"), cell, false)

# A "hero": a goblin on the player side. `tough` = never dies, never kills.
func _hero(mgr, grid, cell: Vector2i, tough := true):
	var h = _mk(mgr, grid, EnemyFactory.create_by_type("goblin"), cell, true)
	if tough:
		h.max_hp = 999999; h.current_hp = 999999; h.attack_damage = 1
	return h

# Arm the manager the way start_battle does, but over hand-built rosters.
func _arm(mgr, birds: Array, heroes: Array) -> void:
	mgr.enemy_units = birds.duplicate(); mgr.player_units = heroes.duplicate()
	mgr.battle_active = true
	mgr._gale_reset()
	mgr._wire_gale_flock()

func _kill(bird, killer) -> void:
	bird.take_damage(bird.current_hp + bird.current_shield + 99999, UnitBase.Element.NORMAL, killer, true)

func _ready() -> void:
	_test_flock_sizes()
	_test_spread()
	_test_scatter()
	_test_hunt_sync_and_refresh()
	_test_simultaneous_deaths()
	_test_killer_unavailable()
	_test_mark_replacement_and_expiry()
	_test_taunt_wins()
	_test_last_bird()
	_test_shove_rules()
	_test_flight_loop()
	_test_reset()
	if _fail.is_empty():
		print("GALE_FLOCK_PROBE: ALL PASS (%d checks)" % _checks); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("GALE_FLOCK_PROBE: %d FAILURE(S) of %d checks" % [_fail.size(), _checks]); get_tree().quit(1)

func _test_flock_sizes() -> void:
	for d in 3:
		var n := 0
		for e in WaveScaler.build_elite_formation(15, d, 9):
			if e["code"] == "GW": n += 1
		_check(n == WaveScaler.GALE_FLOCK_SIZE[d],
			"difficulty %d fielded %d birds, want %d" % [d, n, WaveScaler.GALE_FLOCK_SIZE[d]])

# Four birds, four heroes: every hero should get exactly one bird.
func _test_spread() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var birds: Array = []
	for x in 4:
		birds.append(_bird(mgr, g, Vector2i(x * 2, 1)))
	var heroes: Array = []
	for x in 4:
		heroes.append(_hero(mgr, g, Vector2i(x * 2 + 1, 6)))
	mgr.enemy_units = birds; mgr.player_units = heroes
	for _pass in 3:   # a few frames of retargeting, like the real tick
		for b in birds:
			b.target_unit = mgr._choose_target(b, heroes)
	var per := {}
	for b in birds:
		per[b.target_unit] = int(per.get(b.target_unit, 0)) + 1
	_check(per.size() == 4, "4 birds covered %d heroes — they should spread one per hero" % per.size())
	_check(g.passing_cells.size() == 4 and g.occupied_cells.size() == 4,
		"birds must sit in the nonblocking layer, heroes in the solid one")
	_free(s)

# Kill one bird: the others lose their dodge for GALE_SCATTER_TIME (from the death
# hook, not polling), then regain it; the live accessor agrees with take_damage.
func _test_scatter() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var birds: Array = []
	for x in 3:
		birds.append(_bird(mgr, g, Vector2i(x * 2, 1)))
	var h = _hero(mgr, g, Vector2i(4, 6))
	_arm(mgr, birds, [h])
	_check(is_equal_approx(birds[1].effective_evasion(), EnemyFactory.GALE_WARDEN_EVASION), "live dodge should start at 30%")
	_kill(birds[0], h)
	_check(float(birds[1].get_meta("scatter_t", 0.0)) > 0.0, "a flockmate died but the survivor did not scatter")
	_check(birds[1].effective_evasion() == 0.0, "scattered bird still reports dodge")
	_check(AutoBattleManager.gale_flock_description(birds[1]).begins_with("Dodge: 0%"),
		"details text does not show the live 0% dodge while scattered")
	birds[1].max_hp = 999999; birds[1].current_hp = 999999
	var times0: int = birds[1].times_hit
	for i in 200: birds[1].take_damage(1, UnitBase.Element.NORMAL, null)
	_check(birds[1].times_hit - times0 == 200, "a scattered bird still dodged %d of 200 hits" % (200 - (birds[1].times_hit - times0)))
	for i in 30: mgr._tick_mob_passive(birds[1], [], birds, 0.1)
	_check(float(birds[1].get_meta("scatter_t", 0.0)) <= 0.0, "scatter never wore off")
	_check(birds[1].effective_evasion() > 0.0, "dodge did not come back after scatter")
	mgr.end_battle(true)
	_free(s)

# One death: every survivor targets the killer at once for 10 s. A second death
# refreshes to 10 (not +10) and KEEPS the same mark (owner decision 2026-10-06).
func _test_hunt_sync_and_refresh() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var birds: Array = []
	for x in 5:
		birds.append(_bird(mgr, g, Vector2i(x * 2, 1)))
	var a = _hero(mgr, g, Vector2i(0, 7)); var b = _hero(mgr, g, Vector2i(4, 7)); var c = _hero(mgr, g, Vector2i(8, 7))
	var heroes := [a, b, c]
	_arm(mgr, birds, heroes)
	for bd in birds: bd.target_unit = mgr._choose_target(bd, heroes)
	_kill(birds[0], c)
	var hunt: Dictionary = mgr.gale_hunt_info(false)
	_check(not hunt.is_empty() and hunt["mark"] == c, "the killer was not marked")
	_check(is_equal_approx(float(hunt.get("t", 0.0)), AutoBattleManager.GALE_HUNT_TIME), "hunt did not start at 10s")
	var all_on := true
	for bd in birds.slice(1):
		if mgr._choose_target(bd, heroes) != c: all_on = false
	_check(all_on, "not every surviving bird switched to the mark")
	_check(float(c.get_meta("gale_hunted_t", 0.0)) > 0.0, "marked hero carries no Hunted badge timer")
	# Staggered first swings, not one frame of hits.
	var cds: Array = []
	for bd in birds.slice(1): cds.append(snappedf(bd.attack_cooldown, 0.01))
	cds.sort()
	_check(cds[-1] - cds[0] >= AutoBattleManager.GALE_HUNT_STAGGER * 2.5, "swings on the new mark were not staggered: %s" % [cds])
	mgr._tick_gale(4.0)
	_check(is_equal_approx(float(mgr.gale_hunt_info(false)["t"]), 6.0), "hunt timer did not count down on the combat clock")
	_kill(birds[1], a)
	hunt = mgr.gale_hunt_info(false)
	_check(hunt["mark"] == c, "a second death moved the mark (should stay on the living mark)")
	_check(is_equal_approx(float(hunt["t"]), AutoBattleManager.GALE_HUNT_TIME), "second death did not REFRESH to 10s (got %.2f)" % float(hunt["t"]))
	mgr.end_battle(true)
	_free(s)

# Two birds dying in the same frame start ONE hunt, on the first killer.
func _test_simultaneous_deaths() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var birds: Array = []
	for x in 4:
		birds.append(_bird(mgr, g, Vector2i(x * 2, 1)))
	var a = _hero(mgr, g, Vector2i(1, 7)); var b = _hero(mgr, g, Vector2i(6, 7))
	_arm(mgr, birds, [a, b])
	_kill(birds[0], a)
	_kill(birds[3], b)   # same frame — no tick between
	var hunt: Dictionary = mgr.gale_hunt_info(false)
	_check(hunt.get("mark") == a and is_equal_approx(float(hunt.get("t", 0.0)), AutoBattleManager.GALE_HUNT_TIME),
		"simultaneous deaths: want one hunt on the first killer at 10s")
	_check(mgr._gale_mark_fx.size() == 1, "simultaneous deaths spawned %d mark effects" % mgr._gale_mark_fx.size())
	mgr.end_battle(true)
	_free(s)

# Killer already dead / freed (or a DoT with no source): deterministic fallback —
# the hero nearest the dead bird.
func _test_killer_unavailable() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var birds: Array = []
	for x in 3:
		birds.append(_bird(mgr, g, Vector2i(x * 3, 2)))
	var far = _hero(mgr, g, Vector2i(8, 8)); var near = _hero(mgr, g, Vector2i(0, 4))
	var killer = _hero(mgr, g, Vector2i(4, 8))
	_arm(mgr, birds, [far, near, killer])
	killer.current_hp = 0   # the killer died to something else first
	_kill(birds[0], killer)
	_check(mgr.gale_hunt_info(false).get("mark") == near, "dead killer: fallback should be the hero nearest the fallen bird")
	mgr.end_battle(true); mgr.battle_active = true; mgr._gale_reset()
	_kill(birds[1], null)   # sourceless death (DoT tick)
	var m = mgr.gale_hunt_info(false).get("mark")
	_check(m != null and m != killer, "sourceless death did not pick a living fallback")
	mgr.end_battle(true)
	_free(s)

# Mark dies mid-hunt: ONE shared replacement keeps the remaining time; at expiry
# the birds go back to spreading and the badge clears.
func _test_mark_replacement_and_expiry() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var birds: Array = []
	for x in 4:
		birds.append(_bird(mgr, g, Vector2i(x * 2 + 1, 2)))
	var heroes: Array = []
	for x in 4:
		heroes.append(_hero(mgr, g, Vector2i(x * 2, 7)))
	_arm(mgr, birds, heroes)
	_kill(birds[0], heroes[0])
	mgr._tick_gale(3.0)
	heroes[0].current_hp = 0
	mgr._tick_gale(DT)
	var hunt: Dictionary = mgr.gale_hunt_info(false)
	_check(not hunt.is_empty() and hunt["mark"] != heroes[0] and hunt["mark"].current_hp > 0, "dead mark was not replaced")
	_check(absf(float(hunt.get("t", 0.0)) - (AutoBattleManager.GALE_HUNT_TIME - 3.0 - DT)) < 0.01, "replacement did not keep the remaining time")
	_check(not heroes[0].has_meta("gale_hunted_t"), "dead mark kept its Hunted badge timer")
	var rep = hunt["mark"]
	var all_on := true
	for bd in birds.slice(1):
		if mgr._choose_target(bd, heroes) != rep: all_on = false
	_check(all_on, "birds did not all move to the one replacement")
	# Untargetable mark is also replaced.
	rep.untargetable_time = 1.0
	mgr._tick_gale(DT)
	_check(mgr.gale_hunt_info(false).get("mark") != rep, "untargetable mark was not replaced")
	rep.untargetable_time = 0.0
	var last_mark = mgr.gale_hunt_info(false)["mark"]
	mgr._tick_gale(AutoBattleManager.GALE_HUNT_TIME)
	_check(mgr.gale_hunt_info(false).is_empty(), "hunt never expired")
	_check(not last_mark.has_meta("gale_hunted_t"), "Hunted badge timer survived expiry")
	var live: Array = heroes.filter(func(h): return h.current_hp > 0)
	for _pass in 4:
		for bd in birds.slice(1): bd.target_unit = mgr._choose_target(bd, live)
	var per := {}
	for bd in birds.slice(1): per[bd.target_unit] = true
	_check(per.size() >= 2, "after the hunt the birds stayed piled on one hero")
	mgr.end_battle(true)
	_free(s)

# Taunt beats the mark; the bird rejoins the hunt when the taunt ends.
func _test_taunt_wins() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var birds: Array = []
	for x in 3:
		birds.append(_bird(mgr, g, Vector2i(x * 2, 1)))
	var a = _hero(mgr, g, Vector2i(0, 7)); var riot = _hero(mgr, g, Vector2i(6, 7))
	_arm(mgr, birds, [a, riot])
	_kill(birds[0], a)
	birds[1].taunt_time = 2.0; birds[1].taunt_source = riot
	_check(mgr._choose_target(birds[1], [a, riot]) == riot, "taunt did not override the hunt mark")
	birds[1].taunt_time = 0.0
	_check(mgr._choose_target(birds[1], [a, riot]) == a, "bird did not return to the mark after the taunt")
	mgr.end_battle(true)
	_free(s)

# The last bird keeps hunting alone; its death clears all hunt state.
func _test_last_bird() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var b0 = _bird(mgr, g, Vector2i(1, 1)); var b1 = _bird(mgr, g, Vector2i(5, 1))
	var a = _hero(mgr, g, Vector2i(3, 7))
	_arm(mgr, [b0, b1], [a])
	_kill(b0, a)
	_check(mgr.gale_hunt_info(false).get("mark") == a, "the last bird does not hunt")
	_kill(b1, a)
	_check(mgr.gale_hunt_info(false).is_empty() and not a.has_meta("gale_hunted_t") and mgr._gale_mark_fx.is_empty(),
		"last bird died but the hunt state / badge / mark VFX remained")
	mgr.end_battle(true)
	_free(s)

# Cyclone Shove: hits the bird's OWN target, only from a strike square, lands at
# the contact beat (not on cast), cancels if the caster is stunned, and a shoved
# hero is locked out for GALE_SHOVE_LOCKOUT.
func _test_shove_rules() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var bird = _bird(mgr, g, Vector2i(4, 4))
	var near = _hero(mgr, g, Vector2i(5, 5))     # diagonal, nearest by Euclid tie
	var mine = _hero(mgr, g, Vector2i(4, 5))     # orthogonal: the bird's target
	var far = _hero(mgr, g, Vector2i(4, 8))
	_arm(mgr, [bird], [near, mine, far])
	bird.skill_cd_time = 0.0
	bird.target_unit = far
	_check(not mgr._skill_trigger_ready(bird, [near, mine, far]), "shove fired at a target 4 tiles away (no range check)")
	bird.target_unit = mine
	_check(mgr._skill_trigger_ready(bird, [near, mine, far]), "shove not ready on an adjacent target")
	var hp0: int = mine.current_hp; var near0: int = near.current_hp
	mgr._use_skill(bird, [near, mine, far], [bird])
	_check(mine.current_hp == hp0, "shove damage landed on cast instead of at the contact beat")
	_check(not mgr._skill_trigger_ready(bird, [near, mine, far]), "a second wind-up could start mid wind-up")
	var steps := int(ceil(AutoBattleManager.GALE_SHOVE_CONTACT / DT)) + 1
	for i in steps: mgr._tick_gale(DT)
	_check(mine.current_hp < hp0, "shove never landed on the bird's own target")
	_check(near.current_hp == near0, "shove hit the nearest hero instead of the bird's target")
	_check(mine.grid_position == Vector2i(4, 6), "target not pushed one tile on (at %s)" % mine.grid_position)
	_check(g.occupied_cells.get(Vector2i(4, 6)) == mine and not g.occupied_cells.has(Vector2i(4, 5)),
		"shove left the grid disagreeing with the hero's position")
	# Lockout: another bird can't shove the same hero for 3 s.
	var bird2 = _bird(mgr, g, Vector2i(3, 6))
	mgr.enemy_units.append(bird2); bird2.target_unit = mine; bird2.skill_cd_time = 0.0
	_check(not mgr._skill_trigger_ready(bird2, [mine]), "a second bird could shove inside the lockout")
	mgr._tick_gale(AutoBattleManager.GALE_SHOVE_LOCKOUT + 0.05)
	_check(mgr._skill_trigger_ready(bird2, [mine]), "lockout never expired")
	# Stun mid wind-up cancels it: no damage, lockout released.
	var hp1: int = mine.current_hp
	bird2.target_unit = mine
	mgr._use_skill(bird2, [mine], [bird2])
	bird2.stun_time = 1.0
	for i in steps: mgr._tick_gale(DT)
	_check(mine.current_hp == hp1, "a stunned bird's shove still landed")
	_check(not mgr._gale_shove_lock.has(mine) and not bird2.has_meta("gale_shove_winding"), "cancelled shove left a lockout / wind-up behind")
	mgr.end_battle(true)
	_free(s)

# The real loop: birds never park, strikes land, pause freezes everything, and
# every hero keeps sole ownership of its square while birds fly over it.
func _test_flight_loop() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var birds: Array = []
	for x in 4:
		var bd = _bird(mgr, g, Vector2i(x * 2 + 1, 1))
		bd.max_hp = 999999; bd.current_hp = 999999
		birds.append(bd)
	var heroes: Array = []
	for x in 4:
		heroes.append(_hero(mgr, g, Vector2i(x * 2, 6)))
	mgr.start_battle()
	mgr.time_scale = 1.0
	var still := {}; var worst := {}; var moving_frames := {}
	for bd in birds: still[bd] = 0.0; worst[bd] = 0.0; moving_frames[bd] = 0
	var dmg0 := 0
	for h in heroes: dmg0 += h.current_hp
	var grid_ok := true
	var frames := int(20.0 / DT)
	for f in frames:
		mgr._process(DT)
		for bd in birds:
			if bd.is_moving:
				moving_frames[bd] += 1; still[bd] = 0.0
			else:
				still[bd] += DT; worst[bd] = maxf(worst[bd], still[bd])
		for h in heroes:
			if g.occupied_cells.get(h.grid_position) != h: grid_ok = false
		for bd in birds:
			if g.occupied_cells.values().has(bd): grid_ok = false
	var dmg1 := 0
	for h in heroes: dmg1 += h.current_hp
	var worst_all := 0.0; var frac_min := 1.0
	for bd in birds:
		worst_all = maxf(worst_all, worst[bd])
		frac_min = minf(frac_min, float(moving_frames[bd]) / float(frames))
	print("[probe] flight: longest stationary %.2fs, min moving fraction %.0f%%, hero dmg taken %d" % [worst_all, frac_min * 100.0, dmg0 - dmg1])
	_check(worst_all <= 1.0, "a bird sat still for %.2fs — flight must be continuous" % worst_all)
	_check(frac_min >= 0.6, "a bird was moving only %.0f%% of the fight" % (frac_min * 100.0))
	_check(dmg0 - dmg1 > 0, "flying birds dealt no damage in 20s")
	_check(grid_ok, "a hero lost its own cell / a bird took solid ownership during flight")
	# Pause: positions, hunt timer and wind-ups all freeze.
	_kill(birds[0], heroes[0])
	var t0: float = float(mgr.gale_hunt_info(false).get("t", -1.0))
	var pos0: Array = []
	for bd in birds.slice(1): pos0.append(bd.position)
	mgr.paused = true
	for i in 30: mgr._process(DT)
	var pos1: Array = []
	for bd in birds.slice(1): pos1.append(bd.position)
	_check(pos0 == pos1, "birds moved while paused")
	_check(is_equal_approx(float(mgr.gale_hunt_info(false).get("t", -2.0)), t0), "hunt timer ran while paused")
	mgr.paused = false
	# 4x speed advances the hunt 4x as fast.
	mgr.time_scale = 4.0
	mgr._process(0.25)
	_check(absf(float(mgr.gale_hunt_info(false).get("t", 0.0)) - (t0 - 1.0)) < 0.05, "hunt timer ignores the pace setting")
	# Every bird dies over heroes: heroes keep their squares, the pass layer empties.
	for bd in birds:
		if bd.current_hp > 0:
			_kill(bd, heroes[1])
		g.purge_unit(bd)   # what main_game / the arena do on `died`
	var intact := true
	for h in heroes:
		if g.occupied_cells.get(h.grid_position) != h: intact = false
	_check(intact and g.passing_cells.is_empty(), "bird deaths disturbed hero cells or left passing cells behind")
	mgr.end_battle(false)
	_free(s)

# Battle reset clears every piece of flock state, including metas on heroes that
# persist into the next round.
func _test_reset() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var birds: Array = []
	for x in 3:
		birds.append(_bird(mgr, g, Vector2i(x * 2, 1)))
	var a = _hero(mgr, g, Vector2i(2, 7))
	_arm(mgr, birds, [a])
	_kill(birds[0], a)
	birds[1].target_unit = a; birds[1].grid_position = Vector2i(2, 6)
	g.purge_unit(birds[1]); g.place_unit(birds[1], Vector2i(2, 6))
	mgr._gale_shove_lock[a] = 2.0
	mgr.end_battle(true)
	_check(mgr._gale_hunt.is_empty() and mgr._gale_shove_lock.is_empty() and mgr._gale_shoves.is_empty(),
		"end_battle left hunt / shove state behind")
	_check(not a.has_meta("gale_hunted_t") and not birds[1].has_meta("scatter_t"), "end_battle left flock metas on units")
	_free(s)
