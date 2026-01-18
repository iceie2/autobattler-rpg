extends Node2D
class_name HealthBar

@export var bar_width: float = 50.0
@export var bar_height: float = 6.0
@export var offset_y: float = -35.0

var current_value: float = 1.0
var max_value: float = 1.0

var bg_color: Color = Color(0.2, 0.2, 0.2, 0.8)
var hp_color: Color = Color(0.2, 0.8, 0.2)
var low_hp_color: Color = Color(0.8, 0.2, 0.2)

func _ready():
	position.y = offset_y

func update_health(current: float, maximum: float) -> void:
	current_value = current
	max_value = maximum
	queue_redraw()

func _draw():
	if max_value <= 0:
		return
	
	var percentage = current_value / max_value
	var fill_width = bar_width * percentage
	
	# Draw background
	draw_rect(Rect2(-bar_width / 2, 0, bar_width, bar_height), bg_color)
	
	# Draw health fill
	var color = hp_color if percentage > 0.3 else low_hp_color
	if fill_width > 0:
		draw_rect(Rect2(-bar_width / 2, 0, fill_width, bar_height), color)
	
	# Draw border
	draw_rect(Rect2(-bar_width / 2, 0, bar_width, bar_height), Color.WHITE, false, 1.0)
