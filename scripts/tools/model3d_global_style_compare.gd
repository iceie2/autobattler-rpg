extends Node2D
## Four-way global 3D presentation benchmark on the real painted board.
## Production defaults are untouched: each row supplies a temporary setup-time
## override through Model3DSprite.debug_style_override.

const OUT := "user://_model3d_global_style_compare.png"
const HEROES := [
	UnitBase.UnitClass.BOUNCER,
	UnitBase.UnitClass.BLOODHOUND,
	UnitBase.UnitClass.HEADHUNTER,
	UnitBase.UnitClass.CROSS,
	UnitBase.UnitClass.STITCH,
	UnitBase.UnitClass.DOC,
	UnitBase.UnitClass.SHEILDOR,
]
const VARIANTS := [
	{
		"label": "1  BASELINE\n256 smooth · pitch 0° · outline 2px · 138px",
		"render_resolution": 256, "nearest": false, "camera_pitch_deg": 0.0,
		"outline_px": 2.0, "toon_bands": 2.0, "render_height": 138.0,
		"color_cluster_levels": 0.0,
	},
	{
		"label": "2  PIXELIZED\n128 nearest · pitch 0° · outline 3px · 115px",
		"render_resolution": 128, "nearest": true, "camera_pitch_deg": 0.0,
		"outline_px": 3.0, "toon_bands": 3.0, "render_height": 115.0,
		"color_cluster_levels": 0.0,
	},
	{
		"label": "3  LOW-PITCH PIXELIZED\n128 nearest · pitch 9° · outline 3px · 115px",
		"render_resolution": 128, "nearest": true, "camera_pitch_deg": 9.0,
		"outline_px": 3.0, "toon_bands": 3.0, "render_height": 115.0,
		"color_cluster_levels": 0.0,
	},
	{
		"label": "4  STRONG PIXEL\n96 nearest · pitch 9° · clustered colour · outline 3px",
		"render_resolution": 96, "nearest": true, "camera_pitch_deg": 9.0,
		"outline_px": 3.0, "toon_bands": 3.0, "render_height": 115.0,
		"color_cluster_levels": 6.0,
	},
]
const ROW_Y := [205, 445, 685, 925]
const FIRST_X := 220
const COL_STEP := 120

func _ready() -> void:
	get_window().size = Vector2i(1460, 1080)
	await get_tree().process_frame
	_add_backdrop()
	_add_headers()

	for row in VARIANTS.size():
		var style: Dictionary = VARIANTS[row]
		_label(style["label"], Vector2(10, ROW_Y[row] - 92), 17)
		for col in HEROES.size():
			Model3DSprite.debug_style_override = style.duplicate(true)
			var u: VisualUnit = UnitFactory.create_unit(HEROES[col], UnitBase.Element.NORMAL, true)
			u.position = Vector2(FIRST_X + col * COL_STEP, ROW_Y[row])
			u.can_be_dragged = false
			u.set_meta("anim_preview_lock", true)
			add_child(u)
			Model3DSprite.debug_style_override = {}
			if u.health_bar:
				u.health_bar.hide()
			if u.model3d:
				u.model3d.play("idle")

		# Two untouched 2D enemies anchor pixel density, outline and palette.
		var goblin := EnemyFactory.create_goblin(1)
		goblin.position = Vector2(1110, ROW_Y[row])
		goblin.can_be_dragged = false
		add_child(goblin)
		if goblin.health_bar:
			goblin.health_bar.hide()
		var archer := EnemyFactory.create_goblin_archer(1)
		archer.position = Vector2(1290, ROW_Y[row])
		archer.can_be_dragged = false
		add_child(archer)
		if archer.health_bar:
			archer.health_bar.hide()

	Model3DSprite.debug_style_override = {}
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote %s" % OUT)
	get_tree().quit(0)

func _add_backdrop() -> void:
	var bg := BackgroundLayer.new()
	bg.set_biome_from_round(1)
	bg.show_player_zone = false
	bg.show_enemy_zone = false
	bg.z_index = -20
	bg.position = Vector2(0, 40)
	add_child(bg)

func _add_headers() -> void:
	for col in HEROES.size():
		_label(UnitBase.UnitClass.find_key(HEROES[col]).capitalize(),
			Vector2(FIRST_X - 48 + col * COL_STEP, 50), 13)
	_label("2D references", Vector2(1055, 50), 16)

func _label(text: String, pos: Vector2, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.05))
	l.add_theme_constant_override("outline_size", 5)
	l.z_index = 20
	add_child(l)
