extends Node2D
class_name BackgroundLayer

const GRID_W  := 9
const GRID_H  := 9
const CELL    := 110
const TOTAL_W := GRID_W * CELL   # 990
const TOTAL_H := GRID_H * CELL   # 990

const ZONE_ROWS := 4   # rows per team zone

# ── Terrain atlas (LPC Terrains by bluecarrot16 et al, CC-BY-SA — see CREDITS) ──
const TILE := 32   # source tile size in the atlas (scaled up to fill a cell)
var atlas: Texture2D

# ── Zone indicators (toggled by the game) ─────────────────────────────────────
# Player zone: shown only while dragging an allied hero.
# Enemy zone: shown between rounds, hidden once a round starts.
var show_player_zone := false
var show_enemy_zone := true

# ── Gold game-board border ────────────────────────────────────────────────────
const GOLD        := Color(0.83, 0.69, 0.22)   # warm gold
const GOLD_LIGHT  := Color(1.0, 0.9, 0.5)       # highlight
const GOLD_DARK   := Color(0.5, 0.38, 0.1)       # shadow
const BORDER_W    := 14.0                          # thickness of the frame (sits outside the grid)

func set_player_zone_visible(v: bool) -> void:
	if show_player_zone != v:
		show_player_zone = v
		queue_redraw()

func set_enemy_zone_visible(v: bool) -> void:
	if show_enemy_zone != v:
		show_enemy_zone = v
		queue_redraw()

# Per-biome tile coordinates into terrain-v7.png (in 32px tile units).
# "fill" = the base tile painted everywhere; "variants" = textured tiles scattered in.
var biome_tiles := [
	{ "fill": Vector2i(1, 10),  "variants": [Vector2i(0, 12), Vector2i(1, 12), Vector2i(2, 12)] },   # 0 Spring Meadow
	{ "fill": Vector2i(4, 10),  "variants": [Vector2i(3, 12), Vector2i(4, 12), Vector2i(5, 12)] },   # 1 Summer Field
	{ "fill": Vector2i(10, 10), "variants": [Vector2i(9, 12), Vector2i(10, 12), Vector2i(11, 12)] }, # 2 Golden Autumn
	{ "fill": Vector2i(7, 10),  "variants": [Vector2i(6, 12), Vector2i(7, 12)] },                    # 3 Twilight Forest
	{ "fill": Vector2i(1, 10),  "variants": [Vector2i(0, 12), Vector2i(1, 12), Vector2i(2, 12)] },   # 4 Mystical Glade
]

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	atlas = load("res://assets/terrain/terrain-v7.png")
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()   # drives the battle-line pulse animation

# Biome system - changes every 10 levels
var current_biome := 0
var biomes := [
	# Biome 0: Spring Meadow
	{
		"name": "Spring Meadow",
		"grass_light": Color(0.3, 0.65, 0.2),
		"grass_dark": Color(0.25, 0.55, 0.15),
		"sky_tint": Color(0.7, 0.85, 0.9),
		"enemy_zone_color": Color(0.7, 0.08, 0.08),
		"player_zone_color": Color(0.1, 0.25, 0.75),
		"border_color": Color(0.3, 0.35, 0.6),
	},
	# Biome 1: Summer Field
	{
		"name": "Summer Field",
		"grass_light": Color(0.4, 0.7, 0.1),
		"grass_dark": Color(0.35, 0.6, 0.08),
		"sky_tint": Color(0.8, 0.9, 0.7),
		"enemy_zone_color": Color(0.75, 0.15, 0.15),
		"player_zone_color": Color(0.15, 0.35, 0.85),
		"border_color": Color(0.4, 0.45, 0.5),
	},
	# Biome 2: Golden Autumn
	{
		"name": "Golden Autumn",
		"grass_light": Color(0.65, 0.55, 0.1),
		"grass_dark": Color(0.55, 0.45, 0.05),
		"sky_tint": Color(0.9, 0.8, 0.6),
		"enemy_zone_color": Color(0.8, 0.12, 0.12),
		"player_zone_color": Color(0.12, 0.3, 0.8),
		"border_color": Color(0.5, 0.4, 0.3),
	},
	# Biome 3: Twilight Forest
	{
		"name": "Twilight Forest",
		"grass_light": Color(0.2, 0.45, 0.15),
		"grass_dark": Color(0.15, 0.35, 0.1),
		"sky_tint": Color(0.6, 0.65, 0.75),
		"enemy_zone_color": Color(0.6, 0.1, 0.1),
		"player_zone_color": Color(0.1, 0.2, 0.7),
		"border_color": Color(0.25, 0.3, 0.45),
	},
	# Biome 4: Mystical Glade
	{
		"name": "Mystical Glade",
		"grass_light": Color(0.25, 0.6, 0.4),
		"grass_dark": Color(0.2, 0.5, 0.3),
		"sky_tint": Color(0.7, 0.7, 0.85),
		"enemy_zone_color": Color(0.7, 0.08, 0.25),
		"player_zone_color": Color(0.1, 0.4, 0.8),
		"border_color": Color(0.3, 0.35, 0.5),
	},
]

