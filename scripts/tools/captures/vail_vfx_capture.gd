extends Node2D
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Deterministic Vail VFX captures. Runs WINDOWED.
#   godot --path . res://scenes/tools/vail_vfx_capture.tscn [-- --round=N]
#
# Vail is the AIR hero, so her decade is 11-20 and the air board is where her
# effects have to hold up — it is also the palest board in the game (tile
# luminance 203 against 28-112 for every other biome), which is exactly the
# backdrop a pale cyan wind effect can vanish into. Defaulting to her own
# decade means the hardest case is the one that gets looked at by default.
const DEBUT_ROUND := 11
# 1.0 = the size these actually ship at. A zoomed VFX strip flatters the
# effect exactly the way a 720px model render flatters a 115px character.
const ZOOM := 1.0

func _ready() -> void:
	get_window().size = Vector2i(1100, 620)
	# Render over the REAL board. An effect verified only against a dark clear
	# colour has not been verified — see the enemy VFX captures that all had to
	# be redone for exactly this.
	var bg := BackgroundLayer.new()
	add_child(bg)
	bg.set_biome_from_round(CapturePaths.cli_round(DEBUT_ROUND))
	scale = Vector2(ZOOM, ZOOM)

	# Background-only control FIRST. Without it there is no way to measure how
	# much of a frame is actually the effect: the air board's own painterly
	# variation is wider than the effects are, so a "differs from the median
	# pixel" mask returns essentially the whole image and every effect scores
	# identically. Diffing against this control is the only honest read.
	await _control()

	# Each ability across its own timeline, so the strip reads as the beat does.
	await _strip(VailVFX.Mode.AURA_PULSE, 1.1, "_vail_fx_passive_farwinds.png")
	await _strip(VailVFX.Mode.GUST_MUZZLE, 0.30, "_vail_fx_attack_muzzle.png")
	await _strip(VailVFX.Mode.GUST_IMPACT, 0.34, "_vail_fx_attack_impact.png")
	await _strip(VailVFX.Mode.UPDRAFT_LIFT, 1.0, "_vail_fx_skill_updraft.png")
	await _strip(VailVFX.Mode.DOWNBURST_MARK, 0.30, "_vail_fx_ult_mark.png")
	await _strip(VailVFX.Mode.DOWNBURST_SLAM, 0.70, "_vail_fx_ult_slam.png")
	await _strip(VailVFX.Mode.GROUNDED_RESIDUE, 5.0, "_vail_fx_ult_grounded.png")
	print("VAIL_VFX_CAPTURE: ALL PASS")
	get_tree().quit(0)

func _control() -> void:
	_clear()
	await _save("_vail_fx_control.png")

func _clear() -> void:
	for c in get_children():
		if c is BackgroundLayer:
			continue
		c.free()

func _save(n: String) -> void:
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(
		CapturePaths.out(n)) == OK, "capture failed: " + n)

# Five copies of one effect, each frozen at a different point in its lifetime.
# Freezing rather than filming is deliberate: _process would advance them all in
# step and the strip would show one pose five times.
func _strip(kind: VailVFX.Mode, life: float, name: String) -> void:
	_clear()
	# FOUR, not five, and kept inside x 140-500: the board is a perspective
	# trapezoid occupying only the left of the window, and anything past ~520
	# lands on the painterly side backdrop instead of the play surface, which
	# is not where these ever appear in a real fight.
	for i in range(4):
		var fx := VailVFX.new()
		add_child(fx)
		# Low enough that the tall beats stay in frame (the Downburst column
		# reaches 168px above its own origin).
		fx.setup_point(kind, Vector2(150 + i * 120, 330), life)
		fx.elapsed = life * (float(i) + 0.5) / 4.0
		fx.set_process(false)
		fx.queue_redraw()
	await _save(name)
