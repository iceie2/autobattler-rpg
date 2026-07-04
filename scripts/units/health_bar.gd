extends Node2D
class_name HealthBar

enum BarPlacement { TOP, BOTTOM }

@export var bar_width: float  = 70.0
@export var bar_height: float = 10.0
@export var gap: float        = 1.0
@export var offset_y: float   = 60.0
@export var placement: BarPlacement = BarPlacement.TOP

var hp_current:     float = 1.0
var hp_max:         float = 1.0
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
var _sb_hp:  StyleBoxTexture
var _sb_mp:  StyleBoxTexture
var _sb_ult: StyleBoxTexture
var _sb_ult_ready: StyleBoxTexture   # brightened fill when the ult is charged

const ULT_GLOW := Color(1.25, 1.20, 0.85)   # warm brighten when ult is ready

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sb_bg  = UITheme.stat_bar_bg()
	_sb_hp  = UITheme.stat_bar_fill("hp")
	_sb_mp  = UITheme.stat_bar_fill("mp")
	_sb_ult = UITheme.stat_bar_fill("ult")
	_sb_ult_ready = UITheme.stat_bar_fill("ult")
	_sb_ult_ready.modulate_color = ULT_GLOW
	var total_h: float = bar_height * 3.0 + gap * 2.0
	if placement == BarPlacement.TOP:
		position.y = -(offset_y + total_h)
	else:
		position.y = offset_y

func update_hp(current: float, maximum: float) -> void:
	hp_current = current
	hp_max     = maximum
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
	var x: float = -bar_width / 2.0

	var hp_pct: float  = clamp(hp_current  / max(hp_max,  1.0), 0.0, 1.0)
	var mp_pct: float  = clamp(mp_current  / max(mp_max,  1.0), 0.0, 1.0)
	var ult_pct: float = clamp(ult_current / max(ult_max, 1.0), 0.0, 1.0)
	var ult_fill: StyleBoxTexture = _sb_ult_ready if ult_current >= ult_max else _sb_ult

	_draw_bar(x, 0.0,                      bar_height, hp_pct,  _sb_hp)
	# Shield overlay on HP bar (cyan, semi-transparent, caps at bar width)
	if shield_current > 0.0:
		var sh_pct: float = clamp(shield_current / max(hp_max, 1.0), 0.0, 1.0)
		draw_rect(Rect2(x, 0.0, bar_width * sh_pct, bar_height), Color(0.20, 0.90, 1.0, 0.72))
	_draw_hp_number(x)
	_draw_bar(x, bar_height + gap,         bar_height, mp_pct,  _sb_mp)
	_draw_bar(x, (bar_height + gap) * 2.0, bar_height, ult_pct, ult_fill)

# Numeric HP readout inside the bar (2026-07-03, user request: "maybe a health
# total inside the hp bar"). "cur/max" when it fits, else just current HP.
# Outlined so it reads over both the green fill and the dark empty track.
func _draw_hp_number(x: float) -> void:
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 8 if bar_width < 100.0 else 12
	var txt: String = "%d/%d" % [maxi(int(hp_current), 0), int(hp_max)]
	if font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > bar_width - 4.0:
		txt = str(maxi(int(hp_current), 0))
	var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var baseline: float = (bar_height + font.get_ascent(fsize) - font.get_descent(fsize)) / 2.0
	var pos := Vector2(-tw / 2.0, baseline)
	draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.9))
	draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(1, 1, 1, 0.95))

func _draw_bar(x: float, y: float, h: float, pct: float, fill: StyleBoxTexture) -> void:
	# Dark track + beveled strip fill — drawn with the SAME styleboxes the
	# sidebar's ProgressBars use, so the two render identically.
	_sb_bg.draw(get_canvas_item(), Rect2(x, y, bar_width, h))
	if pct > 0.0:
		fill.draw(get_canvas_item(), Rect2(x, y, bar_width * pct, h))
