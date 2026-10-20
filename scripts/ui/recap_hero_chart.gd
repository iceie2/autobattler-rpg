class_name RecapHeroChart
extends PanelContainer
# ══════════════════════════════════════════════════════════════════════════════
# The run recap's hero chart (2026-10-07, owner layout): the heroes recruited by
# the replay point along the bottom, left to right in STABLE roster order (never
# ranked), each with ONE vertical bar. A hero's column appears when the replay
# reaches the fight where it first stood on the roster - not before.
#
# Toggles: Damage / Protection / Healing show that one measure; TOTAL stacks the
# three as separate segments (damage at the base, then protection, then healing)
# so the column height is their sum while each part stays readable on its own
# colour, pattern and tooltip. Click any bar for that hero's breakdown.
#
# Each view scales to the values at the current replay point, shared across
# heroes, with headroom and rounded ticks. Seeking backwards shrinks the range.
# The axis prints it. Colour AND pattern (stripes /
# dots / plus marks, RecapMetricBar) carry the measure, never colour alone.
#
# Values are RunRecap.prefix_totals() - sums over immutable fight entries -
# interpolated between fight i-1 and fight i while the replay animates.
# ══════════════════════════════════════════════════════════════════════════════

signal metric_changed(metric: int)
signal hero_clicked(uid: int)

const METRICS := [
	{"name": "Damage", "icon": "res://assets/icons/stat_icons/attack_power.png",
		"tip": "Damage: HP removed from enemies by this hero and its summons. Overkill and damage soaked by enemy shields are excluded - the battle report's \"Damage dealt\"."},
	{"name": "Protection", "icon": "res://assets/icons/stat_icons/defense.png",
		"tip": "Protection: damage absorbed by shields this hero SUPPLIED, on allies and on itself, counted when a shield actually absorbs a hit. Unused shield capacity is not counted. A summon's shields count for its owner; item shields and Mana Shield count for the hero wearing them. Shields with no known source are listed apart as unattributed."},
	{"name": "Healing", "icon": "",
		"tip": "Healing: effective HP this hero restored, on allies AND itself (regen, lifesteal, self-heals). Overheal is excluded. A summon's healing counts for its owner."},
]
const TOTAL := 3                      # the stacked view
const TOTAL_TIP := "Total: damage, protection and healing stacked as three separate segments. The height is their sum; each segment keeps its own colour, pattern and value in the tooltip. They measure different things, so compare segments, not just heights."
const MIN_COL := 76.0                 # px per hero before the chart scrolls sideways

var metric: int = 0
var _recap: RunRecap
var _heroes: Array = []               # everyone who ever fought, in roster order
var _shown: Array = []                # those recruited by the replay point
var _prefix: Array = []
var _scale: Array = [1.0, 1.0, 1.0, 1.0]
var _vals: Dictionary = {}            # uid -> [d, p, h] at the replay point
var _states: Dictionary = {}          # uid -> {text, kind}
var _upto_round: int = 0
var _toggles: Array = []
var _sub: Label
var _foot: Label
var _scroll: ScrollContainer
var _plot: _Plot

