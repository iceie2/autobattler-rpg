extends RefCounted
class_name BoardPerspective

## The single source of truth for the board's faked perspective.
##
## The board reads as a plane tilting away from the camera (TFT-style) without
## anything actually becoming 3D: far rows are drawn narrower and shorter, near
## rows wider and taller, and units scale with the row they stand on. Everything
## stays 2D — the grid, the drag & drop, the health bars, the 25 heroes still on
## sprite art — which is the whole point of doing it this way.
##
## BattleGrid (grid_to_world / world_to_grid) and BackgroundLayer (tile drawing)
## BOTH read from here. They must never compute perspective independently: the
## instant they disagree, units stand off their tiles and drag-drop targets the
## wrong cell, and that is very hard to see in a screenshot.
##
## Row 0 is the FAR edge (top of screen, enemy back line); row H-1 is NEAREST.

## Width of the far row as a fraction of the near row. 1.0 disables the effect
## entirely and restores the old flat board, which makes this a one-constant
## kill switch if the look doesn't work out.
##
## DERIVED from PITCH_DEG / CAMERA_DISTANCE below rather than hand-set, so the
## board's taper and the 3D characters' camera tilt cannot drift apart — see
## those constants for the model and why it's worth deriving.
const FAR_SCALE := (CAMERA_DISTANCE - 0.5 * COS_PITCH) / (CAMERA_DISTANCE + 0.5 * COS_PITCH)

## The angle the whole game is viewed from, in degrees above the board plane.
## 90 = straight down, 0 = edge-on. THIS IS THE ONE KNOB for the tabletop look.
##
## Every 3D hero's SubViewport camera reads this too (VisualUnit's
## MODEL_CAMERA_PITCH_DEG), which is the point of it living here: the board is a
## 2D fake and the characters are real 3D, and before this they were two
## unrelated hand-picked numbers that happened to agree.
##
## The board is still NOT vertically foreshortened by the pitch — its total
## height stays grid_h * cell no matter what this is, because the surrounding
## layout, the gold frame and the side rails are all built against that fixed
## footprint (see row_height). Pitch drives the taper and the characters only.
const PITCH_DEG := 28.0

## Camera distance from the board's centre, in board-lengths. Together with
## PITCH_DEG this fixes the taper: a nearer camera tapers harder.
##
## 3.18 is not invented — it is the distance that REPRODUCES the taper the board
## shipped with (the hand-tuned FAR_SCALE 0.74 at the models' hand-picked 18°
## pitch). Keeping it fixed while PITCH_DEG moves means changing the view angle
## re-tilts the characters without also resizing the board under them.
const CAMERA_DISTANCE := 3.18

const COS_PITCH := cos(deg_to_rad(PITCH_DEG))

## How much of the board's height the far rows give up. The board's total
## footprint is UNCHANGED — near rows simply take more of it than far ones — so
## no surrounding layout, frame or UI has to move.
const DEPTH_STRENGTH := 1.0


## Scale factor for row `y`: FAR_SCALE at the back, 1.0 at the front.
static func row_scale(y: float, grid_h: int) -> float:
	if grid_h <= 1:
		return 1.0
	var t: float = clampf(y / float(grid_h - 1), 0.0, 1.0)
	return lerpf(FAR_SCALE, 1.0, t)


## Height in pixels of row `y`. Rows are weighted by their scale and then
## normalised so the rows still sum to exactly grid_h * cell, keeping the board
## the same total size as the flat version.
static func row_height(y: int, grid_h: int, cell: float) -> float:
	var total_weight: float = 0.0
	for r in grid_h:
		total_weight += _depth_weight(r, grid_h)
	if total_weight <= 0.0:
		return cell
	return _depth_weight(y, grid_h) / total_weight * (grid_h * cell)


## Distance from the CENTRE of a `span`-row-tall footprint standing with its top
## row at `y`, down to the near edge it stands on — i.e. where the character's
## feet belong, measured from the node's own origin.
##
## This replaces a flat half-cell (55px). A far row is physically shorter than a
## near one, so a constant plants the feet below a far tile's edge and above a
## near one's; only the row's own height gets a character standing ON its tile
## at every depth.
static func foot_offset(y: int, grid_h: int, cell: float, span: int = 1) -> float:
	var acc: float = 0.0
	for r in range(y, mini(y + maxi(span, 1), grid_h)):
		acc += row_height(r, grid_h, cell)
	return acc * 0.5


## Y of the TOP edge of row `y`, in board-local pixels.
static func row_top(y: int, grid_h: int, cell: float) -> float:
	var acc: float = 0.0
	for r in range(mini(y, grid_h)):
		acc += row_height(r, grid_h, cell)
	return acc


## Centre point of a cell, in board-local pixels. This is what a unit standing on
## that cell is positioned at.
static func cell_centre(col: float, row: float, grid_w: int, grid_h: int, cell: float) -> Vector2:
	var ri: int = int(floor(row))
	var frac: float = row - float(ri)
	var top: float = row_top(clampi(ri, 0, grid_h - 1), grid_h, cell)
	var h: float = row_height(clampi(ri, 0, grid_h - 1), grid_h, cell)
	var y: float = top + h * (0.5 + frac)
	# X fans out from the board's centre line by the row's scale, which is what
	# makes the side edges converge toward the far end.
	var s: float = row_scale(row, grid_h)
	var centre_x: float = grid_w * cell * 0.5
	var x: float = centre_x + (col + 0.5 - grid_w * 0.5) * cell * s
	return Vector2(x, y)


