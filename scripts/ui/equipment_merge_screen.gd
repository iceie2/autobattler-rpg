extends CanvasLayer
class_name EquipmentMergeScreen

signal done

# Equipment merge toast (2026-09-29), the item twin of MergeResultScreen. Plays
# after a MANUAL component merge (drag-to-combine, the Combine tray, the level
# removal menu); silent auto-combine sweeps never toast.
#
#   1. fade in on the TWO source items: icon, name, and their stats as
#      icon + number rows (passives as emblem + level)
#   2. the two cards slide into the middle TOGETHER, mirror-image (neither is
#      the "base": both shrink and fade the same way)
#   3. flash: a NEW card appears where they met, the RESULT (new icon, rarity
#      colour and name)
#   4. stat rows count up on the result card one at a time, exactly like the
#      hero merge, from 0 (the whole merged value is the green +gain, counting
#      down as the number climbs)
#   5. hold, fade, free
#
# Read-only and self-running: no buttons, no Esc, no dim backdrop, and it never
# blocks input (the merge is already applied). The sources are never mutated, so
# present() just reads them (a/b are only "left" and "right" on screen).

const PANEL_W := 474.0
const CARD_W := 196.0
const ICON_PX := 84.0
const ROW_H := 30.0
const TOP := 58.0
const HEAD_H := 150.0     # icon + name area above the rows

const FADE_IN := 0.20
const WAIT_ALPHA := 0.78   # opacity while parked in the queue
const HOLD_START := 0.65
const CONVERGE := 0.42
const FLASH_UP := 0.16
const FLASH_DOWN := 0.35
const HOLD_TRANSFORMED := 0.25
const ROW_TIME := 0.32
const ROW_GAP := 0.06
const HOLD_FINAL := 0.90
const PASSIVE_POP := 0.22      # each passive pops in this long
const PASSIVE_GAP := 0.28
const HOLD_PASSIVES := 1.9     # time to read what the passives do
const PASSIVE_H := 86.0        # one passive entry: name line + wrapped description (up to 4 lines)
const FADE_OUT := 0.35

const TEXT_MUTED := Color(0.72, 0.74, 0.86)
const TEXT_NAME  := Color(0.96, 0.91, 0.79)

# [item.stat_bonus key, UnitFactory.STAT_ICONS key, fmt, scale, suffix, tooltip]
const STATS := [
	["hp",           "hp",            "int", 1.0,   "",  "Max HP"],
	["mana",         "mana",          "int", 1.0,   "",  "Max Mana"],
	["atk",          "atk",           "int", 1.0,   "",  "Attack"],
	["magic",        "magic",         "int", 1.0,   "",  "Magic Power"],
	["res",          "res",           "int", 1.0,   "",  "Armor"],
	["magic_resist", "mres",          "int", 1.0,   "",  "Magic Resist"],
	["ten",          "ten",           "int", 1.0,   "",  "Tenacity"],
	["cdr",          "ability_haste", "int", 1.0,   "",  "Ability Haste"],
	["aspd",         "aspd",          "f2",  1.0,   "",  "Attack Speed"],
	["hpregen",      "hpregen",       "f2",  1.0,   "",  "HP Regen"],
	["manaregen",    "manaregen",     "f2",  1.0,   "",  "Mana Regen"],
	["crit",         "crit_chance",   "int", 100.0, "%", "Crit Chance"],
	["critdmg",      "crit_damage",   "f2",  1.0,   "x", "Crit Damage"],
]

var _root: Control
var _panel: Panel
var _card_a: Panel          # left source item
var _card_b: Panel          # right source item (mirror image of A, equal weight)
var _card_r: Panel          # the RESULT, revealed where the two meet
var _flash: Panel
var _rows: Array = []       # animated rows on the result card
var _passive_entries: Array = []   # [{node, name, desc, key}] popped in after the stats
var _a: ComponentEquipmentItem
var _b: ComponentEquipmentItem
var _result: ComponentEquipmentItem
var _tween: Tween
var _finished := false
var speed := 1.0    # set by MergeToastQueue: a backlog plays the toast faster

func set_speed(s: float) -> void:
	speed = s
	if _tween != null and _tween.is_valid():
		_tween.set_speed_scale(s)

