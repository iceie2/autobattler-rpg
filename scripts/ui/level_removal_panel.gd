extends Control
class_name LevelRemovalPanel

# The "REMOVE N LEVEL(S)" merge menu (redesigned 2026-09-29). When two items'
# passives pool past the result's level budget, the player picks which levels to
# sacrifice, then merges. Pure UI: it knows a pool {passive_key: level} and a
# number of levels to remove, and reports the choice through two signals. The
# merge rules live in ComponentEquipmentRules; EquipmentPanel does the merge.
#
# Flow (need == 1, the common case): pick one passive -> its row turns to the
# "removing" state -> the gold merge button wakes up. Click the row again to
# undo. Cancel / Escape / the back button closes without changing anything.
# need > 1 (purple + purple): clicking a row removes one more level from it, up
# to `need` in total; clicking a row that is already marked undoes one level.

signal confirmed(removals: Dictionary)   # {passive_key: levels_to_remove}
signal cancelled

# ── Palette: dark fantasy, gold/bronze plates, crimson for sacrifice ──────────
const C_TITLE := Color(0.95, 0.82, 0.5)
const C_TEXT := Color(0.94, 0.92, 0.86)
const C_DIM := Color(0.62, 0.64, 0.74)
const C_GOLD := Color(0.90, 0.74, 0.36)
const C_BRONZE := Color(0.45, 0.33, 0.15)
const C_DANGER := Color(0.93, 0.30, 0.20)
const C_DANGER_TEXT := Color(1.0, 0.78, 0.68)
const C_BTN_TEXT := Color(0.29, 0.18, 0.03)        # UITheme.TEXT_BTN: dark brown on gold
const ROW_CUT := 3.0
const BTN_CUT := 5.0

var _pool: Dictionary = {}
var _removed: Dictionary = {}
var _need: int = 1
var _resolved: bool = false
var _kb_active: bool = false

var _dialog: PanelContainer
var _title: Label
var _instruction: Label
var _helper: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _status_left: Label
var _status_right: Label
var _merge_btn: Button
var _merge_count: Label
var _merge_glyph: MergeGlyph
var _cancel_btn: Button
var _rows: Dictionary = {}          # passive_key -> RemovalRow
var _was_ready: bool = false

func _ready() -> void:
	_build()
	visible = false

# ══ Public API ════════════════════════════════════════════════════════════════
func open(pool: Dictionary, need: int) -> void:
	_pool = pool.duplicate()
	_need = maxi(need, 1)
	_removed.clear()
	_resolved = false
	_was_ready = false
	_rebuild_rows()
	_refresh(false)
	visible = true
	call_deferred("_grab_initial_focus")

func close() -> void:
	visible = false

func is_open() -> bool:
	return visible

# One click on a row. Returns nothing; read state through the accessors below.
func toggle(key: String) -> void:
	if _resolved or not _pool.has(key):
		return
	var gone := int(_removed.get(key, 0))
	if total() < _need and gone < int(_pool[key]):
		_removed[key] = gone + 1
	elif gone > 0:
		_removed[key] = gone - 1
		if int(_removed[key]) == 0:
			_removed.erase(key)
	elif _need == 1 and total() == 1:
		# Changing your mind: one pick is the whole budget, so a second row
		# takes over from the first instead of doing nothing.
		_removed.clear()
		_removed[key] = 1
	else:
		return
	_refresh(true, key)

func total() -> int:
	var n := 0
	for v in _removed.values():
		n += int(v)
	return n

func need() -> int:
	return _need

func can_merge() -> bool:
	return not _resolved and total() == _need

func removals() -> Dictionary:
	return _removed.duplicate()

func is_removing(key: String) -> bool:
	return int(_removed.get(key, 0)) > 0

func row_keys() -> Array:
	return _pool.keys()

func status_text() -> String:
	return _status_left.text

func count_text() -> String:
	return _status_right.text

func merge_text() -> String:
	return _merge_btn.text

func merge_button() -> Button:
	return _merge_btn

func cancel_button() -> Button:
	return _cancel_btn

func row_button(key: String) -> Button:
	return (_rows[key] as RemovalRow).hit

func row_node(key: String) -> Control:
	return _rows[key]

func dialog_rect() -> Rect2:
	return _dialog.get_global_rect()

# Merge button press. False (and no signal) unless exactly `need` levels are marked.
func try_confirm() -> bool:
	if not can_merge():
		return false
	_resolved = true
	_merge_btn.disabled = true
	var out := _removed.duplicate()
	visible = false
	confirmed.emit(out)
	return true

