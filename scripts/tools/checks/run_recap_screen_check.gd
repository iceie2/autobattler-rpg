extends Node
# ══════════════════════════════════════════════════════════════════════════════
# RUN RECAP SCREEN behaviour (2026-10-07), on SYNTHETIC recaps built through the
# real RunRecap API (the capture harness's fixtures). Headless; checks logic and
# state, not pixels (see run_recap_capture for the images):
#   * pacing totals (1/5/30/100 fights), first step, floor, ending reserve
#   * Skip from frame one, early / mid / final pause / reveal, by button, Esc and
#     controller Back; idempotent; overview_reached exactly once; final values
#   * reduced motion opens the finished overview; the main menu's LAST RUN
#     replays the journey from the beginning (Esc skips, Esc again closes)
#   * the chart's bars never shrink during the journey and land on prefix totals
#   * departures: icons leave, are tracked apart from the defeat tally
#   * overview replay: back / forward (keys, d-pad, buttons) move the selected
#     stop = replay point; chart, life states and parade follow it; Play steps
#     forward and stops at the end; measure keys / bumpers switch the chart
#   * the defeat parade: wave by wave, in kill order; scrubbing hides later waves
#   * open with Enter / A or a second click; Back restores selection, zoom,
#     measure and parade scroll; non-fight stops / missing reports open nothing
#   * dense routes: no overlapping hit targets; a click zooms in first
#   * the per-fight view opened from history carries historical labels only
#   * the parade is there from wave 1: each icon falls into it, its wave's
#     defeats appear when it lands (journey and forward steps; reduced motion
#     skips the fall)
#   * only recruited heroes have a column; Total stacks the three measures;
#     clicking a bar opens the hero card (journey holds, values = the bar's,
#     rows sum to the damage); Esc / a click outside closes only the card
# It writes user://settings.json (theme / reduced-motion toggles), so:
#   APPDATA=<scratch>/recap/isolated-profile \
#     godot --headless --path . res://scenes/tools/run_recap_screen_check.tscn
# Prints RUN_RECAP_SCREEN_CHECK: ALL PASS. Exit 0 pass, 1 fail, 2 refused.
# ══════════════════════════════════════════════════════════════════════════════

const Fixtures = preload("res://scripts/tools/captures/run_recap_capture.gd")

var failures: Array = []
var fx

