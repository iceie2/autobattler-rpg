extends Node
## Guards the faked-perspective board's geometry invariants.
##
##   GODOT --headless --path . res://scenes/perspective_smoke.tscn
##   → "PERSPECTIVE_SMOKE: ALL PASS"
##
## grid_to_world / world_to_grid are what every placement, click, drag-drop and
## movement step goes through. Once cells stopped being uniform rectangles, a
## rounding error in either direction silently targets a NEIGHBOURING cell —
## which looks like "drag sometimes drops in the wrong square" and is close to
## impossible to spot in a screenshot. So assert the round-trip exactly.

var _fail: Array[String] = []

func _ready() -> void:
	var grid := BattleGrid.new()
	add_child(grid)
	var w: int = grid.grid_width
	var h: int = grid.grid_height
	var cell: float = float(grid.cell_size)

	# 1. Every cell centre must map back to its own cell.
	for y in h:
		for x in w:
			var got: Vector2i = grid.world_to_grid(grid.grid_to_world(Vector2i(x, y)))
			if got != Vector2i(x, y):
				_fail.append("round-trip (%d,%d) -> %s" % [x, y, got])

	# 2. Rows must tile the board exactly: no gaps, no overlap, and the total
	#    height must still equal the flat board's, or the frame and every bit of
	#    surrounding layout would need to move.
	var total: float = 0.0
	for y in h:
		total += BoardPerspective.row_height(y, h, cell)
	if absf(total - h * cell) > 0.5:
		_fail.append("rows sum to %.2f, expected %.2f" % [total, h * cell])

	# 3. Adjacent rows must share an edge, or a seam opens between the tiles.
	for y in range(h - 1):
		var bot: float = BoardPerspective.row_top(y, h, cell) \
			+ BoardPerspective.row_height(y, h, cell)
		var next_top: float = BoardPerspective.row_top(y + 1, h, cell)
		if absf(bot - next_top) > 0.01:
			_fail.append("seam between rows %d/%d: %.3f vs %.3f" % [y, y + 1, bot, next_top])

	# 4. Cell quads must share edges horizontally too.
	for y in h:
		for x in range(w - 1):
			var a := BoardPerspective.cell_quad(x, y, w, h, cell)
			var b := BoardPerspective.cell_quad(x + 1, y, w, h, cell)
			if a[1].distance_to(b[0]) > 0.01 or a[2].distance_to(b[3]) > 0.01:
				_fail.append("column seam at (%d,%d)" % [x, y])

	# 5. Depth must actually vary, and in the right direction — far row smaller.
	var far: float = BoardPerspective.row_scale(0.0, h)
	var near: float = BoardPerspective.row_scale(float(h - 1), h)
	if not (far < near):
		_fail.append("row_scale not increasing toward the viewer (%.3f -> %.3f)" % [far, near])

	# 6. Off-board points must stay off-board, or placement would accept them.
	for p in [Vector2(-40, 50), Vector2(50, -40), Vector2(9999, 50), Vector2(50, 9999)]:
		if grid.is_valid_position(grid.world_to_grid(p)):
			_fail.append("off-board %s reported as a valid cell" % p)

	if _fail.is_empty():
		print("PERSPECTIVE_SMOKE: ALL PASS (%dx%d, far scale %.2f)" % [w, h, far])
		get_tree().quit(0)
	else:
		for f in _fail:
			printerr("PERSPECTIVE_SMOKE FAIL  " + f)
		print("PERSPECTIVE_SMOKE: %d FAILURES" % _fail.size())
		get_tree().quit(1)
