extends Node2D
## 3D presentation comparison for Rift, Static, Bouncer, and Zolt on the real
## board, beside untouched 2D enemies. Row 1 recreates the legacy toon look;
## the other rows compare native PBR and screen-space outline weights.
## Overrides are cleared after each unit is constructed.

const OUT := "user://_model3d_pbr_outline_roster.png"
const HEROES := [
	UnitBase.UnitClass.RIFT,
	UnitBase.UnitClass.STATIC,
	UnitBase.UnitClass.BOUNCER,
	UnitBase.UnitClass.ZOLT,
]
const VARIANTS := [
	{"label": "1  LEGACY toon · 128 nearest",
	 "render_height": 115.0, "toon": true, "outline_with_pbr": false,
	 "outline_px": 2.5, "render_resolution": 128, "nearest": true},
	{"label": "2  PBR SMOOTH · no outline · 115px",
	 "render_height": 115.0, "toon": false, "render_resolution": 256, "nearest": false},
	{"label": "3  PBR SMOOTH + outline 2.5 · 115px",
	 "render_height": 115.0, "toon": false, "outline_with_pbr": true,
	 "render_resolution": 256, "nearest": false},
	{"label": "4  PBR SMOOTH + outline 2.5 · 140px",
	 "render_height": 140.0, "toon": false, "outline_with_pbr": true,
	 "render_resolution": 256, "nearest": false},
	{"label": "5  PBR SMOOTH + outline 1.5 · 140px",
	 "render_height": 140.0, "toon": false, "outline_with_pbr": true,
	 "outline_px": 1.5, "render_resolution": 256, "nearest": false},
]
const ROW_Y := [185, 365, 545, 725, 905]
const FIRST_X := 260
const COL_STEP := 230

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	_add_backdrop()
	_add_headers()

	for row in VARIANTS.size():
		var style: Dictionary = VARIANTS[row]
		_label(style["label"], Vector2(8, ROW_Y[row] - 68), 18)
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
		# Untouched 2D enemies anchor pixel density, outline weight and palette.
		var goblin := EnemyFactory.create_goblin(1)
		goblin.position = Vector2(FIRST_X + HEROES.size() * COL_STEP, ROW_Y[row])
		goblin.can_be_dragged = false
		add_child(goblin)
		if goblin.health_bar:
			goblin.health_bar.hide()
		var archer := EnemyFactory.create_goblin_archer(1)
		archer.position = Vector2(FIRST_X + (HEROES.size() + 1) * COL_STEP, ROW_Y[row])
		archer.can_be_dragged = false
		add_child(archer)
		if archer.health_bar:
			archer.health_bar.hide()

	Model3DSprite.debug_style_override = {}
	await get_tree().create_timer(1.8).timeout
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
	bg.position = Vector2(0, 20)
	bg.scale.x = 1.85
	add_child(bg)

func _add_headers() -> void:
	for col in HEROES.size():
		_label(UnitBase.UnitClass.find_key(HEROES[col]).capitalize(),
			Vector2(FIRST_X - 40 + col * COL_STEP, 44), 18)
	_label("2D anchors", Vector2(FIRST_X + HEROES.size() * COL_STEP - 10, 44), 18)

func _label(text: String, pos: Vector2, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	add_child(l)
