extends Node2D
class_name TexturedSkillEffect

# Plays a horizontal sprite-sheet animation once, then frees itself.
# Each frame is frame_width x frame_height, laid out left-to-right with no gaps.

var frame_width: int = 64
var frame_height: int = 60
var frame_count: int = 1
var fps: float = 18.0
var target_size: Vector2 = Vector2(140, 140)   # max bounding box; aspect ratio preserved

var _sheet: Texture2D
var _sprite: Sprite2D
var _atlas: AtlasTexture
var _elapsed: float = 0.0

func setup(sheet: Texture2D, world_pos: Vector2, f_width: int, f_height: int,
		f_count: int, box_size: Vector2, playback_fps: float = 18.0) -> void:
	_sheet = sheet
	frame_width = f_width
	frame_height = f_height
	frame_count = max(f_count, 1)
	target_size = box_size
	fps = playback_fps
	global_position = world_pos
	# Units render at z_index 1 — draw above them so the effect isn't hidden behind
	# whichever unit happens to y-sort in front of it.
	z_index = 5

	_atlas = AtlasTexture.new()
	_atlas.atlas = _sheet
	_atlas.region = Rect2(0, 0, frame_width, frame_height)

	_sprite = Sprite2D.new()
	_sprite.texture = _atlas
	add_child(_sprite)
	_apply_scale()

func _apply_scale() -> void:
	# Fit frame_width x frame_height inside target_size, preserving aspect ratio.
	var s: float = min(target_size.x / frame_width, target_size.y / frame_height)
	_sprite.scale = Vector2(s, s)

func _process(delta: float) -> void:
	_elapsed += delta
	var frame: int = int(_elapsed * fps)
	if frame >= frame_count:
		queue_free()
		return
	_atlas.region = Rect2(frame * frame_width, 0, frame_width, frame_height)
