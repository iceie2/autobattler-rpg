extends Node
# ══════════════════════════════════════════════════════════════════════════════
# RUN RECAP through the REAL main_game (2026-10-07). A real run, real fights:
#   1. a new run starts a complete, empty record (the opening stop noted)
#   2. a won fight is frozen once: round, outcome, hero rows, defeats == the
#      run-kill delta, the map icon
#   3. a save taken mid-ceremony carries the record + hero uids; RESUMING it
#      replays that fight, and the replay REPLACES the entry (no duplicate)
#   4. a utility stop is kept on the route with its real wave slot
#   5. a lost fight ends the run: the terminal recap is written exactly once,
#      after the run save is cleared, and reloads from disk
#   2b. the real fight's damage breakdown sums to each hero's Damage dealt
#   6. a save written before the recorder existed resumes as PARTIAL history
#      ("recorded from wave X"), never as zeros
# It drives the real main_game, which writes run/progression saves, run history,
# telemetry and the terminal recap, so it runs ONLY in a disposable profile:
#   APPDATA=<scratch>/recap/isolated-profile \
#     godot --headless --fixed-fps 60 --path . res://scenes/tools/run_recap_integration.tscn
# Prints RUN_RECAP_INTEGRATION: ALL PASS. Exit 0 pass, 1 fail, 2 refused.
# ══════════════════════════════════════════════════════════════════════════════

var failures: Array = []
var _mg: Node = null

