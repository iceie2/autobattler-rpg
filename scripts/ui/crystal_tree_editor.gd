extends Control
class_name CrystalTreeEditor

# Dev-only in-game layout editor for the crystal shop tree (2026-07-31).
# Press F9 inside the shop to toggle it; Esc leaves edit mode before it
# closes the shop.
#
# Why this exists: the tree is headed for 5-10x its current node count, and
# hand-authoring positions (the old NODE_LAYOUT with literal 32.25° angles)
# does not survive that. Here you drag nodes where you want them, against the
# real art at the real zoom, and Save writes data/crystal_tree.json back.
#
# Controls:
#   drag a node         move it (moves the whole selection if it's in one)
#   drag empty space    rubber-band select
#   shift+click/band    add to / toggle in the selection
#   middle-drag         pan       |   wheel   zoom
#   ctrl+Z / ctrl+Y     undo / redo (ctrl+shift+Z also redoes)
#
# It only edits LAYOUT — position, size, icon, parent, and which upgrade key
# a slot is bound to. Upgrade content (name/desc/cost/effect) stays in
# Progression.UPGRADES; a slot may be placed before its content exists, and
# Validate reports both directions of mismatch.
#
# Guarded by OS.has_feature("editor") at the toggle site: res:// is read-only
# in an exported build, so there would be nothing to save into.

const PANEL_W := 344.0
const SNAP_STEP := 10.0
const FAN_RADIUS := 150.0    # default distance for the "Fan children" helper
const FAN_SPREAD := 120.0    # degrees the fan spans
const DUPLICATE_OFFSET := Vector2(40, 40)
const UNDO_DEPTH := 64
const BAND_MIN := 4.0        # px before a click counts as a rubber-band drag

var shop: CrystalShop
var active := false

# Selection is a set of keys; _primary is the one whose values the property
# controls display (the last one clicked). Edits apply to the WHOLE selection.
var _selection := PackedStringArray()
var _primary := ""

var _drag_origin := Vector2.ZERO
var _drag_start := {}            # key -> pos at drag start, so snapping can't accumulate drift
var _dragging := false
var _drag_pushed := false        # undo snapshot taken lazily on first motion

var _band_from := Vector2.ZERO
var _banding := false
var _band_additive := false

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []

var _status: Label
var _sel_lbl: Label
var _name_edit: LineEdit
var _desc_edit: TextEdit
# What the fields held when they were last populated — lets the commit
# handlers tell "user actually typed something" from "just refreshed/blurred".
var _name_edit_baseline := ""
var _desc_edit_baseline := ""
var _new_key: LineEdit
var _unplaced: OptionButton
# Multi-parent editing (2026-08-01): a node's current parents are listed with
# a remove button each; a picker + Add button appends a new one. This lives
# in the panel rather than a canvas drag gesture — canvas drags are already
# spoken for by node-move and rubber-band-select, and a picker keeps "which
# parents does X have" scannable at a glance once a node has three or four.
var _parents_box: VBoxContainer
var _parent_add_pick: OptionButton
var _icon_pick: OptionButton
var _size_spin: SpinBox
var _max_spin: SpinBox
var _max_lbl: Label
var _snap_chk: CheckBox
var _suppress_signals := false   # set while repopulating controls programmatically

var _label_layer: Control
var _labels := {}                # key -> Label, so a drag can move one cheaply
var _band_rect: BandRect

# Rubber-band overlay. Lives in canvas space so it stays glued to the tree
# while zoomed, instead of drifting against the nodes it is selecting.
class BandRect extends Control:
	const LINE := Color(1.0, 0.9, 0.55, 0.9)
	const FILL := Color(1.0, 0.9, 0.55, 0.12)
	var band := Rect2()
	func _draw() -> void:
		if band.size == Vector2.ZERO:
			return
		draw_rect(band, FILL, true)
		draw_rect(band, LINE, false, 2.0)