func cancel() -> void:
	if _resolved:
		return
	_resolved = true
	visible = false
	cancelled.emit()

# ══ Input ═════════════════════════════════════════════════════════════════════
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if _kb_active:
			_kb_active = false
			_refresh_rows_style()
	elif event is InputEventKey or event is InputEventJoypadButton:
		if not _kb_active:
			_kb_active = true
			_refresh_rows_style()
	# Escape / controller back = Cancel (the game's convention for every modal).
	# Handled here, ahead of main_game._input, so it closes THIS menu and not the
	# equipment panel underneath it.
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()

func _grab_initial_focus() -> void:
	if not visible:
		return
	var first: Variant = _rows.values()[0] if not _rows.is_empty() else null
	if first:
		(first as RemovalRow).hit.grab_focus()

# ══ Build ═════════════════════════════════════════════════════════════════════
func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.02, 0.05, 0.86)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_dialog = PanelContainer.new()
	_dialog.custom_minimum_size = Vector2(620, 0)
	_dialog.add_theme_stylebox_override("panel", UITheme.panel_box())
	center.add_child(_dialog)

	# Opaque backing under the parchment art, same reason the old overlay had
	# one: panel_box() is semi-transparent and the bag list read straight through.
	var backing_margin := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		backing_margin.add_theme_constant_override(k, 6)
	backing_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(backing_margin)
	var backing := ColorRect.new()
	backing.color = Color(0.06, 0.06, 0.10, 0.98)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backing_margin.add_child(backing)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 22)
	_dialog.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	_title = _label(UITheme.FONT_HEADER, C_TITLE)
	box.add_child(_title)
	_instruction = _label(UITheme.FONT_VALUE, C_TEXT)
	box.add_child(_instruction)
	_helper = _label(UITheme.FONT_BODY, C_DIM, true)
	box.add_child(_helper)
	box.add_child(_divider())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	box.add_child(_divider())
	var status := HBoxContainer.new()
	_status_left = _label(UITheme.FONT_VALUE, C_DIM)
	_status_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_right = _label(UITheme.FONT_VALUE, C_DIM)
	_status_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(_status_left)
	status.add_child(_status_right)
	box.add_child(status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	_merge_btn = _make_button()
	_merge_btn.pressed.connect(try_confirm)
	buttons.add_child(_merge_btn)
	_merge_glyph = MergeGlyph.new()
	_merge_glyph.position = Vector2(16, 0)
	_merge_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_merge_btn.add_child(_merge_glyph)
	_merge_count = Label.new()
	UITheme.apply_font(_merge_count, UITheme.FONT_BODY)
	_merge_count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_merge_count.offset_right = -14
	_merge_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_merge_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_merge_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_merge_btn.add_child(_merge_count)
	_cancel_btn = _make_button()
	_cancel_btn.text = "CANCEL"
	_cancel_btn.pressed.connect(cancel)
	buttons.add_child(_cancel_btn)
	_style_secondary_button(_cancel_btn)
	_merge_btn.focus_neighbor_right = _merge_btn.get_path_to(_cancel_btn)
	_cancel_btn.focus_neighbor_left = _cancel_btn.get_path_to(_merge_btn)

func _label(size: int, color: Color, read: bool = false) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	if read:
		UITheme.apply_read_font(l, size)     # prose: Inter
	else:
		UITheme.apply_font(l, size)          # chrome: LeagueGothic
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Color(C_BRONZE, 0.85)
	d.custom_minimum_size = Vector2(0, 2)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

func _make_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 54)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	UITheme.apply_font(b, UITheme.FONT_VALUE)
	var ring := ChamferBox.make(Color(0, 0, 0, 0), Color(1.0, 0.92, 0.6), BTN_CUT, 2.0)
	ring.hollow = true
	b.add_theme_stylebox_override("focus", ring)
	b.pivot_offset = Vector2(120, 27)
	return b

