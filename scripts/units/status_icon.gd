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

func setup(sheet: Texture2D, f_width: int, f_height: int, f_count: int,
		display_size: Vector2, playback_fps: float = 6.0) -> void:
	frame_width = f_width
	frame_height = f_height
	frame_count = max(f_count, 1)
	fps = playback_fps
	z_index = 6

	_atlas = AtlasTexture.new()
	_atlas.atlas = sheet
	_atlas.region = Rect2(0, 0, frame_width, frame_height)

	_sprite = Sprite2D.new()
	_sprite.texture = _atlas
	var s: float = min(display_size.x / frame_width, display_size.y / frame_height)
	_sprite.scale = Vector2(s, s)
	add_child(_sprite)
	visible = false

func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	var frame: int = int(_elapsed * fps) % frame_count
	_atlas.region = Rect2(frame * frame_width, 0, frame_width, frame_height)
