extends Node
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# ══════════════════════════════════════════════════════════════════════════════
# Run recap screen captures (2026-10-07) from SYNTHETIC recaps. Every PNG carries
# a red "SYNTHETIC LAYOUT FIXTURE" banner and "SYNTHETIC" in its file name: these
# runs are invented through the real RunRecap API and must never be read as a
# player's results.
#
# Cases: one (1 fight, zero kills, defeat) · five (elite, event stop = skipped
# wave, death + revival) · thirty (late joins, bosses, merchants/camps, 12
# heroes) · hundred (100 fights, 20 heroes, hundreds of defeats, VICTORY) ·
# legacy (resumed pre-recorder save: recorded from wave 12).
# Shots: journey early / mid / ending pause / reveal, overview, overview with a
# selection, the per-fight view opened from history, and back again.
#
# Run (windowed - headless has no renderer):
#   APPDATA=<disposable> godot --path . res://scenes/tools/run_recap_capture.tscn
#   optional:  -- --only=hundred --size=1024x600 --theme=light
#   frame times: -- --mode=realtime [--cases=thirty,hundred] lists frames over
#   25 ms; add --split-timing=1 to pin each on warm-up / journey update / render,
#   --job-timing=1 to time every warm-up job (then the journey is pre-warmed).
# It switches themes through UITheme.set_ui_style (user://settings.json), which
# is why it refuses to run outside a disposable profile.
# ══════════════════════════════════════════════════════════════════════════════

const HERO_CLASSES := ["SHAUNA", "NEMI", "DOC", "BLOODHOUND", "SHEILDOR", "JUNE", "RIOT", "LORDEE",
	"SABLE", "STITCH", "COAL", "CROSS", "EMBER", "SEAR", "ZOLT", "REED", "VAIL", "SPORE", "PASTOR", "RUSH"]

var _rng := RandomNumberGenerator.new()
var _split_rng := RandomNumberGenerator.new()   # its own stream: the fixtures above stay as they were
var _normal_types: Array = []         # [type key, sprite path]
var _report_lines: Array = []

func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out

func _ready() -> void:
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	if not appdata.contains("isolated-profile"):
		push_error("run_recap_capture: refusing to run unless APPDATA is a disposable isolated-profile")
		get_tree().quit(2)
		return
	_init_types()
	var args := _args()
	if String(args.get("mode", "")) == "realtime":
		for c in String(args.get("cases", "one,five,thirty,hundred")).split(","):
			await _realtime(c)
		print("RUN_RECAP_CAPTURE: DONE")
		get_tree().quit(0)
		return
	if String(args.get("mode", "")) == "menu":
		await _menu()
		print("RUN_RECAP_CAPTURE: DONE")
		get_tree().quit(0)
		return
	var cases := ["one", "five", "thirty", "hundred", "legacy"]
	var sizes: Array = [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1024, 600)]
	var themes: Array = ["dark", "light"]
	if args.has("only"):
		cases = [String(args["only"])]
	if args.has("size"):
		var p := String(args["size"]).split("x")
		sizes = [Vector2i(int(p[0]), int(p[1]))]
	if args.has("theme"):
		themes = [String(args["theme"])]
	_print_pacing()
	for theme in themes:
		UITheme.set_ui_style(theme)
		for c in cases:
			for sz in sizes:
				# Smaller windows: the cases that stress layout most.
				if sz != Vector2i(1920, 1080) and not args.has("size") and not (c in ["five", "hundred", "legacy"]):
					continue
				await _shoot_case(c, theme, sz)
	for l in _report_lines:
		print(l)
	print("RUN_RECAP_CAPTURE: DONE")
	get_tree().quit(0)

