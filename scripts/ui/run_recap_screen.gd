class_name RunRecapScreen
extends CanvasLayer
# ══════════════════════════════════════════════════════════════════════════════
# RUN RECAP SCREEN (2026-10-07) - the whole run, replayed once it is over.
#
#   JOURNEY   an accelerating walk over the run map's dotted route and painted
#             biome plates: Wave / biome / tier on top, the active encounter a
#             little right of centre, the defeat parade under the route and the
#             hero chart (heroes recruited so far) at the bottom. The camera
#             travels right, the route slides left; text and roster stay put.
#             As each fight is left behind its encounter icon is bopped off the
#             route and falls into the parade (RecapFlyer); that wave's defeated
#             enemies appear in the parade when it lands.
#   ENDING    a clear pause on the last encounter with the outcome (its defeats
#             join the parade), then the painting fades into a quiet background
#             and the camera pulls back over the route.
#   OVERVIEW  a scrubbable replay (owner layout, 2026-10-07): the route with every
#             fight's creature and time, the defeat parade, the hero chart, and
#             back / play-pause / forward in the top band. The SELECTED stop is
#             the replay point: the chart, life states and parade show the run as
#             it stood after that stop. Click the selected fight again (or Enter /
#             controller A / "Open report") to inspect it.
#   HERO      click a hero's bar (journey or overview) for that hero's damage
#             broken down by source and type, up to the replay point.
#   FIGHT     the existing per-fight overview (DefeatReportView) with that fight's
#             frozen report; Back restores selection, zoom, scroll and measure.
#
# The journey is a pure function of one clock `_t`, so Skip is "jump the clock to
# the end": no tweens or timers to cancel, and any moment lands on the same
# overview. The main menu's LAST RUN replays the journey from the beginning;
# reduced motion (or `start_in_overview`) opens the overview directly.
#
# It only ever reads a RunRecap: no units, no combat manager, no live stats.
# ══════════════════════════════════════════════════════════════════════════════

signal overview_reached
signal closed

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SCREEN_LAYER := 100            # under the relic-unlock reveals (120)
const SKIP_FADE := 0.2
const CAM_TRAVEL := 0.40             # share of a fight step spent travelling
const BAR_FROM := 0.25               # bars grow over [BAR_FROM, BAR_TO] of a step
const BAR_TO := 0.88
const DEPART_AT := 0.90
const TICK_GAP := 0.09               # audio rate limits (journey seconds)
const BOP_GAP := 0.14
const PLAY_STEP := 0.6               # seconds per stop when replaying from the overview
const GROW_TIME := 0.35              # a forward step's gains grow in over this long
const LAND_FILL := 0.25              # a landed wave's sprites fill in over this long
const OVERVIEW_ZOOM := 0.72          # readable zoom for long routes in the overview
const HINT := "◀ ▶ step  ·  Space / X play  ·  Enter / A open report  ·  1-4 / bumpers measure  ·  click a bar for a hero's breakdown"

enum Mode { JOURNEY, OVERVIEW, FIGHT }

var recap: RunRecap
var context: String = "terminal"     # "terminal" (the run just ended) | "menu"
var mode: int = Mode.JOURNEY

var _plan: Dictionary = {}
var _n: int = 0
var _step_stop: Array = []           # route-view stop index per fight
var _t: float = 0.0
var _since_open: float = 0.0
var _overview_emitted := false
var _last_point := Vector3(-9, -9, 0)
var _last_tick := -9.0
var _last_bop := -9.0
var _beat_played := false
var _ticked: Dictionary = {}
var _bopped: Dictionary = {}
var _saved: Dictionary = {}
var _size: Vector2 = Vector2(1920, 1080)
var _in_apply := false               # _apply_time -> _layout must not recurse back
# Portrait textures the parade and chart will need, prepared a couple per frame
# during the journey: trimming dozens at once in the reveal frame cost ~100 ms.
var _warm_queue: Array = []
static var _ding: AudioStreamWAV = null   # synthesized once per session (not free in GDScript)

# Overview replay state.
var _sel: int = -1                   # selected route stop = the replay point
var _playing := false
var _play_t := 0.0
var _grow_t := -1.0                  # >= 0 while a forward step's gains grow in
var _cam_follow := false
var _cam_target_x := 0.0
var _cam_target_zoom := 1.0

# Nodes
var _root: Control
var _quiet: ColorRect
var _plate_a: TextureRect
var _plate_b: TextureRect
var _veil: ColorRect
var _route: RecapRouteView
var _chart: RecapHeroChart
var _top: PanelContainer
var _wave_lbl: Label
var _where_lbl: Label
var _chips_lbl: Label
var _note_lbl: Label
var _hint_lbl: Label
var _skip_btn: Button
var _skip_hint: Label
var _end_btn: Button
var _crystal_row: HBoxContainer
var _crystal_lbl: Label
var _transport: HBoxContainer
var _prev_btn: Button
var _play_btn: Button
var _next_btn: Button
var _open_btn: Button
var _stamp: Label
var _trophies: PanelContainer
var _parade_scroll: ScrollContainer
var _parade: RecapDefeatParade
var _zoom_bar: HBoxContainer
var _flyer: RecapFlyer
var _parade_head_lbl: Label
var _ov_flight: Dictionary = {}      # overview: {fi, age} of the icon falling into the parade
var _hero_layer: ColorRect
var _hero_detail: RecapHeroDetail
var _hero_uid: int = -1
var _fight_layer: ColorRect
var _fight_view: DefeatReportView
var _sfx: AudioStreamPlayer

# ── Entry ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = SCREEN_LAYER

# `start_in_overview` skips the journey; reduced motion forces it.
func present(p_recap: RunRecap, p_context: String = "terminal", start_in_overview: bool = false) -> void:
	recap = p_recap
	context = p_context
	visible = true
	_build()
	var kinds: Array = []
	for f in recap.fights:
		var t: int = int(f["type"])
		kinds.append("boss" if t == RunMap.NodeType.BOSS else ("elite" if t == RunMap.NodeType.ELITE else ""))
	_n = recap.fights.size()
	_plan = RecapPacing.plan(kinds)
	_step_stop.clear()
	for f in recap.fights:
		_step_stop.append(_route.stop_index(String(f["key"])))
	_warm_queue.clear()
	for k in recap.enemy_types.keys():
		_warm_queue.append(["portrait", String(recap.enemy_types[k].get("portrait", ""))])
	for h in recap.heroes:
		_warm_queue.append(["portrait", String(VisualUnit.HERO_SPRITE_PATHS.get(int(h["cls"]), ""))])
	# The route's creature stamps too: the reveal zooms out over every stop at
	# once, and building all of their masks in that one frame spiked it.
	var seen := {}
	for st in _route.stops:
		var icon := String(st.get("icon", ""))
		if icon != "" and not seen.has(icon):
			seen[icon] = true
			_warm_queue.append(["creature", icon])
	if start_in_overview or UITheme.reduced_motion() or _n == 0:
		_enter_overview()
	else:
		mode = Mode.JOURNEY
		_t = 0.0
		_apply_time()