## Inverse of cell_centre: board-local pixels back to a (possibly out-of-range)
## grid coordinate. Drag & drop and every click test depend on this being the
## exact inverse, so it walks the same row bands rather than approximating.
static func world_to_cell(local: Vector2, grid_w: int, grid_h: int, cell: float) -> Vector2i:
	# Which row band does this y fall in?
	var row: int = -1
	var acc: float = 0.0
	for r in grid_h:
		var h: float = row_height(r, grid_h, cell)
		if local.y >= acc and local.y < acc + h:
			row = r
			break
		acc += h
	if row < 0:
		# Above the board, or below it — report a row outside the grid so
		# is_valid_position() rejects it instead of clamping into a real cell.
		row = -1 if local.y < 0.0 else grid_h
	var s: float = row_scale(clampf(float(row), 0.0, float(grid_h - 1)), grid_h)
	var centre_x: float = grid_w * cell * 0.5
	var col: float = (local.x - centre_x) / (cell * s) + grid_w * 0.5
	return Vector2i(floori(col), row)


## The four corners of a cell's trapezoid, clockwise from top-left. Used by the
## tile renderer — a cell is NOT a rectangle any more, because its top edge sits
## further back than its bottom edge and is therefore narrower.
static func cell_quad(col: int, row: int, grid_w: int, grid_h: int, cell: float) -> PackedVector2Array:
	var top: float = row_top(row, grid_h, cell)
	var bot: float = top + row_height(row, grid_h, cell)
	# Scale is sampled at the row's edges, not its centre, so neighbouring rows
	# share an edge exactly and no seam opens up between them.
	var s_top: float = row_scale(float(row) - 0.5, grid_h)
	var s_bot: float = row_scale(float(row) + 0.5, grid_h)
	var centre_x: float = grid_w * cell * 0.5
	var l_top: float = centre_x + (col - grid_w * 0.5) * cell * s_top
	var r_top: float = centre_x + (col + 1 - grid_w * 0.5) * cell * s_top
	var l_bot: float = centre_x + (col - grid_w * 0.5) * cell * s_bot
	var r_bot: float = centre_x + (col + 1 - grid_w * 0.5) * cell * s_bot
	return PackedVector2Array([
		Vector2(l_top, top), Vector2(r_top, top),
		Vector2(r_bot, bot), Vector2(l_bot, bot),
	])


## The board's outer outline, clockwise from top-left. The playing surface is a
## trapezoid now, so anything that used to be drawn as a rect AROUND the board
## (the gold frame) has to follow this instead.
static func board_outline(grid_w: int, grid_h: int, cell: float) -> PackedVector2Array:
	var tl := cell_quad(0, 0, grid_w, grid_h, cell)
	var tr := cell_quad(grid_w - 1, 0, grid_w, grid_h, cell)
	var br := cell_quad(grid_w - 1, grid_h - 1, grid_w, grid_h, cell)
	var bl := cell_quad(0, grid_h - 1, grid_w, grid_h, cell)
	return PackedVector2Array([tl[0], tr[1], br[2], bl[3]])


## Push a convex quad outward by `amount` along each edge's outward normal.
##
## Offsetting the CORNERS radially would thin the frame on the slanted sides —
## each edge has to move by the full thickness along its own normal, then the
## new corners come from intersecting adjacent offset edges. That is what keeps
## the gold band a constant width all the way around a tapered board.
static func expand_quad(q: PackedVector2Array, amount: float) -> PackedVector2Array:
	if q.size() != 4:
		return q
	var lines := []           # each entry: [point_on_line, direction]
	for i in 4:
		var a: Vector2 = q[i]
		var b: Vector2 = q[(i + 1) % 4]
		var dir: Vector2 = (b - a).normalized()
		# Clockwise winding in Godot's y-down space: outward normal is (y, -x).
		var n := Vector2(dir.y, -dir.x)
		lines.append([a + n * amount, dir])
	var out := PackedVector2Array()
	for i in 4:
		# Corner i of the expanded quad is where edge (i-1) meets edge i.
		var prev: Array = lines[(i + 3) % 4]
		var cur: Array = lines[i]
		out.append(_line_intersect(prev[0], prev[1], cur[0], cur[1], q[i]))
	return out


static func _line_intersect(p1: Vector2, d1: Vector2, p2: Vector2, d2: Vector2,
		fallback: Vector2) -> Vector2:
	var denom: float = d1.cross(d2)
	if absf(denom) < 0.00001:
		return fallback   # parallel edges (a degenerate board) — don't NaN
	return p1 + d1 * ((p2 - p1).cross(d2) / denom)


## Weight used to distribute the board's fixed height across rows.
static func _depth_weight(y: int, grid_h: int) -> float:
	var s: float = row_scale(float(y), grid_h)
	return lerpf(1.0, s, DEPTH_STRENGTH)
