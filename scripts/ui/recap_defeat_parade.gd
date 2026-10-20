class_name RecapDefeatParade
extends Control
# ══════════════════════════════════════════════════════════════════════════════
# The run recap's trophy strip as a PARADE (2026-10-07, owner layout): every
# confirmed enemy defeat as its own sprite, wave after wave from the run's first
# kill, each wave's group in the order its enemies fell (RunRecap.kill_order).
# Twenty air slimes killed is twenty air slimes standing in line.
#
# Drawn, not built from nodes, so a hundred-wave run (thousands of defeats) is a
# few thousand draw_texture_rect calls on rows actually on screen. It sits in a
# vertical ScrollContainer; each wave starts with its "W n" tag. Hover a sprite
# for what it was and where it fell. Departed map icons are never part of this:
# only recorded defeats are.
#
# `upto` / `fill` follow the replay point: waves after it are hidden, and the
# wave being replayed fills in left to right as `fill` goes 0 -> 1.
# ══════════════════════════════════════════════════════════════════════════════

const S := 30.0                       # sprite cell
const BOSS_S := 46.0
const GAP := 2.0
const GROUP_GAP := 14.0
const TAG_W := 38.0

var upto: int = -1                    # last fight index shown (inclusive)
var fill: float = 1.0                 # share of fight `upto`'s group shown
var _recap: RunRecap
var _groups: Array = []               # [{fi, round, keys}]
var _items: Array = []                # [{rect, key, fi, g, idx}] for the laid-out width
var _tags: Array = []                 # [{pos, text, fi}]
var _group_bottom: Dictionary = {}    # fi -> bottom y of its group
var _layout_w := -1.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func setup(recap: RunRecap) -> void:
	_recap = recap
	_groups.clear()
	for fi in range(recap.fights.size()):
		var keys: Array = recap.kill_order(fi)
		if not keys.is_empty():
			_groups.append({"fi": fi, "round": int(recap.fights[fi]["round"]), "keys": keys})
	upto = recap.fights.size() - 1
	fill = 1.0
	_layout_w = -1.0
	queue_redraw()

func set_upto(fi: int, k: float) -> void:
	if fi == upto and is_equal_approx(k, fill):
		return
	upto = fi
	fill = clampf(k, 0.0, 1.0)
	_update_height()
	queue_redraw()

func total_shown() -> int:
	var n := 0
	for g in _groups:
		if int(g["fi"]) < upto:
			n += (g["keys"] as Array).size()
		elif int(g["fi"]) == upto:
			n += int(floor((g["keys"] as Array).size() * fill + 0.0001))
	return n

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not is_equal_approx(size.x, _layout_w):
		_relayout()

func _boss(key: String) -> bool:
	return bool((_recap.enemy_types.get(key, {}) as Dictionary).get("boss", false))

func _relayout() -> void:
	_layout_w = size.x
	_items.clear()
	_tags.clear()
	_group_bottom.clear()
	if _recap == null:
		return
	var w: float = maxf(120.0, size.x)
	var x := 0.0
	var y := 0.0
	var row_h := S
	for gi in range(_groups.size()):
		var g: Dictionary = _groups[gi]
		if x > 0.0:
			x += GROUP_GAP
		if x + TAG_W + S > w:
			x = 0.0
			y += row_h + GAP + 4.0
			row_h = S
		_tags.append({"pos": Vector2(x, y), "text": "W%d" % int(g["round"]), "fi": int(g["fi"])})
		x += TAG_W
		var keys: Array = g["keys"]
		for idx in range(keys.size()):
			var key := String(keys[idx])
			var s: float = BOSS_S if _boss(key) else S
			if x + s > w:
				x = TAG_W * 0.5
				y += row_h + GAP
				row_h = S
			row_h = maxf(row_h, s)
			_items.append({"rect": Rect2(x, y, s, s), "key": key, "fi": int(g["fi"]), "idx": idx,
				"n": keys.size()})
			x += s + GAP
		_group_bottom[int(g["fi"])] = y + row_h
	_update_height()
	queue_redraw()

