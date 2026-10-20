extends CanvasLayer
class_name HeroMergePanel

# Hero merging, the menu way (2026-09-28). Same chrome and layout conventions as
# EquipmentPanel. Drag-to-merge on the board/bench does the same thing; this is
# for players who'd rather go through an interface — and it's where the rules
# and the exact preview live.
#
#   left  : every hero you own 2+ copies of (field + bench, not downed)
#   right : the copies of the selected hero — pick two; the two highest-level
#           copies are pre-picked — then a preview of the survivor's grade and
#           stat gains, and the MERGE button.
#
# The panel never mutates units itself: MERGE emits merge_requested and
# main_game._try_merge_heroes runs the one shared merge path, then calls
# refresh() back. Survivor choice uses UnitFactory.merge_survivor so the preview
# can't disagree with the result.

signal merge_requested(a: UnitBase, b: UnitBase)

const STAT_NAMES := {"hp": "HP", "mana": "Mana", "atk": "ATK", "magic": "MAG",
	"res": "RES", "aspd": "AS", "hpregen": "HP regen", "manaregen": "Mana regen"}
const PANEL_SIZE := Vector2(1000, 734)
const CARD := Vector2(168, 196)

var _field: Array = []
var _bench: Array = []
var _selected_class: int = -1
var _picked: Array = []          # up to two UnitBase

var _panel: Panel
var _group_list: VBoxContainer
var _copies_row: HBoxContainer
var _copies_head: Label
var _preview: RichTextLabel
var _merge_btn: Button
var _empty_lbl: Label
var _col_head: Color

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = PANEL_SIZE
	_panel.add_theme_stylebox_override("panel", UITheme.menu_surface_box())
	overlay.add_child(_panel)
	UITheme.menu_header(_panel, Rect2(18, 12, 964, 84))
	_lbl(_panel, "MERGE HEROES", 32, UITheme.menu_title_color(),
		Vector2(20, 30), Vector2(960, 48), true)

	_col_head = UITheme.menu_title_color() if UITheme.is_light() else Color(0.95, 0.82, 0.52)
	var sub := _lbl(_panel, "Same grade ranks a hero up. A lower-grade copy counts as part of a merge: C into B is half, D into B a quarter.",
		14, UITheme.menu_subtitle_color(), Vector2(20, 104), Vector2(960, 24), true)
	UITheme.apply_read_font(sub)

	# Left: duplicate groups
	_lbl(_panel, "DUPLICATES", 16, _col_head, Vector2(20, 140), Vector2(300, 24), true)
	var gscroll := ScrollContainer.new()
	gscroll.position = Vector2(20, 168)
	gscroll.size = Vector2(300, 500)
	gscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(gscroll)
	_group_list = VBoxContainer.new()
	_group_list.custom_minimum_size = Vector2(288, 0)
	_group_list.add_theme_constant_override("separation", 6)
	gscroll.add_child(_group_list)

	# Right: copies + preview
	_copies_head = _lbl(_panel, "COPIES — PICK TWO", 16, _col_head,
		Vector2(340, 140), Vector2(640, 24), true)
	var cscroll := ScrollContainer.new()
	cscroll.position = Vector2(340, 168)
	cscroll.size = Vector2(640, CARD.y + 14)
	cscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(cscroll)
	# One horizontal row that scrolls sideways (an HFlowContainer inside a
	# width-0 scroll child wrapped every card onto its own line).
	_copies_row = HBoxContainer.new()
	_copies_row.add_theme_constant_override("separation", 10)
	cscroll.add_child(_copies_row)

	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = true
	_preview.fit_content = false
	_preview.scroll_active = false
	_preview.position = Vector2(340, 390)
	_preview.size = Vector2(640, 282)
	UITheme.apply_rich_font(_preview, UITheme.FONT_VALUE)
	_preview.add_theme_color_override("default_color", UITheme.menu_body_color())
	_panel.add_child(_preview)

	_empty_lbl = _lbl(_panel, "No duplicate heroes yet.\nBuy a second copy of a hero in the shop. A lower-grade copy still helps: it counts as part of a merge.",
		18, UITheme.menu_subtitle_color(), Vector2(40, 300), Vector2(920, 80), true)
	_empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_read_font(_empty_lbl)

	_merge_btn = _btn("MERGE", Rect2(600, 686, 220, 34))
	_merge_btn.pressed.connect(_on_merge_pressed)
	_panel.add_child(_merge_btn)
	var close_btn := _btn("Close", Rect2(830, 686, 140, 34))
	close_btn.pressed.connect(func(): visible = false)
	_panel.add_child(close_btn)

	visible = false
	_center_panel()

