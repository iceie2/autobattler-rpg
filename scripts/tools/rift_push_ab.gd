extends Node

# Side-by-side of Rift's attack before/after the authored right-hand push, at a
# resolution where the arm is actually judgeable. The board renders him 115px
# tall, where a shoulder rotation is a handful of pixels — a strip at that size
# cannot answer "does the free hand cast now", which is the whole question.
const OUT := "user://_rift_push_ab.png"
const ROWS := {
	"v013 (native Meshy: left-hand staff thrust)": "res://assets/3d pipeline/hero/rift/rift_v013.glb",
	"v014 (authored right-hand push)": "res://assets/3d pipeline/hero/rift/rift_v014.glb",
}
# Sampled across the cast: anticipation -> drive -> RELEASE (0.34) -> follow.
const TIMES := [0.17, 0.25, 0.30, 0.34, 0.40, 0.50]
const CELL := 420

func _ready() -> void:
	var sheet := Image.create(CELL * TIMES.size(), CELL * ROWS.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.18, 0.18, 0.20, 1.0))
	var row := 0
	for label in ROWS:
		var model := Model3DSprite.new()
		model.weapon_default_node = "Staff_Held"
		model.debug_style_override = {"render_resolution": CELL}
		add_child(model)
		if not model.setup(ROWS[label], 115.0):
			push_error("setup failed: %s" % ROWS[label])
			get_tree().quit(1)
			return
		model.get_sprite().position = Vector2(-9000, 0)
		model.play("attack")
		var length := model.animation_length("attack")
		for col in TIMES.size():
			model._anim.seek(length * float(TIMES[col]), true)
			model._anim.advance(0.0)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var frame := model._viewport.get_texture().get_image()
			frame.convert(Image.FORMAT_RGBA8)
			sheet.blend_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()),
				Vector2i(col * CELL, row * CELL))
		print("row %d: %s  length=%.2f" % [row, label, length])
		model.queue_free()
		row += 1
	sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	get_tree().quit(0)