# Gold primary plate: bright when it can be pressed, dead bronze when it cannot.
func _style_primary_button(ready: bool) -> void:
	var b := _merge_btn
	var dark := Color(0.16, 0.10, 0.03)
	if ready:
		b.add_theme_stylebox_override("normal", ChamferBox.make(Color(0.87, 0.66, 0.22), dark, BTN_CUT, 2.0,
			Color(1.0, 0.94, 0.62, 0.9), Color(0.55, 0.36, 0.08, 0.9)))
		b.add_theme_stylebox_override("hover", ChamferBox.make(Color(0.98, 0.80, 0.32), dark, BTN_CUT, 2.0,
			Color(1.0, 0.97, 0.75, 0.95), Color(0.6, 0.4, 0.1, 0.9), Color(1.0, 0.85, 0.4, 0.35)))
		b.add_theme_stylebox_override("pressed", ChamferBox.make(Color(0.72, 0.53, 0.15), dark, BTN_CUT, 2.0,
			Color(0, 0, 0, 0), Color(1.0, 0.9, 0.55, 0.4)))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, C_BTN_TEXT)
	else:
		var off := ChamferBox.make(Color(0.20, 0.17, 0.13), Color(0.36, 0.29, 0.18), BTN_CUT, 2.0,
			Color(1, 1, 1, 0.04), Color(0, 0, 0, 0.3))
		b.add_theme_stylebox_override("disabled", off)
		b.add_theme_color_override("font_disabled_color", Color(0.58, 0.52, 0.42))

func _style_secondary_button(b: Button) -> void:
	var text := Color(0.86, 0.82, 0.72)
	b.add_theme_stylebox_override("normal", ChamferBox.make(Color(0.15, 0.15, 0.19), Color(0.48, 0.40, 0.26), BTN_CUT, 2.0,
		Color(1, 1, 1, 0.07), Color(0, 0, 0, 0.35)))
	b.add_theme_stylebox_override("hover", ChamferBox.make(Color(0.22, 0.22, 0.28), Color(0.72, 0.60, 0.34), BTN_CUT, 2.0,
		Color(1, 1, 1, 0.1), Color(0, 0, 0, 0.35), Color(0.9, 0.74, 0.36, 0.18)))
	b.add_theme_stylebox_override("pressed", ChamferBox.make(Color(0.11, 0.11, 0.15), Color(0.6, 0.5, 0.3), BTN_CUT, 2.0))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, text)

# ══ Rows ══════════════════════════════════════════════════════════════════════
func _rebuild_rows() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	for key in _pool:
		var row := RemovalRow.new()
		row.setup(str(key))
		row.toggled_requested.connect(toggle)
		_list.add_child(row)
		_rows[key] = row
	_wire_focus()
	_fit_scroll()

# Show up to four rows before scrolling (a purple+purple pool can hold six).
# Row heights depend on how their descriptions wrap, which is only known after
# layout, so measure the real rows two frames in; the dialog fades in after.
func _fit_scroll() -> void:
	_dialog.modulate.a = 0.0
	_scroll.custom_minimum_size = Vector2(0, 84)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(_list):
		return
	var h := 0.0
	var shown := 0
	for c in _list.get_children():
		if c.is_queued_for_deletion():
			continue
		if shown >= 4:
			break
		h += c.size.y + (8.0 if shown > 0 else 0.0)
		shown += 1
	_scroll.custom_minimum_size = Vector2(0, maxf(h, 84.0))
	_dialog.modulate.a = 1.0

func _wire_focus() -> void:
	var keys := _rows.keys()
	for i in range(keys.size()):
		var hit: Button = (_rows[keys[i]] as RemovalRow).hit
		if i > 0:
			hit.focus_neighbor_top = hit.get_path_to((_rows[keys[i - 1]] as RemovalRow).hit)
		if i < keys.size() - 1:
			hit.focus_neighbor_bottom = hit.get_path_to((_rows[keys[i + 1]] as RemovalRow).hit)
	if not keys.is_empty():
		var last: Button = (_rows[keys[keys.size() - 1]] as RemovalRow).hit
		last.focus_neighbor_bottom = last.get_path_to(_cancel_btn)
		_cancel_btn.focus_neighbor_top = _cancel_btn.get_path_to(last)
		_merge_btn.focus_neighbor_top = _merge_btn.get_path_to(last)

func _refresh_rows_style() -> void:
	for row in _rows.values():
		(row as RemovalRow).show_focus = _kb_active
		(row as RemovalRow).restyle()