func check(ok: bool, label: String) -> void:
	print("  %s: %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		failures.append(label)

func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _boot() -> Node:
	var mg = load("res://scenes/main_game.tscn").instantiate()
	add_child(mg)
	await _frames(30)
	return mg

func _drop(mg) -> void:
	if is_instance_valid(mg):
		mg.queue_free()
	await _frames(10)

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/recap/isolated-profile/"):
		push_error("Refusing the run-recap integration test outside its disposable profile")
		get_tree().quit(2)
		return
	RunSave.clear()
	RunRecap.clear_terminal()
	RunSave.resume_on_start = false

	# ── 1. new run ───────────────────────────────────────────────────────────
	var mg = await _boot()
	check(mg._run_recap != null and mg._run_recap.fights.is_empty() and not mg._run_recap.is_partial(),
		"a new run starts a complete, empty record")
	check(mg._run_recap.route.size() == 1 and mg._run_recap.route[0]["kind"] == "node",
		"the opening relic stop is on the route")
	mg._on_relic_chosen(Relic.by_id("d_gold"))
	await _frames(5)
	if not mg._hero_shop._card_btns.is_empty():
		mg._hero_shop._card_btns[0].emit_signal("pressed")
	await _frames(5)
	if mg.player_units.is_empty():
		check(false, "a starting hero is on the board")
		_finish()
		return

	# ── 2. a won fight ───────────────────────────────────────────────────────
	var n1: Dictionary = _next(mg, true)
	mg._on_map_node_chosen(n1)
	await _frames(5)
	var key1 := RunRecap.encounter_key(String(n1["id"]), int(n1["round"]))
	check(not mg._run_recap.route_entry(key1).is_empty(), "the chosen fight is on the route before it starts")
	var kills0: int = mg._run_kills
	await _fight(mg, true)
	check(mg._run_recap.fights.size() == 1, "the won fight is recorded once")
	if mg._run_recap.fights.is_empty():
		_finish()
		return
	var f1: Dictionary = mg._run_recap.fights[0]
	var hero: UnitBase = mg.player_units[0] if not mg.player_units.is_empty() else mg._downed_heroes[0]
	var uid: int = int(hero.get_meta("recap_uid", 0))
	check(uid > 0, "the hero carries a run identity (uid %d)" % uid)
	check(int(f1["round"]) == int(n1["round"]) and bool(f1["won"]) and String(f1["key"]) == key1,
		"entry: round %d, won, keyed to its node" % int(f1["round"]))
	var row: Array = []
	for r in f1["rows"]:
		if int(r[0]) == uid:
			row = r
	check(not row.is_empty() and int(row[1]) > 0, "the hero's recorded damage is real (%s)" % str(row))
	check(int(f1["defeat_total"]) == mg._run_kills - kills0,
		"defeat tally %d == run-kill delta %d" % [int(f1["defeat_total"]), mg._run_kills - kills0])
	check(mg._run_recap.kill_order(0).size() == int(f1["defeat_total"]) and (f1["kill_seq"] as Array).size() == int(f1["defeat_total"]),
		"the real fight kept its kill order: one entry per defeat (%d)" % int(f1["defeat_total"]))
	check(f1.has("bench"), "the fight records who sat on the bench")
	check(String(mg._run_recap.route_entry(key1)["icon"]) != "" or int(n1["type"]) == RunMap.NodeType.BATTLE,
		"the route keeps the map's creature icon for the node")
	check(bool(f1["available"]) and not mg._run_recap.report_for(key1).is_empty(),
		"the frozen per-fight report is stored and reopens")
	# The damage breakdown of a REAL fight adds up to each hero's Damage dealt.
	var dsplit = f1.get("dmg_split")
	var split_rows: Array = dsplit if dsplit is Array else []
	var split_ok: bool = dsplit is Array
	var split_note: Array = []
	for r in f1["rows"]:
		var sum := 0
		for sr in split_rows:
			if int(sr[0]) == int(r[0]):
				for c in (sr as Array).slice(1):
					sum += int(c)
		split_ok = split_ok and sum == int(r[1])
		split_note.append("uid %d: %d of %d" % [int(r[0]), sum, int(r[1])])
	check(split_ok, "a real fight's damage breakdown sums to each hero's Damage (%s)" % ", ".join(split_note))
	print("  MEASURED: real fight split rows [uid, auto p/m/t, skill p/m/t, ult p/m/t, dot p/m/t, summon p/m/t, other p/m/t] = %s" % str(split_rows))
	var token1 := String(f1["token"])

	# ── 3. save mid-ceremony, resume, replay ─────────────────────────────────
	mg.save_run()
	var saved: Dictionary = RunSave.read_data()
	var srec: Dictionary = saved.get("run_recap", {})
	check(srec.get("fights", []).size() == 1, "the run save carries the record")
	var uids_saved: Array = []
	for hd in saved.get("heroes", []):
		uids_saved.append(int(hd.get("recap_uid", 0)))
	check(uids_saved.has(uid), "hero identity is saved with the hero")
	var save_bytes: int = var_to_str(srec).length()
	print("  MEASURED: record after 1 fight = %d bytes in the run save" % save_bytes)
	await _drop(mg)
	RunSave.resume_on_start = true
	mg = await _boot()
	check(mg._run_recap != null and mg._run_recap.fights.size() == 1
		and String(mg._run_recap.fights[0]["token"]) == token1, "resume restores the same record")
	var resumed_uids: Array = []
	for u in mg.player_units + mg.bench_units:
		resumed_uids.append(int(u.get_meta("recap_uid", 0)))
	check(resumed_uids.has(uid), "the resumed hero keeps uid %d" % uid)
	# The save was mid-ceremony, so the run resumes into round 1's prep again.
	await _fight(mg, true)
	check(mg._run_recap.fights.size() == 1 and String(mg._run_recap.fights[0]["token"]) != token1,
		"the replayed fight REPLACED its entry (still 1 fight)")
	var fight_stops := 0
	for e in mg._run_recap.route:
		if String(e["key"]) == key1:
			fight_stops += 1
	check(fight_stops == 1, "the route holds that fight once")
	await _settle_to_map(mg)

	# ── 4. walk on (winning) until a row offers a utility stop, then take it ──
	var util: Dictionary = _next(mg, false)
	var won_extra := 0
	while util.is_empty() and won_extra < 4:
		var nb: Dictionary = _next(mg, true)
		if nb.is_empty():
			break
		mg._on_map_node_chosen(nb)
		await _frames(5)
		await _fight(mg, true)
		await _settle_to_map(mg)
		won_extra += 1
		util = _next(mg, false)
	if not util.is_empty():
		var fights_before_util: int = mg._run_recap.fights.size()
		mg._on_map_node_chosen(util)
		await _frames(5)
		_close_modals(mg)
		var ukey := "node:%s@%d" % [String(util["id"]), int(util["round"])]
		var ue: Dictionary = mg._run_recap.route_entry(ukey)
		check(not ue.is_empty() and int(ue["round"]) == int(util["round"]) and String(ue["kind"]) == "node",
			"utility stop kept on the route at its real wave slot (%d)" % int(util["round"]))
		check(mg._run_recap.fights.size() == fights_before_util, "a utility stop adds no fight")
	else:
		print("  note: no utility node within 4 rows of this map; the skipped-wave stop is covered by run_recap_smoke")
	var n2: Dictionary = _next(mg, true)
	if n2.is_empty():
		check(false, "a next fight is reachable")
		_finish()
		return
	mg._on_map_node_chosen(n2)
	await _frames(5)

	# ── 5. the losing fight ends the run ─────────────────────────────────────
	check(mg._run_recap_screen == null, "no recap screen during the run (fights, deaths and revivals never open it)")
	var early: bool = await mg._show_run_recap()
	check(not early and mg._run_recap_screen == null, "the recap refuses to open before the run's result is final")
	var hist0: int = RunHistory.entries().size()
	await _fight(mg, false)
	await _frames(10)
	check(not RunSave.exists(), "the run save is cleared at the end")
	check(RunHistory.entries().size() == hist0 + 1, "run history got its one entry")
	check(mg._run_recap.is_final() and mg._run_recap.outcome == "defeat", "the record is final: defeat")
	var n_f: int = mg._run_recap.fights.size()
	check(n_f == 2 + won_extra and not bool(mg._run_recap.fights[n_f - 1]["won"]),
		"%d fights recorded, the last one lost" % n_f)
	if not util.is_empty():
		check(int(mg._run_recap.fights[n_f - 1]["round"]) > int(util["round"]),
			"the fight after the utility stop keeps its real, later wave number")
	check(mg._run_recap.defeat_total() <= mg._run_kills,
		"recorded defeats %d never exceed run kills %d" % [mg._run_recap.defeat_total(), mg._run_kills])
	var disk: RunRecap = RunRecap.load_terminal()
	check(disk != null and disk.outcome == "defeat" and disk.fights.size() == n_f and disk.run_id == mg._run_recap.run_id,
		"the terminal recap is on disk and reloads")
	var term_bytes := 0
	var tf := FileAccess.open(RunRecap.TERMINAL_PATH, FileAccess.READ)
	if tf:
		term_bytes = tf.get_length()
		tf.close()                        # Windows cannot replace a file that is open
	print("  MEASURED: terminal recap file = %d bytes for %d fights" % [term_bytes, mg._run_recap.fights.size()])
	# A second finish is ignored (the record is final).
	var ended: String = mg._run_recap.ended_at
	mg._recap_finish_run(true)
	check(mg._run_recap.outcome == "defeat" and mg._run_recap.ended_at == ended, "the terminal result is set exactly once")

	# ── 5b. the terminal screen: once, after the save; the final fight opens ──
	var screen: RunRecapScreen = mg._run_recap_screen
	check(screen != null and is_instance_valid(screen) and screen.visible, "the run recap opened at the end of the run")
	check(not mg._game_over_screen.visible, "the old result panel stays hidden behind it")
	var again: bool = await mg._show_run_recap()
	var screens := 0
	for c in mg.get_children():
		if c is RunRecapScreen:
			screens += 1
	check(again and screens == 1, "triggering again opens nothing new (%d screen)" % screens)
	if screen != null:
		screen.skip()
		await _frames(3)
		check(screen.mode == RunRecapScreen.Mode.OVERVIEW and screen.selected_key() == String(mg._run_recap.fights[n_f - 1]["key"]),
			"Skip lands on the overview with the final fight selected")
		check(screen.open_fight(screen.selected_key()) and screen.fight_view() != null,
			"the losing fight opens in the per-fight report from its frozen record")
		if screen.fight_view():
			var rep: Dictionary = screen.fight_view()._report
			check(not bool(rep["won"]) and rep["heroes"].size() >= 1 and int(rep["heroes"][0]["deaths"]) >= 1,
				"that report is the real lost fight (hero fell)")
		screen.close_fight()
		await _frames(2)
		check(screen.mode == RunRecapScreen.Mode.OVERVIEW, "Back returns to the overview")
		check(screen.open_hero(uid) and screen.hero_open() and screen.hero_detail() != null,
			"a hero's bar opens its damage breakdown")
		screen.close_hero()
		await _frames(2)
		check(not screen.hero_open() and screen.mode == RunRecapScreen.Mode.OVERVIEW, "the breakdown closes back to the overview")
	await _drop(mg)

	# ── 6. legacy save without a record ──────────────────────────────────────
	RunSave.resume_on_start = false
	mg = await _boot()
	mg._on_relic_chosen(Relic.by_id("d_gold"))
	await _frames(5)
	if not mg._hero_shop._card_btns.is_empty():
		mg._hero_shop._card_btns[0].emit_signal("pressed")
	await _frames(5)
	var n3: Dictionary = _next(mg, true)
	mg._on_map_node_chosen(n3)
	await _frames(5)
	mg.save_run()
	var legacy: Dictionary = RunSave.read_data()
	legacy.erase("run_recap")
	legacy["round"] = 12                  # pretend: a pre-recorder run at wave 12's prep
	legacy.erase("run_map")               # ...from before the run map, too
	legacy.erase("map_node_id")
	RunSave.write_data(legacy)
	await _drop(mg)
	RunSave.resume_on_start = true
	mg = await _boot()
	check(mg._run_recap != null and mg._run_recap.is_partial() and mg._run_recap.history_before_unavailable,
		"a pre-recorder save resumes as PARTIAL history")
	check(mg._run_recap.coverage_from_round >= 12 and mg._run_recap.fights.is_empty(),
		"recorded from wave %d; nothing invented before it" % mg._run_recap.coverage_from_round)
	await _drop(mg)
	RunSave.clear()
	_finish()

# ── helpers ──────────────────────────────────────────────────────────────────

func _next(mg, battle: bool) -> Dictionary:
	for n in mg._run_map.available_next():
		if RunMap.is_battle_node(n) == battle:
			return n
	return {}

func _fight(mg, win: bool) -> void:
	var prev_token: String = mg._run_recap.last_token
	for u in mg.player_units:
		if win:
			u.max_hp = 90000; u.current_hp = 90000
			u.attack_damage = 6000; u.magic_power = 6000
		else:
			u.max_hp = 4; u.current_hp = 4
			u.attack_damage = 1; u.magic_power = 1
	mg._ready_nudged = true
	mg._on_ready_pressed()
	await _frames(2)
	mg._pending_round_reward = {}         # no reward modal in the way of the next step
	mg.auto_battle_manager.set_time_scale(4.0)
	var guard := 0
	while guard < 20000:
		await get_tree().process_frame
		guard += 1
		var tok := String(mg.auto_battle_manager.last_recap.get("token", ""))
		# Done once THIS battle's frozen token is the one the record finalised.
		if not mg.auto_battle_manager.battle_active and tok != "" and tok != prev_token \
				and mg._run_recap.last_token == tok:
			break
	if guard >= 20000:
		check(false, "the fight finished within the frame budget")
	await _frames(3)

# Answer the post-fight modals until the map is back.
func _settle_to_map(mg) -> void:
	var guard := 0
	while guard < 3000 and not mg._run_map_screen.visible:
		await get_tree().process_frame
		guard += 1
		_close_modals(mg)
	check(mg._run_map_screen.visible, "the post-fight flow returns to the map")

func _close_modals(mg) -> void:
	if mg._level_up_screen and mg._level_up_screen.visible:
		mg._level_up_screen.visible = false
		mg._level_up_screen.all_done.emit()
	if mg._reward_choice_screen and mg._reward_choice_screen.visible:
		mg._reward_choice_screen.visible = false
		mg._reward_choice_screen.chosen.emit(0)
	if mg._round_reward_screen and mg._round_reward_screen.visible:
		mg._round_reward_screen.visible = false
		mg._round_reward_screen.done.emit()
	for modal in [mg._event_panel, mg._shop_screen, mg._camp_screen, mg._relic_screen]:
		if modal and modal.visible:
			modal.visible = false

func _finish() -> void:
	print("RUN_RECAP_INTEGRATION: %s" % ("ALL PASS" if failures.is_empty()
		else "%d FAILED -> %s" % [failures.size(), ", ".join(failures)]))
	get_tree().quit(0 if failures.is_empty() else 1)
