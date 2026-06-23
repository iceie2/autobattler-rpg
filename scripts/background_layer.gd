extends Node2D
class_name BackgroundLayer

const GRID_W  := 14
const GRID_H  := 20
const CELL    := 64
const TOTAL_W := GRID_W * CELL   # 896
const TOTAL_H := GRID_H * CELL   # 1280

const ZONE_ROWS := 4   # rows per team zone

func _draw() -> void:
	_draw_base_tiles()
	_draw_enemy_zone()
	_draw_player_zone()
	_draw_grid_lines()
	_draw_border()
	_draw_labels()

# ── Checkerboard stone floor ──────────────────────────────────────────────────
func _draw_base_tiles() -> void:
	var col_a := Color(0.12, 0.13, 0.18)
	var col_b := Color(0.10, 0.11, 0.155)
	for row in range(GRID_H):
		for col in range(GRID_W):
			var c := col_a if (row + col) % 2 == 0 else col_b
			draw_rect(Rect2(col * CELL, row * CELL, CELL, CELL), c)

# ── Enemy zone — rows 0..3, red tint + solid border ──────────────────────────
func _draw_enemy_zone() -> void:
	var zone_h := ZONE_ROWS * CELL

	# Tinted fill (gradient: darker at top, lighter at bottom edge)
	for row in range(ZONE_ROWS):
		var alpha := 0.18 - row * 0.03
		draw_rect(Rect2(0, row * CELL, TOTAL_W, CELL), Color(0.7, 0.08, 0.08, alpha))

	# Thick bottom border marking the zone edge
	var border_y := float(ZONE_ROWS * CELL)
	draw_line(Vector2(0, border_y), Vector2(TOTAL_W, border_y),
		Color(0.9, 0.25, 0.25, 0.9), 3.0)
	# Faint second line for glow effect
	draw_line(Vector2(0, border_y + 2), Vector2(TOTAL_W, border_y + 2),
		Color(1.0, 0.4, 0.4, 0.25), 5.0)

	# Dashed zone pattern along the top edge
	var dash := 24.0
	var gap  := 12.0
	var x    := 0.0
	while x < TOTAL_W:
		draw_line(Vector2(x, 2), Vector2(min(x + dash, TOTAL_W), 2),
			Color(0.9, 0.3, 0.3, 0.6), 3.0)
		x += dash + gap

	# Corner skulls (simple X marks)
	for cx in [24.0, TOTAL_W - 24.0]:
		_draw_x_mark(Vector2(cx, 24), Color(0.85, 0.25, 0.25, 0.8), 8.0)

# ── Player zone — rows 16..19, blue tint + solid border ─────────────────────
func _draw_player_zone() -> void:
	var zone_start := (GRID_H - ZONE_ROWS) * CELL
	var zone_h     := ZONE_ROWS * CELL

	# Tinted fill
	for i in range(ZONE_ROWS):
		var row   := GRID_H - ZONE_ROWS + i
		var alpha := 0.08 + i * 0.03
		draw_rect(Rect2(0, row * CELL, TOTAL_W, CELL), Color(0.1, 0.25, 0.75, alpha))

	# Thick top border
	var border_y := float(zone_start)
	draw_line(Vector2(0, border_y), Vector2(TOTAL_W, border_y),
		Color(0.25, 0.55, 0.95, 0.9), 3.0)
	draw_line(Vector2(0, border_y - 2), Vector2(TOTAL_W, border_y - 2),
		Color(0.4, 0.7, 1.0, 0.25), 5.0)

	# Dashed zone pattern along the bottom edge
	var dash := 24.0
	var gap  := 12.0
	var x    := 0.0
	while x < TOTAL_W:
		draw_line(Vector2(x, TOTAL_H - 2), Vector2(min(x + dash, TOTAL_W), TOTAL_H - 2),
			Color(0.3, 0.6, 0.95, 0.6), 3.0)
		x += dash + gap

	# Corner shield marks
	for cx in [24.0, TOTAL_W - 24.0]:
		_draw_diamond(Vector2(cx, TOTAL_H - 24), Color(0.25, 0.55, 0.95, 0.8), 8.0)

# ── Subtle grid lines ─────────────────────────────────────────────────────────
func _draw_grid_lines() -> void:
	var col := Color(0.0, 0.0, 0.0, 0.3)
	for x in range(GRID_W + 1):
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, TOTAL_H), col, 1.0)
	for y in range(GRID_H + 1):
		draw_line(Vector2(0, y * CELL), Vector2(TOTAL_W, y * CELL), col, 1.0)

# ── Arena border ─────────────────────────────────────────────────────────────
func _draw_border() -> void:
	for i in range(3):
		var a := 0.7 - i * 0.2
		var inset := float(i)
		draw_rect(Rect2(inset, inset, TOTAL_W - inset * 2, TOTAL_H - inset * 2),
			Color(0.3, 0.35, 0.6, a), false, 2.0)

# ── Zone labels ───────────────────────────────────────────────────────────────
func _draw_labels() -> void:
	var font := ThemeDB.fallback_font

	# Enemy zone label (centered in zone)
	var enemy_zone_center_y := float(ZONE_ROWS * CELL) / 2.0
	_draw_label_centered("ENEMY ZONE", Vector2(TOTAL_W / 2.0, enemy_zone_center_y),
		font, 16, Color(1.0, 0.4, 0.4, 0.55))

	# Player zone label
	var player_zone_center_y := float((GRID_H - ZONE_ROWS) * CELL) + float(ZONE_ROWS * CELL) / 2.0
	_draw_label_centered("PLAYER ZONE", Vector2(TOTAL_W / 2.0, player_zone_center_y),
		font, 16, Color(0.4, 0.7, 1.0, 0.55))

# ── Helpers ───────────────────────────────────────────────────────────────────
func _draw_label_centered(text: String, pos: Vector2, font: Font, size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, pos - Vector2(w / 2.0, 0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw_x_mark(center: Vector2, color: Color, s: float) -> void:
	draw_line(center + Vector2(-s, -s), center + Vector2(s, s), color, 2.5)
	draw_line(center + Vector2(s, -s), center + Vector2(-s, s), color, 2.5)

func _draw_diamond(center: Vector2, color: Color, s: float) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -s),
		center + Vector2(s, 0),
		center + Vector2(0, s),
		center + Vector2(-s, 0),
	])
	draw_colored_polygon(pts, color)
