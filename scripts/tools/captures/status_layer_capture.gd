extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Shared status layer captures (ENEMY_FEEL_AUDIT.md §2.1). Runs WINDOWED.
# Run: godot --path . res://scenes/tools/status_layer_capture.tscn [-- --round=N]
# Frame 1: one status per unit (body mark + badge with a part-drained ring).
# Frame 2: one unit carrying five statuses at once — the badge row's worst case.
const ZOOM := 1.9

func _ready() -> void:
	get_window().size = Vector2i(1280, 620)
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(1))
	scale = Vector2(ZOOM, ZOOM)
	await _one_each()
	await _stacked()
	print("STATUS_LAYER_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _u(pos: Vector2, code := "orc_normal"):
	var u = EnemyFactory.create_by_type(code)
	u.position = pos; add_child(u)
	return u

func _clear() -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()

func _save(n: String) -> void:
	for i in range(4): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

func _mark(kind: int, u, tt := 0.9) -> void:
	var fx := StatusFX.new(); add_child(fx)
	fx.setup_on(kind, u)
	fx._t = tt; fx._fade = 1.0; fx.set_process(false); fx.queue_redraw()

# Apply at full length, let the badge see its peak, then drop to 40% left so
# the drain ring is visibly part-empty in the capture.
func _drain(u, field: String, full: float) -> void:
	u.set(field, full)
	await get_tree().process_frame
	u.set(field, full * 0.4)

func _one_each() -> void:
	_clear()
	var kinds := [StatusFX.Kind.BURN, StatusFX.Kind.SLOW, StatusFX.Kind.ROOT,
		StatusFX.Kind.TAUNT, StatusFX.Kind.HEAL_CUT, StatusFX.Kind.WEAKEN]
	var fields := ["burn_time", "slow_time", "root_time", "taunt_time", "heal_cut_time", "weakened_time"]
	var units: Array = []
	for i in kinds.size():
		units.append(_u(Vector2(70 + i * 105, 150), ["orc_normal", "bear_water", "troll_fire",
			"slime_air", "lizard_earth", "windup_bot_lightning"][i]))
	await get_tree().process_frame
	for i in kinds.size():
		var u = units[i]
		if kinds[i] == StatusFX.Kind.SLOW: u.slow_pct = 0.35
		if kinds[i] == StatusFX.Kind.TAUNT: u.taunt_source = units[0]
		if kinds[i] == StatusFX.Kind.WEAKEN: u.weakened_pct = 0.2
		await _drain(u, fields[i], 3.0)
		_mark(kinds[i], u)
	await _save("_status_layer_one_each.png")

func _stacked() -> void:
	_clear()
	var a = _u(Vector2(170, 150), "bear_normal")
	var b = _u(Vector2(420, 150), "goblin")
	await get_tree().process_frame
	a.slow_pct = 0.3
	await _drain(a, "stun_time", 1.5)
	await _drain(a, "slow_time", 2.0)
	await _drain(a, "bleed_time", 4.0)
	await _drain(a, "burn_time", 3.0)
	await _drain(a, "heal_cut_time", 5.0)
	_mark(StatusFX.Kind.SLOW, a)
	_mark(StatusFX.Kind.BURN, a)
	# The 3D goblin as control: marks must sit on a model body as well as a sprite.
	await _drain(b, "root_time", 2.0)
	_mark(StatusFX.Kind.ROOT, b)
	await _save("_status_layer_stacked.png")
