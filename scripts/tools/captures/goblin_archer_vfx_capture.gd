extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   normal,air,water,earth,fire,lightning
# Override with: -- --round=N
const DEBUT_ROUND := 2

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	# Render over the REAL board: the arena is sunlit GRASS, and an effect
	# only verified against a dark clear colour has not been verified.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	await _capture_arrow(false, "_goblin_archer_auto.png")
	await _capture_arrow(true, "_goblin_archer_crippling_arrow.png")
	await _capture_cooldown()
	print("GOBLIN_ARCHER_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _clear() -> void:
	for child in get_children():
		if child is BackgroundLayer:
			continue
		child.free()

func _archer() -> VisualUnit:
	var u := EnemyFactory.create_goblin_archer()
	u.position = Vector2(650, 520)
	u.scale = Vector2(2.2, 2.2)
	add_child(u)
	return u

func _capture_arrow(crippling: bool, file_name: String) -> void:
	_clear()
	var u := _archer()
	await get_tree().process_frame
	if u.health_bar: u.health_bar.hide()
	var p := Projectile.new()
	p.setup(Vector2(760, 500), Vector2(1200, 390), 24, UnitBase.Element.NORMAL)
	p.is_goblin_arrow = true
	p.is_crippling_arrow = crippling
	p.focus_stacks = 4 if not crippling else 0
	add_child(p)
	p.global_position = Vector2(980, 445)
	p.set_process(false)
	await _shot(file_name)

func _capture_cooldown() -> void:
	_clear()
	var u := _archer()
	u.skill_cd_time = 3.0
	await get_tree().process_frame
	u._process(0.0)
	await _shot("_enemy_skill_cooldown_bar.png")

func _shot(file_name: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := CapturePaths.out(file_name)
	var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	assert(err == OK, "capture failed: " + path)
