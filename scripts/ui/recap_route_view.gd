class_name RecapRouteView
extends Control
# ══════════════════════════════════════════════════════════════════════════════
# The run recap's route (2026-10-07): the stops the run actually visited, drawn
# with the RUN MAP's own art (MapRouteArt + RunMapScreen's tables) - the dotted
# gold road on a dark under-stroke, fights as tier-tinted creature silhouettes
# with tier pips, side stops as their map emblems.
#
# World space: one horizontal line of stops, FIGHT_GAP apart (half that around a
# side stop), fights nudged up/down a little by tier like the map's lanes. A
# camera (cam_x, cam_y, zoom) maps world to screen with the focus point at
# `anchor` (fraction of this control). The journey drives the camera; the
# overview lets the player pan (drag), zoom (wheel / buttons) and pick a stop.
#
# HIT TARGETS. A stop is clickable here only when neighbouring stops are at
# least MIN_TARGET px apart on screen, so targets never overlap. Below that, a
# click zooms in around the cursor instead; the screen's back / forward buttons
# (and arrow keys / d-pad) are the always-available way to reach any stop.
# Departing icons are drawn by the screen's RecapFlyer overlay, not here, so they
# can fall out of this control into the defeat parade.
# ══════════════════════════════════════════════════════════════════════════════

signal stop_hovered(index: int)        # -1 = none
signal stop_clicked(index: int)
signal camera_changed
signal user_moved                      # the player panned or zoomed by hand

const FIGHT_GAP := 260.0
const STOP_GAP := 130.0
const LANE := 34.0
const NODE_R := 40.0
const MIN_TARGET := 44.0
const MAX_ZOOM := 1.6
const LABEL_MARGIN := 110.0           # px kept clear at both ends so end labels fit

var stops: Array = []                  # see setup()
var cam: Vector2 = Vector2.ZERO
var zoom: float = 1.0
var anchor: Vector2 = Vector2(0.58, 0.5)
var overview: bool = false
var active: int = -1                   # journey: the stop being visited
var departed: Dictionary = {}          # stop index -> true once its icon flew off
var selected: int = -1
var hovered: int = -1
var road_upto: float = -1.0            # journey: world x the walked road reaches
var lost_index: int = -1               # the fight that ended the run, if lost

var _drag_from: Vector2 = Vector2.INF
var _dragging: bool = false
var _min_x := 0.0
var _max_x := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

# ── Data ──────────────────────────────────────────────────────────────────────

# Builds the world layout from the recap's route. Each stop:
#   {key, kind ("fight" | "node" | "gap"), type, tier, round, biome, icon,
#    fight (index into recap.fights or -1), x, y, label}
func setup(recap: RunRecap) -> void:
	stops.clear()
	var x := 0.0
	var prev: Dictionary = {}
	if recap.is_partial():
		stops.append({"key": "_gap_start", "kind": "gap", "type": -1, "tier": 0,
			"round": recap.coverage_from_round, "biome": maxi(0, (recap.coverage_from_round - 1) / 10),
			"icon": "", "fight": -1, "x": 0.0, "y": 0.0,
			"label": "Waves 1-%d not recorded" % maxi(1, recap.coverage_from_round - 1)})
		x = STOP_GAP
		prev = stops[0]
	for e in recap.route:
		var is_fight: bool = String(e["kind"]) == "fight"
		var fi: int = recap.fight_index(String(e["key"])) if is_fight else -1
		if is_fight and fi < 0:
			continue                   # entered but never fought (e.g. a run that ended elsewhere)
		if not prev.is_empty():
			x += FIGHT_GAP if (is_fight and String(prev["kind"]) == "fight") else STOP_GAP
		var y := 0.0
		if is_fight:
			y = (float(e["tier"]) - 1.0) * LANE
		stops.append({"key": String(e["key"]), "kind": "fight" if is_fight else "node",
			"type": int(e["type"]), "tier": int(e["tier"]), "round": int(e["round"]),
			"biome": int(e["biome"]), "icon": String(e["icon"]), "fight": fi,
			"x": x, "y": y, "label": stop_label(e),
			"duration": float(recap.fights[fi]["duration"]) if fi >= 0 else -1.0})
		prev = stops[stops.size() - 1]
	_min_x = 0.0
	_max_x = x
	queue_redraw()

static func stop_label(e: Dictionary) -> String:
	var t: int = int(e["type"])
	match t:
		RunMap.NodeType.RELIC:
			return "Biome start"
		RunMap.NodeType.EVENT, RunMap.NodeType.MERCHANT, RunMap.NodeType.CAMP:
			return "%s · W%d slot" % [RunMap.type_name(t), int(e["round"])]
	return "W%d" % int(e["round"])