# --mode=realtime: play SYNTHETIC journeys at real speed in a 1920x1080 view and
# report the wall-clock length against the plan, plus frame times (this GPU).
func _realtime(c: String) -> void:
	var recap := _fixture(c)
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	_banner(vp)
	var screen := RunRecapScreen.new()
	vp.add_child(screen)
	var tp := Time.get_ticks_usec()
	screen.present(recap, "terminal")
	print("  present() for %s took %.1f ms (building the screen, before its first frame)" % [c, (Time.get_ticks_usec() - tp) / 1000.0])
	var planned: float = screen.journey_total()
	var t0 := Time.get_ticks_usec()
	var last := t0
	var frames: Array = []
	var worst := 0.0
	var worst_at := 0.0
	var spikes: Array = []                # frames over 25 ms, for finding hitches
	# -- --split-timing=1: the harness drives the screen itself and times its two
	# per-frame jobs, so a spike can be pinned on warm-up, the journey update or
	# the rest of the frame (layout + render).
	var split: bool = _args().has("split-timing")
	if split:
		screen.set_process(false)
	if _args().has("job-timing"):
		# Every warm-up job timed one by one (this warms the screen, so the
		# journey after it is NOT a fair frame-time measurement).
		var costs: Array = []
		var by_kind := {}
		while not screen._warm_queue.is_empty():
			var job: Array = screen._warm_queue.back()
			var tj := Time.get_ticks_usec()
			screen.warm_up(1)
			var jm: float = (Time.get_ticks_usec() - tj) / 1000.0
			costs.append([jm, "%s %s" % [job[0], String(job[1]).get_file()]])
			by_kind[job[0]] = float(by_kind.get(job[0], 0.0)) + jm
		costs.sort_custom(func(x, y): return x[0] > y[0])
		print("  warm-up jobs: %d, by kind %s" % [costs.size(), str(by_kind)])
		for cj in costs.slice(0, 10):
			print("    %.1f ms  %s" % [cj[0], cj[1]])
	var w_ms := 0.0
	var a_ms := 0.0
	while screen.is_journey() and Time.get_ticks_usec() - t0 < 90_000_000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms: float = (now - last) / 1000.0
		frames.append(ms)
		if ms > worst:
			worst = ms
			worst_at = screen.journey_time()
		if ms > 25.0:
			spikes.append(("t=%.2fs %.0fms (warm %.0f, update %.0f)" % [screen.journey_time(), ms, w_ms, a_ms]) if split
				else ("t=%.2fs %.0fms" % [screen.journey_time(), ms]))
		last = now
		if split:
			var tw := Time.get_ticks_usec()
			screen.warm_up(2)
			var ta := Time.get_ticks_usec()
			screen.advance(ms / 1000.0)
			a_ms = (Time.get_ticks_usec() - ta) / 1000.0
			w_ms = (ta - tw) / 1000.0
			last = Time.get_ticks_usec() - int((ta - tw) + a_ms * 1000.0)
	var wall: float = (Time.get_ticks_usec() - t0) / 1_000_000.0
	frames.sort()
	var sum := 0.0
	for f in frames:
		sum += float(f)
	var n: int = maxi(1, frames.size())
	print("REALTIME SYNTHETIC %s: %d fights, planned %.2fs, wall-clock %.2fs, %d frames, avg %.1f ms, p95 %.1f ms, max %.1f ms (at journey t=%.2fs, fights end %.2fs)"
		% [c, recap.fights.size(), planned, wall, frames.size(), sum / n,
		float(frames[int(n * 0.95)]) if frames.size() > 0 else 0.0, float(frames[n - 1]) if frames.size() > 0 else 0.0,
		worst_at, float(screen._plan.get("fights_end", 0.0))])
	if not spikes.is_empty():
		print("  frames over 25 ms: %s" % ", ".join(spikes.slice(0, 12)))
	vp.queue_free()
	await get_tree().process_frame

# --mode=menu: a SYNTHETIC terminal recap on disk (isolated profile), the main
# menu with its LAST RUN entry, and that entry opened (overview, Close).
func _menu() -> void:
	RunRecap.save_terminal(_fixture("thirty"))
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	vp.add_child(menu)
	_banner(vp)
	for _i in range(12):
		await get_tree().process_frame
	_save(vp, "menu_dark_1920x1080_m1_last_run_entry")
	menu._on_last_run()
	for _i in range(8):
		await get_tree().process_frame
	_save(vp, "menu_dark_1920x1080_m2_last_run_opened")
	RunRecap.clear_terminal()
	vp.queue_free()
	await get_tree().process_frame

