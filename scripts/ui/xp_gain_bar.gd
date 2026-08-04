extends Node2D
class_name XPGainBar

# A temporary XP bar that floats under a hero's health bar during the
# round-start ceremony (main_game._play_round_start_ceremony). Heroes have no
# permanent on-board XP bar — the only one lives in the details panel — so this
# node is spawned, filled, and freed as part of the ceremony. Parented to the
# unit, so it tracks the hero wherever they stand.
#
# Fill is driven from outside via set_fill(); level-ups are announced by
# calling pop_level(), which flashes the bar and prints "LEVEL UP!".

const FONT := preload("res://assets/Fonts/LeagueGothic-Regular.otf")

const BAR_W       := 64.0
const BAR_H       := 7.0
const BORDER      := 1.0
const XP_COLOR    := Color(0.93, 0.79, 0.28)   # gold, matches the details-panel XP bar
const TRACK_COLOR := Color(0.10, 0.08, 0.06, 0.85)
const EDGE_COLOR  := Color(0.05, 0.04, 0.03, 0.95)
const TEXT_COLOR  := Color(0.96, 0.86, 0.45)
const LEVEL_COLOR := Color(1.0, 0.95, 0.55)

var fill: float = 0.0          # 0..1 within the current level
var label_text: String = ""    # e.g. "+14 XP", drawn above the bar
var _flash: float = 0.0        # 1 → 0 after a level-up, whitens the fill
var _level_pop: float = 0.0    # lifetime of the floating "LEVEL UP!" text
var _level_text_y: float = 0.0

func _ready() -> void:
	z_index = 90   # under damage text (100), above the units
	set_process(true)

func set_fill(v: float) -> void:
	fill = clampf(v, 0.0, 1.0)
	queue_redraw()

func set_label(t: String) -> void:
	label_text = t
	queue_redraw()

# Called the moment the bar wraps past 100% — the fill is reset by the caller.
func pop_level() -> void:
	_flash = 1.0
	_level_pop = 1.1
	_level_text_y = 0.0

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.0)
		queue_redraw()
	if _level_pop > 0.0:
		_level_pop = maxf(0.0, _level_pop - delta)
		_level_text_y -= delta * 26.0
		queue_redraw()

func _draw() -> void:
	var x := -BAR_W / 2.0
	# Track + border
	draw_rect(Rect2(x - BORDER, -BORDER, BAR_W + BORDER * 2.0, BAR_H + BORDER * 2.0), EDGE_COLOR)
	draw_rect(Rect2(x, 0.0, BAR_W, BAR_H), TRACK_COLOR)
	# Fill — whitens briefly on a level-up
	if fill > 0.0:
		var c: Color = XP_COLOR.lerp(Color.WHITE, _flash)
		draw_rect(Rect2(x, 0.0, BAR_W * fill, BAR_H), c)

	if label_text != "":
		var size := FONT.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string_outline(FONT, Vector2(-size.x / 2.0, -4.0), label_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 2, EDGE_COLOR)
		draw_string(FONT, Vector2(-size.x / 2.0, -4.0), label_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT_COLOR)

	if _level_pop > 0.0:
		var t := "LEVEL UP!"
		var a: float = clampf(_level_pop, 0.0, 1.0)
		var ls := FONT.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		var pos := Vector2(-ls.x / 2.0, -18.0 + _level_text_y)
		draw_string_outline(FONT, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 3,
				Color(EDGE_COLOR.r, EDGE_COLOR.g, EDGE_COLOR.b, a))
		draw_string(FONT, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
				Color(LEVEL_COLOR.r, LEVEL_COLOR.g, LEVEL_COLOR.b, a))