func check(ok: bool, label: String) -> void:
	print("  %s: %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		failures.append(label)

func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("isolated-profile"):
		push_error("run_recap_screen_check: refusing to run outside a disposable isolated-profile")
		get_tree().quit(2)
		return
	fx = Fixtures.new()
	fx._init_types()
	UITheme.set_reduced_motion(false)
	_test_pacing()
	await _test_skip_paths()
	await _test_reduced_motion_and_menu()
	await _test_bars_and_departures()
	await _test_replay_controls()
	await _test_parade()
	await _test_open_and_back()
	await _test_dense_targets()
	await _test_parade_landing()
	await _test_recruits_total_and_cards()
	UITheme.set_reduced_motion(false)
	fx.free()
	_finish()

func _screen(recap: RunRecap, context := "terminal", overview := false) -> RunRecapScreen:
	var s := RunRecapScreen.new()
	add_child(s)
	s.present(recap, context, overview)
	s.set_process(false)          # the test owns the clock
	return s

func _drop(s: RunRecapScreen) -> void:
	if is_instance_valid(s):
		s.queue_free()
	await _frames(2)

func _action(name: String) -> void:
	var a := InputEventAction.new()
	a.action = name
	a.pressed = true
	Input.parse_input_event(a)
	await _frames(2)
	var r := InputEventAction.new()
	r.action = name
	r.pressed = false
	Input.parse_input_event(r)
	await _frames(1)

func _keypress(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e

func _pad(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	return e

func _bar(s: RunRecapScreen, uid: int, m: int = 0) -> float:
	return s._chart.value_of(uid, m)

# ── pacing ───────────────────────────────────────────────────────────────────
func _test_pacing() -> void:
	print("[pacing]")
	for pair in [[1, 4.2], [5, 8.0], [30, 15.0], [100, 24.0]]:
		var kinds: Array = []
		for i in range(int(pair[0])):
			kinds.append("boss" if (i + 1) % 10 == 0 else ("elite" if (i + 1) % 10 == 5 else ""))
		var p := RecapPacing.plan(kinds)
		var d: Array = p["durations"]
		var mn := 99.0
		for x in d:
			mn = minf(mn, float(x))
		check(absf(float(p["total"]) - float(pair[1])) < 0.05,
			"%d fights -> %.2fs total (target %.1fs)" % [pair[0], float(p["total"]), pair[1]])
		check(float(d[0]) > 1.19, "%d fights: first fight %.2fs" % [pair[0], float(d[0])])
		if int(pair[0]) >= 30:
			check(mn >= 0.10 and mn <= 0.15, "%d fights: fastest step %.3fs (0.10-0.15)" % [pair[0], mn])
		check(float(p["final_pause"]) + float(p["reveal"]) >= 2.5, "%d fights: ending time reserved" % pair[0])
	var one := RecapPacing.plan([""])
	check(float(one["total"]) < 5.0, "a one-fight run is short, with no padding (%.2fs)" % float(one["total"]))

# ── skip ─────────────────────────────────────────────────────────────────────
func _test_skip_paths() -> void:
	print("[skip]")
	for case in [["frame one / button", 0.0, "button"], ["early / Esc", 0.6, "esc"],
			["mid / controller Back", -0.5, "pad"], ["final pause / Esc", -1.0, "esc"],
			["reveal / button", -2.0, "button"]]:
		var recap: RunRecap = fx._fixture("thirty")
		var s := _screen(recap)
		var reached := [0]
		s.overview_reached.connect(func(): reached[0] += 1)
		var fe: float = float(s._plan["fights_end"])
		var t: float = float(case[1])
		if t == -0.5: t = fe * 0.5
		elif t == -1.0: t = fe + float(s._plan["final_pause"]) * 0.5
		elif t == -2.0: t = fe + float(s._plan["final_pause"]) + float(s._plan["reveal"]) * 0.5
		s.set_time(t)
		check(s.is_journey() and s._skip_btn.visible and not s._skip_btn.disabled,
			"%s: Skip is there and actionable at t=%.2fs" % [case[0], t])
		match String(case[2]):
			"button": s._skip_btn.pressed.emit()
			"esc": s._input(_keypress(KEY_ESCAPE))
			"pad": s._input(_pad(JOY_BUTTON_BACK))
		check(not s.is_journey() and s.mode == RunRecapScreen.Mode.OVERVIEW, "%s: lands on the overview" % case[0])
		s.skip()
		s._input(_keypress(KEY_ESCAPE))
		check(reached[0] == 1 and s.mode == RunRecapScreen.Mode.OVERVIEW,
			"%s: a second Skip / Esc is harmless; overview_reached fired once" % case[0])
		check(s._end_btn.visible and s._end_btn.text == "Return to Main Menu" and not s._skip_btn.visible
			and s._transport.visible, "%s: replay controls + the existing next step; Skip never starts a run" % case[0])
		var fin: Dictionary = recap.final_totals()
		var ok := true
		for h in recap.fighting_heroes():
			for m in range(3):
				ok = ok and is_equal_approx(_bar(s, int(h["uid"]), m), float(fin[int(h["uid"])][m]))
		check(ok, "%s: the chart shows every hero's final totals" % case[0])
		check(s._trophies.visible and s._parade.upto == recap.fights.size() - 1 and is_equal_approx(s._parade.fill, 1.0)
			and s._parade.total_shown() == recap.defeat_total() and not s._sfx.playing,
			"%s: the whole parade is shown, audio stopped" % case[0])
		await _drop(s)

func _test_reduced_motion_and_menu() -> void:
	print("[reduced motion, reopening]")
	UITheme.set_reduced_motion(true)
	var s := _screen(fx._fixture("five"))
	check(s.mode == RunRecapScreen.Mode.OVERVIEW, "reduced motion opens the finished overview directly")
	await _drop(s)
	UITheme.set_reduced_motion(false)
	# The main menu's LAST RUN entry, for real: it replays the journey from the
	# beginning (owner, 2026-10-08), from the terminal recap on disk.
	RunRecap.save_terminal(fx._fixture("five"))
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await _frames(3)
	menu._on_last_run()
	await _frames(1)
	var m: RunRecapScreen = null
	for c in menu.get_children():
		if c is RunRecapScreen:
			m = c
	check(m != null and m.is_journey() and m.journey_time() < 0.1 and m._parade.total_shown() == 0,
		"LAST RUN plays the journey from the beginning (t=%.2fs)" % (m.journey_time() if m else -1.0))
	if m:
		m.set_process(false)
		m._input(_keypress(KEY_ESCAPE))
		check(m.mode == RunRecapScreen.Mode.OVERVIEW and m._end_btn.text == "Close",
			"menu context: Esc skips to the overview, which offers Close")
		var closed := [false]
		m.closed.connect(func(): closed[0] = true)
		m._input(_keypress(KEY_ESCAPE))
		check(closed[0], "menu context: Esc again closes the recap")
	UITheme.set_reduced_motion(true)
	menu._on_last_run()
	await _frames(1)
	var rm: RunRecapScreen = null
	for c in menu.get_children():
		if c is RunRecapScreen and is_instance_valid(c) and c.visible:
			rm = c
	check(rm != null and rm.mode == RunRecapScreen.Mode.OVERVIEW, "with reduced motion, LAST RUN opens the overview")
	UITheme.set_reduced_motion(false)
	RunRecap.clear_terminal()
	menu.queue_free()
	await _frames(2)

func _test_bars_and_departures() -> void:
	print("[journey: bars, departures]")
	var recap: RunRecap = fx._fixture("thirty")
	var s := _screen(recap)
	var prefix: Array = recap.prefix_totals()
	var uid: int = int(recap.fighting_heroes()[0]["uid"])
	var last := -1.0
	var mono := true
	var t := 0.0
	var landed := true
	var starts: Array = s._plan["starts"]
	var durs: Array = s._plan["durations"]
	while t < float(s._plan["fights_end"]):
		s.set_time(t)
		var v: float = _bar(s, uid)
		mono = mono and v >= last - 0.001
		last = v
		t += 0.05
	for i in [0, 5, 12]:
		s.set_time(float(starts[i]) + float(durs[i]) * 0.97)
		landed = landed and is_equal_approx(_bar(s, uid), float((prefix[i] as Dictionary).get(uid, [0, 0, 0])[0]))
	check(mono, "cumulative damage never shrinks during the journey")
	check(landed, "after each fight the bar equals that fight's prefix total")
	s.set_time(float(starts[1]) + 0.04)
	check(s._route.departed.has(int(s._step_stop[0])), "the first encounter's icon has departed")
	check(not s._route.departed.has(int(s._step_stop[1])), "the current encounter has not")
	var defeats_before := recap.defeat_total()
	s.set_time(float(starts[6]))
	check(recap.defeat_total() == defeats_before, "departed icons never add to the defeat tally")
	await _drop(s)

# ── overview replay ──────────────────────────────────────────────────────────
func _test_replay_controls() -> void:
	print("[overview replay: back / play / forward, measure]")
	var recap: RunRecap = fx._fixture("thirty")
	var s := _screen(recap)
	s.skip()
	await _frames(2)
	var last_stop: int = s._route.stops.size() - 1
	check(s.selected_index() == int(s._step_stop[recap.fights.size() - 1]),
		"the overview opens on the final fight")
	check(s._next_btn.disabled and not s._prev_btn.disabled, "at the end: forward disabled, back enabled")
	var uid: int = int(recap.fighting_heroes()[0]["uid"])
	var prefix: Array = recap.prefix_totals()
	# ← (keyboard arrow / d-pad) through the real input pipeline.
	var sel0: int = s.selected_index()
	await _action("ui_left")
	await _action("ui_left")
	var sel: int = s.selected_index()
	var pt: int = s._point_of(sel)
	check(sel == sel0 - 2, "two ui_left presses step back two stops (%d -> %d)" % [sel0, sel])
	check(pt >= 0 and is_equal_approx(_bar(s, uid), float((prefix[pt] as Dictionary).get(uid, [0, 0, 0])[0])),
		"the chart rewinds to the run as it stood at that stop")
	check(s._parade.upto == pt and s._parade.total_shown() < recap.defeat_total(),
		"the parade hides the waves after it")
	# Back to the first stop with the button, then forward with →: gains grow in.
	for _i in range(200):
		if s._prev_btn.disabled:
			break
		s._prev_btn.pressed.emit()
	check(s.selected_index() == s._first_stop() and s._prev_btn.disabled, "the back button reaches the first stop")
	var first_fight_stop: int = int(s._step_stop[0])
	while s.selected_index() < first_fight_stop:
		await _action("ui_right")
	check(s._grow_t >= 0.0 or is_equal_approx(_bar(s, uid), float((prefix[0] as Dictionary).get(uid, [0, 0, 0])[0])),
		"stepping forward onto a fight grows its gains in")
	s.overview_tick(RunRecapScreen.GROW_TIME + 0.05)
	check(is_equal_approx(_bar(s, uid), float((prefix[0] as Dictionary).get(uid, [0, 0, 0])[0])),
		"after the grow, the bar equals that fight's total")
	var st: Dictionary = s._chart.state_of(int(recap.fighting_heroes()[recap.fighting_heroes().size() - 1]["uid"]))
	check(String(st["kind"]) == "future" and String(st["text"]).begins_with("Joins W"),
		"a later joiner shows when it joins (%s)" % st["text"])
	# Play: Space steps forward every PLAY_STEP and stops at the end.
	s._input(_keypress(KEY_SPACE))
	check(s.is_playing() and s._play_btn.text == "❚❚", "Space starts the replay; the button shows pause")
	var from: int = s.selected_index()
	for _i in range(int(ceil((RunRecapScreen.PLAY_STEP * 3.0 + 0.01) / 0.02))):
		s.overview_tick(0.02)             # frame-sized ticks, as the game runs it
	check(s.selected_index() == from + 3, "the replay advances one stop per step (%d -> %d)" % [from, s.selected_index()])
	s._input(_pad(JOY_BUTTON_X))
	check(not s.is_playing(), "controller X pauses it")
	s.toggle_play()
	for _i in range(400):
		if not s.is_playing():
			break
		s.overview_tick(RunRecapScreen.PLAY_STEP)
	check(not s.is_playing() and s.selected_index() == last_stop, "a replay stops on its own at the last stop")
	s.toggle_play()
	check(s.is_playing() and s.selected_index() == s._first_stop(), "Play at the end starts over from the first stop")
	s._input(_keypress(KEY_ESCAPE))
	check(not s.is_playing() and s.mode == RunRecapScreen.Mode.OVERVIEW, "Esc pauses a replay (terminal stays open)")
	# Measure: 1 2 3 keys and the bumpers.
	s._input(_keypress(KEY_2))
	check(s._chart.metric == 1 and (s._chart._toggles[1] as Button).button_pressed, "key 2 shows protection")
	s._input(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	check(s._chart.metric == 2, "the right bumper cycles to healing")
	s._input(_pad(JOY_BUTTON_LEFT_SHOULDER))
	s._input(_keypress(KEY_1))
	check(s._chart.metric == 0, "key 1 / left bumper back to damage")
	(s._chart._toggles[2] as Button).pressed.emit()
	check(s._chart.metric == 2, "clicking a measure toggle switches the bars")
	await _drop(s)

func _test_parade() -> void:
	print("[defeat parade]")
	var recap: RunRecap = fx._fixture("thirty")
	var s := _screen(recap)
	s.skip()
	await _frames(3)
	var p: RecapDefeatParade = s._parade
	check(p._groups.size() > 0 and int(p._groups[0]["fi"]) == 0 and int(p._groups[0]["round"]) == int(recap.fights[0]["round"]),
		"the parade starts with the first wave's defeats")
	var ordered := true
	for i in range(1, p._groups.size()):
		ordered = ordered and int(p._groups[i]["round"]) > int(p._groups[i - 1]["round"])
	check(ordered, "groups run wave by wave")
	var fi := 3
	var seq: Array = recap.kill_order(fi)
	var expect_seq: Array = []
	for di in recap.fights[fi]["kill_seq"]:
		expect_seq.append(String(recap.fights[fi]["defeats"][int(di)][0]))
	check(not seq.is_empty() and seq == expect_seq, "a wave's sprites follow the recorded kill order")
	var counted := 0
	for g in p._groups:
		counted += (g["keys"] as Array).size()
	check(counted == recap.defeat_total(), "one sprite per defeat (%d), not one per type" % counted)
	await _frames(2)
	check(p._items.size() == counted, "every sprite is laid out")
	var tip := p._get_tooltip((p._items[0]["rect"] as Rect2).get_center())
	check(tip.contains("Wave %d" % int(recap.fights[0]["round"])), "hovering a sprite names it and its wave: %s" % tip)
	# Old records (no kill order kept) still show every defeat, grouped by type.
	recap.fights[fi]["kill_seq"] = []
	var fallback: Array = recap.kill_order(fi)
	check(fallback.size() == seq.size() and fallback[0] == String(recap.fights[fi]["defeats"][0][0]),
		"without a recorded order, the wave still shows every defeat (by type)")
	await _drop(s)

func _test_open_and_back() -> void:
	print("[open a fight, back]")
	var recap: RunRecap = fx._fixture("thirty")
	var s := _screen(recap)
	s.skip()
	await _frames(2)
	var vp := get_viewport()
	var fight_key := String(recap.fights[recap.fights.size() / 2]["key"])
	s._select(fight_key)
	s._route.set_zoom_at(s._route.zoom * 2.0, s._route.size * 0.5)
	s._cam_follow = false
	s._chart.set_metric(1)
	s._parade_scroll.scroll_vertical = 0
	await _frames(2)
	var zoom_before: float = s._route.zoom
	var cam_before: Vector2 = s._route.cam
	var fo := vp.gui_get_focus_owner()
	if fo:
		fo.release_focus()
	await _action("ui_accept")
	check(s.mode == RunRecapScreen.Mode.FIGHT and s.fight_view() != null, "Enter / A opens the selected battle's report")
	if s.fight_view():
		var labels: Array = []
		_collect(s.fight_view(), labels)
		var joined := " | ".join(labels)
		check(joined.contains("WAVE") and joined.contains("THIS BATTLE") and not joined.contains("RUN TOTALS")
			and not joined.contains("CRYSTALS EARNED") and not joined.contains("FINAL BATTLE"),
			"historical labels: this battle only, no run totals or crystals")
		check(s.fight_view()._button.text.contains("Back to Run Overview"), "its button returns to the overview")
		check(s.fight_view()._report == recap.report_for(fight_key), "the view shows that fight's frozen report")
	s._input(_pad(JOY_BUTTON_BACK))
	await _frames(3)
	check(s.mode == RunRecapScreen.Mode.OVERVIEW and s.selected_key() == fight_key, "controller Back returns, selection kept")
	check(is_equal_approx(s._route.zoom, zoom_before) and s._route.cam.is_equal_approx(cam_before),
		"route zoom and pan restored")
	check(s._chart.metric == 1, "the chosen measure is kept")
	check(not (vp.gui_get_focus_owner() is Button), "no button holds focus, so Enter opens a fight again")
	# A second click on the selected node opens it; a click elsewhere selects.
	var si := s._route.stop_index(fight_key)
	s._on_route_click(si)
	check(s.mode == RunRecapScreen.Mode.FIGHT, "a second click on the selected fight opens its report")
	s.close_fight()
	await _frames(2)
	var other := si - 1 if si > 0 else si + 1
	s._on_route_click(other)
	check(s.mode == RunRecapScreen.Mode.OVERVIEW and s.selected_index() == other, "a click on another stop just selects it")
	# A side stop and a fight without a report open nothing.
	var stop_key := ""
	for st in s._route.stops:
		if String(st["kind"]) == "node":
			stop_key = String(st["key"])
	s._select(stop_key)
	check(stop_key != "" and not s.open_fight(stop_key) and s._open_btn.disabled
		and s._chips_lbl.text.contains("no battle report"), "a non-combat stop opens no report, and says why")
	recap.fights[0]["available"] = false
	var k0 := String(recap.fights[0]["key"])
	s._select(k0)
	check(not s.open_fight(k0) and s._open_btn.disabled and s._chips_lbl.text.contains("no report was recorded"),
		"a fight with no stored report opens nothing, and says it is unavailable")
	await _drop(s)

func _test_dense_targets() -> void:
	print("[dense route: hit targets]")
	var recap: RunRecap = fx._fixture("hundred")
	var s := _screen(recap)
	s.skip()
	await _frames(2)
	var rv: RecapRouteView = s._route
	s._fit_route()
	check(not rv.targets_ok() and rv.hit(rv.to_screen(rv.world_pos(20))) == -1,
		"a zoomed-out 100-fight route offers no overlapping click targets")
	var before: float = rv.zoom
	rv._click(rv.to_screen(rv.world_pos(40)))
	check(rv.zoom > before and rv.targets_ok() and rv.min_spacing() >= RecapRouteView.MIN_TARGET,
		"clicking a dense route zooms in until stops are >= 44 px apart (%.0f px)" % rv.min_spacing())
	check(rv.hit(rv.to_screen(rv.world_pos(40))) == 40, "after zooming, the stop under the cursor is the one picked")
	var reach := true
	var seen := {}
	s._select_stop(s._first_stop(), false)
	for _i in range(rv.stops.size() + 2):
		seen[s.selected_index()] = true
		s.step(1)
	for i in range(rv.stops.size()):
		reach = reach and (seen.has(i) or String(rv.stops[i]["kind"]) == "gap")
	check(reach, "forward stepping reaches every one of the %d stops" % rv.stops.size())
	check(s._prev_btn.custom_minimum_size.y >= 44.0 and s._next_btn.custom_minimum_size.y >= 44.0
		and s._play_btn.custom_minimum_size.y >= 44.0, "transport buttons are >= 44 px targets")
	await _drop(s)

# ── icons fall into the parade from wave 1 ───────────────────────────────────
func _test_parade_landing() -> void:
	print("[journey: icons fall into the parade from wave 1]")
	var recap: RunRecap = fx._fixture("thirty")
	var s := _screen(recap)
	await _frames(2)
	var starts: Array = s._plan["starts"]
	var durs: Array = s._plan["durations"]
	var fe: float = float(s._plan["fights_end"])
	s.set_time(0.05)
	check(s._trophies.visible and s._parade.upto == -1 and s._parade.total_shown() == 0,
		"the parade is on screen from the first wave, empty until a wave is left behind")
	check(s._parade_head_lbl.text.contains("so far"), "its heading counts up: %s" % s._parade_head_lbl.text)
	var dep0: float = float(starts[0]) + RunRecapScreen.DEPART_AT * float(durs[0])
	s.set_time(dep0 + RecapFlyer.SQUASH_T + RecapFlyer.HOLD_T + RecapFlyer.FALL_T * 0.5)
	check(s._flyer.flights.size() == 1 and s._parade.upto < 0,
		"the first encounter's icon is in the air; its wave is not in the parade yet")
	var fl: Dictionary = s._flyer.flights[0] if not s._flyer.flights.is_empty() else {}
	var vis := Rect2(s._parade_scroll.global_position, s._parade_scroll.size).grow(2.0)
	check(not fl.is_empty() and vis.has_point(fl["to"]) and (fl["from"] as Vector2).y < (fl["to"] as Vector2).y,
		"it falls from its route node down into the parade")
	s.set_time(dep0 + RecapFlyer.TOTAL_T + RunRecapScreen.LAND_FILL + 0.01)
	check(s._parade.upto == 0 and is_equal_approx(s._parade.fill, 1.0) and s._parade.total_shown() == recap.kill_order(0).size()
		and s._flyer.flights.is_empty(), "once it lands, wave 1's defeats are in the parade (%d)" % s._parade.total_shown())
	var mono := true
	var last := 0
	var t := 0.0
	while t < fe:
		s.set_time(t)
		mono = mono and s._parade.total_shown() >= last
		last = s._parade.total_shown()
		t += 0.04
	check(mono and last < recap.defeat_total(), "the parade only grows during the journey; the last wave is still to come")
	s.set_time(fe + 0.6)
	check(s._parade.upto == recap.fights.size() - 1 and is_equal_approx(s._parade.fill, 1.0)
		and s._parade.total_shown() == recap.defeat_total() and s._parade_head_lbl.text.begins_with("Total"),
		"the final fight's defeats join in the closing pause: the whole tally (%d)" % recap.defeat_total())
	check(recap.defeat_total() == recap.defeat_tally().reduce(func(a, d): return a + int(d["n"]), 0),
		"falling icons never add to the defeat count")
	await _drop(s)

# ── recruits, Total, hero cards ──────────────────────────────────────────────
func _card(s: RunRecapScreen) -> Dictionary:
	var labels: Array = []
	if s.hero_detail():
		_collect(s.hero_detail(), labels)
	var out := {"damage": "", "all": "", "text": " | ".join(labels)}
	for i in range(labels.size()):
		if String(labels[i]).begins_with("DAMAGE  "):
			out["damage"] = String(labels[i]).substr(8)
		if labels[i] == "All sources" and i + 4 < labels.size():
			out["all"] = labels[i + 4]
	return out

func _test_recruits_total_and_cards() -> void:
	print("[recruits, Total, hero cards]")
	var recap: RunRecap = fx._fixture("thirty")
	var pfx: Array = recap.prefix_totals()
	var s := _screen(recap)
	await _frames(2)
	var starts: Array = s._plan["starts"]
	var durs: Array = s._plan["durations"]
	# Only heroes recruited by the replay point have a column.
	s.set_time(0.05)
	var r0: int = int(recap.fights[0]["round"])
	var late := 0
	for h in recap.fighting_heroes():
		late += 1 if int(h["first_round"]) > r0 else 0
	var early_ok := true
	for h in s._chart.shown():
		early_ok = early_ok and int(h["first_round"]) <= r0
	check(late > 0 and early_ok and s._chart.shown().size() == recap.fighting_heroes().size() - late,
		"wave 1: the %d heroes recruited later have no column yet (%d shown)" % [late, s._chart.shown().size()])
	s.set_time(float(s._plan["fights_end"]) - 0.01)
	check(s._chart.shown().size() == recap.fighting_heroes().size(), "by the end every hero has joined the chart")
	# A card mid-journey: the clock holds, the bar and the card agree.
	var fi := 4
	s.set_time(float(starts[fi]) + float(durs[fi]) * 0.4)
	var uid: int = int(s._chart.shown()[0]["uid"])
	check(s.open_hero(uid) and s.hero_open() and s.is_journey(), "clicking a bar mid-journey opens that hero's card")
	await _frames(1)
	var t_open: float = s.journey_time()
	s._process(0.5)
	check(is_equal_approx(s.journey_time(), t_open), "the journey holds while the card is open")
	var want: int = int((pfx[fi] as Dictionary).get(uid, [0, 0, 0])[0])
	check(is_equal_approx(_bar(s, uid), float(want)), "the bar behind the card shows that fight completed (%d)" % want)
	var c := _card(s)
	check(c["damage"] == DefeatReportView.fmt_n(want) and c["all"] == c["damage"],
		"the card's damage (%s) and its rows' sum (%s) match the bar" % [c["damage"], c["all"]])
	check(not String(c["text"]).contains("mismatch"), "no recorder-mismatch note on a fully split record")
	s._input(_keypress(KEY_ESCAPE))
	check(not s.hero_open() and s.is_journey(), "Esc closes the card first; the journey is still running")
	s._process(0.1)
	check(s.journey_time() > t_open, "and carries on")
	# Overview: Total, a click on a column, the dim backdrop, replay point.
	s.skip()
	await _frames(2)
	s._input(_keypress(KEY_4))
	check(s._chart.metric == RecapHeroChart.TOTAL and (s._chart._toggles[3] as Button).button_pressed, "key 4 shows Total")
	var fin: Dictionary = recap.final_totals()
	var tot_ok := true
	var top := 0.0
	for h in recap.fighting_heroes():
		var u: int = int(h["uid"])
		var w: float = float(fin[u][0]) + float(fin[u][1]) + float(fin[u][2])
		tot_ok = tot_ok and is_equal_approx(s._chart.value_of(u, RecapHeroChart.TOTAL), w)
		top = maxf(top, w)
	check(tot_ok and is_equal_approx(s._chart.scale_of(RecapHeroChart.TOTAL), RecapHeroChart.axis_max(top)),
		"Total = damage + protection + healing per hero, on its own scale (%s)" % DefeatReportView.fmt_n(int(top)))
	var final_scale: float = s._chart.scale_of(0)
	s._chart.set_point(0, 1.0)
	var early_scale: float = s._chart.scale_of(0)
	check(early_scale > 0.0 and early_scale < final_scale, "rewinding to wave 1 shrinks the damage range")
	for m in range(4):
		var peak := 0.0
		for h in s._chart.shown():
			peak = maxf(peak, s._chart.value_of(int(h["uid"]), m))
		check(is_equal_approx(s._chart.scale_of(m), RecapHeroChart.axis_max(peak)), "wave 1 metric %d scales to displayed values" % m)
	s._chart.set_point(-1, 0.0)
	check(s._chart.scale_of(0) == 0.0, "before the first fight the range resets to zero")
	s._chart.set_point(0, 0.5)
	check(s._chart.scale_of(0) > 0.0 and s._chart.scale_of(0) <= early_scale, "animated partial values have their own range")
	s._chart.show_final()
	s._input(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	check(s._chart.metric == 0, "the right bumper wraps from Total to Damage")
	s._chart.set_metric(RecapHeroChart.TOTAL)
	await _frames(2)
	var plot = s._chart._plot
	var col := 1
	var hero_uid: int = int(s._chart.shown()[col]["uid"])
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(plot.GUTTER + plot.col_w() * (col + 0.5), plot.size.y * 0.5)
	plot._gui_input(ev)
	check(s.hero_open() and s._hero_uid == hero_uid, "clicking a hero's column opens its card")
	await _frames(1)
	var c2 := _card(s)
	check(c2["damage"] == DefeatReportView.fmt_n(int(fin[hero_uid][0])) and c2["all"] == c2["damage"],
		"the card shows the whole run's damage, split rows summing to it (%s)" % c2["damage"])
	var d := s.hero_detail()
	check(d != null and Rect2(Vector2.ZERO, s._size).encloses(Rect2(d.position, d.size)), "the card fits on screen")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	s._hero_layer.gui_input.emit(click)
	check(not s.hero_open(), "a click outside the card closes it")
	# Back at the first fight, later recruits are hidden again; the card follows the point.
	s._select_stop(int(s._step_stop[0]), false, false)
	var hidden_ok := true
	for h in s._chart.shown():
		hidden_ok = hidden_ok and int(h["first_round"]) <= r0
	check(hidden_ok and s._chart.shown().size() < recap.fighting_heroes().size(), "stepping back hides heroes not yet recruited")
	s.open_hero(uid)
	await _frames(1)
	check(_card(s)["damage"] == DefeatReportView.fmt_n(int((pfx[0] as Dictionary).get(uid, [0, 0, 0])[0])),
		"a card opened at an earlier stop shows the totals up to that stop")
	s.close_hero()
	# A forward step: the icon falls first, then its wave appears.
	while s._point_of(s.selected_index()) < 1:
		s.step(1)
	check(not s._ov_flight.is_empty() and s._parade.upto == 1 and is_equal_approx(s._parade.fill, 0.0),
		"stepping forward: the encounter's icon falls before its wave shows")
	s.overview_tick(0.2)
	check(s._flyer.flights.size() == 1, "the icon is in the air")
	for _i in range(30):
		s.overview_tick(0.05)
	check(s._ov_flight.is_empty() and s._flyer.flights.is_empty() and s._parade.upto == 1 and is_equal_approx(s._parade.fill, 1.0),
		"then that wave's defeats are in the parade")
	UITheme.set_reduced_motion(true)
	s.step(1)
	while s._point_of(s.selected_index()) < 2:
		s.step(1)
	check(s._ov_flight.is_empty() and s._parade.upto == 2 and is_equal_approx(s._parade.fill, 1.0),
		"reduced motion: no falling icon, the wave is simply there")
	UITheme.set_reduced_motion(false)
	s.toggle_play()
	s.open_hero(uid)
	check(not s.is_playing() and s.hero_open(), "opening a card pauses a replay")
	s._input(_keypress(KEY_ESCAPE))
	check(not s.hero_open() and s.visible and s.mode == RunRecapScreen.Mode.OVERVIEW, "Esc closes only the card")
	await _drop(s)

func _collect(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_collect(c, out)

func _finish() -> void:
	print("RUN_RECAP_SCREEN_CHECK: %s" % ("ALL PASS" if failures.is_empty()
		else "%d FAILED -> %s" % [failures.size(), ", ".join(failures)]))
	get_tree().quit(0 if failures.is_empty() else 1)
