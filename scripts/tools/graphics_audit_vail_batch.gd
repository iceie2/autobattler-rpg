extends Node
## Graphics audit 2026-10-02: isolated benchmark of VailVFX AURA_PULSE.
## A: production VailVFX (one draw_colored_polygon per triangle).
## B: test-only subclass that submits each ribbon layer as ONE triangle array.
## Same seeds, same elapsed time, same positions; writes both frames and a
## pixel diff. Production vail_vfx.gd is not modified.
##
## godot --path autobattler-rpg --windowed res://scenes/tools/graphics_audit_vail_batch.tscn

const OUT_DIR := "res://../captures/renders/graphics_audit_20261002/vail_batch"
const COUNT := 33        # live AURA_PULSE nodes measured in the 15-hero battle
const FRAMES := 240

class BatchedVail extends VailVFX:
	func _poly(edges: Array, col: Color) -> void:
		if edges.size() != 2:
			return
		var top: PackedVector2Array = edges[0]
		var bot: PackedVector2Array = edges[1]
		var pts := PackedVector2Array()
		for i in range(top.size() - 1):
			for tri in [[top[i], top[i + 1], bot[i + 1]], [top[i], bot[i + 1], bot[i]]]:
				if absf((tri[1] - tri[0]).cross(tri[2] - tri[0])) < 0.01:
					continue
				pts.append(tri[0]); pts.append(tri[1]); pts.append(tri[2])
		if pts.is_empty():
			return
		var cols := PackedColorArray()
		cols.resize(pts.size())
		cols.fill(col)
		var idx := PackedInt32Array()
		idx.resize(pts.size())
		for i in pts.size():
			idx[i] = i
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)

var board: SubViewport
var results: Dictionary = {}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	board = SubViewport.new()
	board.size = Vector2i(1280, 720)
	board.transparent_bg = false
	board.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(board)
	var bg := ColorRect.new()
	bg.color = Color(0.32, 0.45, 0.25)
	bg.size = Vector2(1280, 720)
	board.add_child(bg)
	for variant in ["A_production", "B_batched", "A_production_2", "B_batched_2"]:
		await _run(variant)
	_diff()
	print("VAIL_BATCH ", JSON.stringify(results))
	get_tree().quit()

func _spawn_all(batched: bool) -> Array:
	var nodes: Array = []
	for i in COUNT:
		var fx: VailVFX = BatchedVail.new() if batched else VailVFX.new()
		fx._seeds = PackedFloat32Array([0.13 * (i % 7), 0.37, 0.71])
		fx.setup_point(VailVFX.Mode.AURA_PULSE,
			Vector2(120 + (i % 11) * 105, 160 + (i / 11) * 190), 1.0e9)
		board.add_child(fx)
		nodes.append(fx)
	return nodes

func _run(variant: String) -> void:
	var nodes := _spawn_all(variant.begins_with("B"))
	for n in nodes:
		n.elapsed = 0.4
		n.set_process(false)
	for i in 10:
		await RenderingServer.frame_post_draw
	var times: Array = []
	var last := Time.get_ticks_usec()
	for f in FRAMES:
		for n in nodes:
			n.queue_redraw()   # same per-frame redraw production does, frozen pose
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	times.sort()
	var total := 0.0
	for t in times: total += t
	results[variant] = {"avg_ms": snappedf(total / times.size(), 0.01),
		"p95_ms": snappedf(times[int(times.size() * 0.95)], 0.01),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	if not variant.ends_with("_2"):
		board.get_texture().get_image().save_png(
			ProjectSettings.globalize_path(OUT_DIR).path_join(variant + ".png"))
	for n in nodes:
		n.queue_free()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

func _diff() -> void:
	var dir := ProjectSettings.globalize_path(OUT_DIR)
	var a := Image.load_from_file(dir.path_join("A_production.png"))
	var b := Image.load_from_file(dir.path_join("B_batched.png"))
	var maxd := 0.0
	var changed := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d: float = maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))
			maxd = maxf(maxd, d)
			if d > 2.0 / 255.0:
				changed += 1
	results["diff"] = {"max_channel_delta_255": roundi(maxd * 255.0), "pixels_over_2": changed,
		"total_pixels": a.get_width() * a.get_height()}
