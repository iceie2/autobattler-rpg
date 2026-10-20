extends Node2D
class_name WardenVFX

var cells: Array = []
var grid
var manager
var life := 1.0
var elapsed := 0.0
var warning := false
var burst := false

func _process(dt: float) -> void:
	if is_instance_valid(manager):
		if manager.paused: return
		dt *= manager.time_scale
	elapsed += dt
	if elapsed >= life: queue_free()
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(grid): return
	var size: float = grid.cell_size * 0.44
	var color := Color(1.0, 0.35, 0.45) if warning else Color(0.45, 0.88, 1.0)
	color.a = 0.85 if not burst else maxf(0, 1.0 - elapsed / life)
	for cell in cells:
		var p: Vector2 = to_local(grid.to_global(grid.grid_to_world(cell)))
		var shape := PackedVector2Array([p+Vector2(-size,-size),p+Vector2(size,-size),p+Vector2(size,size),p+Vector2(-size,size),p+Vector2(-size,-size)])
		draw_colored_polygon(shape, Color(color, 0.16))
		draw_polyline(shape, color, 3.0)
		for i in 4:
			var end: Vector2 = p + Vector2.from_angle(i * PI / 2 + 0.4) * size * (1.0 + (elapsed / life * 2 if burst else 0))
			draw_line(p, end, color, 2.0)
		if warning: draw_arc(p, size * (0.35 + 0.25 * sin(elapsed * 12)), 0, TAU, 24, color, 3)