func journey_total() -> float:
	return float(_plan.get("total", 0.0))

func journey_time() -> float:
	return _t

func is_journey() -> bool:
	return mode == Mode.JOURNEY

func is_playing() -> bool:
	return _playing

# ── Build ─────────────────────────────────────────────────────────────────────

func _vp() -> Vector2:
	var s: Vector2 = get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	return s if s.x >= 100.0 and s.y >= 100.0 else Vector2(1920, 1080)

func _quiet_color() -> Color:
	return Color(0.90, 0.86, 0.77) if UITheme.is_light() else Color(0.055, 0.05, 0.048)

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_quiet = ColorRect.new()
	_quiet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quiet.color = _quiet_color()
	_quiet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_quiet)
	for i in range(2):
		var p := TextureRect.new()
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(p)
		if i == 0: _plate_a = p
		else: _plate_b = p
	_veil = ColorRect.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_veil)

	_route = RecapRouteView.new()
	_route.setup(recap)
	_route.lost_index = -1
	if recap.outcome == "defeat" and not recap.fights.is_empty() and not bool(recap.fights[recap.fights.size() - 1]["won"]):
		_route.lost_index = _route.stop_index(String(recap.fights[recap.fights.size() - 1]["key"]))
	_route.stop_clicked.connect(_on_route_click)
	_route.tooltip_provider = _stop_tooltip
	_route.user_moved.connect(func(): _cam_follow = false)
	_root.add_child(_route)

	_chart = RecapHeroChart.new()
	_root.add_child(_chart)
	_chart.setup(recap)
	_chart.hero_clicked.connect(func(uid): open_hero(uid))

	_build_top()
	_build_trophies()
	_build_zoom_bar()

	_flyer = RecapFlyer.new()
	_flyer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_flyer)

	_stamp = _lbl("", UITheme.FONT_DISPLAY, DefeatReportView.crimson())
	_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stamp.add_theme_constant_override("outline_size", 8)
	_stamp.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85) if not UITheme.is_light() else Color(1, 0.97, 0.9, 0.9))
	_stamp.visible = false
	_root.add_child(_stamp)

	_fight_layer = ColorRect.new()
	_fight_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fight_layer.color = Color(0, 0, 0, 0.86)
	_fight_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_fight_layer.visible = false
	_root.add_child(_fight_layer)

	_hero_layer = ColorRect.new()
	_hero_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hero_layer.color = Color(0, 0, 0, 0.72)
	_hero_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_hero_layer.visible = false
	_hero_layer.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_hero())        # a click outside the card puts it away
	_root.add_child(_hero_layer)

	_sfx = AudioStreamPlayer.new()
	if _ding == null:
		_ding = CrystalShop._make_unlock_ding()   # the game's one sound; no new asset
	_sfx.stream = _ding
	_sfx.volume_db = -20.0
	add_child(_sfx)

	if get_viewport() and not get_viewport().size_changed.is_connected(_layout):
		get_viewport().size_changed.connect(_layout)
	_layout()

func _lbl(text: String, px: int, col: Color, read: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if read:
		UITheme.apply_read_font(l, px)
	else:
		UITheme.apply_font(l, px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _band_box(alpha: float = 0.88) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.97, 0.94, 0.87, alpha) if UITheme.is_light() else Color(0.07, 0.065, 0.06, alpha)
	b.border_color = DefeatReportView.gold()
	b.set_border_width_all(2)
	b.set_corner_radius_all(6)
	b.set_content_margin_all(10)
	return b

func _style_btn(b: Button, primary: bool) -> void:
	if primary:
		UITheme.style_button(b)
	else:
		UITheme.style_button_secondary(b)
	UITheme.apply_font(b, UITheme.FONT_HEADER if primary else UITheme.FONT_VALUE)
	# A focus ring that is always visible, so keyboard/controller users can see
	# where they are (UITheme's buttons are mouse-first).
	b.add_theme_stylebox_override("focus", UITheme.selection_ring_box(DefeatReportView.gold()))
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, 44.0)

func _build_top() -> void:
	_top = PanelContainer.new()
	_top.add_theme_stylebox_override("panel", _band_box())
	_top.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(_top)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	_top.add_child(h)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	left.add_child(line)
	_wave_lbl = _lbl("", UITheme.FONT_DISPLAY, DefeatReportView.gold())
	line.add_child(_wave_lbl)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(mid)
	_where_lbl = _lbl("", UITheme.FONT_VALUE, DefeatReportView.ink())
	_where_lbl.clip_text = true
	_where_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(_where_lbl)
	_chips_lbl = _lbl("", UITheme.FONT_BODY, DefeatReportView.muted())
	_chips_lbl.clip_text = true
	_chips_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_chips_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	mid.add_child(_chips_lbl)
	_note_lbl = _lbl("", UITheme.FONT_BODY, DefeatReportView.muted())
	_note_lbl.clip_text = true
	_note_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_note_lbl.visible = false
	left.add_child(_note_lbl)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(right)
	# Crystals are the run's carry-over reward: shown once the run is told.
	_crystal_row = HBoxContainer.new()
	_crystal_row.add_theme_constant_override("separation", 6)
	_crystal_row.alignment = BoxContainer.ALIGNMENT_END
	_crystal_row.visible = false
	var gem := UITheme.currency_icon("gem")
	gem.custom_minimum_size = Vector2(24, 24)
	_crystal_row.add_child(gem)
	_crystal_lbl = _lbl("", UITheme.FONT_VALUE, Color(0.12, 0.40, 0.72) if UITheme.is_light() else Color(0.45, 0.78, 1.0))
	_crystal_row.add_child(_crystal_lbl)
	_crystal_row.tooltip_text = "Crystals earned this run. They carry over - spend them on the crystal tree."
	_crystal_row.mouse_filter = Control.MOUSE_FILTER_PASS
	right.add_child(_crystal_row)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(buttons)
	_transport = HBoxContainer.new()
	_transport.add_theme_constant_override("separation", 4)
	_transport.visible = false
	buttons.add_child(_transport)
	_prev_btn = _transport_btn("|◀", "Previous stop (← / d-pad left)", func(): step(-1))
	_play_btn = _transport_btn("▶", "Replay the run from the selected stop (Space / controller X)", toggle_play)
	_next_btn = _transport_btn("▶|", "Next stop (→ / d-pad right)", func(): step(1))
	_open_btn = Button.new()
	_open_btn.text = "Open report"
	_style_btn(_open_btn, false)
	_open_btn.custom_minimum_size = Vector2(150, 44)
	_open_btn.pressed.connect(func(): open_fight(selected_key()))
	_transport.add_child(_open_btn)
	_skip_btn = Button.new()
	_skip_btn.text = "Skip ▶▶"
	_style_btn(_skip_btn, false)
	_skip_btn.custom_minimum_size = Vector2(150, 44)
	_skip_btn.tooltip_text = "Jump straight to the finished run overview."
	_skip_btn.pressed.connect(skip)
	buttons.add_child(_skip_btn)
	_end_btn = Button.new()
	_end_btn.text = "Return to Main Menu" if context == "terminal" else "Close"
	_style_btn(_end_btn, true)
	_end_btn.custom_minimum_size = Vector2(230 if context == "terminal" else 120, 48)
	_end_btn.pressed.connect(_on_end_pressed)
	_end_btn.visible = false
	buttons.add_child(_end_btn)
	_skip_hint = _lbl("Esc  ·  Back (B)", UITheme.FONT_BODY, DefeatReportView.muted())
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_skip_hint)
	_hint_lbl = _lbl(HINT, UITheme.FONT_BODY, DefeatReportView.muted())
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_lbl.visible = false
	right.add_child(_hint_lbl)