func set_biome_from_round(battle_round: int) -> void:
	var new_biome = (battle_round - 1) / 10 % biomes.size()
	if new_biome != current_biome:
		current_biome = new_biome
		queue_redraw()

func _draw() -> void:
	_draw_base_tiles()
	_draw_cell_shading()
	if show_enemy_zone:
		_draw_enemy_zone()
	if show_player_zone:
		_draw_player_zone()
	_draw_battle_line()
	_draw_vignette()
	_draw_grid_dots()
	_draw_border()
	_draw_labels()

# ── Grassy meadow terrain from the LPC atlas ──────────────────────────────────
func _draw_base_tiles() -> void:
	var tiles: Dictionary = biome_tiles[current_biome % biome_tiles.size()]
	var fill: Vector2i = tiles["fill"]
	var variants: Array = tiles["variants"]

	for row in range(GRID_H):
		for col in range(GRID_W):
			var h := _hash2(col, row)
			var tcoord := fill
			# ~22% of cells get a textured variant tile for a natural, broken-up look
			if not variants.is_empty() and h % 9 < 2:
				tcoord = variants[(h / 9) % variants.size()]
			_blit_tile(col, row, tcoord)

# Deterministic non-banding hash so scattered tiles don't line up diagonally.
func _hash2(x: int, y: int) -> int:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return abs(h ^ (h >> 16)) % 1000

func _blit_tile(col: int, row: int, tcoord: Vector2i) -> void:
	var dest := Rect2(col * CELL, row * CELL, CELL, CELL)
	if atlas == null:
		# Fallback flat colour if the atlas hasn't imported yet
		draw_rect(dest, Color(0.3, 0.55, 0.2))
		return
	var src := Rect2(tcoord.x * TILE, tcoord.y * TILE, TILE, TILE)
	draw_texture_rect_region(atlas, dest, src)

# ── Enemy zone — rows 0..3, red tint + solid border ──────────────────────────
func _draw_enemy_zone() -> void:
	var biome = biomes[current_biome]
	var enemy_color = biome["enemy_zone_color"]

	# Tinted fill (gradient: darker at top, lighter at bottom edge)
	for row in range(ZONE_ROWS):
		var alpha := 0.4 - row * 0.01
		draw_rect(Rect2(0, row * CELL, TOTAL_W, CELL), Color(enemy_color.r, enemy_color.g, enemy_color.b, alpha))

	# Thick bottom border marking the zone edge
	var border_y := float(ZONE_ROWS * CELL)
	var border_bright = enemy_color.lightened(0.5)
	draw_line(Vector2(0, border_y), Vector2(TOTAL_W, border_y),
		Color(border_bright.r, border_bright.g, border_bright.b, 0.9), 3.0)
	# Faint second line for glow effect
	draw_line(Vector2(0, border_y + 2), Vector2(TOTAL_W, border_y + 2),
		Color(border_bright.r, border_bright.g, border_bright.b, 2.0), 10.0)

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

# ── Player zone — rows 10..13, blue tint + solid border ─────────────────────
func _draw_player_zone() -> void:
	var biome = biomes[current_biome]
	var player_color = biome["player_zone_color"]
	var zone_start := (GRID_H - ZONE_ROWS) * CELL

	# Tinted fill
	for i in range(ZONE_ROWS):
		var row   := GRID_H - ZONE_ROWS + i
		var alpha := 0.4 + i * 0.01
		draw_rect(Rect2(0, row * CELL, TOTAL_W, CELL), Color(player_color.r, player_color.g, player_color.b, alpha))

	# Thick top border
	var border_y := float(zone_start)
	var border_bright = player_color.lightened(0.4)
	draw_line(Vector2(0, border_y), Vector2(TOTAL_W, border_y),
		Color(border_bright.r, border_bright.g, border_bright.b, 0.9), 3.0)
	draw_line(Vector2(0, border_y - 2), Vector2(TOTAL_W, border_y - 2),
		Color(border_bright.r, border_bright.g, border_bright.b, 0.25), 5.0)

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

# ── Corner dots (replace harsh grid lines) ───────────────────────────────────
func _draw_grid_dots() -> void:
	var biome: Dictionary = biomes[current_biome]
	var dot_c: Color = biome["border_color"]
	dot_c.a = 0.55
	for xi in range(GRID_W + 1):
		for yi in range(GRID_H + 1):
			draw_circle(Vector2(xi * CELL, yi * CELL), 2.5, dot_c)

# ── Checkerboard cell shading ─────────────────────────────────────────────────
# Alternates a very faint light/dark wash per cell — breaks up the flat terrain
# and makes individual cells readable without a grid line.
func _draw_cell_shading() -> void:
	for row in range(GRID_H):
		for col in range(GRID_W):
			if (row + col) % 2 == 0:
				draw_rect(Rect2(col * CELL, row * CELL, CELL, CELL), Color(1, 1, 1, 0.055))
			else:
				draw_rect(Rect2(col * CELL, row * CELL, CELL, CELL), Color(0, 0, 0, 0.07))

