extends Node2D
class_name TriarchVFX

var clock
var kind := ""
var cells: Array = []
var elapsed := 0.0
var lifetime := 1.0
var title := ""

func set_clock(mgr) -> void:
	clock = mgr

func setup(mgr, mode: String, targets: Array, life: float, text := "") -> void:
	set_clock(mgr)
	kind = mode; cells = targets.duplicate(); lifetime = life; title = text
	z_index = 90 if kind == "card" else (20 if kind in ["meteor_impact", "arrow", "slash", "plates", "bow"] else 6)
	if kind == "card":
		var label := Label.new()
		label.text = title
		label.add_theme_font_size_override("font_size", 36)
		label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.52))
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(0, get_viewport_rect().size.y * 0.24)
		label.size = Vector2(get_viewport_rect().size.x, 55)
		add_child(label)
	queue_redraw()

func _process(delta: float) -> void:
	if not is_instance_valid(clock) or not clock.battle_active: return
	if clock.paused: return
	elapsed += delta * clock.time_scale
	if elapsed >= lifetime: queue_free(); return
	queue_redraw()

func point(cell: Vector2i) -> Vector2:
	return to_local(clock.battle_grid.to_global(clock.battle_grid.grid_to_world(cell)))

func quad(cell: Vector2i) -> PackedVector2Array:
	var grid: BattleGrid = clock.battle_grid
	var q := BoardPerspective.cell_quad(cell.x, cell.y, grid.grid_width, grid.grid_height, grid.cell_size)
	var result := PackedVector2Array()
	for p in q: result.append(to_local(grid.to_global(p)))
	return result

func _draw() -> void:
	if not is_instance_valid(clock): return
	var t := clampf(elapsed / lifetime, 0, 1)
	var gold := Color(1.0, 0.72, 0.25, 0.9)
	var violet := Color(0.75, 0.4, 1.0, 0.95)
	for cell in cells:
		var p := point(cell)
		match kind:
			"line", "cleave", "meteors":
				var color := violet if kind == "meteors" else gold
				var q := quad(cell)
				draw_colored_polygon(q, Color(color, 0.14 + t * 0.12))
				q.append(q[0]); draw_polyline(q, color, 3.0)
				if kind == "meteors":
					# Light splash bounds explain the adjacent-cell damage; the
					# strong centre square still identifies the exact meteor cell.
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							var splash: Vector2i = cell + Vector2i(dx, dy)
							if (dx != 0 or dy != 0) and clock.battle_grid.is_valid_position(splash):
								var bounds := quad(splash); bounds.append(bounds[0])
								draw_polyline(bounds, Color(violet, 0.24), 1.0)
					draw_arc(p, 20 + t * 15, 0, TAU, 40, color, 3)
					# Meteor reaches the centre precisely when the shared channel lands.
					var rock := p + Vector2(40 * (1 - t), -260 * (1 - t))
					draw_line(rock + Vector2(12, -45), rock, Color(1, 0.5, 0.2, 0.8), 12)
					draw_circle(rock, 13, Color(1, 0.9, 0.55))
			"landing":
				draw_set_transform(p, 0, Vector2(1, 0.4))
				draw_circle(Vector2.ZERO, 15 + t * 32, Color(0, 0, 0, 0.2 + t * 0.3))
				draw_arc(Vector2.ZERO, 20 + t * 35, 0, TAU, 48, gold, 4)
				draw_set_transform(Vector2.ZERO)
			"impact", "dust", "shout", "meteor_impact":
				var r := (40 if kind == "meteor_impact" else 12) + t * (135 if kind == "meteor_impact" else 85)
				if kind == "meteor_impact":
					draw_circle(p, 26 * (1 - t), Color(1.0, 0.72, 0.3, 0.9 * (1 - t)))
					draw_circle(p, 12 * (1 - t), Color(1.0, 0.95, 0.8, 1 - t))
				draw_set_transform(p, 0, Vector2(1, 0.5))
				draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(gold, 1 - t), 9 * (1 - t) + 1)
				draw_set_transform(Vector2.ZERO)
				for i in 12:
					var d := Vector2.from_angle(i * TAU / 12.0)
					draw_circle(p + d * r * Vector2(1, 0.5), 5 + t * 9, Color(0.8, 0.72, 0.52, (1 - t) * 0.5))
			"plates", "bow":
				for i in (7 if kind == "plates" else 2):
					var d := Vector2.from_angle(i * 2.4 - 2.0)
					var pos := p + d * t * 85 + Vector2(0, -55 + t * t * 75)
					draw_set_transform(pos, t * (i + 2))
					draw_rect(Rect2(-8, -12, 16, 24) if kind == "plates" else Rect2(-3, -30, 6, 60), Color(0.7, 0.75, 0.85, 1 - t))
					draw_set_transform(Vector2.ZERO)
			"slash":
				draw_arc(p, 42, -PI + t, t, 24, Color(gold, 1 - t), 7)
	if kind == "arrow" and cells.size() > 1:
		# The luminous full-line piercing trail appears on the damage frame.
		draw_line(point(cells[0]), point(cells[-1]), Color(gold, 1 - t), 5)
		var p := point(cells[-1])
		var direction := (p - point(cells[0])).normalized()
		var side := direction.orthogonal()
		draw_colored_polygon(PackedVector2Array([p + direction * 12, p - direction * 8 + side * 8, p - direction * 8 - side * 8]), Color(1, 1, 1, 1 - t))
