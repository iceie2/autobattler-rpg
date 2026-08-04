extends Node2D
class_name HealthBar

enum BarPlacement { TOP, BOTTOM }

@export var bar_width: float  = 70.0
# HP dominates the stack (2026-07-06 user report: three equal bars split focus
# 1/3 each and read as noise) — MP and ult are thin slivers underneath.
# bar_height doubled again same day: the tile PNGs carry a lot of transparent
# padding (see _content_rect below), so the old 14px height only rendered
# ~5-6px of actual sprite — read as small even before the padding gap issue.
@export var bar_height: float = 28.0   # HP bar
@export var sub_height: float = 5.0    # MP / ult bars
@export var gap: float        = 1.0
@export var offset_y: float   = 60.0

# Deadlock/TFT-style HP segmentation (2026-07-06 user request): the HP bar is
# built from tiled sprites instead of a solid fill — a left cap, a repeating
# 100-HP "body" segment, and a right cap. Max HP determines how many body
# segments exist (so a boss's bar is literally longer, not just a differently
# colored percentage), current HP determines how much of that shape is filled.
# Big pools tick in 500s instead (2026-07-15): a 12k-HP elite at 100/segment
# is 120 sub-pixel slivers — mush, not segments.
const SEGMENT_HP := 100.0
const SEGMENT_HP_BIG := 500.0
const BIG_POOL_THRESHOLD := 2000.0
# Drawn-width clamps (2026-07-15): natural tile width still grows with max HP,
# but small pools floor at 0.8× bar_width (an 83-HP goblin's bar used to be a
# ~25px nub narrower than its own MP strip AND its own HP number) and big
# pools cap at bar_width + 40 ≈ the unit's own cell footprint, so late-game
# bars stop invading the neighbors' space.
const MIN_WIDTH_FACTOR := 0.8
const MAX_WIDTH_EXTRA := 40.0
# Tuning knobs (2026-07-06 user request): both axes scale independently off
# bar_height so the width/height ratio can be dialed in without touching the
# tile-cropping math. 1.0 = no change from the base bar_height.
const HP_WIDTH_SCALE := 0.5
const HP_HEIGHT_SCALE := 0.6
const TEX_FULL_LEFT   := preload("res://assets/using/icons/hp/full_left.png")
const TEX_FULL_MID    := preload("res://assets/using/icons/hp/full_mid.png")
const TEX_FULL_RIGHT  := preload("res://assets/using/icons/hp/full_right.png")
const TEX_EMPTY_LEFT  := preload("res://assets/using/icons/hp/empty_left.png")
const TEX_EMPTY_MID   := preload("res://assets/using/icons/hp/empty_mid.png")
const TEX_EMPTY_RIGHT := preload("res://assets/using/icons/hp/empty_right.png")

# The source PNGs are 13x20 canvases but the actual painted pixels sit in a
# small off-center region within each (e.g. full_mid's content is only cols
# 8-13, rows 6-14) — a leftover from however they were exported. Using the
# full canvas as the tile width left a transparent gap between every segment
# (2026-07-06 user report: "too split"). We crop to the real opaque bounds via
# Image.get_used_rect() instead of hardcoding pixel offsets, so segments butt
# up edge-to-edge and the fix keeps working if the art gets redrawn later.
static var _content_rect_cache: Dictionary = {}
static func _content_rect(tex: Texture2D) -> Rect2:
	if _content_rect_cache.has(tex):
		return _content_rect_cache[tex]
	var r: Rect2 = Rect2(tex.get_image().get_used_rect())
	_content_rect_cache[tex] = r
	return r

# Enemy bars fill RED (2026-07-15): placement alone stops reading as a side
# cue once units scrum together. A plain red modulate over the green tiles
# would come out muddy olive, so we hue-mirror the fill art by swapping the
# R/G channels once and caching the result (tiles are 13×20 — trivial).
static var _enemy_tex_cache: Dictionary = {}
static func _enemy_variant(tex: Texture2D) -> Texture2D:
	if _enemy_tex_cache.has(tex):
		return _enemy_tex_cache[tex]
	var img: Image = tex.get_image().duplicate()
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.g, c.r, c.b, c.a))
	var out := ImageTexture.create_from_image(img)
	_enemy_tex_cache[tex] = out
	return out

