extends Node2D
class_name ProgressionRails

# Two vertical "journey" rails drawn in the empty strips either side of the
# arena:
#   LEFT  — the run's 10 biomes (macro progress, wave 1 → 100)
#   RIGHT — the 10 waves inside the CURRENT biome (micro progress)
#
# Drawn in world space (a Node2D sibling of BackgroundLayer) rather than as UI
# Controls because these strips are where the biome backdrop art paints, and
# _draw() + _process gives us the per-frame pulse/travel animation for free
# without building a Control tree per node.
#
# Positioned by main_game.gd's _center_battlefield() to the same origin as the
# arena, so all coordinates below are arena-local: the board spans 0..ARENA_W
# horizontally, and the side strips live at negative x / beyond ARENA_W.

const ARENA_W  := 990.0    # mirrors BackgroundLayer.TOTAL_W
const SIDEBAR_W := 285.0   # mirrors main_game.gd SIDEBAR_W

const WAVES_PER_BIOME := 10
const BIOME_COUNT     := 10   # Balance.VICTORY_ROUND / WAVES_PER_BIOME

const PAD_V   := 86.0   # vertical breathing room at the top/bottom of a rail
const WIND_X  := 20.0   # how far the path snakes off the rail's centre line

# Decade → biome identity. Order matches the locked wave structure (Normal,
# Air, Water, Earth, Fire, Lightning, then the four mixed endgame acts).
const BIOMES := [
	{ "name": "Grassland",  "color": Color(0.45, 0.70, 0.35) },
	{ "name": "Skyreach",   "color": Color(0.70, 0.88, 0.95) },
	{ "name": "Tidewater",  "color": Color(0.30, 0.60, 0.85) },
	{ "name": "Caverns",    "color": Color(0.72, 0.55, 0.30) },
	{ "name": "Ashlands",   "color": Color(0.85, 0.40, 0.20) },
	{ "name": "Stormreach", "color": Color(0.62, 0.50, 0.90) },
	{ "name": "Warfront",   "color": Color(0.80, 0.35, 0.40) },
	{ "name": "The Wastes", "color": Color(0.60, 0.55, 0.45) },
	{ "name": "The Abyss",  "color": Color(0.40, 0.30, 0.55) },
	{ "name": "Apex",       "color": Color(0.95, 0.80, 0.35) },
]

# Everything is drawn FULLY OPAQUE with NO backing panel (user call) — the
# translucent scrim and the solid dark channel that replaced it both read as a
# grey/black box sitting on the art. The rails now float directly on the biome
# plate: pure white trail, and every element gets a hard black outline so it
# pops on light backdrops (grassland) as well as dark ones (caverns). The
# outline is a 1-2px stroke, deliberately NOT a filled panel.
const TRAIL      := Color(1, 1, 1)              # the path itself — pure white
const OUTLINE    := Color(0, 0, 0)              # hard edge for contrast
const TEXT_MAIN  := Color(1, 1, 1)
const TEXT_SUB   := Color(0.86, 0.88, 0.92)
const NODE_CORE  := Color(0.04, 0.04, 0.06)     # dark centre inside every node

# Progress is encoded by TRAIL WIDTH rather than by colour or alpha, so the
# whole path can stay white: walked segments are thick, upcoming ones hairline.
const TRAIL_W_DONE := 5.0
const TRAIL_W_TODO := 2.0

var current_round := 1

# Travel animation: 0→1 as the marker slides from the previous node to the
# current one. Starts at 1 (settled) so the first frame isn't mid-flight.
const TRAVEL_TIME := 2.5
var _travel := 1.0
var _travel_from_round := 1

func set_round(battle_round: int) -> void:
	if battle_round == current_round:
		return
	# Only animate a forward step within the same biome; a biome change (or a
	# save-restore jump) just snaps, since there's no shared path to slide along.
	var same_biome := _decade_of(battle_round) == _decade_of(current_round)
	_travel_from_round = current_round
	_travel = 0.0 if (same_biome and battle_round == current_round + 1) else 1.0
	current_round = battle_round
	queue_redraw()

func _process(delta: float) -> void:
	if _travel < 1.0:
		_travel = min(1.0, _travel + delta / TRAVEL_TIME)
	queue_redraw()   # pulse/glow animate every frame

