extends Node
const CapturePaths = preload("res://scripts/tools/capture_paths.gd")

# Renders the defeat infographic from SYNTHETIC fixtures (solo / four-hero /
# crowded) in both themes and at several window sizes. Every PNG carries a
# "SYNTHETIC LAYOUT FIXTURE" banner: these numbers are invented and must never
# be mistaken for a player's results.
#
# Run (windowed - headless has no renderer):
#   APPDATA=<disposable> godot --path . res://scenes/tools/defeat_report_capture.tscn
#   optional:  -- --only=four --size=1280x720 --theme=light
# It writes via UITheme.set_ui_style, i.e. into user://settings.json, which is why
# it must run with APPDATA pointed at a disposable profile.

const HERO_CLASSES := ["SHAUNA", "NEMI", "DOC", "BLOODHOUND", "SHEILDOR", "JUNE", "RIOT", "LORDEE",
	"SABLE", "STITCH", "COAL", "CROSS", "EMBER", "SEAR", "ZOLT", "REED", "VAIL", "SPORE"]
const HERO_NAMES := ["Shauna", "Nemi", "Doc", "Bloodhound", "Sheildor", "June", "Riot", "Lordee",
	"Sable", "Stitch", "Coal", "Cross", "Ember", "Sear", "Zolt", "Reed", "Vail", "Spore"]

func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out

func _ready() -> void:
	if not OS.get_environment("APPDATA").contains("isolated-profile") and not OS.get_environment("APPDATA").contains("scratch"):
		push_error("defeat_report_capture: refusing to run unless APPDATA is a disposable profile")
		get_tree().quit(2)
		return
	var args := _args()
	var cases: Array = [["solo", 1, 2, 45.0], ["four", 4, 6, 63.4], ["crowded", 14, 26, 214.0]]
	var sizes: Array = [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1024, 600)]
	var themes: Array = ["dark", "light"]
	if args.has("only"):
		cases = cases.filter(func(c): return c[0] == args["only"])
	if args.has("size"):
		var p := String(args["size"]).split("x")
		sizes = [Vector2i(int(p[0]), int(p[1]))]
	if args.has("theme"):
		themes = [args["theme"]]
	for theme in themes:
		UITheme.set_ui_style(theme)
		for c in cases:
			for sz in sizes:
				# Full-size matrix only for the crowded case's smaller windows.
				if sz != Vector2i(1920, 1080) and c[0] == "solo" and not args.has("size"):
					continue
				await _shot(theme, c, sz)
	print("DEFEAT_REPORT_CAPTURE: DONE")
	get_tree().quit(0)

func _shot(theme: String, c: Array, sz: Vector2i) -> void:
	var vp := SubViewport.new()
	vp.size = sz
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.30, 0.45, 0.22)
	vp.add_child(bg)
	var go := GameOverScreen.new()
	vp.add_child(go)
	var summary := {"crystals": 14, "rounds_cleared": 22, "fell_on": 23, "enemies_defeated": 318,
		"biome": "Tidewater", "encounter": "Elite", "difficulty": "Veteran"}
	go.show_defeat_report(summary, _fixture(c[1], c[2], c[3]))
	var banner := Label.new()
	banner.text = " SYNTHETIC LAYOUT FIXTURE - NOT A REAL RESULT "
	banner.position = Vector2(4, 2)
	banner.z_index = 100
	banner.add_theme_font_size_override("font_size", 14)
	banner.add_theme_color_override("font_color", Color.WHITE)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.7, 0.1, 0.1)
	banner.add_theme_stylebox_override("normal", bs)
	vp.add_child(banner)
	for i in range(6):
		await get_tree().process_frame
	go.report_view().reveal_now()
	await get_tree().process_frame
	await get_tree().process_frame
	var tag := "%s_%s_%dx%d" % [c[0], theme, sz.x, sz.y]
	_save(vp, tag)
	# Hovered timeline marker (the first death marker) -> readout line.
	var tl := go.report_view().timeline()
	if tl and not tl._markers.is_empty():
		tl._update_hover((tl._markers[0]["pos"] as Vector2))
		await get_tree().process_frame
		await get_tree().process_frame
		_save(vp, tag + "_hover")
	# Scrolled to the bottom, when the content does not fit.
	var sc: ScrollContainer = go.report_view()._scroll
	if sc.get_v_scroll_bar().max_value > sc.size.y + 2.0:
		sc.scroll_vertical = 100000
		await get_tree().process_frame
		await get_tree().process_frame
		_save(vp, tag + "_scrolled")
	vp.queue_free()
	await get_tree().process_frame

func _save(vp: SubViewport, tag: String) -> void:
	var img: Image = vp.get_texture().get_image()
	var path := CapturePaths.out("defeat_report_%s.png" % tag)
	img.save_png(path)
	print("saved ", path)

