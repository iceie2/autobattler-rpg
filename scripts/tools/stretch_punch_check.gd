extends Node2D
## Filmstrip of the stretch punch, so the reach can be judged frame by frame.
##
##   GODOT --path . res://scenes/tools/stretch_punch_check.tscn
##   → user://_stretch_punch.png
##
## Top row: stretch ON. Bottom row: the same clip with stretch OFF, same frames.
## Windowed (the character needs a real GPU render).
##
## Also asserts the arm actually gets longer. The stretch is baked into the clip's
## scale tracks, so a silent failure (wrong bone name, missing track, the bake not
## running) just gives a plain punch with no error anywhere — this is what catches
## that. It already caught one: the first, runtime-modifier version measured x1.00.

const OUT := "user://_stretch_punch.png"
const MODEL := "res://assets/3d pipeline/hero/bouncer/bouncer.glb"
const CLIP := "attack"
const CELL := 210
const CELL_W := 400
const COLS := 7
const CHAR_H := 190.0

var _fail: Array[String] = []

func _ready() -> void:
	var sheet := Image.create(CELL_W * COLS, CELL * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.10, 0.11, 0.14, 1.0))

	var reach_on := await _strip(sheet, 0, true)
	var reach_off := await _strip(sheet, 1, false)

	print("max hand reach from shoulder:  stretch ON %.3f   OFF %.3f  (x%.2f)"
		% [reach_on, reach_off, reach_on / maxf(reach_off, 0.001)])
	if reach_on <= reach_off * 1.15:
		_fail.append("arm did not measurably lengthen (%.3f vs %.3f) — the modifier "
			% [reach_on, reach_off] + "is probably being overwritten by the AnimationPlayer")

	sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote %s" % OUT)
	if _fail.is_empty():
		print("STRETCH_PUNCH: ALL PASS")
		get_tree().quit(0)
	else:
		for f in _fail:
			printerr("STRETCH_PUNCH FAIL  " + f)
		get_tree().quit(1)

## Renders one row of the filmstrip and returns the furthest the hand ever got
## from the shoulder during the clip.
func _strip(sheet: Image, row: int, stretch: bool) -> float:
	var m := Model3DSprite.new()
	m.stretch_arm = stretch
	add_child(m)
	if not m.setup(MODEL, CHAR_H):
		_fail.append("setup failed (stretch=%s)" % stretch)
		return 0.0
	m.get_sprite().position = Vector2(-9000, 0)   # keep it out of the captured frame

	var skel := m._find(m._model, "Skeleton3D") as Skeleton3D
	var hand: int = skel.find_bone("RightHand")
	var shoulder: int = skel.find_bone("RightArm")

	var length: float = m.animation_length(CLIP)
	m.play_oneshot(CLIP)
	var best: float = 0.0
	for c in COLS:
		var t: float = length * (float(c) / float(COLS - 1)) * 0.999
		m._anim.seek(t, true)
		m._anim.advance(0.0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw

		var d: float = (skel.get_bone_global_pose(hand).origin
			- skel.get_bone_global_pose(shoulder).origin).length()
		best = maxf(best, d)

		var frame := m._viewport.get_texture().get_image()
		# Preserve aspect: the stretch row uses a WIDER viewport than the plain
		# row, and squashing both into one cell size made the comparison lie.
		var fit: float = minf(float(CELL_W) / frame.get_width(),
			float(CELL) / frame.get_height())
		frame.resize(int(frame.get_width() * fit), int(frame.get_height() * fit),
			Image.INTERPOLATE_LANCZOS)
		frame.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()),
			Vector2i(c * CELL_W + (CELL_W - frame.get_width()) / 2,
				row * CELL + (CELL - frame.get_height()) / 2))
	m.queue_free()
	return best

