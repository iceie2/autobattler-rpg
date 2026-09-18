extends Node
# Regression test for the "invisible wall of stranded grid cells" bug
# (2026-08-07 user report: the wave-50 Emberhollow stood in its spawn row for a
# whole fight, taking ranged hits, never crossing the field or attacking).
#
# Mechanism: occupied_cells is keyed by position and every removal used to be
# too — remove_unit(unit.grid_position). That is only correct while a unit's
# grid_position matches the cells it is REGISTERED on, and several callers
# ignored place_unit()'s false return, which breaks the tie. Once broken, the
# removal at death silently no-ops and the dead unit's real cells stay in
# occupied_cells forever, pointing at a freed node. Nothing clears them —
# occupied_cells outlives the round — so they block MOVEMENT but not ranged
# attacks, which never consult occupancy. 1×1 mobs weave through the gaps; a
# 2×2 boss, which needs a clear 2×2 origin, gets pinned.
#
# Same failure shape as the Khagan dismount fix (EnemyFactory.advance_khagan_
# phase), which was patched at its one call site rather than at the source.
#
#   godot --headless --fixed-fps 30 res://scenes/phantom_cell_test.tscn

var grid: BattleGrid
var mgr: AutoBattleManager
var units_root: Node2D

func _ready() -> void:
	await get_tree().process_frame
	var failures: Array[String] = []

	grid = BattleGrid.new()
	add_child(grid)
	units_root = Node2D.new()
	add_child(units_root)
	mgr = AutoBattleManager.new()
	add_child(mgr)
	mgr.initialize(grid, null)
	mgr.skill_effect_container = units_root
	mgr.projectile_container = units_root

	# ── 1. purge_unit clears cells a position-keyed removal would miss ────────
	var drifter: VisualUnit = EnemyFactory.create_by_type("orc_earth")
	units_root.add_child(drifter)
	grid.place_unit(drifter, Vector2i(2, 1))
	drifter.grid_position = Vector2i(7, 3)   # the drift: registered at (2,1), claims (7,3)

	grid.remove_unit(drifter.grid_position)  # the OLD removal — a no-op here
	if not grid.is_cell_occupied(Vector2i(2, 1)):
		failures.append("setup wrong: position-keyed removal unexpectedly cleared the cell")
	grid.purge_unit(drifter)
	if grid.is_cell_occupied(Vector2i(2, 1)):
		failures.append("purge_unit left a cell registered to the unit")

	# ── 2. sweep_phantoms reclaims cells held by freed nodes ─────────────────
	var doomed: VisualUnit = EnemyFactory.create_by_type("orc_earth")
	units_root.add_child(doomed)
	grid.place_unit(doomed, Vector2i(4, 1))
	doomed.queue_free()
	await get_tree().process_frame
	if not grid.is_cell_occupied(Vector2i(4, 1)):
		failures.append("setup wrong: freed unit's cell cleared itself")
	var reclaimed: int = grid.sweep_phantoms()
	if reclaimed != 1 or grid.is_cell_occupied(Vector2i(4, 1)):
		failures.append("sweep_phantoms reclaimed %d cell(s), expected 1" % reclaimed)

	# ── 3. The real thing: a 2×2 boss walled by phantom cells still crosses ──
	# A phantom row across the divider, exactly where a wave's front line dies.
	for x in range(grid.grid_width):
		grid.occupied_cells[Vector2i(x, 3)] = null
		grid.grid_cells[3][x] = null

	var boss: VisualUnit = EnemyFactory.create_by_type("emberhollow")
	boss.set_level(50)
	_wire(boss)
	boss.grid_position = Vector2i(3, 0)
	grid.place_unit(boss, boss.grid_position)
	boss.position = grid.grid_to_world(boss.grid_position)

	var hero: VisualUnit = UnitFactory.create_unit(
			UnitBase.UnitClass.RIOT, UnitBase.Element.NORMAL, true)
	hero.set_level(10)
	hero.max_hp = 999999          # must outlive the walk, not the fight
	hero.current_hp = hero.max_hp
	_wire(hero)
	hero.grid_position = Vector2i(4, grid.grid_height - 3)
	grid.place_unit(hero, hero.grid_position)
	hero.position = grid.grid_to_world(hero.grid_position)

	var start_pos: Vector2i = boss.grid_position
	mgr.start_battle()          # collect_units() sweeps the phantom row

	var elapsed := 0.0
	var closed := false
	while mgr.battle_active and elapsed < 30.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time() * mgr.time_scale
		if boss.grid_position.y > start_pos.y and boss.damage_dealt > 0:
			closed = true
			break

	if not closed:
		failures.append(
			"boss never crossed AND attacked in %.1fs (start %s, ended %s, dmg %d) — the wall held"
			% [elapsed, start_pos, boss.grid_position, boss.damage_dealt])

	if failures.is_empty():
		print("PHANTOM_CELL_TEST: ALL PASS (boss closed in %.1fs)" % elapsed)
	else:
		for f in failures:
			print("PHANTOM_CELL_TEST FAIL: %s" % f)
	get_tree().quit(0 if failures.is_empty() else 1)

func _wire(u: VisualUnit) -> void:
	units_root.add_child(u)
	u.battle_manager = mgr
	u.died.connect(func():
		if grid and is_instance_valid(u):
			grid.purge_unit(u))
