extends Node

# Visual harness for the run map screen (2026-09-19).
# Generates a real biome map, opens the screen on it, and captures it twice:
# at the start of the biome, and part-way up after walking a few nodes (so the
# walked-path highlighting and the adjacent-only tooltips can be checked).
#
#   godot --path . res://scenes/_run_map_capture.tscn -- --biome=2 --seed=7 --steps=5
#
# Writes through CapturePaths. Needs a real window — no --headless.

const CapturePathsScript = preload("res://scripts/tools/capture_paths.gd")

func _ready() -> void:
	var biome := 0
	var map_seed := 12345
	var steps := 5
	var opening := false
	var motion_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--biome="): biome = int(a.split("=")[1])
		if a.begins_with("--seed="):  map_seed = int(a.split("=")[1])
		if a.begins_with("--steps="): steps = int(a.split("=")[1])
		if a == "--opening": opening = true
		if a.begins_with("--motion="): motion_dir = a.substr("--motion=".length())

	# --opening drives the REAL main_game through a run's first two beats
	# (map → relic node → relic pick → free starting hero) and captures each.
	# That sequence soft-locked a first playthrough — the picker came up with no
	# cards — so it's worth being able to LOOK at it, not just assert it.
	if opening:
		await _capture_opening()
		return

	# --size=WxH renders at another resolution. The map derives node size and
	# lane spacing from the viewport (RunMapScreen._layout), so a layout that is
	# comfortable at 1080p can still collide on a 1366x768 laptop — VD-14's
	# five-wide rows are checked at both, not assumed from one.
	var win := Vector2i(1920, 1080)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var wh: PackedStringArray = a.substr("--size=".length()).split("x")
			if wh.size() == 2:
				win = Vector2i(int(wh[0]), int(wh[1]))
	get_window().size = win

	# Seed the GLOBAL rng before generating, not just the map's own. The layout
	# comes from the map's rng, but every node's reward is rolled by RoundReward
	# on the global one — so two captures with identical arguments drew the same
	# map with different loot on it, and an A/B of the reward badge compared a
	# coin against a sword on the same node.
	seed(map_seed)
	var map := RunMap.generate(biome, map_seed, true)
	var bad: Array = map.validate()
	if not bad.is_empty():
		push_error("generated map failed validate(): %s" % str(bad))

	var screen := RunMapScreen.new()
	# ── THE PROBES ARE NOT OPTIONAL ───────────────────────────────────────────
	# The node art and the hover card are both fed by callables that main_game
	# injects. A standalone screen with neither still RENDERS — it just draws the
	# ⚔ glyph instead of the creature silhouette and a card with the fight facts
	# missing — so an un-probed capture comes back looking like a plausible
	# screenshot of a game that has lost its monster art. It did exactly that on
	# 2026-09-19 and cost a round trip arguing about art nobody had broken.
	#
	# sprite_path_for is a static on the screen precisely so this harness can
	# call the SAME resolver the game does; there is no second implementation
	# here to drift. The preview probe genuinely needs a live WaveDirector and a
	# grid, which this scene has not got, so it stays unset — and _shot refuses
	# to write the hover capture without it rather than writing a lie.
	# One director for the whole capture, not one per call: it caches unit prices
	# per (code, round) and a fresh instance would re-instantiate every body for
	# every node on the map.
	var probe_director := WaveDirector.new()
	screen.sprite_probe = func(round_no: int, node_type: int, difficulty: int,
			wave_seed: int) -> String:
		var battle_code: String = ""
		if node_type == RunMap.NodeType.BATTLE:
			battle_code = probe_director.lead_code(round_no, difficulty, wave_seed)
		return RunMapScreen.sprite_path_for(round_no, node_type, -1, battle_code)
	add_child(screen)
	await get_tree().process_frame
	if motion_dir != "":
		await _capture_motion(screen, map, map_seed, motion_dir)
		get_tree().quit()
		return
	screen.present(map, "Biome %d" % (biome + 1))
	# Wait out the opening reveal, not a fixed frame count. A fresh biome inks
	# itself in (~1.8s at REVEAL_RATE 0.7), and the old fixed 20 frames shot it
	# mid-reveal — every run_map_start taken since the reveal landed showed the
	# first few rows and an empty right half, which read as missing nodes.
	var reveal_guard: int = 0
	while screen._reveal_start >= 0.0 and reveal_guard < 600:
		await get_tree().process_frame
		reveal_guard += 1
	for _i in range(20):
		await get_tree().process_frame
	await _shot("run_map_start")

	# Walk partway so cleared nodes, the lit path and the new frontier all show.
	# The MAP is seeded, but the walk up it was not, so two runs of this harness
	# with identical arguments stood on different nodes and hovered different
	# forks. That makes the captures useless for the one thing a capture harness
	# is for — putting two renders of the SAME frame side by side and seeing
	# what a change did. Seed the walk from the same number that seeds the map.
	seed(map_seed)
	for _i in range(steps):
		var options: Array = map.available_next()
		if options.is_empty():
			break
		map.advance_to(String(options[randi() % options.size()]["id"]))
	screen.present(map, "Biome %d" % (biome + 1))
	for _i in range(20):
		await get_tree().process_frame
	await _shot("run_map_midway")

	# ── The one-edge hover preview ────────────────────────────────────────────
	# The forks ahead are hairlines until you hover one. That is a property of
	# the EDGE pass, not of the hover card, so it can be shown truthfully here
	# even though the card itself cannot be (see the refusal below): drive
	# _hover_id directly and keep the card hidden, rather than calling
	# _on_node_hover and capturing a card with its fight facts blank.
	var preview: Array = map.available_next()
	if not preview.is_empty():
		screen._hover_id = String(preview[0]["id"])
		screen._tip.visible = false
		for _i in range(20):
			await get_tree().process_frame
		await _shot("run_map_hover_edge")
		screen._hover_id = ""

	# Hover a reachable FIGHT so the card's enemy mini-board is in the shot —
	# that panel only exists on hover, so a plain capture can never show it and
	# "it renders" would be an assumption rather than something anyone checked.
	# …but only if the card can actually be filled. preview_probe needs a live
	# WaveDirector and battle grid, which this standalone scene has not got, so
	# the hover card here would render with its fight facts blank. That picture
	# is worse than no picture: it looks like a bug in the card. Refuse it and
	# say which command DOES produce a truthful one.
	if not screen.preview_probe.is_valid():
		push_warning("run_map_capture: no preview_probe on the standalone screen — "
			+ "SKIPPING run_map_hover. The node card needs the live game: "
			+ "re-run with `-- --opening` for a truthful hover capture.")
		print("SKIPPED run_map_hover (needs --opening — see warning above)")
	else:
		screen._hover_armed = true
		for opt in map.available_next():
			if RunMap.is_battle_node(opt):
				# The card is CLICK-driven now (hover only lights the cone), so
				# the harness opens it directly. The cursor still gets parked on
				# the node so the cone in the shot matches the card.
				var btn: Button = screen._buttons.get(String(opt["id"]))
				if btn:
					Input.warp_mouse(btn.get_global_rect().get_center())
				await get_tree().process_frame
				screen.open_dossier(opt)
				break
		for _i in range(20):
			await get_tree().process_frame
		await _shot("run_map_hover")

	# Row widths too: a layout check is only a check if the capture actually
	# contains the width being checked — the first VD-14 render of seed 12345
	# had no 5-wide row at all and would have "passed" by omission.
	var widths: Array = []
	for row in map.rows:
		widths.append(row.size())
	print("CAPTURED biome %d seed %d — %d rows, walked %d, at %s, widths %s"
		% [biome, map_seed, map.rows.size(), steps, map.current_id, str(widths)])
	get_tree().quit()

