extends Node2D

const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Crowded readability check for the Rat, on a REAL early wave with a REAL
# BattleGrid (so spacing, perspective and health bars are the live ones).
# Shows the worst realistic case at once: several rats swarming (rings live at
# different strengths) and a victim carrying the persistent disease.
#
# Runs WINDOWED. Run: godot --path . res://scenes/tools/rat_wave_check.tscn

const DIFFICULTY := 1

func _ready() -> void:
	get_window().size = Vector2i(1500, 900)
	RenderingServer.set_default_clear_color(Color(0.10, 0.09, 0.08))
	var grid := BattleGrid.new()
	add_child(grid)
	await get_tree().process_frame

	# Find an early round that actually fields several rats.
	var units: Array = []
	var rats: Array = []
	var chosen := 0
	for attempt in range(40):
		var r: int = 1 + (attempt % 3)
		for u in units:
			grid.purge_unit(u); u.free()
		units = []; rats = []
		var director := WaveDirector.new()
		for entry in director.generate_wave_spec(r, DIFFICULTY, grid.grid_width):
			var u: VisualUnit = director.create_enemy_for_entry(entry, r)
			if not u: continue
			add_child(u)
			var cell: Vector2i = entry.get("pos", Vector2i(0, 0))
			grid.place_unit(u, cell)
			u.grid_position = cell
			u.position = grid.to_global(grid.grid_to_world(cell))
			units.append(u)
			if u.unit_name == "Rat": rats.append(u)
		chosen = r
		if rats.size() >= 3: break

	print("ROUND %d — %d units, %d Rats" % [chosen, units.size(), rats.size()])
	for u in units: print("   %s @ %s" % [u.unit_name, u.grid_position])
	await get_tree().process_frame

	var fxroot := Node2D.new()
	add_child(fxroot)
	# Swarm rings at escalating strength.
	for i in range(rats.size()):
		var fx := RatVFX.new()
		fxroot.add_child(fx)
		fx.setup_infest(rats[i], AutoBattleManager.RAT_INFEST_RING)
		fx.set_pack_strength(clampf(0.5 + 0.25 * float(i), 0.0, 1.0))
		fx.global_position = rats[i].global_position
		fx.host = null
		fx._spin = 0.6 + float(i) * 0.7
		fx.set_process(false); fx.queue_redraw()
	# Persistent disease on every NON-rat, plus one bite landing.
	var victims: Array = units.filter(func(u): return u.unit_name != "Rat")
	for i in range(victims.size()):
		var fx := RatVFX.new()
		fxroot.add_child(fx)
		fx.setup_disease(victims[i], AutoBattleManager.RAT_BITE_REACH)
		fx.global_position = victims[i].global_position
		fx.host = null
		fx._spin = 0.4 + float(i) * 1.3
		fx.set_process(false); fx.queue_redraw()
	if not victims.is_empty():
		var imp := RatVFX.new()
		fxroot.add_child(imp)
		imp.setup_point(RatVFX.Mode.BITE_IMPACT, victims[0].global_position,
			AutoBattleManager.RAT_BITE_REACH, 1.0)
		imp.elapsed = 0.30
		imp.set_process(false); imp.queue_redraw()

	for i in range(4): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path(CapturePaths.out("rat_wave_crowded.png")))
	assert(err == OK)
	print("RAT_WAVE_CHECK: ALL PASS")
	get_tree().quit(0)
