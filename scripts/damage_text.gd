extends Node2D
class_name DamageText

var damage_amount: int = 0
var element_color: Color = Color.WHITE
var velocity: Vector2 = Vector2(0, -50)  # Move upward
var lifetime: float = 1.0
var elapsed: float = 0.0

# Visual settings
var font_size: int = 20
var outline_width: int = 2

func _ready():
	pass

func setup(damage: int, element: UnitBase.Element, start_pos: Vector2):
	damage_amount = damage
	element_color = get_element_color(element)
	global_position = start_pos
	
	# Add some random horizontal drift
	velocity.x = randf_range(-20, 20)
	
	queue_redraw()

func _process(delta: float):
	elapsed += delta
	
	# Move upward and fade out
	position += velocity * delta
	
	# Slow down over time
	velocity *= 0.95
	
	# Delete when lifetime expires
	if elapsed >= lifetime:
		queue_free()
	else:
		queue_redraw()

func _draw():
	if damage_amount <= 0:
		return
	
	var text = str(damage_amount)
	var alpha = 1.0 - (elapsed / lifetime)
	
	# Create color with fade
	var color = Color(element_color.r, element_color.g, element_color.b, alpha)
	var outline_color = Color(0, 0, 0, alpha)
	
	# Draw text with outline effect
	var font = ThemeDB.fallback_font
	var size = font_size
	
	# Draw outline (black)
	for x_offset in range(-outline_width, outline_width + 1):
		for y_offset in range(-outline_width, outline_width + 1):
			if x_offset != 0 or y_offset != 0:
				draw_string(font, Vector2(x_offset, y_offset), text, HORIZONTAL_ALIGNMENT_CENTER, -1, size, outline_color)
	
	# Draw main text
	draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_CENTER, -1, size, color)

func get_element_color(elem: UnitBase.Element) -> Color:
	match elem:
		UnitBase.Element.FIRE:
			return Color(1.0, 0.3, 0.0)  # Orange-red
		UnitBase.Element.WATER:
			return Color(0.2, 0.6, 1.0)  # Blue
		UnitBase.Element.EARTH:
			return Color(0.7, 0.5, 0.2)  # Brown/tan
		UnitBase.Element.AIR:
			return Color(0.8, 1.0, 1.0)  # Light cyan
		UnitBase.Element.LIGHTNING:
			return Color(1.0, 1.0, 0.2)  # Bright yellow
		UnitBase.Element.NORMAL:
			return Color(1.0, 1.0, 1.0)  # White
		_:
			return Color(1.0, 1.0, 1.0)
