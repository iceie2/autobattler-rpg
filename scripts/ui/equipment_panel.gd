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
var _hero_empty_lbl: Label
var _equipped_head: Label

func _component_mode() -> bool:
	return inventory is ComponentEquipmentInventory

func _combine_width() -> int:
	return 2 if _component_mode() else 3

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
# True when this pick was opened by Auto-Combine (2026-08-06) rather than the
# manual Fuse button — routes Confirm/Cancel to EquipmentInventory's
# resolve_auto_pick/cancel_auto_pick instead of the local _commit_fuse.
var _pick_is_auto: bool = false
var _pick_title: Label
# Component merge menu (EQUIPMENT_GREEN_PAIRS.md): both inputs' passives are
# pooled and the player removes levels until the pool fits the result's budget.
var _rm_removed: Dictionary = {}          # handed to combine_components by _commit_fuse
var _removal_panel: LevelRemovalPanel
var _removal_sources: Array[EquipmentItem] = []

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
	# 2026-09-27 screen audit: moved onto the shared menu chrome (banner +
	# menu_surface_box, dark and light). The banner costs 34px, so every
	# absolute y below the title moved down by TOP (was 70 → 104 etc).
	_panel.size = Vector2(1000, 734)
	_panel.add_theme_stylebox_override("panel", UITheme.menu_surface_box())
	overlay.add_child(_panel)
	UITheme.menu_header(_panel, Rect2(18, 12, 964, 84))

	# Title
	_lbl(_panel, "EQUIPMENT", 32, UITheme.menu_title_color(),
		Vector2(20, 30), Vector2(960, 48), true)

	# Three-column layout: inventory, heroes, hero equipment
	var left_x = 20
	var mid_x = 340
	var right_x = 660
	var col_width = 300
	var content_y = 104
	var content_h = 600
	var col_head: Color = UITheme.menu_title_color() if UITheme.is_light() \
		else Color(0.95, 0.82, 0.52)

	# Left column: inventory
	_lbl(_panel, "INVENTORY", 16, col_head,
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
	_combine_toggle_btn = _btn("⚗  Combine Mode", Rect2(left_x, 538, col_width - 96, 28))
	_combine_toggle_btn.pressed.connect(_toggle_combine_mode)
	_panel.add_child(_combine_toggle_btn)

	# Auto-Combine (2026-08-06): one-click sweep that repeatedly fuses any 3
	# same-rarity items it can find (mixed type allowed, same as manual Fuse),
	# auto-picking the strongest passives when a fusion exceeds the cap. Explicit
	# button press, not on-pickup, so nothing gets consumed without the player
	# choosing to sweep.
	var auto_btn := _btn("Auto", Rect2(left_x + col_width - 92, 538, 92, 28))
	UITheme.apply_font(auto_btn, UITheme.FONT_HEADER)
	auto_btn.tooltip_text = "Fuse every possible match of same-rarity items"
	auto_btn.pressed.connect(_auto_combine_sweep)
	_panel.add_child(auto_btn)

	_slot_boxes.clear()
	var slot_w := 92
	var slot_gap := 12
	for i in range(3):
		var box := Panel.new()
		box.position = Vector2(left_x + i * (slot_w + slot_gap), 572)
		box.size = Vector2(slot_w, 88)
		box.add_theme_stylebox_override("panel", UITheme.slot_box())
		_panel.add_child(box)
		_slot_boxes.append(box)

	_combine_status_lbl = _lbl(_panel, "", 13, UITheme.menu_subtitle_color(),
		Vector2(left_x, 662), Vector2(col_width, 24), true)
	_combine_status_lbl.clip_text = true
	_combine_status_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	_fuse_btn = _btn("Fuse", Rect2(left_x, 688, col_width, 32))
	_fuse_btn.pressed.connect(_fuse_selected)
	_fuse_btn.visible = false
	_panel.add_child(_fuse_btn)

	# Middle column: hero list
	_lbl(_panel, "HEROES", 16, col_head,
		Vector2(mid_x, content_y), Vector2(col_width, 24), true)

	_hero_list = ItemList.new()
	_hero_list.position = Vector2(mid_x, content_y + 28)
	_hero_list.size = Vector2(col_width, content_h - 60)
	_hero_list.item_selected.connect(_on_hero_selected)
	UITheme.apply_font(_hero_list, UITheme.FONT_VALUE)
	# Godot's default ItemList box is a flat grey slab that sat badly on both
	# surfaces; a faint inset matching the inventory rows instead.
	var list_box := StyleBoxFlat.new()
	list_box.bg_color = Color(0, 0, 0, 0.08) if UITheme.is_light() else Color(0.10, 0.10, 0.15, 0.8)
	list_box.border_color = Color(UITheme.menu_subtitle_color(), 0.4)
	list_box.set_border_width_all(1)
	list_box.set_corner_radius_all(4)
	list_box.set_content_margin_all(6)
	_hero_list.add_theme_stylebox_override("panel", list_box)
	_hero_list.add_theme_color_override("font_color", UITheme.menu_body_color())
	_panel.add_child(_hero_list)
	# Empty state — a blank grey box read as "broken" in the audit.
	_hero_empty_lbl = _lbl(_panel, "No heroes on your team yet", 16,
		UITheme.menu_subtitle_color(), Vector2(mid_x, content_y + 60),
		Vector2(col_width, 24), true)
	_hero_empty_lbl.visible = false

	# Right column: hero equipment
	_equipped_head = _lbl(_panel, "EQUIPPED", 16, col_head,
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
	var close_btn = _btn("Close", Rect2(830, 686, 140, 34))
	close_btn.pressed.connect(func(): visible = false)
	_panel.add_child(close_btn)

	# Built LAST on purpose: sibling draw order is child order, so building the
	# pick overlay earlier let the hero list / right column paint straight over
	# the top of it.
	_build_pick_overlay()

	# The merge menu (level removal) is its own control, added after everything
	# else so it draws over the whole panel.
	_removal_panel = LevelRemovalPanel.new()
	add_child(_removal_panel)
	_removal_panel.confirmed.connect(_on_removal_confirmed)
	_removal_panel.cancelled.connect(_on_removal_cancelled)

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
		UITheme.apply_font(label, UITheme.FONT_BODY)
		label.add_theme_color_override("font_color", UITheme.menu_subtitle_color())
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
	_hero_empty_lbl.visible = _hero_list.item_count == 0
	# The cap is per-run (crystal tree / relics), so the header reads it live
	# instead of the old hard-coded "(6 max)".
	_equipped_head.text = "EQUIPPED (%d max)" % inventory.hero_item_cap()

func _refresh_hero_equipment() -> void:
	for child in _hero_items_list.get_children():
		child.queue_free()

	if not _selected_hero:
		var label = Label.new()
		label.text = "Select a hero"
		UITheme.apply_font(label, UITheme.FONT_BODY)
		label.add_theme_color_override("font_color", UITheme.menu_subtitle_color())
		_hero_items_list.add_child(label)
		return

	var hero_items = inventory.get_hero_equipment(_selected_hero)
	if hero_items.size() == 0:
		var label = Label.new()
		label.text = "No equipment"
		UITheme.apply_font(label, UITheme.FONT_BODY)
		label.add_theme_color_override("font_color", UITheme.menu_subtitle_color())
		_hero_items_list.add_child(label)
		return

	for item in hero_items:
		_add_equipped_item_button(_hero_items_list, item)

# Item art, or null when a name has no icon mapped (EquipmentManager.ITEM_ICONS).
# Cached because the inventory list rebuilds on every refresh and load() on a
# already-imported texture is cheap but not free.
static var _icon_cache: Dictionary = {}
static func _item_icon(item: EquipmentItem) -> Texture2D:
	if item is ComponentEquipmentItem:
		return GearIcons.icon_for(item)   # composite: emblem + tier frame + notches
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
	UITheme.apply_font(btn, UITheme.body_font(15))
	btn.add_theme_color_override("font_color", item.icon_color)
	btn.clip_text = true
	btn.tooltip_text = item.to_short_string()
	btn.custom_minimum_size = Vector2(280, ICON_PX + 12)

func _add_inventory_item_button(parent: VBoxContainer, item: EquipmentItem) -> void:
	var btn = Button.new()
	btn.text = "%s (%s)" % [item.name, item.get_rarity_name()]
	if item is ComponentEquipmentItem:
		var component := item as ComponentEquipmentItem
		var top := ComponentEquipmentRules.dominant_passive(component.passive_levels)
		if top != "":
			btn.text = "%s %d (%s)" % [GearCatalog.display_name(top),
				int(component.passive_levels[top]), item.get_rarity_name()]
			if component.passive_levels.size() > 1:
				btn.text += "  +%d" % (component.passive_levels.size() - 1)
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

# Delegates to EquipmentInventory's own sweep (2026-08-06) so this button and
# the sidebar's persistent Auto-Combine toggle share one implementation —
# including pausing to ask the player when a fusion's passives exceed the
# result's cap (see EquipmentInventory.auto_combine_pick_needed).
func _auto_combine_sweep() -> void:
	var before := inventory.items.size()
	inventory.run_auto_combine_once()
	_refresh_all()
	if inventory.items.size() < before:
		_combine_status_lbl.text = "Auto-combined items"
	elif _combine_mode:
		_combine_status_lbl.text = "Nothing to auto-combine"

# ── Combine (upgrade) flow ────────────────────────────────────────────────────
func _toggle_combine_mode() -> void:
	_combine_mode = not _combine_mode
	_combine_sel.clear()
	_refresh_inventory()
	_update_combine_ui()

func _toggle_combine_selection(item: EquipmentItem) -> void:
	if item in _combine_sel:
		_combine_sel.erase(item)
	elif _combine_sel.size() < _combine_width():
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
		if i >= _combine_width():
			box.visible = false
			continue
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
			# Exact type-scale steps, clipped to the 88px tile. The old 12/10 bases
			# went through body_font() and came out at 20px, which overflowed the
			# tile and stacked the rarity on top of the name (2026-09-27 audit).
			var nm := Label.new()
			nm.text = item.name
			nm.position = Vector2(2, 50)
			nm.size = Vector2(88, 18)
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nm.clip_text = true
			nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			UITheme.apply_font(nm, UITheme.FONT_BODY)
			nm.add_theme_color_override("font_color", item.icon_color.lightened(0.35))
			nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(nm)
			var rar := Label.new()
			rar.text = item.get_rarity_name()
			rar.position = Vector2(2, 68)
			rar.size = Vector2(88, 14)
			rar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rar.clip_text = true
			UITheme.apply_font(rar, UITheme.FONT_CAPTION)
			rar.add_theme_color_override("font_color", Color(0.78, 0.78, 0.86))
			rar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(rar)
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
	var width := _combine_width()
	if not _combine_mode:
		_combine_status_lbl.text = "Fuse %d same-rarity items → 1 upgraded" % width
		_fuse_btn.visible = false
		return

	var ready_reason := _combine_ready()   # "" = ready, else why not
	if ready_reason == "":
		var r: int = _combine_sel[0].rarity
		var next_name: String = EquipmentItem.new("x", r + 1).get_rarity_name()
		_combine_status_lbl.text = "Ready: %d× %s → %s" % [width, _combine_sel[0].get_rarity_name(), next_name]
		_fuse_btn.text = "Fuse ×%d → %s" % [width, next_name]
		_fuse_btn.visible = true
		_fuse_btn.disabled = false
	else:
		_combine_status_lbl.text = "%d/%d selected — %s" % [_combine_sel.size(), width, ready_reason]
		# Was left at its build-time "Fuse ×3" — wrong for 2-item component merges.
		_fuse_btn.text = "Fuse ×%d" % width
		_fuse_btn.visible = true
		_fuse_btn.disabled = true

# "" when the current selection can be fused, else a short reason.
func _combine_ready() -> String:
	if _combine_sel.size() < _combine_width():
		return "pick same-rarity items"
	var r: int = _combine_sel[0].rarity
	for it in _combine_sel:
		if it.rarity != r:
			return "must all be same rarity"
	if r >= EquipmentItem.Rarity.LEGENDARY:
		return "Legendary is max tier"
	if _component_mode():
		if not (_combine_sel[0] is ComponentEquipmentItem) \
				or not (_combine_sel[1] is ComponentEquipmentItem):
			# Legacy items from before the equipment redesign can sit in a
			# component-mode bag (old saves); say so in player terms.
			return "old-style items can't be fused"
		if not ComponentEquipmentRules.can_combine(
				_combine_sel[0] as ComponentEquipmentItem,
				_combine_sel[1] as ComponentEquipmentItem):
			return "these two can't combine"
	return ""

func _fuse_selected() -> void:
	if _combine_ready() != "":
		return
	var sources: Array[EquipmentItem] = _combine_sel.duplicate()
	if _component_mode():
		var a := sources[0] as ComponentEquipmentItem
		var b := sources[1] as ComponentEquipmentItem
		if ComponentEquipmentRules.levels_to_remove(a, b) > 0:
			_open_level_removal(sources)   # the player picks which levels go
		else:
			_commit_fuse(sources, [])
		return
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
	if _component_mode():
		var merged := (inventory as ComponentEquipmentInventory).combine_components(sources, _rm_removed.duplicate())
		_rm_removed.clear()
		if merged == null:
			return
		_combine_sel.clear()
		_refresh_all()
		_update_combine_ui()
		return
	var cap: int = EquipmentManager.passive_cap(sources[0].rarity + 1)
	var candidates: Array = EquipmentManager.candidate_passives(sources)
	var combined: EquipmentItem = EquipmentManager.combine_items(sources, keep)
	if combined == null:
		return
	# Logged unconditionally now (2026-08-07). The old `if not candidates.is_empty()`
	# guard silently dropped every Common→Uncommon fusion, because three Commons
	# offer no passives at all — see EquipmentInventory.log_fusion.
	inventory.log_fusion(sources, cap, candidates, keep)
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

	_pick_title = _lbl(_pick_panel, "CHOOSE PASSIVES TO KEEP", 20, Color(0.95, 0.82, 0.5),
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
	if _pick_is_auto and inventory:
		# Cancelled without choosing — leave the triple untouched in the bag;
		# Auto-Combine will offer it again on the next pickup.
		inventory.cancel_auto_pick()
	_pick_is_auto = false
	_pick_sources.clear()

# Entry point for Auto-Combine (2026-08-06): opens the panel (if not already
# open) straight to the passive-pick overlay for a paused fusion, instead of
# requiring the player to enter Combine Mode manually.
func show_auto_pick(sources: Array[EquipmentItem], candidates: Array, cap: int) -> void:
	visible = true
	_center_panel()
	_pick_is_auto = true
	_open_passive_pick(sources, candidates, cap)

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
	_pick_title.text = "CHOOSE PASSIVES TO KEEP"
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
		UITheme.apply_font(b, UITheme.body_font(13))
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
	var was_auto := _pick_is_auto
	_pick_is_auto = false   # confirmed, not cancelled — _close_pick shouldn't also cancel
	_close_pick()
	if was_auto and inventory:
		inventory.resolve_auto_pick(sources, keep)
		_refresh_all()
	else:
		_commit_fuse(sources, keep)

# ── Component merge menu: remove levels until the pool fits ──────────────────
# The menu itself is LevelRemovalPanel (scripts/ui/level_removal_panel.gd); this
# panel only feeds it a pool and performs the merge it reports back.
# Public entry for the bag's drag-to-combine (main_game._drop_combine).
#
# close_when_done: the caller opened this panel ONLY to host the removal menu
# (a drag-to-combine in the bag), so put the player back where they were as soon
# as the merge is confirmed or cancelled instead of leaving the Equipment menu
# open. Left false when the player was already in the panel.
var _close_after_removal := false

func open_level_removal(sources: Array[EquipmentItem], close_when_done: bool = false) -> void:
	_close_after_removal = close_when_done
	_open_level_removal(sources)

func _finish_removal_session() -> void:
	if _close_after_removal:
		_close_after_removal = false
		visible = false

func _open_level_removal(sources: Array[EquipmentItem]) -> void:
	var a := sources[0] as ComponentEquipmentItem
	var b := sources[1] as ComponentEquipmentItem
	_removal_sources = sources
	_removal_panel.open(ComponentEquipmentRules.pooled_levels(a, b),
		ComponentEquipmentRules.levels_to_remove(a, b))

func removal_menu_open() -> bool:
	return _removal_panel != null and _removal_panel.is_open()

# Escape / hiding this panel while the menu is up: same as pressing Cancel.
func cancel_removal_menu() -> void:
	if removal_menu_open():
		_removal_panel.cancel()

func _on_removal_confirmed(removals: Dictionary) -> void:
	var sources := _removal_sources.duplicate()
	_removal_sources.clear()
	_rm_removed = removals.duplicate()
	_commit_fuse(sources, [])
	_finish_removal_session()

func _on_removal_cancelled() -> void:
	# Nothing was merged and nothing changes: both items stay in the bag.
	_removal_sources.clear()
	_rm_removed.clear()
	_finish_removal_session()

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
