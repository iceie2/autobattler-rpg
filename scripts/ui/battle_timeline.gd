class_name BattleTimeline
extends Control
# The defeat report's central graphic: one lane per hero over a shared SIMULATION
# seconds axis (so 0.25x / 4x / pause never distort it - the recorder stamps
# battle_elapsed, not wall time).
#
#   bar        a stretch the hero was alive; gaps are time spent down
#   X circle   death          up-triangle  revival
#   diamond    ultimate       plus circle  a large heal on an ally
#
# Shapes differ as well as colours, so nothing relies on colour alone. Markers
# that would land on top of each other in one lane (same timestamp) are fanned
# out sideways a few pixels each; the true time stays in the hover text.
# Hover anything for details; the readout line under the lanes updates at once.

const GUTTER := 176.0
const AXIS_H := 26.0
const LEGEND_H := 26.0
const READOUT_H := 28.0
const PAD_R := 20.0
const MARK_R := 6.5
const MARK_STEP := 13.0

var _r: Dictionary = {}
var _heroes: Array = []
var _span: float = 1.0
var _lane_h: float = 30.0
var _markers: Array = []          # {pos, ev, lane, text}
var _hover: int = -1
var _hover_text: String = ""
var _tex: Dictionary = {}

func setup(report: Dictionary) -> void:
	_r = report
	_heroes = report.get("heroes", [])
	_span = maxf(float(report.get("duration", 0.0)), 0.1)
	_lane_h = 34.0 if _heroes.size() <= 4 else (28.0 if _heroes.size() <= 8 else 23.0)
	custom_minimum_size = Vector2(560.0, AXIS_H + _heroes.size() * _lane_h + LEGEND_H + READOUT_H + 10.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hover_text = "Hover a marker or a bar for details."
	_layout()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		_hover_text = "Hover a marker or a bar for details."
		queue_redraw()

# ── Geometry ──────────────────────────────────────────────────────────────────

func _plot_x0() -> float: return GUTTER
func _plot_w() -> float: return maxf(40.0, size.x - GUTTER - PAD_R)
func _x_of(t: float) -> float: return _plot_x0() + clampf(t / _span, 0.0, 1.0) * _plot_w()
func _lane_top(i: int) -> float: return AXIS_H + i * _lane_h
func _lane_mid(i: int) -> float: return _lane_top(i) + _lane_h * 0.5

func _lane_of(hero_id) -> int:
	for i in range(_heroes.size()):
		if _heroes[i]["id"] == hero_id:
			return i
	return -1

func _layout() -> void:
	_markers.clear()
	var per_lane: Dictionary = {}
	for ev in _r.get("events", []):
		var lane := _lane_of(ev["hero"])
		if lane < 0:
			continue
		if not per_lane.has(lane):
			per_lane[lane] = []
		per_lane[lane].append(ev)
	for lane in per_lane.keys():
		var last_x := -1000.0
		for ev in per_lane[lane]:     # events arrive time-sorted
			var x: float = _x_of(float(ev["t"]))
			if x - last_x < MARK_STEP:
				x = last_x + MARK_STEP
			last_x = x
			_markers.append({"pos": Vector2(x, _lane_mid(lane)), "ev": ev, "lane": lane,
				"text": _describe(ev)})

func _describe(ev: Dictionary) -> String:
	var t := BattleRecorder.fmt_time(float(ev["t"]))
	match String(ev["kind"]):
		"death":
			var by := String(ev.get("by", ""))
			return "%s fell at %s%s." % [ev["name"], t, (" (last hit by %s)" % by) if by != "" else ""]
		"revive":
			return "%s was revived at %s." % [ev["name"], t]
		"ultimate":
			var ab := String(ev.get("ability", ""))
			return "%s used %s at %s." % [ev["name"], ab if ab != "" else "an ultimate", t]
		"heal":
			return "%s healed %s for %d HP at %s." % [ev["name"], ev.get("target", "an ally"),
				int(ev.get("amount", 0)), t]
	return ""

# ── Palette (dark + light) ────────────────────────────────────────────────────

func _col(dark: Color, light: Color) -> Color:
	return light if UITheme.is_light() else dark

func _alive_col() -> Color: return _col(Color(0.86, 0.70, 0.28), Color(0.70, 0.50, 0.10))
func _death_col() -> Color: return _col(Color(0.90, 0.28, 0.27), Color(0.64, 0.10, 0.10))
func _revive_col() -> Color: return _col(Color(0.55, 0.90, 0.60), Color(0.15, 0.50, 0.22))
func _ult_col() -> Color: return _col(Color(0.78, 0.62, 1.0), Color(0.40, 0.22, 0.70))
func _heal_col() -> Color: return _col(Color(0.40, 0.88, 0.78), Color(0.08, 0.46, 0.40))
func _ink() -> Color: return _col(Color(0.94, 0.91, 0.85), Color(0.22, 0.18, 0.13))
func _muted() -> Color: return _col(Color(0.70, 0.68, 0.64), Color(0.38, 0.32, 0.25))
func _grid() -> Color: return _col(Color(1, 1, 1, 0.10), Color(0.2, 0.15, 0.05, 0.16))
func _lane_bg() -> Color: return _col(Color(1, 1, 1, 0.035), Color(0.3, 0.2, 0.05, 0.07))

# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var font: Font = get_theme_default_font()
	var fs: int = UITheme.FONT_BODY
	var fs_small: int = UITheme.FONT_BODY
	var x0 := _plot_x0()
	var x1 := x0 + _plot_w()
	var lanes_bottom := AXIS_H + _heroes.size() * _lane_h

	# Axis + gridlines
	var step := _tick_step()
	var t := 0.0
	while t <= _span + 0.001:
		var x := _x_of(t)
		draw_line(Vector2(x, AXIS_H - 4), Vector2(x, lanes_bottom), _grid(), 1.0)
		draw_string(font, Vector2(x - 20, AXIS_H - 9), _tick_label(t), HORIZONTAL_ALIGNMENT_CENTER, 40, fs_small, _muted())
		t += step
	# Final instant (the end of the fight), labelled so the scale has a right edge.
	draw_line(Vector2(x1, AXIS_H - 4), Vector2(x1, lanes_bottom), _col(Color(0.9, 0.3, 0.3, 0.55), Color(0.6, 0.1, 0.1, 0.55)), 1.5)

	for i in range(_heroes.size()):
		var h: Dictionary = _heroes[i]
		var top := _lane_top(i)
		if i % 2 == 0:
			draw_rect(Rect2(0, top, size.x, _lane_h), _lane_bg())
		_draw_gutter(i, h, top, font, fs)
		var mid := _lane_mid(i)
		# Down-time hairline, then the alive bars over it.
		draw_line(Vector2(x0, mid), Vector2(x1, mid), _col(Color(1, 1, 1, 0.18), Color(0.2, 0.1, 0.0, 0.25)), 1.0)
		var bar_h: float = clampf(_lane_h * 0.34, 6.0, 12.0)
		for pair in h["intervals"]:
			var a := _x_of(float(pair[0]))
			var b := _x_of(float(pair[1]))
			if b - a < 2.0:
				b = a + 2.0
			draw_rect(Rect2(a, mid - bar_h * 0.5, b - a, bar_h), _alive_col())
			draw_rect(Rect2(a, mid - bar_h * 0.5, b - a, 2.0), _alive_col().lightened(0.35))

	for i in range(_markers.size()):
		_draw_marker(_markers[i], i == _hover)

	# Legend
	var ly := lanes_bottom + 6.0 + LEGEND_H * 0.5
	var lx := GUTTER
	lx = _legend_item(lx, ly, "alive", font, fs_small)
	lx = _legend_item(lx, ly, "death", font, fs_small)
	lx = _legend_item(lx, ly, "revive", font, fs_small)
	lx = _legend_item(lx, ly, "ultimate", font, fs_small)
	lx = _legend_item(lx, ly, "heal", font, fs_small)

	# Readout
	var ry := lanes_bottom + LEGEND_H + 4.0
	draw_string(font, Vector2(8, ry + READOUT_H * 0.5 + 6), _hover_text, HORIZONTAL_ALIGNMENT_LEFT,
		size.x - 16, fs, _ink())

func _draw_gutter(i: int, h: Dictionary, top: float, font: Font, fs: int) -> void:
	var icon: float = minf(_lane_h - 6.0, 26.0)
	var cy := top + _lane_h * 0.5
	var tex: Texture2D = _tex_for(String(h.get("portrait", "")))
	if tex:
		draw_texture_rect(tex, Rect2(6, cy - icon * 0.5, icon, icon), false)
	else:
		draw_circle(Vector2(6 + icon * 0.5, cy), icon * 0.5, _col(Color(0.25, 0.22, 0.2), Color(0.7, 0.62, 0.5)))
		draw_string(font, Vector2(6, cy + 6), String(h["name"]).substr(0, 1), HORIZONTAL_ALIGNMENT_CENTER, icon, fs, _ink())
	var name_x := 6.0 + icon + 8.0
	draw_string(font, Vector2(name_x, cy + 6), _fit_text(font, String(h["name"]), GUTTER - name_x - 6.0, fs),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _ink())

func _fit_text(font: Font, text: String, max_w: float, fs: int) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
		return text
	var s := text
	while s.length() > 1 and font.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		s = s.substr(0, s.length() - 1)
	return s + "…"

func _draw_marker(m: Dictionary, hot: bool) -> void:
	var p: Vector2 = m["pos"]
	var kind := String(m["ev"]["kind"])
	var r := MARK_R + (2.0 if hot else 0.0)
	var edge := _col(Color(0, 0, 0, 0.85), Color(1, 1, 1, 0.9))
	match kind:
		"death":
			draw_circle(p, r + 1.5, edge)
			draw_circle(p, r, _death_col())
			var d := r * 0.5
			var ink := Color(1, 1, 1)
			draw_line(p + Vector2(-d, -d), p + Vector2(d, d), ink, 2.0)
			draw_line(p + Vector2(-d, d), p + Vector2(d, -d), ink, 2.0)
		"revive":
			var pts := PackedVector2Array([p + Vector2(0, -r - 1), p + Vector2(r + 1, r), p + Vector2(-r - 1, r)])
			var out := PackedVector2Array([p + Vector2(0, -r - 3), p + Vector2(r + 3, r + 1.5), p + Vector2(-r - 3, r + 1.5)])
			draw_colored_polygon(out, edge)
			draw_colored_polygon(pts, _revive_col())
		"ultimate":
			var dm := PackedVector2Array([p + Vector2(0, -r - 1), p + Vector2(r + 1, 0), p + Vector2(0, r + 1), p + Vector2(-r - 1, 0)])
			var dm_out := PackedVector2Array([p + Vector2(0, -r - 3), p + Vector2(r + 3, 0), p + Vector2(0, r + 3), p + Vector2(-r - 3, 0)])
			draw_colored_polygon(dm_out, edge)
			draw_colored_polygon(dm, _ult_col())
		"heal":
			draw_circle(p, r + 1.5, edge)
			draw_circle(p, r, _heal_col())
			var d2 := r * 0.55
			var ink2 := Color(0.05, 0.12, 0.10) if not UITheme.is_light() else Color(1, 1, 1)
			draw_line(p + Vector2(-d2, 0), p + Vector2(d2, 0), ink2, 2.0)
			draw_line(p + Vector2(0, -d2), p + Vector2(0, d2), ink2, 2.0)

func _legend_item(x: float, y: float, kind: String, font: Font, fs: int) -> float:
	var label: String = {"alive": "alive", "death": "fell", "revive": "revived",
		"ultimate": "ultimate", "heal": "large heal"}[kind]
	if kind == "alive":
		draw_rect(Rect2(x, y - 4, 18, 8), _alive_col())
		x += 24.0
	else:
		_draw_marker({"pos": Vector2(x + MARK_R, y), "ev": {"kind": kind}}, false)
		x += MARK_R * 2.0 + 8.0
	draw_string(font, Vector2(x, y + 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _muted())
	return x + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 20.0

func _tick_step() -> float:
	var max_ticks: float = maxf(2.0, _plot_w() / 78.0)
	for s in [1.0, 2.0, 5.0, 10.0, 15.0, 20.0, 30.0, 60.0, 120.0, 300.0, 600.0, 1200.0]:
		if _span / s <= max_ticks:
			return s
	return 1800.0

func _tick_label(t: float) -> String:
	if _span >= 120.0:
		return "%d:%02d" % [int(t) / 60, int(t) % 60]
	return "%ds" % int(round(t))

func _tex_for(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex[path] = t
	return t

# ── Hover ─────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)

func _update_hover(pos: Vector2) -> void:
	var best := -1
	var best_d := 12.0
	for i in range(_markers.size()):
		var d: float = (_markers[i]["pos"] as Vector2).distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	_hover = best
	_hover_text = _text_at(pos, best)
	queue_redraw()

func _text_at(pos: Vector2, marker: int) -> String:
	if marker >= 0:
		return String(_markers[marker]["text"])
	var lane := int(floor((pos.y - AXIS_H) / _lane_h))
	if lane >= 0 and lane < _heroes.size() and pos.x >= _plot_x0() and pos.x <= _plot_x0() + _plot_w():
		var h: Dictionary = _heroes[lane]
		var t: float = (pos.x - _plot_x0()) / _plot_w() * _span
		var prev_end := 0.0
		for pair in h["intervals"]:
			if t >= float(pair[0]) and t <= float(pair[1]):
				return "%s: alive from %s to %s." % [h["name"], BattleRecorder.fmt_time(float(pair[0])),
					BattleRecorder.fmt_time(float(pair[1]))]
			if t < float(pair[0]):
				return "%s: down from %s to %s." % [h["name"], BattleRecorder.fmt_time(prev_end),
					BattleRecorder.fmt_time(float(pair[0]))]
			prev_end = float(pair[1])
		if prev_end < _span:
			return "%s: down from %s to the end of the fight." % [h["name"], BattleRecorder.fmt_time(prev_end)]
		return "%s: standing at the end of the fight." % h["name"]
	return "Hover a marker or a bar for details."

func _get_tooltip(at_position: Vector2) -> String:
	var best := -1
	var best_d := 12.0
	for i in range(_markers.size()):
		var d: float = (_markers[i]["pos"] as Vector2).distance_to(at_position)
		if d < best_d:
			best_d = d
			best = i
	var txt := _text_at(at_position, best)
	return "" if txt.begins_with("Hover") else txt

# Exposed for the focused test: where a hero's marker of `kind` is drawn, as a
# time-sorted list of {t, x}. Lets the test prove simultaneous events stay apart.
func marker_positions(hero_id, kind: String) -> Array:
	var out: Array = []
	for m in _markers:
		if m["ev"]["hero"] == hero_id and m["ev"]["kind"] == kind:
			out.append({"t": float(m["ev"]["t"]), "x": (m["pos"] as Vector2).x})
	return out