# Real enemy types with cut-out art, for SYNTHETIC trophies and route icons.
func _init_types() -> void:
	_normal_types.clear()
	for k in VisualUnit.MONSTER_SPRITE_PATHS.keys():
		var p := String(VisualUnit.MONSTER_SPRITE_PATHS[k])
		if p.contains("/normal/") and ResourceLoader.exists(p):
			_normal_types.append([String(k), p])
	_normal_types.sort_custom(func(a, b): return a[0] < b[0])

func _print_pacing() -> void:
	for n in [1, 2, 5, 12, 30, 60, 100]:
		var kinds: Array = []
		for i in range(n):
			kinds.append("boss" if (i + 1) % 10 == 0 else ("elite" if (i + 1) % 10 == 5 else ""))
		var p := RecapPacing.plan(kinds)
		var d: Array = p["durations"]
		var mn := 99.0
		for x in d:
			mn = minf(mn, float(x))
		print("PACING n=%3d total=%5.2fs (target %5.2fs) first=%.2fs min=%.3fs fights=%.2fs ending=%.1fs"
			% [n, float(p["total"]), RecapPacing.target_total(n), float(d[0]), mn,
			float(p["fights_end"]), float(p["final_pause"]) + float(p["reveal"])])

# ── one case ─────────────────────────────────────────────────────────────────
func _shoot_case(c: String, theme: String, sz: Vector2i) -> void:
	var recap := _fixture(c)
	var vp := SubViewport.new()
	vp.size = sz
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.30, 0.45, 0.22)
	vp.add_child(bg)
	var screen := RunRecapScreen.new()
	vp.add_child(screen)
	screen.present(recap, "terminal")
	screen.set_process(false)                     # the harness owns the clock
	screen.warm_up(10000)                         # what the first frames of play do
	screen._since_open = 1.0
	screen._skip_btn.modulate.a = 1.0
	screen._skip_hint.modulate.a = 1.0
	_banner(vp)
	var tag := "%s_%s_%dx%d" % [c, theme, sz.x, sz.y]
	var total: float = screen.journey_total()
	var fe: float = float(screen._plan.get("fights_end", 0.0))
	var pause: float = float(screen._plan.get("final_pause", 0.0))
	_report_lines.append("CASE %s: %d fights, %d stops, journey %.2fs" % [tag, recap.fights.size(),
		screen._route.stops.size(), total])
	if screen.is_journey():
		var shots := [["j1_early", minf(0.75, fe * 0.5)], ["j2_mid", fe * 0.55],
			["j3_end_pause", fe + pause * 0.7], ["j4_reveal", fe + pause + float(screen._plan["reveal"]) * 0.55]]
		# An encounter icon part-way through its fall into the parade.
		if recap.fights.size() > 1:
			var j: int = recap.fights.size() / 3
			var t_fall: float = float(screen._plan["starts"][j]) + RunRecapScreen.DEPART_AT * float(screen._plan["durations"][j])
			t_fall += RecapFlyer.SQUASH_T + RecapFlyer.HOLD_T + RecapFlyer.FALL_T * 0.7
			shots.insert(2, ["j2b_falling", t_fall])
		for s in shots:
			screen.set_time(float(s[1]))
			await _settle(screen)
			_save(vp, tag + "_" + String(s[0]))
		screen.advance(total + 1.0)
	_ease_overview(screen)
	await _settle(screen)
	_save(vp, tag + "_o1_overview")
	# Step back to the middle of the run: chart, states and parade follow it.
	if recap.fights.size() > 1:
		var mid_key := String(recap.fights[recap.fights.size() / 2]["key"])
		screen._select(mid_key, true)
		_ease_overview(screen)
		await _settle(screen)
		_save(vp, tag + "_o2_selected")
		screen._chart.set_metric(1)
		await _settle(screen)
		_save(vp, tag + "_o3_measure_protection")
		screen._chart.set_metric(2)
		await _settle(screen)
		_save(vp, tag + "_o4_measure_healing")
		screen._chart.set_metric(RecapHeroChart.TOTAL)
		await _settle(screen)
		_save(vp, tag + "_o4b_measure_total")
		screen._chart.set_metric(0)
		# The top damage dealer's breakdown, as of the selected stop.
		var best := -1
		var best_v := -1.0
		for h in screen._chart.shown():
			var v: float = screen._chart.value_of(int(h["uid"]), 0)
			if v > best_v:
				best_v = v
				best = int(h["uid"])
		if best > 0 and screen.open_hero(best):
			await _settle(screen, 4)
			_save(vp, tag + "_o6_hero_breakdown")
			screen.close_hero()
			await _settle(screen)
		# Mid-replay: Play from here, part-way through the next stop's growth.
		screen.toggle_play()
		screen.overview_tick(RunRecapScreen.PLAY_STEP + 0.12)
		await _settle(screen)
		_save(vp, tag + "_o5_playing")
		screen.toggle_play()
		screen._select(mid_key, true)
		_ease_overview(screen)
		var ok := screen.open_fight(mid_key)
		_report_lines.append("  open_fight(%s) -> %s" % [mid_key, ok])
		await _settle(screen, 6)
		if ok:
			_save(vp, tag + "_f1_fight_report")
			screen.close_fight()
			await _settle(screen, 4)
			_report_lines.append("  back: selected=%s focus=%s" % [screen.selected_key(),
				vp.gui_get_focus_owner().get_class() if vp.gui_get_focus_owner() else "none"])
			_save(vp, tag + "_f2_back")
	# The lost/last fight opens too.
	if not recap.fights.is_empty() and sz == Vector2i(1920, 1080):
		var last_key := String(recap.fights[recap.fights.size() - 1]["key"])
		if screen.open_fight(last_key):
			await _settle(screen, 6)
			_save(vp, tag + "_f3_last_fight")
			screen.close_fight()
	vp.queue_free()
	await get_tree().process_frame

