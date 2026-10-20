extends CanvasLayer
class_name MergeResultScreen

signal done

# Merge transformation toast (2026-09-29, replaces the dismissible result modal).
#
# NOT a menu: no buttons, no Esc, no dim backdrop. main_game creates one per
# merge AFTER the merge is applied, calls present(survivor, before) with the
# snapshot taken BEFORE UnitFactory.merge_heroes, and it plays itself out and
# frees itself:
#
#   1. fade in on the OLD grade — old card colour, old badge letter, old stats,
#      every changed stat shown as "old  +gain" (e.g. 2047 +12)
#   2. transformation: flash + scale pop, the badge flips B → A, the card takes
#      the new grade colour, the portrait brightens
#   3. changed stats only, one at a time: the main value climbs while its gain
#      counts down to +0 (2047 +12 → 2059), integer-stepped for whole stats and
#      2-decimal-snapped for aspd/regen. Old values never change early, so a
#      "2059 → 2059" row cannot appear.
#   4. hold on the finished hero, then fade + shrink slightly, emit done, free.
#
# The full-rect root swallows clicks while it plays so nothing reaches the board.

const PANEL_W := 470.0   # card + one icon/number/gain column
const CARD_W := 190.0
const CARD_H := 270.0
const BAR_EXTRA := 38.0    # extra card height for the merge-progress bar
const BAR_H := 10.0
const PROGRESS_TIME := 0.7
const PORTRAIT := 120.0
const ROW_H := 32.0
const TOP := 58.0

const FADE_IN := 0.20
const WAIT_ALPHA := 0.78   # opacity while parked in the queue
const HOLD_OLD := 0.45
const FLASH_UP := 0.16
const FLASH_DOWN := 0.35
const HOLD_TRANSFORMED := 0.25
const ROW_TIME := 0.32
const ROW_GAP := 0.06
const HOLD_FINAL := 0.90
const FADE_OUT := 0.35

const TEXT_MUTED := Color(0.72, 0.74, 0.86)
const TEXT_GAIN  := Color(0.45, 0.95, 0.50)

# [snapshot key, icon key (UnitFactory.STAT_ICONS), caption, format]
const ROWS := [
	["max_hp",        "hp",        "MAX HP",           "int"],
	["max_mana",      "mana",      "MAX MANA",         "int"],
	["attack_damage", "atk",       "ATTACK",           "int"],
	["magic_power",   "magic",     "MAGIC POWER",      "int"],
	["resistance",    "res",       "ARMOR",            "int"],
	["magic_resist",  "mres",      "MAGIC RESIST",     "int"],
	["attack_speed",  "aspd",      "ATTACKS / SEC",    "f2"],
	["hp_regen",      "hpregen",   "HP REGEN / SEC",   "f2"],
	["mana_regen",    "manaregen", "MANA REGEN / SEC", "f2"],
]

var _root: Control
var _panel: Panel
var _card: Panel
var _flash: Panel
var _portrait: HeroPortrait
var _badge: Label
var _grade_chip: Label
var _rows_box: VBoxContainer
var _rows: Array = []          # [{main, gain, fmt, a, b, total}]
var _old_c := Color.WHITE
var _new_c := Color.WHITE
var _old_g := "B"
var _new_g := "A"
var _tween: Tween
var _partial := false         # grade unchanged: only merge progress moved (a lesser copy)
var _show_bar := false
var _bar_fill: ColorRect
var _bar_lbl: Label
var _bar_w := 0.0
var _bar_from := 0.0          # fill fractions the bar animates between
var _bar_to := 0.0
var _bar_text_to := ""
var _after_frac := 0.0        # after the (optional) grade flip: leftover progress / new threshold
var _after_text := ""
var _finished := false
var speed := 1.0    # set by MergeToastQueue: a backlog plays the toast faster

# Everything the screen compares, captured off the unit. Call BEFORE merging.
static func snapshot(u: UnitBase) -> Dictionary:
	var s := {"grade": u.recruit_grade if u.recruit_grade != "" else "B", "level": u.level,
		"progress": u.merge_progress, "threshold": UnitFactory.merge_value(UnitFactory.grade_of(u))}
	for r in ROWS:
		s[r[0]] = float(u.get(r[0]))
	for key in UnitFactory.MERGE_KEYS:
		s["g_" + key] = u.stat_growth(key)
	return s

