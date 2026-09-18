extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Deterministic Slime VFX captures. elapsed/_t pinned, _process off.
# Runs WINDOWED. Run: godot --path . res://scenes/tools/slime_vfx_capture.tscn
const ZOOM := 2.6
const E := UnitBase.Element.NORMAL

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	RenderingServer.set_default_clear_color(Color(0.11, 0.10, 0.08))
	scale = Vector2(ZOOM, ZOOM)
	await _pair(SlimeVFX.Mode.GOO_WINDUP, 0.85, "_slime_goo_windup.png")
	await _pair(SlimeVFX.Mode.GOO_SPLAT, 0.30, "_slime_goo_splat.png")
	await _corroded()
	await _split()
	await _elements()
	print("SLIME_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2, kind := 0, elem := E):
	var u
	match kind:
		0: u = EnemyFactory._create_slime(elem)
		1: u = EnemyFactory.create_goblin()
		_: u = EnemyFactory.create_windup_bot_normal()
	u.position = pos; u.scale = Vector2(1.15, 1.15); add_child(u)
	return u

func _clear() -> void:
	for c in get_children(): c.free()

func _save(n: String) -> void:
	for i in range(3): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

func _pin(fx: SlimeVFX, t: float, tt := 1.0) -> void:
	fx.elapsed = t * fx.lifetime if is_finite(fx.lifetime) else t
	fx._t = tt; fx.set_process(false); fx.queue_redraw()

func _pair(kind: SlimeVFX.Mode, t: float, n: String) -> void:
	_clear()
	var sl = _u(Vector2(150, 132))
	var v = _u(Vector2(292, 132), 1)
	await get_tree().process_frame
	if sl.health_bar: sl.health_bar.hide()
	if v.health_bar: v.health_bar.hide()
	var fx := SlimeVFX.new(); add_child(fx)
	if kind == SlimeVFX.Mode.GOO_WINDUP:
		fx.setup_windup(sl, E, AutoBattleManager.SLIME_REACH, 1.0)
		fx.global_position = sl.global_position; fx.host = null
	else:
		fx.setup_point(kind, v.global_position, E, AutoBattleManager.SLIME_REACH, 1.0)
	_pin(fx, t)
	await _save(n)

# Persistent corrosion on three DIFFERENT body colours — a status has to be
# legible on an arbitrary sprite, and bars stay visible as overlap evidence.
func _corroded() -> void:
	_clear()
	for i in range(3):
		var v = _u(Vector2(80 + i * 130, 140), [1, 2, 0][i])
		await get_tree().process_frame
		var fx := SlimeVFX.new(); add_child(fx)
		fx.setup_corroded(v, E, AutoBattleManager.SLIME_REACH)
		fx.global_position = v.global_position; fx.host = null
		_pin(fx, 0.0, 0.5 + float(i) * 1.1)
	await _save("_slime_corroded_persistent.png")

# The split across its arc — one still cannot show a body coming apart.
func _split() -> void:
	_clear()
	for i in range(4):
		var sl = _u(Vector2(70 + i * 120, 140))
		await get_tree().process_frame
		if sl.health_bar: sl.health_bar.hide()
		var fx := SlimeVFX.new(); add_child(fx)
		fx.setup_point(SlimeVFX.Mode.SPLIT, sl.global_position, E,
			AutoBattleManager.SLIME_REACH * 2.0, 1.0)
		_pin(fx, [0.08, 0.30, 0.55, 0.85][i])
	await _save("_slime_split_arc.png")

func _elements() -> void:
	_clear()
	var els := [UnitBase.Element.NORMAL, UnitBase.Element.FIRE, UnitBase.Element.WATER,
		UnitBase.Element.EARTH, UnitBase.Element.AIR, UnitBase.Element.LIGHTNING]
	for i in range(els.size()):
		var e: int = els[i]
		var pos := Vector2(75 + (i % 3) * 133, 78 + (i / 3) * 110)
		var sl = _u(pos, 0, e)
		await get_tree().process_frame
		if sl.health_bar: sl.health_bar.hide()
		var fx := SlimeVFX.new(); add_child(fx)
		fx.setup_point(SlimeVFX.Mode.GOO_SPLAT, sl.global_position, e,
			AutoBattleManager.SLIME_REACH, 1.0)
		_pin(fx, 0.30)
	await _save("_slime_elements.png")
