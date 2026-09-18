extends SceneTree
## Headless check: does the camera frame widen to include the death clip?
## Run: godot --headless --script res://scripts/tools/_death_frame_check.gd

var _m
var _done := false

func _initialize() -> void:
	var Model3DSprite = load("res://scripts/units/model3d_sprite.gd")
	_m = Model3DSprite.new()
	_m.camera_pitch_deg = 18.0
	root.add_child(_m)

func _process(_dt: float) -> bool:
	if _done:
		return true
	_done = true
	var ok: bool = _m.setup("res://assets/3d pipeline/hero/bouncer/bouncer.glb", 118.0)
	print("setup ok:", ok)
	print("model_height (idle):", _m._model_height)
	print("camera.size (frame):", _m._camera.size if _m._camera else "NO CAMERA")
	print("sprite_scale_compensation:", _m._sprite_scale_compensation)
	print("_sprite.scale:", _m._sprite.scale)
	var effective_px_per_unit: float = _m._sprite.scale.y * (float(_m.render_size.y) / _m._camera.size)
	print("effective on-screen px-per-world-unit:", effective_px_per_unit)
	print("idle character on-screen height (should be ~118):", _m._model_height * effective_px_per_unit)

	var Model3DSprite = load("res://scripts/units/model3d_sprite.gd")
	var idle_aabb = Model3DSprite.character_bounds(_m._model)
	var idle_centre = idle_aabb.position + idle_aabb.size * 0.5
	print("idle_centre:", idle_centre)
	print("camera.position:", _m._camera.position)
	print("(camera x/z should equal idle_centre x/z; camera y is offset by pitch, not equal)")
	return true