func open(field: Array, bench: Array) -> void:
	_selected_class = -1
	_picked.clear()
	refresh(field, bench)
	_center_panel()
	visible = true

# Rebuild from the live roster (also called by main_game after every merge, so
# a drag-merge while the panel is open, or the panel's own MERGE, both land).
func refresh(field: Array, bench: Array) -> void:
	_field = field
	_bench = bench
	var groups := _groups()
	if not groups.has(_selected_class):
		_selected_class = groups.keys()[0] if not groups.is_empty() else -1
		_picked.clear()
	_picked = _picked.filter(func(u): return is_instance_valid(u) and u in groups.get(_selected_class, []))
	if _picked.size() < 2 and _selected_class != -1:
		_autopick(groups[_selected_class])
	_rebuild_groups(groups)
	_rebuild_copies(groups.get(_selected_class, []))
	_rebuild_preview()

func _groups() -> Dictionary:
	var by_class := {}
	for u in _field + _bench:
		if not (u and is_instance_valid(u)) or u.is_summoned:
			continue
		if not by_class.has(u.unit_class):
			by_class[u.unit_class] = []
		by_class[u.unit_class].append(u)
	var out := {}
	for cls in by_class:
		if by_class[cls].size() >= 2:
			out[cls] = by_class[cls]
	return out

# Pre-pick the best legal pair: a full merge (a rank-up) beats a partial one, a
# bigger partial beats a smaller one, then the higher levels; if nothing is legal
# (e.g. only S+ copies) the two highest levels, and the preview says why.
func _autopick(copies: Array) -> void:
	var best: Array = []
	var best_score := -1
	for i in range(copies.size()):
		for j in range(i + 1, copies.size()):
			var sv: UnitBase = UnitFactory.merge_survivor(copies[i], copies[j])
			var cs: UnitBase = copies[j] if sv == copies[i] else copies[i]
			if UnitFactory.merge_block_reason(sv, cs) != "":
				continue
			var plan := UnitFactory.merge_plan(sv, cs)
			var score: int = int(plan["steps"]) * 100000 + int(plan["added"]) * 100 \
				+ int(copies[i].level) + int(copies[j].level)
			if score > best_score:
				best_score = score
				best = [copies[i], copies[j]]
	if best.is_empty():
		var sorted := copies.duplicate()
		sorted.sort_custom(func(x, y): return x.level > y.level)
		best = sorted.slice(0, 2)
	_picked = best

func _rebuild_groups(groups: Dictionary) -> void:
	for c in _group_list.get_children():
		c.queue_free()
	_empty_lbl.visible = groups.is_empty()
	_copies_head.visible = not groups.is_empty()
	for cls in groups:
		var copies: Array = groups[cls]
		var b := _btn("", Rect2(0, 0, 288, 56))
		b.custom_minimum_size = Vector2(288, 56)
		b.toggle_mode = true
		b.button_pressed = cls == _selected_class
		b.pressed.connect(func():
			_selected_class = cls
			_picked.clear()
			refresh(_field, _bench))
		var p := HeroPortrait.new()
		p.position = Vector2(6, 4)
		p.size = Vector2(48, 48)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(p)
		p.setup(cls)
		var grades: Array = copies.map(func(u): return u.recruit_grade if u.recruit_grade != "" else "B")
		_lbl(b, "%s  ×%d" % [copies[0].unit_name, copies.size()], 16, UITheme.menu_body_color(),
			Vector2(62, 4), Vector2(220, 26))
		_lbl(b, "grades " + " · ".join(grades), 12, UITheme.menu_subtitle_color(),
			Vector2(62, 28), Vector2(220, 22))
		_group_list.add_child(b)