func present(a: ComponentEquipmentItem, b: ComponentEquipmentItem, result: ComponentEquipmentItem) -> void:
	prepare(a, b, result)
	play()

# Builds the cards without starting the animation. waiting=true parks it
# visibly (dimmed) so the queue can hold it to the right of the playing toast.
func prepare(a: ComponentEquipmentItem, b: ComponentEquipmentItem, result: ComponentEquipmentItem,
		waiting: bool = false) -> void:
	_a = a
	_b = b
	_result = result
	_build()
	# A merge still waiting in the queue: the SAME card, parked to the right, a
	# touch smaller and dimmer, ready to slide into the centre (MergeToastQueue).
	if waiting:
		_panel.modulate.a = WAIT_ALPHA

func play() -> void:
	if _finished:
		return
	_play()

func contains_click(point: Vector2) -> bool:
	for card in [_card_a, _card_b, _card_r]:
		var local: Vector2 = card.get_global_transform_with_canvas().affine_inverse() * point
		if card.visible and card.modulate.a > 0.05 and Rect2(Vector2.ZERO, card.size).has_point(local):
			return true
	return false

func skip() -> void:
	_finish()

# ── Build ─────────────────────────────────────────────────────────────────────
func _stat(item: ComponentEquipmentItem, key: String, scale: float) -> float:
	return float(item.stat_bonus.get(key, 0)) * scale

# Rows for a card: [{icon, a, b, fmt, prefix, suffix, tip}] built for `from`
# to `to`. A stat gets a row when ANY of the three items has it, so both cards
# line up row for row.
func _row_specs(from: ComponentEquipmentItem, to: ComponentEquipmentItem) -> Array:
	# `from` == null means "from nothing": every value starts at 0.
	var specs: Array = []
	for s in STATS:
		if _stat(_a, s[0], s[3]) == 0.0 and _stat(_b, s[0], s[3]) == 0.0 \
				and _stat(_result, s[0], s[3]) == 0.0:
			continue
		var path: String = UnitFactory.STAT_ICONS.get(s[1], "")
		var tex: Texture2D = load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
		specs.append({"icon": tex, "a": 0.0 if from == null else _stat(from, s[0], s[3]), "b": _stat(to, s[0], s[3]),
			"fmt": s[2], "prefix": "", "suffix": s[4], "tip": s[5]})
	var keys: Array = []
	for it in [_a, _b, _result]:
		for k in it.passive_levels:
			if not (k in keys):
				keys.append(k)
	for k in keys:
		specs.append({"icon": GearIcons.emblem(str(k)),
			"a": 0.0 if from == null else float(from.passive_levels.get(k, 0)),
			"b": float(to.passive_levels.get(k, 0)), "fmt": "int", "prefix": "Lv ", "suffix": "",
			"tip": GearCatalog.display_name(str(k))})
	return specs

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never blocks input: the merge is already applied
	add_child(_root)

	# Each source shows only what it has; the result counts up from nothing.
	var specs_a := _row_specs(_a, _a).filter(func(sp): return float(sp["a"]) > 0.0)
	var specs_b := _row_specs(_b, _b).filter(func(sp): return float(sp["a"]) > 0.0)
	var specs_r := _row_specs(null, _result)
	var n_rows: int = maxi(maxi(specs_a.size(), specs_b.size()), specs_r.size())
	var card_h: float = HEAD_H + n_rows * ROW_H + 16.0
	var passive_keys: Array = _result.passive_levels.keys()
	var card_h_r: float = card_h + (12.0 + passive_keys.size() * PASSIVE_H if not passive_keys.is_empty() else 0.0)
	var panel_h: float = TOP + maxf(card_h, card_h_r) + 24.0

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, panel_h)
	_panel.pivot_offset = _panel.size * 0.5
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())   # no backdrop: cards float over the board
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_panel.position = (vp - _panel.size) / 2.0
	var kicker := _label(_panel, "✦  ITEMS COMBINED  ✦", UITheme.FONT_HEADER, UITheme.menu_title_color(),
		Vector2(0, 14), Vector2(PANEL_W, 34))
	kicker.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	kicker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	kicker.add_theme_constant_override("outline_size", 8)

	var mid_x: float = (PANEL_W - CARD_W) * 0.5
	_card_a = _make_card(_a, Vector2(24, TOP), card_h)
	_card_b = _make_card(_b, Vector2(PANEL_W - 24 - CARD_W, TOP), card_h)
	_card_r = _make_card(_result, Vector2(mid_x, TOP), card_h_r)
	_card_r.modulate.a = 0.0   # revealed by the flash
	for pair in [[_card_a, specs_a], [_card_b, specs_b]]:
		for sp in pair[1]:
			MergeStatRows.make_row(pair[0].get_meta("rows_box"), sp["icon"], sp["a"], sp["a"], sp["fmt"],
				sp["prefix"], sp["suffix"], sp["tip"], ROW_H, 28.0)
	for sp in specs_r:
		var row := MergeStatRows.make_row(_card_r.get_meta("rows_box"), sp["icon"], sp["a"], sp["b"],
			sp["fmt"], sp["prefix"], sp["suffix"], sp["tip"], ROW_H, 28.0)
		if not is_zero_approx(float(row["total"])):
			_rows.append(row)
	_build_passive_entries(_card_r.get_meta("rows_box"), passive_keys)

	# White flash over the result card (transparent until the merge).
	_flash = Panel.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(1, 1, 1, 1)
	fb.set_corner_radius_all(12)
	_flash.add_theme_stylebox_override("panel", fb)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	_card_r.add_child(_flash)
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.9, 0.9)   # parked/first-frame size; play() grows it to 1

