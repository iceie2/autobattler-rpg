extends Node
# Hill Giant kit probe. Drives the REAL manager.
#   - demoted heavy-wave Giant: Boulder Smash (adjacent footprint) unchanged
#   - round-5 elite: GROUNDBREAKER loop (owner 2026-10-06) -- arms after 2
#     landed blows, hits exactly the 4x2 block, knocks back 1 (blocked = stays,
#     grid intact), STUCK CLUB exposes armor/MR through the shared accessor that
#     take_damage uses, yank restores them, and a battle reset clears it all.
# Run: godot --headless --rendering-method gl_compatibility --fixed-fps 30 res://scenes/tools/hill_giant_kit_probe.tscn

var _fail: Array = []

func _check(c: bool, m: String) -> void:
	if not c: _fail.append(m)

func _unit(mgr, grid, u: UnitBase, cell: Vector2i, player: bool) -> UnitBase:
	add_child(u); u.battle_manager = mgr; u.is_player_unit = player
	assert(grid.place_unit(u, cell)); u.grid_position = cell
	return u

func _cells_of(grid, u) -> int:
	var n := 0
	for c in grid.occupied_cells:
		if grid.occupied_cells[c] == u: n += 1
	return n

func _ready() -> void:
	_boulder_smash()
	_groundbreaker()
	if _fail.is_empty():
		print("HILL_GIANT_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("HILL_GIANT_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _setup() -> Array:
	var grid := BattleGrid.new(); var mgr := AutoBattleManager.new(); var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null); mgr.skill_effect_container = fx
	return [grid, mgr]

# ── demoted heavy Giant keeps Boulder Smash (the original footprint check) ──
func _boulder_smash() -> void:
	var gm := _setup(); var grid = gm[0]; var mgr = gm[1]
	var giant := EnemyFactory.create_hill_giant()
	EnemyFactory.demote_hill_giant(giant)
	_unit(mgr, grid, giant, Vector2i(3, 1), false)
	var near := _unit(mgr, grid, EnemyFactory.create_goblin(), Vector2i(5, 1), true)   # flush with the 2x2
	var far := _unit(mgr, grid, EnemyFactory.create_goblin(), Vector2i(6, 1), true)
	mgr.enemy_units = [giant]; mgr.player_units = [near, far]
	_check(giant.skill_name == "Boulder Smash", "demoted Giant lost Boulder Smash")
	_check(mgr._skill_trigger_ready(giant, mgr.player_units), "adjacent target must enable Boulder Smash")
	var nb := near.current_hp; var fb := far.current_hp
	mgr._use_skill(giant, mgr.player_units, mgr.enemy_units)
	_check(near.current_hp == nb, "Boulder Smash must wait for contact")
	mgr._tick_hill_giant_actions(AutoBattleManager.HILL_GIANT_SMASH_CONTACT + 0.01)
	_check(near.current_hp < nb, "footprint-adjacent target was not hit")
	_check(far.current_hp == fb, "target outside displayed footprint was hit")
	_check(giant.damage_dealt == nb - near.current_hp, "smash damage accounting mismatch")
	_check(mgr._groundbreakers.is_empty(), "a demoted Giant started a Groundbreaker")