# The harness owns the clock: let the overview camera finish easing.
func _ease_overview(screen: RunRecapScreen) -> void:
	for _i in range(40):
		screen.overview_tick(0.05)

func _settle(screen: RunRecapScreen, n: int = 3) -> void:
	for _i in range(n):
		screen._route.queue_redraw()
		await get_tree().process_frame

func _banner(vp: SubViewport) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 200
	vp.add_child(layer)
	var banner := Label.new()
	banner.text = " SYNTHETIC LAYOUT FIXTURE - NOT A REAL RESULT "
	banner.position = Vector2(4, 2)
	banner.add_theme_font_size_override("font_size", 14)
	banner.add_theme_color_override("font_color", Color.WHITE)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.7, 0.1, 0.1)
	banner.add_theme_stylebox_override("normal", bs)
	layer.add_child(banner)

func _save(vp: SubViewport, tag: String) -> void:
	var img: Image = vp.get_texture().get_image()
	var path := CapturePaths.out("run_recap_SYNTHETIC_%s.png" % tag)
	img.save_png(path)
	print("saved ", path)

# ── SYNTHETIC recaps (NOT real data) ──────────────────────────────────────────
func _fixture(c: String) -> RunRecap:
	_rng.seed = hash(c)
	_split_rng.seed = hash(c + "-split")
	match c:
		"one": return _build(1, 2, false, 0, false, true)
		"five": return _build(6, 4, false, 0, false, false, true)
		"thirty": return _build(33, 12, false, 0, true)
		"hundred": return _build(100, 20, true, 0, true)
		"legacy": return _build(19, 6, false, 12, false)
	return _build(5, 3, false, 0, false)

