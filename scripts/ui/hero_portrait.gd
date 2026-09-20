extends Control
class_name HeroPortrait

# Drop-in replacement for a static hero TextureRect: plays the hero's
# in-battle idle animation (assets/sprites/heroes/<key>/idle_south.png+json)
# when it exists, scaled/centred to fit this control's rect exactly like a
# TextureRect with STRETCH_KEEP_ASPECT_CENTERED would. Falls back to the
# static VisualUnit.HERO_SPRITE_PATHS PNG for heroes that don't have
# generated idle frames yet, so every call site can switch over uniformly.

var _sprite: AnimatedSprite2D
var _static_rect: TextureRect
var _resize_cb: Callable

func setup(unit_class: int) -> void:
	_teardown()

	if not VisualUnit.HERO_SPRITE_PATHS.has(unit_class):
		return
	var hero_path: String = VisualUnit.HERO_SPRITE_PATHS[unit_class]
	var hero_key: String = hero_path.get_file().get_basename()
	var dir := "res://assets/sprites/heroes/%s" % hero_key
	var png_path := "%s/idle_south.png" % dir
	var json_path := "%s/idle_south.json" % dir

	if ResourceLoader.exists(png_path) and FileAccess.file_exists(json_path):
		var f := FileAccess.open(json_path, FileAccess.READ)
		var meta = JSON.parse_string(f.get_as_text())
		f.close()
		if meta is Dictionary and meta.has("frame_w") and meta.has("count"):
			_setup_animated(png_path, meta)
			return

	_setup_static(hero_path)

func _setup_animated(png_path: String, meta: Dictionary) -> void:
	var texture: Texture2D = load(png_path)
	var frame_w: int = int(meta["frame_w"])
	var frame_h: int = int(meta.get("frame_h", frame_w))
	var count: int = int(meta["count"])
	var fps: float = float(meta.get("fps", 12.0))
	# Normalize against visible pixels, not the export canvas. Different source
	# sheets carry wildly different transparent margins, which made one recruit
	# look tiny and the next overflow the exact same portrait frame.
	var used := Rect2i(0, 0, frame_w, frame_h)
	var image: Image = texture.get_image()
	if image:
		var union := Rect2i()
		for i in range(count):
			var frame_used: Rect2i = image.get_region(Rect2i(i * frame_w, 0, frame_w, frame_h)).get_used_rect()
			if frame_used.size == Vector2i.ZERO:
				continue
			union = frame_used if union.size == Vector2i.ZERO else union.merge(frame_used)
		if union.size != Vector2i.ZERO:
			used = _padded_rect(union, Vector2i(frame_w, frame_h))

	var sf := SpriteFrames.new()
	sf.add_animation("idle_south")
	sf.set_animation_loop("idle_south", true)
	sf.set_animation_speed("idle_south", fps)
	for i in range(count):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * frame_w + used.position.x, used.position.y,
			used.size.x, used.size.y)
		sf.add_frame("idle_south", atlas)

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = sf
	add_child(_sprite)
	_sprite.play("idle_south")
	_layout_sprite(used.size.x, used.size.y)
	_resize_cb = func(): _layout_sprite(used.size.x, used.size.y)
	resized.connect(_resize_cb)

func _layout_sprite(frame_w: int, frame_h: int) -> void:
	if not _sprite:
		return
	var s := size
	if s.x <= 0.0 or s.y <= 0.0 or frame_w <= 0 or frame_h <= 0:
		return
	var scale_val: float = min(s.x / float(frame_w), s.y / float(frame_h))
	_sprite.scale = Vector2(scale_val, scale_val)
	_sprite.position = s * 0.5

func _setup_static(hero_path: String) -> void:
	_static_rect = TextureRect.new()
	var texture: Texture2D = load(hero_path)
	var shown: Texture2D = texture
	if texture:
		var image: Image = texture.get_image()
		if image:
			var used: Rect2i = image.get_used_rect()
			if used.size != Vector2i.ZERO:
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = _padded_rect(used, image.get_size())
				shown = atlas
	_static_rect.texture = shown
	_static_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_static_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_static_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Must be added to the tree (i.e. have a parent) BEFORE the FULL_RECT preset
	# is applied — with no parent yet, Godot sizes the anchors/offsets against
	# the viewport instead, which blew this up to full-screen size.
	add_child(_static_rect)
	_static_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _padded_rect(rect: Rect2i, bounds: Vector2i) -> Rect2i:
	var pad: int = maxi(4, int(maxi(rect.size.x, rect.size.y) * 0.07))
	var x0 := maxi(0, rect.position.x - pad)
	var y0 := maxi(0, rect.position.y - pad)
	var x1 := mini(bounds.x, rect.end.x + pad)
	var y1 := mini(bounds.y, rect.end.y + pad)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)

func _teardown() -> void:
	if _resize_cb.is_valid() and resized.is_connected(_resize_cb):
		resized.disconnect(_resize_cb)
	_resize_cb = Callable()
	if _sprite and is_instance_valid(_sprite):
		_sprite.queue_free()
		_sprite = null
	if _static_rect and is_instance_valid(_static_rect):
		_static_rect.queue_free()
		_static_rect = null