# Height grows with what is shown, so the scroll range follows the replay.
func _update_height() -> void:
	var bottom := 0.0
	for fi in _group_bottom.keys():
		if int(fi) <= upto:
			bottom = maxf(bottom, float(_group_bottom[fi]))
	custom_minimum_size.y = bottom + 4.0

# Where fight `fi`'s group starts (its first sprite), in this control's space,
# whether or not it is shown yet - the falling encounter icon aims here.
# (-1, -1) when that fight defeated nothing.
func group_anchor(fi: int) -> Vector2:
	if not is_equal_approx(size.x, _layout_w):
		_relayout()
	for tg in _tags:
		if int(tg["fi"]) == fi:
			return (tg["pos"] as Vector2) + Vector2(TAG_W + S * 0.5, S * 0.5)
	return Vector2(-1, -1)

# Bottom edge of the newest shown group (the screen scrolls it into view).
func latest_bottom() -> float:
	var bottom := 0.0
	for fi in _group_bottom.keys():
		if int(fi) <= upto:
			bottom = maxf(bottom, float(_group_bottom[fi]))
	return bottom

func _shown(it: Dictionary) -> bool:
	var fi: int = int(it["fi"])
	if fi < upto:
		return true
	if fi > upto:
		return false
	return float(it["idx"]) < float(it["n"]) * fill - 0.0001

func _get_tooltip(at: Vector2) -> String:
	for it in _items:
		if _shown(it) and (it["rect"] as Rect2).has_point(at):
			var t: Dictionary = _recap.enemy_types.get(String(it["key"]), {})
			var f: Dictionary = _recap.fights[int(it["fi"])]
			return "%s%s - defeated in Wave %d (%s)" % [String(t.get("name", it["key"])),
				" (boss)" if bool(t.get("boss", false)) else (" (elite)" if bool(t.get("elite", false)) else ""),
				int(f["round"]), RunMap.type_name(int(f["type"]))]
	return ""

func _draw() -> void:
	if _recap == null:
		return
	if not is_equal_approx(size.x, _layout_w):
		_relayout()
	# Cull to the part of us the scroll container shows.
	var vis := Rect2(Vector2(-10, -10), size + Vector2(20, 20))
	var par := get_parent() as ScrollContainer
	if par:
		vis = Rect2(Vector2(-10, float(par.scroll_vertical) - S * 2.0), Vector2(size.x + 20, par.size.y + S * 4.0))
	var font := get_theme_default_font()
	var fs: int = UITheme.FONT_BODY
	var muted := DefeatReportView.muted()
	for tg in _tags:
		if int(tg["fi"]) > upto:
			continue
		var p: Vector2 = tg["pos"]
		if not vis.has_point(p + Vector2(4, 4)):
			continue
		draw_line(p + Vector2(0, 2), p + Vector2(0, S - 2), Color(DefeatReportView.gold(), 0.5), 2.0)
		draw_string(font, p + Vector2(5, S * 0.5 + fs * 0.35), String(tg["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, muted)
	for it in _items:
		if not _shown(it):
			continue
		var r: Rect2 = it["rect"]
		if not vis.intersects(r):
			continue
		var key := String(it["key"])
		var t: Dictionary = _recap.enemy_types.get(key, {})
		var tex: Texture2D = DefeatReportView._enemy_texture(String(t.get("portrait", "")))
		if tex:
			var asp: float = tex.get_width() / maxf(1.0, float(tex.get_height()))
			var dw: float = r.size.x * minf(1.0, asp)
			var dh: float = r.size.y / maxf(1.0, asp) if asp > 1.0 else r.size.y
			draw_texture_rect(tex, Rect2(r.position + (r.size - Vector2(dw, dh)) * 0.5, Vector2(dw, dh)), false)
		else:
			draw_circle(r.get_center(), r.size.x * 0.38, Color(muted, 0.6))
			var ini := String(t.get("name", key)).substr(0, 1).to_upper()
			var iw: float = font.get_string_size(ini, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, r.get_center() + Vector2(-iw * 0.5, fs * 0.35), ini, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				DefeatReportView.ink())
		if bool(t.get("boss", false)):
			draw_line(Vector2(r.position.x + 2, r.end.y + 1), Vector2(r.end.x - 2, r.end.y + 1), DefeatReportView.gold(), 2.0)
