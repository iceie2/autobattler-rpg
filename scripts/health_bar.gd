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

# Single full-bar textures (35x5, beveled), cropped from assets/UI/stat_bar/ strips.
const TEX_HP:  Texture2D = preload("res://assets/UI/stat_bar/fill_hp.png")   # green  HP
const TEX_MP:  Texture2D = preload("res://assets/UI/stat_bar/fill_mp.png")   # blue   MP
const TEX_ULT: Texture2D = preload("res://assets/UI/stat_bar/fill_ult.png")  # purple ULT

const BG_COLOR  := Color(0.06, 0.06, 0.08, 0.92)
const BORDER    := Color(0.0, 0.0, 0.0, 0.85)
const ULT_GLOW  := Color(1.25, 1.20, 0.85)   # warm brighten when ult is ready

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	var ult_tint: Color = ULT_GLOW if ult_current >= ult_max else Color.WHITE

	_draw_bar(x, 0.0,                      bar_height, hp_pct,  TEX_HP)
	# Shield overlay on HP bar (cyan, semi-transparent, caps at bar width)
	if shield_current > 0.0:
		var sh_pct: float = clamp(shield_current / max(hp_max, 1.0), 0.0, 1.0)
		draw_rect(Rect2(x, 0.0, bar_width * sh_pct, bar_height), Color(0.20, 0.90, 1.0, 0.72))
	_draw_bar(x, bar_height + gap,         bar_height, mp_pct,  TEX_MP)
	_draw_bar(x, (bar_height + gap) * 2.0, bar_height, ult_pct, TEX_ULT, ult_tint)

func _draw_bar(x: float, y: float, h: float, pct: float, tex: Texture2D, tint: Color = Color.WHITE) -> void:
	# Dark track with a 1px border so empty bars stay readable over any sprite.
	draw_rect(Rect2(x - 1, y - 1, bar_width + 2, h + 2), BORDER)
	draw_rect(Rect2(x, y, bar_width, h), BG_COLOR)
	# Colored fill — crop the source texture by pct so it drains left-to-right.
	if pct > 0.0:
		var src := Rect2(0, 0, float(tex.get_width()) * pct, float(tex.get_height()))
		var dst := Rect2(x, y, bar_width * pct, h)
		draw_texture_rect_region(tex, dst, src, tint)