func _refresh(animate: bool, changed_key: String = "") -> void:
	var one := _need == 1
	_title.text = "REMOVE %d LEVEL%s" % [_need, "" if one else "S"]
	_instruction.text = "Choose one passive to sacrifice" if one \
		else "Choose %d levels to sacrifice" % _need
	_helper.text = "Click it again to undo before merging."
	for key in _rows:
		var row := _rows[key] as RemovalRow
		row.show_focus = _kb_active
		row.set_removal(int(_pool[key]), int(_removed.get(key, 0)), animate and key == changed_key)
	var done := total()
	_status_right.text = "%d / %d" % [done, _need]
	if done < _need:
		_status_left.text = ("Select 1 passive" if one else "Select %d levels" % (_need - done))
		_status_left.add_theme_color_override("font_color", C_DIM)
		_status_right.add_theme_color_override("font_color", C_DIM)
	else:
		_status_left.text = ("1 passive will be removed" if one else "%d levels will be removed" % _need)
		_status_left.add_theme_color_override("font_color", C_DANGER_TEXT)
		_status_right.add_theme_color_override("font_color", C_DANGER_TEXT)
	var ready := can_merge()
	_style_primary_button(ready)
	_merge_btn.disabled = not ready
	_merge_btn.text = "REMOVE & MERGE" if ready else ("SELECT A PASSIVE" if one else "SELECT %d LEVELS" % _need)
	_merge_count.text = _status_right.text
	_merge_count.add_theme_color_override("font_color", C_BTN_TEXT if ready else Color(0.58, 0.52, 0.42))
	_merge_glyph.visible = ready
	if ready and not _was_ready and animate:
		_pop_merge_button()
	_was_ready = ready

# The button wakes up: a quick flash and a small pop, nothing that costs time.
func _pop_merge_button() -> void:
	_merge_btn.pivot_offset = _merge_btn.size * 0.5
	_merge_btn.modulate = Color(1.45, 1.3, 1.0)
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_merge_btn, "modulate", Color.WHITE, 0.30)
	t.tween_property(_merge_btn, "scale", Vector2(1.04, 1.04), 0.09)
	t.chain().tween_property(_merge_btn, "scale", Vector2.ONE, 0.14)

