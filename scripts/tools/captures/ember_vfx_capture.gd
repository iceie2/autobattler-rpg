extends Node2D
const Paths = preload("res://scripts/tools/capture_paths.gd")
class ArrowPreview extends Node2D:
	func _draw() -> void:
		EmberVFX.draw_arrow(self, Vector2.RIGHT)

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(Paths.cli_round(1))
	for row in 5:
		var label := Label.new()
		label.text = EmberVFX.Mode.keys()[row]
		label.position = Vector2(20, 85 + row * 95)
		label.z_index = 30
		add_child(label)
		for col in 4:
			var fx := EmberVFX.new()
			add_child(fx)
			fx.setup(row as EmberVFX.Mode, Vector2(230 + col * 230, 110 + row * 95), null, 0.7, 78.0)
			fx.elapsed = 0.7 * (col + 0.5) / 4.0
			fx.set_process(false)
			fx.queue_redraw()
	for col in 4:
		var arrow := ArrowPreview.new()
		arrow.position = Vector2(230 + col * 230, 585)
		arrow.z_index = 20
		add_child(arrow)
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(Paths.out("ember_vfx_strip.png"))
	print("EMBER_STRIP PASS")
	get_tree().quit()