func _transport_btn(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	_style_btn(b, false)
	b.custom_minimum_size = Vector2(48, 44)
	b.pressed.connect(cb)
	_transport.add_child(b)
	return b

func _build_trophies() -> void:
	_trophies = PanelContainer.new()
	_trophies.add_theme_stylebox_override("panel", _band_box(0.92))
	_root.add_child(_trophies)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_trophies.add_child(v)
	var tally: Array = recap.defeat_tally()
	var total: int = recap.defeat_total()
	var summoned := 0
	for d in tally:
		summoned += int(d["summoned"])
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", 12)
	v.add_child(head)
	head.add_child(_lbl("ENEMIES DEFEATED", UITheme.FONT_HEADER, DefeatReportView.gold()))
	_parade_head_lbl = _lbl("", UITheme.FONT_VALUE, DefeatReportView.ink())
	_parade_head_lbl.set_meta("total", total)
	_parade_head_lbl.set_meta("summoned", summoned)
	head.add_child(_parade_head_lbl)
	var basis := "every confirmed defeat, wave by wave, in the order they fell"
	if recap.is_partial():
		basis += " · recorded from Wave %d" % recap.coverage_from_round
	var basis_lbl := _lbl(basis, UITheme.FONT_BODY, DefeatReportView.muted())
	basis_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	basis_lbl.tooltip_text = "Each confirmed death of an enemy-side unit while a recorded fight was running, one sprite each: an enemy revived and killed again appears each time; summoned enemies appear as their own type. Phase changes are not deaths. Surviving enemies and the map's encounter icons are never counted. Hover a sprite for what it was and where it fell."
	head.add_child(basis_lbl)
	if recap.run_kills_counter >= 0 and recap.run_kills_counter != total and not recap.is_partial():
		var n := _lbl("The run's kill counter read %s: it also counts fights replayed after a resume and kills landing after a fight's final whistle." % DefeatReportView.fmt_n(recap.run_kills_counter),
			UITheme.FONT_BODY, DefeatReportView.muted(), true)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size = Vector2(200, 0)
		v.add_child(n)
	if total == 0:
		v.add_child(_lbl("No enemies were defeated in the recorded fights.", UITheme.FONT_VALUE, DefeatReportView.ink()))
	_parade_scroll = ScrollContainer.new()
	_parade_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_parade_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_parade_scroll)
	_parade = RecapDefeatParade.new()
	_parade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parade_scroll.add_child(_parade)
	_parade.setup(recap)
	_parade_scroll.get_v_scroll_bar().value_changed.connect(func(_v): _parade.queue_redraw())

func _build_zoom_bar() -> void:
	_zoom_bar = HBoxContainer.new()
	_zoom_bar.add_theme_constant_override("separation", 4)
	_zoom_bar.visible = false
	_root.add_child(_zoom_bar)
	for spec in [["−", "Zoom the route out", func(): _zoom_by(1.0 / 1.5)],
			["Fit", "Show the whole route", func(): _fit_route()],
			["+", "Zoom the route in", func(): _zoom_by(1.5)]]:
		var b := Button.new()
		b.text = spec[0]
		b.tooltip_text = spec[1]
		_style_btn(b, false)
		b.custom_minimum_size = Vector2(46, 44)
		b.pressed.connect(spec[2])
		_zoom_bar.add_child(b)

func _fit_route() -> void:
	_cam_follow = false
	_route.frame_all()

func _zoom_by(k: float) -> void:
	_cam_follow = false
	var at := _route.to_screen(_route.world_pos(_sel)) if _sel >= 0 else _route.size * 0.5
	_route.set_zoom_at(_route.zoom * k, at)

static func _biome_name(b: int) -> String:
	return String(ProgressionRails.BIOMES[clampi(b, 0, ProgressionRails.BIOMES.size() - 1)]["name"])

static func _tier_name(t: int) -> String:
	var pips := "●".repeat(clampi(t, 0, 2) + 1)
	return "%s %s" % [RunMapScreen.TIER_NAMES[clampi(t, 0, RunMapScreen.TIER_NAMES.size() - 1)], pips]

static func _headliner(f: Dictionary) -> String:
	for h in f.get("headliners", []):
		if bool(h.get("boss", false)):
			return String(h["name"])
	for h in f.get("headliners", []):
		return String(h["name"])
	return ""

# ── Layout ────────────────────────────────────────────────────────────────────
# Fixed regions, recomputed on resize: top band, route, defeat parade, hero
# chart - the same rects in the journey and the overview, so nothing under the
# player's eye jumps when the journey ends.

