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
# Visual combine tray (2026-08-04): three real slots showing what's selected plus
# a result preview, replacing the old invisible selection set whose only feedback
# was an "n/3 selected" line.
var _slot_boxes: Array[Panel] = []

# Passive-pick overlay (2026-08-04). Fusions are now capped at 1/2/3/4 distinct
# passives by rarity (EquipmentManager.PASSIVE_CAP_BY_RARITY), so when the inputs
# offer more than the cap the PLAYER chooses which survive instead of the game
# silently keeping the strongest.
var _pick_panel: Panel
var _pick_scrim: ColorRect
var _pick_list: VBoxContainer
var _pick_hint: Label
var _pick_confirm: Button
var _pick_sources: Array[EquipmentItem] = []
var _pick_candidates: Array = []
var _pick_chosen: Array[String] = []
var _pick_cap: int = 0

const ICON_PX := 34

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
	inv_scroll.size = Vector2(col_width, 400)   # leave room for the combine tray
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(inv_scroll)

	_inventory_list = VBoxContainer.new()
	_inventory_list.custom_minimum_size = Vector2(col_width - 12, 0)
	_inventory_list.add_theme_constant_override("separation", 4)
	inv_scroll.add_child(_inventory_list)

	# ── Combine tray under the inventory ──
	# Three real slots, so "what have I picked and what will it make" is visible
	# at a glance instead of living in a status string.
	_combine_toggle_btn = _btn("⚗  Combine Mode", Rect2(left_x, 504, col_width, 28))
	_combine_toggle_btn.pressed.connect(_toggle_combine_mode)
	_panel.add_child(_combine_toggle_btn)

	_slot_boxes.clear()
	var slot_w := 92
	var slot_gap := 12
	for i in range(3):
		var box := Panel.new()
		box.position = Vector2(left_x + i * (slot_w + slot_gap), 538)
		box.size = Vector2(slot_w, 88)
		box.add_theme_stylebox_override("panel", UITheme.slot_box())
		_panel.add_child(box)
		_slot_boxes.append(box)

	_combine_status_lbl = _lbl(_panel, "", 13, Color(0.7, 0.7, 0.85),
		Vector2(left_x, 628), Vector2(col_width, 24), true)

	_fuse_btn = _btn("Fuse ×3", Rect2(left_x, 654, col_width, 30))
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

	# Close button — moved right (2026-08-04) so the taller combine tray in the
	# left column has room; the right column's scroll ends at y=638.
	var close_btn = _btn("Close", Rect2(830, 652, 140, 32))
	close_btn.pressed.connect(func(): visible = false)
	_panel.add_child(close_btn)

	# Built LAST on purpose: sibling draw order is child order, so building the
	# pick overlay earlier let the hero list / right column paint straight over
	# the top of it.
	_build_pick_overlay()

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
			_hero_list.add_item("%s (%d/%d)" % [unit.unit_name, eq_count, inventory.hero_item_cap()])

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

# Item art, or null when a name has no icon mapped (EquipmentManager.ITEM_ICONS).
# Cached because the inventory list rebuilds on every refresh and load() on a
# already-imported texture is cheap but not free.
static var _icon_cache: Dictionary = {}
static func _item_icon(item: EquipmentItem) -> Texture2D:
	if _icon_cache.has(item.name):
		return _icon_cache[item.name]
	var p: String = EquipmentManager.ITEM_ICONS.get(item.name, "")
	var tex: Texture2D = (load(p) as Texture2D) if p != "" else null
	_icon_cache[item.name] = tex
	return tex

# Shared look for an item button in either list (2026-08-04): icon on the left,
# rarity-coloured text, rarity-tinted border. The panel used to be a wall of
# untinted text rows, which is most of why it read as unfinished.
func _style_item_button(btn: Button, item: EquipmentItem) -> void:
	btn.icon = _item_icon(item)
	btn.expand_icon = true
	btn.add_theme_constant_override("icon_max_width", ICON_PX)
	btn.add_theme_constant_override("h_separation", 10)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", UITheme.body_font(15))
	btn.add_theme_color_override("font_color", item.icon_color)
	btn.clip_text = true
	btn.tooltip_text = item.to_short_string()
	btn.custom_minimum_size = Vector2(280, ICON_PX + 12)