func setup(recap: RunRecap) -> void:
	_recap = recap
	_heroes = recap.fighting_heroes()
	_prefix = recap.prefix_totals()
	_scale = [0.0, 0.0, 0.0, 0.0]
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.97, 0.94, 0.87, 0.94) if UITheme.is_light() else Color(0.07, 0.065, 0.06, 0.90)
	box.border_color = DefeatReportView.gold()
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(10)
	add_theme_stylebox_override("panel", box)
	for c in get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	head.add_child(_lbl("HERO CONTRIBUTION", UITheme.FONT_HEADER, DefeatReportView.gold()))
	_sub = _lbl("", UITheme.FONT_BODY, DefeatReportView.muted())
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sub.clip_text = true
	_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_sub)
	var group := ButtonGroup.new()
	_toggles.clear()
	for m in range(4):
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = "%s  [%d]" % [METRICS[m]["name"] if m < 3 else "Total", m + 1]
		if m < 3:
			b.icon = _icon_texture(m)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 20)
		b.custom_minimum_size = Vector2(150 if m < 3 else 120, 44)
		b.tooltip_text = (String(METRICS[m]["tip"]) if m < 3 else TOTAL_TIP) \
			+ "\n\nEach view auto-scales to the highest displayed value at this replay point, with headroom. The range changes as the replay advances or rewinds. Keys 1-4 or controller bumpers switch. Click a bar for that hero's breakdown."
		_style_toggle(b, m == metric)
		b.button_pressed = m == metric
		var mm := m
		b.pressed.connect(func(): set_metric(mm))
		head.add_child(b)
		_toggles.append(b)
	_scroll = ScrollContainer.new()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	_plot = _Plot.new()
	_plot.chart = self
	_plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_plot)
	_foot = _lbl("", UITheme.FONT_BODY, DefeatReportView.muted())
	_foot.clip_text = true
	_foot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_foot)
	var notes: Array = []
	var bench := recap.bench_only_count()
	if bench > 0:
		notes.append("%d more hero%s sat out every recorded fight." % [bench, "" if bench == 1 else "es"])
	var unattr := recap.unattributed_protection()
	if unattr > 0:
		notes.append("Unattributed shield absorption (no known hero source): %s." % DefeatReportView.fmt_n(unattr))
	_foot.text = "  ".join(notes)
	_foot.visible = not notes.is_empty()
	_refresh_sub()

func _lbl(text: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	UITheme.apply_font(l, px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _style_toggle(b: Button, on: bool) -> void:
	var light := UITheme.is_light()
	var box := StyleBoxFlat.new()
	box.bg_color = (Color(0.86, 0.80, 0.68) if light else Color(0.20, 0.18, 0.15)) if on \
		else (Color(0.93, 0.89, 0.80) if light else Color(0.11, 0.10, 0.09))
	box.border_color = DefeatReportView.gold() if on else Color(DefeatReportView.gold(), 0.35)
	box.set_border_width_all(2 if on else 1)
	box.set_corner_radius_all(5)
	box.content_margin_left = 10
	box.content_margin_right = 10
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, box)
	b.add_theme_stylebox_override("focus", UITheme.selection_ring_box(DefeatReportView.gold()))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, DefeatReportView.ink() if on else DefeatReportView.muted())
	UITheme.apply_font(b, UITheme.FONT_BODY)

static var _cross_tex: Texture2D = null

# Damage and protection use the game's stat icons; there is no healing icon in
# the art, so the cross is drawn into a small texture here (no new asset file).
static func _icon_texture(m: int) -> Texture2D:
	var path: String = METRICS[m]["icon"]
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	if _cross_tex == null:
		var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var col := Color(0.30, 0.80, 0.42)
		for y in range(18):
			for x in range(18):
				var in_v: bool = x >= 6 and x <= 11 and y >= 1 and y <= 16
				var in_h: bool = y >= 6 and y <= 11 and x >= 1 and x <= 16
				if in_v or in_h:
					var edge: bool = (in_v and (x == 6 or x == 11) and not in_h) or (in_h and (y == 6 or y == 11) and not in_v) \
						or (in_v and (y == 1 or y == 16)) or (in_h and (x == 1 or x == 16))
					img.set_pixel(x, y, Color(0.05, 0.2, 0.08) if edge else col)
		_cross_tex = ImageTexture.create_from_image(img)
	return _cross_tex

func set_metric(m: int) -> void:
	metric = clampi(m, 0, TOTAL)
	for i in range(_toggles.size()):
		(_toggles[i] as Button).set_pressed_no_signal(i == metric)
		_style_toggle(_toggles[i], i == metric)
	_refresh_sub()
	if _plot:
		_plot.queue_redraw()
	metric_changed.emit(metric)

func cycle_metric(dir: int) -> void:
	set_metric(posmod(metric + dir, 4))

func _refresh_sub() -> void:
	if _sub == null:
		return
	if _heroes.is_empty():
		_sub.text = "No hero contribution was recorded in this run."
		return
	var sc: float = _scale[metric]
	var name: String = "Damage + protection + healing, stacked" if metric == TOTAL else String(METRICS[metric]["name"])
	_sub.text = "%s · whole run, cumulative%s · auto-scale 0-%s · click a bar for its breakdown" % [name,
		(" to Wave %d" % _upto_round) if _upto_round > 0 else "",
		DefeatReportView.fmt_n(int(sc)) if sc > 0.0 else "0 (none recorded)"]

