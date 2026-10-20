extends Node
## Graphics audit 2026-10-02: controlled before/after variants on the real biome
## backdrops. Every variant changes ONLY its own runtime instances (extra light
## node, shader parameter, extra shadow node); no production defaults, imported
## materials or GLBs are touched. Same pose (idle t=0.5, paused), same scale,
## same camera for every row. Writes to graphics_audit_20261002/variants/.
##
## godot --path autobattler-rpg --windowed res://scenes/tools/graphics_audit_variants.tscn

const OUT_DIR := "res://../captures/renders/graphics_audit_20261002/variants"
const SUBJECTS := [UnitBase.UnitClass.RIFT, UnitBase.UnitClass.STATIC,
	UnitBase.UnitClass.BOUNCER, UnitBase.UnitClass.ZOLT, UnitBase.UnitClass.VAIL,
	UnitBase.UnitClass.LUMEN, UnitBase.UnitClass.PASTOR, UnitBase.UnitClass.SPORE,
	UnitBase.UnitClass.SEAR, UnitBase.UnitClass.NEMI]
const ROUNDS := [1, 11, 21, 31, 41, 51]
const VARIANTS := [
	{"name": "A  production baseline"},
	{"name": "B  + cool back/rim light", "rim": true},
	{"name": "C  + stronger contact shadow", "shadow": true},
	{"name": "D  + 2.0px outline", "outline": 2.0},
	{"name": "E  B+C, goblin on hero render", "rim": true, "shadow": true, "goblin_hero": true},
]
const VARIANTS_2 := [
	{"name": "A  production baseline"},
	{"name": "B  material rim 0.5", "mat_rim": 0.5},
	{"name": "C  material rim 1.0", "mat_rim": 1.0},
	{"name": "D  ambient 0.85 -> 1.25", "ambient": 1.25},
	{"name": "E  rim 0.5 + 2px outline + shadow", "mat_rim": 0.5, "outline": 2.0, "shadow": true},
]
const SUBJECTS_3 := [UnitBase.UnitClass.RIFT, UnitBase.UnitClass.STATIC,
	UnitBase.UnitClass.BOUNCER, UnitBase.UnitClass.ZOLT, UnitBase.UnitClass.VAIL,
	UnitBase.UnitClass.LUMEN, UnitBase.UnitClass.RIOT, UnitBase.UnitClass.JUNE,
	UnitBase.UnitClass.DOC, UnitBase.UnitClass.LORDEE]
# Meshy bodies import metallic=1.0 with no metallic texture (glTF default).
const VARIANTS_3 := [
	{"name": "A  production (metallic 1.0)"},
	{"name": "B  metallic 0, roughness kept", "metal": 0.0},
	{"name": "C  metallic 0, roughness 0.75", "metal": 0.0, "rough": 0.75},
	{"name": "D  metallic 0.3, roughness 0.6", "metal": 0.3, "rough": 0.6},
	{"name": "E  C + goblin on hero render", "metal": 0.0, "rough": 0.75, "goblin_hero": true},
]
# Set 4 (2026-10-05): Rush fur/material candidates via the debug override.
const VARIANTS_4 := [
	{"name": "A  original (metallic 1.0)", "dbg_pbr": {"Material_1": {"metallic": 1.0, "roughness": 0.41}}},
	{"name": "B  metal 0.3 / rough 0.6", "dbg_pbr": {"Material_1": {"metallic": 0.3, "roughness": 0.6}}},
	{"name": "C  matte 0 / 0.75 (current)", "dbg_pbr": {"Material_1": {"metallic": 0.0, "roughness": 0.75}}},
	{"name": "D  matte + warm tint", "dbg_pbr": {"Material_1": {"metallic": 0.0, "roughness": 0.75, "albedo_tint": Color(0.92, 0.80, 0.62)}}},
	{"name": "E  metal 0.5 / rough 0.5", "dbg_pbr": {"Material_1": {"metallic": 0.5, "roughness": 0.5}}},
]
var subjects: Array = SUBJECTS
var variants: Array = VARIANTS
var set_tag := ""

const COL_X0 := 230.0
const COL_DX := 140.0
const ROW_Y0 := 175.0
const ROW_DY := 196.0