# ── Battle-line separator ─────────────────────────────────────────────────────
# Pulsing glow at the board centre — uses the biome's zone colours so it
# automatically fits every environment. Diamond markers at each column edge.
func _draw_battle_line() -> void:
	var t     := Time.get_ticks_msec() * 0.001
	var pulse := 0.5 + 0.3 * sin(t * 1.8)
	var mid_y := TOTAL_H * 0.5

	var biome: Dictionary = biomes[current_biome]
	var ec: Color = biome["enemy_zone_color"]
	var pc: Color = biome["player_zone_color"]
	var lc := Color((ec.r + pc.r) * 0.5, (ec.g + pc.g) * 0.5, (ec.b + pc.b) * 0.5).lightened(0.55)

	# Layered soft glow (widest strip at lowest alpha, narrowing toward core)
	for i in range(5, 0, -1):
		draw_line(Vector2(0, mid_y), Vector2(TOTAL_W, mid_y),
			Color(lc.r, lc.g, lc.b, pulse * 0.045 * i), float(i) * 7.0)
	# Sharp core line
	draw_line(Vector2(0, mid_y), Vector2(TOTAL_W, mid_y),
		Color(lc.r, lc.g, lc.b, pulse * 0.9), 2.0)
	# Diamond marker at each column boundary
	var step := float(TOTAL_W) / float(GRID_W)
	for i in range(GRID_W + 1):
		_draw_diamond(Vector2(i * step, mid_y),
			Color(lc.r, lc.g, lc.b, pulse * 0.75), 5.0)

# ── Edge vignette ─────────────────────────────────────────────────────────────
# Dark gradient inward from all four edges — draws the eye to the centre.
func _draw_vignette() -> void:
	var steps    := 10
	var max_depth := 72.0
	var band      := max_depth / float(steps)
	for i in range(steps):
		var a := pow(float(steps - i) / float(steps), 2.0) * 0.20
		var d := float(i) / float(steps) * max_depth
		var c := Color(0, 0, 0, a)
		draw_rect(Rect2(0,              d,              TOTAL_W, band), c)   # top
		draw_rect(Rect2(0,              TOTAL_H-d-band, TOTAL_W, band), c)   # bottom
		draw_rect(Rect2(d,              0,              band, TOTAL_H), c)   # left
		draw_rect(Rect2(TOTAL_W-d-band, 0,              band, TOTAL_H), c)   # right

# ── Gold game-board border ────────────────────────────────────────────────────
func _draw_border() -> void:
	var w := BORDER_W
	# The frame sits entirely OUTSIDE the playable grid (grid spans 0..TOTAL),
	# so no cell is ever covered. Bars are drawn in the margin around the board.
	draw_rect(Rect2(-w, -w, TOTAL_W + 2 * w, w), GOLD)            # top
	draw_rect(Rect2(-w, TOTAL_H, TOTAL_W + 2 * w, w), GOLD)       # bottom
	draw_rect(Rect2(-w, -w, w, TOTAL_H + 2 * w), GOLD)           # left
	draw_rect(Rect2(TOTAL_W, -w, w, TOTAL_H + 2 * w), GOLD)      # right
	# Dark outer edge for depth
	draw_rect(Rect2(-w, -w, TOTAL_W + 2 * w, TOTAL_H + 2 * w), GOLD_DARK, false, 2.0)
	# Bright inner edge hugging the grid
	draw_rect(Rect2(-1, -1, TOTAL_W + 2, TOTAL_H + 2), GOLD_LIGHT, false, 2.0)
	# Corner studs centred in the frame corners for a game-board feel
	var r := w * 0.5
	for c in [Vector2(-w * 0.5, -w * 0.5), Vector2(TOTAL_W + w * 0.5, -w * 0.5),
			Vector2(-w * 0.5, TOTAL_H + w * 0.5), Vector2(TOTAL_W + w * 0.5, TOTAL_H + w * 0.5)]:
		draw_circle(c, r, GOLD_LIGHT)
		draw_circle(c, r * 0.55, GOLD_DARK)

# ── Zone labels (only shown alongside their active zone) ───────────────────────
func _draw_labels() -> void:
	var font := ThemeDB.fallback_font

	if show_enemy_zone:
		var enemy_zone_center_y := float(ZONE_ROWS * CELL) / 2.0
		_draw_label_centered("ENEMY ZONE", Vector2(TOTAL_W / 2.0, enemy_zone_center_y),
			font, 16, Color(1.0, 0.4, 0.4, 0.55))

	if show_player_zone:
		var player_zone_center_y := float((GRID_H - ZONE_ROWS) * CELL) + float(ZONE_ROWS * CELL) / 2.0
		_draw_label_centered("PLACE HERE", Vector2(TOTAL_W / 2.0, player_zone_center_y),
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
