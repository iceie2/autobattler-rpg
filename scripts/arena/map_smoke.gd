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
		# The cursor is inherited from the hero card that just closed. Merely
		# appearing over a node must not count as an intentional hover.
		if mg._run_map_screen._hover_armed:
			_fails.append("map hover armed before the player moved the mouse")
		if mg._run_map_screen._tip.visible:
			_fails.append("a node dossier opened from the inherited hero-card cursor")
		_checked += 11

	# ── The dossier must be transparent to the mouse ─────────────────────────
	# The card is centred and large, so it lies over the very nodes you hover.
	# If ANY Control in it stops the pointer, the node beneath fires
	# mouse_exited, the card hides, the node re-enters, and the card flickers on
	# every pixel of movement. That's invisible in a screenshot, so it's checked
	# here: after a hover, every Control in the card must be MOUSE_FILTER_IGNORE.
	var hover_node: Dictionary = {}
	for row in map.rows:
		for n in row:
			if RunMap.is_battle_node(n):
				hover_node = n
				break
		if not hover_node.is_empty():
			break
	if not hover_node.is_empty():
		mg._run_map_screen._hover_armed = true
		mg._run_map_screen._on_node_hover(hover_node, true)
		await get_tree().process_frame
		var blockers: Array[String] = []
		_collect_mouse_blockers(mg._run_map_screen._tip, blockers)
		if not blockers.is_empty():
			_fails.append("dossier catches the mouse (hover flicker): %s"
				% ", ".join(blockers))
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

# Every Control in the subtree that would swallow a mouse event.
func _collect_mouse_blockers(n: Node, out: Array[String]) -> void:
	if n is Control and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		out.append("%s(%s)" % [n.name, n.get_class()])
	for child in n.get_children():
		_collect_mouse_blockers(child, out)