var board: SubViewport
var canvas: Node2D
var units: Array = []          # [VisualUnit, row, col]
var stats: Dictionary = {}

func _ready() -> void:
	Model3DSprite.debug_style_override = {}
	board = SubViewport.new()
	board.size = Vector2i(1920, 1080)
	board.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(board)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for a in OS.get_cmdline_user_args():
		if a == "--set=2":
			variants = VARIANTS_2
			set_tag = "set2_"
		if a.begins_with("--prefix="):
			set_tag = a.substr(9) + set_tag
		if a == "--set=4":
			variants = VARIANTS_4
			subjects = [UnitBase.UnitClass.RUSH, UnitBase.UnitClass.RUSH, UnitBase.UnitClass.RUSH]
			set_tag = "set4_"
		if a == "--set=3":
			variants = VARIANTS_3
			subjects = SUBJECTS_3
			set_tag = "set3_"
	for rnd in ROUNDS:
		await _render_round(rnd)
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR).path_join(set_tag + "variant_stats.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(stats, "  "))
	f.close()
	print("VARIANTS_DONE")
	get_tree().quit()

func _render_round(rnd: int) -> void:
	units.clear()
	canvas = Node2D.new()
	board.add_child(canvas)
	var bg := BackgroundLayer.new()
	bg.set_biome_from_round(rnd)
	bg.show_player_zone = false
	bg.show_enemy_zone = false
	bg.z_index = -20
	bg.position = Vector2(0, 20)
	bg.scale.x = 1.85
	canvas.add_child(bg)
	for col in subjects.size():
		_label(UnitBase.UnitClass.find_key(subjects[col]).capitalize(),
			Vector2(COL_X0 + col * COL_DX - 50, 40), 20)
	_label("Goblin", Vector2(COL_X0 + subjects.size() * COL_DX - 50, 40), 20)
	for row in variants.size():
		var v: Dictionary = variants[row]
		var y := ROW_Y0 + row * ROW_DY
		_label(v["name"], Vector2(10, y - 150), 18)
		for col in subjects.size():
			_place(subjects[col], v, row, col, Vector2(COL_X0 + col * COL_DX, y))
		_place_goblin(v, row, Vector2(COL_X0 + subjects.size() * COL_DX, y))
	await get_tree().create_timer(1.5).timeout
	for e in units:
		var u: VisualUnit = e[0]
		if u.model3d and u.model3d._anim:
			u.model3d.play("idle")
			u.model3d._anim.seek(0.5, true)
			u.model3d._anim.pause()
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := board.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR).path_join("%svariants_r%d.png" % [set_tag, rnd]))
	_measure(rnd, img)
	print("VARIANTS wrote round ", rnd)
	canvas.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _place(cls: int, v: Dictionary, row: int, col: int, pos: Vector2) -> void:
	var u: VisualUnit = UnitFactory.create_unit(cls, UnitBase.Element.NORMAL, true)
	if v.has("dbg_pbr"):
		# render_resolution must be restated: setup() falls back to the 128px class
		# constant, not the hero's 256, whenever any override is present.
		Model3DSprite.debug_style_override = {"pbr_material_overrides": v["dbg_pbr"], "render_resolution": 256}
	_finish(u, v, row, col, pos)
	Model3DSprite.debug_style_override = {}

func _place_goblin(v: Dictionary, row: int, pos: Vector2) -> void:
	if v.get("goblin_hero", false):
		# The hero block of VisualUnit._setup_model3d, applied to the goblin only.
		Model3DSprite.debug_style_override = {"render_resolution": 256, "nearest": false,
			"msaa": Viewport.MSAA_4X, "outline_px": 1.5, "outline_soft_edges": true,
			"toon": false, "outline_with_pbr": true}
	var u: VisualUnit = EnemyFactory.create_goblin(4)
	# Model3DSprite.setup() runs when the unit enters the tree, so the override
	# has to stay set until after _finish() adds it.
	_finish(u, v, row, subjects.size(), pos)
	Model3DSprite.debug_style_override = {}
	if v.get("goblin_hero", false):
		u.soft_contact_shadow = true