func _ready() -> void:
	# Full-height strip down the shop's right edge — taller than the tree view
	# so it also covers the detail bar's right end, which edit mode doesn't use.
	position = Vector2(1500 - PANEL_W - 16, 86)
	size = Vector2(PANEL_W, 858)
	visible = false
	_build_panel()

func set_active(on: bool) -> void:
	active = on
	visible = on
	# Buttons must stop eating clicks in edit mode so hit-testing/dragging can
	# be handled uniformly by the tree view (see CrystalShop.set_nodes_clickable).
	shop.set_nodes_clickable(not on)
	shop.set_tree_view_expanded(on)
	if on:
		_rebuild_overlays()
		_refresh_controls()
		_set_status("Drag nodes to place. Drag empty space to box-select. "
			+ "Middle-drag pans, wheel zooms, F to frame all.")
	else:
		_clear_overlays()
		shop.highlight_nodes(PackedStringArray())

# ── Panel UI ──────────────────────────────────────────────────────────────────

func _build_panel() -> void:
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", UITheme.panel_box())
	add_child(bg)

	# Scrolling rather than a fixed-height column: the field list only grows
	# as more editing controls land (name/desc were the first to not fit),
	# and a ScrollContainer means that never has to be re-measured by hand.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6, 6)
	scroll.size = Vector2(PANEL_W - 12, size.y - 12)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(PANEL_W - 28, 0)
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)

	_head(col, "TREE EDITOR — F9")
	_status = _text(col, "", 14)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 52

	var undo_row := HBoxContainer.new()
	undo_row.add_theme_constant_override("separation", 6)
	col.add_child(undo_row)
	var ub := _button(undo_row, "↶ Undo", _undo)
	ub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rb := _button(undo_row, "↷ Redo", _redo)
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fb := _button(undo_row, "⛶ Frame", _frame_all)
	fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fb.tooltip_text = "Fit the whole tree in view (F)."

	# ── Add ───────────────────────────────────────────────────────────────
	_head(col, "Add node")
	_unplaced = OptionButton.new()
	_unplaced.tooltip_text = "Upgrades in Progression.UPGRADES with no tree slot yet."
	col.add_child(_unplaced)
	_new_key = LineEdit.new()
	_new_key.placeholder_text = "…or a new key (content added later)"
	col.add_child(_new_key)
	_button(col, "＋  Add at view center", _on_add)

	col.add_child(HSeparator.new())

	# ── Selection ─────────────────────────────────────────────────────────
	_head(col, "Selected")
	_sel_lbl = _text(col, "(nothing selected)", 16)
	_sel_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_text(col, "Name", 13)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "(inherits Progression.UPGRADES)"
	_name_edit.text_submitted.connect(func(_t): _on_name_committed())
	_name_edit.focus_exited.connect(_on_name_committed)
	col.add_child(_name_edit)

	_text(col, "Description", 13)
	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size.y = 64
	_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_desc_edit.placeholder_text = "(inherits Progression.UPGRADES)"
	_desc_edit.focus_exited.connect(_on_desc_committed)
	col.add_child(_desc_edit)
	_button(col, "↺  Revert to catalogue wording", _on_revert_wording)

	_text(col, "Parents", 13)
	_parents_box = VBoxContainer.new()
	_parents_box.add_theme_constant_override("separation", 2)
	col.add_child(_parents_box)
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 6)
	col.add_child(add_row)
	_parent_add_pick = OptionButton.new()
	_parent_add_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_parent_add_pick)
	var add_parent_btn := _button(add_row, "+ Add", _on_add_parent)
	add_parent_btn.tooltip_text = "Add the picked node as another parent " \
		+ "(on top of any it already has). Hub = no parent link at all."

	_text(col, "Icon", 13)
	_icon_pick = OptionButton.new()
	_icon_pick.item_selected.connect(_on_icon_picked)
	col.add_child(_icon_pick)

	_text(col, "Size", 13)
	_size_spin = SpinBox.new()
	_size_spin.min_value = 40
	_size_spin.max_value = 220
	_size_spin.step = 2
	_size_spin.value_changed.connect(_on_size_changed)
	col.add_child(_size_spin)

	_max_lbl = _text(col, "Max level", 13)
	_max_spin = SpinBox.new()
	_max_spin.min_value = 0          # 0 = inherit the catalogue value
	_max_spin.max_value = 99
	_max_spin.step = 1
	_max_spin.tooltip_text = "How many times this node can be bought.\n" \
		+ "0 = inherit whatever Progression.UPGRADES says."
	_max_spin.value_changed.connect(_on_max_level_changed)
	col.add_child(_max_spin)

	_button(col, "⧉  Duplicate", _on_duplicate)
	_button(col, "Fan children around it", _on_fan)
	_button(col, "🗑  Delete", _on_delete)

	col.add_child(HSeparator.new())

	_snap_chk = CheckBox.new()
	_snap_chk.text = "Snap to %dpx grid" % int(SNAP_STEP)
	_snap_chk.button_pressed = true
	col.add_child(_snap_chk)

	_button(col, "Validate", _on_validate)
	_button(col, "💾  Save to crystal_tree.json", _on_save)

