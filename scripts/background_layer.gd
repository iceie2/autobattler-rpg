extends Node2D
class_name BackgroundLayer

# Drawn once behind the battle grid.
# Sizes match BattleGrid: 22 cols × 14 rows × 64 px per cell = 1408 × 896
const GRID_W  := 22
const GRID_H  := 14
const CELL    := 64
const TOTAL_W := GRID_W * CELL   # 1408
const TOTAL_H := GRID_H * CELL   # 896

# Zone split: enemies top 4 rows, players bottom 4 rows, neutral middle
const ENEMY_ROWS  := 4
const PLAYER_ROWS := 4

func _draw() -> void:
	_draw_base()
	_draw_zones()
	_draw_stone_tiles()
	_draw_border()

func _draw_base() -> void:
	# Rich dark-blue gradient background
	var rect := Rect2(0, 0, TOTAL_W, TOTAL_H)
	draw_rect(rect, Color(0.06, 0.07, 0.12))

func _draw_zones() -> void:
	# Enemy zone — subtle red tint overlay
	var enemy_h := ENEMY_ROWS * CELL
	for i in range(ENEMY_ROWS):
		var alpha := 0.06 + 0.02 * (ENEMY_ROWS - 1 - i)
		draw_rect(Rect2(0, i * CELL, TOTAL_W, CELL), Color(0.6, 0.05, 0.05, alpha))

	# Player zone — subtle blue tint overlay
	var player_start := (GRID_H - PLAYER_ROWS) * CELL
	for i in range(PLAYER_ROWS):
		var alpha := 0.04 + 0.02 * i
		draw_rect(Rect2(0, player_start + i * CELL, TOTAL_W, CELL), Color(0.05, 0.15, 0.5, alpha))

	# Neutral divider line in center
	var mid_y := float(GRID_H / 2) * CELL
	draw_line(Vector2(0, mid_y), Vector2(TOTAL_W, mid_y), Color(0.3, 0.3, 0.5, 0.3), 2.0)

func _draw_stone_tiles() -> void:
	# Subtle stone-block pattern on the floor
	var tile_col_a := Color(0.12, 0.13, 0.18)
	var tile_col_b := Color(0.10, 0.11, 0.16)
	for row in range(GRID_H):
		for col in range(GRID_W):
			var checker := (row + col) % 2
			var c := tile_col_a if checker == 0 else tile_col_b
			draw_rect(Rect2(col * CELL, row * CELL, CELL, CELL), c)
			# Subtle inner shadow lines on each tile
			var x := col * CELL
			var y := row * CELL
			draw_line(Vector2(x, y), Vector2(x + CELL, y), Color(0.0, 0.0, 0.0, 0.25), 1.0)
			draw_line(Vector2(x, y), Vector2(x, y + CELL), Color(0.0, 0.0, 0.0, 0.25), 1.0)
			draw_line(Vector2(x + CELL, y), Vector2(x + CELL, y + CELL), Color(0.25, 0.25, 0.3, 0.15), 1.0)
			draw_line(Vector2(x, y + CELL), Vector2(x + CELL, y + CELL), Color(0.25, 0.25, 0.3, 0.15), 1.0)

func _draw_border() -> void:
	# Glowing border around the whole arena
	for i in range(4):
		var alpha := 0.5 - i * 0.1
		var inset := float(i)
		draw_rect(
			Rect2(inset, inset, TOTAL_W - inset * 2, TOTAL_H - inset * 2),
			Color(0.3, 0.35, 0.6, alpha), false, 1.5
		)

	# Corner runes (simple diamond glyphs)
	var corners := [
		Vector2(24, 24), Vector2(TOTAL_W - 24, 24),
		Vector2(24, TOTAL_H - 24), Vector2(TOTAL_W - 24, TOTAL_H - 24)
	]
	for c in corners:
		_draw_rune(c, Color(0.4, 0.5, 0.9, 0.7))

	# Top "ENEMY" and bottom "PLAYER" zone labels
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(8, 20), "ENEMY ZONE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.4, 0.4, 0.55))
	draw_string(font, Vector2(8, TOTAL_H - 6), "PLAYER ZONE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.4, 0.6, 0.95, 0.55))

func _draw_rune(center: Vector2, color: Color) -> void:
	var s := 10.0
	var pts := PackedVector2Array([
		center + Vector2(0, -s),
		center + Vector2(s, 0),
		center + Vector2(0, s),
		center + Vector2(-s, 0),
	])
	draw_colored_polygon(pts, color)
	for i in pts.size():
		draw_line(pts[i], pts[(i + 1) % pts.size()], Color(1, 1, 1, 0.4), 1.0)
