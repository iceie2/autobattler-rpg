extends Node2D
class_name StatusIcon

# Loops a small sprite-sheet animation above a unit's head for as long as a
# status effect is active (stun, burn, etc. — anything gated by a >0 timer on
# UnitBase). Unlike TexturedSkillEffect this loops forever and is shown/hidden
# by the owning unit rather than freeing itself.

var frame_width: int = 96
var frame_height: int = 96
var frame_count: int = 1
var fps: float = 6.0

var _sprite: Sprite2D
var _atlas: AtlasTexture
var _elapsed: float = 0.0
var _count_lbl: Label

const COUNT_FONT := preload("res://assets/Fonts/LeagueGothic-Regular.otf")

# f_width/f_height of 0 means "the sheet is a single whole image" — the element
# stack glyphs are plain PNGs of unknown size, so their dimensions come from the
# texture rather than being hardcoded per entry (2026-08-02).
func setup(sheet: Texture2D, f_width: int, f_height: int, f_count: int,
		display_size: Vector2, playback_fps: float = 6.0, tint: Color = Color.WHITE) -> void:
	frame_count = max(f_count, 1)
	if f_width <= 0 or f_height <= 0:
		frame_width = int(sheet.get_width()) / frame_count
		frame_height = int(sheet.get_height())
	else:
		frame_width = f_width
		frame_height = f_height
	fps = playback_fps
	z_index = 6

	_atlas = AtlasTexture.new()
	_atlas.atlas = sheet
	_atlas.region = Rect2(0, 0, frame_width, frame_height)

	_sprite = Sprite2D.new()
	_sprite.texture = _atlas
	_sprite.modulate = tint
	var s: float = min(display_size.x / frame_width, display_size.y / frame_height)
	_sprite.scale = Vector2(s, s)
	add_child(_sprite)
	visible = false

# Stack count riding on the icon's lower-right. Hidden at count <= 1, because a
# lone "1" is noise — the icon itself already says the status is present. What
# matters is watching the number climb toward the pop.
func set_count(n: int) -> void:
	if n <= 1:
		if _count_lbl:
			_count_lbl.visible = false
		return
	if not _count_lbl:
		_count_lbl = Label.new()
		_count_lbl.add_theme_font_override("font", COUNT_FONT)
		_count_lbl.add_theme_font_size_override("font_size", 18)
		_count_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		_count_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_count_lbl.add_theme_constant_override("outline_size", 4)
		_count_lbl.z_index = 1
		_count_lbl.position = Vector2(2, -4)
		add_child(_count_lbl)
	_count_lbl.visible = true
	_count_lbl.text = str(n)

func _process(delta: float) -> void:
	if not visible:
		return
	if frame_count <= 1:
		return   # static glyph — nothing to animate
	_elapsed += delta
	var frame: int = int(_elapsed * fps) % frame_count
	_atlas.region = Rect2(frame * frame_width, 0, frame_width, frame_height)