# ── round-5 elite: the Groundbreaker loop ──
func _groundbreaker() -> void:
	var gm := _setup(); var grid = gm[0]; var mgr = gm[1]
	var giant := EnemyFactory.create_hill_giant()
	giant.max_hp = 999999; giant.current_hp = 999999
	_unit(mgr, grid, giant, Vector2i(3, 1), false)          # body (3..4, 1..2); south block = cols 2..5, rows 3..4
	var a := _unit(mgr, grid, EnemyFactory.create_goblin(), Vector2i(4, 3), true)    # near row -> knocked to (4,4)
	var b := _unit(mgr, grid, EnemyFactory.create_goblin(), Vector2i(3, 4), true)    # far row  -> knocked to (3,5)
	var c := _unit(mgr, grid, EnemyFactory.create_goblin(), Vector2i(2, 4), true)    # far row, BLOCKED below
	var wall := _unit(mgr, grid, EnemyFactory.create_goblin(), Vector2i(2, 5), false)  # an enemy blocking c's square
	var out := _unit(mgr, grid, EnemyFactory.create_goblin(), Vector2i(6, 4), true)  # just outside the block
	for h in [a, b, c, out]:
		h.max_hp = 999999; h.current_hp = 999999
	mgr.enemy_units = [giant, wall]; mgr.player_units = [a, b, c, out]

	_check(giant.skill_name == "Groundbreaker", "elite Giant has no Groundbreaker")
	_check(not mgr._skill_trigger_ready(giant, mgr.player_units), "Groundbreaker armed before 2 landed blows")
	giant.set_meta("gb_swings", 2)
	_check(mgr._skill_trigger_ready(giant, mgr.player_units), "Groundbreaker not armed after 2 blows with heroes in front")
	var hp0 := {a: a.current_hp, b: b.current_hp, c: c.current_hp, out: out.current_hp}
	mgr._use_skill(giant, mgr.player_units, mgr.enemy_units)
	_check(bool(giant.get_meta("hill_giant_committed", false)), "not committed during the windup")
	_check(int(giant.get_meta("gb_swings", 9)) == 0, "blow count not reset by the slam")
	mgr._tick_groundbreakers(AutoBattleManager.GB_WINDUP - 0.05)
	_check(a.current_hp == hp0[a], "Groundbreaker hit before contact")
	mgr._tick_groundbreakers(0.06)                          # contact
	for h in [a, b, c]:
		_check(h.current_hp < hp0[h], "a hero inside the 4x2 block was not hit (%s)" % h.grid_position)
	_check(out.current_hp == hp0[out], "a hero OUTSIDE the block was hit")
	_check(a.grid_position == Vector2i(4, 4), "near-row hero not knocked back 1 (at %s)" % a.grid_position)
	_check(b.grid_position == Vector2i(3, 5), "far-row hero not knocked back 1 (at %s)" % b.grid_position)
	_check(c.grid_position == Vector2i(2, 4), "blocked hero moved (at %s)" % c.grid_position)
	for u in [a, b, c, out, wall]:
		_check(grid.get_unit_at(u.grid_position) == u and _cells_of(grid, u) == 1,
			"grid occupancy broken for unit at %s" % u.grid_position)
	_check(_cells_of(grid, giant) == 4, "the giant's 2x2 occupancy changed")

	# STUCK CLUB: can't act, armor + MR to 0 through the SHARED accessor.
	_check(bool(giant.get_meta("hill_giant_committed", false)), "giant free to act while stuck")
	_check(giant.effective_armor() == 0 and giant.effective_magic_resist() == 0,
		"effective armor/MR not 0 while stuck (%d / %d)" % [giant.effective_armor(), giant.effective_magic_resist()])
	_check(giant.resistance == 20 and giant.magic_resist == 20, "the BASE stats were modified")
	var g0 := giant.current_hp
	giant.take_damage(100, UnitBase.Element.NORMAL, null)
	var exposed_hit := g0 - giant.current_hp
	mgr._tick_groundbreakers(AutoBattleManager.GB_STUCK)    # -> yank
	_check(giant.exposed_time <= 0.0, "Exposed still running after the club came out")
	_check(giant.effective_armor() == 20 and giant.effective_magic_resist() == 20, "defenses not restored on the yank")
	_check(bool(giant.get_meta("hill_giant_committed", false)), "giant free to act during the yank")
	var g1 := giant.current_hp
	giant.take_damage(100, UnitBase.Element.NORMAL, null)
	var normal_hit := g1 - giant.current_hp
	_check(exposed_hit > normal_hit, "take_damage ignored Exposed (exposed %d vs normal %d)" % [exposed_hit, normal_hit])
	mgr._tick_groundbreakers(AutoBattleManager.GB_YANK + 0.01)
	_check(not bool(giant.get_meta("hill_giant_committed", true)), "giant still locked after the yank")
	_check(mgr._groundbreakers.is_empty(), "Groundbreaker state not cleared after the loop")

	# Battle reset mid-stuck clears everything.
	giant.set_meta("gb_swings", 2)
	mgr._use_skill(giant, mgr.player_units, mgr.enemy_units)
	mgr._tick_groundbreakers(AutoBattleManager.GB_WINDUP + 0.01)
	_check(giant.exposed_time > 0.0, "second slam didn't expose")
	mgr._clear_hill_giant_actions()
	_check(giant.exposed_time <= 0.0 and giant.effective_armor() == 20, "battle reset left the giant exposed")
	_check(not bool(giant.get_meta("hill_giant_committed", true)), "battle reset left the giant locked")