func _capture_opening() -> void:
	get_window().size = Vector2i(1920, 1080)
	var mg := (load("res://scenes/main_game.tscn") as PackedScene).instantiate()
	add_child(mg)
	# Relics reveal left-to-right; wait through the whole cascade so this audit
	# never mistakes an in-progress animation for a one-choice screen.
	for _i in range(200):
		await get_tree().process_frame
	await _shot("opening_1_relic")
	if mg._relic_screen._card_row.get_child_count() > 0:
		(mg._relic_screen._card_row.get_child(0) as Button).emit_signal("pressed")
	# The picker's cards reveal on a STAGGERED slot-machine reel (see
	# hero_shop.CARD_STAGGER), so a shot taken a second in catches card 1 landed
	# and cards 2-3 still spinning — which looks exactly like the soft-lock bug
	# it's here to rule out. Wait past the whole cascade.
	for _i in range(200):
		await get_tree().process_frame
	await _shot("opening_2_starting_hero")

	# Take the hero so the map comes back, then hover a real fight. This has to
	# happen on the LIVE game: the node card's "what am I facing" panel is fed by
	# a probe main_game injects, so a standalone screen shows the card with those
	# lines simply missing — which is exactly how the first capture of it lied.
	if not mg._hero_shop._card_btns.is_empty():
		mg._hero_shop._card_btns[0].emit_signal("pressed")
	for _i in range(40):
		await get_tree().process_frame
	var screen2 = mg._run_map_screen
	Input.warp_mouse(Vector2(8, 8))
	screen2._tip.visible = false
	await get_tree().process_frame
	await _shot("opening_3_map_ready")
	# The card a new player actually sees first: one reachable stage-1 fight.
	screen2._hover_armed = true
	var previewed_first: Dictionary = {}
	for first_opt in mg._run_map.available_next():
		if RunMap.is_battle_node(first_opt):
			previewed_first = first_opt
			screen2.open_dossier(first_opt)
			# The dossier performs a two-frame container settle on first use; audit
			# the stable presentation, not its transient construction rectangle.
			for _settle in range(4):
				await get_tree().process_frame
			await _shot("opening_4_first_node_card")
			screen2._tip.visible = false
			break
	# Hover a node HIGH UP the map, deliberately not one you can step onto: the
	# card must show the whole fight from anywhere, so capturing an adjacent node
	# would prove nothing about that.
	# THE BOSS ROW FIRST. Bosses are where sprite resolution actually breaks —
	# they're the only multi-phase units, so they're the ones whose art is keyed
	# "khagan_phase1" with no plain "khagan" to look up. A card captured on an
	# ordinary wave exercises none of that and passed happily while the wave-10
	# boss rendered as a blank grey disc in the preview of his own fight.
	var far_nodes: Array = []
	for row in mg._run_map.rows:
		for n in row:
			if int(n["type"]) == RunMap.NodeType.BOSS:
				far_nodes.append(n)
	for row2 in mg._run_map.rows:
		for n2 in row2:
			if RunMap.is_battle_node(n2) and int(n2["row"]) >= 8:
				far_nodes.append(n2)
	for opt in far_nodes:
		if RunMap.is_battle_node(opt):
			var btn2: Button = screen2._buttons.get(String(opt["id"]))
			if btn2:
				Input.warp_mouse(btn2.get_global_rect().get_center())
			await get_tree().process_frame
			screen2.open_dossier(opt)
			# Re-assert the hover on the frame before the shot: warping the
			# cursor makes the button emit its own enter/exit a frame later, and
			# a stray exit hides the card again — which is why the first two
			# attempts at this capture came back with no card at all.
			for _i in range(30):
				await get_tree().process_frame
			screen2.open_dossier(opt)
			await get_tree().process_frame
			break
	await _shot("opening_5_future_boss_card")

	# Commit to the middle available fight and capture the exact state in which
	# the player is expected to arrange their hero and press READY. This makes the
	# opening audit cover the whole promise chain, not stop at a hover preview.
	screen2._tip.visible = false
	# Enter the SAME node captured above. Choosing a different tier here made the
	# audit compare a one-goblin Skirmish card with a two-enemy Veteran battle and
	# could neither prove nor disprove that the preview kept its promise.
	var first_fight: Dictionary = previewed_first
	if not first_fight.is_empty():
		mg._on_map_node_chosen(first_fight)
		for _i in range(30):
			await get_tree().process_frame
		await _shot("opening_6_first_battle_prep")

	print("CAPTURED opening — picker cards: %d, map open over it: %s, formation rows: %d"
		% [mg._hero_shop._card_btns.size(), str(mg._run_map_screen.visible),
			screen2._tip_formation.size()])
	get_tree().quit()