# A Panel (nothing clickable) painted like the reward cards, tinted by rarity.
func _make_card(item: ComponentEquipmentItem, pos: Vector2, h: float) -> Panel:
	var card := Panel.new()
	card.position = pos
	card.size = Vector2(CARD_W, h)
	card.pivot_offset = card.size * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UITheme.card_box(item.icon_color))
	_panel.add_child(card)
	var icon := TextureRect.new()
	icon.position = Vector2((CARD_W - ICON_PX) * 0.5, 22)
	icon.size = Vector2(ICON_PX, ICON_PX)
	icon.pivot_offset = icon.size * 0.5
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = GearIcons.icon_for(item)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)
	var name_l := _label(card, item.name, UITheme.FONT_VALUE, TEXT_NAME,
		Vector2(6, 112), Vector2(CARD_W - 12, 26))
	var chip := _chip(card, item.get_rarity_name().to_upper(), item.icon_color.lightened(0.2),
		Vector2(CARD_W - 8, 8))
	var box := VBoxContainer.new()
	box.position = Vector2(10, HEAD_H)
	box.size = Vector2(CARD_W - 20, h - HEAD_H)
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	card.set_meta("rows_box", box)
	card.set_meta("icon", icon)
	card.set_meta("name", name_l)
	card.set_meta("chip", chip)
	return card

# One entry per passive on the merged item: emblem, "Name Lv N", and what it
# does at that level. Hidden until the stats are done, then popped in one by one.
func _build_passive_entries(box: VBoxContainer, keys: Array) -> void:
	if keys.is_empty():
		return
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(gap)
	for k in keys:
		var key := str(k)
		var level: int = int(_result.passive_levels[k])
		var entry := HBoxContainer.new()
		entry.custom_minimum_size = Vector2(0, PASSIVE_H)
		entry.add_theme_constant_override("separation", 8)
		entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.pivot_offset = Vector2(0, PASSIVE_H * 0.5)
		entry.modulate.a = 0.0
		box.add_child(entry)
		var ic := TextureRect.new()
		ic.custom_minimum_size = Vector2(34, 34)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		ic.texture = GearIcons.emblem(key)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(ic)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(col)
		var nm := Label.new()
		nm.text = "%s  Lv %d" % [GearCatalog.display_name(key), level]
		UITheme.apply_font(nm, UITheme.FONT_BODY)
		nm.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
		nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		nm.add_theme_constant_override("outline_size", 5)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(nm)
		var ds := Label.new()
		ds.text = GearCatalog.describe(key, level)
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.custom_minimum_size = Vector2(120, 0)
		UITheme.apply_read_font(ds, 13)
		ds.add_theme_color_override("font_color", TEXT_NAME)
		ds.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		ds.add_theme_constant_override("outline_size", 4)
		ds.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(ds)
		_passive_entries.append({"node": entry, "name": nm, "desc": ds, "key": key})