# waves: last wave fought. victory: last wave is won and the run is a victory.
# from_round > 1: a legacy partial record starting there.
func _build(waves: int, n_heroes: int, victory: bool, from_round: int, late_joins: bool,
		zero_kills: bool = false, force_skip: bool = false) -> RunRecap:
	var recap := RunRecap.from_legacy("SYNTHETIC-run", from_round) if from_round > 1 \
		else RunRecap.create("SYNTHETIC-run")
	var heroes: Array = []
	for i in range(n_heroes):
		var cls: int = UnitBase.UnitClass[HERO_CLASSES[i % HERO_CLASSES.size()]]
		var uid: int = i + 1
		recap._touch_hero(uid, HERO_CLASSES[i % HERO_CLASSES.size()].capitalize(), cls, 0)
		heroes.append(uid)
	recap.next_uid = n_heroes + 1
	var start: int = maxi(1, from_round)
	for w in range(start, waves + 1):
		var biome: int = (w - 1) / 10
		var stage: int = (w - 1) % 10 + 1
		if stage == 1:
			recap.note_node({"node_id": "b%dr0c1" % biome, "round": w, "biome": biome, "type": RunMap.NodeType.RELIC}, false)
		var type: int = RunMap.NodeType.BOSS if stage == 10 else (RunMap.NodeType.ELITE if stage == 5 else RunMap.NodeType.BATTLE)
		var last: bool = w == waves
		# Some waves are taken by a side stop instead of a fight (skipped wave).
		var skip_here: bool = not last and type == RunMap.NodeType.BATTLE and stage in [3, 7] \
			and (force_skip or (waves < 100 and _rng.randf() < 0.5))
		if skip_here:
			var ut: int = [RunMap.NodeType.EVENT, RunMap.NodeType.MERCHANT, RunMap.NodeType.CAMP][_rng.randi() % 3]
			recap.note_node({"node_id": "b%dr%dc3" % [biome, stage], "round": w, "biome": biome, "type": ut}, false)
			continue
		var tier: int = _rng.randi_range(0, 2) if type == RunMap.NodeType.BATTLE else 1
		var icon := ""
		if type == RunMap.NodeType.BATTLE:
			icon = String(_normal_types[_rng.randi() % _normal_types.size()][1])
		else:
			icon = RunMapScreen.sprite_path_for(w, type)
		var node_id := "b%dr%dc%d" % [biome, stage, tier]
		var won: bool = not last or victory
		# Roster: late joiners arrive over the run.
		var active: Array = []
		for i in range(n_heroes):
			var join_at: int = start + (i * 3 if late_joins else (i % 2) * 2)
			if w >= join_at:
				active.append(heroes[i])
		var fielded: Array = active.slice(0, mini(active.size(), 20))
		# A sixth hero sits on the bench every fourth wave (bench state in the chart).
		var bench: Array = active.slice(20)
		if fielded.size() >= 6 and w % 4 == 0 and not last:
			bench.append(fielded[5])
			fielded.remove_at(5)
		var rep := _report(fielded, recap, won, w, type)
		var tap := _tap(fielded, w, type, zero_kills or (from_round == 0 and false), won)
		tap["split"] = _split_for(rep)
		var ids := {}
		for uid in fielded:
			ids[100000 + int(uid)] = uid
		recap.finalise_fight({"node_id": node_id, "round": w, "biome": biome, "type": type, "tier": tier,
			"icon": icon, "won": won}, rep, tap, ids, active, bench)
		# The legacy case's first recorded waves predate the damage breakdown too.
		if from_round > 1 and w < from_round + 3:
			recap.fights[recap.fights.size() - 1]["dmg_split"] = null
	recap.finalise_run("victory" if victory else "defeat", waves, recap.defeat_total(), 42)
	return recap