func _rebuild_copies(copies: Array) -> void:
	for c in _copies_row.get_children():
		c.queue_free()
	for u in copies:
		var card := _btn("", Rect2(Vector2.ZERO, CARD))
		card.custom_minimum_size = CARD
		card.toggle_mode = true
		card.button_pressed = u in _picked
		card.pressed.connect(_on_card_pressed.bind(u))
		var g: String = u.recruit_grade if u.recruit_grade != "" else "B"
		var gc: Color = UnitFactory.GRADE_COLORS.get(g, Color.WHITE)
		# Picked = lit in the copy's grade colour; unpicked = a quiet slot, so
		# the pair about to merge is obvious at a glance.
		var box: StyleBox
		if u in _picked:
			var ring := StyleBoxFlat.new()
			ring.bg_color = Color(gc, 0.22)
			ring.border_color = gc
			ring.set_border_width_all(3)
			ring.set_corner_radius_all(6)
			box = ring
		else:
			# Neutral, NOT UITheme.slot_box — its warm fill read as more selected
			# than the picked cards (seen in the first capture).
			var quiet := StyleBoxFlat.new()
			quiet.bg_color = Color(0, 0, 0, 0.08) if UITheme.is_light() else Color(0.10, 0.10, 0.15, 0.85)
			quiet.border_color = Color(UITheme.menu_subtitle_color(), 0.45)
			quiet.set_border_width_all(1)
			quiet.set_corner_radius_all(6)
			box = quiet
		for s in ["normal", "hover", "pressed", "focus"]:
			card.add_theme_stylebox_override(s, box)
		if not (u in _picked):
			card.modulate = Color(1, 1, 1, 0.72)
		var p := HeroPortrait.new()
		p.position = Vector2((CARD.x - 96) * 0.5, 8)
		p.size = Vector2(96, 96)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(p)
		p.setup(u.unit_class)
		_lbl(card, g, 30, gc, Vector2(CARD.x - 40, 2), Vector2(34, 36), true)
		_lbl(card, "Lv %d" % u.level, 18, UITheme.menu_body_color(), Vector2(0, 108), Vector2(CARD.x, 26), true)
		var where := "BENCH" if u in _bench else "FIELD"
		_lbl(card, where, 12, UITheme.menu_subtitle_color(), Vector2(0, 136), Vector2(CARD.x, 20), true)
		_lbl(card, "XP %d / %d" % [int(u.current_xp), int(u.xp_to_level)], 12, UITheme.menu_subtitle_color(),
			Vector2(0, 158), Vector2(CARD.x, 20), true)
		_copies_row.add_child(card)

func _on_card_pressed(u: UnitBase) -> void:
	if u in _picked:
		_picked.erase(u)
	else:
		_picked.append(u)
		if _picked.size() > 2:
			_picked.pop_front()   # keep the two most recent picks
	refresh(_field, _bench)

