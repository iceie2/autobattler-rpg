extends Node

# Isolated Wind-Up Bot kit probe — drives the REAL AutoBattleManager, because
# every bug this guards against was invisible to the arena's generic probe:
# that one reports NO_KIT for a mob with an empty ultimate_name and never looks
# at live behaviour.
#
# Run: godot --headless --fixed-fps 30 res://scenes/tools/windup_bot_kit_probe.tscn

var _failures: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _mk(mgr, grid, unit, cell: Vector2i, player: bool):
	add_child(unit)
	unit.battle_manager = mgr
	unit.is_player_unit = player
	assert(grid.place_unit(unit, cell))
	unit.grid_position = cell
	return unit

func _fresh() -> Dictionary:
	var grid := BattleGrid.new()
	var mgr := AutoBattleManager.new()
	var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null)
	mgr.skill_effect_container = fx
	return {"grid": grid, "mgr": mgr}

func _ready() -> void:
	await _test_knockup_flies_and_lands()
	_test_no_accidental_ultimate()
	_test_range_gate()
	_test_punch_is_committed()
	_test_interrupt_and_whiff()
	_test_overclock_steps()
	_test_overclock_resets()
	_test_auto_contact()
	_test_shared_key_mobs_unchanged()

	if _failures.is_empty():
		print("WINDUP_BOT_KIT_PROBE: ALL PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("FAIL: ", f)
		print("WINDUP_BOT_KIT_PROBE: %d FAILURE(S)" % _failures.size())
		get_tree().quit(1)

# ── The knock-up actually leaves the ground and comes back ───────────────────
# Every failure mode here is SILENT: a knock-up that never moves the sprite, or
# one that leaves a hero parked in mid-air, both look like a working build in
# the logs. So this asserts the sprite offset really rises and really returns,
# and that grid_position never moved (a real displacement would strand a cell —
# see CONVENTIONS §1 phantom-cell test).
func _test_knockup_flies_and_lands() -> void:
	var s := _fresh()
	var mgr = s["mgr"]
	var bot = _mk(mgr, s["grid"], EnemyFactory.create_windup_bot_normal(), Vector2i(2, 2), false)
	var vic = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.enemy_units = [bot]; mgr.player_units = [vic]
	vic.max_hp = 99999; vic.current_hp = 99999      # must survive to be tossed
	var cell_before: Vector2i = vic.grid_position
	await get_tree().process_frame

	mgr._use_skill(bot, mgr.player_units, mgr.enemy_units)
	mgr._tick_windup_punches(AutoBattleManager.WINDUP_PUNCH_CONTACT + 0.01)
	var stun: float = vic.stun_time
	_check(stun > 0.0, "setup: victim was not stunned, so no knock-up could start")

	# Airborne: sample partway through the stun and require real altitude.
	var peak_seen := 0.0
	var spin_min := 1.0
	var spin_negative_runs := 0
	var was_negative := false
	var t := 0.0
	while t < stun * 0.98:
		await get_tree().process_frame
		t += get_process_delta_time()
		peak_seen = maxf(peak_seen, -vic._toss_offset.y)
		var sx: float = vic._updraft_spin_x
		spin_min = minf(spin_min, sx)
		# Count entries into the back half of the flip, not frames spent there.
		if sx < 0.0 and not was_negative:
			spin_negative_runs += 1
		was_negative = sx < 0.0
	_check(peak_seen > 20.0,
		"knock-up never lifted the target (peak %.1f px) — the punt is invisible" % peak_seen)
	# Height is a deliberate value (raised 50% on 2026-09-16 for readability);
	# assert the arc really reaches it rather than trusting the tween.
	_check(peak_seen > VisualUnit.KNOCKUP_PEAK_HEIGHT * 0.7,
		"knock-up peaked at %.1f px, well short of KNOCKUP_PEAK_HEIGHT %.0f"
			% [peak_seen, VisualUnit.KNOCKUP_PEAK_HEIGHT])
	# Exactly ONE 360: the spin layer is a cos() scale flip, so across the whole
	# airborne window it must pass through negative (back of the flip) and come
	# home to +1. Two turns would pass through negative twice and read as a
	# tumble instead of a single deliberate flip.
	_check(spin_min < -0.85,
		"spin never reached the back of the flip (min scale %.2f) — that is not a full 360" % spin_min)
	_check(spin_negative_runs == 1,
		"sprite crossed into the back half %d times; exactly 1 means one clean 360"
			% spin_negative_runs)
	_check(vic.grid_position == cell_before,
		"knock-up moved the victim's grid cell %s -> %s; it must be purely visual"
			% [cell_before, vic.grid_position])

	# Landed: by the time the stun expires the sprite must be back on the ground.
	while t < stun + 0.4:
		await get_tree().process_frame
		t += get_process_delta_time()
	_check(absf(vic._toss_offset.y) < 1.0,
		"target never came back down (offset %.1f px) — it is parked in mid-air"
			% vic._toss_offset.y)
	_check(vic.grid_position == cell_before,
		"victim did not land back in its own square")

# ── The accidental ultimate ───────────────────────────────────────────────────
func _test_no_accidental_ultimate() -> void:
	var bot := EnemyFactory.create_windup_bot_normal()
	add_child(bot)
	_check(bot.ultimate_charge_max == 0,
		"bot still inherits an ultimate pool (%d) — the WARRIOR fallback re-fires its skill"
			% bot.ultimate_charge_max)
	_check(bot.ultimate_name == "", "bot unexpectedly declares an ultimate name")
	# _charge_ultimate must be a no-op, so no strip ever fills.
	bot._charge_ultimate(9999)
	_check(not bot.ultimate_ready, "bot became ultimate_ready despite declaring no ultimate")
	_check(bot.ultimate_charge == 0, "bot accumulated ultimate charge (%d)" % bot.ultimate_charge)

# ── Melee adjacency is actually enforced ──────────────────────────────────────
func _test_range_gate() -> void:
	var s := _fresh()
	var mgr = s["mgr"]
	var bot = _mk(mgr, s["grid"], EnemyFactory.create_windup_bot_normal(), Vector2i(2, 2), false)
	var far = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(6, 2), true)
	mgr.enemy_units = [bot]; mgr.player_units = [far]
	_check(not mgr._skill_trigger_ready(bot, mgr.player_units),
		"Wind-Up Punch triggered on a target 4 tiles away — it must require melee adjacency")
	var near = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.player_units = [near, far]
	_check(mgr._skill_trigger_ready(bot, mgr.player_units),
		"Wind-Up Punch did not trigger on an adjacent target")