func stop_index(key: String) -> int:
	for i in range(stops.size()):
		if String(stops[i]["key"]) == key:
			return i
	return -1

func world_pos(i: int) -> Vector2:
	return Vector2(float(stops[i]["x"]), float(stops[i]["y"]))

# A short route strip (small windows) shrinks its nodes and lane spread to fit
# vertically; the horizontal layout and zoom are untouched.
func vfit() -> float:
	return clampf((size.y - 60.0) / 210.0, 0.5, 1.0)

func to_screen(w: Vector2) -> Vector2:
	var d := (w - cam) * zoom
	d.y *= vfit()
	return d + anchor * size

func to_world(s: Vector2) -> Vector2:
	var d := s - anchor * size
	d.y /= vfit()
	return d / maxf(zoom, 0.0001) + cam

# The zoom that frames every stop in this control, never above 1.
func fit_zoom() -> float:
	var span: float = maxf(1.0, _max_x - _min_x)
	return clampf((size.x - 2.0 * LABEL_MARGIN) / span, 0.005, 1.0)

func frame_all() -> void:
	anchor = Vector2(0.5, 0.5)
	zoom = fit_zoom()
	cam = Vector2((_min_x + _max_x) * 0.5, 0.0)
	camera_changed.emit()
	queue_redraw()

# Screen distance between the two closest neighbouring stops.
func min_spacing() -> float:
	return STOP_GAP * zoom if stops.size() > 1 else 9999.0

func targets_ok() -> bool:
	return min_spacing() >= MIN_TARGET

# The zoom at which stops become individually clickable.
func select_zoom() -> float:
	return clampf(MIN_TARGET / STOP_GAP * 1.4, 0.0, MAX_ZOOM)

# Keep the camera unless the stop is off screen (focus moves must not jolt the view).
func ensure_visible(i: int) -> void:
	if i < 0 or i >= stops.size():
		return
	var p := to_screen(world_pos(i))
	if p.x < LABEL_MARGIN * 0.6 or p.x > size.x - LABEL_MARGIN * 0.6:
		center_on(i)

func center_on(i: int, ensure_selectable: bool = false) -> void:
	if i < 0 or i >= stops.size():
		return
	if ensure_selectable and not targets_ok():
		zoom = select_zoom()
	cam = world_pos(i) * Vector2(1, 0)
	camera_changed.emit()
	queue_redraw()

func set_zoom_at(z: float, screen_point: Vector2) -> void:
	var before := to_world(screen_point)
	zoom = clampf(z, fit_zoom(), MAX_ZOOM)
	var after := to_world(screen_point)
	cam += before - after
	_clamp_cam()
	camera_changed.emit()
	queue_redraw()

func _clamp_cam() -> void:
	cam.x = clampf(cam.x, _min_x, _max_x)
	cam.y = clampf(cam.y, -LANE * 3.0, LANE * 3.0)

# ── Input (overview only) ─────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if not overview:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom_at(zoom * 1.25, mb.position)
			user_moved.emit()
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom_at(zoom / 1.25, mb.position)
			user_moved.emit()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_from = mb.position
				_dragging = false
			else:
				if not _dragging and _drag_from != Vector2.INF:
					_click(mb.position)
				_drag_from = Vector2.INF
				_dragging = false
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_from != Vector2.INF and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			if _dragging or mm.position.distance_to(_drag_from) > 5.0:
				if not _dragging:
					user_moved.emit()
				_dragging = true
				cam -= mm.relative / maxf(zoom, 0.0001)
				_clamp_cam()
				camera_changed.emit()
				queue_redraw()
		else:
			_update_hover(mm.position)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hovered != -1:
		hovered = -1
		stop_hovered.emit(-1)
		queue_redraw()
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()

func hit(p: Vector2) -> int:
	if not targets_ok():
		return -1
	var best := -1
	var best_d := MIN_TARGET * 0.5
	for i in range(stops.size()):
		if String(stops[i]["kind"]) == "gap":
			continue
		var d: float = to_screen(world_pos(i)).distance_to(p)
		if d <= best_d:
			best_d = d
			best = i
	return best

func _update_hover(p: Vector2) -> void:
	var h := hit(p)
	if h != hovered:
		hovered = h
		stop_hovered.emit(h)
		queue_redraw()

# Hovering any stop explains it (wave, biome, tier, outcome, time, defeats) -
# the screen supplies the text. Works at any zoom: a tooltip never needs a
# 44 px target, only the nearest stop under the cursor.
var tooltip_provider: Callable = Callable()

