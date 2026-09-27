extends Node
# ══════════════════════════════════════════════════════════════════════════════
# RUN MAP SMOKE (2026-09-19) — proves the two-counter model holds in the REAL
# game, not just in the generator.
#
# `arena --mode=map` checks map STRUCTURE in bulk. What it can't see is the part
# that actually matters to a player: that walking an interstitial node doesn't
# burn a wave, that walking a battle node advances the wave counter by exactly
# one, and that the map and GameState.battle_round never drift apart. Those all
# live in main_game, so this drives main_game.
#
# It walks a biome by calling the same entry point the screen calls
# (_on_map_node_chosen) and asserts the counters after every step. Battles are
# not fought — the node is entered, the round is checked, and the walk moves on.
#
# Run:  godot --headless res://scenes/map_smoke.tscn
# Exit code 0 = pass, 1 = fail.
# ══════════════════════════════════════════════════════════════════════════════

# Read off the screen itself rather than restated, so retuning the dwell there
# cannot leave this test asserting a boundary the game no longer has.
const DOSSIER_DWELL_S := RunMapScreen.DOSSIER_DWELL

var _fails: Array = []
var _checked: int = 0

func _ready() -> void:
	var mg_scene := load("res://scenes/main_game.tscn") as PackedScene
	var mg := mg_scene.instantiate()
	add_child(mg)
	for _i in range(30):
		await get_tree().process_frame

	if not mg.MAP_MODE:
		print("MAP_SMOKE: SKIPPED — MAP_MODE is off")
		get_tree().quit(0)
		return

	# The map is generated immediately, but the opening cadence is relic choice
	# -> starting hero -> map. The mandatory relic landmark is already consumed.
	if mg._run_map == null:
		print("MAP_SMOKE: FAILED -> no map generated at run start")
		get_tree().quit(1)
		return
	if mg._run_map_screen.visible:
		_fails.append("the map screen is visible before the opening relic choice")

	var map: RunMap = mg._run_map

	# ── The opening beat: relic node → Call to Arms ───────────────────────────
	# A run opens on its three relic choices. The free starting-hero picker is
	# chained off that pick, so if anything in
	# that chain breaks the run is UNPLAYABLE — you get a picker with no heroes
	# in it and no way forward. First playthrough hit exactly that, so it's a
	# permanent check now.
	var current: Dictionary = map.node_by_id(map.current_id)
	if current.is_empty() or int(current.get("type", -1)) != RunMap.NodeType.RELIC:
		_fails.append("the opening relic landmark was not consumed before presentation")
	else:
		if not mg._relic_screen.visible:
			_fails.append("the run did not open on the relic screen")
		var offers: Array = Relic.roll_offers(1, [])
		mg._on_relic_chosen(offers[0] if not offers.is_empty() else {"name": "test"})
		for _i in range(5):
			await get_tree().process_frame
		if not mg._hero_shop.visible:
			_fails.append("Call to Arms picker never opened after the relic pick")
		if mg._hero_shop._offers.is_empty():
			_fails.append("Call to Arms picker opened with NO hero offers — run is stuck")
		if mg._hero_shop._card_btns.size() < 3:
			_fails.append("Call to Arms picker drew %d hero cards, expected 3"
				% mg._hero_shop._card_btns.size())
		# THE SOFT-LOCK, reproduced: the map must not be clickable behind the
		# picker. It used to re-open over it, so you could start a round with no
		# hero — and starting a round runs _enter_player_turn → clear_offers(),
		# which emptied the picker you were still standing in front of.
		if mg._run_map_screen.visible:
			_fails.append("the map is open on top of the Call to Arms picker")
		var cards_before: int = mg._hero_shop._card_btns.size()
		mg._enter_player_turn()
		for _i in range(2):
			await get_tree().process_frame
		if mg._hero_shop._card_btns.size() != cards_before:
			_fails.append("a prep phase wiped the open picker's cards (%d -> %d)"
				% [cards_before, mg._hero_shop._card_btns.size()])
		# Take the first hero so the walk below has a team, and so the picker's
		# own completion path is exercised.
		if not mg._hero_shop._card_btns.is_empty():
			mg._hero_shop._card_btns[0].emit_signal("pressed")
			for _i in range(5):
				await get_tree().process_frame
		if mg.player_units.is_empty():
			_fails.append("picking a starting hero did not put one on the board")
		# …and once a hero exists, the map comes back on its own.
		if not mg._run_map_screen.visible:
			_fails.append("the map did not re-open after the starting hero was picked")
		# …and the run's FIRST biome inks itself in. main_game consumes the
		# start landmark before the map is ever shown, which silently disabled
		# the reveal on the one biome every player sees. The standalone motion
		# checks further down could never catch that — a standalone map starts
		# with nothing consumed — so it is asserted here, in the real flow.
		elif mg._run_map_screen._reveal_start < 0.0:
			_fails.append("the run's first biome opened without its reveal")
		# The cursor is inherited from the hero card that just closed. Merely
		# appearing over a node must not count as an intentional hover.
		if mg._run_map_screen._hover_armed:
			_fails.append("map hover armed before the player moved the mouse")
		if mg._run_map_screen._tip.visible:
			_fails.append("a node dossier opened from the inherited hero-card cursor")
		_checked += 11

	# ── Hover LOOKS, click ASKS ──────────────────────────────────────────────
	# The dossier is a big centred card, so opening it on hover covered the very
	# paths the cone had just lit. Hover now lights the cone and nothing else,
	# and the fight preview costs a click. Both halves are asserted below,
	# because "no card appeared" is exactly the kind of thing that silently
	# regresses the moment someone reconnects a signal.
	var hover_node: Dictionary = {}
	for row in map.rows:
		for n in row:
			if RunMap.is_battle_node(n):
				hover_node = n
				break
		if not hover_node.is_empty():
			break
	if not hover_node.is_empty():
		var screen: RunMapScreen = mg._run_map_screen
		screen._hover_armed = true
		screen._on_node_hover(hover_node)
		await get_tree().process_frame
		if screen._tip.visible:
			_fails.append("hovering %s opened the dossier — it must only light the cone"
				% hover_node["id"])
		if screen._selected_id != "":
			_fails.append("hovering %s selected it; only a click may do that"
				% hover_node["id"])
		# …but RESTING on it opens the card by itself. Driven by feeding _process
		# directly rather than waiting out real frames: a second of wall clock in
		# a smoke test is a second nobody gets back, and the boundary is the
		# thing under test, not the frame rate.
		screen._dwell = 0.0
		screen._process(DOSSIER_DWELL_S * 0.5)
		if screen._tip.visible:
			_fails.append("half the dwell opened the dossier on %s" % hover_node["id"])
		screen._process(DOSSIER_DWELL_S * 0.6)
		if not screen._tip.visible:
			_fails.append("resting on %s for the full dwell opened nothing"
				% hover_node["id"])
		if screen._dossier_pinned:
			_fails.append("a dwell-opened dossier was pinned; moving off will never clear it")
		# Moving to another node retires it again — a card you did not ask for
		# must not outlive the cursor that summoned it.
		var other: Dictionary = {}
		for opt_h in map.available_next():
			if String(opt_h["id"]) != String(hover_node["id"]):
				other = opt_h
				break
		if not other.is_empty():
			screen._on_node_hover(other)
			if screen._tip.visible or screen._selected_id != "":
				_fails.append("the dwell dossier survived moving to %s" % other["id"])
		screen._clear_selection()
		screen._on_node_hover(hover_node)
		screen._dwell = 0.0
		_checked += 1

		# ── The commitment preview dims exactly what the fork cannot reach ────
		# Hovering a node fades everything downstream of it that it cannot get
		# to, so a lane you can't climb out of is visible BEFORE you click into
		# it rather than two rows later. That's a claim about a set, which a
		# screenshot cannot check: the cone is compared against a closure walked
		# independently here, so an off-by-one in the traversal fails the smoke
		# instead of quietly under-dimming the map.
		screen._refresh_cone()
		var expected: Dictionary = {}
		var frontier: Array = [String(hover_node["id"])]
		expected[String(hover_node["id"])] = true
		while not frontier.is_empty():
			var at: String = String(frontier.pop_back())
			for cid in map.node_by_id(at).get("children", []):
				if not expected.has(String(cid)):
					expected[String(cid)] = true
					frontier.append(String(cid))
		var cone_ids: Array = screen._cone.keys()
		cone_ids.sort()
		var want_ids: Array = expected.keys()
		want_ids.sort()
		if cone_ids != want_ids:
			_fails.append("hover cone is %d nodes, the real closure is %d"
				% [cone_ids.size(), want_ids.size()])
		# …and the dimming has to actually reach the map. A cone that covers
		# everything would pass the comparison above and dim nothing at all.
		var dimmed: int = 0
		for row_c in map.rows:
			for n_c in row_c:
				var id_c: String = String(n_c["id"])
				var factor: float = screen._cone_factor(id_c)
				var walked: bool = id_c == map.current_id or map.cleared.has(id_c)
				if expected.has(id_c) or walked:
					if factor < 1.0:
						_fails.append("%s is reachable (or already walked) but dimmed" % id_c)
				elif factor < 1.0:
					dimmed += 1
				else:
					_fails.append("%s is unreachable from the hovered fork but stayed lit" % id_c)
		if dimmed == 0:
			_fails.append("hovering %s dimmed nothing — the preview says nothing"
				% hover_node["id"])
		_checked += 1

		# ── …and a CLICK opens it, without committing to anything ────────────
		# The first click on a node must never start a fight. That is the whole
		# safety property of moving the preview off hover, so it is counted
		# rather than trusted: node_chosen has to stay silent.
		var chosen: Array = []
		screen.node_chosen.connect(func(n): chosen.append(n))
		var pick: Dictionary = {}
		for opt in map.available_next():
			if RunMap.is_battle_node(opt):
				pick = opt
				break
		if pick.is_empty():
			_fails.append("no reachable fight to open a dossier on")
		else:
			screen._on_node_pressed(pick)
			await get_tree().process_frame
			if not screen._tip.visible:
				_fails.append("clicking %s opened no dossier" % pick["id"])
			if screen._selected_id != String(pick["id"]):
				_fails.append("clicking %s did not select it" % pick["id"])
			if not chosen.is_empty():
				_fails.append("the FIRST click on %s entered the node" % pick["id"])
			if not screen._tip_action.visible:
				_fails.append("no BEGIN button on a node the player may enter")
			# A dwell card opens under the cursor that summoned it, so the card
			# must let the single click that follows reach the node beneath it —
			# every part of it except BEGIN.
			if screen._tip.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				_fails.append("the dossier blocks the click meant for the node under it")
			if screen._tip_action.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				_fails.append("BEGIN was made click-through — it can never be pressed")
			# Clicking neither a node nor the card puts it away.
			screen._maybe_dismiss_dossier(Vector2(4, 4))
			if screen._tip.visible or screen._selected_id != "":
				_fails.append("clicking off the map did not dismiss the dossier")
		screen._clear_selection()
		_checked += 1

	# ── The SECOND click commits ─────────────────────────────────────────────
	# Driven on a throwaway screen rather than the live one: entering a node on
	# main_game's map would start a real battle and desync the walk below, so
	# this would otherwise be the one half of the interaction nobody checks.
	var solo := RunMapScreen.new()
	add_child(solo)
	var solo_map := RunMap.generate(0, 4242, false)
	solo.present(solo_map, "Commit check")
	await get_tree().process_frame
	var entered: Array = []
	solo.node_chosen.connect(func(n): entered.append(n))
	var solo_pick: Dictionary = solo_map.available_next()[0]
	solo._on_node_pressed(solo_pick)          # opens the dossier
	await get_tree().process_frame
	solo._on_node_pressed(solo_pick)          # …and commits
	await get_tree().process_frame
	if entered.size() != 1:
		_fails.append("second click on %s emitted node_chosen %d times, expected 1"
			% [solo_pick["id"], entered.size()])
	elif String(entered[0]["id"]) != String(solo_pick["id"]):
		_fails.append("second click entered %s, not the selected %s"
			% [entered[0]["id"], solo_pick["id"]])
	if solo.visible or solo._tip.visible:
		_fails.append("the map stayed up after committing to a node")
	# A node you cannot step onto is scoutable but never enterable, however many
	# times it is clicked.
	var far: Dictionary = solo_map.rows[solo_map.rows.size() - 1][0]
	entered.clear()
	solo._on_node_pressed(far)
	solo._on_node_pressed(far)
	await get_tree().process_frame
	if not entered.is_empty():
		_fails.append("clicking the unreachable %s twice entered it" % far["id"])
	if not solo._tip.visible:
		_fails.append("the unreachable %s could not be scouted" % far["id"])
	if solo._tip_action.visible:
		_fails.append("BEGIN offered on the unreachable %s" % far["id"])

	# ── Dwell, then ONE click ────────────────────────────────────────────────
	# The whole reason the dwell exists: rest on a node, read the card that
	# opens itself, and go — a single click, not two. Asserted on its own fresh
	# screen because the one above has already been committed on.
	var solo2 := RunMapScreen.new()
	add_child(solo2)
	var solo2_map := RunMap.generate(0, 777, false)
	solo2.present(solo2_map, "Dwell check")
	await get_tree().process_frame
	var one_click: Array = []
	solo2.node_chosen.connect(func(n): one_click.append(n))
	solo2._hover_armed = true
	var dwell_pick: Dictionary = solo2_map.available_next()[0]
	solo2._on_node_hover(dwell_pick)
	solo2._dwell = 0.0
	solo2._process(DOSSIER_DWELL_S + 0.1)
	if not solo2._tip.visible:
		_fails.append("dwelling on %s opened nothing" % dwell_pick["id"])
	solo2._on_node_pressed(dwell_pick)
	await get_tree().process_frame
	if one_click.size() != 1:
		_fails.append("dwell then ONE click entered %d times, expected 1"
			% one_click.size())
	solo2.queue_free()
	solo.queue_free()
	_checked += 1

	# ── Motion ───────────────────────────────────────────────────────────────
	# Everything below steps the screen's own clock through _process directly,
	# the same way the dwell check does: the boundaries are what's under test,
	# not the frame rate, and no awaits sit between steps so the engine's own
	# frames can't add time behind the test's back.
	var mo := RunMapScreen.new()
	add_child(mo)
	await get_tree().process_frame

	# CURVED PATHS STILL CAN'T CROSS. The screen's comment argues it from the
	# layout (one x per row, so every curve between two rows is the same blend
	# of its endpoints at the same step). This checks the argument on real maps:
	# every pair of edges between two rows, sampled along their length, must
	# share x at every sample and never swap vertical order.
	var crossings: int = 0
	var x_drift: int = 0
	for b_i in range(4):
		for s_i in range(12):
			var gm := RunMap.generate(b_i, 9000 + b_i * 100 + s_i, false)
			mo.present(gm, "geometry")
			for r_i in range(gm.rows.size() - 1):
				var parents: Array = gm.rows[r_i]
				for pa in range(parents.size()):
					for pb in range(pa + 1, parents.size()):
						for ca in parents[pa]["children"]:
							for cb in parents[pb]["children"]:
								var ea: PackedVector2Array = RunMapScreen._edge_points(
									mo._node_pos(parents[pa]),
									mo._node_pos(gm.node_by_id(String(ca))))
								var eb: PackedVector2Array = RunMapScreen._edge_points(
									mo._node_pos(parents[pb]),
									mo._node_pos(gm.node_by_id(String(cb))))
								for k_i in range(ea.size()):
									if absf(ea[k_i].x - eb[k_i].x) > 0.01:
										x_drift += 1
									if ea[k_i].y > eb[k_i].y + 0.01:
										crossings += 1
	if x_drift > 0:
		_fails.append("curved edges between one pair of rows disagree on x at %d samples "
			% x_drift + "— the no-crossing argument's premise is gone")
	if crossings > 0:
		_fails.append("curved edges cross at %d samples across 48 maps" % crossings)

	# THE REVEAL PLAYS ONCE PER BIOME. present() runs after every fight, so a
	# reveal keyed on anything looser would replay on every single visit.
	var rv_map := RunMap.generate(0, 31337, false)
	mo.present(rv_map, "reveal")
	if mo._reveal_start < 0.0:
		_fails.append("a fresh biome did not start its reveal")
	elif mo._reveal_row(rv_map.rows.size() - 1) > 0.0:
		_fails.append("the boss row was visible on the reveal's first frame")
	mo._process(mo._reveal_duration() + 0.1)
	if mo._reveal_start >= 0.0:
		_fails.append("the reveal never finished")
	mo.present(rv_map, "reveal again")
	if mo._reveal_start >= 0.0:
		_fails.append("re-opening the SAME biome replayed its reveal")
	var rv_next := RunMap.generate(1, 31338, false)
	mo.present(rv_next, "next biome")
	if mo._reveal_start < 0.0:
		_fails.append("the next biome did not reveal")
	mo._process(mo._reveal_duration() + 0.1)

	# HOVER LIFT eases in under the cursor and back out when it leaves.
	mo._hover_armed = true
	var lift_a: Dictionary = rv_next.rows[0][0]
	var lift_b: Dictionary = rv_next.rows[1][0]
	mo._on_node_hover(lift_a)
	mo._process(0.5)
	if float(mo._lift.get(String(lift_a["id"]), 0.0)) < 0.9:
		_fails.append("the hovered node did not lift")
	mo._on_node_hover(lift_b)
	mo._process(0.5)
	if mo._lift.has(String(lift_a["id"])):
		_fails.append("a node kept its lift after the cursor left it")
	mo._clear_selection()
	mo._hover_id = ""

	# THE TRAVEL BEAT. Stand on the relic, commit to a fight: the marker walks
	# first and node_chosen fires ONCE, on arrival — and a click mid-walk can't
	# start a second one.
	var tv_map := RunMap.generate(2, 4040, false)
	mo.present(tv_map, "travel")
	mo._process(mo._reveal_duration() + 0.1)
	tv_map.advance_to(String(tv_map.rows[0][0]["id"]))
	mo.present(tv_map, "travel")
	var walked_to: Array = []
	mo.node_chosen.connect(func(n): walked_to.append(n))
	var tv_pick: Dictionary = tv_map.available_next()[0]
	mo._on_node_pressed(tv_pick)            # open the dossier
	mo._on_node_pressed(tv_pick)            # commit — the walk begins
	if not walked_to.is_empty():
		_fails.append("committing fired node_chosen before the marker walked the path")
	if mo._travel.is_empty():
		_fails.append("committing along a real path started no travel beat")
	mo._process(RunMapScreen.TRAVEL_SECONDS * 0.5)
	mo._on_node_pressed(tv_pick)            # a click mid-walk
	if not walked_to.is_empty():
		_fails.append("node_chosen fired halfway along the path")
	if mo._tip.visible or mo._selected_id != "":
		_fails.append("a click mid-walk opened a dossier over the traveller")
	mo._process(RunMapScreen.TRAVEL_SECONDS)
	if walked_to.size() != 1:
		_fails.append("the walk ended with node_chosen fired %d times, expected 1"
			% walked_to.size())
	if mo.visible:
		_fails.append("the map stayed up after the traveller arrived")
	mo.queue_free()
	_checked += 1

	var waves_seen: Array[int] = []
	var guard: int = 0

	while guard < 40:
		guard += 1
		var options: Array = map.available_next()
		if options.is_empty():
			break
		var node: Dictionary = options[randi() % options.size()]
		var round_before: int = mg.game_state.battle_round
		var is_battle: bool = RunMap.is_battle_node(node)

		mg._on_map_node_chosen(node)
		for _i in range(3):
			await get_tree().process_frame
		_checked += 1

		var round_after: int = mg.game_state.battle_round
		if is_battle:
			# A battle node lands the wave counter on ITS OWN round. That is
			# usually +1, but it JUMPS when the path skipped waves — take a side
			# node instead of wave 2 and the next fight really is wave 3, with
			# wave 2's scaling, XP and gold simply never happening. What must
			# never happen is the counter going backwards or landing on the wrong
			# round, because every other system keys off it.
			if round_after != int(node["round"]):
				_fails.append("battle node %s is round %d but the game is on %d"
					% [node["id"], int(node["round"]), round_after])
			if round_after <= round_before:
				_fails.append("battle node %s moved the round %d -> %d (backwards)"
					% [node["id"], round_before, round_after])
			waves_seen.append(int(node["wave"]))
			# Prep phase entered: the tier the node carried must be the tier the
			# wave was built at, or the map's promise is cosmetic.
			if mg._locked_difficulty != int(node["difficulty"]):
				_fails.append("battle node %s is tier %d but the wave locked tier %d"
					% [node["id"], int(node["difficulty"]), mg._locked_difficulty])
			# Nothing fights here; step past it as if it had been cleared.
			map.cleared[String(node["id"])] = true
		else:
			# Event nodes must open an actual encounter. Advancing the map and
			# silently showing nothing is a consumed choice, not a valid event.
			if int(node["type"]) == RunMap.NodeType.EVENT and not mg._event_panel.visible:
				_fails.append("event node %s opened no event panel" % node["id"])
			# THE RULE: a utility node does not start a battle.
			if round_after != round_before:
				_fails.append("interstitial node %s moved the round %d -> %d"
					% [node["id"], round_before, round_after])
			# Close whatever modal it opened so the walk can continue.
			mg._event_panel.visible = false
			mg._shop_screen.visible = false
			mg._relic_screen.visible = false
			mg._event_from_map = false
			mg._shop_from_map = false

	# A path may SKIP waves now by taking a side node in a wave row, so the count
	# is a range. What must still hold absolutely: waves arrive in ascending
	# order and none repeats — skipping wave 6 means the next fight is wave 7,
	# never wave 6 again.
	var floor_waves: int = 2  # protected elite + boss
	if waves_seen.size() > RunMap.WAVES_PER_BIOME or waves_seen.size() < floor_waves:
		_fails.append("walked %d waves through the biome, expected %d-%d (%s)"
			% [waves_seen.size(), floor_waves, RunMap.WAVES_PER_BIOME, str(waves_seen)])
	for i in range(1, waves_seen.size()):
		if waves_seen[i] <= waves_seen[i - 1]:
			_fails.append("waves did not ascend: %s" % str(waves_seen))
			break
	# The elite (wave 5) and the boss (wave 10) are unskippable by design.
	if not 5 in waves_seen:
		_fails.append("the walk skipped the wave-5 elite: %s" % str(waves_seen))
	if not RunMap.WAVES_PER_BIOME in waves_seen:
		_fails.append("the walk skipped the boss: %s" % str(waves_seen))

	# The save has to carry the map, or a quit mid-biome silently rewinds it.
	mg.save_run()
	var saved: Dictionary = RunSave.read_data()
	if not saved.has("run_map") or saved["run_map"].is_empty():
		_fails.append("save_run did not write the map")
	else:
		var restored := RunMap.from_dict(saved["run_map"])
		if restored.rows.size() != map.rows.size():
			_fails.append("restored map has %d rows, original had %d"
				% [restored.rows.size(), map.rows.size()])
		if restored.current_id != map.current_id:
			_fails.append("restored map stands on %s, original on %s"
				% [restored.current_id, map.current_id])
		# A reward stub must come back as the same TYPE and richness — the map
		# promised it before the save.
		for r in range(map.rows.size()):
			for c in range(map.rows[r].size()):
				var before: Dictionary = map.rows[r][c].get("reward", {})
				var after: Dictionary = restored.rows[r][c].get("reward", {})
				if before.is_empty():
					continue
				if int(before.get("type", -1)) != int(after.get("type", -2)):
					_fails.append("%s reward type changed across the save"
						% map.rows[r][c]["id"])
				var bi: EquipmentItem = before.get("item")
				var ai: EquipmentItem = after.get("item")
				if bi and ai and int(bi.rarity) != int(ai.rarity):
					_fails.append("%s item rarity changed across the save (%d -> %d)"
						% [map.rows[r][c]["id"], bi.rarity, ai.rarity])
	_checked += 1

	# ── THE FILLER PIN: same node = same fight, new run = new fight ───────────
	# Veteran/Brutal waves top the authored base up with random filler. Before
	# 2026-09-20 that rolled on every call, so the map's node card generated one
	# wave and the fight generated a different one — the card was advertising a
	# roster the round would not deliver. The node now carries a wave_seed minted
	# from the RUN's rng, and both paths generate through it.
	#
	# Both halves are asserted, because each alone is satisfiable by a bug:
	# a hardcoded seed passes the "stable" half while destroying variety, and the
	# old unseeded code passes the "varies" half while lying to the player.
	var pinned: Dictionary = {}
	for row_p in map.rows:
		for n_p in row_p:
			if not RunMap.is_battle_node(n_p):
				continue
			if int(n_p.get("difficulty", 0)) == WaveScaler.Difficulty.NORMAL:
				continue    # Normal has no filler to pin
			if int(n_p.get("wave_seed", 0)) == 0:
				_fails.append("%s carries no wave_seed" % n_p["id"])
				continue
			pinned[String(n_p["id"])] = n_p
	if pinned.is_empty():
		_fails.append("no Veteran/Brutal node on the map to check the filler pin")
	for id_p in pinned:
		var n2: Dictionary = pinned[id_p]
		var a: Dictionary = _roster(mg, n2)
		var b: Dictionary = _roster(mg, n2)
		if a != b:
			_fails.append("%s rerolled its wave: %s then %s" % [id_p, str(a), str(b)])
			break

	# A SECOND run must not inherit the first run's cast. Same biome, same node
	# coordinates, different run seed — the rosters have to diverge somewhere.
	var other := RunMap.generate(map.biome, 999331, false)
	var differs: bool = false
	var compared: int = 0
	for id_p in pinned:
		var n3: Dictionary = other.node_by_id(String(id_p))
		if n3.is_empty() or not RunMap.is_battle_node(n3):
			continue
		if int(n3.get("difficulty", -1)) != int(pinned[id_p].get("difficulty", -2)):
			continue    # different tier there; not a like-for-like comparison
		compared += 1
		if _roster(mg, n3) != _roster(mg, pinned[id_p]):
			differs = true
			break
	if compared > 0 and not differs:
		_fails.append("a second run produced an identical cast on all %d comparable "
			% compared + "nodes — the seed is not per-run")

	if _fails.is_empty():
		print("MAP_SMOKE: PASSED (%d steps, %d/%d waves fought in order)"
			% [_checked, waves_seen.size(), RunMap.WAVES_PER_BIOME])
		get_tree().quit(0)
	else:
		print("MAP_SMOKE: FAILED")
		for f in _fails:
			print("  - %s" % f)
		get_tree().quit(1)

# The wave a node would field, as a {code: count} bag. Generated through the
# node's own seed, which is the whole point of the check above — this is the
# same call the node card and the committed fight both make.
func _roster(mg, node: Dictionary) -> Dictionary:
	var spec: Array = mg._wave_director.generate_wave_spec(
		int(node.get("round", 0)), int(node.get("difficulty", 0)),
		mg.battle_grid.grid_width, -1, int(node.get("wave_seed", 0)))
	var bag: Dictionary = {}
	for e: Dictionary in spec:
		var c: String = String(e.get("code", e.get("type", "?")))
		bag[c] = int(bag.get(c, 0)) + 1
	return bag
