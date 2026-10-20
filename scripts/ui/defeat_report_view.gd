class_name DefeatReportView
extends PanelContainer
# The defeat infographic (2026-10-07). Pure presentation: it is handed two plain
# dictionaries and never touches a unit, the combat manager or any live stat.
#
#   summary  RUN-level facts from main_game._defeat_summary()
#   report   the frozen FINAL-BATTLE report from BattleRecorder.snapshot()
#
# The two are labelled and laid out apart on purpose: "RUN TOTALS" strip under the
# header, "FINAL BATTLE" for everything measured in the fight that ended the run.
#
# Hierarchy: header (outcome + reward) -> run totals -> timeline -> hero cards
# -> enemy survivors -> one factual takeaway. Hero cards are in ROSTER order,
# never sorted by output, so a damage ranking cannot imply a support was useless;
# every bar is scaled against the team's best on THAT metric only, and each row's
# tooltip states the exact unit and denominator.

signal return_pressed

const MAX_W := 1260.0
const MARGIN := 18.0

var _summary: Dictionary = {}
var _report: Dictionary = {}
# Historical inspection from the run recap (2026-10-07). Empty = the live final-
# battle report, exactly as before. With {"historical": true, ...} the SAME view
# shows one recorded fight: per-fight labels, no run-level strip or crystals
# (those are whole-run facts, never one fight's), and a Back button.
#   title, won, where, back_label, reduced_detail (Array of strings)
var _ctx: Dictionary = {}
var _avail: Vector2 = Vector2(1920, 1080)
var _scroll: ScrollContainer
var _content: VBoxContainer
var _grid: GridContainer
var _timeline: BattleTimeline
var _button: Button
var _reveal: Array[Control] = []
var _tween: Tween
var _fit_pass := 0

# ── Palette ───────────────────────────────────────────────────────────────────

static func _c(dark: Color, light: Color) -> Color:
	return light if UITheme.is_light() else dark

static func gold() -> Color:     return _c(Color(1.0, 0.84, 0.45), Color(0.50, 0.34, 0.06))
static func crimson() -> Color:  return _c(Color(0.95, 0.32, 0.30), Color(0.62, 0.12, 0.10))
static func ink() -> Color:      return UITheme.menu_body_color()
static func muted() -> Color:    return UITheme.menu_subtitle_color()
static func col_dealt() -> Color:  return _c(Color(0.95, 0.62, 0.25), Color(0.78, 0.42, 0.08))
static func col_taken() -> Color:  return _c(Color(0.90, 0.33, 0.33), Color(0.66, 0.14, 0.14))
static func col_heal() -> Color:   return _c(Color(0.40, 0.85, 0.55), Color(0.12, 0.50, 0.25))
static func col_shield() -> Color: return _c(Color(0.50, 0.70, 1.0), Color(0.15, 0.38, 0.75))
static func col_alive() -> Color:  return _c(Color(0.86, 0.70, 0.28), Color(0.70, 0.50, 0.10))