func _get_tooltip(at: Vector2) -> String:
	if not overview or not tooltip_provider.is_valid():
		return ""
	var best := -1
	var best_d := 24.0
	for i in range(stops.size()):
		var d: float = to_screen(world_pos(i)).distance_to(at)
		if d < best_d:
			best_d = d
			best = i
	return String(tooltip_provider.call(best)) if best >= 0 else ""

func _click(p: Vector2) -> void:
	var h := hit(p)
	if h >= 0:
		stop_clicked.emit(h)
	elif not targets_ok():
		set_zoom_at(select_zoom(), p)   # too dense to pick from: zoom in here first

# ── Drawing ───────────────────────────────────────────────────────────────────

func _font() -> Font:
	return get_theme_default_font()

func _ink() -> Color:
	return Color(0.20, 0.15, 0.09) if UITheme.is_light() else Color(0.96, 0.93, 0.86)

func _draw() -> void:
	if stops.is_empty():
		return
	var font := _font()
	var fs: int = UITheme.FONT_BODY
	var spacing := min_spacing()
	var show_labels: bool = spacing >= 40.0
	var vis := Rect2(Vector2(-200, -200), size + Vector2(400, 400))

	# ── Road ─────────────────────────────────────────────────────────────────
	var last_biome_lbl := -1e9
	for i in range(1, stops.size()):
		var a := to_screen(world_pos(i - 1))
		var b := to_screen(world_pos(i))
		if (a.x < vis.position.x and b.x < vis.position.x) or (a.x > vis.end.x and b.x > vis.end.x):
			continue
		var pts: PackedVector2Array = RunMapScreen._edge_points(a, b)
		var walked: bool = overview or road_upto < 0.0 or float(stops[i]["x"]) <= road_upto + 0.5
		var gap_edge: bool = String(stops[i - 1]["kind"]) == "gap"
		var under := Color(0, 0, 0, 0.55 if walked else 0.25)
		draw_polyline(pts, under, maxf(2.0, 6.0 * minf(1.0, zoom * 1.5)), true)
		var road: Color = RunMapScreen.ROAD_GOLD if walked else Color(1, 1, 1, 0.30)
		if gap_edge:
			road = Color(0.75, 0.72, 0.65, 0.55)
		var w: float = clampf(3.0 * zoom * 1.4, 1.5, 3.5)
		MapRouteArt.draw_flow(self, pts, 0.0, road, w, maxf(2.0, 7.0 * minf(1.0, zoom * 1.4)),
			maxf(3.0, 7.0 * minf(1.0, zoom * 1.4)))
		# A skipped wave with nothing standing in for it (no side stop): say so.
		var ra: int = int(stops[i - 1]["round"])
		var rb: int = int(stops[i]["round"])
		if String(stops[i - 1]["kind"]) == "fight" and String(stops[i]["kind"]) == "fight" \
				and rb - ra > 1 and show_labels:
			var txt := "W%d-%d not fought" % [ra + 1, rb - 1] if rb - ra > 2 else "W%d not fought" % (ra + 1)
			_text(font, (a + b) * 0.5 + Vector2(0, -16), txt, fs, Color(_ink(), 0.7))
		# Biome boundary.
		if int(stops[i]["biome"]) != int(stops[i - 1]["biome"]) and String(stops[i - 1]["kind"]) != "gap":
			var mx: float = (a.x + b.x) * 0.5
			draw_line(Vector2(mx, 8), Vector2(mx, size.y - 8), Color(_ink(), 0.18), 1.0)
			# Biome names stay as landmarks even when the route is zoomed out to dots.
			if show_labels or mx - last_biome_lbl >= 120.0:
				last_biome_lbl = mx
				var bi: int = clampi(int(stops[i]["biome"]), 0, ProgressionRails.BIOMES.size() - 1)
				_text(font, Vector2(mx, 22), String(ProgressionRails.BIOMES[bi]["name"]), fs, Color(_ink(), 0.75))

	# ── Stops ────────────────────────────────────────────────────────────────
	# Every fight wears its creature (owner, 2026-10-07: "each node should be the
	# monster sprite"), sized by the room to its neighbours; only a route zoomed
	# so far out that no sprite fits falls back to a tier dot.
	var last_boss_lbl := -1e9
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	var show_time: bool = spacing >= 56.0
	for i in range(stops.size()):
		var s: Dictionary = stops[i]
		var p := to_screen(world_pos(i))
		if not vis.has_point(p):
			continue
		var kind := String(s["kind"])
		if kind == "gap":
			_text(font, p + Vector2(0, -6), "…", UITheme.FONT_HEADER, Color(_ink(), 0.6))
			if show_labels:
				_text(font, p + Vector2(0, 26), String(s["label"]), fs, Color(_ink(), 0.8))
			continue
		var big: bool = (not overview and i == active) or (overview and (i == selected or i == hovered))
		# Journey: what lies ahead is the road not yet walked - drawn quieter.
		var ahead: bool = not overview and road_upto >= 0.0 and road_upto < 1e8 \
			and float(s["x"]) > road_upto + 0.5 and i != active
		var fade: float = 0.5 if ahead else 1.0
		var r: float = NODE_R * clampf(zoom, 0.25, 1.0) * vfit()
		if int(s["type"]) == RunMap.NodeType.BOSS:
			r *= 1.3
		elif int(s["type"]) == RunMap.NodeType.ELITE:
			r *= 1.12
		var gone: bool = not overview and departed.has(i)
		var sr: float = r
		if gone:
			sr = r * 0.72                 # its icon flew off; a smaller copy stays on the road
		elif overview and not big:
			sr = r * 0.82
		sr = minf(sr, spacing * 0.48)   # never overlap the neighbouring stop
		var dense: bool = sr < 6.0
		if kind == "fight":
			var tier_col := MapRouteArt.tier_color(int(s["tier"]))
			tier_col.a *= fade * (0.85 if gone else 1.0)
			if dense:
				draw_circle(p, 3.5, tier_col)
				# Boss waves stay labelled as landmarks on a zoomed-out route.
				if int(s["type"]) == RunMap.NodeType.BOSS and p.x - last_boss_lbl >= 56.0:
					last_boss_lbl = p.x
					_text(font, p + Vector2(0, -14), "W%d" % int(s["round"]), fs, Color(_ink(), 0.85))
			else:
				var icon := MapRouteArt.creature(String(s["icon"]))
				var drawn := false
				if icon:
					drawn = MapRouteArt.draw_creature(self, icon, p, Vector2(sr * 2.3, sr * 2.1), tier_col,
						0.9 * tier_col.a)
				if not drawn:
					draw_circle(p, sr + 3.0, Color(0, 0, 0, 0.9 * tier_col.a))
					draw_circle(p, sr, tier_col.darkened(0.55))
					_text(font, p + Vector2(0, sr * 0.18), MapRouteArt.glyph(int(s["type"])),
						UITheme.FONT_HEADER if sr >= 18.0 else fs, tier_col)
				# Tier as PIPS too, never colour alone; the fight's length under them.
				var pips: int = int(s["tier"]) + 1
				var py: float = p.y + maxf(9.0, sr) + 7.0
				for k in range(pips):
					draw_circle(Vector2(p.x - float(pips - 1) * 5.0 + float(k) * 10.0, py), 2.6, tier_col)
				if show_time and float(s.get("duration", -1.0)) >= 0.0:
					_text(font, Vector2(p.x, py + 13.0), BattleRecorder.fmt_time(float(s["duration"])), fs,
						Color(_ink(), 0.85 * fade))
			# The run's outcome is only shown once the journey has reached it.
			if i == lost_index and not dense and (overview or road_upto >= 1e8):
				draw_arc(p, sr + 6.0, 0.0, TAU, 28, DefeatReportView.crimson(), 3.0)
		else:
			var em := MapRouteArt.stop_emblem(int(s["type"]), int(s["biome"]))
			var side: float = minf(maxf(14.0, r * 1.1), spacing * 0.9)
			if dense or side < 10.0:
				draw_circle(p, 3.0, Color(_ink(), 0.7))
			elif em:
				draw_texture_rect(em, Rect2(p - Vector2(side, side) * 0.5, Vector2(side, side)), false,
					Color(1, 1, 1, 0.95))
			else:
				draw_circle(p, side * 0.45, Color(0, 0, 0, 0.8))
				_text(font, p + Vector2(0, side * 0.15), MapRouteArt.glyph(int(s["type"])), fs, Color(1, 1, 1, 0.9))
		if big:
			var ring := (sr if kind == "fight" else r) + 8.0 + pulse * 2.0
			draw_arc(p, ring, 0.0, TAU, 40, RunMapScreen.ROAD_GOLD, 3.0)
		if show_labels and not dense:
			var ly: float = p.y - (sr if kind == "fight" else r) - 10.0
			_text(font, Vector2(p.x, ly), String(s["label"]), fs, _ink() if (big or not overview) else Color(_ink(), 0.85))

func _text(font: Font, centre: Vector2, txt: String, fs: int, col: Color) -> void:
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := centre + Vector2(-w * 0.5, fs * 0.35)
	# A dark halo so labels read on the painted plates in both themes.
	var halo := Color(0, 0, 0, 0.75) if not UITheme.is_light() else Color(1, 0.97, 0.9, 0.85)
	draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, halo)
	draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
