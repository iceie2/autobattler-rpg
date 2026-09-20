extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   normal,air,water,earth,fire,lightning
# Override with: -- --round=N
const DEBUT_ROUND := 3

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	# Render over the REAL board: the arena is sunlit GRASS, and an effect
	# only verified against a dark clear colour has not been verified.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	await _capture_aura()
	await _capture_auto()
	await _capture_mend()
	print("GOBLIN_SHAMAN_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _clear() -> void:
	for child in get_children():
		if child is BackgroundLayer:
			continue
		child.free()

func _unit(u: VisualUnit, pos: Vector2) -> VisualUnit:
	u.position = pos
	u.scale = Vector2(1.65, 1.65)
	add_child(u)
	return u

func _capture_aura() -> void:
	_clear()
	var shaman := _unit(EnemyFactory.create_goblin_shaman_fire(), Vector2(550, 315))
	await get_tree().process_frame
	if shaman.health_bar: shaman.health_bar.hide()
	var fx := GoblinShamanVFX.new()
	add_child(fx)
	fx.setup_aura(shaman, UnitBase.Element.FIRE, 260.0)
	await _shot("_goblin_shaman_spirit_link.png")

func _capture_auto() -> void:
	_clear()
	var shaman := _unit(EnemyFactory.create_goblin_shaman_fire(), Vector2(330, 390))
	await get_tree().process_frame
	if shaman.health_bar: shaman.health_bar.hide()
	var p := Projectile.new()
	p.setup(Vector2(510, 360), Vector2(980, 280), 9, UnitBase.Element.FIRE)
	p.is_goblin_shaman_orb = true
	add_child(p)
	p.global_position = Vector2(720, 325)
	p.set_process(false)
	await _shot("_goblin_shaman_auto.png")

func _capture_mend() -> void:
	_clear()
	var shaman := _unit(EnemyFactory.create_goblin_shaman_fire(), Vector2(300, 390))
	var ally := _unit(EnemyFactory.create_goblin(), Vector2(820, 320))
	await get_tree().process_frame
	if shaman.health_bar: shaman.health_bar.hide()
	if ally.health_bar: ally.health_bar.hide()
	var fx := GoblinShamanVFX.new()
	add_child(fx)
	fx.setup_mend(shaman, ally, UnitBase.Element.FIRE, 1.0)
	fx.global_position = shaman.global_position
	fx.elapsed = 0.62
	fx.set_process(false)
	fx.queue_redraw()
	await _shot("_goblin_shaman_mend.png")

func _shot(file_name: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := CapturePaths.out(file_name)
	var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	assert(err == OK, "capture failed: " + path)