# ══ Row control ═══════════════════════════════════════════════════════════════
class RemovalRow extends PanelContainer:
	signal toggled_requested(key: String)
	var key: String = ""
	var have: int = 1
	var gone: int = 0
	var hovered: bool = false
	var focused: bool = false
	var show_focus: bool = false          # focus glow only after keyboard / pad input
	var hit: Button
	var _icon: TextureRect
	var _name: Label
	var _chip: Label
	var _desc: Label
	var _hint: Label
	var _slot: SelectionSlot
	var _tween: Tween

	func setup(p_key: String) -> void:
		key = p_key
		custom_minimum_size = Vector2(0, 84)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_bottom", 8)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(margin)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(line)

		_icon = TextureRect.new()
		_icon.texture = GearIcons.emblem(key)
		_icon.custom_minimum_size = Vector2(52, 52)
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(_icon)

		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 2)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(text)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(head)
		_name = Label.new()
		UITheme.apply_font(_name, UITheme.FONT_HEADER)
		_name.text = GearCatalog.display_name(key)
		_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(_name)
		_chip = Label.new()
		UITheme.apply_font(_chip, UITheme.FONT_BODY)
		_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(_chip)
		_desc = Label.new()
		UITheme.apply_read_font(_desc, UITheme.FONT_READ)
		_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_desc.custom_minimum_size = Vector2(180, 0)
		_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(_desc)

		var side := HBoxContainer.new()
		side.add_theme_constant_override("separation", 8)
		side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(side)
		_hint = Label.new()
		UITheme.apply_font(_hint, UITheme.FONT_VALUE)
		_hint.custom_minimum_size = Vector2(112, 0)
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		side.add_child(_hint)
		_slot = SelectionSlot.new()
		_slot.custom_minimum_size = Vector2(26, 26)
		_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		side.add_child(_slot)

		# The whole row is one flat button on top: clicks, keyboard focus and
		# controller navigation all come for free, and the row draws its own state.
		hit = Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_ALL
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var none := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "disabled", "focus"]:
			hit.add_theme_stylebox_override(s, none)
		hit.mouse_entered.connect(func(): hovered = true; restyle())
		hit.mouse_exited.connect(func(): hovered = false; restyle())
		hit.focus_entered.connect(func(): focused = true; restyle())
		hit.focus_exited.connect(func(): focused = false; restyle())
		hit.pressed.connect(func(): toggled_requested.emit(key))
		add_child(hit)
		restyle()

	func set_removal(p_have: int, p_gone: int, pulse: bool) -> void:
		var was_selected := gone > 0
		have = p_have
		gone = p_gone
		_desc.text = GearCatalog.describe(key, have)
		if gone == 0:
			_chip.text = "Lv %d" % have
		elif have - gone > 0:
			_chip.text = "Lv %d → %d" % [have, have - gone]
		else:
			_chip.text = "Lv %d → gone" % have
		hit.tooltip_text = "%s: %s" % [_name.text, _desc.text]
		restyle()
		if pulse and gone > 0 and not was_selected:
			flash()

	func is_selected() -> bool:
		return gone > 0

	func restyle() -> void:
		var selected := gone > 0
		var lit := hovered or (focused and show_focus)
		var box: ChamferBox
		if selected:
			box = ChamferBox.make(Color(0.23, 0.075, 0.07), LevelRemovalPanel.C_DANGER if not lit \
				else Color(1.0, 0.42, 0.3), LevelRemovalPanel.ROW_CUT, 2.0, Color(1.0, 0.5, 0.4, 0.22),
				Color(0, 0, 0, 0.4), Color(LevelRemovalPanel.C_DANGER, 0.28))
		elif lit:
			box = ChamferBox.make(Color(0.15, 0.15, 0.22), LevelRemovalPanel.C_GOLD, LevelRemovalPanel.ROW_CUT, 2.0,
				Color(1, 1, 1, 0.08), Color(0, 0, 0, 0.35), Color(LevelRemovalPanel.C_GOLD, 0.2))
		else:
			box = ChamferBox.make(Color(0.09, 0.09, 0.14), Color(0.32, 0.30, 0.42), LevelRemovalPanel.ROW_CUT, 2.0,
				Color(1, 1, 1, 0.05), Color(0, 0, 0, 0.35))
		box.set_content_margin_all(0)
		add_theme_stylebox_override("panel", box)
		_name.add_theme_color_override("font_color",
			LevelRemovalPanel.C_DANGER_TEXT if selected else LevelRemovalPanel.C_TEXT)
		_chip.add_theme_color_override("font_color",
			Color(1.0, 0.6, 0.48) if selected else LevelRemovalPanel.C_DIM)
		_desc.add_theme_color_override("font_color",
			Color(0.74, 0.60, 0.58) if selected else Color(0.72, 0.74, 0.84))
		_icon.modulate = Color(1, 0.8, 0.75) if selected else Color.WHITE
		if selected:
			_hint.text = "REMOVING" if gone < 2 else "REMOVING ×%d" % gone
			_hint.add_theme_color_override("font_color", Color(1.0, 0.5, 0.38))
			_slot.set_state(SelectionSlot.State.REMOVING)
		elif lit:
			_hint.text = "REMOVE"
			_hint.add_theme_color_override("font_color", Color(LevelRemovalPanel.C_GOLD, 0.9))
			_slot.set_state(SelectionSlot.State.HOVER)
		else:
			_hint.text = ""
			_slot.set_state(SelectionSlot.State.EMPTY)

	# A short crimson flash the moment a row is marked for removal.
	func flash() -> void:
		if _tween and _tween.is_valid():
			_tween.kill()
		modulate = Color(1.55, 1.1, 1.05)
		_tween = create_tween()
		_tween.tween_property(self, "modulate", Color.WHITE, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# Empty square -> gold-lit square -> filled crimson square with a minus.
class SelectionSlot extends Control:
	enum State { EMPTY, HOVER, REMOVING }
	var state: int = State.EMPTY

	func set_state(s: int) -> void:
		if s != state:
			state = s
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		match state:
			State.EMPTY:
				draw_rect(r, Color(0.5, 0.48, 0.6), false, 2.0)
			State.HOVER:
				draw_rect(r, LevelRemovalPanel.C_GOLD, false, 2.0)
				draw_line(r.position + Vector2(5, r.size.y * 0.5), r.position + Vector2(r.size.x - 5, r.size.y * 0.5),
					Color(LevelRemovalPanel.C_GOLD, 0.55), 2.0)
			State.REMOVING:
				draw_rect(r, LevelRemovalPanel.C_DANGER)
				draw_rect(r, Color(1.0, 0.7, 0.6), false, 2.0)
				draw_line(r.position + Vector2(5, r.size.y * 0.5), r.position + Vector2(r.size.x - 5, r.size.y * 0.5),
					Color.WHITE, 3.0)

# Two chevrons meeting in the middle: a small "merge" mark for the gold button.
class MergeGlyph extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(22, 54)
		size = Vector2(22, 54)

	func _draw() -> void:
		var c := LevelRemovalPanel.C_BTN_TEXT
		var y := size.y * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(1, y - 8), Vector2(9, y), Vector2(1, y + 8)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(21, y - 8), Vector2(13, y), Vector2(21, y + 8)]), c)
