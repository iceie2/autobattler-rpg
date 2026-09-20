extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   normal,air,water,earth,fire,lightning
# Override with: -- --round=N
const DEBUT_ROUND := 7
# Deterministic Orc VFX captures. Runs WINDOWED.
# Run: godot --path . res://scenes/tools/orc_vfx_capture.tscn
const ZOOM := 2.4

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	# Render over the REAL board: the arena is sunlit GRASS, and an effect
	# only verified against a dark clear colour has not been verified.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	scale = Vector2(ZOOM, ZOOM)
	await _crush()
	await _rage()
	await _orc_vs_ogre()
	print("ORC_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

# Same ability name => same visual language, scaled to the body. This still is
# the evidence for that decision: an Ogre showing a DIFFERENT effect for an
# identically-named "Crushing Blow" would misrepresent the ability.
func _orc_vs_ogre() -> void:
	_clear()
	var codes := ["orc_normal", "ogre"]
	for i in range(2):
		var u = _u(Vector2(120 + i * 180, 158), codes[i])
		await get_tree().process_frame
		if u.health_bar: u.health_bar.hide()
		var fx := OrcVFX.new(); add_child(fx)
		fx.setup_point(OrcVFX.Mode.CRUSH_IMPACT, u.global_position,
			u.get_meta("crush_vfx_reach", 104.0), 1.0)
		_pin(fx, 0.30)
	await _save("_orc_vs_ogre_slam_scale.png")

func _u(pos: Vector2, code := "orc_normal"):
	var u = EnemyFactory.create_by_type(code)
	u.position = pos; u.scale = Vector2(0.95, 0.95); add_child(u)
	return u

func _clear() -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()

func _save(n: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

func _pin(fx: OrcVFX, t: float, tt := 1.0) -> void:
	fx.elapsed = t * fx.lifetime if is_finite(fx.lifetime) else t
	fx._t = tt; fx.set_process(false); fx.queue_redraw()

# Windup escalating then the slam landing — the telegraph must escalate
# monotonically, which no single still can show.
func _crush() -> void:
	_clear()
	var specs := [[OrcVFX.Mode.CRUSH_WINDUP, 0.25], [OrcVFX.Mode.CRUSH_WINDUP, 0.92],
		[OrcVFX.Mode.CRUSH_IMPACT, 0.18], [OrcVFX.Mode.CRUSH_IMPACT, 0.60]]
	for i in range(specs.size()):
		var o = _u(Vector2(85 + i * 140, 158))
		await get_tree().process_frame
		if o.health_bar: o.health_bar.hide()
		var fx := OrcVFX.new(); add_child(fx)
		if specs[i][0] == OrcVFX.Mode.CRUSH_WINDUP:
			fx.setup_on(specs[i][0], o, AutoBattleManager.ORC_REACH, 1.0)
			fx.global_position = o.global_position; fx.host = null
		else:
			fx.setup_point(specs[i][0], o.global_position, AutoBattleManager.ORC_REACH, 1.0)
		_pin(fx, specs[i][1])
	await _save("_orc_crushing_blow.png")

# Healthy / the berserk trigger firing / the sustained enraged state.
# Bars VISIBLE — also the evidence nothing covers them.
func _rage() -> void:
	_clear()
	var modes := [-1, OrcVFX.Mode.BERSERK_TRIGGER, OrcVFX.Mode.ENRAGED]
	for i in range(3):
		var o = _u(Vector2(110 + i * 160, 158))
		await get_tree().process_frame
		if modes[i] == -1:
			continue
		var fx := OrcVFX.new(); add_child(fx)
		fx.setup_on(modes[i], o, AutoBattleManager.ORC_REACH, 1.0)
		fx.global_position = o.global_position; fx.host = null
		_pin(fx, 0.35 if modes[i] == OrcVFX.Mode.BERSERK_TRIGGER else 0.0, 1.2)
	await _save("_orc_bloodrage.png")