func _report(fielded: Array, recap: RunRecap, won: bool, w: int, type: int) -> Dictionary:
	var dur: float = _rng.randf_range(14.0, 48.0) + (30.0 if type == RunMap.NodeType.BOSS else 0.0)
	var heroes: Array = []
	var events: Array = []
	var team := {"dealt_hp": 0, "dealt_shield": 0, "taken_hp": 0, "taken_shield": 0, "heal_out": 0, "heal_self": 0}
	var scale: float = 1.0 + float(w) * 0.12
	for uid in fielded:
		var h: Dictionary = recap.hero(int(uid))
		var role: int = int(uid) % 4          # 0 carry, 1 tank, 2 healer, 3 mixed
		var dealt: int = int(_rng.randf_range(200, 900) * scale * (2.2 if role == 0 else (0.5 if role == 2 else 1.0)))
		var heal_out: int = int(_rng.randf_range(150, 600) * scale) if role == 2 else (int(_rng.randf_range(0, 80) * scale) if role == 3 else 0)
		var heal_self: int = int(_rng.randf_range(0, 120) * scale) if role != 2 else 0
		var died: bool = not won or _rng.randf() < 0.12
		var revived: bool = won and died and _rng.randf() < 0.5
		var t_death: float = _rng.randf_range(dur * 0.2, dur * 0.95)
		var iv: Array = [[0.0, dur]]
		if died:
			iv = [[0.0, t_death]]
			events.append({"t": t_death, "kind": "death", "hero": 100000 + int(uid), "name": h["name"], "by": "SYNTHETIC foe"})
			if revived:
				var t_up: float = minf(dur, t_death + 3.0)
				iv.append([t_up, dur])
				events.append({"t": t_up, "kind": "revive", "hero": 100000 + int(uid), "name": h["name"]})
		var ulted: bool = _rng.randf() < 0.5
		if ulted:
			events.append({"t": _rng.randf_range(4.0, dur), "kind": "ultimate", "hero": 100000 + int(uid),
				"name": h["name"], "ability": "SYNTHETIC ult"})
		var alive := 0.0
		for p in iv:
			alive += float(p[1]) - float(p[0])
		heroes.append({"id": 100000 + int(uid), "name": h["name"], "cls": h["cls"], "level": 1 + w / 3,
			"dealt_hp": dealt, "dealt_shield": int(dealt * 0.05), "dealt_by_summons": 0,
			"taken_hp": int(_rng.randf_range(100, 700) * scale), "taken_shield": int(_rng.randf_range(0, 120) * scale),
			"heal_out": heal_out, "heal_self": heal_self, "overheal": int(heal_out * 0.2),
			"deaths": 1 if died else 0, "revives": 1 if revived else 0, "ults": 1 if ulted else 0,
			"hp_end": 0 if (died and not revived) else 200, "max_hp_end": 900 + w * 20,
			"survived": not died or revived, "alive_time": alive, "intervals": iv})
		for k in team.keys():
			team[k] += int(heroes[heroes.size() - 1][k])
	events.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var survivors: Array = []
	if not won:
		for i in range(_rng.randi_range(2, 6)):
			var ty: Array = _normal_types[_rng.randi() % _normal_types.size()]
			survivors.append({"name": "SYNTHETIC %s" % ty[0], "portrait": ty[1], "hp": 300, "max_hp": 800,
				"start_max_hp": 800, "summoned": false})
	var rep := {"won": won, "duration": dur, "heroes": heroes, "events": events, "team": team,
		"enemies": {"seen": 8, "remaining": survivors.size(), "hp": 300 * survivors.size(),
			"max_hp": 800 * survivors.size(), "survivors": survivors},
		"unattributed_taken": 0}
	rep["takeaway"] = BattleRecorder.build_takeaway(rep)
	return rep