static func short_n(v: int) -> String:
	if v >= 1_000_000:
		return "%.2fM" % (v / 1_000_000.0)
	if v >= 100_000:
		return "%.0fk" % (v / 1000.0)
	if v >= 10_000:
		return "%.1fk" % (v / 1000.0)
	return DefeatReportView.fmt_n(v)

func value_of(uid: int, m: int) -> float:
	var v: Array = _vals.get(uid, [0.0, 0.0, 0.0])
	if m == TOTAL:
		return float(v[0]) + float(v[1]) + float(v[2])
	return float(v[m])

func state_of(uid: int) -> Dictionary:
	return _states.get(uid, {"text": "", "kind": ""})

func upto_round() -> int:
	return _upto_round

# Replay point: fight `step` (index into recap.fights) with `frac` of its gains
# shown. step < 0 = before the first fight; frac 1 = that fight complete.
func set_point(step: int, frac: float) -> void:
	if _recap == null:
		return
	var prev: Dictionary = _prefix[step - 1] if step >= 1 and step - 1 < _prefix.size() else {}
	var cur: Dictionary = _prefix[step] if step >= 0 and step < _prefix.size() else prev
	var f: Dictionary = _recap.fights[step] if step >= 0 and step < _recap.fights.size() else {}
	# Life state flips to this fight's outcome halfway through its growth, so a
	# hero's fall is not announced before the fight has played out on screen.
	var f_state: Dictionary = f
	if frac < 0.5:
		f_state = _recap.fights[step - 1] if step >= 1 and step - 1 < _recap.fights.size() else {}
	_upto_round = int(f["round"]) if not f.is_empty() else 0
	# Only heroes already recruited at this point get a column (owner, 2026-10-07).
	_shown.clear()
	for h in _heroes:
		var fr: int = int(h["first_round"])
		if _upto_round > 0 and fr > 0 and fr <= _upto_round:
			_shown.append(h)
	for h in _heroes:
		var uid: int = int(h["uid"])
		var a: Array = prev.get(uid, [0, 0, 0])
		var b: Array = cur.get(uid, a)
		var vals: Array = []
		for m in range(3):
			vals.append(lerpf(float(a[m]), float(b[m]), clampf(frac, 0.0, 1.0)))
		_vals[uid] = vals
		_states[uid] = life_state(h, f_state)
	_scale = [0.0, 0.0, 0.0, 0.0]
	for h in _shown:
		for m in range(4):
			_scale[m] = maxf(_scale[m], value_of(int(h["uid"]), m))
	for m in range(4):
		_scale[m] = axis_max(float(_scale[m]))
	_refresh_sub()
	if _plot:
		_plot.queue_redraw()

func show_final() -> void:
	set_point(_recap.fights.size() - 1, 1.0)

# Life state at a replay point (a fight entry, or {} = before any fight).
static func life_state(h: Dictionary, f: Dictionary) -> Dictionary:
	var uid: int = int(h["uid"])
	if f.is_empty():
		return {"text": "Joins W%d" % int(h["first_round"]), "kind": "future"}
	var rnd: int = int(f["round"])
	var in_rows := false
	for row in f["rows"]:
		if int(row[0]) == uid:
			in_rows = true
	if not in_rows and int(h["first_round"]) > rnd:
		return {"text": "Joins W%d" % int(h["first_round"]), "kind": "future"}
	if (f["fallen"] as Array).has(uid):
		return {"text": "☠ Fell W%d" % rnd, "kind": "fell"}
	if (f["revived"] as Array).has(uid):
		return {"text": "↑ Revived W%d" % rnd, "kind": "revived"}
	if in_rows:
		return {"text": "Fought W%d" % rnd, "kind": "fought"}
	if (f.get("bench", []) as Array).has(uid):
		return {"text": "Bench W%d" % rnd, "kind": "bench"}
	if not (f["roster"] as Array).has(uid) and int(h["last_round"]) < rnd:
		return {"text": "Left after W%d" % int(h["last_round"]), "kind": "gone"}
	return {"text": "Not fielded W%d" % rnd, "kind": "out"}