func _decade_of(battle_round: int) -> int:
	return clampi((battle_round - 1) / WAVES_PER_BIOME, 0, BIOME_COUNT - 1)

func _wave_in_biome(battle_round: int) -> int:
	return (battle_round - 1) % WAVES_PER_BIOME + 1

# ── Layout helpers ────────────────────────────────────────────────────────────
# Both rails share the same vertical node spacing so the two sides read as one
# system. Strip widths come from the live viewport, matching how
# _center_battlefield() derives the arena origin.
func _strip_centre_x(left: bool) -> float:
	var vp := get_viewport_rect().size
	if left:
		var w := position.x - SIDEBAR_W
		return -w * 0.5
	var right_w := vp.x - SIDEBAR_W - (position.x + ARENA_W)
	return ARENA_W + right_w * 0.5

func _node_pos(index: int, count: int, left: bool) -> Vector2:
	var vp := get_viewport_rect().size
	var top := -position.y + PAD_V
	var bottom := -position.y + vp.y - PAD_V
	var t := 0.0 if count <= 1 else float(index) / float(count - 1)
	# Index 0 sits at the BOTTOM and progress climbs upward — reads as ascending
	# a journey rather than draining down a meter (user call).
	var y := lerpf(bottom, top, t)
	# Snake the path so it reads as a trail rather than a ruler. Mirrored per
	# side so both rails lean away from the arena.
	var wind := sin(float(index) * 0.85) * WIND_X
	return Vector2(_strip_centre_x(left) + (wind if left else -wind), y)

func _pulse() -> float:
	return 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0042)

func _draw() -> void:
	if position.x <= SIDEBAR_W:
		return   # strips collapsed (very narrow window) — nothing to draw into
	# No backing panel — the rails draw straight onto the biome plate. Legibility
	# comes from the black outline baked into each primitive instead.
	_draw_biome_rail()
	_draw_wave_rail()

# ── LEFT: biome rail (macro — where you are in the whole run) ─────────────────
func _draw_biome_rail() -> void:
	var here := _decade_of(current_round)
	var pts: Array[Vector2] = []
	for i in range(BIOME_COUNT):
		pts.append(_node_pos(i, BIOME_COUNT, true))

	_draw_path(pts, here, float(_wave_in_biome(current_round) - 1) / float(WAVES_PER_BIOME))

	for i in range(BIOME_COUNT):
		var col: Color = BIOMES[i]["color"]
		if i < here:
			_draw_node(pts[i], 7.0, col, false)                  # cleared
		elif i == here:
			_draw_node(pts[i], 10.0, col.lightened(0.12), true)   # current, pulsing
		else:
			_draw_node(pts[i], 6.5, _locked(col), false)          # locked ahead

	# Only the current biome is named — labelling all ten would be unreadable in
	# a 180px strip and the rail already shows position at a glance.
	var name_txt: String = BIOMES[here]["name"]
	_draw_text(name_txt, pts[here] + Vector2(0, 34.0), 15, TEXT_MAIN)
	_draw_text("BIOME %d/%d" % [here + 1, BIOME_COUNT],
		pts[here] + Vector2(0, 52.0), 11, TEXT_SUB)

