extends Node2D
## Shading diagnostic on a FLAT background (2026-10-02).
##
## WHY FLAT, NOT THE BOARD. Every previous sweep put variants in different ROWS of
## the real board, so each unit stood on a different patch of grass. A pixel diff
## between rows then measured the grass, not the character -- ~4,000 of ~5,700
## pixels "changed" in every variant, including ones that changed nothing. Here
## every variant sits on the same mid-grey, in the same row, at the same size, so
## any pixel that differs between two columns differs because of the CHARACTER.
##
## The board look is judged separately. This scene answers one question: which
## of these actually changes what a dark material looks like?

const OUT := "user://_model3d_shading_diag.png"
const BG := Color(0.50, 0.50, 0.50)
const HEROES := [UnitBase.UnitClass.SEAR, UnitBase.UnitClass.SPORE, UnitBase.UnitClass.PASTOR]
const VARIANTS := [
	{"label": "LIVE", "rim_lift": 0.0, "spec": 0.0, "ssao": false},
	{"label": "SSAO", "rim_lift": 0.0, "spec": 0.0, "ssao": true},
	{"label": "RIM LIFT", "rim_lift": 1.0, "spec": 0.0, "ssao": false},
	{"label": "SPEC 0.35", "rim_lift": 0.0, "spec": 0.35, "ssao": false},
	{"label": "RIM + SPEC", "rim_lift": 1.0, "spec": 0.35, "ssao": false},
]
const X0 := 150
const DX := 170
const Y0 := 190
const DY := 210

func _ready() -> void:
	get_window().size = Vector2i(1060, 720)
	await get_tree().process_frame
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = Vector2(1060, 720)
	bg.z_index = -50
	add_child(bg)
	for c in VARIANTS.size():
		_label(VARIANTS[c]["label"], Vector2(X0 - 40 + c * DX, 24))
	for r in HEROES.size():
		_label(UnitBase.UnitClass.find_key(HEROES[r]).capitalize(), Vector2(8, Y0 + r * DY - 60))
		for c in VARIANTS.size():
			var v: Dictionary = VARIANTS[c].duplicate(true)
			v["render_height"] = 115.0
			Model3DSprite.debug_style_override = v
			var u: VisualUnit = UnitFactory.create_unit(HEROES[r], UnitBase.Element.NORMAL, true)
			u.position = Vector2(X0 + c * DX, Y0 + r * DY)
			u.can_be_dragged = false
			u.set_meta("anim_preview_lock", true)
			add_child(u)
			Model3DSprite.debug_style_override = {}
			if u.health_bar:
				u.health_bar.hide()
			if u.model3d:
				u.model3d.play("idle")
				# NOT set_paused(): that sets the viewport to UPDATE_DISABLED, and
				# called this early it can freeze a viewport that never rendered a
				# frame -- every column blank, which would read as "no difference".
	Model3DSprite.debug_style_override = {}
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT))
	print("wrote %s" % OUT)
	get_tree().quit(0)

func _label(t: String, p: Vector2) -> void:
	var l := Label.new()
	l.text = t
	l.position = p
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color.WHITE)
	add_child(l)
