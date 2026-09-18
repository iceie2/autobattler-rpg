extends Node2D
## Side-by-side filmstrip of the SAME clip on two versions of a model, so a
## skin-weight change can actually be judged.
##
##   GODOT --path . res://scenes/tools/glove_compare.tscn -- \
##       a=res://.../boxing_bot.glb b=res://.../_bot_hard.glb clip=attack
##   → user://_glove_compare.png   (top row = a, bottom row = b)
##
## Windowed: the characters render through SubViewports and need a real GPU.
##
## Rendered large and un-toon'd on purpose — the outline and the 118px board size
## both hide exactly the kind of small deformation error this is meant to show.

const OUT := "user://_glove_compare.png"
const COLS := 6
const CELL := Vector2i(320, 320)
const CHAR_H := 300.0

var _opts := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			_opts[kv[0]] = kv[1]

	var a_path: String = _opts.get("a", "res://assets/3d pipeline/hero/bouncer/bouncer.glb")
	var b_path: String = _opts.get("b", "res://assets/3d pipeline/hero/bouncer/bouncer.glb")
	var clip: String = _opts.get("clip", "attack")

	get_window().size = Vector2i(400, 300)
	var sheet := Image.create(CELL.x * COLS, CELL.y * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.10, 0.11, 0.14, 1.0))

	await _row(sheet, 0, a_path, clip)
	await _row(sheet, 1, b_path, clip)

	sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote %s  (top=%s, bottom=%s, clip=%s)"
		% [OUT, a_path.get_file(), b_path.get_file(), clip])
	get_tree().quit(0)

func _row(sheet: Image, row: int, path: String, clip: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("missing model: %s" % path)
		return
	var m := Model3DSprite.new()
	m.toon = false          # flat shading shows deformation; the outline hides it
	m.stretch_arm = false   # judging the WEIGHTS, not the stretch
	add_child(m)
	if not m.setup(path, CHAR_H):
		return
	m.get_sprite().position = Vector2(-9000, 0)   # keep it out of the captured frame

	var length: float = m.animation_length(clip)
	m.play(clip, false)
	for c in COLS:
		m._anim.seek(length * (float(c) / float(COLS - 1)) * 0.999, true)
		m._anim.advance(0.0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var frame := m._viewport.get_texture().get_image()
		frame.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
		frame.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()),
			Vector2i(c * CELL.x, row * CELL.y))
	m.queue_free()