func _layout() -> void:
	if _root == null:
		return
	_size = _vp()
	var W: float = _size.x
	var H: float = _size.y
	var M: float = 16.0 if W >= 1280.0 else 10.0
	# Short windows: the key hints live in the buttons' tooltips instead, and the
	# chart takes a larger share so its bars keep a readable height.
	_hint_lbl.visible = mode == Mode.OVERVIEW and H >= 760.0
	var top_h: float = maxf(clampf(H * 0.09, 72.0, 100.0), _top.get_combined_minimum_size().y)
	var chart_h: float = clampf(H * (0.36 if H >= 900.0 else 0.42), 240.0, 400.0)
	_top.position = Vector2(M, M)
	_top.size = Vector2(W - 2.0 * M, top_h)
	_wave_lbl.add_theme_font_size_override("font_size", UITheme.FONT_DISPLAY if H >= 700.0 and W >= 1280.0 else UITheme.FONT_HEADER + 6)
	_chart.position = Vector2(M, H - M - chart_h)
	_chart.size = Vector2(W - 2.0 * M, chart_h)
	var mid_y: float = M + top_h + M
	var mid_h: float = maxf(120.0, _chart.position.y - M - mid_y)
	# The parade is on screen from the first wave (owner, 2026-10-07).
	var troph_h: float = clampf(mid_h * 0.42, 92.0, 220.0)
	_route.position = Vector2(0, mid_y)
	_route.size = Vector2(W, mid_h - troph_h - M * 0.5)
	_trophies.position = Vector2(M, mid_y + _route.size.y + M * 0.5)
	_trophies.size = Vector2(W - 2.0 * M, troph_h)
	_zoom_bar.position = Vector2(W - M - 150.0, mid_y + 6.0)
	_stamp.position = Vector2(0, mid_y + 12.0)   # above the route line, never on a stop
	_stamp.size = Vector2(W, 60.0)
	_stamp.pivot_offset = _stamp.size * 0.5
	if _fight_view and is_instance_valid(_fight_view):
		_fight_view.fit(_size)
	_center_hero()
	if mode == Mode.OVERVIEW:
		_route.queue_redraw()
	elif mode == Mode.JOURNEY and not _in_apply:
		_apply_time()

# ── Journey clock ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_since_open += delta
	if _skip_btn and _skip_btn.visible:
		_skip_btn.modulate.a = clampf(_since_open / SKIP_FADE, 0.0, 1.0)
		_skip_hint.modulate.a = _skip_btn.modulate.a
	# One job a frame: each is a GPU readback of ~15-20 ms (up to ~60 ms for a
	# large sprite), so two in one frame showed as a visible stutter.
	warm_up(1)
	if mode == Mode.JOURNEY:
		if not hero_open():            # the journey holds while a hero card is open
			advance(delta)
	elif mode == Mode.OVERVIEW:
		overview_tick(delta)

# Prepare up to `count` queued textures (portrait trims, creature stamps).
func warm_up(count: int) -> void:
	for _i in range(count):
		if _warm_queue.is_empty():
			return
		var job: Array = _warm_queue.pop_back()
		if String(job[1]) == "":
			continue
		if job[0] == "creature":
			var tex := MapRouteArt.creature(String(job[1]))
			if tex:
				MapRouteArt.silhouette_mask(tex)
		else:
			DefeatReportView._enemy_texture(String(job[1]))

# Move the journey clock (the capture/test harness steps it explicitly too).
func advance(dt: float) -> void:
	if mode != Mode.JOURNEY:
		return
	_t = minf(_t + maxf(0.0, dt), journey_total())
	_apply_time()
	if _t >= journey_total():
		_enter_overview()

func set_time(t: float) -> void:
	if mode != Mode.JOURNEY:
		return
	_t = clampf(t, 0.0, journey_total())
	_apply_time()

func _step_at(t: float) -> Vector2:
	var starts: Array = _plan["starts"]
	var durs: Array = _plan["durations"]
	if t >= float(_plan["fights_end"]):
		return Vector2(_n - 1, 1.0)
	var lo := 0
	var hi := _n - 1
	while lo < hi:
		var mid: int = (lo + hi + 1) / 2
		if float(starts[mid]) <= t:
			lo = mid
		else:
			hi = mid - 1
	return Vector2(lo, clampf((t - float(starts[lo])) / maxf(0.0001, float(durs[lo])), 0.0, 1.0))

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _stop_x(step_i: int) -> float:
	var si: int = int(_step_stop[step_i]) if step_i >= 0 and step_i < _step_stop.size() else -1
	return float(_route.stops[si]["x"]) if si >= 0 else 0.0

func _apply_time() -> void:
	if _n == 0 or _route.stops.is_empty():
		return
	_in_apply = true
	_apply_time_inner()
	_in_apply = false

func _apply_time_inner() -> void:
	var t := _t
	var su := _step_at(t)
	var i: int = int(su.x)
	var u: float = su.y
	var fe: float = float(_plan["fights_end"])
	var pause: float = float(_plan["final_pause"])
	var reveal: float = float(_plan["reveal"])

	# Camera: travel from the previous fight (or the first stop) to this one.
	var x_prev: float = _stop_x(i - 1) if i > 0 else float(_route.stops[0]["x"])
	var x_cur: float = _stop_x(i)
	var cam_x: float = lerpf(x_prev, x_cur, _ease(u / CAM_TRAVEL))
	var jz: float = clampf(_route.size.y / 430.0, 0.55, 1.0)
	var k_rev: float = clampf((t - fe - pause) / maxf(0.001, reveal), 0.0, 1.0) if t > fe + pause else 0.0
	if k_rev > 0.0:
		var e := _ease(k_rev)
		var fit := _route.fit_zoom()
		_route.anchor = Vector2(lerpf(0.58, 0.5, e), 0.5)
		_route.zoom = lerpf(jz, fit, e)
		var mid_x: float = (float(_route.stops[0]["x"]) + float(_route.stops[_route.stops.size() - 1]["x"])) * 0.5
		_route.cam = Vector2(lerpf(x_cur, mid_x, e), 0.0)
	else:
		_route.anchor = Vector2(0.58, 0.5)
		_route.zoom = jz
		_route.cam = Vector2(cam_x, 0.0)
	_route.road_upto = cam_x if t < fe else 1e9
	_route.active = int(_step_stop[i])

	# Departures (every fight but the last): the icon is bopped off the route and
	# falls into the parade; that wave's defeats appear there once it lands.
	var starts: Array = _plan["starts"]
	var durs: Array = _plan["durations"]
	_route.departed.clear()
	_flyer.flights.clear()
	var landed_upto := -1
	var landed_fill := 1.0
	for j in range(mini(i + 1, _n - 1)):
		var dep: float = float(starts[j]) + DEPART_AT * float(durs[j])
		if t >= dep:
			var sj: int = int(_step_stop[j])
			_route.departed[sj] = true
			var age: float = t - dep
			if RecapFlyer.landed(age):
				landed_upto = j
				landed_fill = clampf((age - RecapFlyer.TOTAL_T) / LAND_FILL, 0.0, 1.0)
			elif sj >= 0:
				_flyer.flights.append(_flight_for(j, age))
			if not _bopped.has(j) and t - _last_bop >= BOP_GAP:
				_last_bop = t
				_play(1.35, -24.0)
			_bopped[j] = true
	# The last fight never departs: its defeats join the parade in the final pause.
	if t >= fe + 0.15:
		landed_upto = _n - 1
		landed_fill = clampf((t - fe - 0.15) / 0.4, 0.0, 1.0)
	_parade.set_upto(landed_upto, landed_fill)
	_update_parade_head()
	_scroll_parade_to_latest()
	_route.queue_redraw()
	_flyer.queue_redraw()

	# Chart: this fight's gains grow in over [BAR_FROM, BAR_TO] of its step.
	var bar_k: float = _ease((u - BAR_FROM) / (BAR_TO - BAR_FROM))
	var key := Vector3(i, snappedf(bar_k, 0.02), 0)
	if key != _last_point:
		_last_point = key
		_chart.set_point(i, bar_k)
	if bar_k > 0.0 and not _ticked.has(i):
		_ticked[i] = true
		if t - _last_tick >= TICK_GAP:
			_last_tick = t
			_play(2.1, -28.0)

	# Top band follows the fight being visited.
	_fill_top_journey(i, t >= fe)

	# Biome plates: cross-fade when the run crosses into a new decade.
	var biome: int = int(recap.fights[i]["biome"])
	var first_of_biome := i
	while first_of_biome > 0 and int(recap.fights[first_of_biome - 1]["biome"]) == biome:
		first_of_biome -= 1
	var prev_biome: int = int(recap.fights[first_of_biome - 1]["biome"]) if first_of_biome > 0 else biome
	var fade: float = clampf((t - float(starts[first_of_biome])) / maxf(0.15, minf(0.6, float(durs[first_of_biome]))), 0.0, 1.0)
	_plate_a.texture = MapRouteArt.backdrop(prev_biome)
	_plate_b.texture = MapRouteArt.backdrop(biome)
	var plate_dim := Color(0.80, 0.80, 0.84) if UITheme.is_light() else Color(0.62, 0.62, 0.68)
	_plate_a.modulate = Color(plate_dim, (1.0 - fade) * (1.0 - k_rev))
	_plate_b.modulate = Color(plate_dim, fade * (1.0 - k_rev))
	_veil.color = Color(_quiet_color(), 0.30 + 0.70 * k_rev)

	# Ending: stamp the outcome on the last encounter, then the parade fills in
	# wave by wave while the painting fades and the camera pulls back.
	if t >= fe:
		var a: float = clampf((t - fe) / 0.3, 0.0, 1.0) * (1.0 - clampf((k_rev - 0.6) / 0.4, 0.0, 1.0))
		_stamp.visible = a > 0.0
		_stamp.text = _outcome_text()
		_stamp.add_theme_color_override("font_color", _outcome_color())
		_stamp.modulate.a = a
		_stamp.scale = Vector2.ONE * (1.0 + 0.12 * (1.0 - clampf((t - fe) / 0.3, 0.0, 1.0)))
		if not _beat_played and t >= fe + 0.08:
			_beat_played = true
			_play(0.62, -12.0)
	else:
		_stamp.visible = false
	_end_btn.visible = false

