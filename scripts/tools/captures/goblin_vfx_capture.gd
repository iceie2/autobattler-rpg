extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   normal,air,water,earth,fire,lightning
# Override with: -- --round=N
const DEBUT_ROUND := 1


func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	# Render over the REAL board: the arena is sunlit GRASS, and an effect
	# only verified against a dark clear colour has not been verified.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	await _capture_auto()
	await _capture_pack()
	await _capture_shank()
	print("GOBLIN_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _base_unit(pos: Vector2) -> VisualUnit:
	var g := EnemyFactory.create_goblin()
	g.position = pos
	g.scale = Vector2(2.2, 2.2)
	add_child(g)
	if g.health_bar: g.health_bar.hide()
	return g

func _clear() -> void:
	for child in get_children():
		if child is BackgroundLayer:
			continue
		child.free()

func _capture_auto() -> void:
	_clear()
	var g := _base_unit(Vector2(900, 560))
	await get_tree().process_frame
	if g.animated_sprite and g.animated_sprite.sprite_frames.has_animation("attack"):
		g.animated_sprite.animation = "attack"
		g.animated_sprite.frame = 6
		g.animated_sprite.pause()
	var fx := GoblinVFX.new()
	add_child(fx)
	fx.scale = Vector2(2.2, 2.2)
	fx.setup_point(GoblinVFX.Mode.AUTO_IMPACT, Vector2(1030, 500), 0.30)
	fx.elapsed = 0.08
	await _shot("_goblin_attack_animation_contact.png")

func _capture_pack() -> void:
	_clear()
	for i in range(3):
		var g := _base_unit(Vector2(640 + i * 300, 540))
		var fx := GoblinVFX.new()
		add_child(fx)
		fx.scale = Vector2(2.2, 2.2)
		fx.setup_pack(g)
		fx.set_pack_strength([0.2, 0.6, 1.0][i])
		fx.elapsed = 0.35 + i * 0.08
	await _shot("_goblin_pack_courage.png")

func _capture_shank() -> void:
	_clear()
	var g := _base_unit(Vector2(780, 560))
	await get_tree().process_frame
	if g.animated_sprite and g.animated_sprite.sprite_frames.has_animation("attack"):
		g.animated_sprite.animation = "attack"
		g.animated_sprite.frame = 6
		g.animated_sprite.pause()
	var windup := GoblinVFX.new()
	add_child(windup)
	windup.scale = Vector2(2.2, 2.2)
	windup.setup_point(GoblinVFX.Mode.SHANK_WINDUP, Vector2(780, 560), 0.50)
	windup.elapsed = 0.27
	var impact := GoblinVFX.new()
	add_child(impact)
	impact.scale = Vector2(2.2, 2.2)
	impact.setup_point(GoblinVFX.Mode.SHANK_IMPACT, Vector2(1060, 500), 0.48)
	impact.elapsed = 0.08
	await _shot("_goblin_shank_contact.png")

func _shot(file_name: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := CapturePaths.out(file_name)
	var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	assert(err == OK, "capture failed: " + path)
