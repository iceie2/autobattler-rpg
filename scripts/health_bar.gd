extends Node2D
class_name HealthBar

@export var bar_width: float = 52.0
@export var bar_height: float = 5.0
@export var offset_y: float = -40.0

# HP
var hp_current: float = 1.0
var hp_max: float = 1.0
# MP
var mp_current: float = 1.0
var mp_max: float = 1.0
# Ultimate charge
var ult_current: float = 0.0
var ult_max: float = 1.0

const GAP := 2.0

const BG_COLOR  := Color(0.15, 0.15, 0.15, 0.85)
const HP_COLOR  := Color(0.2, 0.82, 0.25)
const HP_LOW    := Color(0.85, 0.18, 0.18)
const MP_COLOR  := Color(0.2, 0.45, 0.95)
const ULT_COLOR := Color(0.92, 0.72, 0.1)
const ULT_READY := Color(1.0, 0.9, 0.2)
const BORDER    := Color(0.0, 0.0, 0.0, 0.6)

func _ready() -> void:
	position.y = offset_y

func update_hp(current: float, maximum: float) -> void:
	hp_current = current
	hp_max = maximum
	queue_redraw()

func update_mp(current: float, maximum: float) -> void:
	mp_current = current
	mp_max = maximum
	queue_redraw()

func update_ult(current: float, maximum: float) -> void:
	ult_current = current
	ult_max = maximum
	queue_redraw()

func _draw() -> void:
	var x := -bar_width / 2.0
	_draw_bar(x, 0.0,                       hp_current,  hp_max,  HP_COLOR if (hp_current / max(hp_max, 1)) > 0.3 else HP_LOW)
	_draw_bar(x, bar_height + GAP,           mp_current,  mp_max,  MP_COLOR)
	var is_ready := ult_current >= ult_max
	_draw_bar(x, (bar_height + GAP) * 2.0,  ult_current, ult_max, ULT_READY if is_ready else ULT_COLOR)

func _draw_bar(x: float, y: float, current: float, maximum: float, fill: Color) -> void:
	var pct := clamp(current / max(maximum, 1.0), 0.0, 1.0)
	# Background
	draw_rect(Rect2(x, y, bar_width, bar_height), BG_COLOR)
	# Fill
	if pct > 0:
		draw_rect(Rect2(x, y, bar_width * pct, bar_height), fill)
	# Border
	draw_rect(Rect2(x, y, bar_width, bar_height), BORDER, false, 1.0)
