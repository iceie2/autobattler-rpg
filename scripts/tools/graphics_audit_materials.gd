extends Node
## Graphics audit 2026-10-02: read-only live material inventory (metallic and
## roughness channels included) for every 3D hero and 3D monster model.

func _ready() -> void:
	var paths: Dictionary = {}
	for cls in VisualUnit.HERO_MODEL_PATHS:
		paths[UnitBase.UnitClass.find_key(cls)] = VisualUnit.HERO_MODEL_PATHS[cls]
	for k in VisualUnit.MONSTER_MODEL_PATHS:
		paths["mon:" + k] = VisualUnit.MONSTER_MODEL_PATHS[k]
	for key in paths:
		var scene := load(paths[key]) as PackedScene
		if scene == null:
			continue
		var root := scene.instantiate()
		var seen := {}
		for n in Model3DSprite._walk(root):
			if n is MeshInstance3D:
				for s in n.mesh.get_surface_count():
					var m = n.get_active_material(s)
					if m is BaseMaterial3D and not seen.has(m.get_instance_id()):
						seen[m.get_instance_id()] = true
						print("MAT %-22s %-30s metal=%.2f metal_tex=%s ch=%d rough=%.2f rough_tex=%s emis=%s emis_tex=%s albedo=%s" % [
							key, m.resource_name, m.metallic, m.metallic_texture != null,
							m.metallic_texture_channel, m.roughness, m.roughness_texture != null,
							m.emission_enabled, m.emission_texture != null, m.albedo_color])
		root.free()
	get_tree().quit()