func tooltip_for(i: int) -> String:
	if i < 0 or i >= _shown.size():
		return ""
	var h: Dictionary = _shown[i]
	var uid: int = int(h["uid"])
	var st := state_of(uid)
	return "%s - %s\nDamage %s  ·  Protection %s  ·  Healing %s%s\n\n%s\n\nClick for this hero's breakdown." % [h["name"], st["text"],
		DefeatReportView.fmt_n(int(round(value_of(uid, 0)))), DefeatReportView.fmt_n(int(round(value_of(uid, 1)))),
		DefeatReportView.fmt_n(int(round(value_of(uid, 2)))),
		("  (totals up to Wave %d)" % _upto_round) if _upto_round > 0 else "",
		TOTAL_TIP if metric == TOTAL else String(METRICS[metric]["tip"])]

func heroes() -> Array:
	return _heroes

func shown() -> Array:
	return _shown

func scale_of(m: int) -> float:
	return float(_scale[m])

# Four equal tick intervals, rounded upward with 10% room above the tallest bar.
static func axis_max(value: float) -> float:
	if value <= 0.0:
		return 0.0
	var tick: float = maxf(1.0, value * 1.1 / 4.0)
	var magnitude: float = pow(10.0, floor(log(tick) / log(10.0)))
	return ceil(tick / magnitude) * magnitude * 4.0

