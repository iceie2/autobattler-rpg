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

# Ground props (scattered decals from arena_props.py — see [[arena_prop_pipeline]]).
# OFF by default (2026-07-28 user call): static, non-animated decal clutter
# next to static, non-animated unit sprites reads as visual noise rather than
# atmosphere. Base tile + backdrop still render per biome either way — this
# only gates the scattered grass/rock/flower props on top. Kept as a toggle,
# not deleted, because the whole pipeline (50 props/decade, prep tooling) is
# staying for whenever animated sprites make decals worth the clutter again.
var show_ground_props := false

func set_ground_props_visible(v: bool) -> void:
	if show_ground_props != v:
		show_ground_props = v
		queue_redraw()

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
	atlas = load("res://assets/terrain/terrain-v7.png")
	_sync_texture_filter()
	queue_redraw()

# Filtering has to follow the art style of the current decade, and both live on
# this one CanvasItem (decals must stay in the same _draw as the base so they
# layer *under* the zone tints and battle line):
#   • decades with generated art → painterly tile + decals scaled to 46-92px
#     from a 256px source and rotated, which NEAREST turns into sparkle.
#   • decades still on the legacy LPC atlas → 32px tiles upscaled to 110px
#     cells, which NEAREST is required to keep crisp.
func _sync_texture_filter() -> void:
	var has_art := _load_arena_art(_decade_range() + "/ready/tile.png") != null
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if has_art \
		else CanvasItem.TEXTURE_FILTER_NEAREST

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
	if battle_round != _decal_round:
		_decal_round = battle_round   # re-rolls the decal scatter each wave
		_sync_texture_filter()
		queue_redraw()
	_set_side_backdrop_from_round(battle_round)

# ── Side backdrops (tall scenes filling the gap between the arena and the
# sidebars) — one elemental illustration per 10-round decade, wrapping once
# the roster of generated art runs out. Missing files are skipped silently
# so partially-completed art sets don't break the arena. ──────────────────
const BACKDROP_DIR := "res://assets/terrain/biomes/"
# Canonical decade→element order (wave_structure_1_100, locked): Normal, Air,
# Water, Earth, Fire, Lightning for waves 1-60, then wraps for the mixed
# 61-100 endgame acts. All 6 backdrop images now exist on disk (2026-07-28).
const BACKDROP_ORDER := ["normal", "air", "water", "earth", "fire", "lightning"]

var _backdrop_cache := {}
var side_backdrop_texture: Texture2D

func _load_side_backdrop(biome_name: String) -> Texture2D:
	if _backdrop_cache.has(biome_name):
		return _backdrop_cache[biome_name]
	var path := BACKDROP_DIR + biome_name + "_backdrop.png"
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		push_warning("BackgroundLayer: no side backdrop found at %s" % path)
		return null   # don't cache a miss — retry next round in case the file lands later
	_backdrop_cache[biome_name] = tex
	return tex

func _set_side_backdrop_from_round(battle_round: int) -> void:
	var decade := (battle_round - 1) / 10
	var biome_name: String = BACKDROP_ORDER[decade % BACKDROP_ORDER.size()]
	var tex := _load_side_backdrop(biome_name)
	if tex != side_backdrop_texture:
		side_backdrop_texture = tex
		queue_redraw()

func _draw_side_backdrops() -> void:
	if side_backdrop_texture == null:
		return
	# One full-viewport image behind everything, cover-fit (scaled + cropped,
	# never distorted) and centred. The arena and sidebars paint over the
	# middle, so only the outer edges of the image end up visible — avoids
	# having to hand-place separate left/right strips (and the seam/mirror
	# weirdness that came with it).
	var vp_size := get_viewport_rect().size
	var tex_size := side_backdrop_texture.get_size()
	var s: float = max(vp_size.x / tex_size.x, vp_size.y / tex_size.y)
	var draw_size: Vector2 = tex_size * s
	# Centre on the board's own centre (local space) rather than trying to
	# compensate for the node's position within the viewport — that inversion
	# only holds when this node sits at the viewport's exact centre, which
	# breaks in layouts like the arena sandbox that place the board off to
	# one side. Centring on the board itself is layout-independent.
	var board_center := Vector2(TOTAL_W, TOTAL_H) * 0.5
	var top_left: Vector2 = board_center - draw_size * 0.5
	draw_texture_rect(side_backdrop_texture, Rect2(top_left, draw_size), false)

func _draw() -> void:
	_draw_side_backdrops()
	_draw_base_tiles()
	if show_ground_props:
		_draw_ground_decals()
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