func _add_inventory_item_button(parent: VBoxContainer, item: EquipmentItem) -> void:
	var btn = Button.new()
	btn.text = "%s (%s)" % [item.name, item.get_rarity_name()]
	_style_item_button(btn, item)
	var selected: bool = _combine_mode and item in _combine_sel
	if selected:
		# Highlighted (selected for combining) — bright rarity-tinted border.
		btn.add_theme_stylebox_override("normal", _flat(item.icon_color.darkened(0.55), item.icon_color, 2, 4))
		btn.add_theme_stylebox_override("hover",  _flat(item.icon_color.darkened(0.45), item.icon_color, 2, 4))
	else:
		# Unselected rows still carry a faint rarity tint on the border so grade
		# is readable without reading the text.
		btn.add_theme_stylebox_override("normal", _flat(Color(0.1, 0.1, 0.15, 0.8), item.icon_color.darkened(0.4), 1, 4))
		btn.add_theme_stylebox_override("hover",  _flat(Color(0.15, 0.15, 0.22, 0.8), item.icon_color, 1, 4))
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

# Paint the three tray slots from the current selection. An empty slot shows a
# dashed placeholder so "you need three" is legible without reading a counter.
func _refresh_slots() -> void:
	for i in range(_slot_boxes.size()):
		var box := _slot_boxes[i]
		for c in box.get_children():
			c.queue_free()
		if not _combine_mode:
			box.visible = false
			continue
		box.visible = true
		if i < _combine_sel.size():
			var item := _combine_sel[i]
			var tex := _item_icon(item)
			if tex:
				var tr := TextureRect.new()
				tr.texture = tex
				tr.position = Vector2(24, 4)
				tr.size = Vector2(44, 44)
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				box.add_child(tr)
			# Dark plate behind the name: rarity colours are dark on a dark slot
			# (grey commons especially), and the first capture had these
			# effectively unreadable sitting straight on the art.
			var plate := ColorRect.new()
			plate.color = Color(0, 0, 0, 0.55)
			plate.position = Vector2(2, 50)
			plate.size = Vector2(88, 34)
			plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(plate)
			var nm := _lbl(box, item.name, 12, item.icon_color.lightened(0.35),
				Vector2(2, 51), Vector2(88, 16), true)
			nm.clip_text = true
			_lbl(box, item.get_rarity_name(), 10, Color(0.72, 0.72, 0.82),
				Vector2(2, 66), Vector2(88, 14), true)
			# Click a filled slot to pull that item back out.
			var clear_btn := Button.new()
			clear_btn.flat = true
			clear_btn.position = Vector2.ZERO
			clear_btn.size = box.size
			clear_btn.tooltip_text = "Remove from tray"
			clear_btn.pressed.connect(func(): _toggle_combine_selection(item))
			box.add_child(clear_btn)
		else:
			_lbl(box, "+", 26, Color(0.45, 0.45, 0.55), Vector2(0, 24), Vector2(88, 34), true)

# Reflect combine state in the toggle label, tray, status line, and Fuse button.
func _update_combine_ui() -> void:
	_combine_toggle_btn.text = "⚗  Combine Mode: ON" if _combine_mode else "⚗  Combine Mode"
	_refresh_slots()
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
	# Passive cap (2026-08-04): if the inputs offer more distinct passives than
	# the result tier can hold, the PLAYER picks which survive. Only ask when
	# there's an actual decision — an over-cap prompt with no choice in it is
	# just a click tax.
	var cap: int = EquipmentManager.passive_cap(sources[0].rarity + 1)
	var candidates: Array = EquipmentManager.candidate_passives(sources)
	if candidates.size() > cap and cap > 0:
		_open_passive_pick(sources, candidates, cap)
		return
	_commit_fuse(sources, [])

func _commit_fuse(sources: Array[EquipmentItem], keep: Array) -> void:
	var combined: EquipmentItem = EquipmentManager.combine_items(sources, keep)
	if combined == null:
		return
	for it in sources:
		inventory.remove_item(it)   # emits inventory_changed → sidebar bag refreshes
	inventory.add_item(combined)
	_combine_sel.clear()
	_refresh_all()
	_update_combine_ui()