func _head(parent: Node, text: String) -> Label:
	var l := _text(parent, text, 18)
	l.add_theme_color_override("font_color", UITheme.TEXT_HEADER)
	return l

func _text(parent: Node, text: String, sz: int) -> Label:
	var l := Label.new()
	l.text = text
	UITheme.apply_font(l, UITheme.body_font(sz))
	l.add_theme_color_override("font_color", UITheme.TEXT_BODY)
	parent.add_child(l)
	return l

func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 32
	UITheme.style_button(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _set_status(msg: String) -> void:
	_status.text = msg

# ── Undo / redo ───────────────────────────────────────────────────────────────
# Snapshot-based: every mutating action stores the tree as it was BEFORE the
# change. See CrystalTree.to_doc/apply_doc for why whole-tree snapshots beat
# per-operation inverses here.

func _push_undo() -> void:
	_undo_stack.append(shop.tree_data().to_doc())
	if _undo_stack.size() > UNDO_DEPTH:
		_undo_stack.pop_front()
	_redo_stack.clear()

func _undo() -> void:
	if _undo_stack.is_empty():
		_set_status("Nothing to undo.")
		return
	_redo_stack.append(shop.tree_data().to_doc())
	_restore(_undo_stack.pop_back())
	_set_status("Undid one step (%d left)." % _undo_stack.size())

func _redo() -> void:
	if _redo_stack.is_empty():
		_set_status("Nothing to redo.")
		return
	_undo_stack.append(shop.tree_data().to_doc())
	_restore(_redo_stack.pop_back())
	_set_status("Redid one step (%d left)." % _redo_stack.size())

func _frame_all() -> void:
	shop.frame_all()
	var b: Rect2 = shop.tree_data().bounds()
	_set_status("Framed %d nodes — %d × %d canvas units." % [
		shop.tree_data().nodes.size(), int(b.size.x), int(b.size.y)])

func _restore(doc: Dictionary) -> void:
	shop.tree_data().apply_doc(doc)
	_prune_selection()          # a restored tree may not contain what was selected
	_sync_overrides()          # caps are part of the snapshot too
	shop.rebuild_tree()
	_apply_selection()

func _input(event: InputEvent) -> void:
	if not active or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# Don't steal shortcuts from the new-key text field.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if not event.ctrl_pressed:
		if event.keycode == KEY_F:
			_frame_all()
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_Z:
		if event.shift_pressed:
			_redo()
		else:
			_undo()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Y:
		_redo()
		get_viewport().set_input_as_handled()

# ── Selection ─────────────────────────────────────────────────────────────────

func _set_selection(keys: PackedStringArray, primary: String = "") -> void:
	_selection = keys
	if primary != "" and _selection.has(primary):
		_primary = primary
	elif not _selection.has(_primary):
		_primary = _selection[_selection.size() - 1] if _selection.size() > 0 else ""
	_apply_selection()

func _apply_selection() -> void:
	shop.highlight_nodes(_selection)
	_refresh_controls()

func _toggle_in_selection(key: String) -> void:
	var idx := _selection.find(key)
	if idx >= 0:
		_selection.remove_at(idx)
	else:
		_selection.append(key)
	_set_selection(_selection, key)

# Drops keys that no longer exist (after an undo, or a delete).
func _prune_selection() -> void:
	var tree := shop.tree_data()
	var kept := PackedStringArray()
	for k in _selection:
		if tree.has(k):
			kept.append(k)
	_selection = kept
	if not _selection.has(_primary):
		_primary = _selection[_selection.size() - 1] if _selection.size() > 0 else ""

# ── Canvas interaction ────────────────────────────────────────────────────────

# Returns true when the event was consumed. Anything not consumed falls back
# to the shop's own pan/zoom handling (wheel zoom, middle-drag pan).
func handle_tree_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		return _handle_click(event)
	if event is InputEventMouseMotion:
		if _dragging:
			_drag_to(shop.view_to_canvas(event.position))
			return true
		if _banding:
			_band_rect.band = _rect_between(_band_from, shop.view_to_canvas(event.position))
			_band_rect.queue_redraw()
			return true
	return false

func _handle_click(event: InputEventMouseButton) -> bool:
	var canvas_pos := shop.view_to_canvas(event.position)
	if event.pressed:
		var key := shop.node_at(canvas_pos)
		if key == "":
			# Empty space starts a box-select. Shift keeps what's already
			# selected so several boxes can be unioned together.
			_band_additive = event.shift_pressed
			if not _band_additive:
				_set_selection(PackedStringArray())
			_band_from = canvas_pos
			_banding = true
			_band_rect.band = Rect2(canvas_pos, Vector2.ZERO)
			_band_rect.queue_redraw()
			return true
		if event.shift_pressed:
			_toggle_in_selection(key)
		elif not _selection.has(key):
			_set_selection(PackedStringArray([key]), key)
		else:
			_primary = key      # clicking inside an existing selection keeps it
			_refresh_controls()
		_begin_drag(canvas_pos)
		return true

	# Release.
	if _dragging:
		_dragging = false
		_drag_pushed = false
		return true
	if _banding:
		_end_band(canvas_pos)
		return true
	return false

func _begin_drag(canvas_pos: Vector2) -> void:
	if _selection.is_empty():
		return
	_dragging = true
	_drag_pushed = false
	_drag_origin = canvas_pos
	# Snapshot start positions so grid snapping is computed from the original
	# spot each frame instead of compounding onto the previous snapped value.
	_drag_start.clear()
	var tree := shop.tree_data()
	for k in _selection:
		var n := tree.find(k)
		if n != null:
			_drag_start[k] = n.pos

func _drag_to(canvas_pos: Vector2) -> void:
	if not _drag_pushed:
		_push_undo()      # lazy: a click that never moves shouldn't cost an undo step
		_drag_pushed = true
	var delta := canvas_pos - _drag_origin
	# Snap the GRABBED node to the grid and move everything else by the same
	# delta. Snapping each node independently would shift off-grid ones
	# relative to their neighbours and quietly deform a moved cluster.
	if _snap_chk.button_pressed and _drag_start.has(_primary):
		var anchor: Vector2 = _drag_start[_primary] + delta
		delta = Vector2(snappedf(anchor.x, SNAP_STEP), snappedf(anchor.y, SNAP_STEP)) \
				- _drag_start[_primary]
	for k: String in _drag_start:
		var pos: Vector2 = _drag_start[k] + delta
		shop.move_node_visual(k, pos)
		var lbl: Label = _labels.get(k)
		if lbl != null:
			lbl.position = _label_pos(shop.tree_data().find(k))
	if _selection.size() == 1:
		var n := shop.tree_data().find(_selection[0])
		_set_status("%s  (%d, %d)" % [_selection[0], int(n.pos.x), int(n.pos.y)])
	else:
		_set_status("Moving %d nodes." % _selection.size())

func _end_band(canvas_pos: Vector2) -> void:
	_banding = false
	var rect := _rect_between(_band_from, canvas_pos)
	_band_rect.band = Rect2()
	_band_rect.queue_redraw()
	if rect.size.x < BAND_MIN and rect.size.y < BAND_MIN:
		return          # a plain click on empty space: just a deselect
	var picked := _selection.duplicate() if _band_additive else PackedStringArray()
	for n in shop.tree_data().nodes:
		if rect.has_point(n.pos) and not picked.has(n.key):
			picked.append(n.key)
	_set_selection(picked)
	_set_status("%d node(s) selected." % picked.size())

func _rect_between(a: Vector2, b: Vector2) -> Rect2:
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())

