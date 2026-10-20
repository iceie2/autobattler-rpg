extends Node2D
class_name TempestTrailVFX

# The controller owns the clock, so warning, pause and discharge match combat.
# Draw the same perspective-projected cells that the hit test uses.
const ICE := Color(0.18, 0.85, 1.0)
const WHITE := Color(0.84, 0.99, 1.0)
var grid: BattleGrid
var cells: Array[Vector2i] = []
var mode := "laying"
var progress := 0.0
var clock := 0.0
var surge := false
var lead := Vector2.ZERO

func setup(board: BattleGrid, is_surge: bool) -> void:
	grid = board
	surge = is_surge
	z_index = 1

func show_state(path: Array[Vector2i], phase: String, fraction: float, t: float, head_pos: Vector2) -> void:
	cells = path.duplicate()
	mode = phase
	progress = fraction
	clock = t
	lead = head_pos
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(grid): return
	var dormant: bool = mode == "dormant"
	var firing: bool = mode == "discharge"
	var a: float = 0.26 if dormant else (1.0-progress if firing else 0.65+0.25*sin(clock*8.0))
	var stroke: Color = WHITE if firing else ICE
	var centres := PackedVector2Array()
	for cell in cells:
		var quad := BoardPerspective.cell_quad(cell.x, cell.y, grid.grid_width, grid.grid_height, grid.cell_size)
		var local_quad := PackedVector2Array()
		for point in quad: local_quad.append(to_local(grid.to_global(point)))
		var c: Vector2 = to_local(grid.to_global(grid.grid_to_world(cell)))
		centres.append(c)
		if not dormant:
			draw_colored_polygon(local_quad, Color(0.06,0.50,0.8,a*(0.48 if firing else 0.14)))
			var outline: PackedVector2Array = local_quad.duplicate()
			outline.append(outline[0])
			draw_polyline(outline, Color(stroke,a), 3.0 if firing else 1.6)
		var r: float = grid.cell_size * grid.row_scale(cell.y) * 0.16
		draw_arc(c,r,0,TAU,20,Color(stroke,a),2.5)
		# A shrinking rune indicates how close the circuit is to firing.
		if mode == "charging":
			draw_arc(c,r*(1.9-progress),-PI/2,TAU-PI/2,24,Color(WHITE,a),2.0)
		if firing:
			for side in [-1.0,1.0]:
				var p := PackedVector2Array([c+Vector2(side*25,-65),c+Vector2(-side*12,-38),c+Vector2(side*8,-18),c])
				draw_polyline(p,Color(ICE,a*0.4),8.0)
				draw_polyline(p,Color(WHITE,a),2.5)
	if mode == "laying" and not cells.is_empty(): centres.append(to_local(lead))
	if centres.size() >= 2:
		var current := PackedVector2Array()
		for i in range(centres.size()-1):
			var a_pos: Vector2 = centres[i]
			var b_pos: Vector2 = centres[i+1]
			var normal: Vector2 = (b_pos-a_pos).orthogonal().normalized()
			for j in 8:
				var f: float = float(j)/8.0
				current.append(a_pos.lerp(b_pos,f)+normal*sin(f*TAU*1.5+clock*12)*sin(f*PI)*5.0)
		current.append(centres[-1])
		draw_polyline(current,Color(0.02,0.08,0.16,a),10.0)
		draw_polyline(current,Color(stroke,a),5.0 if surge else 3.0)
		if not dormant: draw_polyline(current,Color(WHITE,a),1.3)