# ── Passive pick overlay ──────────────────────────────────────────────────────
func _build_pick_overlay() -> void:
	# Scrim: UITheme.panel_box() is a semi-transparent texture, so without an
	# opaque backdrop the inventory list reads straight through the dialog. It
	# also swallows clicks aimed at the panel underneath.
	_pick_scrim = ColorRect.new()
	_pick_scrim.color = Color(0.02, 0.02, 0.05, 0.88)
	_pick_scrim.position = Vector2.ZERO
	_pick_scrim.size = _panel.size
	_pick_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pick_scrim.visible = false
	_panel.add_child(_pick_scrim)

	_pick_panel = Panel.new()
	_pick_panel.size = Vector2(460, 340)
	_pick_panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	_pick_panel.visible = false
	_pick_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(_pick_panel)
	_pick_panel.position = (_panel.size - _pick_panel.size) / 2.0
	# Second opaque layer behind the dialog's own art, same reason as the scrim.
	var backing := ColorRect.new()
	backing.color = Color(0.06, 0.06, 0.10, 0.97)
	backing.position = Vector2(6, 6)
	backing.size = _pick_panel.size - Vector2(12, 12)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pick_panel.add_child(backing)

	_lbl(_pick_panel, "CHOOSE PASSIVES TO KEEP", 20, Color(0.95, 0.82, 0.5),
		Vector2(0, 16), Vector2(460, 30), true)
	_pick_hint = _lbl(_pick_panel, "", 13, Color(0.72, 0.78, 0.92),
		Vector2(16, 50), Vector2(428, 20), true)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(16, 80)
	scroll.size = Vector2(428, 190)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pick_panel.add_child(scroll)
	_pick_list = VBoxContainer.new()
	_pick_list.custom_minimum_size = Vector2(416, 0)
	_pick_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_pick_list)

	_pick_confirm = _btn("Confirm", Rect2(16, 284, 210, 38))
	_pick_confirm.pressed.connect(_confirm_pick)
	_pick_panel.add_child(_pick_confirm)
	var cancel := _btn("Cancel", Rect2(238, 284, 206, 38))
	cancel.pressed.connect(_close_pick)
	_pick_panel.add_child(cancel)

func _close_pick() -> void:
	_pick_panel.visible = false
	_pick_scrim.visible = false
	_pick_sources.clear()

func _open_passive_pick(sources: Array[EquipmentItem], candidates: Array, cap: int) -> void:
	_pick_sources = sources
	_pick_candidates = candidates
	_pick_cap = cap
	_pick_chosen.clear()
	# Pre-select the strongest, so Confirm without touching anything reproduces
	# the old auto-keep behaviour rather than fusing away every passive.
	for i in range(mini(cap, candidates.size())):
		_pick_chosen.append(str(candidates[i]["name"]))
	_refresh_pick()
	_pick_scrim.visible = true
	_pick_panel.visible = true

func _refresh_pick() -> void:
	_pick_hint.text = "This fusion can carry %d of %d — pick %d." % [
		_pick_cap, _pick_candidates.size(), _pick_cap]
	for c in _pick_list.get_children():
		c.queue_free()
	for cand: Dictionary in _pick_candidates:
		var nm := str(cand["name"])
		var chosen: bool = nm in _pick_chosen
		var b := Button.new()
		b.text = "%s  %s" % ["☑" if chosen else "☐",
			EquipmentItem.describe_passive(nm, float(cand["value"]))]
		b.add_theme_font_size_override("font_size", UITheme.body_font(13))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size = Vector2(410, 38)
		var tint := Color(0.55, 0.9, 0.6) if chosen else Color(0.65, 0.65, 0.75)
		b.add_theme_color_override("font_color", tint)
		b.add_theme_stylebox_override("normal", _flat(Color(0.1, 0.1, 0.16, 0.85), tint.darkened(0.45), 1, 4))
		b.add_theme_stylebox_override("hover",  _flat(Color(0.16, 0.16, 0.24, 0.85), tint, 1, 4))
		b.pressed.connect(func(): _toggle_pick(nm))
		_pick_list.add_child(b)
	_pick_confirm.text = "Confirm (%d/%d)" % [_pick_chosen.size(), _pick_cap]
	_pick_confirm.disabled = _pick_chosen.size() != _pick_cap

func _toggle_pick(nm: String) -> void:
	if nm in _pick_chosen:
		_pick_chosen.erase(nm)
	elif _pick_chosen.size() < _pick_cap:
		_pick_chosen.append(nm)
	else:
		# At the cap: replace the oldest pick so clicking always does something
		# rather than silently no-op'ing.
		_pick_chosen.pop_front()
		_pick_chosen.append(nm)
	_refresh_pick()

func _confirm_pick() -> void:
	if _pick_chosen.size() != _pick_cap or _pick_sources.is_empty():
		return
	var sources := _pick_sources.duplicate()
	var keep := _pick_chosen.duplicate()
	_close_pick()
	_commit_fuse(sources, keep)

func _add_equipped_item_button(parent: VBoxContainer, item: EquipmentItem) -> void:
	var btn = Button.new()
	btn.text = "✕  %s (%s)" % [item.name, item.get_rarity_name()]
	_style_item_button(btn, item)
	btn.tooltip_text = "%s\n\nClick to unequip." % item.to_short_string()
	btn.add_theme_stylebox_override("normal",
		_flat(Color(0.12, 0.12, 0.2, 0.8), item.icon_color.darkened(0.4), 1, 4))
	btn.add_theme_stylebox_override("hover",
		_flat(Color(0.18, 0.18, 0.28, 0.8), item.icon_color, 1, 4))
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