# ── Control population ────────────────────────────────────────────────────────

func _refresh_controls() -> void:
	_suppress_signals = true
	var tree := shop.tree_data()

	# Unplaced upgrades (content exists, no slot).
	_unplaced.clear()
	for u in Progression.catalogue():
		var k := String(u["key"])
		if not tree.has(k):
			_unplaced.add_item("%s  (%s)" % [k, u["name"]])
			_unplaced.set_item_metadata(_unplaced.item_count - 1, k)
	if _unplaced.item_count == 0:
		_unplaced.add_item("— every upgrade is placed —")
		_unplaced.set_item_metadata(0, "")

	var n := tree.find(_primary) if _primary != "" else null
	var has_sel := n != null
	if _selection.size() > 1:
		_sel_lbl.text = "%d nodes — edits apply to all\n(showing %s)" % [_selection.size(), _primary]
	else:
		_sel_lbl.text = _primary if has_sel else "(nothing selected)"
	_parent_add_pick.disabled = not has_sel
	_icon_pick.disabled = not has_sel
	_size_spin.editable = has_sel

	_name_edit.editable = has_sel
	_desc_edit.editable = has_sel
	if has_sel:
		_name_edit.text = n.name_override
		_name_edit.placeholder_text = "(inherits \"%s\")" % _catalogue_name(_primary)
		_desc_edit.text = n.desc_override
		_desc_edit.placeholder_text = "(inherits catalogue desc)"
	else:
		_name_edit.text = ""
		_desc_edit.text = ""
	_name_edit_baseline = _name_edit.text
	_desc_edit_baseline = _desc_edit.text

	# Current parents: one row per parent link on the primary node, each with
	# its own remove button (removing leaves the node's other parents intact;
	# removing the last one falls back to the hub).
	for c in _parents_box.get_children():
		c.queue_free()
	if has_sel:
		if n.parents.is_empty():
			_text(_parents_box, "(hub — Call to Arms)", 13)
		for p in n.parents:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			_parents_box.add_child(row)
			var lbl := _text(row, p, 13)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var rm := _button(row, "✕", _on_remove_parent.bind(p))
			rm.custom_minimum_size = Vector2(28, 24)
			rm.tooltip_text = "Remove this one parent link (other parents stay)."
	else:
		_text(_parents_box, "(nothing selected)", 13)

	# Add-parent options: the hub, plus every node that wouldn't create a
	# cycle for anything currently selected and isn't already a parent of it.
	_parent_add_pick.clear()
	_parent_add_pick.add_item("(hub — Call to Arms)")
	_parent_add_pick.set_item_metadata(0, "")
	for other in tree.nodes:
		if has_sel and (n.parents.has(other.key) or not _selection_can_parent(other.key)):
			continue
		_parent_add_pick.add_item(other.key)
		_parent_add_pick.set_item_metadata(_parent_add_pick.item_count - 1, other.key)

	_icon_pick.clear()
	for icon in CrystalTree.available_icons():
		_icon_pick.add_item(icon)
		_icon_pick.set_item_metadata(_icon_pick.item_count - 1, icon)
	if has_sel:
		_select_by_metadata(_icon_pick, n.icon)

	_size_spin.value = n.size if has_sel else 96.0

	_max_spin.editable = has_sel
	_max_spin.value = n.max_level if has_sel else 0
	# Spell out what 0 actually resolves to, so "inherit" isn't a mystery value.
	if has_sel:
		_max_lbl.text = "Max level  (0 = inherit → %d)" % _catalogue_max(_primary)
	else:
		_max_lbl.text = "Max level"
	_suppress_signals = false