func _play(pitch: float, db: float) -> void:
	if _sfx == null or DisplayServer.get_name() == "headless":
		return
	_sfx.pitch_scale = pitch
	_sfx.volume_db = db
	_sfx.play()

func _outcome_text() -> String:
	if recap.outcome == "victory":
		return "✦  VICTORY  ·  WAVE %d  ✦" % recap.final_round
	if recap.outcome == "defeat":
		return "☠  DEFEATED ON WAVE %d" % recap.final_round
	return "RUN IN PROGRESS"

func _outcome_color() -> Color:
	return DefeatReportView.gold() if recap.outcome == "victory" else DefeatReportView.crimson()

func _fill_top_journey(i: int, ended: bool) -> void:
	var f: Dictionary = recap.fights[i]
	_wave_lbl.text = "WAVE %d" % int(f["round"])
	_wave_lbl.add_theme_color_override("font_color", DefeatReportView.gold())
	var where: Array = [_biome_name(int(f["biome"]))]
	var type_name := RunMap.type_name(int(f["type"]))
	var head := _headliner(f)
	where.append(("%s: %s" % [type_name.to_upper(), head]) if head != "" and int(f["type"]) != RunMap.NodeType.BATTLE else type_name)
	_where_lbl.text = "  ·  ".join(where)
	var last: bool = i == _n - 1
	var result := "Won ✓"
	if last and ended:
		result = "Victory ✦" if recap.outcome == "victory" else ("Defeat ✕" if not bool(f["won"]) else "Won ✓")
	elif last and not bool(f["won"]):
		result = "…"
	_chips_lbl.text = "%s  ·  %s  ·  fight %d of %d" % [_tier_name(int(f["tier"])), result, i + 1, _n]
	if recap.is_partial():
		_note_lbl.text = "Recorded from Wave %d - earlier waves were not recorded." % recap.coverage_from_round
		_note_lbl.visible = true

# ── Skip / overview ───────────────────────────────────────────────────────────

# Idempotent: safe from any frame of the journey, the ending, or the overview.
func skip() -> void:
	if mode == Mode.JOURNEY:
		_enter_overview()

func _enter_overview() -> void:
	if _sfx:
		_sfx.stop()
	mode = Mode.OVERVIEW
	if _n > 0:
		_t = journey_total()
	_layout()
	_route.overview = true
	_route.departed.clear()
	_flyer.flights.clear()
	_flyer.queue_redraw()
	_ov_flight = {}
	_route.road_upto = -1.0
	_route.active = -1
	_plate_a.modulate.a = 0.0
	_plate_b.modulate.a = 0.0
	_veil.color = Color(_quiet_color(), 1.0)
	_stamp.visible = false
	_skip_btn.visible = false
	_skip_hint.visible = false
	_end_btn.visible = true
	_transport.visible = true
	_hint_lbl.visible = _size.y >= 760.0
	_zoom_bar.visible = true
	_fill_top_overview()
	# Frame: a short route shows whole; a long one eases in to a readable zoom
	# on its last stop (the selection) so every creature can be seen.
	_route.frame_all()
	var pick := -1
	if _n > 0:
		pick = int(_step_stop[_n - 1])
	elif not _route.stops.is_empty():
		pick = _route.stops.size() - 1
	_select_stop(pick, false, false)
	if pick >= 0 and _route.zoom < OVERVIEW_ZOOM * 0.5:
		# The run's end sits toward the right, so the road that led there fills the view.
		_cam_target_x = maxf(float(_route.stops[0]["x"]),
			float(_route.stops[pick]["x"]) - 0.25 * _route.size.x / OVERVIEW_ZOOM)
		_cam_target_zoom = OVERVIEW_ZOOM
		_cam_follow = true
		if UITheme.reduced_motion():
			_route.zoom = OVERVIEW_ZOOM
			_route.cam = Vector2(_cam_target_x, 0.0)
			_route.anchor = Vector2(0.5, 0.5)
			_cam_follow = false
	if not _overview_emitted:
		_overview_emitted = true
		overview_reached.emit()

