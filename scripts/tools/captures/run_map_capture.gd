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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--biome="): biome = int(a.split("=")[1])
		if a.begins_with("--seed="):  map_seed = int(a.split("=")[1])
		if a.begins_with("--steps="): steps = int(a.split("=")[1])
		if a == "--opening": opening = true

	# --opening drives the REAL main_game through a run's first two beats
	# (map → relic node → relic pick → free starting hero) and captures each.
	# That sequence soft-locked a first playthrough — the picker came up with no
	# cards — so it's worth being able to LOOK at it, not just assert it.
	if opening:
		await _capture_opening()
		return

	get_window().size = Vector2i(1920, 1080)

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
	screen.present(map, "Biome %d" % (biome + 1))
	for _i in range(20):
		await get_tree().process_frame
	await _shot("run_map_start")

	# Walk partway so cleared nodes, the lit path and the new frontier all show.
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
				# The card follows the MOUSE (see _process), so a hover driven by
				# code alone parks it wherever the cursor happens to be —
				# off-screen in a capture. Put the cursor on the node first.
				var btn: Button = screen._buttons.get(String(opt["id"]))
				if btn:
					Input.warp_mouse(btn.get_global_rect().get_center())
				await get_tree().process_frame
				screen._on_node_hover(opt, true)
				break
		for _i in range(20):
			await get_tree().process_frame
		await _shot("run_map_hover")

	print("CAPTURED biome %d seed %d — %d rows, walked %d, at %s"
		% [biome, map_seed, map.rows.size(), steps, map.current_id])
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
			screen2._on_node_hover(first_opt, true)
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
			screen2._on_node_hover(opt, true)
			# Re-assert the hover on the frame before the shot: warping the
			# cursor makes the button emit its own enter/exit a frame later, and
			# a stray exit hides the card again — which is why the first two
			# attempts at this capture came back with no card at all.
			for _i in range(30):
				await get_tree().process_frame
			screen2._on_node_hover(opt, true)
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

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = CapturePathsScript.out("%s.png" % name)
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("  -> %s%s" % [path, "" if err == OK else "  (SAVE FAILED)"])
