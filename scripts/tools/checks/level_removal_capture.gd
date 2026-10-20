extends Node2D

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Renders the REMOVE N LEVEL merge menu in its states over the real board (the
# menu sits over the game, so it is judged over the game): default, hovered,
# selected for removal, and a two-level menu with six rows to stress wrapping
# and scrolling. One sheet per run.
# Runs WINDOWED (--headless renders empty PNGs).
# Run: godot --path . res://scenes/tools/level_removal_capture.tscn
var OUT: String = CapturePaths.out("level_removal_menu.png")

func _ready() -> void:
	get_window().size = Vector2i(1500, 950)
	RenderingServer.set_default_clear_color(Color(0.12, 0.13, 0.10))
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(1)
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := LevelRemovalPanel.new()
	layer.add_child(panel)
	await get_tree().process_frame

	var shots: Array[Image] = []
	var pool := {"recovery": 1, "aftercast_ward": 1, "sustained_assault": 1, "equilibrium": 1}

	panel.open(pool, 1)
	await _settle()
	shots.append(_grab(panel))                                   # 1 default

	var hov := panel.row_node("sustained_assault")
	hov.hovered = true
	hov.restyle()
	await _settle()
	shots.append(_grab(panel))                                   # 2 hovered
	hov.hovered = false
	hov.restyle()

	panel.row_button("aftercast_ward").pressed.emit()
	await get_tree().create_timer(0.5).timeout
	await _settle()
	shots.append(_grab(panel))                                   # 3 selected

	panel.open({"thorns": 2, "lifesteal": 1, "spell_echo": 1, "mana_shield": 1,
		"arcane_conduit": 1, "critical_focus": 1}, 2)
	await _settle()
	panel.row_button("thorns").pressed.emit()
	panel.row_button("thorns").pressed.emit()
	await get_tree().create_timer(0.5).timeout
	await _settle()
	shots.append(_grab(panel))                                   # 4 stress: 2 levels, 6 rows

	var pad := 16
	var w := 0
	var h := 0
	for s in shots:
		w += s.get_width() + pad
		h = maxi(h, s.get_height())
	var sheet := Image.create(w + pad, h + pad * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	var x := pad
	for s in shots:
		sheet.blit_rect(s, Rect2i(Vector2i.ZERO, s.get_size()), Vector2i(x, pad))
		x += s.get_width() + pad
	var err := sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("LEVEL_REMOVAL_CAPTURE: %s -> %s  (%d frames, dialog %s)" % ["saved" if err == OK else "SAVE FAILED", OUT, shots.size(), str(shots[0].get_size())])
	get_tree().quit(0)

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _grab(panel: LevelRemovalPanel) -> Image:
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	# dialog_rect() is in canvas (design) units; the image is in window pixels.
	var k: Vector2 = Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var r := panel.dialog_rect().grow(6)
	var px := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k))
	return img.get_region(px.intersection(Rect2i(Vector2i.ZERO, img.get_size())))
