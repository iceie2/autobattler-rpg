extends Node
## Read-only asset audit and isolated render experiments. No production defaults
## or imported materials are edited; variants affect only their own instances.

const OUT_DIR := "res://../captures/renders/quality_audit_20261002"
const SUBJECTS := [UnitBase.UnitClass.RIFT, UnitBase.UnitClass.STATIC,
	UnitBase.UnitClass.BOUNCER, UnitBase.UnitClass.ZOLT,
	UnitBase.UnitClass.PASTOR, UnitBase.UnitClass.DOC]
const VARIANTS := [
	{"name": "CURRENT PBR", "msaa": 0},
	{"name": "4x MSAA / current outline", "msaa": 2},
	{"name": "4x MSAA / soft edge outline", "msaa": 2, "soft": true},
	{"name": "Soft outline / directional fill", "msaa": 2, "soft": true, "lighting": true},
	{"name": "Soft outline / self shadow", "msaa": 2, "soft": true, "shadow": true},
]
const SOFT_OUTLINE := """
shader_type canvas_item;
uniform float thickness = 2.0;
uniform vec4 line_color : source_color = vec4(0.09, 0.07, 0.12, 1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * thickness;
	float a = 0.0;
	a = max(a, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	a = max(a, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	a = max(a, texture(TEXTURE, UV + px * 0.707).a);
	a = max(a, texture(TEXTURE, UV - px * 0.707).a);
	a = max(a, texture(TEXTURE, UV + vec2(px.x, -px.y) * 0.707).a);
	a = max(a, texture(TEXTURE, UV + vec2(-px.x, px.y) * 0.707).a);
	float border = smoothstep(0.05, 0.95, a) * line_color.a;
	float alpha = c.a + (1.0 - c.a) * border;
	vec3 rgb = (c.rgb * c.a + line_color.rgb * (1.0 - c.a) * border) / max(alpha, 0.0001);
	COLOR = vec4(rgb, alpha);
}
"""

var board: SubViewport
var canvas: Node2D
var units: Array[VisualUnit] = []
var audit: Dictionary = {"heroes": [], "variants": VARIANTS}

func _ready() -> void:
	Model3DSprite.debug_style_override = {}
	board = SubViewport.new()
	board.size = Vector2i(1920, 1080)
	board.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(board)
	_make_canvas()
	var roster: Array = VisualUnit.HERO_MODEL_PATHS.keys()
	roster.append(UnitBase.UnitClass.NEMI)
	for i in roster.size():
		var cls: int = roster[i]
		var pos := Vector2(350 + (i % 5) * 300, 190 + (i / 5) * 240)
		var u := _spawn(cls, pos)
		_label(UnitBase.UnitClass.find_key(cls).capitalize(), pos + Vector2(-80, -95), 22)
		if u.model3d:
			audit["heroes"].append(_inventory(u))
		else:
			audit["heroes"].append({"hero": UnitBase.UnitClass.find_key(cls), "renderer": "2D"})
	await _capture("roster_current.png")
	canvas.queue_free()
	await get_tree().process_frame
	units.clear()
	_make_canvas()
	for col in SUBJECTS.size():
		_label(UnitBase.UnitClass.find_key(SUBJECTS[col]).capitalize(), Vector2(310 + col * 230, 40), 22)
	_label("2D anchor", Vector2(1650, 40), 22)
	for row in VARIANTS.size():
		var variant: Dictionary = VARIANTS[row]
		_label(variant["name"], Vector2(12, 115 + row * 180), 20)
		for col in SUBJECTS.size():
			var u := _spawn(SUBJECTS[col], Vector2(360 + col * 230, 190 + row * 180))
			_apply_variant(u.model3d, variant)
		var anchor := EnemyFactory.create_goblin(1)
		anchor.position = Vector2(1740, 190 + row * 180)
		canvas.add_child(anchor)
		anchor.can_be_dragged = false
		if anchor.health_bar:
			anchor.health_bar.hide()
	await _capture("render_experiments.png")
	var path := ProjectSettings.globalize_path(OUT_DIR).path_join("material_inventory.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(audit, "\t"))
	print("QUALITY_AUDIT wrote ", path)
	get_tree().quit()

func _make_canvas() -> void:
	canvas = Node2D.new()
	board.add_child(canvas)
	var bg := BackgroundLayer.new()
	bg.set_biome_from_round(1)
	bg.show_player_zone = false
	bg.show_enemy_zone = false
	bg.z_index = -20
	bg.position = Vector2(0, 20)
	bg.scale.x = 1.85
	canvas.add_child(bg)

func _spawn(cls: int, pos: Vector2) -> VisualUnit:
	var u: VisualUnit = UnitFactory.create_unit(cls, UnitBase.Element.NORMAL, true)
	u.position = pos
	u.can_be_dragged = false
	u.set_meta("anim_preview_lock", true)
	canvas.add_child(u)
	if u.health_bar:
		u.health_bar.hide()
	units.append(u)
	return u

func _apply_variant(m: Model3DSprite, variant: Dictionary) -> void:
	m._viewport.msaa_3d = variant["msaa"]
	if variant.get("soft", false):
		var previous: ShaderMaterial = m._sprite.material
		var mat := ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = SOFT_OUTLINE
		mat.set_shader_parameter("thickness", previous.get_shader_parameter("thickness"))
		mat.set_shader_parameter("line_color", m.outline_color)
		m._sprite.material = mat
	for child in m._viewport.get_children():
		if child is DirectionalLight3D:
			child.shadow_enabled = variant.get("shadow", false)
			if variant.get("lighting", false):
				child.light_energy = 1.65
		if child is WorldEnvironment and variant.get("lighting", false):
			child.environment.ambient_light_energy = 0.55
			child.environment.ambient_light_color = Color(0.78, 0.80, 0.86)
	if variant.get("lighting", false):
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-15, 140, 0)
		fill.light_energy = 0.35
		m._viewport.add_child(fill)