# What Progression.UPGRADES says, ignoring any override — shown next to the
# spinner so 0 has a visible meaning.
func _catalogue_max(key: String) -> int:
	for u in Progression.catalogue():
		if String(u["key"]) == key:
			return int(u["max_level"])
	return 0

func _catalogue_name(key: String) -> String:
	for u in Progression.catalogue():
		if String(u["key"]) == key:
			return String(u["name"])
	return key

func _selection_can_parent(new_parent: String) -> bool:
	var tree := shop.tree_data()
	for k in _selection:
		if not tree.can_parent(k, new_parent):
			return false
	return true

func _select_by_metadata(opt: OptionButton, value: String) -> void:
	for i in range(opt.item_count):
		if String(opt.get_item_metadata(i)) == value:
			opt.select(i)
			return
	opt.select(-1)

# ── Actions ───────────────────────────────────────────────────────────────────

func _on_add() -> void:
	var key := _new_key.text.strip_edges()
	if key == "" and _unplaced.selected >= 0:
		key = String(_unplaced.get_item_metadata(_unplaced.selected))
	if key == "":
		_set_status("Pick an unplaced upgrade or type a new key first.")
		return
	var tree := shop.tree_data()
	if tree.has(key):
		_set_status("'%s' already has a node." % key)
		return
	_push_undo()
	# Land it in the middle of the current view rather than at the hub — with
	# a large tree the hub is usually nowhere near where you're working.
	tree.add_node(key, shop.view_center_canvas())
	_new_key.text = ""
	shop.rebuild_tree()
	_set_selection(PackedStringArray([key]), key)
	_set_status("Added '%s'. Drag it into place." % key)