# --motion=<dir>: the reveal, the hover lift + cone flow, and the travel beat,
# saved frame by frame so they can be judged as MOTION. A still shows none of
# the three.
#
# The screen's own _process is switched off and stepped by hand at exactly 1/30s
# per saved frame, so the sequence is identical every run however long each PNG
# takes to write — wall-clock frames would stutter wherever the disk did.
# Frames go to the directory given, never into the project: they are throwaway.
func _capture_motion(screen: RunMapScreen, map: RunMap, map_seed: int,
		dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	Input.warp_mouse(Vector2(4, 4))     # park the real cursor away from every node
	screen.set_process(false)
	var dt := 1.0 / 30.0
	# 1. The reveal, from the first frame of a fresh biome.
	screen.present(map, "Biome")
	var n_reveal: int = int(ceil(screen._reveal_duration() / dt)) + 8
	for i in range(n_reveal):
		screen._process(dt)
		await _motion_frame(dir, "reveal", i)
	# 2. Stand two nodes in, then rest on a fork: the lift eases up, the cone
	#    lights and the dashes drift along it.
	seed(map_seed)
	for _s in range(2):
		var opts: Array = map.available_next()
		map.advance_to(String(opts[randi() % opts.size()]["id"]))
	screen.present(map, "Biome")
	var fork: Dictionary = map.available_next()[0]
	screen._hover_armed = true
	screen._on_node_hover(fork)
	for i in range(40):
		screen._process(dt)
		# Hold the dwell back: this sequence is about the lift and the flow, and
		# the card opening at the one-second mark would cover both.
		screen._dwell = 0.0
		await _motion_frame(dir, "hover", i)
	# 3. Commit to that fork and follow the marker until it arrives.
	screen.open_dossier(fork)
	screen._on_node_pressed(fork)
	var n_travel: int = int(ceil(RunMapScreen.TRAVEL_SECONDS / dt)) + 1
	for i in range(n_travel):
		screen._process(dt)
		if not screen.visible:
			break
		await _motion_frame(dir, "travel", i)
	print("MOTION frames -> %s  (reveal %d, hover 40, travel <=%d)"
		% [dir, n_reveal, n_travel])

func _motion_frame(dir: String, tag: String, i: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	img.save_png("%s/%s_%03d.png" % [dir, tag, i])

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = CapturePathsScript.out("%s.png" % name)
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("  -> %s%s" % [path, "" if err == OK else "  (SAVE FAILED)"])
