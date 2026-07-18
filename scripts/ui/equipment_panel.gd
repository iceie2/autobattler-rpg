extends CanvasLayer
class_name EquipmentPanel

var inventory: EquipmentInventory
var player_units: Array = []
var _panel: Panel
var _inventory_list: VBoxContainer
var _hero_list: ItemList
var _hero_items_list: VBoxContainer
var _selected_hero: UnitBase = null
var _selected_item: EquipmentItem = null

# Combine (upgrade) mode: pick 3 same-rarity items to fuse into one of the next tier.
var _combine_mode: bool = false
var _combine_sel: Array[EquipmentItem] = []
var _combine_toggle_btn: Button
var _combine_status_lbl: Label
var _fuse_btn: Button

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = Vector2(1000, 700)
	# UI theme pass 2026-07-04: dobo card panel instead of flat navy box.
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	overlay.add_child(_panel)

	# Title
	_lbl(_panel, "EQUIPMENT MANAGEMENT", 32, Color(0.85, 0.85, 1.0),
		Vector2(20, 18), Vector2(960, 40), true)

	# Three-column layout: inventory, heroes, hero equipment
	var left_x = 20
	var mid_x = 340
	var right_x = 660
	var col_width = 300
	var content_y = 70
	var content_h = 600

	# Left column: inventory
	_lbl(_panel, "INVENTORY", 16, Color(1.0, 1.0, 0.5),
		Vector2(left_x, content_y), Vector2(col_width, 24), true)

	var inv_scroll = ScrollContainer.new()
	inv_scroll.position = Vector2(left_x, content_y + 28)
	inv_scroll.size = Vector2(col_width, content_h - 60 - 78)   # leave room for combine bar
	_panel.add_child(inv_scroll)

	_inventory_list = VBoxContainer.new()
	_inventory_list.add_theme_constant_override("separation", 4)
	inv_scroll.add_child(_inventory_list)

	# ── Combine (upgrade) bar under the inventory ──
	var combine_y = content_y + 28 + (content_h - 60 - 78) + 6
	_combine_toggle_btn = _btn("⚗ Combine Mode", Rect2(left_x, combine_y, col_width, 26))
	_combine_toggle_btn.pressed.connect(_toggle_combine_mode)
	_panel.add_child(_combine_toggle_btn)

	_combine_status_lbl = _lbl(_panel, "", 13, Color(0.7, 0.7, 0.85),
		Vector2(left_x, combine_y + 30), Vector2(col_width, 18), true)

	_fuse_btn = _btn("Fuse ×3", Rect2(left_x, combine_y + 50, col_width, 26))
	_fuse_btn.pressed.connect(_fuse_selected)
	_fuse_btn.visible = false
	_panel.add_child(_fuse_btn)

	# Middle column: hero list
	_lbl(_panel, "HEROES", 16, Color(1.0, 0.5, 1.0),
		Vector2(mid_x, content_y), Vector2(col_width, 24), true)

	_hero_list = ItemList.new()
	_hero_list.position = Vector2(mid_x, content_y + 28)
	_hero_list.size = Vector2(col_width, content_h - 60)
	_hero_list.item_selected.connect(_on_hero_selected)
	_panel.add_child(_hero_list)

	# Right column: hero equipment
	_lbl(_panel, "EQUIPPED (6 max)", 14, Color(0.5, 1.0, 1.0),
		Vector2(right_x, content_y), Vector2(col_width, 24), true)

	var eq_scroll = ScrollContainer.new()
	eq_scroll.position = Vector2(right_x, content_y + 28)
	eq_scroll.size = Vector2(col_width, content_h - 60)
	_panel.add_child(eq_scroll)

	_hero_items_list = VBoxContainer.new()
	_hero_items_list.add_theme_constant_override("separation", 4)
	eq_scroll.add_child(_hero_items_list)

	# Close button
	var close_btn = _btn("Close", Rect2(450, 660, 100, 32))
	close_btn.pressed.connect(func(): visible = false)
	_panel.add_child(close_btn)

	visible = false
	_center_panel()

func open(inv: EquipmentInventory, units: Array) -> void:
	inventory = inv
	player_units = units
	_combine_mode = false
	_combine_sel.clear()
	_refresh_all()
	_update_combine_ui()
	visible = true

func _refresh_all() -> void:
	_refresh_inventory()
	_refresh_hero_list()
	_refresh_hero_equipment()

func _refresh_inventory() -> void:
	for child in _inventory_list.get_children():
		child.queue_free()

	if inventory.items.size() == 0:
		var label = Label.new()
		label.text = "No items"
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_inventory_list.add_child(label)
		return

	for item in inventory.items:
		_add_inventory_item_button(_inventory_list, item)

func _refresh_hero_list() -> void:
	_hero_list.clear()
	for unit in player_units:
		if unit and is_instance_valid(unit):
			var eq_count = inventory.get_hero_equipment(unit).size()
			_hero_list.add_item("%s (%d/6)" % [unit.unit_name, eq_count])

func _refresh_hero_equipment() -> void:
	for child in _hero_items_list.get_children():
		child.queue_free()

	if not _selected_hero:
		var label = Label.new()
		label.text = "Select a hero"
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_hero_items_list.add_child(label)
		return

	var hero_items = inventory.get_hero_equipment(_selected_hero)
	if hero_items.size() == 0:
		var label = Label.new()
		label.text = "No equipment"
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_hero_items_list.add_child(label)
		return

	for item in hero_items:
		_add_equipped_item_button(_hero_items_list, item)