# ── Timeline ──────────────────────────────────────────────────────────────────
func _play() -> void:
	var mid_x: float = (PANEL_W - CARD_W) * 0.5
	_tween = create_tween()
	_tween.set_speed_scale(speed)
	_tween.tween_property(_panel, "modulate:a", 1.0, FADE_IN)
	_tween.parallel().tween_property(_panel, "scale", Vector2.ONE, FADE_IN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(HOLD_START)
	_tween.tween_callback(func() -> void: pass)   # step boundary: the parallel slide starts after the hold
	# Both cards slide into the middle together, mirror-image: same easing, same
	# shrink, same fade. Neither is the "base".
	for c in [_card_a, _card_b]:
		_tween.parallel().tween_property(c, "position:x", mid_x, CONVERGE) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		_tween.parallel().tween_property(c, "scale", Vector2(0.86, 0.86), CONVERGE)
		_tween.parallel().tween_property(c, "modulate:a", 0.0, CONVERGE * 0.35).set_delay(CONVERGE * 0.65)
	# Flash: reveal the result where they met.
	_tween.tween_method(_set_flash, 0.0, 1.0, FLASH_UP)
	_tween.parallel().tween_property(_card_r, "scale", Vector2(1.10, 1.10), FLASH_UP).from(Vector2(0.9, 0.9))
	_tween.tween_callback(_apply_result)
	_tween.tween_method(_set_flash, 1.0, 0.0, FLASH_DOWN)
	_tween.parallel().tween_property(_card_r, "scale", Vector2.ONE, FLASH_DOWN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_card_r.get_meta("icon"), "scale", Vector2.ONE, FLASH_DOWN) \
		.from(Vector2(1.5, 1.5)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(HOLD_TRANSFORMED)
	# Stats: one at a time, the gain counting down as the value climbs.
	for row in _rows:
		_tween.tween_callback(MergeStatRows.begin_color.bind(row))
		_tween.tween_method(MergeStatRows.step.bind(row), 0.0, 1.0, ROW_TIME)
		_tween.tween_callback(MergeStatRows.finish.bind(row, self))
		_tween.tween_interval(ROW_GAP)
	for pe in _passive_entries:
		var node: Control = pe["node"]
		_tween.tween_property(node, "modulate:a", 1.0, PASSIVE_POP)
		_tween.parallel().tween_property(node, "scale", Vector2.ONE, PASSIVE_POP) \
			.from(Vector2(0.8, 0.8)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_interval(PASSIVE_GAP)
	_tween.tween_interval(HOLD_PASSIVES if not _passive_entries.is_empty() else HOLD_FINAL)
	_tween.tween_property(_panel, "modulate:a", 0.0, FADE_OUT)
	_tween.parallel().tween_property(_panel, "scale", Vector2(0.94, 0.94), FADE_OUT)
	_tween.tween_callback(_finish)

func _set_flash(a: float) -> void:
	if is_instance_valid(_flash):
		_flash.modulate.a = a * 0.75

func _apply_result() -> void:
	_card_a.visible = false
	_card_b.visible = false
	_card_r.modulate.a = 1.0

func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_root.hide()
	done.emit()
	queue_free()

# ── Widgets ───────────────────────────────────────────────────────────────────
func _label(parent: Node, text: String, px: int, col: Color, pos: Vector2, sz: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = sz
	UITheme.apply_font(l, px)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _chip(parent: Control, text: String, col: Color, right_top: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	UITheme.apply_font(l, UITheme.FONT_CAPTION)
	l.add_theme_color_override("font_color", col)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.04, 0.07, 0.85)
	box.border_color = Color(col.r, col.g, col.b, 0.55)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", box)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	l.reset_size()
	l.position = Vector2(right_top.x - l.size.x, right_top.y)
	l.set_meta("right_edge", right_top.x)
	return l