# ── Base ground ───────────────────────────────────────────────────────────────
# A decade with its own generated tile (assets/UI/arena/<range>/ready/tile.png)
# uses it; everything else still falls back to the legacy LPC atlas below.
#
# The tile is drawn with draw_texture_rect(tile: true), which repeats it at its
# NATIVE size — so a 512px texture covers the 990px board about twice at a
# strict 1:1 pixel ratio. That matters: scaling it to fit the 110px cell grid
# instead would make it repeat once per cell, which is precisely the visible
# grid rhythm the base/decal split exists to avoid.
func _draw_base_tiles() -> void:
	var decade_tile := _load_arena_art(_decade_range() + "/ready/tile.png")
	if decade_tile != null:
		draw_texture_rect(decade_tile, Rect2(0, 0, TOTAL_W, TOTAL_H), true)
		return

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

# ── Ground decals ─────────────────────────────────────────────────────────────
# Scattered elements (flower clumps, bare earth, pebbles, tufts) layered over
# the base tile instead of being baked into it. Baking them in made the features
# repeat on an obvious fixed grid every time the tile wrapped; placing them here
# with a per-cell hash — plus per-instance offset, rotation, scale and mirroring
# — means the eye can't find the period even though the base texture repeats.
#
# EVERYTHING here must stay deterministic: _process() calls queue_redraw() every
# frame, so a randi() would make the decals strobe. The hash is seeded with the
# round number so each wave gets a fresh layout from the same art.
#
# Art is organised per DECADE (assets/UI/arena/<lo>-<hi>/ready/), not per biome
# name — one folder per 10 waves, matching how the run is actually structured.
# `ready/` holds the processed, game-ready files; the raw generations with their
# magenta backgrounds stay in the parent folder as the source of truth.
const ARENA_ART_DIR := "res://assets/UI/arena/"

# ── Prop taxonomy ─────────────────────────────────────────────────────────────
# Decals are DISCOVERED, not listed. The code probes <kind>_1 … <kind>_<MAX_
# VARIANTS> per decade and uses whatever exists — adding art is a drop-in, no
# manifest to keep in sync across ten folders.
#
# Kind NAMES are per-decade — "grass" makes no sense as a floor prop on a
# floating sky island, so Air gets cloud/crystal/feather/mist/stone instead of
# a reskinned grass/flower/branch/dirt/rock (an earlier pass did exactly that
# reskin and it read as forced; see [[arena_prop_pipeline]]). What IS shared
# across every decade is the STRUCTURE: 5 roles in a fixed weight/size order —
# main ground cover, small colour accent, scattered debris, high-contrast
# ground patch, hard detail — because that's what reads as "one aesthetic
# floor" no matter what the biome's own vocabulary is. `arena_props.py` is the
# single source of truth for both the kind names and the weights below; keep
# this dict in sync with it by hand (there's no shared codegen between GDScript
# and Python here).
const ROLE_WEIGHTS := [4, 2, 1, 1, 1]
const ROLE_SIZES := [
	{ "min": 72.0, "max": 130.0 },   # main cover — biggest, most common
	{ "min": 48.0, "max": 84.0 },    # accent
	{ "min": 60.0, "max": 104.0 },   # debris
	{ "min": 52.0, "max": 88.0 },    # patch — high-contrast, kept rare by weight
	{ "min": 44.0, "max": 76.0 },    # hard detail — smallest
]
const DECADE_KIND_NAMES := {
	"1-10":   ["grass", "flower", "branch", "dirt", "rock"],
	"11-20":  ["cloud", "crystal", "feather", "mist", "stone"],
	"21-30":  ["kelp", "coral", "driftwood", "sand", "shell"],
	"31-40":  ["moss", "mushroom", "root", "scree", "shard"],
	"41-50":  ["scrub", "ember", "cinder", "ash", "basalt"],
	"51-60":  ["rush", "bloom", "branch", "puddle", "gravel"],
	"61-70":  ["weed", "bloom", "wreckage", "mud", "rubble"],
	"71-80":  ["scrub", "husk", "deadwood", "dust", "stone"],
	"81-90":  ["lichen", "bloom", "root", "soil", "shard"],
	"91-100": ["turf", "bloom", "branch", "sand", "marble"],
}
const MAX_VARIANTS := 8   # how many numbered files to probe per kind

# Weight-expanded pick list per decade, so choosing is a single modulo. Built
# once per decade (it hits the filesystem) and cached — _draw runs every frame.
var _weighted_cache := {}