func _fill_top_overview() -> void:
	_wave_lbl.text = _outcome_text()
	_wave_lbl.add_theme_color_override("font_color", _outcome_color())
	var stops := 0
	for s in _route.stops:
		if String(s["kind"]) == "node":
			stops += 1
	var sim := 0.0
	for f in recap.fights:
		sim += maxf(0.0, float(f["duration"]))
	# Waves cleared never counts the wave that ended the run.
	var cleared: int = recap.final_round if recap.outcome == "victory" else maxi(0, recap.final_round - 1)
	_where_lbl.text = "Waves cleared %d  ·  %d fight%s recorded  ·  %d other stop%s  ·  %s of battle (simulation time)" % [
		cleared, _n, "" if _n == 1 else "s", stops, "" if stops == 1 else "s", BattleRecorder.fmt_time(sim)]
	_crystal_lbl.text = "+%s crystals earned" % DefeatReportView.fmt_n(recap.crystals)
	_crystal_row.visible = recap.is_final()
	var notes: Array = []
	if recap.is_partial():
		notes.append("Recorded from Wave %d - earlier waves were not recorded and are not counted." % recap.coverage_from_round)
	notes.append_array(recap.limits_hit)
	_note_lbl.text = " ".join(notes)
	_note_lbl.visible = not notes.is_empty()

# ── Selection = replay point ──────────────────────────────────────────────────

# The last fight at or before route stop `si` (-1 = before the first fight).
func _point_of(si: int) -> int:
	var best := -1
	for f in range(_n):
		var s: int = int(_step_stop[f])
		if s >= 0 and s <= si:
			best = f
	return best

func _first_stop() -> int:
	for i in range(_route.stops.size()):
		if String(_route.stops[i]["kind"]) != "gap":
			return i
	return -1

# Select a stop. `grow` animates a newly reached fight's gains (forward steps);
# `move_camera` pans only when the stop is near or past an edge of the route.
func _select_stop(si: int, grow: bool, move_camera: bool = true) -> void:
	if si < 0 or si >= _route.stops.size():
		return
	var prev_point := _point_of(_sel)
	_sel = si
	_route.selected = si
	if move_camera:
		var p := _route.to_screen(_route.world_pos(si))
		var w: float = _route.size.x
		if _cam_follow or p.x < w * 0.2 or p.x > w * 0.8:
			if not _cam_follow:
				_cam_target_zoom = _route.zoom
			_cam_target_x = float(_route.stops[si]["x"])
			_cam_follow = true
	var point := _point_of(si)
	var animate: bool = grow and point != prev_point and point >= 0 and not UITheme.reduced_motion()
	_grow_t = 0.0 if animate else -1.0
	# Stepping onto a fight bops a copy of its icon into the parade, as in the
	# journey; the wave's sprites appear when it lands.
	_ov_flight = {"fi": point, "age": 0.0} if animate else {}
	_apply_point(point, 0.0 if animate else 1.0, 0.0 if animate else 1.0)
	_update_info()
	_route.queue_redraw()

# The chart and the parade at a replay point. The parade's part is optional:
# during a forward step it waits for the falling icon to land.
func _apply_point(point: int, k_chart: float, k_parade: float = -1.0) -> void:
	_chart.set_point(point, k_chart)
	if k_parade >= 0.0:
		_parade.set_upto(point, k_parade)
		_update_parade_head()
		_scroll_parade_to_latest()

# A running count while the parade fills; the run's total once it is complete.
func _update_parade_head() -> void:
	if _parade_head_lbl == null:
		return
	var total: int = int(_parade_head_lbl.get_meta("total", 0))
	var summoned: int = int(_parade_head_lbl.get_meta("summoned", 0))
	var shown: int = _parade.total_shown()
	if shown >= total:
		_parade_head_lbl.text = "Total %s%s" % [DefeatReportView.fmt_n(total),
			(" (incl. %s summoned)" % DefeatReportView.fmt_n(summoned)) if summoned > 0 else ""]
	else:
		_parade_head_lbl.text = "%s so far  ·  %s by the end" % [DefeatReportView.fmt_n(shown), DefeatReportView.fmt_n(total)]

# Fight j's falling icon at `age`: from its route node (where the node is on
# screen right now) to where its wave's sprites go in the parade, kept inside
# the parade's visible area (the parade scrolls to it as it lands).
func _flight_for(j: int, age: float) -> Dictionary:
	var sj: int = int(_step_stop[j])
	var s: Dictionary = _route.stops[sj]
	var from: Vector2 = _route.position + _route.to_screen(_route.world_pos(sj))
	var vis := Rect2(_parade_scroll.global_position - _root.global_position, _parade_scroll.size)
	var anchor := _parade.group_anchor(j)
	var to: Vector2
	if anchor.x < 0.0:
		to = vis.position + Vector2(40.0, vis.size.y * 0.5)     # it defeated nothing
	else:
		to = _parade.global_position - _root.global_position + anchor
		to.y = clampf(to.y, vis.position.y + 10.0, vis.end.y - 10.0)
	var r: float = RecapRouteView.NODE_R * clampf(_route.zoom, 0.25, 1.0) * _route.vfit()
	if int(s["type"]) == RunMap.NodeType.BOSS:
		r *= 1.3
	elif int(s["type"]) == RunMap.NodeType.ELITE:
		r *= 1.12
	return {"from": from, "to": to, "age": age, "icon": String(s["icon"]), "tier": int(s["tier"]), "r": r}

func _scroll_parade_to_latest() -> void:
	if _parade_scroll == null:
		return
	var bottom: float = _parade.latest_bottom()
	var view_h: float = _parade_scroll.size.y
	if bottom > float(_parade_scroll.scroll_vertical) + view_h or bottom < float(_parade_scroll.scroll_vertical):
		_parade_scroll.scroll_vertical = int(maxf(0.0, bottom - view_h + 4.0))

func _select(key: String, _move_camera: bool = true) -> void:
	_select_stop(_route.stop_index(key), false)

func selected_key() -> String:
	return String(_route.stops[_sel]["key"]) if _sel >= 0 and _sel < _route.stops.size() else ""

func selected_index() -> int:
	return _sel

# Back / forward, skipping the "not recorded" lead-in. Stops any replay.
func step(dir: int, from_play: bool = false) -> void:
	if mode != Mode.OVERVIEW or _route.stops.is_empty():
		return
	if not from_play:
		_set_playing(false)
	var i: int = _sel + dir
	while i >= 0 and i < _route.stops.size() and String(_route.stops[i]["kind"]) == "gap":
		i += dir
	if i < 0 or i >= _route.stops.size():
		return
	_select_stop(i, dir > 0)

