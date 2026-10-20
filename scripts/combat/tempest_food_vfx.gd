extends Node2D
class_name TempestFoodVFX

# Board food is an effect, never a combat unit or a blocking occupant.
# Its animation is driven by the controller's combat clock (pause/speed safe).
const GOLD := Color(1.0,0.86,0.2)
const LIME := Color(0.62,1.0,0.32)
const SWALLOW_TIME := 0.65
var grid: BattleGrid
var cell: Vector2i
var clock := 0.0
var swallowed := false
var swallow_clock := 0.0

func setup(board: BattleGrid, position: Vector2i) -> void:
	grid = board; cell = position; z_index = 2
	queue_redraw()

func advance(dt: float) -> void:
	clock += dt
	if swallowed: swallow_clock += dt
	queue_redraw()

func consume() -> void:
	swallowed = true; swallow_clock = 0.0; queue_redraw()

func finished() -> bool:
	return swallowed and swallow_clock >= SWALLOW_TIME

func _draw() -> void:
	if not is_instance_valid(grid): return
	var centre := to_local(grid.to_global(grid.grid_to_world(cell)))
	var scale := grid.row_scale(cell.y)
	var r: float = grid.cell_size*scale*0.13
	var f := clampf(swallow_clock/SWALLOW_TIME,0,1)
	var a := 1.0-f if swallowed else 1.0
	var bob := Vector2(0,(-12+sin(clock*4)*3)*scale)
	if swallowed:
		draw_arc(centre,r*(1+f*5),0,TAU,32,Color(LIME,a),3*scale)
		for i in 8:
			var direction := Vector2.from_angle(i*TAU/8+clock)
			draw_line(centre+direction*r,centre+direction*r*(1+f*4),Color(GOLD,a),2*scale)
	else:
		draw_arc(centre,r*1.8,0,TAU,32,Color(LIME,0.7),2*scale)
		draw_arc(centre,r*2.15,clock,clock+PI*1.4,28,Color(GOLD,0.8),2*scale)
	draw_circle(centre+bob,r*(1-f)*1.6,Color(LIME,0.12*a))
	draw_circle(centre+bob,r*(1-f),Color(GOLD,a))
	draw_circle(centre+bob+Vector2(-r*0.2,-r*0.25),r*(1-f)*0.43,Color(1,1,0.9,a))
	if not swallowed:
		draw_polyline(PackedVector2Array([centre+bob+Vector2(0,-r*0.8),centre+bob+Vector2(-r*0.25,0),centre+bob+Vector2(r*0.2,0),centre+bob+Vector2(0,r*0.75)]),Color(0.24,0.4,0.04),2*scale)
