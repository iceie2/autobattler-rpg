extends Node2D

# Regression test for WHERE Rift's Collapse actually lands.
#
# Two separate faults put the well off the board (user report 2026-09-17,
# screenshot: the well rendered past the board's left edge while the damage
# still resolved on the enemies):
#
#   1. COORDINATE SPACE. battle_grid.grid_to_world() returns a point in the
#      GRID's local space. Assigning it straight to a node's global_position
#      offsets it by the board's own origin. Every other correct call site in
#      the codebase wraps it: `grid.to_global(grid.grid_to_world(cell))`.
#   2. CENTRING. The well was pinned to the board's geometric centre rather
#      than to the enemies it gathers.
#
# The grid is deliberately given a NON-ZERO origin here, and the effect
# container a different one again. With the bug, the two offsets do not cancel
# and the assert fires; at zero offsets the bug is invisible, which is exactly
# why it shipped.
const GRID_ORIGIN := Vector2(410.0, 137.0)
const FX_ORIGIN := Vector2(-63.0, 291.0)

func _ready() -> void:
	var grid := BattleGrid.new()
	grid.position = GRID_ORIGIN
	grid.visible = false
	add_child(grid)

	var mgr := AutoBattleManager.new()
	add_child(mgr)
	mgr.battle_grid = grid
	var fx_layer := Node2D.new()
	fx_layer.position = FX_ORIGIN
	add_child(fx_layer)
	mgr.skill_effect_container = fx_layer
	var proj_layer := Node2D.new()
	add_child(proj_layer)
	mgr.projectile_container = proj_layer
	await get_tree().process_frame

	var caster: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.RIFT, UnitBase.Element.NORMAL, true)
	add_child(caster)
	grid.place_unit(caster, Vector2i(3, 7))
	caster.grid_position = Vector2i(3, 7)
	caster.position = grid.to_global(grid.grid_to_world(caster.grid_position))
	mgr.player_units = [caster]

	# A deliberately lopsided cluster: if the well were still pinned to the board
	# centre it would land nowhere near these three.
	var cells := [Vector2i(6, 1), Vector2i(7, 2), Vector2i(7, 1)]
	var foes: Array = []
	for cell: Vector2i in cells:
		# Plain UnitBase dummies: this test is about WHERE the well lands, and a
		# bare Node2D carries every field _rift_collapse touches without pulling
		# in three more 3D models.
		var e := UnitBase.new()
		e.unit_class = UnitBase.UnitClass.RIFT
		e.is_player_unit = false
		e.max_hp = 500
		e.current_hp = 500
		add_child(e)
		grid.place_unit(e, cell)
		e.grid_position = cell
		e.position = grid.to_global(grid.grid_to_world(cell))
		foes.append(e)
	mgr.enemy_units = foes
	await get_tree().process_frame

	var want := Vector2.ZERO
	for f in foes:
		want += f.global_position
	want /= float(foes.size())

	mgr._rift_collapse(caster, foes)
	await get_tree().process_frame

	var well: RiftVFX = null
	for c in fx_layer.get_children():
		if c is RiftVFX and c.mode == RiftVFX.Mode.COLLAPSE_WELL:
			well = c
			break
	assert(well != null, "RIFT_ULT_CENTER: no COLLAPSE_WELL effect was spawned")

	# Half a cell of tolerance: the well snaps to a cell centre, the centroid of
	# three bodies generally does not.
	var off: float = well.global_position.distance_to(want)
	var tol: float = grid.cell_size * 0.5
	print("RIFT_ULT_CENTER: well=%s enemy_centroid=%s offset=%.1fpx tol=%.1fpx"
		% [well.global_position, want, off, tol])
	assert(off <= tol, "RIFT_ULT_CENTER: well is %.1fpx from the enemy centroid (tol %.1f)" % [off, tol])

	# And it must be ON the board, which the raw-grid_to_world bug broke.
	var board := Rect2(grid.to_global(Vector2.ZERO),
		Vector2(grid.grid_width, grid.grid_height) * grid.cell_size)
	assert(board.has_point(well.global_position),
		"RIFT_ULT_CENTER: well at %s is outside the board %s" % [well.global_position, board])

	print("RIFT_ULT_CENTER: ALL PASS")
	get_tree().quit(0)
