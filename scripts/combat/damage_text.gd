extends Node2D
class_name DamageText

var damage_amount: int = 0
var element_color: Color = Color.WHITE
var is_heal: bool = false
var is_crit: bool = false            # gold + oversized + wobble + a "CRIT" tag
var velocity: Vector2 = Vector2(0, -70)
var lifetime: float = 1.2
var elapsed: float = 0.0
var _fpos: Vector2 = Vector2.ZERO   # true float position; node is pixel-snapped from this
var scale_mult: float = 1.0  # Animates from 0.8 → 1.1 → 1.0

const CRIT_COLOR := Color(1.0, 0.84, 0.0)   # gold — overrides element color on a crit
const CRIT_SCALE := 1.45                     # crits render this much bigger than the same non-crit number

# Visual settings
@export var font: Font = preload("res://assets/Fonts/LeagueGothic-Regular.otf")
@export var font_size: int = 36
@export var outline_width: int = 2
@export var head_offset: Vector2 = Vector2(0, -16)
const HEAL_COLOR := Color(0.25, 0.95, 0.35)   # green — always this color, regardless of element

func _ready():
	pass

func setup(damage: int, element: UnitBase.Element, start_pos: Vector2, crit: bool = false):
	damage_amount = damage
	is_crit = crit
	# A crit reads as gold regardless of element — the "this one's special" signal.
	element_color = CRIT_COLOR if crit else get_element_color(element)
	is_heal = false
	_fpos = (start_pos + head_offset).round()
	global_position = _fpos
	# Crits pop straight up harder and float a touch longer so they own the moment.
	velocity = Vector2(randf_range(-3, 3), randf_range(-92, -74) if crit else randf_range(-70, -55))
	if crit:
		lifetime = 1.45
	z_index = 100  # Higher than your sprite's z_index
	queue_redraw()

# Same shape as setup(), but always green with a "+" prefix — used whenever a
# unit heals any HP at all (see UnitBase.heal()'s spawn_heal_text() call).
func setup_heal(amount: int, start_pos: Vector2):
	damage_amount = amount
	element_color = HEAL_COLOR
	is_heal = true
	_fpos = (start_pos + head_offset).round()
	global_position = _fpos
	velocity = Vector2(randf_range(-3, 3), randf_range(-70, -55))
	z_index = 100
	queue_redraw()

func _process(delta: float):
	elapsed += delta
	# Accumulate motion in a float, but snap the node to whole pixels each frame so
	# the font glyphs never land on sub-pixel positions (which smears the text).
	_fpos += velocity * delta
	global_position = _fpos.round()

	velocity.x = move_toward(velocity.x, 0.0, 40.0 * delta)
	velocity.y = move_toward(velocity.y, 0.0, 90.0 * delta)

	# Scale animation: pop out then settle. Crits overshoot harder (0.7→1.3) for punch.
	var pop_duration = 0.15
	var peak := 1.3 if is_crit else 1.1
	var start_s := 0.7 if is_crit else 0.8
	if elapsed < pop_duration:
		var pop_progress = elapsed / pop_duration
		scale_mult = lerp(start_s, peak, pow(pop_progress, 1.5))
	else:
		var settle_progress = (elapsed - pop_duration) / (lifetime - pop_duration)
		scale_mult = lerp(peak, 0.95, settle_progress)

	# Crit wobble: a quick decaying tilt so the gold number "kicks" as it lands.
	if is_crit:
		rotation = deg_to_rad(9.0) * sin(elapsed * 34.0) * maxf(0.0, 1.0 - elapsed / 0.4)

	if elapsed >= lifetime:
		queue_free()
	else:
		queue_redraw()
func _draw():
	if damage_amount <= 0:
		return

	var text = ("+" + str(damage_amount)) if is_heal else str(damage_amount)
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

	# Crit tag: a small "CRIT" caption riding just above the number.
	if is_crit:
		var tag := "CRIT"
		var tag_fs := int(round(fs * 0.42))
		var tag_size := draw_font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs)
		var tag_pos := Vector2(round(-tag_size.x / 2.0), round(-fs * 0.78))
		for xo in range(-outline_width, outline_width + 1):
			for yo in range(-outline_width, outline_width + 1):
				if xo != 0 or yo != 0:
					draw_string(draw_font, tag_pos + Vector2(xo, yo), tag,
						HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs, outline_color)
		draw_string(draw_font, tag_pos, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs, color)

func get_scaled_font_size() -> int:
	var t = inverse_lerp(1.0, 9999.0, float(damage_amount))
	t = clamp(t, 0.0, 1.0)
	t = pow(t, 0.6)
	var damage_scale = lerp(1.0, 1.8, t)
	var crit_mult := CRIT_SCALE if is_crit else 1.0
	return int(round(font_size * damage_scale * scale_mult * crit_mult))
	

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