# ── Committed cast: nothing resolves before visible contact ───────────────────
func _test_punch_is_committed() -> void:
	var s := _fresh()
	var mgr = s["mgr"]
	var bot = _mk(mgr, s["grid"], EnemyFactory.create_windup_bot_normal(), Vector2i(2, 2), false)
	var vic = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.enemy_units = [bot]; mgr.player_units = [vic]
	var hp0: int = vic.current_hp

	mgr._use_skill(bot, mgr.player_units, mgr.enemy_units)
	_check(vic.current_hp == hp0, "Wind-Up Punch dealt damage before its contact frame")
	_check(vic.stun_time == 0.0, "Wind-Up Punch stunned before its contact frame")
	_check(bot.get_meta("hill_giant_committed", false),
		"bot is not flagged committed during the wind-up — it can walk away mid-cast")

	# Mid-wind-up: still nothing.
	mgr._tick_windup_punches(AutoBattleManager.WINDUP_PUNCH_CONTACT * 0.5)
	_check(vic.current_hp == hp0, "damage resolved halfway through the wind-up")

	mgr._tick_windup_punches(AutoBattleManager.WINDUP_PUNCH_CONTACT * 0.5 + 0.01)
	var removed: int = hp0 - vic.current_hp
	_check(removed > 0, "Wind-Up Punch never dealt damage at contact")
	_check(not bot.get_meta("hill_giant_committed", false),
		"committed flag was never released after contact")

	# Damage accounting must be POST-MITIGATION, not the pre-mitigation raw.
	var raw: int = int(float(bot.attack_damage) * bot.skill_damage_multiplier)
	_check(bot.damage_dealt == removed,
		"damage meter recorded %d but %d HP was actually removed (raw would be %d)"
			% [bot.damage_dealt, removed, raw])

	# Stun: 1.5s nominal, tenacity-scaled. The knock-up must match it exactly.
	var expect: float = vic.tenacity_scaled(1.5)
	_check(abs(vic.stun_time - expect) < 0.001,
		"stun was %.3fs, expected %.3fs (1.5s scaled by tenacity %d)"
			% [vic.stun_time, expect, vic.tenacity])
	_check(vic.stun_time > 1.0,
		"stun %.3fs is not longer than the old 1.0s — the 1.5s change did not land" % vic.stun_time)