@export var placement: BarPlacement = BarPlacement.TOP

# Effective drawn height of the HP tiles — bar_height scaled by HP_HEIGHT_SCALE.
# MP/ult positions and the bar's total height are derived from this so tuning
# HP_HEIGHT_SCALE never makes the HP bar overlap the bars beneath it.
func _hp_h() -> float:
	return bar_height * HP_HEIGHT_SCALE

# Total stacked height of HP + MP + ult rows. Used by VisualUnit to park status
# icons clear of the bar instead of on top of it (2026-08-02).
func total_height() -> float:
	return _hp_h() + sub_height * 2.0 + gap * 2.0

var hp_current:     float = 1.0
var hp_max:         float = 1.0
# Recent-damage ghost (2026-07-17): when HP drops, a pale bar lingers at the
# OLD level and drains down to the new one over ~0.5s, so burst damage reads
# instead of the bar just teleporting shorter. _process self-disables when idle.
var hp_ghost:       float = 1.0
var _ghost_time:    float = 0.0
const GHOST_HOLD  := 0.5    # total lifetime of a ghost flash
const GHOST_DRAIN := 2.0    # bars-per-second the ghost catches down to real HP
var mp_current:     float = 1.0
var mp_max:         float = 1.0
var ult_current:    float = 0.0
var ult_max:        float = 1.0
var shield_current: float = 0.0

# Same bars as the sidebar Team Status (2026-07-05, user request) — the
# beveled strip fills and dark track come from UITheme.stat_bar_*, the single
# source for every stat bar in the game. Styleboxes are built ONCE here and
# drawn directly in _draw(); per-frame allocation in bar redraws is a real
# perf cost at 29 units.
var _sb_bg:  StyleBoxFlat
var _sb_mp:  StyleBoxTexture
var _sb_ult: StyleBoxTexture
var _sb_ult_ready: StyleBoxTexture   # brightened fill when the ult is charged

const ULT_GLOW := Color(1.25, 1.20, 0.85)   # warm brighten when ult is ready

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)   # only ticks while a damage ghost is draining
	_sb_bg  = UITheme.stat_bar_bg()
	_sb_mp  = UITheme.stat_bar_fill("mp")
	_sb_ult = UITheme.stat_bar_fill("ult")
	_sb_ult_ready = UITheme.stat_bar_fill("ult")
	_sb_ult_ready.modulate_color = ULT_GLOW
	var total_h: float = _hp_h() + sub_height * 2.0 + gap * 2.0
	if placement == BarPlacement.TOP:
		position.y = -(offset_y + total_h)
	else:
		position.y = offset_y

func update_hp(current: float, maximum: float) -> void:
	if current < hp_current:
		# Took damage — leave a ghost at the pre-hit level (or keep an even
		# higher one still draining) and start the drain timer.
		hp_ghost = maxf(hp_ghost, hp_current)
		_ghost_time = GHOST_HOLD
		set_process(true)
	else:
		hp_ghost = current   # healed or unchanged: no ghost
	hp_current = current
	hp_max     = maximum
	queue_redraw()

func _process(delta: float) -> void:
	_ghost_time -= delta
	# Hold briefly, then chase the ghost down to real HP.
	if _ghost_time < GHOST_HOLD * 0.6:
		hp_ghost = move_toward(hp_ghost, hp_current, hp_max * GHOST_DRAIN * delta)
	if _ghost_time <= 0.0 or hp_ghost <= hp_current + 0.01:
		hp_ghost = hp_current
		set_process(false)
	queue_redraw()

func update_mp(current: float, maximum: float) -> void:
	mp_current = current
	mp_max     = maximum
	queue_redraw()

func update_ult(current: float, maximum: float) -> void:
	ult_current = current
	ult_max     = maximum
	queue_redraw()

func update_shield(current: float, hp_max_ref: float) -> void:
	shield_current = current
	if hp_max_ref > 0.0:
		hp_max = hp_max_ref
	queue_redraw()

