extends Node
func _ready() -> void:
	var scn: PackedScene = load("res://assets/3d pipeline/hero/riot/riot.glb")
	var root: Node = scn.instantiate()
	add_child(root)
	await get_tree().process_frame
	var skels: Array = []
	var anims: Array = []
	_walk(root, skels, anims)
	print("DIAG skeletons: %d" % skels.size())
	for s in skels:
		print("   %-28s bones=%d" % [s.name, s.get_bone_count()])
	for a in anims:
		print("DIAG AnimationPlayer '%s' clips=%s" % [a.name, a.get_animation_list()])
		if a.get_animation_list().size() > 0:
			var clip: String = "attack" if a.has_animation("attack") else a.get_animation_list()[0]
			var an: Animation = a.get_animation(clip)
			print("   clip '%s' len=%.2f tracks=%d" % [clip, an.length, an.get_track_count()])
			for t in mini(4, an.get_track_count()):
				print("      track %d path=%s type=%d" % [t, an.track_get_path(t), an.track_get_type(t)])
	get_tree().quit(0)

func _walk(n: Node, skels: Array, anims: Array) -> void:
	if n is Skeleton3D: skels.append(n)
	if n is AnimationPlayer: anims.append(n)
	for c in n.get_children(): _walk(c, skels, anims)