# ── the plot ──────────────────────────────────────────────────────────────────
class _Plot extends Control:
	var chart: RecapHeroChart
	const GUTTER := 54.0
	const TOP := 24.0
	const FOOT := 68.0                # portrait + name + state, clear of a horizontal scrollbar

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED or what == NOTIFICATION_MOUSE_EXIT:
			queue_redraw()

	func col_w() -> float:
		var n: int = maxi(1, chart.shown().size())
		return maxf(RecapHeroChart.MIN_COL, (size.x - GUTTER) / float(n))

	func _process(_dt: float) -> void:
		var par := get_parent() as ScrollContainer
		if par == null:
			return
		var want: float = GUTTER + col_w() * float(maxi(1, chart.shown().size()))
		var target: float = want if want > par.size.x + 1.0 else 0.0
		if not is_equal_approx(custom_minimum_size.x, target):
			custom_minimum_size.x = target

	func column_at(at: Vector2) -> int:
		if at.x < GUTTER:
			return -1
		var i: int = int(floor((at.x - GUTTER) / col_w()))
		return i if i >= 0 and i < chart.shown().size() else -1

	func _get_tooltip(at: Vector2) -> String:
		return chart.tooltip_for(column_at(at))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			queue_redraw()                # column hover highlight
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var i := column_at(event.position)
			if i >= 0:
				chart.hero_clicked.emit(int(chart.shown()[i]["uid"]))
				accept_event()

	func _draw() -> void:
		if chart == null:
			return
		var font := get_theme_default_font()
		var fs: int = UITheme.FONT_BODY
		var ink := DefeatReportView.ink()
		var muted := DefeatReportView.muted()
		var m: int = chart.metric
		var sc: float = maxf(1.0, chart.scale_of(m))
		var base_y: float = size.y - FOOT
		var plot_h: float = maxf(20.0, base_y - TOP)
		# Axis + grid at 0 / 25 / 50 / 75 / 100 % of this view's scale; on a short
		# plot only the labels that have room are printed.
		var label_every: int = 1 if plot_h / 4.0 >= float(fs) + 6.0 else (2 if plot_h / 2.0 >= float(fs) + 6.0 else 4)
		for g in range(5):
			var k: float = float(g) / 4.0
			var y: float = base_y - k * plot_h
			draw_line(Vector2(GUTTER - 4.0, y), Vector2(size.x, y), Color(muted, 0.18 if g > 0 else 0.55), 1.0)
			if g % label_every != 0:
				continue
			var txt := RecapHeroChart.short_n(int(round(sc * k))) if chart.scale_of(m) > 0.0 else "0"
			var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(GUTTER - 8.0 - w, y + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, muted)
		var heroes: Array = chart.shown()
		if heroes.is_empty():
			var msg := "No hero recruited yet at this point of the run." if chart.upto_round() == 0 else ""
			if msg != "":
				var mw: float = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, Vector2((size.x - mw) * 0.5, base_y - plot_h * 0.5), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, muted)
			return
		var cw: float = col_w()
		var bw: float = clampf(cw * 0.5, 14.0, 48.0)
		var hover := column_at(get_local_mouse_position()) if get_global_rect().has_point(get_global_mouse_position()) else -1
		for i in range(heroes.size()):
			var h: Dictionary = heroes[i]
			var uid: int = int(h["uid"])
			var st: Dictionary = chart.state_of(uid)
			var cx: float = GUTTER + cw * (float(i) + 0.5)
			if i == hover:
				draw_rect(Rect2(GUTTER + cw * i + 2.0, TOP - 18.0, cw - 4.0, plot_h + 18.0 + FOOT - 4.0),
					Color(DefeatReportView.gold(), 0.08))
			var total: float = chart.value_of(uid, m)
			var top_y: float = base_y
			if m == RecapHeroChart.TOTAL:
				# Three segments: damage at the base, protection, healing on top.
				for part in range(3):
					var pv: float = chart.value_of(uid, part)
					if pv <= 0.0:
						continue
					var ph: float = maxf(2.0, clampf(pv / sc, 0.0, 1.0) * plot_h)
					var r := Rect2(cx - bw * 0.5, top_y - ph, bw, ph)
					draw_rect(r, RecapMetricBar.fill_color(part))
					RecapMetricBar.draw_pattern(self, part, r, RecapMetricBar.pattern_color(part))
					draw_rect(r, Color(0, 0, 0, 0.45), false, 1.0)
					top_y -= ph
			elif total > 0.0:
				var bh: float = maxf(2.0, clampf(total / sc, 0.0, 1.0) * plot_h)
				var r2 := Rect2(cx - bw * 0.5, base_y - bh, bw, bh)
				draw_rect(r2, RecapMetricBar.fill_color(m))
				RecapMetricBar.draw_pattern(self, m, r2, RecapMetricBar.pattern_color(m))
				draw_rect(r2, Color(0, 0, 0, 0.45), false, 1.0)
				top_y = base_y - bh
			var vt := RecapHeroChart.short_n(int(round(total)))
			var vw: float = font.get_string_size(vt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(cx - vw * 0.5, top_y - 6.0), vt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
			# Portrait, name, state under the baseline. Until the screen's warm-up
			# has trimmed a portrait it is drawn as loaded (trimming twenty at
			# once in the opening frame was most of its hitch).
			var path: String = String(VisualUnit.HERO_SPRITE_PATHS.get(int(h["cls"]), ""))
			var tex: Texture2D = null
			if path != "":
				tex = DefeatReportView._trim_cache[path] if DefeatReportView._trim_cache.has(path) else MapRouteArt.tex(path)
			if tex:
				var ps := 24.0
				var asp: float = tex.get_width() / maxf(1.0, float(tex.get_height()))
				var pw: float = ps * minf(1.0, asp)
				var ph2: float = ps / maxf(1.0, asp) if asp > 1.0 else ps
				draw_texture_rect(tex, Rect2(cx - pw * 0.5, base_y + 4.0 + (ps - ph2) * 0.5, pw, ph2), false)
			_text_fit(font, cx, base_y + 44.0, String(h["name"]), fs, cw - 6.0, ink)
			var sc_col: Color = DefeatReportView.crimson() if st["kind"] == "fell" else muted
			_text_fit(font, cx, base_y + 60.0, String(st["text"]), fs, cw - 6.0, sc_col)

	func _text_fit(font: Font, cx: float, y: float, txt: String, fs: int, max_w: float, col: Color) -> void:
		var t := txt
		while t.length() > 1 and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
			t = t.substr(0, t.length() - 2) + "…"
		var w: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(cx - w * 0.5, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
