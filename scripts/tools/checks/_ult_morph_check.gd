extends SceneTree
## Minimal headless check: does bouncer.glb's "ult" animation actually drive
## the mesh's "bulk" blend shape weight through Godot's own AnimationPlayer,
## with no viewport/rendering involved at all (so it can't hang on the dummy
## renderer). Run with:
##   godot --headless --script res://scripts/tools/checks/_ult_morph_check.gd

func _initialize() -> void:
	var path := "res://assets/3d pipeline/hero/bouncer/bouncer.glb"
	var model: Node = (load(path) as PackedScene).instantiate()
	root.add_child(model)

	var ap: AnimationPlayer = _find(model, "AnimationPlayer")
	if not ap:
		print("NO ANIMATIONPLAYER")
		quit(1)
		return

	var mi: MeshInstance3D = _find(model, "MeshInstance3D")
	if not mi:
		print("NO MESHINSTANCE3D")
		quit(1)
		return

	var bulk_idx := -1
	for i in mi.mesh.get_blend_shape_count():
		print("blend shape %d: %s" % [i, mi.mesh.get_blend_shape_name(i)])
		if mi.mesh.get_blend_shape_name(i) == "bulk":
			bulk_idx = i
	if bulk_idx < 0:
		print("NO 'bulk' BLEND SHAPE ON THE MESH")
		quit(1)
		return

	if not ap.has_animation("ult"):
		print("NO 'ult' ANIMATION")
		quit(1)
		return
	var anim := ap.get_animation("ult")
	print("ult: %.2fs, %d tracks" % [anim.length, anim.get_track_count()])
	for t in anim.get_track_count():
		print("  track %d: type=%s path=%s" % [t, anim.track_get_type(t), anim.track_get_path(t)])

	ap.play("ult")
	print("\nblend_shapes property name for 'bulk': %s" % mi.mesh.get_blend_shape_name(bulk_idx))
	for f in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.5, 2.0]:
		ap.seek(f, true)
		var w: float = mi.get_blend_shape_value(bulk_idx)
		print("t=%.2f  bulk weight=%.4f" % [f, w])

	quit(0)

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
