extends Node2D

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# A/B filmstrip for the Hill Giant attack size pop (2026-09-17).
# TOP row    — the OLD behaviour, reproduced by forcing _anim_scale_mult back to
#              what the frame-0 / 3-column scan produced (attack 1.675).
# BOTTOM row — the current build.
# Same unit, same frames, same everything else, so the only difference on screen
# is the correction itself.
#
# Runs WINDOWED (--headless renders nothing).
# Run: godot --path . res://scenes/tools/hill_giant_scale_ab.tscn

const FRAMES := 6
const CELL := Vector2i(230, 250)
const OLD_MULT := {"attack": 1.675, "walk_south": 1.182, "walk_north": 1.182,
	"walk_east": 1.182, "walk_west": 1.182, "idle_south": 1.0}

func _ready() -> void:
	get_window().size = Vector2i(CELL.x * FRAMES, CELL.y * 2 + 40)
	RenderingServer.set_default_clear_color(Color(0.11, 0.10, 0.08))
	for i in range(4): await get_tree().process_frame

	var strip := Image.create(CELL.x * FRAMES, CELL.y * 2, false, Image.FORMAT_RGBA8)
	for row in range(2):
		var used_old: bool = row == 0
		for f in range(FRAMES):
			var img := await _shot(f, used_old)
			strip.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * f, CELL.y * row))

	var path := CapturePaths.out("hill_giant_scale_ab.png")
	assert(strip.save_png(ProjectSettings.globalize_path(path)) == OK)
	print("HILL_GIANT_SCALE_AB: ALL PASS (top = old frame-0 scan, bottom = current)")
	get_tree().quit(0)

func _shot(frame_i: int, old: bool) -> Image:
	for c in get_children(): c.free()
	var g := EnemyFactory.create_hill_giant()
	g.position = Vector2(CELL.x * 0.5, CELL.y - 30) / _content_scale()
	add_child(g)
	for i in range(3): await get_tree().process_frame
	if g.health_bar: g.health_bar.hide()
	if old:
		for k in OLD_MULT.keys():
			if g._anim_scale_mult.has(k):
				g._anim_scale_mult[k] = OLD_MULT[k]
	var spr: AnimatedSprite2D = g.animated_sprite
	if spr and spr.sprite_frames.has_animation("attack"):
		spr.play("attack")
		spr.pause()
		spr.frame = mini(frame_i, spr.sprite_frames.get_frame_count("attack") - 1)
	for i in range(2): await get_tree().process_frame
	g._apply_animation()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var r := Rect2i(Vector2i.ZERO, Vector2i(
		mini(CELL.x, img.get_width()), mini(CELL.y, img.get_height())))
	return img.get_region(r)

# The project applies a content scale; positions given in viewport px must be
# divided back out (measured the same way as the knock-up filmstrip).
func _content_scale() -> float:
	var vp := get_viewport().get_visible_rect().size
	return vp.x / maxf(float(get_window().size.x), 1.0)