# What the toast needs to DRAW the hero, captured at merge time. The queue holds
# this instead of the live unit: by the time a queued toast plays, that unit may
# have been consumed by a later merge.
static func info_of(u: UnitBase) -> Dictionary:
	return {"unit_class": u.unit_class, "name": u.get_class_name_string(),
		"element": u.current_element, "icon": UnitDetailsController.portrait_texture(u)}

func set_speed(s: float) -> void:
	speed = s
	if _tween != null and _tween.is_valid():
		_tween.set_speed_scale(s)

# Convenience for tests / direct use: snapshot the unit's current state as "after".
func present(unit: UnitBase, before: Dictionary) -> void:
	present_data(info_of(unit), before, snapshot(unit))

func present_data(info: Dictionary, before: Dictionary, after: Dictionary) -> void:
	prepare_data(info, before, after)
	play()

# Builds the card without starting the animation. waiting=true parks it visibly
# (dimmed) so the queue can hold it to the right of the playing toast.
func prepare_data(info: Dictionary, before: Dictionary, after: Dictionary, waiting: bool = false) -> void:
	_old_g = before["grade"]
	_new_g = after["grade"]
	_old_c = UnitFactory.GRADE_COLORS.get(_old_g, TEXT_MUTED)
	_new_c = UnitFactory.GRADE_COLORS.get(_new_g, TEXT_GAIN)
	_partial = _old_g == _new_g
	_build(info, before, after)
	# A merge still waiting in the queue: the SAME card, parked to the right, a
	# touch smaller and dimmer, ready to slide into the centre (MergeToastQueue).
	if waiting:
		_panel.modulate.a = WAIT_ALPHA

func play() -> void:
	if _finished:
		return
	_play()

func contains_click(point: Vector2) -> bool:
	var local: Vector2 = _card.get_global_transform_with_canvas().affine_inverse() * point
	return _card.visible and Rect2(Vector2.ZERO, _card.size).has_point(local)

func skip() -> void:
	_finish()

