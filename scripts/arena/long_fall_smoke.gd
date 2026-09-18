extends Node
# ══════════════════════════════════════════════════════════════════════════════
# THE LONG FALL SMOKE — Skyrender's second beat.
# REDESIGNED 2026-08-04 per user feedback ("sudden with no logic"): the boss now
# visibly carries the victim to the edge before throwing, is stunned for the
# whole carry (that's the cost, replacing landing damage), and the victim lands
# at a RANDOM open cell in its own team zone rather than its origin square.
#
# Asserts:
#   1. it fires on the top damage dealer (Arcfang's targeting rule)
#   2. the victim is actually removed from the grid while airborne (this build
#      can no longer claim "the square is never vacated" — that's the trade)
#   3. untargetable + stunned for the whole sequence
#   4. the BOSS is stunned too, for LONG_FALL_BOSS_BUSY — the carry's cost
#   5. it lands somewhere IN the team zone, alive, at an OPEN cell, un-stunned
#      afterward, at full stats (still no landing damage)
#   6. the visual toss offset returns to zero on both the victim and the boss
#   7. an interrupted fall (round ends mid-flight) is put back on the grid by
#      _init_unit_timers, not left floating off-grid forever
#   8. the passive tick path actually reaches the beat, and never while aloft
#
# REDESIGNED AGAIN 2026-08-04: the grab is no longer instant at range — the
# boss must WALK to be adjacent to its target first (real pathfinding, real
# footsteps), and its basic attack range dropped to 1 to match. New asserts:
#   9. begin() picks a target and enters "approaching" without grabbing yet
#  10. the approach tick actually moves the boss closer over time
#  11. once adjacent, the approach hands off into the existing grab chain
#  12. while approaching, the boss's normal target/attack/move path is a no-op
#
# Run:  godot --headless --fixed-fps 30 res://scenes/long_fall_smoke.tscn
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
	await get_tree().process_frame

	# ── Stage: one Skyrender vs two heroes ───────────────────────────────────
	var boss = EnemyFactory.create_skyrender(14)
	var carry = UnitFactory.create_unit(UnitBase.UnitClass.BLOODHOUND,
			UnitFactory.element_for_class(UnitBase.UnitClass.BLOODHOUND), true)
	var other = UnitFactory.create_unit(UnitBase.UnitClass.BOUNCER,
			UnitFactory.element_for_class(UnitBase.UnitClass.BOUNCER), true)
	for u in [boss, carry, other]:
		add_child(u)

	var carry_cell := Vector2i(3, 6)
	var other_cell := Vector2i(5, 6)
	grid.place_unit(boss, Vector2i(3, 1))
	grid.place_unit(carry, carry_cell)
	grid.place_unit(other, other_cell)
	boss.grid_position = Vector2i(3, 1)
	carry.grid_position = carry_cell
	other.grid_position = other_cell

	mgr.enemy_units = [boss]
	mgr.player_units = [carry, other]

	# Make the carry unambiguously the top damage dealer.
	carry.damage_dealt = 5000
	other.damage_dealt = 10
	var carry_atk: int = carry.attack_damage
	var carry_hp: int = carry.current_hp

	# ── 9: begin() picks the top damage dealer and only starts the approach ──
	var boss_start: Vector2i = boss.grid_position
	mgr._skyrender_long_fall_begin(boss, mgr.player_units)
	_check(boss.get_meta("long_fall_state", "") == "approaching",
			"begin() did not enter the approaching state")
	_check(boss.get_meta("long_fall_target", null) == carry,
			"begin() picked the wrong target — should be the top damage dealer")
	_check(not carry.has_meta("long_fall_active"),
			"begin() grabbed immediately instead of walking over first")

	# ── 12: while approaching, the normal per-unit tick is a no-op (no attack,
	# no retargeting) — only _skyrender_long_fall_approach_tick may move it ────
	boss.target_unit = null
	mgr._tick_unit(boss, 0.05)
	_check(boss.get_meta("long_fall_state", "") == "approaching",
			"a normal _tick_unit call disturbed the approaching state")
	_check(boss.target_unit == null,
			"boss picked a normal attack target while it should be walking to its Long Fall victim")

	# ── 10/11: simulate the approach — it must actually move, then hand off
	# into the existing grab chain once adjacent ──────────────────────────────
	var moved_at_least_once := false
	var sim_t := 0.0
	var sim_step := 0.05
	while sim_t < 10.0 and boss.get_meta("long_fall_state", "") == "approaching":
		mgr._skyrender_long_fall_approach_tick(boss, mgr.player_units, sim_step)
		mgr.update_unit_movements(sim_step)
		if boss.grid_position != boss_start:
			moved_at_least_once = true
		sim_t += sim_step

	_check(moved_at_least_once,
			"boss never actually moved during the approach — it's still an instant-range grab")
	_check(carry.has_meta("long_fall_active"),
			"approach never handed off into the grab — carry was never taken")
	_check(not other.has_meta("long_fall_active"),
			"grabbed the WRONG unit — the low-damage hero was taken")
	_check(mgr._unit_dist(boss, carry) <= 1 or not is_instance_valid(carry) or carry.grid_position == Vector2i(-1, -1),
			"grab fired while boss was still out of range of the victim")

	# ── 2: THE CELL IS VACATED (the trade this redesign made) ────────────────
	_check(not grid.is_cell_occupied(carry_cell),
			"victim's origin cell is still occupied — it must be vacated for a random landing to be legal")

	# ── 3: away = untargetable AND unable to act ─────────────────────────────
	_check(carry.untargetable_time > 0.0,
			"victim is still targetable while off the board (untargetable_time=%.2f)" % carry.untargetable_time)
	_check(carry.stun_time > 0.0,
			"victim can still act while off the board (stun_time=%.2f)" % carry.stun_time)
	_check(carry.stun_time > carry.untargetable_time,
			"stun (%.2f) must outlast the away window (%.2f) — otherwise it acts mid-air"
			% [carry.stun_time, carry.untargetable_time])
	var picked = mgr.find_nearest_enemy(boss, mgr.player_units)
	_check(picked != carry,
			"find_nearest_enemy still returns the airborne hero — it can be attacked mid-fall")

	# ── 4: THE BOSS pays the cost — stunned for the whole carry ──────────────
	_check(boss.stun_time > 0.0,
			"boss can still attack while carrying a hero across the board — this is the whole point of the redesign")
	_check(is_equal_approx(boss.stun_time, mgr.LONG_FALL_BOSS_BUSY) or boss.stun_time >= mgr.LONG_FALL_BOSS_BUSY,
			"boss stun (%.2f) is shorter than LONG_FALL_BOSS_BUSY (%.2f) — the carry isn't actually costing attacks"
			% [boss.stun_time, mgr.LONG_FALL_BOSS_BUSY])

	# ── 5: it lands somewhere in the team zone, intact ───────────────────────
	var total_away: float = mgr.LONG_FALL_GRAB + mgr.LONG_FALL_CARRY + mgr.LONG_FALL_EDGE_PAUSE \
			+ mgr.LONG_FALL_THROW + mgr.LONG_FALL_GONE + mgr.LONG_FALL_REENTRY
	var waited := 0.0
	while waited < total_away + 0.5:
		await get_tree().process_frame
		var d: float = get_process_delta_time()
		waited += d
		for u in [carry, other]:
			mgr._tick_statuses(u, d)

	_check(not carry.has_meta("long_fall_active"),
			"long_fall_active never cleared — the hero is still flagged airborne after landing")
	_check(mgr._in_team_zone(true, carry.grid_position),
			"landed OUTSIDE its own team zone: %s" % carry.grid_position)
	_check(grid.is_cell_occupied(carry.grid_position),
			"grid disagrees with the unit about where it landed")
	_check(grid.get_unit_at(carry.grid_position) == carry,
			"landing cell is occupied by something other than the victim")
	_check(carry.current_hp == carry_hp,
			"the fall dealt damage (%d -> %d) — it is stun-only by design (the carry is the cost now)"
			% [carry_hp, carry.current_hp])
	_check(carry.attack_damage == carry_atk,
			"attack_damage changed across the fall (%d -> %d) — nothing may be taken"
			% [carry_atk, carry.attack_damage])
	_check(carry.untargetable_time <= 0.0,
			"still untargetable after landing (%.2f)" % carry.untargetable_time)

	# ── 6: both sprites came home ─────────────────────────────────────────────
	_check(carry._toss_offset.length() < 1.0,
			"victim sprite left parked off-screen after landing (toss offset %s)" % carry._toss_offset)
	_check(boss._toss_offset.length() < 1.0,
			"boss sprite never recoiled back to its position (toss offset %s)" % boss._toss_offset)

	# ── 7: round-boundary cleanup of an INTERRUPTED fall ─────────────────────
	var origin2 := Vector2i(2, 7)
	grid.remove_unit(carry.grid_position)
	carry.set_meta("long_fall_active", true)
	carry.set_meta("long_fall_origin", origin2)
	carry._toss_offset = Vector2(0, 1400)
	if carry.health_bar:
		carry.health_bar.visible = false
	mgr._init_unit_timers()
	_check(not carry.has_meta("long_fall_active"),
			"interrupted fall: long_fall_active survived the battle reset")
	_check(carry._toss_offset == Vector2.ZERO,
			"interrupted fall: hero still parked off-screen at round start (%s)" % carry._toss_offset)
	_check(carry.health_bar == null or carry.health_bar.visible,
			"interrupted fall: health bar never came back")
	_check(grid.is_cell_occupied(origin2) and grid.get_unit_at(origin2) == carry,
			"interrupted fall: hero was never put back on the grid at its stored origin")
	_check(carry.grid_position == origin2,
			"interrupted fall: grid_position (%s) doesn't match the restored origin (%s)"
			% [carry.grid_position, origin2])

	# ── 8: THE TICK PATH actually fires it, and never while aloft ────────────
	carry.remove_meta("long_fall_active")
	carry.untargetable_time = 0.0
	carry.stun_time = 0.0
	boss.remove_meta("long_fall_timer")
	boss.set_meta("skyrender_aloft", false)
	boss.set_meta("skyrender_timer", 0.0)

	var fired_at := -1.0
	var simt := 0.0
	var step := 0.1
	while simt < 40.0 and fired_at < 0.0:
		mgr._tick_mob_passive(boss, mgr.player_units, mgr.enemy_units, step)
		mgr.update_unit_movements(step)
		simt += step
		if carry.has_meta("long_fall_active") or other.has_meta("long_fall_active"):
			fired_at = simt
	_check(fired_at > 0.0,
			"the skyrender_ascent tick NEVER fired the Long Fall in 30 simulated seconds — " +
			"the beat is unreachable in real combat")
	if fired_at > 0.0:
		_check(not bool(boss.get_meta("skyrender_aloft", false)),
				"the grab fired while the boss was ALOFT at t=%.1fs — that is the " % fired_at +
				"worst-moment pile-on the aloft gate exists to prevent")

	# ── Report ───────────────────────────────────────────────────────────────
	if _fails.is_empty():
		print("LONG_FALL_SMOKE: ALL PASS")
		get_tree().quit(0)
	else:
		for f in _fails:
			print("LONG_FALL_SMOKE: FAIL -> %s" % f)
		print("LONG_FALL_SMOKE: %d FAILURE(S)" % _fails.size())
		get_tree().quit(1)
