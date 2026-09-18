extends Node
# ══════════════════════════════════════════════════════════════════════════════
# PLAYTEST WARP SMOKE (2026-08-04) — F6/F7 round warp in main_game.gd.
#
# The warp exists so boss/elite beats can be WATCHED (the arena harness is
# headless and can only ever verify balance). If it silently lands on the wrong
# round, or fields a round-1-sized team at round 40, every feel judgement made
# with it is worthless — so it gets asserted like any other mechanic.
#
# Asserts: F6 snaps to the elite/boss cadence (5,10,15,20…) from any starting
# point, heroes and team size actually scale, ±1 works, and it clamps at 1.
#
# Run:  godot --headless res://scenes/warp_smoke.tscn
# Exit code 0 = pass, 1 = fail.
# ══════════════════════════════════════════════════════════════════════════════

var _fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)

func _ready() -> void:
	var mg := (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	for i in range(30):
		await get_tree().process_frame

	mg.max_player_units = maxi(mg.max_player_units, 2)
	mg._recruit_hero(UnitBase.UnitClass.BLOODHOUND,
			UnitFactory.element_for_class(UnitBase.UnitClass.BLOODHOUND), {})
	mg._recruit_hero(UnitBase.UnitClass.BOUNCER,
			UnitFactory.element_for_class(UnitBase.UnitClass.BOUNCER), {})
	await get_tree().process_frame

	var heroes: Array = mg.player_units.filter(func(u): return u and is_instance_valid(u))
	_check(heroes.size() > 0, "no heroes recruited — the rest of this test is meaningless")
	if heroes.is_empty():
		_report()
		return
	var start_level: int = heroes[0].level
	var start_team: int = mg.max_player_units

	# ── F6 walks the elite/boss cadence exactly ──────────────────────────────
	for expected in [5, 10, 15, 20]:
		mg._debug_warp_rounds(5)
		await get_tree().process_frame
		_check(mg.game_state.battle_round == expected,
				"F6 landed on round %d, expected %d" % [mg.game_state.battle_round, expected])

	# ── heroes and team size actually scaled ─────────────────────────────────
	var lvl20: int = heroes[0].level
	_check(lvl20 > start_level,
			"heroes did not scale on warp (still level %d at round 20)" % lvl20)
	_check(lvl20 == int(round(20.0 * mg.DEBUG_WARP_LEVEL_PER_ROUND)),
			"hero level %d is off the documented 0.8x curve for round 20" % lvl20)
	_check(mg.max_player_units > start_team,
			"team size never grew (%d) — a round-20 wave against a round-1 team" % mg.max_player_units)
	_check(heroes[0].current_hp == heroes[0].max_hp,
			"warped in at partial HP (%d/%d)" % [heroes[0].current_hp, heroes[0].max_hp])

	# ── an odd F7 nudge must not desync the F6 cadence ───────────────────────
	mg._debug_warp_rounds(1)
	await get_tree().process_frame
	_check(mg.game_state.battle_round == 21,
			"F7 +1 landed on %d, expected 21" % mg.game_state.battle_round)
	mg._debug_warp_rounds(5)
	await get_tree().process_frame
	_check(mg.game_state.battle_round == 25,
			"F6 after an odd nudge landed on %d, expected 25 (cadence lost)"
			% mg.game_state.battle_round)

	# ── backwards, and the floor ─────────────────────────────────────────────
	mg._debug_warp_rounds(-5)
	await get_tree().process_frame
	_check(mg.game_state.battle_round == 20,
			"Shift+F6 landed on %d, expected 20" % mg.game_state.battle_round)

	for i in range(10):
		mg._debug_warp_rounds(-5)
		await get_tree().process_frame
	_check(mg.game_state.battle_round >= 1,
			"warped below round 1 (%d)" % mg.game_state.battle_round)

	_report()

func _report() -> void:
	if _fails.is_empty():
		print("WARP_SMOKE: ALL PASS")
		get_tree().quit(0)
	else:
		for f in _fails:
			print("WARP_SMOKE: FAIL -> %s" % f)
		print("WARP_SMOKE: %d FAILURE(S)" % _fails.size())
		get_tree().quit(1)