# ── Edge cases: interrupted cast, and a target that leaves ────────────────────
func _test_interrupt_and_whiff() -> void:
	# Stunning the bot mid-wind-up must cancel the punch outright.
	var s := _fresh()
	var mgr = s["mgr"]
	var bot = _mk(mgr, s["grid"], EnemyFactory.create_windup_bot_normal(), Vector2i(2, 2), false)
	var vic = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.enemy_units = [bot]; mgr.player_units = [vic]
	var hp0: int = vic.current_hp
	mgr._use_skill(bot, mgr.player_units, mgr.enemy_units)
	bot.stun_time = 2.0                              # interrupt
	mgr._tick_windup_punches(AutoBattleManager.WINDUP_PUNCH_CONTACT + 0.01)
	_check(vic.current_hp == hp0,
		"an interrupted (stunned) bot still landed its Wind-Up Punch — no counterplay window")
	_check(not bot.get_meta("hill_giant_committed", false),
		"interrupted cast left the bot permanently flagged committed (it would never act again)")

	# Target walks out of reach during the wind-up → clean whiff, no damage.
	var s2 := _fresh()
	var mgr2 = s2["mgr"]
	var bot2 = _mk(mgr2, s2["grid"], EnemyFactory.create_windup_bot_normal(), Vector2i(2, 2), false)
	var vic2 = _mk(mgr2, s2["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr2.enemy_units = [bot2]; mgr2.player_units = [vic2]
	var hp2: int = vic2.current_hp
	mgr2._use_skill(bot2, mgr2.player_units, mgr2.enemy_units)
	vic2.grid_position = Vector2i(7, 2)              # stepped away
	mgr2._tick_windup_punches(AutoBattleManager.WINDUP_PUNCH_CONTACT + 0.01)
	_check(vic2.current_hp == hp2,
		"target that left melee range during the wind-up was still hit")
	_check(vic2.stun_time == 0.0, "out-of-range target was still stunned")

	# Dead target mid-wind-up must not crash or resolve.
	var s3 := _fresh()
	var mgr3 = s3["mgr"]
	var bot3 = _mk(mgr3, s3["grid"], EnemyFactory.create_windup_bot_normal(), Vector2i(2, 2), false)
	var vic3 = _mk(mgr3, s3["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr3.enemy_units = [bot3]; mgr3.player_units = [vic3]
	mgr3._use_skill(bot3, mgr3.player_units, mgr3.enemy_units)
	vic3.current_hp = 0
	mgr3._tick_windup_punches(AutoBattleManager.WINDUP_PUNCH_CONTACT + 0.01)
	_check(bot3.damage_dealt == 0, "bot credited damage against an already-dead target")

# ── Overclock: discrete, capped, and matches the printed description ──────────
func _test_overclock_steps() -> void:
	var s := _fresh()
	var mgr = s["mgr"]
	var bot = _mk(mgr, s["grid"], EnemyFactory.create_windup_bot_normal(), Vector2i(2, 2), false)
	mgr.enemy_units = [bot]; mgr.player_units = []
	bot.set_meta("oc_time", 0.0)

	# The contract is the mapping battle-time -> bonus. Drive oc_time directly
	# and tick with dt=0, so this asserts the mapping exactly instead of
	# measuring float drift in the probe's own accumulator (summing 0.05s steps
	# lands on 2.9999998 at the 3s boundary and tests nothing useful).
	var expectations := [
		[0.0, 0.00], [2.9, 0.00], [3.0, 0.05], [5.9, 0.05],
		[6.0, 0.10], [15.0, 0.25], [29.9, 0.45], [30.0, 0.50], [60.0, 0.50],
	]
	for e in expectations:
		var want_t: float = e[0]
		var want: float = e[1]
		bot.set_meta("oc_time", want_t)
		mgr._tick_passive(bot, mgr.player_units, mgr.enemy_units, 0.0)
		var got: float = float(bot.get_meta("oc_bonus", -1.0))
		_check(abs(got - want) < 0.0001,
			"Overclock at %.1fs was +%.1f%%, expected +%.1f%% (description promises +5%% every 3s)"
				% [want_t, got * 100.0, want * 100.0])
		_check(abs(float(bot.get_meta("mob_aspd_bonus", -1.0)) - want) < 0.0001,
			"oc_bonus and mob_aspd_bonus disagree at %.1fs" % want_t)
	# The cap must be the stated +50%, reached at exactly 30s.
	_check(float(bot.get_meta("oc_bonus", 0.0)) == 0.50,
		"Overclock exceeded or missed its +50%% cap (%.3f)" % float(bot.get_meta("oc_bonus", 0.0)))

func _test_overclock_resets() -> void:
	var s := _fresh()
	var mgr = s["mgr"]
	var bot = _mk(mgr, s["grid"], EnemyFactory.create_windup_bot_normal(), Vector2i(2, 2), false)
	mgr.enemy_units = [bot]; mgr.player_units = []
	# Wind it fully up, as a previous round would have.
	for i in range(700):
		mgr._tick_passive(bot, mgr.player_units, mgr.enemy_units, 0.05)
	_check(float(bot.get_meta("oc_bonus", 0.0)) == 0.50, "setup: bot did not reach max Overclock")
	# A new battle must start it cold.
	mgr._init_unit_timers()
	_check(float(bot.get_meta("oc_bonus", -1.0)) == 0.0,
		"oc_bonus survived battle init (%.3f) — a reused bot starts pre-wound"
			% float(bot.get_meta("oc_bonus", -1.0)))
	_check(float(bot.get_meta("mob_aspd_bonus", -1.0)) == 0.0,
		"mob_aspd_bonus survived battle init — the haste leaks into the next round")
	_check(float(bot.get_meta("oc_time", -1.0)) == 0.0, "oc_time survived battle init")

# ── Auto: damage lands with the lunge, and is counted post-mitigation ─────────
func _test_auto_contact() -> void:
	var s := _fresh()
	var mgr = s["mgr"]
	var bot = _mk(mgr, s["grid"], EnemyFactory.create_windup_bot_normal(), Vector2i(2, 2), false)
	var vic = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.enemy_units = [bot]; mgr.player_units = [vic]
	bot.crit_chance = 0.0                            # determinism
	var hp0: int = vic.current_hp
	bot.attack(vic)
	_check(vic.current_hp == hp0, "auto dealt damage before the lunge reached the target")
	mgr._tick_windup_autos(AutoBattleManager.WINDUP_AUTO_CONTACT + 0.01)
	var removed: int = hp0 - vic.current_hp
	_check(removed > 0, "auto never dealt damage at contact")
	_check(bot.damage_dealt == removed,
		"auto damage meter recorded %d but %d HP was removed" % [bot.damage_dealt, removed])

	# The manager applies on-hit passives immediately after unit.attack(); the
	# delayed auto applies them again at contact. The bot MUST be excluded from
	# the immediate call or every landed-hit passive fires twice per swing
	# (Sheildor carries the same exclusion for the same reason).
	var src: String = FileAccess.get_file_as_string("res://scripts/combat/auto_battle_manager.gd")
	var guarded: int = src.count("and not _has_delayed_auto(unit)")
	_check(guarded == 2,
		"expected 2 _has_delayed_auto exclusions around _apply_on_hit_passives, found %d — on-hit passives would double-apply"
			% guarded)

# ── The shared `windup_punch` key must not have retuned its other users ───────
func _test_shared_key_mobs_unchanged() -> void:
	for maker in [["Minotaur", EnemyFactory.create_minotaur()],
			["Storm Giant", EnemyFactory.create_storm_giant()]]:
		var name: String = maker[0]
		var mob = maker[1]
		add_child(mob)
		_check(str(mob.get_meta("mob_skill", "")) == "windup_punch",
			"%s no longer uses the shared windup_punch key — probe is stale" % name)
		_check(not bool(mob.get_meta("windup_bot", false)),
			"%s was wrongly marked as a Wind-Up Bot (it would get the knock-up and clockwork VFX)" % name)
		_check(float(mob.get_meta("windup_stun", 1.0)) == 1.0,
			"%s stun changed from 1.0s — polishing the bot must not retune it" % name)

	# And the knock-up itself only resolves through a real bot.
	var s := _fresh()
	var mgr = s["mgr"]
	var mino = _mk(mgr, s["grid"], EnemyFactory.create_minotaur(), Vector2i(2, 2), false)
	var vic = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(4, 2), true)
	mgr.enemy_units = [mino]; mgr.player_units = [vic]
	mgr._use_skill(mino, mgr.player_units, mgr.enemy_units)
	mgr._tick_windup_punches(AutoBattleManager.WINDUP_PUNCH_CONTACT + 0.01)
	if vic.current_hp > 0 and vic.stun_time > 0.0:
		_check(abs(vic.stun_time - vic.tenacity_scaled(1.0)) < 0.001,
			"Minotaur Gore Rush stun is %.3fs, expected the unchanged 1.0s scaled" % vic.stun_time)