# Copies keep the original's parent/size/icon and land offset from it, so a
# duplicated cluster stays readable instead of stacking exactly on top.
func _on_duplicate() -> void:
	if _selection.is_empty():
		_set_status("Select a node to duplicate.")
		return
	_push_undo()
	var tree := shop.tree_data()
	var made := PackedStringArray()
	for k in _selection:
		var src := tree.find(k)
		if src == null:
			continue
		var copy := tree.add_node(tree.unique_key(k), src.pos + DUPLICATE_OFFSET)
		copy.parents = src.parents.duplicate()
		copy.size = src.size
		copy.icon = src.icon
		copy.max_level = src.max_level
		copy.name_override = src.name_override
		copy.desc_override = src.desc_override
		made.append(copy.key)
	_sync_overrides()
	shop.rebuild_tree()
	_set_selection(made)
	_set_status("Duplicated %d node(s) — rename the copies to real upgrade keys." % made.size())

func _on_delete() -> void:
	if _selection.is_empty():
		return
	_push_undo()
	var tree := shop.tree_data()
	var count := _selection.size()
	for k in _selection:
		tree.remove_node(k)
	_set_selection(PackedStringArray())
	shop.rebuild_tree()
	_set_status("Deleted %d node(s) (children re-parented upward)." % count)

func _on_add_parent() -> void:
	if _selection.is_empty() or _parent_add_pick.selected < 0:
		return
	var new_parent := String(_parent_add_pick.get_item_metadata(_parent_add_pick.selected))
	if not _selection_can_parent(new_parent):
		_set_status("That would make a selected node its own ancestor.")
		_refresh_controls()
		return
	_push_undo()
	var tree := shop.tree_data()
	var added := 0
	for k in _selection:
		if new_parent == "":
			continue      # hub is the absence of a link, nothing to add
		if tree.add_parent(k, new_parent):
			added += 1
	shop.rebuild_tree()
	_apply_selection()
	if new_parent == "":
		_set_status("Hub isn't a link to add — remove existing parents instead to fall back to it.")
	else:
		_set_status("Added '%s' as a parent to %d node(s)." % [new_parent, added])