func _rebuild_preview() -> void:
	_merge_btn.disabled = true
	if _selected_class == -1:
		_preview.text = ""
		return
	if _picked.size() < 2:
		_preview.text = "[center]Pick two copies to merge.[/center]"
		return
	var a: UnitBase = _picked[0]
	var b: UnitBase = _picked[1]
	var hex := func(g: String) -> String:
		return UnitFactory.GRADE_COLORS.get(g, Color.WHITE).to_html(false)
	var survivor: UnitBase = UnitFactory.merge_survivor(a, b)
	var consumed: UnitBase = b if survivor == a else a
	var why := UnitFactory.merge_block_reason(survivor, consumed)
	if why != "":
		_preview.text = "\n[center][color=#e06a5a]%s[/color][/center]" % why
		return
	var plan := UnitFactory.merge_plan(survivor, consumed)
	var old_g := UnitFactory.grade_of(survivor)
	var new_g: String = plan["grade_after"]
	var steps: int = plan["steps"]
	var thr: int = plan["threshold_before"]
	var head := "[color=#%s]" % _col_head.to_html(false)
	var t := ""
	if steps == 0:
		# A lesser copy: no rank-up yet, just progress toward the next grade.
		var next_g := UnitFactory.next_grade(old_g)
		t = "[center][font_size=%d]Lv %d  [color=#%s]%s[/color]   +%s of a merge[/font_size][/center]\n" % [
			UITheme.FONT_HEADER, survivor.level, hex.call(old_g), old_g,
			UnitFactory.progress_text(int(plan["added"]), thr)]
		t += "\n[center]%sMERGE PROGRESS[/color]   [color=#7fd67f]%s → %s[/color]  toward [color=#%s]%s[/color][/center]\n" % [
			head, UnitFactory.progress_text(int(plan["progress_before"]), thr),
			UnitFactory.progress_text(int(plan["progress_after"]), thr), hex.call(next_g), next_g]
		t += "\n[center]No stat change yet: the stats come when it ranks up.[/center]\n"
	else:
		t = "[center][font_size=%d]Lv %d survivor:  [color=#%s]%s[/color]  →  [color=#%s]%s[/color][/font_size][/center]\n" % [
			UITheme.FONT_HEADER, survivor.level, hex.call(old_g), old_g, hex.call(new_g), new_g]
		var gains := UnitFactory.merge_preview(survivor, steps)
		var now_parts: Array = []
		var lvl_parts: Array = []
		for key in UnitFactory.MERGE_KEYS:
			if not gains.has(key):
				continue
			var nm: String = STAT_NAMES[key]
			var now: float = gains[key]["now"]
			var per: float = gains[key]["per_level"]
			var fmt := "%+.2f" if key in ["aspd", "hpregen", "manaregen"] else "%+d"
			if now != 0.0:
				now_parts.append("%s [color=#7fd67f]%s[/color]" % [nm, fmt % (now if fmt == "%+.2f" else int(now))])
			lvl_parts.append("%s %s" % [nm, ("%+.2f" % per) if per != float(int(per)) else ("%+d" % int(per))])
		t += "\n%sRIGHT NOW[/color]  (growth backfilled for %d levels)\n%s\n" % [head, survivor.level, "   ".join(now_parts)]
		t += "\n%sEVERY LEVEL FROM NOW ON[/color]\n%s\n" % [head, "   ".join(lvl_parts)]
		if int(plan["progress_after"]) > 0:
			t += "\n[center]Keeps %s of a merge toward the next grade.[/center]\n" % UnitFactory.progress_text(
				int(plan["progress_after"]), int(plan["threshold_after"]))
	t += "\n[color=#%s]The Lv %d %s copy is used up: its gear goes back to your bag, and half its XP (%d) carries over.[/color]" % [
		UITheme.menu_subtitle_color().to_html(false), consumed.level, UnitFactory.grade_of(consumed),
		int(consumed.current_xp * UnitFactory.MERGE_XP_CARRY)]
	_preview.text = t
	_merge_btn.disabled = false

func _on_merge_pressed() -> void:
	if _picked.size() == 2:
		merge_requested.emit(_picked[0], _picked[1])

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_panel.position = (vp - _panel.size) / 2.0

func _lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_font(l, UITheme.body_font(sz))
	l.add_theme_color_override("font_color", col)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _btn(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	UITheme.style_button(b)
	UITheme.apply_font(b, UITheme.body_font(18))
	return b
