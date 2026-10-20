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
#   8. the passive tick path reaches the beat, AT TAKE-OFF (aloft)
#
# AERIAL SNATCH 2026-10-04 (owner, with the spread-wing v002 body): the walk-up
# (2026-08-04) is gone -- it swoops in from the sky at the start of each flight.
#   9. begin() snatches the top damage dealer at once; the boss's square never moves
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

	# ── 9: AERIAL SNATCH (2026-10-04) — begin() grabs the top damage dealer
	# straight away, from wherever it is: no walk-up, no range requirement ────
	var boss_start: Vector2i = boss.grid_position
	mgr._skyrender_long_fall_begin(boss, mgr.player_units)
	_check(carry.has_meta("long_fall_active"),
			"begin() did not snatch the top damage dealer straight away")
	_check(not other.has_meta("long_fall_active"),
			"grabbed the WRONG unit — the low-damage hero was taken")
	_check(boss.grid_position == boss_start,
			"the boss's grid square moved — the swoop is visual only")

	# ── 2: the victim is off the grid while it's carried ─────────────────────
	_check(not grid.is_cell_occupied(carry_cell),
			"victim's origin cell is still occupied while it's being carried off")

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

	# ── 5: FATAL (owner 2026-10-04) — thrown off the edge, the hero DIES ─────
	var other_hp: int = other.current_hp
	var waited := 0.0
	# + the boss's flight home, so its own toss offset has settled too (check 6).
	while waited < maxf(mgr.LONG_FALL_KILL_AT, mgr.LONG_FALL_BOSS_BUSY) + 0.5:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_check(not is_instance_valid(carry) or carry.current_hp <= 0,
			"the snatched hero survived being thrown off the edge — it must die")
	if is_instance_valid(carry):
		_check(not carry.has_meta("long_fall_active"), "long_fall_active never cleared on the dead hero")
		for cell in grid.occupied_cells:
			_check(grid.occupied_cells[cell] != carry, "the dead hero still holds grid cell %s" % cell)
	_check(other.current_hp == other_hp, "the OTHER hero was harmed by the Long Fall")
	# Revived after the round, the body must be back on the board, not parked
	# off-screen where the throw left it (2026-10-04 bug: invisible in prep).
	if is_instance_valid(carry):
		carry.revive(0.5)
		_check(carry._toss_offset.length() < 1.0,
			"revived hero is still parked off-screen (toss offset %s)" % carry._toss_offset)
		_check(carry.health_bar == null or carry.health_bar.visible, "revived hero has no health bar")

	# ── 6: the boss flew home ─────────────────────────────────────────────────
	_check(boss._toss_offset.length() < 1.0,
			"boss sprite never flew back to its position (toss offset %s)" % boss._toss_offset)

	# ── 7: round-boundary cleanup of an INTERRUPTED fall (round ends mid-carry) ─
	var origin2 := Vector2i(2, 7)
	grid.purge_unit(other)
	other.set_meta("long_fall_active", true)
	other.set_meta("long_fall_origin", origin2)
	other._toss_offset = Vector2(0, 1400)
	if other.health_bar:
		other.health_bar.visible = false
	mgr._init_unit_timers()
	_check(not other.has_meta("long_fall_active"),
			"interrupted fall: long_fall_active survived the battle reset")
	_check(other._toss_offset == Vector2.ZERO,
			"interrupted fall: hero still parked off-screen at round start (%s)" % other._toss_offset)
	_check(other.health_bar == null or other.health_bar.visible,
			"interrupted fall: health bar never came back")
	_check(grid.is_cell_occupied(origin2) and grid.get_unit_at(origin2) == other,
			"interrupted fall: hero was never put back on the grid at its stored origin")
	_check(other.grid_position == origin2,
			"interrupted fall: grid_position (%s) doesn't match the restored origin (%s)"
			% [other.grid_position, origin2])

	# ── 8: THE TICK PATH fires it — exactly at take-off (aerial snatch) ──────
	mgr.player_units = [other]
	other.untargetable_time = 0.0
	other.stun_time = 0.0
	boss.set_meta("skyrender_aloft", false)
	boss.set_meta("skyrender_timer", 0.0)

	var fired_at := -1.0
	var simt := 0.0
	var step := 0.1
	while simt < 40.0 and fired_at < 0.0:
		mgr._tick_mob_passive(boss, mgr.player_units, mgr.enemy_units, step)
		mgr.update_unit_movements(step)
		simt += step
		if other.has_meta("long_fall_active"):
			fired_at = simt
	_check(fired_at > 0.0,
			"the skyrender_ascent tick NEVER fired the Long Fall in 30 simulated seconds — " +
			"the beat is unreachable in real combat")
	if fired_at > 0.0:
		_check(bool(boss.get_meta("skyrender_aloft", false)),
				"the snatch fired at t=%.1fs while GROUNDED — it should open each flight" % fired_at)

	# ── Report ───────────────────────────────────────────────────────────────
	if _fails.is_empty():
		print("LONG_FALL_SMOKE: ALL PASS")
		get_tree().quit(0)
	else:
		for f in _fails:
			print("LONG_FALL_SMOKE: FAIL -> %s" % f)
		print("LONG_FALL_SMOKE: %d FAILURE(S)" % _fails.size())
		get_tree().quit(1)