func _finish(u: VisualUnit, v: Dictionary, row: int, col: int, pos: Vector2) -> void:
	u.position = pos
	u.can_be_dragged = false
	u.set_meta("anim_preview_lock", true)
	canvas.add_child(u)
	if u.health_bar:
		u.health_bar.hide()
	units.append([u, row, col])
	var m: Model3DSprite = u.model3d
	if m and v.get("rim", false):
		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-20.0, 160.0, 0.0)   # behind, slightly above
		rim.light_color = Color(0.78, 0.84, 1.0)
		rim.light_energy = 1.3
		rim.shadow_enabled = false
		m._viewport.add_child(rim)
	if m and v.has("metal") and (u.model3d and (not u.model3d.toon)):
		for node in m._walk(m._model):
			if node is MeshInstance3D:
				for si in node.mesh.get_surface_count():
					var cur: Material = node.get_active_material(si)
					if cur is BaseMaterial3D and cur.metallic >= 0.99 and cur.metallic_texture == null:
						var dm: BaseMaterial3D = cur.duplicate()
						dm.metallic = float(v["metal"])
						if v.has("rough"):
							dm.roughness = float(v["rough"])
						node.set_surface_override_material(si, dm)
	if m and v.has("mat_rim"):
		for node in m._walk(m._model):
			if node is MeshInstance3D:
				for si in node.mesh.get_surface_count():
					var active: Material = node.get_active_material(si)
					if active is BaseMaterial3D:
						var dup: BaseMaterial3D = active.duplicate()
						dup.rim_enabled = true
						dup.rim = float(v["mat_rim"])
						dup.rim_tint = 0.5
						node.set_surface_override_material(si, dup)
	if m and v.has("ambient"):
		for child in m._viewport.get_children():
			if child is WorldEnvironment:
				var env: Environment = child.environment.duplicate()
				env.ambient_light_energy = float(v["ambient"])
				child.environment = env
	if m and v.has("outline"):
		var mat: ShaderMaterial = m._sprite.material
		mat.set_shader_parameter("thickness",
			float(mat.get_shader_parameter("thickness")) * float(v["outline"]) / m.outline_px)
	if v.get("shadow", false):
		var extra := ExtraShadow.new()
		extra.unit = u
		extra.z_index = -1
		u.add_child(extra)

## Simulates raising the contact shadow 0.32 -> ~0.5 with a tighter core: drawn
## on top of the production shadow, same ellipse, same foot line.
class ExtraShadow extends Node2D:
	var unit: VisualUnit
	var tex: GradientTexture2D
	func _ready() -> void:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0)])
		tex = GradientTexture2D.new()
		tex.gradient = g
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var w: float = 34.0 * unit.cell_size * unit._depth_scale * 0.7
		var h: float = w * 0.34
		draw_set_transform(Vector2(0, unit._foot_anchor_y), 0.0, Vector2(1.0, h / w))
		draw_texture_rect(tex, Rect2(Vector2(-w, -w), Vector2(w * 2, w * 2)), false, Color(1, 1, 1, 0.30))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Figure-pixel stats from each unit's own viewport (A vs B is the rim test),
## plus local board contrast for the composited cell.
func _measure(rnd: int, img: Image) -> void:
	var out: Dictionary = {}
	for e in units:
		var u: VisualUnit = e[0]
		if not u.model3d:
			continue
		var vimg := u.model3d._viewport.get_texture().get_image()
		var n := 0
		var sum := 0.0
		var sum2 := 0.0
		var edge := 0
		for y in vimg.get_height():
			for x in vimg.get_width():
				var c := vimg.get_pixel(x, y)
				if c.a > 0.5:
					var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
					n += 1
					sum += l
					sum2 += l * l
				elif c.a > 0.02:
					edge += 1
		if n == 0:
			continue
		var mean := sum / n
		var key := "%s_%s" % [UnitBase.UnitClass.find_key(u.unit_class), str(e[1])]
		out[key] = {"luma_mean": snappedf(mean, 0.001),
			"luma_std": snappedf(sqrt(maxf(sum2 / n - mean * mean, 0.0)), 0.001),
			"partial_alpha_px": edge}
	stats["r%d" % rnd] = out

func _label(value: String, pos: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	canvas.add_child(label)