# Removes exactly one parent link from every selected node that has it (the
# ✕ button on a single row only fires for the primary node, but a multi-node
# selection sharing that same parent gets it stripped from all of them too,
# matching how every other property editor here applies to the whole set).
func _on_remove_parent(parent_key: String) -> void:
	if _selection.is_empty():
		return
	_push_undo()
	var tree := shop.tree_data()
	var removed := 0
	for k in _selection:
		if tree.remove_parent(k, parent_key):
			removed += 1
	shop.rebuild_tree()
	_apply_selection()
	_set_status("Removed parent '%s' from %d node(s)." % [parent_key, removed])

func _on_icon_picked(idx: int) -> void:
	if _suppress_signals or _selection.is_empty():
		return
	_push_undo()
	var icon := String(_icon_pick.get_item_metadata(idx))
	for k in _selection:
		shop.tree_data().find(k).icon = icon
	shop.rebuild_tree()
	_apply_selection()

func _on_size_changed(value: float) -> void:
	if _suppress_signals or _selection.is_empty():
		return
	_push_undo()
	for k in _selection:
		shop.tree_data().find(k).size = value
	shop.rebuild_tree()
	_apply_selection()

func _on_name_committed() -> void:
	if _selection.is_empty() or _name_edit.text == _name_edit_baseline:
		return   # blur/refresh with no actual edit — don't spend an undo step
	_push_undo()
	var text := _name_edit.text
	for k in _selection:
		shop.tree_data().find(k).name_override = text
	Progression.apply_tree_overrides(shop.tree_data())
	_name_edit_baseline = text
	shop.rebuild_tree()      # tooltips read the new name
	_apply_selection()
	_refresh_detail_if_selected()
	_set_status("%d node(s) renamed." % _selection.size())

func _on_desc_committed() -> void:
	if _selection.is_empty() or _desc_edit.text == _desc_edit_baseline:
		return
	_push_undo()
	var text := _desc_edit.text
	for k in _selection:
		shop.tree_data().find(k).desc_override = text
	Progression.apply_tree_overrides(shop.tree_data())
	_desc_edit_baseline = text
	_refresh_detail_if_selected()
	_set_status("%d node(s) redescribed." % _selection.size())

func _on_revert_wording() -> void:
	if _selection.is_empty():
		return
	_push_undo()
	for k in _selection:
		var n := shop.tree_data().find(k)
		n.name_override = ""
		n.desc_override = ""
	Progression.apply_tree_overrides(shop.tree_data())
	shop.rebuild_tree()
	_apply_selection()
	_refresh_detail_if_selected()
	_set_status("%d node(s) reverted to catalogue wording." % _selection.size())

# The parchment detail bar is hidden in edit mode, but a designer switching
# out of edit mode right after typing a description should see it took —
# refresh it now instead of waiting for the next select.
func _refresh_detail_if_selected() -> void:
	if shop._selected_key != "" and _selection.has(shop._selected_key):
		shop._refresh()

func _on_max_level_changed(value: float) -> void:
	if _suppress_signals or _selection.is_empty():
		return
	_push_undo()
	for k in _selection:
		shop.tree_data().find(k).max_level = int(value)
	_sync_overrides()
	shop.rebuild_tree()      # progress rings and MAX badges re-read the new cap
	_apply_selection()
	if int(value) == 0:
		_set_status("%d node(s) back to their catalogue max." % _selection.size())
	else:
		_set_status("%d node(s) capped at level %d." % [_selection.size(), int(value)])

# Push the tree's overrides (caps + wording) into Progression so the shop's
# rings/badges/buy-gate/detail-text reflect edits immediately, pre-save.
func _sync_overrides() -> void:
	Progression.apply_tree_overrides(shop.tree_data())

