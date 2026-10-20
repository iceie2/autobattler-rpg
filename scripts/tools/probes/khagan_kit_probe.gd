extends Node
# Khagan kit probe (wave-10 boss, owner 2026-10-03): Sidestep Charge + Dread Gaze
# while mounted; Ink Cloud + Eight Arms dismounted; the dismount lands the rider
# on ONE cell. Drives the REAL manager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/khagan_kit_probe.tscn

var _fail: Array = []

func _check(c: bool, m: String) -> void:
	if not c: _fail.append(m)

func _hero(mgr, grid, cell: Vector2i):
	var h: VisualUnit = EnemyFactory.create_by_type("goblin")
	add_child(h); h.battle_manager = mgr; h.is_player_unit = true
	assert(grid.place_unit(h, cell)); h.grid_position = cell
	h.max_hp = 9999999; h.current_hp = 9999999
	return h

func _ready() -> void:
	var grid := BattleGrid.new(); var mgr := AutoBattleManager.new(); var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null); mgr.skill_effect_container = fx
	var kh: VisualUnit = EnemyFactory.create_by_type("khagan")
	add_child(kh); kh.battle_manager = mgr; kh.is_player_unit = false
	assert(grid.place_unit(kh, Vector2i(3, 2))); kh.grid_position = Vector2i(3, 2)
	kh.max_hp = 9999999; kh.current_hp = 9999999
	var lane = _hero(mgr, grid, Vector2i(6, 3))    # in its bottom body row, to the right
	var top = _hero(mgr, grid, Vector2i(6, 2))     # in its TOP body row, 2 tiles under the board edge
	var front = _hero(mgr, grid, Vector2i(4, 4))   # the row in front of it
	var off = _hero(mgr, grid, Vector2i(1, 7))     # nowhere near the lane
	var opps: Array = [lane, top, front, off]
	mgr.enemy_units = [kh]; mgr.player_units = opps

	_check(str(kh.get_meta("mob_passive", "")) == "khagan_kit", "Khagan has no khagan_kit passive")

	# Dread Gaze goes to the 2 heroes that hurt it most.
	kh.take_damage(500, UnitBase.Element.NORMAL, off)
	kh.take_damage(300, UnitBase.Element.NORMAL, lane)
	kh.take_damage(10, UnitBase.Element.NORMAL, front)
	mgr._khagan_kit_passive(kh, opps, 6.0)   # past both opening timers
	_check(off.weaken_flavor == "dread" and off.weakened_time > 0.0, "the top damage dealer was not gazed")
	_check(lane.weaken_flavor == "dread", "the second damage dealer was not gazed")
	_check(front.weakened_time <= 0.0, "a third hero was gazed")
	_check(bool(kh.get_meta("hill_giant_committed", false)), "the charge windup did not start")

	# Sidestep Charge resolves: crab runs right, lane heroes hit and shoved out.
	var hp0: int = lane.current_hp
	mgr._tick_khagan_kit(AutoBattleManager.KHAGAN_CHARGE_WINDUP + 0.05)
	_check(bool(kh.get_meta("hill_giant_committed", false)), "the scuttle should still be running after one step")
	# Step it across the board in small slices: the body must glide steadily
	# toward the edge, never jumping back (the 2026-10-03 mid-charge jitter).
	var last_x: float = kh.position.x
	var backstep := 0.0
	for i in 400:
		mgr._tick_khagan_kit(0.02)
		backstep = maxf(backstep, last_x - kh.position.x)
		last_x = kh.position.x
	_check(backstep < 0.5, "the body jumped BACK %.1fpx mid-charge (should glide one way)" % backstep)
	_check(not bool(kh.get_meta("hill_giant_committed", true)), "commit flag stuck after the charge")
	_check(kh.grid_position.x > 3 and kh.grid_position.y == 2, "the crab did not run sideways (now %s)" % kh.grid_position)
	# Full sweep: it ploughs through the pinned hero (bowled aside) to the edge.
	_check(kh.grid_position.x + kh.cell_size == grid.grid_width,
		"the sweep stopped short of the edge (at x=%d, width %d)" % [kh.grid_position.x, grid.grid_width])
	_check(grid.get_unit_at(kh.grid_position) == kh and grid.get_unit_at(Vector2i(3, 2)) != kh,
		"grid occupancy did not follow the crab")
	_check(lane.current_hp < hp0, "the hero in its row was not hit")
	# Knockback goes ACROSS the charge (a rightward charge throws up/down), 4 tiles.
	_check(lane.grid_position == Vector2i(6, 7),
		"bottom-row hero should be thrown 4 tiles DOWN to (6,7), is at %s" % lane.grid_position)
	_check(lane.stun_time <= 0.0, "a hero with room to fly the full 4 tiles was stunned")
	# Top-row hero thrown UP hits the board edge after 2 tiles: slammed + stunned.
	_check(top.grid_position == Vector2i(6, 0), "top-row hero should be thrown up to the edge (6,0), is at %s" % top.grid_position)
	_check(top.stun_time > 0.0, "a hero thrown into the wall was not stunned")
	_check(front.current_hp < front.max_hp, "the hero in front was not hit")
	_check(off.current_hp == off.max_hp - 0, "a hero outside the lane was hit")

	# Dismount: one cell, Ink Cloud skill.
	kh.current_hp = 0
	var anchor_before: Vector2i = kh.grid_position
	EnemyFactory.advance_khagan_phase(kh)
	_check(kh.cell_size == 1, "still 2×2 after dismount")
	var cells := 0
	for y in grid.grid_height:
		for x in grid.grid_width:
			if grid.get_unit_at(Vector2i(x, y)) == kh: cells += 1
	_check(cells == 1, "dismounted rider holds %d cells" % cells)
	_check(absi(kh.grid_position.x - anchor_before.x) <= 1 and absi(kh.grid_position.y - anchor_before.y) <= 1,
		"rider landed outside the mount's block")
	_check(str(kh.get_meta("mob_skill", "")) == "khagan_ink", "phase 2 has no Ink Cloud skill")
	await get_tree().create_timer(0.6).timeout
	_check(kh.position.distance_to(mgr._world_pos_for(kh, kh.grid_position)) < 1.0,
		"the body is not standing on its cell after the dismount (%s vs %s)" % [kh.position, mgr._world_pos_for(kh, kh.grid_position)])

	# Highest battle damage wins, then skip tiles covered by pending/live ink.
	off.damage_dealt = 1000; lane.damage_dealt = 500; top.damage_dealt = 200
	_check(mgr._khagan_ink_target(kh, opps) == off.grid_position, "ink did not aim at the highest damage dealer")
	mgr._begin_khagan_ink(kh, off.grid_position)
	_check(mgr._khagan_ink_target(kh, opps) == lane.grid_position, "pending ink did not redirect to the next damage dealer")
	mgr._tick_khagan_kit(AutoBattleManager.KHAGAN_INK_FLIGHT + 0.05)
	_check(off.blind_time > 0.0, "the ink did not blind the hero it landed on")
	_check(off.ink_poison_stacks == 1 and off.ink_poison_dps() == 10.0, "ink impact did not add poison")
	mgr._tick_khagan_kit(1.0)
	_check(off.ink_poison_stacks == 2 and off.ink_poison_dps() == 20.0, "standing in ink did not increase poison damage")
	off.current_shield = 100
	var poison_hp: int = off.current_hp
	mgr._tick_statuses(off, 1.0)
	_check(off.current_hp == poison_hp and off.current_shield == 80, "stacking poison did not deal its displayed damage into shields")
	off.current_shield = 0
	mgr._tick_statuses(off, 1.0)
	_check(off.current_hp == poison_hp - 20, "poison HP damage disagrees with live DPS")
	off._update_status_icons()
	_check(off._status_icons.get("ink_poison").stack_count == 2, "poison badge did not show live stacks")
	_check(mgr._khagan_ink_target(kh, opps) == lane.grid_position, "live ink did not redirect to the next damage dealer")
	for h in opps:
		mgr._khagan_ink_pools.append({"centre": h.grid_position, "time": AutoBattleManager.KHAGAN_INK_BLIND})
	var fallback: Vector2i = mgr._khagan_ink_target(kh, opps)
	_check(grid.is_valid_position(fallback) and grid.get_unit_at(fallback) == null and not mgr._khagan_tile_inked(fallback), "all-inked fallback did not choose an empty uninked tile")
	mgr._tick_khagan_kit(AutoBattleManager.KHAGAN_INK_BLIND + 0.05)
	_check(mgr._khagan_ink_target(kh, opps) == off.grid_position, "expired ink still blocked the highest damage dealer")
	mgr._khagan_ink_pools.append({"centre": off.grid_position, "time": 3.0})
	mgr._clear_khagan_kit()
	_check(not mgr._khagan_tile_inked(off.grid_position), "battle reset left ink coverage behind")
	mgr._tick_statuses(off, 10.0)
	_check(off.ink_poison_stacks == 0 and off.ink_poison_dps() == 0.0, "poison did not expire")
	mgr._add_ink_poison(off, kh)
	off.clear_debuffs()
	_check(off.ink_poison_stacks == 0 and off.ink_poison_dps() == 0.0, "cleanse did not remove poison")
	mgr._add_ink_poison(off, kh)
	mgr._init_unit_timers()
	_check(off.ink_poison_stacks == 0 and off.ink_poison_dps() == 0.0, "battle reset did not remove poison")
	# Reapply after the reset/cleanse checks before measuring blind misses.
	mgr._land_khagan_ink({"centre": off.grid_position, "caster": kh})
	var misses := 0
	for i in 200:
		var before: int = kh.current_hp
		kh.max_hp = 9999999; kh.current_hp = 9999999; before = kh.current_hp
		kh.take_damage(10, UnitBase.Element.NORMAL, off)
		if kh.current_hp == before: misses += 1
	_check(misses > 60 and misses < 140, "blind miss rate off: %d/200" % misses)

	# Eight Arms: an auto also lashes the other heroes beside it.
	var p: Vector2i = kh.grid_position
	for h in opps:
		grid.purge_unit(h)
	var a = _hero(mgr, grid, p + Vector2i(1, 0)) if grid.is_valid_position(p + Vector2i(1, 0)) else _hero(mgr, grid, p + Vector2i(-1, 0))
	var b = _hero(mgr, grid, p + Vector2i(0, 1))
	mgr.player_units = [a, b]
	mgr._apply_on_hit_passives(kh, a, mgr.player_units)
	_check(b.current_hp < b.max_hp, "Eight Arms did not lash the second adjacent hero")
	_check(a.current_hp == a.max_hp, "Eight Arms double-hit the main target")

	if _fail.is_empty():
		print("KHAGAN_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("KHAGAN_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)
