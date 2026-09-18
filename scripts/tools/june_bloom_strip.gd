extends Node2D

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Bloom over TIME. A still frame cannot show the three things that separate this
# from the first pass — the growth-in, the travelling surge, and the wither — so
# this films the same real board at six points across the 8s field and stacks the
# band region into one strip.
#
# Runs WINDOWED. Run: godot --path . res://scenes/tools/june_bloom_strip.tscn
var OUT: String = CapturePaths.out("june_bloom_strip.png")
const TIMES := [0.12, 0.30, 0.60, 2.40, 5.00, 7.60]
const CROP := Rect2i(250, 90, 460, 360)

func _ready() -> void:
	get_window().size = Vector2i(1500, 950)
	RenderingServer.set_default_clear_color(Color(0.12, 0.13, 0.10))

	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(1)
	var grid := BattleGrid.new()
	add_child(grid)
	var mgr := AutoBattleManager.new()
	add_child(mgr)
	mgr.battle_grid = grid
	var fx := Node2D.new()
	add_child(fx)
	mgr.skill_effect_container = fx
	mgr.projectile_container = Node2D.new()
	add_child(mgr.projectile_container)
	await get_tree().process_frame

	var june: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.JUNE,
		UnitBase.Element.EARTH, true)
	add_child(june)
	june.grid_position = Vector2i(3, 6)
	grid.place_unit(june, june.grid_position)
	june.position = grid.to_global(grid.grid_to_world(june.grid_position))

	var foes: Array = []
	for cell: Vector2i in [Vector2i(5, 2), Vector2i(6, 2), Vector2i(6, 3), Vector2i(4, 3)]:
		var e: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.RIOT,
			UnitBase.Element.NORMAL, false)
		add_child(e)
		e.grid_position = cell
		grid.place_unit(e, cell)
		e.position = grid.to_global(grid.grid_to_world(cell))
		foes.append(e)
	mgr.player_units = [june]
	mgr.enemy_units = foes
	await get_tree().process_frame

	mgr._june_bloom(june, foes)
	var strip := Image.create(CROP.size.x * TIMES.size(), CROP.size.y, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.08, 0.08, 0.07, 1.0))
	var prev := 0.0
	for i in TIMES.size():
		await get_tree().create_timer(TIMES[i] - prev).timeout
		prev = TIMES[i]
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		strip.blend_rect(img, CROP, Vector2i(i * CROP.size.x, 0))
		print("  t=%.2f  fields=%d" % [TIMES[i], mgr.bloom_fields.size()])
	var err := strip.save_png(ProjectSettings.globalize_path(OUT))
	assert(err == OK, "JUNE_BLOOM_STRIP: save failed")
	print("JUNE_BLOOM_STRIP: ALL PASS -> ", OUT)
	get_tree().quit(0)
