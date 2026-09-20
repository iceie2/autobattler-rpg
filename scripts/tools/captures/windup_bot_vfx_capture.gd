extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Real debut round (enemy_biome_matrix survey). This enemy fights on:
#   normal,air,water,earth
# Override with: -- --round=N
const DEBUT_ROUND := 3

# Deterministic Wind-Up Bot VFX captures. `elapsed`/`_spin` are pinned by hand
# and _process is disabled, so every run produces the same frame — these are
# reviewable evidence, not screenshots of whatever the tween happened to be
# doing. Runs WINDOWED: --headless uses the dummy renderer and would write
# empty PNGs (same reason as the model3d probes, CONVENTIONS §1).
#
# Run: godot --path . res://scenes/tools/windup_bot_vfx_capture.tscn

const ELEM := UnitBase.Element.NORMAL
# Uniform magnification for the stills only. Everything — bot, VFX, spacing —
# is scaled by the same factor, so the captures stay an honest record of the
# effect's real size RELATIVE to the unit and its 110px cell, just readable.
const ZOOM := 2.6

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	# Render over the REAL board: the arena is sunlit GRASS, and an effect
	# only verified against a dark clear colour has not been verified.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	scale = Vector2(ZOOM, ZOOM)
	# Anticipation, twice, because the whole point of the wind-up is that it
	# ESCALATES — one frame could never show that.
	await _capture_point(WindUpBotVFX.Mode.PUNCH_WINDUP, 0.22, "_windup_bot_punch_windup_early.png")
	await _capture_point(WindUpBotVFX.Mode.PUNCH_WINDUP, 0.88, "_windup_bot_punch_windup_late.png")
	await _capture_point(WindUpBotVFX.Mode.PUNCH_IMPACT, 0.26, "_windup_bot_punch_impact.png")
	await _capture_point(WindUpBotVFX.Mode.AUTO_IMPACT, 0.24, "_windup_bot_auto_impact.png")
	await _capture_overclock()
	await _capture_elements()
	print("WINDUP_BOT_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _bot(element: int, pos: Vector2):
	var bot = EnemyFactory._create_windup_bot(element)
	bot.position = pos
	bot.scale = Vector2(1.15, 1.15)
	add_child(bot)
	return bot

func _clear() -> void:
	for child in get_children():
		if child is BackgroundLayer:
			continue
		child.free()

func _save(file_name: String) -> void:
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := CapturePaths.out(file_name)
	var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	assert(err == OK, "capture failed: " + path)

func _pin(fx: WindUpBotVFX, t: float, spin: float = 1.1) -> void:
	fx.elapsed = t * fx.lifetime if is_finite(fx.lifetime) else t
	fx._spin = spin
	fx.set_process(false)
	fx.queue_redraw()

func _capture_point(kind: WindUpBotVFX.Mode, t: float, file_name: String) -> void:
	_clear()
	var bot = _bot(ELEM, Vector2(150, 132))
	var victim = _bot(ELEM, Vector2(292, 132))
	await get_tree().process_frame
	if bot.health_bar: bot.health_bar.hide()
	if victim.health_bar: victim.health_bar.hide()
	var fx := WindUpBotVFX.new()
	add_child(fx)
	if kind == WindUpBotVFX.Mode.PUNCH_WINDUP:
		# Anchored on the CASTER — this is the bot coiling its own mainspring.
		fx.setup_windup(bot, ELEM, AutoBattleManager.WINDUP_PUNCH_REACH, 1.0)
		fx.global_position = bot.global_position
		fx.caster_unit = null            # pin the position, stop it tracking
	else:
		# Anchored on the TARGET — contact happens where the fist lands.
		fx.setup_point(kind, victim.global_position, ELEM,
			AutoBattleManager.WINDUP_PUNCH_REACH, 1.0)
	_pin(fx, t)
	await _save(file_name)

# Escalation strip: the same mechanism at 0 / +10% / +30% / +50%, side by side.
# A single frame can only ever show one stack count, so the passive's whole
# "it is winding up over the fight" read has to be demonstrated across a row.
func _capture_overclock() -> void:
	_clear()
	var steps := [0, 2, 6, 10]
	for i in range(steps.size()):
		var bot = _bot(ELEM, Vector2(55 + i * 120, 165))
		await get_tree().process_frame
		# Bars stay VISIBLE here on purpose — this strip is also the evidence
		# that the Overclock badge never sits on top of the health bar.
		var fx := WindUpBotVFX.new()
		add_child(fx)
		fx.setup_overclock(bot, ELEM)
		fx.set_overclock_steps(steps[i])
		fx.global_position = bot.global_position
		fx.caster_unit = null
		fx._tick_flash = 0.0             # no milestone flare in the still
		_pin(fx, 0.0, 0.9 + float(i) * 0.35)
	await _save("_windup_bot_overclock_escalation.png")

# All six variants at the same beat: same machine, different charge.
func _capture_elements() -> void:
	_clear()
	var elements := [UnitBase.Element.NORMAL, UnitBase.Element.FIRE, UnitBase.Element.WATER,
		UnitBase.Element.EARTH, UnitBase.Element.AIR, UnitBase.Element.LIGHTNING]
	for i in range(elements.size()):
		var e: int = elements[i]
		var col: int = i % 3
		var row: int = i / 3
		var pos := Vector2(75 + col * 133, 78 + row * 110)
		var bot = _bot(e, pos)
		await get_tree().process_frame
		if bot.health_bar: bot.health_bar.hide()
		var fx := WindUpBotVFX.new()
		add_child(fx)
		fx.setup_point(WindUpBotVFX.Mode.PUNCH_IMPACT, bot.global_position, e,
			AutoBattleManager.WINDUP_PUNCH_REACH, 1.0)
		_pin(fx, 0.26)
	await _save("_windup_bot_elements.png")