static func fmt_n(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out

static func fmt_s(t: float) -> String:
	return BattleRecorder.fmt_time(t)

# ── Entry ─────────────────────────────────────────────────────────────────────

func setup(summary: Dictionary, report: Dictionary, available: Vector2, context: Dictionary = {}) -> void:
	_summary = summary
	_report = report
	_ctx = context
	_avail = available
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := StyleBoxFlat.new()
	box.bg_color = _c(Color(0.105, 0.10, 0.10), Color(0.93, 0.89, 0.80))
	box.border_color = gold()
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(MARGIN)
	add_theme_stylebox_override("panel", box)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gutter := MarginContainer.new()
	gutter.add_theme_constant_override("margin_right", 14)   # clear of the scrollbar
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_child(_content)
	_scroll.add_child(gutter)

	_content.add_child(_build_header())
	var accent := ColorRect.new()
	accent.color = gold() if (_historical() and bool(_ctx.get("won", false))) else crimson()
	accent.custom_minimum_size = Vector2(0, 3)
	_content.add_child(accent)
	if not _historical():
		_content.add_child(_build_run_strip())
	_content.add_child(_build_battle_section())
	_content.add_child(_build_timeline_section())
	_content.add_child(_build_heroes_section())
	_content.add_child(_build_enemy_section())
	_content.add_child(_build_takeaway())

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_button = Button.new()
	_button.text = String(_ctx.get("back_label", "Return to Main Menu"))
	UITheme.style_button(_button)
	UITheme.apply_font(_button, UITheme.FONT_HEADER)
	_button.custom_minimum_size = Vector2(300, 48)
	_button.pressed.connect(func(): return_pressed.emit())
	row.add_child(_button)
	root.add_child(row)

	for c in _content.get_children():
		if c != accent:
			_reveal.append(c)
	fit(available)

# Size to the window, then shrink-wrap to the content (scrolling only when the
# content is taller than the window). Safe to call again on a window resize.
func fit(available: Vector2) -> void:
	_avail = available
	var w: float = minf(clampf(available.x - 32.0, 560.0, MAX_W), maxf(300.0, available.x - 8.0))
	var inner: float = w - MARGIN * 2.0
	if _grid:
		_grid.columns = 2 if (inner >= 940.0 and _report.get("heroes", []).size() > 1) else 1
	custom_minimum_size = Vector2(w, 0)
	size = Vector2(w, 10)
	_fit_pass = 0
	_settle.call_deferred()

# Content wraps with width, so measure after layout has run, twice.
func _settle() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	var fixed: float = size.y - _scroll.size.y
	var want: float = _content.get_combined_minimum_size().y + 4.0
	var room: float = maxf(120.0, _avail.y - 24.0 - fixed)
	_scroll.custom_minimum_size = Vector2(0, minf(want, room))
	size = Vector2(size.x, 10)
	await get_tree().process_frame
	position = Vector2(maxf(0.0, (_avail.x - size.x) * 0.5), maxf(0.0, (_avail.y - size.y) * 0.5))
	_fit_pass += 1
	if _fit_pass < 2:
		_settle.call_deferred()

func play_reveal() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	for i in range(_reveal.size()):
		var sec: Control = _reveal[i]
		sec.modulate.a = 0.0
		_tween.tween_property(sec, "modulate:a", 1.0, 0.35).set_delay(0.08 * i) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _button:
		_button.grab_focus()

# Capture/test hook: skip the animation and show everything.
func reveal_now() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	for sec in _reveal:
		sec.modulate.a = 1.0

func timeline() -> BattleTimeline:
	return _timeline

# ── Small builders ────────────────────────────────────────────────────────────

func _lbl(text: String, px: int, col: Color, read: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if read:
		UITheme.apply_read_font(l, px)
	else:
		UITheme.apply_font(l, px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l

func _card_box(accent: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = _c(Color(0.145, 0.135, 0.13), Color(0.97, 0.94, 0.87))
	b.border_color = accent
	b.set_border_width_all(1)
	b.set_corner_radius_all(5)
	b.set_content_margin_all(12)
	return b

func _chip_box() -> StyleBoxFlat:
	var b := _card_box(_c(Color(0.42, 0.36, 0.24), Color(0.62, 0.52, 0.34)))
	b.set_content_margin_all(7)
	b.content_margin_left = 12
	b.content_margin_right = 12
	return b

func _card(accent: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	var a := accent if accent.a > 0.0 else _c(Color(0.42, 0.36, 0.24), Color(0.62, 0.52, 0.34))
	p.add_theme_stylebox_override("panel", _card_box(a))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p

func _heading(text: String, sub: String = "") -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_lbl(text, UITheme.FONT_HEADER, gold()))
	if sub != "":
		h.add_child(_lbl(sub, UITheme.FONT_BODY, muted(), true))
	var rule := ColorRect.new()
	rule.color = Color(gold(), 0.35)
	rule.custom_minimum_size = Vector2(20, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(rule)
	return h

func _chip(caption: String, value: String, tip: String = "") -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _chip_box())
	var v := HBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(_lbl(caption, UITheme.FONT_BODY, muted()))
	var val := _lbl(value, UITheme.FONT_VALUE, ink())
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(val)
	p.add_child(v)
	if tip != "":
		p.tooltip_text = tip
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p

# Roster portrait (animated idle when the hero has one) or an initial.
func _hero_portrait(h: Dictionary, px: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px, px)
	var cls: int = int(h.get("cls", -1))
	if String(h.get("portrait", "")) != "" and VisualUnit.HERO_SPRITE_PATHS.has(cls):
		var hp := HeroPortrait.new()
		hp.custom_minimum_size = Vector2(px, px)
		hp.size = Vector2(px, px)
		holder.add_child(hp)
		hp.setup(cls)
		return holder
	return _initial_badge(String(h.get("name", "?")), px)

func _initial_badge(name: String, px: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(px, px)
	var bg := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = _c(Color(0.25, 0.22, 0.20), Color(0.72, 0.64, 0.50))
	sb.set_corner_radius_all(int(px * 0.5))
	bg.add_theme_stylebox_override("panel", sb)
	bg.size = Vector2(px, px)
	holder.add_child(bg)
	var l := _lbl(name.substr(0, 1).to_upper(), UITheme.FONT_VALUE, ink())
	l.size = Vector2(px, px)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(l)
	return holder

static var _trim_cache: Dictionary = {}

# A static texture cropped to its visible pixels, so small-in-frame sprites do
# not render as specks. Cached per path.
static func _enemy_texture(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if _trim_cache.has(path):
		return _trim_cache[path]
	var tex: Texture2D = load(path) as Texture2D
	var out: Texture2D = tex
	if tex:
		var img: Image = tex.get_image()
		if img:
			var used: Rect2i = img.get_used_rect()
			if used.size.x > 0 and used.size.y > 0 and used.size != img.get_size():
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(used)
				out = at
	_trim_cache[path] = out
	return out

func _enemy_portrait(e: Dictionary, px: float) -> Control:
	var tex := _enemy_texture(String(e.get("portrait", "")))
	if tex == null:
		return _initial_badge(String(e.get("name", "?")), px)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr

# ── Header + run totals ───────────────────────────────────────────────────────

func _historical() -> bool:
	return bool(_ctx.get("historical", false))

func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var where := "%s  ·  %s encounter  ·  %s difficulty" % [_summary.get("biome", "?"),
		_summary.get("encounter", "Battle"), _summary.get("difficulty", "?")]
	if _historical():
		var won := bool(_ctx.get("won", false))
		left.add_child(_lbl(String(_ctx.get("title", "RECORDED BATTLE")), UITheme.FONT_DISPLAY,
			gold() if won else crimson()))
		left.add_child(_lbl(String(_ctx.get("where", where)), UITheme.FONT_VALUE, ink()))
		left.add_child(_lbl("Recorded battle from this run. This fight lasted %s (simulation time, unaffected by game speed or pause)"
			% fmt_s(float(_report.get("duration", 0.0))), UITheme.FONT_BODY, muted(), true))
		h.add_child(left)
		return h          # crystals are a whole-run figure: never shown as one fight's
	left.add_child(_lbl("☠  DEFEATED", UITheme.FONT_DISPLAY, crimson()))
	left.add_child(_lbl(where, UITheme.FONT_VALUE, ink()))
	left.add_child(_lbl("Final fight lasted %s (simulation time, unaffected by game speed or pause)"
		% fmt_s(float(_report.get("duration", 0.0))), UITheme.FONT_BODY, muted(), true))
	h.add_child(left)

	var reward := PanelContainer.new()
	reward.add_theme_stylebox_override("panel", _card_box(Color(0.35, 0.62, 0.95)))
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 10)
	var icon := UITheme.currency_icon("gem")
	icon.custom_minimum_size = Vector2(38, 38)
	rh.add_child(icon)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 0)
	rv.add_child(_lbl("CRYSTALS EARNED", UITheme.FONT_BODY, muted()))
	rv.add_child(_lbl("+%s" % fmt_n(int(_summary.get("crystals", 0))), UITheme.FONT_HEADER,
		_c(Color(0.45, 0.78, 1.0), Color(0.12, 0.40, 0.72))))
	rh.add_child(rv)
	reward.add_child(rh)
	reward.tooltip_text = "Crystals carry over — spend them on the crystal tree for your next run."
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(reward)
	return h

func _build_run_strip() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(_heading("RUN TOTALS", "the whole run, not just the last fight"))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	var cleared := int(_summary.get("rounds_cleared", 0))
	row.add_child(_sized(_chip("Rounds cleared", fmt_n(cleared),
		"Fights you won this run. The round you lost is not counted."), 250))
	row.add_child(_sized(_chip("Fell on round", fmt_n(int(_summary.get("fell_on", cleared + 1))),
		"The round whose fight ended the run."), 250))
	row.add_child(_sized(_chip("Enemies defeated", fmt_n(int(_summary.get("enemies_defeated", 0))),
		"Enemies defeated across the whole run, including the final fight."), 250))
	v.add_child(row)
	return v

func _sized(c: Control, w: float) -> Control:
	c.custom_minimum_size = Vector2(w, 0)
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return c

# ── Final battle: team strip, timeline ────────────────────────────────────────

func _build_battle_section() -> Control:
	var t: Dictionary = _report.get("team", {})
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(_heading("THIS BATTLE" if _historical() else "FINAL BATTLE",
		"this fight only  ·  %s" % fmt_s(float(_report.get("duration", 0.0)))))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	row.add_child(_sized(_chip("Damage dealt", fmt_n(int(t.get("dealt_hp", 0))),
		"HP removed from enemies by your heroes (and their summons). Overkill and damage soaked by enemy shields are not counted."), 250))
	row.add_child(_sized(_chip("Damage taken", fmt_n(int(t.get("taken_hp", 0))),
		"HP your heroes actually lost. Overkill and shield-absorbed damage are not counted."), 250))
	row.add_child(_sized(_chip("Healing delivered", fmt_n(int(t.get("heal_out", 0))),
		"Effective HP restored on other allies. Self-healing (%s) and overheal are not included." % fmt_n(int(t.get("heal_self", 0)))), 250))
	if int(t.get("taken_shield", 0)) > 0:
		row.add_child(_sized(_chip("Shields absorbed", fmt_n(int(t.get("taken_shield", 0))),
			"Damage soaked by shields on your heroes. Shields that expired unused are not counted."), 250))
	v.add_child(row)
	return v

func _build_timeline_section() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(_heading("TIMELINE", "seconds of simulated fight time"))
	var reduced: Array = _ctx.get("reduced_detail", [])
	if _historical() and not reduced.is_empty():
		var rn := _lbl("Stored marker detail is reduced for this fight: " + " ".join(reduced),
			UITheme.FONT_BODY, muted(), true)
		rn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rn.custom_minimum_size = Vector2(200, 0)
		v.add_child(rn)
	var card := _card()
	_timeline = BattleTimeline.new()
	_timeline.setup(_report)
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(_timeline)
	v.add_child(card)
	return v

# ── Heroes ────────────────────────────────────────────────────────────────────

func _build_heroes_section() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_heading("YOUR HEROES", "in roster order — not ranked"))
	var note := _lbl("Damage and healing are effective amounts: overkill, overheal and expired shields are left out. "
		+ "Each bar is scaled to your team's best on that one measure; hover any row for exact units.",
		UITheme.FONT_BODY, muted(), true)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(200, 0)
	v.add_child(note)
	_grid = GridContainer.new()
	_grid.columns = 1
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heroes: Array = _report.get("heroes", [])
	var mx := {"dealt_hp": 0, "taken_hp": 0, "heal_out": 0, "taken_shield": 0}
	for h in heroes:
		for k in mx.keys():
			mx[k] = maxi(int(mx[k]), int(h[k]))
	for h in heroes:
		_grid.add_child(_build_hero_card(h, mx))
	v.add_child(_grid)
	return v

func _build_hero_card(h: Dictionary, mx: Dictionary) -> Control:
	var duration: float = maxf(float(_report.get("duration", 0.0)), 0.1)
	var team: Dictionary = _report.get("team", {})
	var card := _card(col_alive() if bool(h["survived"]) else Color(crimson(), 0.8))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	card.add_child(hb)
	hb.add_child(_hero_portrait(h, 72.0))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)

	# Name row
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(_lbl(String(h["name"]), UITheme.FONT_VALUE, ink()))
	if int(h.get("level", 0)) > 0:
		top.add_child(_lbl("Lv %d" % int(h["level"]), UITheme.FONT_BODY, muted()))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(_lbl(_status_text(h), UITheme.FONT_BODY,
		col_alive() if bool(h["survived"]) else crimson()))
	vb.add_child(top)

	var dealt := int(h["dealt_hp"])
	var taken := int(h["taken_hp"])
	var heal := int(h["heal_out"])
	var self_heal := int(h["heal_self"])
	var shield := int(h["taken_shield"])

	var tip_dealt := "%s dealt %s damage to enemy HP" % [h["name"], fmt_n(dealt)]
	if int(team.get("dealt_hp", 0)) > 0:
		tip_dealt += " — %d%% of the team's recorded damage" % int(round(100.0 * dealt / float(team["dealt_hp"])))
	tip_dealt += ".\nOverkill is not counted; %s more went into enemy shields." % fmt_n(int(h["dealt_shield"]))
	if int(h.get("dealt_by_summons", 0)) > 0:
		tip_dealt += "\nIncludes %s from summons." % fmt_n(int(h["dealt_by_summons"]))
	vb.add_child(_stat_row("Damage dealt", fmt_n(dealt), float(dealt), float(mx["dealt_hp"]),
		col_dealt(), tip_dealt))

	var tip_taken := "%s lost %s HP." % [h["name"], fmt_n(taken)]
	if int(h.get("max_hp_end", 0)) > 0:
		tip_taken += " That is %d%% of their max HP at the end of the fight (%s)." % [
			int(round(100.0 * taken / float(h["max_hp_end"]))), fmt_n(int(h["max_hp_end"]))]
	tip_taken += "\nOverkill on the killing blow is not counted. Damage soaked by shields is listed separately."
	vb.add_child(_stat_row("Damage taken", fmt_n(taken), float(taken), float(mx["taken_hp"]),
		col_taken(), tip_taken))

	var heal_txt := "—"
	if heal > 0 or self_heal > 0:
		heal_txt = fmt_n(heal) if heal > 0 else "—"
		if self_heal > 0:
			heal_txt += "  (+%s self)" % fmt_n(self_heal)
	var tip_heal := "Effective healing %s delivered to OTHER allies: %s HP.\n" % [h["name"], fmt_n(heal)]
	tip_heal += "Self-healing (regen, lifesteal, self-heals) is shown separately: %s HP.\n" % fmt_n(self_heal)
	tip_heal += "Overheal — healing beyond missing HP — is excluded: %s." % fmt_n(int(h["overheal"]))
	if heal == 0 and self_heal == 0:
		tip_heal = "%s restored no HP in this fight (no healing recorded)." % h["name"]
	vb.add_child(_stat_row("Healing", heal_txt, float(heal), float(mx["heal_out"]), col_heal(), tip_heal))

	if int(team.get("taken_shield", 0)) > 0:
		vb.add_child(_stat_row("Shield absorbed", fmt_n(shield), float(shield), float(mx["taken_shield"]),
			col_shield(), "Damage that shields on %s soaked instead of HP: %s.\nCredited to the hero the shield protected, not whoever cast it." % [h["name"], fmt_n(shield)]))

	# Lifeline
	var alive: float = float(h["alive_time"])
	var line := _stat_row("Time alive", "%s / %s" % [fmt_s(alive), fmt_s(duration)], 0.0, 1.0, col_alive(),
		_alive_tip(h, alive, duration))
	var bar: ReportBar = line.get_meta("bar")
	bar.mode = ReportBar.Mode.LIFELINE
	bar.intervals = h["intervals"]
	bar.span = duration
	bar.fill = col_alive()
	var ds: Array = []
	var rs: Array = []
	for ev in _report.get("events", []):
		if ev["hero"] == h["id"]:
			if ev["kind"] == "death": ds.append(float(ev["t"]))
			elif ev["kind"] == "revive": rs.append(float(ev["t"]))
	bar.death_times = ds
	bar.revive_times = rs
	vb.add_child(line)
	return card

func _status_text(h: Dictionary) -> String:
	if bool(h["survived"]):
		return "STANDING AT THE END" if int(h["deaths"]) == 0 else "REVIVED · STANDING"
	var last := 0.0
	for pair in h["intervals"]:
		last = float(pair[1])
	return "FELL AT %s" % fmt_s(last)

func _alive_tip(h: Dictionary, alive: float, duration: float) -> String:
	var parts: Array = []
	for pair in h["intervals"]:
		parts.append("%s–%s" % [fmt_s(float(pair[0])), fmt_s(float(pair[1]))])
	var tip := "%s was alive for %s of the %s fight (%d%%).\nAlive: %s." % [h["name"], fmt_s(alive),
		fmt_s(duration), int(round(100.0 * alive / maxf(duration, 0.1))), ", ".join(parts)]
	if int(h["deaths"]) > 0:
		tip += "\nFell %d time%s, revived %d." % [int(h["deaths"]), "" if int(h["deaths"]) == 1 else "s", int(h["revives"])]
	return tip

func _stat_row(label: String, value_text: String, value: float, max_value: float, fill: Color, tip: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := _lbl(label, UITheme.FONT_BODY, muted())
	l.custom_minimum_size = Vector2(112, 0)
	row.add_child(l)
	var bar := ReportBar.new()
	bar.value = value
	bar.max_value = max_value
	bar.fill = fill
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(80, 14)
	row.add_child(bar)
	var v := _lbl(value_text, UITheme.FONT_BODY, ink())
	v.custom_minimum_size = Vector2(150, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	row.tooltip_text = tip
	row.set_meta("bar", bar)
	return row

# ── Enemies ───────────────────────────────────────────────────────────────────

func _build_enemy_section() -> Control:
	var en: Dictionary = _report.get("enemies", {})
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_heading("ALL ENEMIES", "when the fight ended" if (_historical()
		and bool(_ctx.get("won", false))) else "when the last hero fell"))
	var card := _card()
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	card.add_child(cv)
	var remaining := int(en.get("remaining", 0))
	var seen := int(en.get("seen", 0))
	if seen == 0:
		cv.add_child(_lbl("No enemy units were left standing.", UITheme.FONT_VALUE, ink()))
		v.add_child(card)
		return v
	var hp := int(en.get("hp", 0))
	var mhp := int(en.get("max_hp", 0))
	var pct := int(round(100.0 * hp / float(maxi(mhp, 1))))
	cv.add_child(_lbl("%d of %d enemy unit%s still standing  ·  %s / %s HP left (%d%%)" % [
		remaining, seen, "" if seen == 1 else "s", fmt_n(hp), fmt_n(mhp), pct], UITheme.FONT_VALUE, ink()))
	var agg := ReportBar.new()
	agg.value = float(hp)
	agg.max_value = float(maxi(mhp, 1))
	agg.fill = col_taken()
	agg.custom_minimum_size = Vector2(80, 18)
	agg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agg.tooltip_text = "Combined current HP of the surviving enemies over their combined CURRENT max HP — buffs, debuffs and phase changes included, read live from combat."
	cv.add_child(agg)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for e in en.get("all", en.get("survivors", [])):
		flow.add_child(_enemy_chip(e))
	cv.add_child(flow)
	v.add_child(card)
	return v

func _enemy_chip(e: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _card_box(_c(Color(0.42, 0.30, 0.28), Color(0.62, 0.45, 0.40))))
	p.custom_minimum_size = Vector2(250, 0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	p.add_child(hb)
	hb.add_child(_enemy_portrait(e, 46.0))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var nm := String(e["name"]) + ("  (summon)" if bool(e.get("summoned", false)) else "")
	if int(e["hp"]) <= 0:
		nm += "  (defeated)"
	vb.add_child(_lbl(nm, UITheme.FONT_BODY, ink()))
	var changed: bool = int(e["max_hp"]) != int(e.get("start_max_hp", e["max_hp"]))
	vb.add_child(_lbl("%s / %s HP%s" % [fmt_n(int(e["hp"])), fmt_n(int(e["max_hp"])), " *" if changed else ""],
		UITheme.FONT_BODY, muted()))
	var bar := ReportBar.new()
	bar.value = float(e["hp"])
	bar.max_value = float(maxi(int(e["max_hp"]), 1))
	bar.fill = col_taken()
	bar.custom_minimum_size = Vector2(60, 10)
	vb.add_child(bar)
	var tip := "%s: %s of %s HP remaining." % [e["name"], fmt_n(int(e["hp"])), fmt_n(int(e["max_hp"]))]
	if changed:
		tip += "\n* Max HP is %s now; it was %s when this unit first appeared. The current value includes temporary effects." % [
			fmt_n(int(e["max_hp"])), fmt_n(int(e["start_max_hp"]))]
	p.tooltip_text = tip
	return p

# ── Takeaway ──────────────────────────────────────────────────────────────────

func _build_takeaway() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_heading("TAKEAWAY"))
	var card := _card(Color(gold(), 0.9))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	card.add_child(cv)
	var main: String = String(_report.get("takeaway", ""))
	if main == "":
		main = "Not enough was recorded in this fight to say more."
	var l := _lbl(main, UITheme.FONT_READ, ink(), true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	cv.add_child(l)
	var second := BattleRecorder.damage_share_note(_report)
	if second != "":
		var s := _lbl(second, UITheme.FONT_BODY, muted(), true)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size = Vector2(200, 0)
		cv.add_child(s)
	v.add_child(card)
	return v
