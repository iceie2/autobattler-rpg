extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   normal,air,water,earth,fire,lightning
# Override with: -- --round=N
const DEBUT_ROUND := 1

# Deterministic Rat VFX captures. elapsed/_spin pinned by hand and _process off,
# so every run yields the same frame.
# Runs WINDOWED (--headless renders nothing).
# Run: godot --path . res://scenes/tools/rat_vfx_capture.tscn

const ZOOM := 2.6

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	# Render over the REAL board: the arena is sunlit GRASS, and an effect
	# only verified against a dark clear colour has not been verified.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	scale = Vector2(ZOOM, ZOOM)
	await _pair(RatVFX.Mode.BITE_WINDUP, 0.85, "_rat_bite_windup.png")
	await _pair(RatVFX.Mode.BITE_IMPACT, 0.30, "_rat_bite_impact.png")
	await _disease()
	await _infest()
	print("RAT_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _rat(pos: Vector2, maker := 0):
	var u
	match maker:
		0: u = EnemyFactory.create_rat()
		1: u = EnemyFactory.create_goblin()              # green body
		2: u = EnemyFactory.create_windup_bot_normal()   # grey body
		_: u = EnemyFactory.create_skeleton()            # pale body
	u.position = pos
	u.scale = Vector2(1.15, 1.15)
	add_child(u)
	return u

func _clear() -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()

func _save(name: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(name))
	assert(err == OK, "capture failed: " + name)

func _pin(fx: RatVFX, t: float, spin := 1.0) -> void:
	fx.elapsed = t * fx.lifetime if is_finite(fx.lifetime) else t
	fx._spin = spin
	fx.set_process(false)
	fx.queue_redraw()

func _pair(kind: RatVFX.Mode, t: float, name: String) -> void:
	_clear()
	var rat = _rat(Vector2(150, 132))
	var vic = _rat(Vector2(292, 132), 1)
	await get_tree().process_frame
	if rat.health_bar: rat.health_bar.hide()
	if vic.health_bar: vic.health_bar.hide()
	var fx := RatVFX.new()
	add_child(fx)
	if kind == RatVFX.Mode.BITE_WINDUP:
		fx.setup_windup(rat, AutoBattleManager.RAT_BITE_REACH, 1.0)
		fx.global_position = rat.global_position
		fx.host = null
	else:
		fx.setup_point(kind, vic.global_position, AutoBattleManager.RAT_BITE_REACH, 1.0)
	_pin(fx, t)
	await _save(name)

# The persistent plague cloud at three points in its drift loop — a single still
# cannot show that it is continuously alive for the DoT's whole duration.
func _disease() -> void:
	_clear()
	# Three DIFFERENT body colours: a status has to be legible on an arbitrary
	# sprite, not just on whichever one the capture happened to pick.
	for i in range(3):
		var vic = _rat(Vector2(80 + i * 130, 140), i + 1)
		await get_tree().process_frame
		# Bars VISIBLE: evidence the cloud never covers them.
		var fx := RatVFX.new()
		add_child(fx)
		fx.setup_disease(vic, AutoBattleManager.RAT_BITE_REACH)
		fx.global_position = vic.global_position
		fx.host = null
		_pin(fx, 0.0, 0.6 + float(i) * 1.5)
	await _save("_rat_disease_persistent.png")

# Infestation ring: not swarming / half / full.
func _infest() -> void:
	_clear()
	var strengths := [0.0, 0.5, 1.0]
	for i in range(strengths.size()):
		var r = _rat(Vector2(80 + i * 130, 140))
		await get_tree().process_frame
		var fx := RatVFX.new()
		add_child(fx)
		fx.setup_infest(r, AutoBattleManager.RAT_INFEST_RING)
		fx.set_pack_strength(strengths[i])
		fx.global_position = r.global_position
		fx.host = null   # after setup_infest, so ground_y is already read off it
		_pin(fx, 0.0, 0.7 + float(i) * 0.9)
	await _save("_rat_infestation_ring.png")