func _tap(fielded: Array, w: int, type: int, zero_kills: bool, won: bool) -> Dictionary:
	var hs := {}
	for uid in fielded:
		var role: int = int(uid) % 4
		var prot: int = int(_rng.randf_range(100, 500) * (1.0 + w * 0.1)) if role == 1 else (int(_rng.randf_range(0, 60)) if role == 3 else 0)
		hs[100000 + int(uid)] = {"uid": uid, "protect_out": int(prot * 0.7), "protect_self": int(prot * 0.3)}
	var defeats: Array = []
	var total := 0
	var summoned := 0
	if not zero_kills:
		for i in range(_rng.randi_range(2, 4) + w / 15):
			var ty: Array = _normal_types[_rng.randi() % _normal_types.size()]
			var n: int = _rng.randi_range(1, 4) + w / 12
			var s: int = n / 3 if _rng.randf() < 0.3 else 0
			defeats.append({"key": ty[0], "name": String(ty[0]).replace("_", " ").capitalize(), "portrait": ty[1],
				"n": n, "summoned": s, "boss": false, "elite": false})
			total += n
			summoned += s
		if won and type != RunMap.NodeType.BATTLE:
			var path := RunMapScreen.sprite_path_for(w, type)
			var key := path.get_file().get_basename() if path != "" else "SYNTHETIC_headliner_w%d" % w
			defeats.append({"key": key, "name": key.replace("_", " ").capitalize(), "portrait": path, "n": 1,
				"summoned": 0, "boss": type == RunMap.NodeType.BOSS, "elite": type == RunMap.NodeType.ELITE})
			total += 1
	var head: Array = []
	if type != RunMap.NodeType.BATTLE:
		var p2 := RunMapScreen.sprite_path_for(w, type)
		head.append({"name": p2.get_file().get_basename().replace("_", " ").capitalize(), "key": p2,
			"boss": type == RunMap.NodeType.BOSS, "elite": type == RunMap.NodeType.ELITE})
	return {"token": "SYNTHETIC-%d" % w, "heroes": hs, "protect_unattributed": _rng.randi_range(0, 30),
		"defeats": defeats, "defeat_total": total, "summoned_total": summoned, "headliners": head,
		"order": _kill_order(defeats)}

# SYNTHETIC damage breakdowns: invented shares per role (NOT measured from the
# game), [source, type, weight], each hero's cells summing to its dealt_hp.
const SPLIT_PROFILES := [
	[[0, 0, 52], [1, 0, 14], [2, 2, 18], [0, 1, 6], [3, 0, 4], [5, 0, 6]],     # carry
	[[0, 0, 46], [1, 1, 26], [2, 0, 16], [5, 0, 12]],                         # tank
	[[0, 1, 38], [1, 1, 30], [2, 1, 18], [3, 2, 10], [5, 1, 4]],              # healer
	[[0, 0, 30], [1, 1, 14], [2, 1, 14], [3, 0, 16], [4, 0, 18], [5, 2, 8]],  # mixed
]

func _split_for(rep: Dictionary) -> Dictionary:
	var out := {}
	for h in rep["heroes"]:
		var dealt: int = int(h["dealt_hp"])
		var cells: Array = []
		cells.resize(RecapFightTap.SOURCES * RecapFightTap.TYPES)
		cells.fill(0)
		var prof: Array = SPLIT_PROFILES[(int(h["id"]) - 100000) % 4]
		var weights: Array = []
		var wsum := 0.0
		for e in prof:
			var wt: float = float(e[2]) * _split_rng.randf_range(0.6, 1.4)
			weights.append(wt)
			wsum += wt
		var given := 0
		for i in range(prof.size()):
			var part: int = int(floor(dealt * weights[i] / wsum))
			cells[int(prof[i][0]) * RecapFightTap.TYPES + int(prof[i][1])] += part
			given += part
		cells[int(prof[0][0]) * RecapFightTap.TYPES + int(prof[0][1])] += dealt - given
		out[int(h["id"])] = cells
	return out

# A plausible SYNTHETIC kill order: the types interleaved, the headliner last.
func _kill_order(defeats: Array) -> Array:
	var pool: Array = []
	var last: Array = []
	for d in defeats:
		for _n in range(int(d["n"])):
			if bool(d["boss"]) or bool(d["elite"]):
				last.append(d["key"])
			else:
				pool.append(d["key"])
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool + last