func toggle_play() -> void:
	if mode != Mode.OVERVIEW or _route.stops.is_empty():
		return
	if _playing:
		_set_playing(false)
		return
	# From the end, a replay starts over from the first stop.
	if _sel >= _route.stops.size() - 1:
		_select_stop(_first_stop(), false)
	_play_t = 0.0
	_set_playing(true)

func _set_playing(on: bool) -> void:
	_playing = on
	if _play_btn:
		_play_btn.text = "❚❚" if on else "▶"
		_play_btn.tooltip_text = "Pause the replay (Space / controller X)" if on \
			else "Replay the run from the selected stop (Space / controller X)"

func overview_tick(dt: float) -> void:
	if _playing:
		_play_t += dt
		if _play_t >= PLAY_STEP:
			# One stop per frame at most: a hitch never skips stops or piles up.
			_play_t = minf(_play_t - PLAY_STEP, PLAY_STEP * 0.5)
			if _sel >= _route.stops.size() - 1:
				_set_playing(false)
			else:
				step(1, true)
				if _sel >= _route.stops.size() - 1:
					_set_playing(false)
	if _grow_t >= 0.0:
		_grow_t += dt
		var k: float = _ease(_grow_t / GROW_TIME)
		_apply_point(_point_of(_sel), k)
		if _grow_t >= GROW_TIME:
			_grow_t = -1.0
	_flyer.flights.clear()
	if not _ov_flight.is_empty():
		_ov_flight["age"] = float(_ov_flight["age"]) + dt
		var fi: int = int(_ov_flight["fi"])
		var age: float = float(_ov_flight["age"])
		if RecapFlyer.landed(age):
			var kp: float = clampf((age - RecapFlyer.TOTAL_T) / LAND_FILL, 0.0, 1.0)
			_parade.set_upto(fi, kp)
			_update_parade_head()
			_scroll_parade_to_latest()
			if kp >= 1.0:
				_ov_flight = {}
		elif fi >= 0 and fi < _n and int(_step_stop[fi]) >= 0:
			_flyer.flights.append(_flight_for(fi, age))
	_flyer.queue_redraw()
	if _cam_follow and _route:
		var a: float = 1.0 - exp(-dt * 7.0)
		_route.anchor = _route.anchor.lerp(Vector2(0.5, 0.5), a)
		_route.cam.x = lerpf(_route.cam.x, _cam_target_x, a)
		_route.cam.y = lerpf(_route.cam.y, 0.0, a)
		_route.zoom = lerpf(_route.zoom, _cam_target_zoom, a)
		if absf(_route.cam.x - _cam_target_x) < 0.5 and absf(_route.zoom - _cam_target_zoom) < 0.002:
			_route.cam.x = _cam_target_x
			_route.zoom = _cam_target_zoom
			_cam_follow = false
	if _route:
		_route.queue_redraw()        # selection ring pulse

func _stop_line(si: int) -> String:
	if si < 0 or si >= _route.stops.size():
		return ""
	var s: Dictionary = _route.stops[si]
	if String(s["kind"]) == "gap":
		return String(s["label"])
	if String(s["kind"]) != "fight":
		if int(s["type"]) == RunMap.NodeType.RELIC:
			return "%s start  ·  where the run entered this biome - no fight, so no battle report" % _biome_name(int(s["biome"]))
		return "%s  ·  wave %d slot  ·  %s  ·  the run took this stop instead of the wave's fight - no battle report" % [
			RunMap.type_name(int(s["type"])), int(s["round"]), _biome_name(int(s["biome"]))]
	var f: Dictionary = recap.fights[int(s["fight"])]
	var bits: Array = ["Wave %d" % int(f["round"]), RunMap.type_name(int(f["type"])), _tier_name(int(f["tier"])),
		_biome_name(int(f["biome"]))]
	var head := _headliner(f)
	if head != "":
		bits.append(head)
	bits.append("Won" if bool(f["won"]) else "Lost - the run ended here")
	if float(f["duration"]) >= 0.0:
		bits.append(BattleRecorder.fmt_time(float(f["duration"])))
	bits.append("%d defeat%s" % [int(f["defeat_total"]), "" if int(f["defeat_total"]) == 1 else "s"])
	return "  ·  ".join(bits)

func _stop_tooltip(si: int) -> String:
	var t := _stop_line(si).replace("  ·  ", "\n")
	if si >= 0 and si < _route.stops.size() and String(_route.stops[si]["kind"]) == "fight":
		t += "\n\nClick to select; click the selected fight again to open its report."
	return t

func _update_info() -> void:
	var si := _sel
	var line := _stop_line(si)
	var is_fight: bool = si >= 0 and String(_route.stops[si]["kind"]) == "fight"
	var available := false
	if is_fight:
		available = bool(recap.fights[int(_route.stops[si]["fight"])].get("available", false))
		if not available:
			line += "  ·  no report was recorded for this fight"
	_chips_lbl.text = line
	_chips_lbl.tooltip_text = line
	_open_btn.disabled = not available
	_open_btn.text = "Open report" if available else ("No report" if is_fight else "No fight here")
	_open_btn.tooltip_text = "Open this battle's report (Enter / controller A, or click the selected node again)" if available \
		else ("No report was recorded for this fight." if is_fight else "This stop was not a fight.")
	_prev_btn.disabled = si <= _first_stop()
	_next_btn.disabled = si >= _route.stops.size() - 1

func _on_route_click(i: int) -> void:
	if mode != Mode.OVERVIEW:
		return
	_set_playing(false)
	if i == _sel and String(_route.stops[i]["kind"]) == "fight":
		open_fight(String(_route.stops[i]["key"]))    # a second click on the selection opens it
		return
	_select_stop(i, i > _sel)

# ── Fight inspection ──────────────────────────────────────────────────────────