# Evenly spaces the selected node's children on an arc pointing away from its
# own parent — the automated replacement for the hand-computed sibling angles
# the old hardcoded layout needed.
func _on_fan() -> void:
	if _primary == "":
		_set_status("Select the parent node first.")
		return
	var tree := shop.tree_data()
	var n := tree.find(_primary)
	var kids := tree.children_of(_primary)
	if kids.is_empty():
		_set_status("'%s' has no children to fan." % _primary)
		return
	_push_undo()
	# Outward = away from this node's own (first) parent, so branches keep
	# growing away from the hub instead of doubling back over it. With
	# several parents this is just a direction hint, so the first is enough.
	var first_parent := n.parents[0] if not n.parents.is_empty() else ""
	var outward := (n.pos - tree.position_of(first_parent))
	if outward.length() < 1.0:
		outward = Vector2.UP
	var base := outward.angle()
	var spread := deg_to_rad(FAN_SPREAD)
	for i in range(kids.size()):
		# Single child goes straight out; otherwise spread evenly across the arc.
		var t: float = 0.5 if kids.size() == 1 else float(i) / float(kids.size() - 1)
		var a: float = base + (t - 0.5) * spread
		kids[i].pos = n.pos + Vector2(cos(a), sin(a)) * FAN_RADIUS
	shop.rebuild_tree()
	_apply_selection()
	_set_status("Fanned %d children of '%s'." % [kids.size(), _primary])

func _on_validate() -> void:
	var keys := PackedStringArray()
	for u in Progression.catalogue():
		keys.append(String(u["key"]))
	var problems := shop.tree_data().validate(keys)
	if problems.is_empty():
		_set_status("✓ Tree is valid — every upgrade placed, every node bound.")
	else:
		_set_status("%d problem(s):\n• %s" % [problems.size(), "\n• ".join(problems)])

func _on_save() -> void:
	if shop.tree_data().save_to_disk():
		_set_status("✓ Saved %d nodes to %s" % [
			shop.tree_data().nodes.size(), CrystalTree.DATA_PATH])
	else:
		_set_status("✗ Save failed — see the console.")

# ── Canvas overlays (edit mode only) ──────────────────────────────────────────
# Key labels: at 20 nodes you can tell them apart by art; at 150 you cannot.

func _rebuild_overlays() -> void:
	_clear_overlays()
	_label_layer = Control.new()
	_label_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop.editor_canvas().add_child(_label_layer)
	for n in shop.tree_data().nodes:
		var l := Label.new()
		l.text = n.key
		l.position = _label_pos(n)
		l.size = Vector2(160, 18)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.apply_font(l, UITheme.body_font(11))
		l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
		l.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.02, 0.95))
		l.add_theme_constant_override("outline_size", 6)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label_layer.add_child(l)
		_labels[n.key] = l

	# Sized generously rather than anchored: its parent canvas has no size of
	# its own, and the band is drawn in canvas coordinates from origin.
	_band_rect = BandRect.new()
	_band_rect.position = Vector2.ZERO
	_band_rect.size = Vector2(4000, 4000)
	_band_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop.editor_canvas().add_child(_band_rect)

func _label_pos(n: CrystalTree.TreeNode) -> Vector2:
	# Clears the 18px MAX badge that a maxed node draws just under its icon.
	return n.pos + Vector2(-80, n.size / 2.0 + 20)

func _clear_overlays() -> void:
	_labels.clear()
	if is_instance_valid(_label_layer):
		_label_layer.queue_free()
	_label_layer = null
	if is_instance_valid(_band_rect):
		_band_rect.queue_free()
	_band_rect = null

# A rebuild frees the whole canvas, overlays included — put them back.
func on_tree_rebuilt() -> void:
	if active:
		# Fresh buttons default to grabbing clicks — put them back in the
		# pass-through state edit mode needs.
		shop.set_nodes_clickable(false)
		_rebuild_overlays()
