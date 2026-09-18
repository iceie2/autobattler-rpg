extends Node2D

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Ignite across its cast. It is a three-beat ability now (throw, ground run,
# column) and a still frame cannot show any of that — same reason Bloom needed a
# filmstrip. Real board, real grass.
#
# Runs WINDOWED. Run: godot --path . res://scenes/tools/sear_ignite_strip.tscn
var OUT: String = CapturePaths.out("sear_ignite_strip.png")
const TIMES := [0.05, 0.14, 0.26, 0.42, 0.62, 0.85]
const CROP := Rect2i(170, 180, 420, 430)

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
	sear.grid_position = Vector2i(3, 5)
	grid.place_unit(sear, sear.grid_position)
	sear.position = grid.to_global(grid.grid_to_world(sear.grid_position))

	var foe: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.RIOT,
		UnitBase.Element.NORMAL, false)
	add_child(foe)
	foe.battle_manager = mgr
	foe.grid_position = Vector2i(5, 3)
	grid.place_unit(foe, foe.grid_position)
	foe.position = grid.to_global(grid.grid_to_world(foe.grid_position))
	mgr.player_units = [sear]
	mgr.enemy_units = [foe]
	await get_tree().process_frame

	mgr._sear_ignite(sear, [foe])
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
	assert(foe.burn_time > 0.0, "SEAR_IGNITE_STRIP: target is not burning")
	var err := strip.save_png(ProjectSettings.globalize_path(OUT))
	assert(err == OK, "SEAR_IGNITE_STRIP: save failed")
	print("SEAR_IGNITE_STRIP: ALL PASS -> ", OUT)
	get_tree().quit(0)