# ── RIGHT: wave rail (micro — progress through the current biome) ─────────────
func _draw_wave_rail() -> void:
	var here := _wave_in_biome(current_round)
	var base := current_round - here   # absolute round just before this biome
	var pts: Array[Vector2] = []
	for i in range(WAVES_PER_BIOME):
		pts.append(_node_pos(i, WAVES_PER_BIOME, false))

	var tint: Color = BIOMES[_decade_of(current_round)]["color"]
	# Travel fraction lets the trail grow smoothly into the node being entered.
	var seg := float(here - 1) + (_travel - 1.0)
	_draw_path(pts, int(max(0.0, floor(seg))), seg - floor(max(0.0, seg)))

	for i in range(WAVES_PER_BIOME):
		var abs_round := base + i + 1
		var is_boss := WaveScaler.is_boss_round(abs_round)
		var is_elite := WaveScaler.is_elite_round(abs_round)
		var r := 7.0
		if is_boss:
			r = 12.0
		elif is_elite:
			r = 9.5
		var done := i + 1 < here
		var cur := i + 1 == here
		var col := tint
		if is_boss:
			col = Color(0.95, 0.35, 0.30)
		elif is_elite:
			col = Color(0.98, 0.75, 0.30)
		var shown := col if (done or cur) else _locked(col)
		if cur:
			shown = shown.lightened(0.12)
		if is_boss or is_elite:
			_draw_marker_ring(pts[i], r, shown)
		_draw_node(pts[i], r * (0.62 if (is_boss or is_elite) else 1.0), shown, cur)

	# The traveling marker — slides between nodes on a wave advance, then rests
	# on the current node and pulses with it.
	var marker := pts[clampi(here - 1, 0, WAVES_PER_BIOME - 1)]
	if _travel < 1.0 and here >= 2:
		marker = pts[here - 2].lerp(pts[here - 1], ease(_travel, -2.0))
	_draw_traveler(marker, tint)

	_draw_text("WAVE %d" % current_round, pts[clampi(here - 1, 0, 9)] + Vector2(0, 36.0),
		15, TEXT_MAIN)
	_draw_text("%d/%d in biome" % [here, WAVES_PER_BIOME],
		pts[clampi(here - 1, 0, 9)] + Vector2(0, 54.0), 11, TEXT_SUB)

# ── Primitives ────────────────────────────────────────────────────────────────
# A node that isn't reached yet is drawn in a DARKENED version of its real
# colour rather than a faded one — keeps the hue readable (so you can see which
# biome is coming) with no transparency anywhere.
func _locked(col: Color) -> Color:
	return col.darkened(0.42)

# Three passes: a black stroke under the whole route (this is what makes white
# pop on a light backdrop), then the full route as a hairline, then the walked
# portion thick over the top — including a partial final segment mid-travel.
func _draw_path(pts: Array[Vector2], lit_upto: int, partial: float) -> void:
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], OUTLINE, TRAIL_W_DONE + 3.0)
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], TRAIL, TRAIL_W_TODO)
	for i in range(min(lit_upto, pts.size() - 1)):
		draw_line(pts[i], pts[i + 1], TRAIL, TRAIL_W_DONE)
	if lit_upto < pts.size() - 1 and partial > 0.0:
		var a: Vector2 = pts[lit_upto]
		var b: Vector2 = pts[lit_upto + 1]
		draw_line(a, a.lerp(b, clampf(partial, 0.0, 1.0)), TRAIL, TRAIL_W_DONE)

# The "current" pulse is a white ring that grows rather than a stack of
# translucent halos, so the blink survives the no-transparency rule.
func _draw_node(centre: Vector2, radius: float, col: Color, pulsing: bool) -> void:
	if pulsing:
		var p := _pulse()
		var pr := radius + 5.0 + p * 4.0
		draw_arc(centre, pr, 0.0, TAU, 28, OUTLINE, 4.0)
		draw_arc(centre, pr, 0.0, TAU, 28, TRAIL, 2.0)
	draw_circle(centre, radius + 2.0, OUTLINE)   # hard rim = contrast on any art
	draw_circle(centre, radius, NODE_CORE)
	draw_circle(centre, radius * 0.72, col)

func _draw_marker_ring(centre: Vector2, radius: float, col: Color) -> void:
	draw_arc(centre, radius, 0.0, TAU, 24, OUTLINE, 4.0)
	draw_arc(centre, radius, 0.0, TAU, 24, col, 2.0)

func _draw_traveler(centre: Vector2, col: Color) -> void:
	var p := _pulse()
	draw_circle(centre, 9.0 + p * 2.0, OUTLINE)
	draw_circle(centre, 7.0 + p * 2.0, col)
	draw_circle(centre, 3.0 + p * 1.2, TRAIL)

# No plate and no panel — legibility comes from an outline drawn around the
# glyphs, so the text works on both the grassland and the abyss plates.
func _draw_text(txt: String, centre: Vector2, size: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := Vector2(centre.x - w * 0.5, centre.y)
	for ox in [-1.5, 0.0, 1.5]:
		for oy in [-1.5, 0.0, 1.5]:
			if ox != 0.0 or oy != 0.0:
				draw_string(font, origin + Vector2(ox, oy), txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, size, OUTLINE)
	draw_string(font, origin, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
