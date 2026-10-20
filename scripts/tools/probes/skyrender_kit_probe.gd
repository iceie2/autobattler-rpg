extends Node
# Skyrender Storm Dive + Downdraft probe (owner 2026-10-04). Drives the REAL manager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/skyrender_kit_probe.tscn

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
	var sk: VisualUnit = EnemyFactory.create_by_type("skyrender")
	add_child(sk); sk.battle_manager = mgr; sk.is_player_unit = false
	assert(grid.place_unit(sk, Vector2i(3, 0))); sk.grid_position = Vector2i(3, 0)
	sk.max_hp = 9999999; sk.current_hp = 9999999
	# A tight cluster lower down, and one loner far away.
	var a = _hero(mgr, grid, Vector2i(5, 6))
	var b = _hero(mgr, grid, Vector2i(6, 6))
	var c = _hero(mgr, grid, Vector2i(5, 7))
	var loner = _hero(mgr, grid, Vector2i(0, 8))
	var opps: Array = [a, b, c, loner]
	mgr.enemy_units = [sk]; mgr.player_units = opps

	# ── Storm Dive ──
	_check(mgr._storm_dive_begin(sk, opps), "Storm Dive did not start with heroes on the board")
	var o: Vector2i = sk.get_meta("sd_origin", Vector2i(-1, -1))
	var area: Array = mgr._sky_area(o)
	_check(area.has(a.grid_position) and area.has(b.grid_position) and area.has(c.grid_position),
		"the dive target %s doesn't cover the 3-hero cluster" % o)
	var hp0: int = a.current_hp
	mgr._storm_dive_land(sk, opps)
	_check(sk.grid_position == o, "it didn't land on the marked spot (at %s, marked %s)" % [sk.grid_position, o])
	_check(not sk.has_meta("sd_origin"), "dive state not cleared after landing")
	_check(a.current_hp < hp0 and b.current_hp < b.max_hp and c.current_hp < c.max_hp, "a clustered hero took no dive damage")
	_check(loner.current_hp == loner.max_hp, "the far loner was hit by the dive")
	for h in [a, b, c]:
		_check(not (h.grid_position.x >= o.x and h.grid_position.x <= o.x + 1 and h.grid_position.y >= o.y and h.grid_position.y <= o.y + 1),
			"a hero is still inside the landing square at %s" % h.grid_position)
		_check(grid.get_unit_at(h.grid_position) == h, "grid lost track of a thrown hero at %s" % h.grid_position)
	for dy in 2:
		for dx in 2:
			_check(grid.get_unit_at(o + Vector2i(dx, dy)) == sk, "landing square cell %s isn't the boss's" % (o + Vector2i(dx, dy)))

	# ── Downdraft: only heroes in the 4x4 around it ──
	var near_cell := Vector2i(o.x - 1, o.y)
	if grid.is_cell_occupied(near_cell):
		near_cell = Vector2i(o.x + 2, o.y)
	var near = _hero(mgr, grid, near_cell) if not grid.is_cell_occupied(near_cell) else a
	opps.append(near)
	var n0: int = near.current_hp
	var l0: int = loner.current_hp
	mgr._skyrender_downdraft(sk, opps)
	_check(near.current_hp < n0, "Downdraft missed a hero right beside it")
	_check(near.slow_time > 0.0, "Downdraft didn't slow")
	_check(loner.current_hp == l0, "Downdraft hit a hero across the board")

	# ── No heroes: no dive (it just lands) ──
	_check(not mgr._storm_dive_begin(sk, []), "Storm Dive started with nobody to dive on")

	if _fail.is_empty():
		print("SKYRENDER_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("SKYRENDER_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)
