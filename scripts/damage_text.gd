extends Node2D
class_name DamageText

var damage_amount: int = 0
var element_color: Color = Color.WHITE
var velocity: Vector2 = Vector2(0, -70)
var lifetime: float = 1.2
var elapsed: float = 0.0
var _fpos: Vector2 = Vector2.ZERO   # true float position; node is pixel-snapped from this
var scale_mult: float = 1.0  # Animates from 0.8 → 1.1 → 1.0

# Visual settings
@export var font: Font = preload("res://assets/Fonts/LeagueGothic-Regular.otf")
@export var font_size: int = 36
@export var outline_width: int = 2
@export var head_offset: Vector2 = Vector2(0, -16)

func _ready():
	pass

func setup(damage: int, element: UnitBase.Element, start_pos: Vector2):
	damage_amount = damage
	element_color = get_element_color(element)
	_fpos = (start_pos + head_offset).round()
	global_position = _fpos
	velocity = Vector2(randf_range(-3, 3), randf_range(-70, -55))
	z_index = 100  # Higher than your sprite's z_index
	queue_redraw()

func _process(delta: float):
	elapsed += delta
	# Accumulate motion in a float, but snap the node to whole pixels each frame so
	# the font glyphs never land on sub-pixel positions (which smears the text).
	_fpos += velocity * delta
	global_position = _fpos.round()

	velocity.x = move_toward(velocity.x, 0.0, 40.0 * delta)
	velocity.y = move_toward(velocity.y, 0.0, 90.0 * delta)

	# Scale animation: pop out 0.8→1.1 in first 0.15s, then settle back to 1.0
	var pop_duration = 0.15
	if elapsed < pop_duration:
		var pop_progress = elapsed / pop_duration
		scale_mult = lerp(0.8, 1.1, pow(pop_progress, 1.5))
	else:
		var settle_progress = (elapsed - pop_duration) / (lifetime - pop_duration)
		scale_mult = lerp(1.1, 0.95, settle_progress)

	if elapsed >= lifetime:
		queue_free()
	else:
		queue_redraw()
func _draw():
	if damage_amount <= 0:
		return

	var text = str(damage_amount)
	var alpha = 1.0 - (elapsed / lifetime)

	var color = Color(element_color.r, element_color.g, element_color.b, alpha)
	var outline_color = Color(0, 0, 0, alpha)

	var draw_font = font if font != null else ThemeDB.fallback_font
	var fs = get_scaled_font_size()
	var text_size = draw_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	# Whole-pixel origin so glyphs stay crisp.
	var pos = Vector2(round(-text_size.x / 2.0), 0)

	for x_offset in range(-outline_width, outline_width + 1):
		for y_offset in range(-outline_width, outline_width + 1):
			if x_offset != 0 or y_offset != 0:
				draw_string(
					draw_font,
					pos + Vector2(x_offset, y_offset),
					text,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					fs,
					outline_color
				)

	draw_string(
		draw_font,
		pos,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		color
	)

func get_scaled_font_size() -> int:
	var t = inverse_lerp(1.0, 9999.0, float(damage_amount))
	t = clamp(t, 0.0, 1.0)
	t = pow(t, 0.6)
	var damage_scale = lerp(1.0, 1.8, t)
	return int(round(font_size * damage_scale * scale_mult))
	

func get_element_color(elem: UnitBase.Element) -> Color:
	match elem:
		UnitBase.Element.FIRE:
			return Color(1.0, 0.3, 0.0)
		UnitBase.Element.WATER:
			return Color(0.2, 0.6, 1.0)
		UnitBase.Element.EARTH:
			return Color(0.7, 0.5, 0.2)
		UnitBase.Element.AIR:
			return Color(0.8, 1.0, 1.0)
		UnitBase.Element.LIGHTNING:
			return Color(1.0, 1.0, 0.2)
		UnitBase.Element.NORMAL:
			return Color(1.0, 1.0, 1.0)
		_:
			return Color(1.0, 1.0, 1.0)
