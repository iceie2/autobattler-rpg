extends Node2D

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Crowded-battle readability check for the Wind-Up Bot, on the REAL wave-6
# formation. Uses the same WaveDirector the live game uses (never a hand-copied
# mirror — that drifts) and the real BattleGrid, so the spacing, the perspective
# and the health bars are the ones the player actually sees.
#
# It renders the worst realistic case: every bot Overclocked to a different
# stack count, one mid-wind-up, one at impact, and one victim mid-knock-up — all
# on screen at once. If the effects are going to smear into noise, it happens
# here.
#
# Runs WINDOWED (--headless writes empty PNGs).
# Run: godot --path . res://scenes/tools/windup_bot_wave6_check.tscn

const ROUND := 6
const DIFFICULTY := 1

func _ready() -> void:
	get_window().size = Vector2i(1500, 900)
	RenderingServer.set_default_clear_color(Color(0.10, 0.09, 0.08))

	var grid := BattleGrid.new()
	add_child(grid)
	await get_tree().process_frame

	# ── The real wave-6 spec ──────────────────────────────────────────────────
	var director := WaveDirector.new()
	var spec: Array = director.generate_wave_spec(ROUND, DIFFICULTY, grid.grid_width)
	var units: Array = []
	var tally: Dictionary = {}
	for entry in spec:
		var u: VisualUnit = director.create_enemy_for_entry(entry, ROUND)
		if not u:
			continue
		add_child(u)
		var cell: Vector2i = entry.get("pos", Vector2i(0, 0))
		grid.place_unit(u, cell)
		u.grid_position = cell
		u.position = grid.to_global(grid.grid_to_world(cell))
		units.append(u)
		tally[u.unit_name] = int(tally.get(u.unit_name, 0)) + 1

	print("WAVE %d COMPOSITION (%d units):" % [ROUND, units.size()])
	for k in tally.keys():
		print("   %-28s x%d" % [k, tally[k]])
	var bots: Array = units.filter(func(u): return bool(u.get_meta("windup_bot", false)))
	print("   -> Wind-Up Bots on board: %d" % bots.size())
	await get_tree().process_frame

	# ── Every Wind-Up Bot effect live, simultaneously ─────────────────────────
	var fxroot := Node2D.new()
	add_child(fxroot)
	for i in range(bots.size()):
		var bot = bots[i]
		# Overclock at a different stack count per bot: 2 / 6 / 10.
		var oc := WindUpBotVFX.new()
		fxroot.add_child(oc)
		oc.setup_overclock(bot, bot.current_element)
		oc.set_overclock_steps([2, 6, 10][i % 3])
		oc.global_position = bot.global_position
		oc.caster_unit = null
		oc._tick_flash = 0.0
		oc._spin = 0.8 + float(i) * 0.5
		oc.set_process(false)
		oc.queue_redraw()

	# Bot 0 winding up (late anticipation).
	if bots.size() > 0:
		var w := WindUpBotVFX.new()
		fxroot.add_child(w)
		w.setup_windup(bots[0], bots[0].current_element,
			AutoBattleManager.WINDUP_PUNCH_REACH, 1.0)
		w.global_position = bots[0].global_position
		w.caster_unit = null
		w.elapsed = 0.86
		w._spin = 1.4
		w.set_process(false)
		w.queue_redraw()

	# Bot 1 landing its punch on the nearest non-bot, which is mid-knock-up.
	if bots.size() > 1:
		var victims: Array = units.filter(func(u): return not bool(u.get_meta("windup_bot", false)))
		if not victims.is_empty():
			var vic = victims[0]
			var imp := WindUpBotVFX.new()
			fxroot.add_child(imp)
			imp.setup_point(WindUpBotVFX.Mode.PUNCH_IMPACT, vic.global_position,
				bots[1].current_element, AutoBattleManager.WINDUP_PUNCH_REACH, 1.0)
			imp.elapsed = 0.24
			imp._spin = 2.0
			imp.set_process(false)
			imp.queue_redraw()
			# Freeze the victim at the top of its arc so the knock-up is visible
			# in a still (the tween would be mid-flight for only a few frames).
			vic._set_toss(Vector2(0, -VisualUnit.KNOCKUP_PEAK_HEIGHT))
			vic._updraft_spin_x = 0.35     # mid-tumble
			vic._apply_animation()

	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := CapturePaths.out("windup_bot_wave6_crowded.png")
	var err := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	assert(err == OK, "capture failed")
	print("WINDUP_BOT_WAVE6_CHECK: ALL PASS")
	get_tree().quit(0)