# Opens the recorded fight in the existing per-fight overview. Returns false (and
# opens nothing) for a stop that is not a fight or a fight with no stored report.
func open_fight(key: String) -> bool:
	if mode != Mode.OVERVIEW:
		return false
	var report: Dictionary = recap.report_for(key)
	if report.is_empty():
		return false
	close_hero()
	var f: Dictionary = recap.fight(key)
	_set_playing(false)
	_saved = {"sel": _sel, "cam": _route.cam, "zoom": _route.zoom, "anchor": _route.anchor,
		"parade_scroll": _parade_scroll.scroll_vertical,
		"chart_scroll": _chart._scroll.scroll_horizontal, "metric": _chart.metric}
	mode = Mode.FIGHT
	var won: bool = bool(f["won"])
	var summary := {"biome": _biome_name(int(f["biome"])), "encounter": RunMap.type_name(int(f["type"])),
		"difficulty": RunMapScreen.TIER_NAMES[clampi(int(f["tier"]), 0, 2)]}
	var head := _headliner(f)
	var where := "%s  ·  %s encounter%s  ·  %s difficulty" % [summary["biome"], summary["encounter"],
		(" (%s)" % head) if head != "" else "", summary["difficulty"]]
	var ctx := {"historical": true, "won": won,
		"title": ("WAVE %d  ·  WON" % int(f["round"])) if won else ("☠  WAVE %d  ·  LOST" % int(f["round"])),
		"where": where, "back_label": "◀  Back to Run Overview",
		"reduced_detail": report.get("reduced_detail", [])}
	_fight_view = DefeatReportView.new()
	_fight_layer.add_child(_fight_view)
	_fight_view.setup(summary, report, _size, ctx)
	_fight_view.return_pressed.connect(close_fight)
	_fight_view.reveal_now()
	_fight_layer.visible = true
	_fight_view._button.grab_focus.call_deferred()
	return true

func close_fight() -> void:
	if mode != Mode.FIGHT:
		return
	if _fight_view and is_instance_valid(_fight_view):
		_fight_view.queue_free()
	_fight_view = null
	_fight_layer.visible = false
	mode = Mode.OVERVIEW
	# Put the overview back exactly as it was.
	_select_stop(int(_saved.get("sel", _sel)), false, false)
	_route.cam = _saved.get("cam", _route.cam)
	_route.zoom = _saved.get("zoom", _route.zoom)
	_route.anchor = _saved.get("anchor", _route.anchor)
	_cam_follow = false
	_chart.set_metric(int(_saved.get("metric", _chart.metric)))
	_route.queue_redraw()
	_restore_scroll.call_deferred(int(_saved.get("parade_scroll", 0)), int(_saved.get("chart_scroll", 0)))
	# Enter / A goes back to opening the selected fight, not the report's button.
	var fo := get_viewport().gui_get_focus_owner() if get_viewport() else null
	if fo:
		fo.release_focus()

func _restore_scroll(ps: int, cs: int) -> void:
	_parade_scroll.scroll_vertical = ps
	_chart._scroll.scroll_horizontal = cs

func fight_view() -> DefeatReportView:
	return _fight_view

# ── Hero breakdown ────────────────────────────────────────────────────────────

# Opens one hero's damage breakdown, cumulative to the replay point the chart is
# showing. In the journey the clock holds while it is open; if the current
# fight's gains are still growing in, the clock first moves to where they are
# complete, so the card and the bar behind it show the same numbers.
func open_hero(uid: int) -> bool:
	if mode == Mode.FIGHT or recap == null:
		return false
	var hero: Dictionary = {}
	for h in recap.heroes:
		if int(h["uid"]) == uid:
			hero = h
	if hero.is_empty():
		return false
	var point := -1
	if mode == Mode.JOURNEY:
		var su := _step_at(_t)
		point = int(su.x)
		if su.y < BAR_TO and _t < float(_plan["fights_end"]):
			_t = float(_plan["starts"][point]) + BAR_TO * float(_plan["durations"][point])
			_apply_time()
	else:
		_set_playing(false)
		point = _point_of(_sel)
		if _grow_t >= 0.0:
			_grow_t = -1.0
			_apply_point(point, 1.0)
	close_hero()
	_hero_uid = uid
	_hero_detail = RecapHeroDetail.new()
	_hero_layer.add_child(_hero_detail)
	_hero_detail.setup(recap, hero, point, String(_chart.state_of(uid)["text"]), _size)
	_hero_detail.closed.connect(close_hero)
	_hero_layer.visible = true
	_center_hero()
	_center_hero.call_deferred()      # again once its labels have measured themselves
	_hero_detail.focus_close.call_deferred()
	return true

func close_hero() -> void:
	if _hero_detail and is_instance_valid(_hero_detail):
		_hero_detail.queue_free()
	_hero_detail = null
	_hero_uid = -1
	if _hero_layer:
		_hero_layer.visible = false

func hero_open() -> bool:
	return _hero_uid >= 0

func hero_detail() -> RecapHeroDetail:
	return _hero_detail

func _center_hero() -> void:
	if _hero_detail == null or not is_instance_valid(_hero_detail):
		return
	_hero_detail.reset_size()
	var sz: Vector2 = _hero_detail.get_combined_minimum_size()
	_hero_detail.size = sz
	_hero_detail.position = ((_size - sz) * 0.5).max(Vector2(8, 8))

# ── Input ─────────────────────────────────────────────────────────────────────

static func is_back(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		return true
	if event is InputEventJoypadButton and event.pressed:
		var jb := event as InputEventJoypadButton
		return jb.button_index == JOY_BUTTON_BACK or jb.button_index == JOY_BUTTON_B
	return false

static func _key(event: InputEvent, code: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == code

static func _pad(event: InputEvent, button: JoyButton) -> bool:
	return event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == button

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if hero_open():
		# The card is modal: Back closes it; its Close button keeps Enter / A.
		if is_back(event):
			close_hero()
			get_viewport().set_input_as_handled()
		return
	if is_back(event):
		match mode:
			Mode.JOURNEY:
				skip()
				get_viewport().set_input_as_handled()
			Mode.FIGHT:
				close_fight()
				get_viewport().set_input_as_handled()
			Mode.OVERVIEW:
				if context == "menu":
					_on_end_pressed()
					get_viewport().set_input_as_handled()
				elif _playing:
					_set_playing(false)
					get_viewport().set_input_as_handled()
		return
	if mode != Mode.OVERVIEW:
		return
	var handled := true
	if event.is_action_pressed("ui_left"):
		step(-1)
	elif event.is_action_pressed("ui_right"):
		step(1)
	elif _key(event, KEY_SPACE) or _pad(event, JOY_BUTTON_X):
		toggle_play()
	elif _key(event, KEY_1):
		_chart.set_metric(0)
	elif _key(event, KEY_2):
		_chart.set_metric(1)
	elif _key(event, KEY_3):
		_chart.set_metric(2)
	elif _key(event, KEY_4):
		_chart.set_metric(RecapHeroChart.TOTAL)
	elif _pad(event, JOY_BUTTON_LEFT_SHOULDER):
		_chart.cycle_metric(-1)
	elif _pad(event, JOY_BUTTON_RIGHT_SHOULDER):
		_chart.cycle_metric(1)
	elif event.is_action_pressed("ui_accept"):
		# A focused button keeps Enter / A for itself (Tab reaches every button).
		var fo := get_viewport().gui_get_focus_owner()
		if fo is Button:
			handled = false
		else:
			open_fight(selected_key())
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()

func _on_end_pressed() -> void:
	if context == "terminal":
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		return
	visible = false
	closed.emit()
	queue_free()