# ── Build ─────────────────────────────────────────────────────────────────────
func _build(info: Dictionary, before: Dictionary, after: Dictionary) -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never blocks input: the merge is already applied
	add_child(_root)

	# Only stats that changed, in display order.
	var changed: Array = []
	for r in ROWS:
		var a: float = before[r[0]]
		var b: float = after[r[0]]
		var total: float
		if r[3] == "int":
			total = float(int(round(b)) - int(round(a)))
		else:
			total = snappedf(b - a, 0.01)
		if not is_zero_approx(total):
			changed.append([r, a, b, total])

	# One card holds everything: hero on the left, the stat rows on the right,
	# all on the grade-coloured card background (no loose text on the board).
	var bp: int = int(before.get("progress", 0))
	var ap: int = int(after.get("progress", 0))
	_show_bar = bp > 0 or ap > 0
	var has_rows: bool = not changed.is_empty()
	var card_h: float = maxf(CARD_H + (BAR_EXTRA if _show_bar else 0.0), changed.size() * ROW_H + 24.0)
	# A partial merge changes no stats: just the hero card, centred.
	var card_w: float = (PANEL_W - 48.0) if has_rows else CARD_W
	var kicker_text := "✦  MERGE PROGRESS  ✦" if _partial else "✦  HEROES MERGED  ✦"
	var panel_h: float = TOP + card_h + 28.0
	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, panel_h)
	_panel.pivot_offset = _panel.size * 0.5
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())   # no backdrop: cards float over the board
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_panel.position = (vp - _panel.size) / 2.0

	var kicker := _lbl(_panel, kicker_text, UITheme.FONT_HEADER, UITheme.menu_title_color(),
		Vector2(0, 14), Vector2(PANEL_W, 34))
	kicker.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	kicker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	kicker.add_theme_constant_override("outline_size", 8)

	# Card starts in the OLD grade's look.
	# A Panel, not a Button: the overlay must contain nothing clickable.
	_card = Panel.new()
	_card.position = Vector2((PANEL_W - card_w) * 0.5, TOP)
	_card.size = Vector2(card_w, card_h)
	_card.pivot_offset = _card.size * 0.5
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint_card(_old_c)
	_panel.add_child(_card)
	_chip(_card, "LV %d" % int(after["level"]), TEXT_MUTED, Vector2(8, 8), false)
	_grade_chip = _chip(_card, "GRADE " + _old_g, _old_c.lightened(0.2), Vector2(CARD_W - 8, 8), true)
	_portrait = HeroPortrait.new()
	_portrait.position = Vector2((CARD_W - PORTRAIT) / 2.0, 30)
	_portrait.size = Vector2(PORTRAIT, PORTRAIT)
	_portrait.pivot_offset = _portrait.size * 0.5
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.modulate = Color(0.78, 0.78, 0.84)   # old treatment: a touch dull
	_card.add_child(_portrait)
	_portrait.setup(info["unit_class"])
	_lbl(_card, str(info["name"]), UITheme.FONT_VALUE,
		SynergyData.element_color(info["element"]).lightened(0.15),
		Vector2(6, 156), Vector2(CARD_W - 12, 26))
	_badge = _lbl(_card, _old_g, UITheme.FONT_DISPLAY, _old_c.lightened(0.2),
		Vector2(0, 190), Vector2(CARD_W, 64))
	_badge.pivot_offset = Vector2(CARD_W * 0.5, 32)
	_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_badge.add_theme_constant_override("outline_size", 6)

	# Merge-progress bar under the grade: a lesser copy fills part of it; leftover
	# progress after a rank-up shows here too.
	if _show_bar:
		_bar_w = CARD_W - 44.0
		var thr_b: int = int(before.get("threshold", 4))
		var thr_a: int = int(after.get("threshold", 4))
		_bar_from = float(bp) / float(thr_b)
		_bar_to = float(ap) / float(thr_a)      # partial: same threshold; rank-up: new one
		_after_frac = _bar_to
		_after_text = UnitFactory.progress_text(ap, thr_a)
		_bar_text_to = _after_text
		var bar_back := ColorRect.new()
		bar_back.position = Vector2(22, 262)
		bar_back.size = Vector2(_bar_w, BAR_H)
		bar_back.color = Color(0, 0, 0, 0.5)
		bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card.add_child(bar_back)
		_bar_fill = ColorRect.new()
		_bar_fill.position = Vector2(22, 262)
		_bar_fill.size = Vector2(_bar_w * _bar_from, BAR_H)
		_bar_fill.color = _old_c.lightened(0.2)
		_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card.add_child(_bar_fill)
		_bar_lbl = _lbl(_card, "PROGRESS  " + UnitFactory.progress_text(bp, thr_b), UITheme.FONT_CAPTION,
			TEXT_MUTED, Vector2(6, 276), Vector2(CARD_W - 12, 18))

	# Hairline between the hero and the numbers.
	if has_rows:
		var divider := ColorRect.new()
		divider.position = Vector2(CARD_W, 18)
		divider.size = Vector2(1, card_h - 36.0)
		divider.color = Color(1, 1, 1, 0.14)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_card.add_child(divider)

	# Stat rows live INSIDE the card, on its colour.
	_rows_box = VBoxContainer.new()
	_rows_box.position = Vector2(CARD_W + 16.0, (card_h - changed.size() * ROW_H) * 0.5)
	_rows_box.size = Vector2(card_w - CARD_W - 28.0, changed.size() * ROW_H)
	_rows_box.add_theme_constant_override("separation", 0)
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_rows_box)
	for c in changed:
		_rows.append(_make_row(c[0], c[1], c[2], c[3]))

	# White flash layer over the whole card (transparent until the transformation).
	_flash = Panel.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(1, 1, 1, 1)
	fb.set_corner_radius_all(12)
	_flash.add_theme_stylebox_override("panel", fb)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	_card.add_child(_flash)

	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.9, 0.9)   # parked/first-frame size; play() grows it to 1

func _make_row(r: Array, a: float, b: float, _total: float) -> Dictionary:
	# Icon only, no stat name (the icon says it; hover gives the name). The
	# counting logic is shared with the equipment merge toast: MergeStatRows.
	var path: String = UnitFactory.STAT_ICONS.get(r[1], "")
	var tex: Texture2D = load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
	return MergeStatRows.make_row(_rows_box, tex, a, b, r[3], "", "", r[2], ROW_H)

