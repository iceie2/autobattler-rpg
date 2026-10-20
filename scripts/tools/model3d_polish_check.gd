extends "res://scripts/tools/model3d_quality_audit.gd"
## Visual QA plus behavioral checks for glow isolation, source-material safety,
## and motion transition measurements. Uses an offscreen full-size board.
const POLISH_DIR := "res://../captures/renders/quality_polish_20261002"
var failures: Array[String] = []

func _ready() -> void:
	seed(20261002)
	Model3DSprite.debug_style_override = {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(POLISH_DIR))
	board = SubViewport.new()
	board.size = Vector2i(1920, 1080)
	board.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(board)
	_make_canvas()
	for col in SUBJECTS.size():
		_label(UnitBase.UnitClass.find_key(SUBJECTS[col]).capitalize(), Vector2(235 + col * 225, 44), 22)
	_label("Nemi (2D)", Vector2(1590, 44), 22)
	for row in 3:
		_label(["Approved PBR baseline", "Polish / 2x MSAA", "Polish / 4x MSAA"][row], Vector2(12, 150 + row * 300), 24)
		for col in SUBJECTS.size():
			var u := _spawn(SUBJECTS[col], Vector2(300 + col * 225, 230 + row * 300))
			var m := u.model3d
			m._viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][row]
			m._sprite.material.set_shader_parameter("soft_edges", row > 0)
			if row == 0:
				u.soft_contact_shadow = false
				for node in m._walk(m._model):
					if node is MeshInstance3D:
						for s in node.mesh.get_surface_count():
							node.set_surface_override_material(s, null)
		var nemi := _spawn(UnitBase.UnitClass.NEMI, Vector2(1650, 230 + row * 300))
		_check(nemi.model3d == null, "Nemi remains 2D")
	await _save("edges_before_after.png", true)
	await _clear_canvas()
	_make_canvas()
	var glowing := [UnitBase.UnitClass.DOC, UnitBase.UnitClass.BLOODHOUND,
		UnitBase.UnitClass.CROSS, UnitBase.UnitClass.STATIC]
	for col in glowing.size():
		var cls: int = glowing[col]
		_label(UnitBase.UnitClass.find_key(cls).capitalize(), Vector2(355 + col * 340, 45), 24)
		var copies: Array[Model3DSprite] = []
		var source_state: Dictionary = {}
		for row in 3:
			var u := _spawn(cls, Vector2(420 + col * 340, 255 + row * 300))
			var m := u.model3d
			copies.append(m)
			var clip: String = ["idle", "skill" if m.has_animation("skill") else "attack", "ult"][row]
			_check(m.play(clip), "%s can play %s" % [UnitBase.UnitClass.find_key(cls), clip])
			m._viewport.msaa_3d = Viewport.MSAA_2X
			_check(not m._pbr_glow_mats.is_empty(), "PBR glow surfaces registered")
			var expected: Color = m.glow_by_clip.get(clip, m.glow_base)
			for mat in m._pbr_glow_mats:
				_check(mat.emission.is_equal_approx(Color(expected.r, expected.g, expected.b, 1)), "Clip sets native emission color")
				_check(is_equal_approx(mat.emission_energy_multiplier, expected.a * m.glow_energy), "Clip sets native glow intensity")
			for node in m._walk(m._model):
				if node is MeshInstance3D:
					for s in node.mesh.get_surface_count():
						var src: Material = node.mesh.surface_get_material(s)
						if src is BaseMaterial3D and src.resource_name == m.glow_material:
							var active: BaseMaterial3D = node.get_active_material(s)
							_check(active != src, "Glow material copied instead of mutating imported source")
							_check(active.albedo_texture == src.albedo_texture and active.emission_texture == src.emission_texture, "Native material textures retained")
							_check(is_equal_approx(active.roughness, src.roughness), "Native roughness retained")
							if source_state.has(src.get_instance_id()):
								_check(source_state[src.get_instance_id()] == [src.albedo_color, src.emission, src.emission_energy_multiplier], "Imported source material unchanged across instances")
							else:
								source_state[src.get_instance_id()] = [src.albedo_color, src.emission, src.emission_energy_multiplier]
			_label(clip, Vector2(350 + col * 340, 165 + row * 300), 20)
		for a in copies.size():
			for b in range(a + 1, copies.size()):
				for mat in copies[a]._pbr_glow_mats:
					_check(not copies[b]._pbr_glow_mats.has(mat), "Each hero owns independent glow materials")
	await _save("glow_idle_skill_ult.png", true)
	await _clear_canvas()
	_make_canvas()
	var transitions: Array = []
	for cls in VisualUnit.HERO_MODEL_PATHS:
		var u := _spawn(cls, Vector2.ZERO)
		transitions.append(_transition_metrics(u.model3d, UnitBase.UnitClass.find_key(cls)))
		if cls in [UnitBase.UnitClass.VAIL, UnitBase.UnitClass.LUMEN]:
			for node in u.model3d._walk(u.model3d._model):
				if node is MeshInstance3D:
					var src: Material = node.mesh.surface_get_material(0)
					if src is BaseMaterial3D and src.albedo_texture:
						var img: Image = src.albedo_texture.get_image()
						if img.is_compressed():
							img.decompress()
						img.save_png(ProjectSettings.globalize_path(POLISH_DIR).path_join("%s_source_albedo.png" % UnitBase.UnitClass.find_key(cls).to_lower()))
	FileAccess.open(ProjectSettings.globalize_path(POLISH_DIR).path_join("transition_metrics.json"), FileAccess.WRITE).store_string(JSON.stringify(transitions, "\t"))
	await _material_pilots()
	await _check_transitions()
	await _versioned_materials()
	print("POLISH_CHECK: ", "PASS" if failures.is_empty() else JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _material_pilots() -> void:
	await _clear_canvas()
	_make_canvas()
	var mask := ImageTexture.create_from_image(Image.load_from_file(
		ProjectSettings.globalize_path(POLISH_DIR).path_join("lumen_emission_mask_candidate_v001.png")))
	var vail := [
		{"label": "Vail / original"},
		{"label": "Vail / body emission OFF", "material": {"roughness": 0.85, "emission_energy": 0.0}},
		{"label": "Vail / body emission 0.15", "material": {"roughness": 0.85, "emission_energy": 0.15}},
		{"label": "Vail / body emission 0.35", "material": {"roughness": 0.85, "emission_energy": 0.35}},
		{"label": "Vail / 0.15 + filmic", "material": {"roughness": 0.85, "emission_energy": 0.15}, "tonemap": Environment.TONE_MAPPER_FILMIC},
	]
	var lumen := [
		{"label": "Lumen / original"},
		{"label": "Lumen / armor roughness", "material": {"roughness": 0.55, "metallic": 0.45}},
		{"label": "Lumen / brighter armor", "material": {"roughness": 0.55, "albedo_tint": Color(1.25, 1.25, 1.25)}},
		{"label": "Lumen / selective emission 1.2", "material": {"roughness": 0.55, "metallic": 0.45, "emission_color": Color(0.60, 0.30, 1.0), "emission_energy": 1.2, "emission_texture": mask}},
		{"label": "Lumen / selective emission 2.0", "material": {"roughness": 0.55, "metallic": 0.45, "emission_color": Color(0.60, 0.30, 1.0), "emission_energy": 2.0, "emission_texture": mask}},
	]
	for row in 2:
		var variants: Array = vail if row == 0 else lumen
		var cls: int = UnitBase.UnitClass.VAIL if row == 0 else UnitBase.UnitClass.LUMEN
		for col in variants.size():
			var variant: Dictionary = variants[col]
			var style := {"render_resolution": 256, "render_height": 140.0,
				"toon": false, "nearest": false, "outline_with_pbr": true,
				"outline_px": 1.5, "outline_soft_edges": true, "msaa": Viewport.MSAA_4X,
				"pbr_material_overrides": {}}
			if variant.has("material"):
				style["pbr_material_overrides"] = {"Material_1": variant["material"]}
			Model3DSprite.debug_style_override = style
			var path: String = "res://assets/3d pipeline/hero/%s/%s_v001.glb" % [
				"vail" if row == 0 else "lumen", "vail" if row == 0 else "lumen"]
			var u := _spawn_version(cls, Vector2(350 + col * 300, 355 + row * 410), path)
			Model3DSprite.debug_style_override = {}
			for child in u.model3d._viewport.get_children():
				if child is DirectionalLight3D and variant.has("key"):
					child.light_energy = variant["key"]
				if child is WorldEnvironment:
					if variant.has("ambient"):
						child.environment.ambient_light_energy = variant["ambient"]
					if variant.has("tonemap"):
						child.environment.tonemap_mode = variant["tonemap"]
						child.environment.tonemap_white = 4.0
			_label(variant["label"], Vector2(230 + col * 300, 235 + row * 410), 20)
	await _save("vail_lumen_material_pilots.png", true)

func _spawn_version(cls: int, pos: Vector2, path: String) -> VisualUnit:
	var u := _spawn(cls, pos)
	u.model3d.queue_free()
	u.model3d = null
	_check(u._setup_model3d(path), "Versioned material model loads")
	u.soft_contact_shadow = true
	return u

func _check_transitions() -> void:
	await _clear_canvas()
	_make_canvas()
	var cases := {UnitBase.UnitClass.PASTOR: "ult", UnitBase.UnitClass.LORDEE: "ult",
		UnitBase.UnitClass.REED: "attack", UnitBase.UnitClass.SPORE: "ult", UnitBase.UnitClass.RIOT: "attack"}
	var report: Array = []
	for cls in cases:
		var jumps: Array[float] = []
		for variant in 2:
			var u := _spawn(cls, Vector2.ZERO)
			var m := u.model3d
			if variant == 0:
				m.clip_blend_by_clip = {}
			var clip: String = cases[cls]
			m.play(clip, false)
			m._anim.seek(m.animation_length(clip) * 0.99, true)
			m._anim.advance(0.0)
			m._anim.pause()
			var skel: Skeleton3D = m._find(m._model, "Skeleton3D")
			var before: Array[Vector3] = []
			for bone in skel.get_bone_count():
				before.append((skel.global_transform * skel.get_bone_global_pose(bone)).origin)
			m.play("idle")
			m._anim.advance(1.0 / 60.0)
			var distance := 0.0
			for bone in skel.get_bone_count():
				var pos: Vector3 = (skel.global_transform * skel.get_bone_global_pose(bone)).origin
				distance += pos.distance_squared_to(before[bone])
			jumps.append(sqrt(distance / skel.get_bone_count()) / m._model_height)
		_check(jumps[1] < jumps[0] * 0.95, "Return blend reduces %s pose jump" % UnitBase.UnitClass.find_key(cls))
		report.append({"hero": UnitBase.UnitClass.find_key(cls), "clip": cases[cls],
			"hard_cut_rms": jumps[0], "blended_rms": jumps[1]})
	FileAccess.open(ProjectSettings.globalize_path(POLISH_DIR).path_join("blend_continuity.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	var timed: Array[Model3DSprite] = []
	for cls in [UnitBase.UnitClass.DOC, UnitBase.UnitClass.PASTOR]:
		var u := _spawn(cls, Vector2.ZERO)
		_check(u.model3d.play_oneshot_timed("attack", 0.20), "Timed attack starts")
		timed.append(u.model3d)
	await get_tree().create_timer(0.35).timeout
	for m in timed:
		_check(not m.is_oneshot_playing() and m._current == "idle", "Timed attack resumes idle")
		_check(is_equal_approx(m._anim.speed_scale, 1.0), "Timed attack restores speed")
		_check(m.play_oneshot_timed("death", 0.15, ""), "Death hold starts")
	await get_tree().create_timer(0.30).timeout
	for m in timed:
		_check(m._current == "death" and not m.is_oneshot_playing(), "Death remains held")

func _versioned_materials() -> void:
	await _clear_canvas()
	_make_canvas()
	for col in 4:
		var hero: String = "vail" if col < 2 else "lumen"
		var cls: int = UnitBase.UnitClass.VAIL if col < 2 else UnitBase.UnitClass.LUMEN
		var version: int = 1 if col % 2 == 0 else 2
		_label("%s / %s" % [hero.capitalize(), "original" if version == 1 else "polished"], Vector2(290 + col * 350, 50), 24)
		for row in 2:
			Model3DSprite.debug_style_override = {"render_resolution": 256, "render_height": 140.0,
				"toon": false, "nearest": false, "outline_with_pbr": true, "outline_px": 1.5,
				"outline_soft_edges": true, "msaa": Viewport.MSAA_4X}
			var path := "res://assets/3d pipeline/hero/%s/%s_v00%d.glb" % [hero, hero, version]
			var u := _spawn_version(cls, Vector2(400 + col * 350, 320 + row * 430), path)
			Model3DSprite.debug_style_override = {}
			var m := u.model3d
			var clip: String = "idle" if row == 0 else "attack"
			m.play(clip)
			m._anim.seek(m.animation_length(clip) * 0.35, true)
			m._anim.pause()
			_label(clip, Vector2(340 + col * 350, 220 + row * 430), 20)
	var bg: BackgroundLayer = canvas.get_child(0)
	for round_number in [1, 11, 21, 31, 41, 51]:
		bg.set_biome_from_round(round_number)
		await _save("materials_biome_%02d.png" % round_number, false)

func _transition_metrics(m: Model3DSprite, hero: String) -> Dictionary:
	var out := {"hero": hero, "blend_seconds": m.clip_blend_sec,
		"blend_by_clip": m.clip_blend_by_clip.duplicate(), "clips": []}
	var skel: Skeleton3D = m._find(m._model, "Skeleton3D")
	if skel == null or not m.has_animation("idle"):
		return out
	m._anim.play(m._clip("idle"), 0.0)
	m._anim.seek(0.0, true)
	m._anim.advance(0.0)
	var idle: Array[Transform3D] = []
	for b in skel.get_bone_count():
		idle.append(skel.global_transform * skel.get_bone_global_pose(b))
	for name in ["walk", "attack", "skill", "ult"]:
		if not m.has_animation(name):
			continue
		m._anim.play(m._clip(name), 0.0)
		var clip: Animation = m._anim.get_animation(m._clip(name))
		var metrics: Dictionary = {"name": name}
		for key in ["start", "end"]:
			m._anim.seek(0.0 if key == "start" else maxf(0.0, clip.length - 0.001), true)
			m._anim.advance(0.0)
			var distance := 0.0
			for b in skel.get_bone_count():
				var pose: Transform3D = skel.global_transform * skel.get_bone_global_pose(b)
				distance += pose.origin.distance_squared_to(idle[b].origin)
			metrics[key + "_rms_fraction_height"] = sqrt(distance / skel.get_bone_count()) / m._model_height
		out["clips"].append(metrics)
	return out

func _save(name: String, freeze: bool) -> void:
	await get_tree().create_timer(0.6).timeout
	if freeze:
		for u in units:
			if u.model3d and u.model3d._anim:
				u.model3d._anim.seek(0.0, true)
				u.model3d._anim.pause()
	await RenderingServer.frame_post_draw
	board.get_texture().get_image().save_png(ProjectSettings.globalize_path(POLISH_DIR).path_join(name))
	print("POLISH_CHECK wrote ", name)

func _clear_canvas() -> void:
	canvas.queue_free()
	await get_tree().process_frame
	units.clear()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