func _draw() -> void:
	var hp_h: float = _hp_h()
	var hp_width: float = _draw_hp_tiles(hp_h)
	# Recent-damage ghost: pale segment from the current fill edge out to the
	# lingering old level, fading as the flash ages.
	if hp_ghost > hp_current + 0.01 and hp_max > 0.0:
		var cur_pct: float = clampf(hp_current / hp_max, 0.0, 1.0)
		var gho_pct: float = clampf(hp_ghost / hp_max, 0.0, 1.0)
		var x0: float = -hp_width / 2.0 + hp_width * cur_pct
		var gw: float = hp_width * (gho_pct - cur_pct)
		var a: float = 0.6 * clampf(_ghost_time / GHOST_HOLD, 0.0, 1.0)
		draw_rect(Rect2(x0, 0.0, gw, hp_h), Color(1.0, 0.95, 0.95, a))
	# Shield overlay on HP bar (cyan, semi-transparent, caps at the tiled width)
	if shield_current > 0.0:
		var sh_pct: float = clamp(shield_current / max(hp_max, 1.0), 0.0, 1.0)
		draw_rect(Rect2(-hp_width / 2.0, 0.0, hp_width * sh_pct, hp_h), Color(0.20, 0.90, 1.0, 0.72))
	_draw_hp_number(hp_width, hp_h)

	# MP/ult strips match the HP bar's drawn width (a fixed 70px used to stick
	# out past small units' HP bars) and vanish entirely for units without the
	# stat — no more permanently-empty black tracks under manaless/ultless mobs.
	var sub_x: float = -hp_width / 2.0
	var sub_y: float = hp_h + gap
	if mp_max > 0.0:
		var mp_pct: float = clamp(mp_current / mp_max, 0.0, 1.0)
		_draw_bar(sub_x, sub_y, sub_height, mp_pct, _sb_mp, hp_width)
		sub_y += sub_height + gap
	if ult_max > 0.0:
		var ult_pct: float = clamp(ult_current / ult_max, 0.0, 1.0)
		var ult_fill: StyleBoxTexture = _sb_ult_ready if ult_current >= ult_max else _sb_ult
		_draw_bar(sub_x, sub_y, sub_height, ult_pct, ult_fill, hp_width)