# ── Timeline ──────────────────────────────────────────────────────────────────
func _play() -> void:
	_tween = create_tween()
	_tween.set_speed_scale(speed)
	_tween.tween_property(_panel, "modulate:a", 1.0, FADE_IN)
	_tween.parallel().tween_property(_panel, "scale", Vector2.ONE, FADE_IN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(HOLD_OLD)
	if _partial:
		# A lesser copy: the grade does not change, so no flash; the card swells
		# and the merge-progress bar fills.
		_tween.tween_method(_set_bar, 0.0, 1.0, PROGRESS_TIME)
		_tween.parallel().tween_property(_card, "scale", Vector2(1.06, 1.06), PROGRESS_TIME * 0.5)
		_tween.tween_property(_card, "scale", Vector2.ONE, 0.18)
		_tween.tween_interval(HOLD_TRANSFORMED)
	else:
		# Transformation: flash up, swap to the new grade at the peak, flash down.
		_tween.tween_method(_set_flash, 0.0, 1.0, FLASH_UP)
		_tween.parallel().tween_property(_card, "scale", Vector2(1.10, 1.10), FLASH_UP)
		_tween.tween_callback(_apply_new_grade)
		_tween.tween_method(_set_flash, 1.0, 0.0, FLASH_DOWN)
		_tween.parallel().tween_property(_card, "scale", Vector2.ONE, FLASH_DOWN) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.parallel().tween_property(_badge, "scale", Vector2.ONE, FLASH_DOWN) \
			.from(Vector2(1.6, 1.6)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_interval(HOLD_TRANSFORMED)
	# Changed stats, one at a time.
	for row in _rows:
		_tween.tween_callback(MergeStatRows.begin_color.bind(row))
		_tween.tween_method(MergeStatRows.step.bind(row), 0.0, 1.0, ROW_TIME)
		_tween.tween_callback(MergeStatRows.finish.bind(row, self))
		_tween.tween_interval(ROW_GAP)
	_tween.tween_interval(HOLD_FINAL)
	_tween.tween_property(_panel, "modulate:a", 0.0, FADE_OUT)
	_tween.parallel().tween_property(_panel, "scale", Vector2(0.94, 0.94), FADE_OUT)
	_tween.tween_callback(_finish)

func _set_flash(a: float) -> void:
	if is_instance_valid(_flash):
		_flash.modulate.a = a * 0.75

func _apply_new_grade() -> void:
	_badge.text = _new_g
	_badge.add_theme_color_override("font_color", _new_c.lightened(0.2))
	_grade_chip.text = "GRADE " + _new_g
	_grade_chip.add_theme_color_override("font_color", _new_c.lightened(0.2))
	_grade_chip.reset_size()
	_grade_chip.position.x = float(_grade_chip.get_meta("right_edge")) - _grade_chip.size.x
	_paint_card(_new_c)
	_portrait.modulate = Color.WHITE
	if _show_bar:
		# After a rank-up the bar restarts toward the NEXT grade with whatever was left over.
		_bar_fill.color = _new_c.lightened(0.2)
		_bar_fill.size.x = _bar_w * _after_frac
		_bar_lbl.text = "PROGRESS  " + _after_text

# 0 → 1: fills the merge-progress bar of a partial merge.
func _set_bar(t: float) -> void:
	if not is_instance_valid(_bar_fill):
		return
	_bar_fill.size.x = _bar_w * lerpf(_bar_from, _bar_to, t)
	if t >= 1.0:
		_bar_lbl.text = "PROGRESS  " + _bar_text_to

# Same look as UITheme.paint_card (the reward screen's cards), as a panel.
func _paint_card(accent: Color) -> void:
	_card.add_theme_stylebox_override("panel", UITheme.card_box(accent))

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
func _lbl(parent: Node, text: String, px: int, col: Color, pos: Vector2, sz: Vector2) -> Label:
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

func _chip(parent: Control, text: String, col: Color, pos: Vector2, right_align: bool) -> Label:
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
	l.position = Vector2(pos.x - l.size.x, pos.y) if right_align else pos
	if right_align:
		l.set_meta("right_edge", pos.x)
	return l