# ── Synthetic report (NOT real data) ──────────────────────────────────────────
func _fixture(n_heroes: int, n_enemies: int, dur: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + n_heroes
	var heroes: Array = []
	var events: Array = []
	var team := {"dealt_hp": 0, "dealt_shield": 0, "taken_hp": 0, "taken_shield": 0, "heal_out": 0, "heal_self": 0}
	for i in range(n_heroes):
		var cls_name: String = HERO_CLASSES[i % HERO_CLASSES.size()]
		var cls: int = UnitBase.UnitClass[cls_name]
		var fell: float = -1.0
		if i % 3 != 2 or n_heroes == 1:
			fell = dur * (0.35 + 0.6 * rng.randf()) if n_heroes > 1 else dur - 1.0
		var iv: Array = [[0.0, fell if fell > 0.0 else dur]]
		var deaths := 1 if fell > 0.0 else 0
		var revives := 0
		var id := 5000 + i
		var nm: String = HERO_NAMES[i % HERO_NAMES.size()]
		if fell > 0.0:
			events.append({"t": fell, "kind": "death", "hero": id, "name": nm, "by": "Tide Orc"})
		if i == 3 and n_heroes >= 4:
			iv = [[0.0, dur * 0.3], [dur * 0.3 + 6.0, dur * 0.55]]
			deaths = 2
			revives = 1
			events = events.filter(func(e): return e["hero"] != id)
			events.append({"t": dur * 0.3, "kind": "death", "hero": id, "name": nm, "by": "Tide Orc"})
			events.append({"t": dur * 0.3 + 6.0, "kind": "revive", "hero": id, "name": nm})
			events.append({"t": dur * 0.55, "kind": "death", "hero": id, "name": nm, "by": "Kelpie"})
			fell = dur * 0.55
		if i % 2 == 0:
			events.append({"t": dur * (0.1 + 0.05 * i), "kind": "ultimate", "hero": id, "name": nm, "ability": "Ultimate"})
		var is_healer: bool = cls_name in ["DOC", "CROSS"]
		var healed := (900 + rng.randi_range(0, 400)) if is_healer else 0
		if is_healer:
			events.append({"t": dur * 0.2, "kind": "heal", "hero": id, "name": nm, "target": "Shauna", "amount": 410})
		var alive := 0.0
		for pair in iv:
			alive += float(pair[1]) - float(pair[0])
		var row := {"id": id, "name": nm, "cls": cls, "portrait": VisualUnit.HERO_SPRITE_PATHS.get(cls, ""),
			"level": 8 + i, "dealt_hp": 0 if is_healer else rng.randi_range(1500, 9000),
			"dealt_shield": 0, "dealt_by_summons": 0, "taken_hp": rng.randi_range(600, 4200),
			"taken_shield": 400 if i % 4 == 0 else 0, "heal_out": healed, "heal_self": 120 if i % 3 == 0 else 0,
			"overheal": 300 if is_healer else 0, "healed_in": 0, "intervals": iv, "deaths": deaths,
			"revives": revives, "ults": 1, "alive_time": alive, "survived": fell < 0.0,
			"hp_end": 0 if fell > 0.0 else 800, "max_hp_end": 2400}
		heroes.append(row)
		for k in team.keys():
			team[k] += int(row[k])
	# Several events on the very same instant for one hero (timeline stress).
	if n_heroes >= 4:
		for k in ["ultimate", "heal", "ultimate"]:
			events.append({"t": 30.0, "kind": k, "hero": 5001, "name": HERO_NAMES[1], "ability": "Tidal Surge",
				"target": "Shauna", "amount": 300})
	events.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var mon: Array = VisualUnit.MONSTER_SPRITE_PATHS.values()
	var names := ["Tide Orc", "Kelpie", "Drowned Maw", "Sea Slime", "Basilisk", "Siren", "Brine Troll"]
	var surv: Array = []
	var hp_sum := 0
	var max_sum := 0
	for j in range(n_enemies):
		var mx := 600 + 120 * (j % 5)
		var hp := int(mx * rng.randf_range(0.15, 0.95))
		surv.append({"name": names[j % names.size()], "portrait": mon[(j * 7) % mon.size()], "hp": hp,
			"max_hp": mx, "start_max_hp": mx - (200 if j == 1 else 0), "summoned": j % 6 == 5})
		hp_sum += hp
		max_sum += mx
	var rep := {"version": 1, "won": false, "duration": dur, "heroes": heroes, "events": events,
		"enemies": {"seen": n_enemies + 5, "remaining": n_enemies, "hp": hp_sum, "max_hp": max_sum, "survivors": surv},
		"team": team, "unattributed_taken": 0, "notes": []}
	rep["takeaway"] = BattleRecorder.build_takeaway(rep)
	return rep