# Tiled HP bar: a fixed-width left/right cap sandwiching (hp_max / SEGMENT_HP)
# repeating body segments (fractional segments render at partial width, e.g.
# 150 max HP = 1.5 body segments). Current HP fills that shape left-to-right.
# Returns the total drawn width so the caller can position the shield overlay
# and HP number over it.
func _draw_hp_tiles(hp_h: float) -> float:
	var mid_empty_src: Rect2 = _content_rect(TEX_EMPTY_MID)
	var mid_full_src:  Rect2 = _content_rect(TEX_FULL_MID)
	var left_full_src:  Rect2 = _content_rect(TEX_FULL_LEFT)
	var left_empty_src: Rect2 = _content_rect(TEX_EMPTY_LEFT)
	var right_full_src:  Rect2 = _content_rect(TEX_FULL_RIGHT)
	var right_empty_src: Rect2 = _content_rect(TEX_EMPTY_RIGHT)

	# Enemy bars (TOP placement) fill red — see _enemy_variant. Empty/track
	# tiles stay shared so both sides keep the identical dark track.
	var is_enemy: bool = placement == BarPlacement.TOP
	var full_left:  Texture2D = _enemy_variant(TEX_FULL_LEFT)  if is_enemy else TEX_FULL_LEFT
	var full_mid:   Texture2D = _enemy_variant(TEX_FULL_MID)   if is_enemy else TEX_FULL_MID
	var full_right: Texture2D = _enemy_variant(TEX_FULL_RIGHT) if is_enemy else TEX_FULL_RIGHT

	# Vertical scale keeps the sprite's pixel-art proportions (derived from the
	# mid tile's content height), then HP_WIDTH_SCALE narrows the result
	# horizontally (2026-07-06 user report: bar read 2x too wide at this height).
	var scale: float = hp_h / mid_empty_src.size.y
	var cap_w: float = maxf(left_empty_src.size.x, right_empty_src.size.x) * scale * HP_WIDTH_SCALE
	var mid_w: float = mid_empty_src.size.x * scale * HP_WIDTH_SCALE

	var seg_hp: float = SEGMENT_HP_BIG if hp_max > BIG_POOL_THRESHOLD else SEGMENT_HP
	var mid_units: float = max(1.0, hp_max / seg_hp)
	# Clamp the drawn width (see the constants' note), stretching/squeezing the
	# body segments to fit — caps keep their art proportions.
	var natural_width: float = cap_w * 2.0 + mid_w * mid_units
	var clamped_width: float = clampf(natural_width, bar_width * MIN_WIDTH_FACTOR, bar_width + MAX_WIDTH_EXTRA)
	if not is_equal_approx(natural_width, clamped_width):
		mid_w = (clamped_width - cap_w * 2.0) / mid_units

	var full_tiles: int = int(floor(mid_units + 0.0001))
	var frac: float = mid_units - full_tiles
	if frac < 0.001:
		frac = 0.0
	var rendered_tiles: int = full_tiles + (1 if frac > 0.0 else 0)
	var total_width: float = cap_w * 2.0 + mid_w * mid_units
	var filled_units: float = clamp(hp_current / seg_hp, 0.0, mid_units)

	var x_cursor: float = -total_width / 2.0

	var left_tex: Texture2D = full_left if hp_current > 0.0 else TEX_EMPTY_LEFT
	var left_src: Rect2 = left_full_src if hp_current > 0.0 else left_empty_src
	draw_texture_rect_region(left_tex, Rect2(x_cursor, 0.0, cap_w, hp_h), left_src)
	x_cursor += cap_w

	for i in range(rendered_tiles):
		var width_units: float = 1.0 if i < full_tiles else frac
		var seg_w: float = mid_w * width_units
		var filled_in_tile: float = clamp(filled_units - i, 0.0, width_units)
		var fill_frac: float = filled_in_tile / width_units if width_units > 0.0 else 0.0

		var empty_src := Rect2(mid_empty_src.position, Vector2(mid_empty_src.size.x * width_units, mid_empty_src.size.y))
		draw_texture_rect_region(TEX_EMPTY_MID, Rect2(x_cursor, 0.0, seg_w, hp_h), empty_src)
		if fill_frac > 0.0:
			var fill_src := Rect2(mid_full_src.position, Vector2(mid_full_src.size.x * width_units * fill_frac, mid_full_src.size.y))
			draw_texture_rect_region(full_mid, Rect2(x_cursor, 0.0, seg_w * fill_frac, hp_h), fill_src)
		x_cursor += seg_w

	var right_tex: Texture2D = full_right if hp_current >= hp_max else TEX_EMPTY_RIGHT
	var right_src: Rect2 = right_full_src if hp_current >= hp_max else right_empty_src
	draw_texture_rect_region(right_tex, Rect2(x_cursor, 0.0, cap_w, hp_h), right_src)

	return total_width

# Numeric HP readout inside the bar (2026-07-03, user request: "maybe a health
# total inside the hp bar"). "cur/max" when it fits, else just current HP.
# Outlined so it reads over both the tile fill and the empty track.
func _draw_hp_number(hp_width: float, hp_h: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 16 if hp_width < 100.0 else 20
	var txt: String = "%d/%d" % [maxi(int(hp_current), 0), int(hp_max)]
	if font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > hp_width - 4.0:
		txt = str(maxi(int(hp_current), 0))
	var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var baseline: float = (hp_h + font.get_ascent(fsize) - font.get_descent(fsize)) / 2.0
	var pos := Vector2(-tw / 2.0, baseline)
	draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.9))
	draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1, 1, 1, 0.95))

func _draw_bar(x: float, y: float, h: float, pct: float, fill: StyleBoxTexture, w: float = -1.0) -> void:
	# Dark track + beveled strip fill — drawn with the SAME styleboxes the
	# sidebar's ProgressBars use, so the two render identically.
	var bw: float = w if w > 0.0 else bar_width
	_sb_bg.draw(get_canvas_item(), Rect2(x, y, bw, h))
	if pct > 0.0:
		fill.draw(get_canvas_item(), Rect2(x, y, bw * pct, h))
