extends Node2D
## Headless check that a merged character .glb imported and animates cleanly.
##
## Prints the node tree, the skeleton bone count and every animation with its
## length, then renders a contact sheet — one row per animation, sampled evenly
## across its length — so the rig can be eyeballed without opening the editor.
## Same pattern as the other capture tools in this folder (see CONVENTIONS.md).
##
##   GODOT --headless --path . --script res://scenes/tools/model3d_probe.tscn
##   (run the SCENE, not this script; it needs a 2D tree to render into)
##
## Optional CLI args (after --):
##   model=res://assets/3d pipeline/hero/bouncer/bouncer.glb
##   cols=6  out=user://_model3d_probe.png

const DEFAULT_MODEL := "res://assets/3d pipeline/hero/bouncer/bouncer.glb"
const CELL := 160          ## on-sheet size of one pose
const CHAR_H := 130.0      ## rendered character height inside a cell

var _opts := {}
var _shot: Model3DSprite

func _ready() -> void:
	_opts = _parse_args()
	var path: String = _opts.get("model", DEFAULT_MODEL)
	if not ResourceLoader.exists(path):
		push_error("model not found: %s" % path)
		get_tree().quit(1)
		return

	# ── structural report ────────────────────────────────────────────────────
	var inspect: Node = (load(path) as PackedScene).instantiate()
	add_child(inspect)
	print("=== %s ===" % path)
	_dump_tree(inspect, 0)

	var skel := _find(inspect, "Skeleton3D") as Skeleton3D
	if skel:
		print("\nskeleton: %d bones (root bone: %s)" % [skel.get_bone_count(), skel.get_bone_name(0)])
	else:
		push_warning("no Skeleton3D — the mesh will not deform")

	var ap := _find(inspect, "AnimationPlayer") as AnimationPlayer
	if not ap:
		push_error("no AnimationPlayer — animations did not import")
		get_tree().quit(1)
		return

	var names := ap.get_animation_list()
	print("\nanimations (%d):" % names.size())
	for n in names:
		var a := ap.get_animation(n)
		print("  %-14s %6.2fs  %3d tracks" % [n, a.length, a.get_track_count()])

	var bounds := Model3DSprite.character_bounds(inspect)
	print("\nmodel aabb: pos=%s size=%s (height %.3f units)" % [bounds.position, bounds.size, bounds.size.y])
	inspect.queue_free()

	# ── contact sheet ────────────────────────────────────────────────────────
	var cols: int = int(_opts.get("cols", "6"))
	await _render_sheet(path, names, cols)
	get_tree().quit(0)

## One Model3DSprite is reused for every pose: set the animation, seek to the
## sample time, let the SubViewport render a frame, then blit it into the sheet.
func _render_sheet(path: String, names: PackedStringArray, cols: int) -> void:
	_shot = Model3DSprite.new()
	add_child(_shot)
	if not _shot.setup(path, CHAR_H):
		return

	var sheet := Image.create(cols * CELL, names.size() * CELL, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.09, 0.10, 0.13, 1.0))

	var font := ThemeDB.fallback_font
	for row in names.size():
		var anim_name := names[row]
		var length: float = _shot._anim.get_animation(anim_name).length
		for col in cols:
			_shot.play(anim_name)
			# Sample across the clip; the last column lands just shy of the end
			# so a looping clip doesn't show frame 0 twice.
			var t: float = length * (float(col) / float(cols))
			_shot._anim.seek(t, true)
			_shot._anim.advance(0.0)
			await RenderingServer.frame_post_draw
			var frame := _shot._viewport.get_texture().get_image()
			frame.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
			frame.convert(Image.FORMAT_RGBA8)
			sheet.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()),
				Vector2i(col * CELL, row * CELL))
		print("  sheet row %d: %s (%.2fs)" % [row, anim_name, length])

	var out: String = _opts.get("out", "user://_model3d_probe.png")
	sheet.save_png(ProjectSettings.globalize_path(out))
	print("\nwrote %s (%dx%d, %d clips)" % [out, sheet.get_width(), sheet.get_height(), names.size()])

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			out[kv[0]] = kv[1]
	return out

func _dump_tree(n: Node, depth: int) -> void:
	print("  ".repeat(depth) + "%s (%s)" % [n.name, n.get_class()])
	for c in n.get_children():
		_dump_tree(c, depth + 1)

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null

