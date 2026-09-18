extends Node2D

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Scorched Path across its full 5s life. The tile is meant to COOL — char stays,
# embers dim — and a still frame cannot show that, which is the same reason
# June's Bloom needed a filmstrip.
#
# Runs WINDOWED. Run: godot --path . res://scenes/tools/sear_trail_strip.tscn
var OUT: String = CapturePaths.out("sear_trail_strip.png")
const TIMES := [0.15, 0.60, 1.60, 3.00, 4.20, 4.90]
const CROP := Rect2i(150, 300, 430, 380)

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

	var sear: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.SEAR,
		UnitBase.Element.FIRE, true)
	add_child(sear)
	sear.battle_manager = mgr
	sear.grid_position = Vector2i(2, 6)
	grid.place_unit(sear, sear.grid_position)
	sear.position = grid.to_global(grid.grid_to_world(sear.grid_position))
	mgr.player_units = [sear]
	mgr.enemy_units = []
	await get_tree().process_frame

	# Three tiles lit at once so the strip shows the whole cooling curve together.
	for cell: Vector2i in [Vector2i(2, 5), Vector2i(3, 5), Vector2i(3, 4)]:
		sear.grid_position = cell
		mgr._on_unit_finished_step(sear)
	sear.position = grid.to_global(grid.grid_to_world(sear.grid_position))

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
		print("  t=%.2f  tiles=%d vfx=%d" % [TIMES[i], mgr.fire_trail.size(), mgr._sear_scorch_vfx.size()])
	var err := strip.save_png(ProjectSettings.globalize_path(OUT))
	assert(err == OK, "SEAR_TRAIL_STRIP: save failed")
	print("SEAR_TRAIL_STRIP: ALL PASS -> ", OUT)
	get_tree().quit(0)
