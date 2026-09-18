extends Node2D
## Side-by-side of render-style options for the 3D characters, over a real
## painted biome backdrop with 2D heroes for reference.
##
##   GODOT --path . res://scenes/tools/model3d_style_sweep.tscn
##   → user://_model3d_style.png
##
## Exists because "it looks off" is not actionable and neither is my opinion
## about why. Each column changes ONE thing, on the same backdrop, at the same
## size, next to the same 2D heroes.

const OUT := "user://_model3d_style.png"

# label, camera pitch, base yaw, toon, outline_scale
# Rendered at the REAL board height. An outline that reads fine on a 230px
# preview can vanish completely at the 118px a unit actually occupies, which is
# exactly what happened to the first cel pass.
const VARIANTS := [
	["PBR\nno outline", 0.0, 0.0, false, 0.0],
	["CEL\n1px outline", 0.0, 0.0, true, 1.0],
	["CEL\n2px outline", 0.0, 0.0, true, 2.0],
	["CEL\n3px outline", 0.0, 0.0, true, 3.0],
]
const COL_W := 360
const CHAR_H := 118.0
const BASE_Y := 620

func _ready() -> void:
	# Full 1920x1080: the project stretches canvas_items from that design size,
	# so a smaller window would just shrink everything and hide the detail.
	get_window().size = Vector2i(1920, 1080)
	await get_tree().process_frame

	_add_backdrop()

	for i in VARIANTS.size():
		var v: Array = VARIANTS[i]
		var x := COL_W / 2 + i * COL_W
		var m := Model3DSprite.new()
		m.camera_pitch_deg = v[1]
		m.base_yaw_deg = v[2]
		m.toon = v[3]
		m.outline_px = v[4]
		m.position = Vector2(x, BASE_Y)
		add_child(m)
		if not m.setup("res://assets/3d pipeline/hero/bouncer/bouncer.glb", CHAR_H):
			push_error("setup failed for variant %s" % v[0])
			continue
		m.get_sprite().position = Vector2(0, -CHAR_H * 0.5)
		m.play("idle")
		_label(str(v[0]), Vector2(x - COL_W / 2 + 16, BASE_Y + 60))

	# Reference column: the 2D roster this has to sit beside.
	var ref_x := COL_W / 2 + VARIANTS.size() * COL_W
	var refs := [UnitBase.UnitClass.NEMI, UnitBase.UnitClass.SABLE]
	for i in refs.size():
		var u: VisualUnit = UnitFactory.create_unit(refs[i], UnitBase.Element.NORMAL, true)
		u.position = Vector2(ref_x - 70 + i * 140, BASE_Y)
		u.can_be_dragged = false
		add_child(u)
		# Blow the 2D art up to the same on-screen height as the models, or the
		# comparison flatters whichever happens to be drawn bigger.
		var s2d: Node2D = u.animated_sprite if u.animated_sprite else u.plain_sprite
		if s2d:
			pass
	_label("2D roster\n(reference)", Vector2(ref_x - COL_W / 2 + 10, 330))

	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote %s" % OUT)
	get_tree().quit(0)

## The REAL board ground, not a stand-in. Judging "does this character sit in
## the scene" against a flat colour would answer the wrong question.
func _add_backdrop() -> void:
	var bg := BackgroundLayer.new()
	bg.set_biome_from_round(1)
	bg.show_player_zone = false
	bg.show_enemy_zone = false
	bg.z_index = -10
	bg.position = Vector2(0, 120)
	add_child(bg)

func _label(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
