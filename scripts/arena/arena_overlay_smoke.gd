extends Node
# ══════════════════════════════════════════════════════════════════════════════
# ARENA OVERLAY SMOKE — BOSS_SPECTACLE_PLAN.md §2e, Slice A2.
# Verifies the board-wide ArenaOverlay layer wires correctly to Skyrender's
# aloft cycle (the plan's "0/3 reads" case) without touching any balance path.
#
# Asserts:
#   1. start_battle() spawns exactly one ArenaOverlay, idle (alpha 0, no state)
#   2. going aloft calls fade_in("windswept") synchronously (_state flips)
#   3. the alpha tween actually ramps up to ~1.0 within FADE_TIME
#   4. slamming back down calls fade_out() and the tween settles to alpha 0 /
#      state "" — it doesn't get stuck on
#   5. end_battle() frees the overlay and clears the manager's reference
#
# Run:  godot --headless --fixed-fps 30 res://scenes/arena_overlay_smoke.tscn
# Exit code 0 = pass, 1 = fail.
# ══════════════════════════════════════════════════════════════════════════════

var _fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)

func _ready() -> void:
	var mgr = load("res://scripts/combat/auto_battle_manager.gd").new()
	var grid = load("res://scripts/combat/battle_grid.gd").new()
	add_child(grid)
	add_child(mgr)
	mgr.battle_grid = grid
	var sec := Node2D.new()
	add_child(sec)
	mgr.skill_effect_container = sec
	await get_tree().process_frame

	var boss = EnemyFactory.create_skyrender(14)
	var hero = UnitFactory.create_unit(UnitBase.UnitClass.BLOODHOUND,
			UnitFactory.element_for_class(UnitBase.UnitClass.BLOODHOUND), true)
	for u in [boss, hero]:
		add_child(u)
	grid.place_unit(boss, Vector2i(3, 1))
	grid.place_unit(hero, Vector2i(3, 6))
	boss.grid_position = Vector2i(3, 1)
	hero.grid_position = Vector2i(3, 6)
	mgr.enemy_units = [boss]
	mgr.player_units = [hero]

	# ── 1: start_battle() spawns exactly one, idle overlay ──────────────────
	mgr.start_battle()
	await get_tree().process_frame
	_check(mgr.arena_overlay != null and is_instance_valid(mgr.arena_overlay),
			"start_battle() did not spawn arena_overlay")
	_check(mgr.arena_overlay._state == "",
			"arena_overlay has a state before any boss beat fired")
	_check(mgr.arena_overlay._alpha <= 0.0,
			"arena_overlay is already visible before any boss beat fired")

	# start_battle() re-collects units from the scene tree via collect_units(),
	# which would drop our hand-placed roster — restore it the way long_fall_smoke
	# does, driving the passive tick directly rather than through collect_units().
	mgr.enemy_units = [boss]
	mgr.player_units = [hero]

	# ── 2/3: force the ground->aloft flip and check the hook fires ──────────
	boss.set_meta("skyrender_aloft", false)
	boss.set_meta("skyrender_timer", mgr.SKYRENDER_GROUND_TIME - 0.05)
	mgr._tick_mob_passive(boss, mgr.player_units, mgr.enemy_units, 0.1)
	_check(bool(boss.get_meta("skyrender_aloft", false)),
			"forced tick did not flip skyrender_aloft to true")
	_check(mgr.arena_overlay._state == "windswept",
			"going aloft did not call arena_overlay.fade_in('windswept')")

	var waited := 0.0
	while waited < ArenaOverlay.FADE_TIME + 0.3:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_check(mgr.arena_overlay._alpha > 0.9,
			"arena_overlay alpha (%.2f) never ramped up after fade_in" % mgr.arena_overlay._alpha)

	# ── 4: force the aloft->ground flip and check it fades back out ─────────
	boss.set_meta("skyrender_aloft", true)
	boss.set_meta("skyrender_timer", mgr.SKYRENDER_ALOFT_TIME - 0.05)
	mgr._tick_mob_passive(boss, mgr.player_units, mgr.enemy_units, 0.1)
	_check(not bool(boss.get_meta("skyrender_aloft", false)),
			"forced tick did not flip skyrender_aloft back to false")

	waited = 0.0
	while waited < ArenaOverlay.FADE_TIME + 0.3:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_check(mgr.arena_overlay._alpha <= 0.01,
			"arena_overlay alpha (%.2f) never faded back out after landing" % mgr.arena_overlay._alpha)
	_check(mgr.arena_overlay._state == "",
			"arena_overlay state stuck on '%s' after landing — it would read as a bug on the next boss"
			% mgr.arena_overlay._state)

	# ── 5: end_battle() frees it and clears the reference ───────────────────
	mgr.end_battle(true)
	_check(mgr.arena_overlay == null,
			"end_battle() did not clear the arena_overlay reference")

	# ── Report ───────────────────────────────────────────────────────────────
	if _fails.is_empty():
		print("ARENA_OVERLAY_SMOKE: ALL PASS")
		get_tree().quit(0)
	else:
		for f in _fails:
			print("ARENA_OVERLAY_SMOKE: FAIL -> %s" % f)
		print("ARENA_OVERLAY_SMOKE: %d FAILURE(S)" % _fails.size())
		get_tree().quit(1)