func _add_inventory_item_button(parent: VBoxContainer, item: EquipmentItem) -> void:
	var btn = Button.new()
	btn.text = item.to_short_string()
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", item.icon_color)
	var selected: bool = _combine_mode and item in _combine_sel
	if selected:
		# Highlighted (selected for combining) — bright rarity-tinted border.
		btn.add_theme_stylebox_override("normal", _flat(item.icon_color.darkened(0.55), item.icon_color, 2, 4))
		btn.add_theme_stylebox_override("hover",  _flat(item.icon_color.darkened(0.45), item.icon_color, 2, 4))
	else:
		btn.add_theme_stylebox_override("normal", _flat(Color(0.1, 0.1, 0.15, 0.8), Color(0.3, 0.3, 0.4), 1, 4))
		btn.add_theme_stylebox_override("hover",  _flat(Color(0.15, 0.15, 0.22, 0.8), Color(0.5, 0.5, 0.6), 1, 4))
	btn.custom_minimum_size = Vector2(280, 40)
	btn.pressed.connect(func():
		if _combine_mode:
			_toggle_combine_selection(item)
		elif _selected_hero:
			if inventory.apply_to_hero(item, _selected_hero):
				_refresh_all()
			else:
				print("Cannot equip: hero full or item invalid")
	)
	parent.add_child(btn)

# ── Combine (upgrade) flow ────────────────────────────────────────────────────
func _toggle_combine_mode() -> void:
	_combine_mode = not _combine_mode
	_combine_sel.clear()
	_refresh_inventory()
	_update_combine_ui()

func _toggle_combine_selection(item: EquipmentItem) -> void:
	if item in _combine_sel:
		_combine_sel.erase(item)
	elif _combine_sel.size() < 3:
		_combine_sel.append(item)
	_refresh_inventory()
	_update_combine_ui()

# Reflect combine state in the toggle label, status line, and Fuse button.
func _update_combine_ui() -> void:
	_combine_toggle_btn.text = "⚗ Combine Mode: ON" if _combine_mode else "⚗ Combine Mode"
	if not _combine_mode:
		_combine_status_lbl.text = "Fuse 3 same-rarity items → 1 upgraded"
		_fuse_btn.visible = false
		return

	var ready_reason := _combine_ready()   # "" = ready, else why not
	if ready_reason == "":
		var r: int = _combine_sel[0].rarity
		var next_name: String = EquipmentItem.new("x", r + 1).get_rarity_name()
		_combine_status_lbl.text = "Ready: 3× %s → %s" % [_combine_sel[0].get_rarity_name(), next_name]
		_fuse_btn.text = "Fuse ×3 → %s" % next_name
		_fuse_btn.visible = true
		_fuse_btn.disabled = false
	else:
		_combine_status_lbl.text = "%d/3 selected — %s" % [_combine_sel.size(), ready_reason]
		_fuse_btn.visible = true
		_fuse_btn.disabled = true

# "" when the current selection can be fused, else a short reason.
func _combine_ready() -> String:
	if _combine_sel.size() < 3:
		return "pick same-rarity items"
	var r: int = _combine_sel[0].rarity
	for it in _combine_sel:
		if it.rarity != r:
			return "must all be same rarity"
	if r >= EquipmentItem.Rarity.LEGENDARY:
		return "Legendary is max tier"
	return ""

func _fuse_selected() -> void:
	if _combine_ready() != "":
		return
	var sources: Array[EquipmentItem] = _combine_sel.duplicate()
	var combined: EquipmentItem = EquipmentManager.combine_items(sources)
	if combined == null:
		return
	for it in sources:
		inventory.remove_item(it)   # emits inventory_changed → sidebar bag refreshes
	inventory.add_item(combined)
	_combine_sel.clear()
	_refresh_all()
	_update_combine_ui()

func _add_equipped_item_button(parent: VBoxContainer, item: EquipmentItem) -> void:
	var btn = Button.new()
	btn.text = "✕ " + item.to_short_string()
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", item.icon_color)
	btn.add_theme_stylebox_override("normal",
		_flat(Color(0.12, 0.12, 0.2, 0.8), Color(0.4, 0.4, 0.5), 1, 4))
	btn.add_theme_stylebox_override("hover",
		_flat(Color(0.18, 0.18, 0.28, 0.8), Color(0.6, 0.6, 0.7), 1, 4))
	btn.custom_minimum_size = Vector2(280, 40)
	btn.pressed.connect(func():
		if _selected_hero:
			inventory.remove_from_hero(item, _selected_hero)
			_refresh_all()
	)
	parent.add_child(btn)

func _on_hero_selected(index: int) -> void:
	if index >= 0 and index < player_units.size():
		_selected_hero = player_units[index] as UnitBase
		_refresh_hero_equipment()

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_panel.position = (vp - _panel.size) / 2.0

func _lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", UITheme.body_font(sz))
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
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	b.add_theme_stylebox_override("normal",  _flat(Color(0.14, 0.14, 0.22), Color(0.4, 0.4, 0.55), 1, 6))
	b.add_theme_stylebox_override("hover",   _flat(Color(0.22, 0.22, 0.33), Color(0.6, 0.6, 0.8), 1, 6))
	b.add_theme_stylebox_override("pressed", _flat(Color(0.1, 0.1, 0.18), Color(0.3, 0.3, 0.5), 1, 6))
	return b

func _flat(bg: Color, border: Color = Color.TRANSPARENT, bw: int = 0, radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = bw
	s.border_width_right = bw
	s.border_width_top = bw
	s.border_width_bottom = bw
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	return s