func _weighted_decals(decade: String) -> Array:
	if _weighted_cache.has(decade):
		return _weighted_cache[decade]
	var out: Array = []
	var names: Array = DECADE_KIND_NAMES.get(decade, [])
	for role in range(names.size()):
		var kind: String = names[role]
		var size: Dictionary = ROLE_SIZES[role]
		var variants: Array = []
		for n in range(1, MAX_VARIANTS + 1):
			var file_name := "%s_%d" % [kind, n]
			if _load_decal(decade, file_name) != null:
				variants.append(file_name)   # a gap in numbering is fine, keep probing
		if variants.is_empty():
			continue
		# One entry per WEIGHT unit holding the whole variant list, so the
		# variant is chosen separately at draw time. Appending per-variant
		# instead would mean generating more variants of a kind also made that
		# kind more frequent, which is not what a weight should do.
		var entry := { "variants": variants, "min": size["min"], "max": size["max"] }
		for _i in range(ROLE_WEIGHTS[role]):
			out.append(entry)
	_weighted_cache[decade] = out
	return out

const DECAL_CHANCE   := 42   # out of 100 cells
# (size range now lives per-kind in DECAL_SETS)
# Jitter is deliberately wide enough (vs CELL 110) that decals straddle cell
# boundaries — clamping them near cell centres leaves a faint grid rhythm.
const DECAL_JITTER   := 45

var _art_cache := {}         # full path → Texture2D or null
var _decal_round := 1

# "1-10", "11-20", … from the current round.
func _decade_range() -> String:
	var d := (_decal_round - 1) / 10
	return "%d-%d" % [d * 10 + 1, d * 10 + 10]

func _load_arena_art(rel: String) -> Texture2D:
	if _art_cache.has(rel):
		return _art_cache[rel]
	# exists() first: _draw runs every frame, and a bare load() on an absent
	# path logs a hard ERROR — an incomplete art set would flood the console.
	# Safe to cache the miss because the manifest above is fixed, so a file
	# that's absent now stays absent for the rest of the run.
	var path := ARENA_ART_DIR + rel
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_art_cache[rel] = tex
	return tex

func _load_decal(decade: String, name: String) -> Texture2D:
	return _load_arena_art(decade + "/ready/" + name + ".png")

func _draw_ground_decals() -> void:
	var biome := _decade_range()
	var picks := _weighted_decals(biome)
	if picks.is_empty():
		return
	for row in range(GRID_H):
		for col in range(GRID_W):
			var h := _hash3(col, row, _decal_round)
			if h % 100 >= DECAL_CHANCE:
				continue
			# Independent hash streams per property, so kind/variant/size/
			# rotation/offset don't correlate into a visible pattern of their own.
			var h2 := _hash3(col * 7 + 1, row * 13 + 5, _decal_round)
			var h3 := _hash3(col * 31 + 9, row * 17 + 3, _decal_round)
			var h4 := _hash3(col * 53 + 11, row * 23 + 7, _decal_round)
			var entry: Dictionary = picks[(h / 100) % picks.size()]
			var variants: Array = entry["variants"]
			var tex := _load_decal(biome, variants[h4 % variants.size()])
			if tex == null:
				continue
			var size := lerpf(entry["min"], entry["max"], float(h2 % 100) / 99.0)
			var span := DECAL_JITTER * 2 + 1
			var centre := Vector2(
				col * CELL + CELL * 0.5 + float(h2 / 100 % span - DECAL_JITTER),
				row * CELL + CELL * 0.5 + float(h3 % span - DECAL_JITTER))
			# Keep the whole sprite inside the board — _draw() has no clip rect,
			# so an edge cell's jittered decal would otherwise spill past the
			# gold frame. Uses the rotated extent, not size*0.5, since a
			# rotated square's corners reach further than its half-width.
			var reach := size * 0.708
			centre.x = clampf(centre.x, reach, TOTAL_W - reach)
			centre.y = clampf(centre.y, reach, TOTAL_H - reach)
			var rot := TAU * float(h3 / 100 % 360) / 360.0
			var flip := -1.0 if (h % 2 == 0) else 1.0
			draw_set_transform(centre, rot, Vector2(flip, 1.0))
			draw_texture_rect(tex, Rect2(-size * 0.5, -size * 0.5, size, size), false)
			draw_set_transform_matrix(Transform2D.IDENTITY)

# Deterministic non-banding hash so scattered tiles don't line up diagonally.
func _hash2(x: int, y: int) -> int:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return abs(h ^ (h >> 16)) % 1000

# Same, plus a third input so the scatter can be re-rolled per round.
func _hash3(x: int, y: int, z: int) -> int:
	var h := x * 374761393 + y * 668265263 + z * 2246822519
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	h = (h ^ (h >> 7)) * 2654435761
	return abs(h ^ (h >> 15)) % 100000

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