func _inventory(u: VisualUnit) -> Dictionary:
	var m := u.model3d
	var out := {"hero": UnitBase.UnitClass.find_key(u.unit_class), "renderer": "PBR",
		"viewport": [m.render_size.x, m.render_size.y], "msaa": m._viewport.msaa_3d,
		"glow_material": m.glow_material, "registered_glow_materials": m._glow_mats.size() + m._pbr_glow_mats.size(),
		"glow_clips": m.glow_by_clip.keys(), "blend_seconds": m.clip_blend_sec,
		"surfaces": [], "triangles": 0}
	for node in m._walk(m._model):
		if not node is MeshInstance3D:
			continue
		var mi: MeshInstance3D = node
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var count: int = arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size()
			out["triangles"] += count / 3
			var src := mi.mesh.surface_get_material(s)
			if src is BaseMaterial3D:
				out["surfaces"].append({"name": src.resource_name, "roughness": src.roughness,
					"metallic": src.metallic, "albedo_texture": src.albedo_texture != null,
					"normal_enabled": src.normal_enabled, "normal_texture": src.normal_texture != null,
					"roughness_texture": src.roughness_texture != null,
					"ao_enabled": src.ao_enabled, "ao_texture": src.ao_texture != null,
					"emission_enabled": src.emission_enabled,
					"emission_color": [src.emission.r, src.emission.g, src.emission.b],
					"emission_texture": src.emission_texture != null,
					"albedo_color": [src.albedo_color.r, src.albedo_color.g, src.albedo_color.b],
					"emission_energy": src.emission_energy_multiplier,
					"filter": src.texture_filter})
	return out

func _capture(name: String) -> void:
	await get_tree().create_timer(1.8).timeout
	for u in units:
		if u.model3d and u.model3d._anim:
			u.model3d._anim.seek(0.0, true)
			u.model3d._anim.pause()
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	board.get_texture().get_image().save_png(dir.path_join(name))
	if name == "render_experiments.png":
		for row in VARIANTS.size():
			units[row * SUBJECTS.size()].model3d._viewport.get_texture().get_image().save_png(
				dir.path_join("rift_viewport_%d.png" % row))
	print("QUALITY_AUDIT wrote ", name)

func _label(value: String, pos: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	canvas.add_child(label)
