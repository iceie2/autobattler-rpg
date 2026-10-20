extends Control
class_name MerchantWorkshop

signal purchase_requested(kind: String, target: Variant, modifier: String)
signal closed()

# 2026-10-02 (owner): bag items have no box around them; the drop target is a
# small slot only a little bigger than an item, not the whole station; the slot
# lights up while an item is being dragged, and the item pops into it on drop.
const ICON_PX := 72.0
const SLOT_PX := 96.0

class ItemTile extends Button:
	var item: EquipmentItem
	func _get_drag_data(_at_position: Vector2) -> Variant:
		if item == null: return null
		var preview := Control.new()
		var icon := TextureRect.new()
		icon.texture = GearIcons.icon_for(item)
		icon.size = Vector2(ICON_PX, ICON_PX)
		icon.position = -icon.size * 0.5      # centred on the cursor
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.modulate = Color(1, 1, 1, 0.92)
		preview.add_child(icon)
		set_drag_preview(preview)
		return item

# The small drop target. Draws itself: a frame that wakes up while anything is
# being dragged, a ghost of the dragged item when hovered, then the item itself.
class Slot extends Control:
	var kind := "reforge"
	var item: EquipmentItem
	var pop := 1.0:
		set(v):
			pop = v
			queue_redraw()
	signal item_dropped(kind: String, item: EquipmentItem)
	var _dragging := false
	var _hover := false
	var _t := 0.0
	var _box := StyleBoxFlat.new()

	func _init() -> void:
		_box.set_corner_radius_all(10)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is EquipmentItem
	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		item_dropped.emit(kind, data)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_BEGIN:
			_dragging = true
		elif what == NOTIFICATION_DRAG_END:
			_dragging = false
			_hover = false
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		var h := _dragging and get_global_rect().has_point(get_global_mouse_position())
		if h != _hover:
			_hover = h
		if _dragging or _hover:
			queue_redraw()   # the pulse

	func place(new_item: EquipmentItem, animate: bool = true) -> void:
		var changed := new_item != item
		item = new_item
		queue_redraw()
		if changed and animate and new_item != null and is_inside_tree():
			create_tween().tween_property(self, "pop", 1.0, 0.30).from(1.4) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var pulse := 0.5 + 0.5 * sin(_t * 7.0)
		if _hover:
			_box.bg_color = Color(0.12, 0.30, 0.28, 0.80)
			_box.border_color = Color(0.75, 1.0, 0.95)
			_box.set_border_width_all(4)
		elif _dragging:
			_box.bg_color = Color(0.05, 0.12, 0.11, 0.72)
			_box.border_color = Color(0.54, 0.82, 0.80, 0.55 + 0.45 * pulse)
			_box.set_border_width_all(3)
		else:
			_box.bg_color = Color(0.03, 0.03, 0.025, 0.58)
			_box.border_color = Color(0.72, 0.60, 0.38, 0.75 if item != null else 0.5)
			_box.set_border_width_all(2)
		draw_style_box(_box, Rect2(Vector2.ZERO, size))
		var c := size * 0.5
		if item != null:
			var tex := GearIcons.icon_for(item)
			draw_set_transform(c, 0.0, Vector2(pop, pop))
			draw_texture_rect(tex, Rect2(-ICON_PX * 0.5, -ICON_PX * 0.5, ICON_PX, ICON_PX), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif _hover:
			var dragged = get_viewport().gui_get_drag_data()
			if dragged is EquipmentItem:
				draw_texture_rect(GearIcons.icon_for(dragged),
					Rect2(c.x - ICON_PX * 0.5, c.y - ICON_PX * 0.5, ICON_PX, ICON_PX), false,
					Color(1, 1, 1, 0.55))
		else:
			# Empty: a plus, so the slot reads as "put something here".
			var col := Color(0.95, 0.9, 0.78, 0.55)
			draw_line(c + Vector2(-14, 0), c + Vector2(14, 0), col, 3.0)
			draw_line(c + Vector2(0, -14), c + Vector2(0, 14), col, 3.0)

# The big backdrop zone: click it to pick which service you are using. It no
# longer accepts drops — the small slot does.
class Station extends Button:
	var kind := "reforge"

var provider: Callable
var _kind := "reforge"
var _item: EquipmentItem
var _context: Dictionary
var _tray: HFlowContainer
var _details: RichTextLabel
var _modifier: OptionButton
var _choices: Array
var _confirm: Button
var _result: Label
var _stations: Dictionary = {}
var _slots: Dictionary = {}
var _hints: Dictionary = {}

func _ready() -> void:
	position = Vector2(395, 122)
	size = Vector2(1490, 925)
	var art := TextureRect.new()
	art.texture = preload("res://assets/using/merchant_workshop/stations.png")
	art.position = Vector2(0, 0)
	art.size = Vector2(1490, 590)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	var tint := ColorRect.new()
	tint.position = art.position
	tint.size = art.size
	tint.color = Color(0, 0, 0, 0.25)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)
	for kind in ["reforge", "enchant"]:
		var station := Station.new()
		station.kind = kind
		station.position = Vector2(20 if kind == "reforge" else 755, 15)
		station.size = Vector2(715, 355)
		station.add_theme_stylebox_override("normal", _box(Color(0.06, 0.06, 0.05, 0.12)))
		station.add_theme_stylebox_override("hover", _box(Color(0.2, 0.28, 0.25, 0.3)))
		station.add_theme_stylebox_override("focus", _box(Color(0.15, 0.4, 0.4, 0.35)))
		station.pressed.connect(func(): _kind = kind; _update())
		add_child(station)
		_stations[kind] = station
		# Title above the slot, hint below it (labels ignore the mouse so the
		# station underneath still gets the click).
		var title := Label.new()
		title.text = "REFORGE  •  ANVIL" if kind == "reforge" else "ENCHANT  •  ARCANE BENCH"
		title.position = station.position + Vector2(0, 38)
		title.size = Vector2(station.size.x, 44)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.apply_font(title, UITheme.FONT_DISPLAY)
		title.add_theme_color_override("font_color", Color("f3e5c9"))
		title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		title.add_theme_constant_override("outline_size", 8)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(title)
		var slot := Slot.new()
		slot.kind = kind
		slot.size = Vector2(SLOT_PX, SLOT_PX)
		slot.position = station.position + Vector2((station.size.x - SLOT_PX) * 0.5, 150)
		slot.pivot_offset = slot.size * 0.5
		slot.item_dropped.connect(func(k: String, item: EquipmentItem): _kind = k; _item = item; _update())
		add_child(slot)
		_slots[kind] = slot
		var hint := Label.new()
		hint.position = slot.position + Vector2(-150, SLOT_PX + 14)
		hint.size = Vector2(SLOT_PX + 300, 34)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.apply_font(hint, UITheme.FONT_VALUE)
		hint.add_theme_color_override("font_color", Color("f3e5c9"))
		hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		hint.add_theme_constant_override("outline_size", 6)
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hint)
		_hints[kind] = hint
	var readout := Panel.new()
	readout.position = Vector2(15, 385)
	readout.size = Vector2(1460, 195)
	readout.add_theme_stylebox_override("panel", _box(Color(0.06, 0.07, 0.065, 0.91)))
	add_child(readout)
	_details = RichTextLabel.new()
	_details.position = Vector2(20, 14)
	_details.size = Vector2(1010, 166)
	UITheme.apply_rich_font(_details, 21)
	readout.add_child(_details)
	_modifier = OptionButton.new()
	_modifier.position = Vector2(1045, 28)
	_modifier.size = Vector2(390, 55)
	UITheme.apply_font(_modifier, 19)
	_modifier.item_selected.connect(func(_i): _update_details())
	readout.add_child(_modifier)
	_confirm = Button.new()
	_confirm.position = Vector2(1045, 106)
	_confirm.size = Vector2(390, 60)
	UITheme.apply_font(_confirm, 21)
	_confirm.pressed.connect(_purchase)
	readout.add_child(_confirm)
	var tray_panel := Panel.new()
	tray_panel.position = Vector2(15, 595)
	tray_panel.size = Vector2(1460, 224)
	tray_panel.add_theme_stylebox_override("panel", _box(Color(0.08, 0.065, 0.045, 0.94)))
	add_child(tray_panel)
	var tray_title := Label.new()
	tray_title.text = "YOUR BAG  •  Drag an item to a station, or select it here"
	tray_title.position = Vector2(18, 9)
	tray_title.size = Vector2(1400, 35)
	UITheme.apply_font(tray_title, 21)
	tray_panel.add_child(tray_title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(18, 50)
	scroll.size = Vector2(1424, 158)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tray_panel.add_child(scroll)
	_tray = HFlowContainer.new()
	_tray.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tray.add_theme_constant_override("h_separation", 8)
	_tray.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_tray)
	_result = Label.new()
	_result.position = Vector2(20, 833)
	_result.size = Vector2(1090, 62)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_font(_result, 20)
	add_child(_result)
	var back := Button.new()
	back.text = "Back to Stock"
	back.position = Vector2(1160, 839)
	back.size = Vector2(310, 57)
	UITheme.apply_font(back, 22)
	back.pressed.connect(func(): hide(); closed.emit())
	add_child(back)
	hide()

func open() -> void:
	_result.text = ""
	_item = null
	reload()
	show()
	_stations[_kind].grab_focus()

func reload() -> void:
	_context = provider.call() if provider.is_valid() else {}
	if _item != null and not _context.get("items", []).has(_item): _item = null
	for child in _tray.get_children():
		_tray.remove_child(child)
		child.queue_free()
	for item in _context.get("items", []):
		_tray.add_child(_make_tile(item))
	_update()

# A bag item is just its icon: no box. Rarity is already in the icon's own tier
# frame. Hover brightens it; an item that is currently sitting in a slot is
# dimmed in the bag.
func _make_tile(item: EquipmentItem) -> ItemTile:
	var tile := ItemTile.new()
	tile.item = item
	tile.custom_minimum_size = Vector2(80, 80)
	tile.icon = GearIcons.icon_for(item)
	tile.expand_icon = true
	tile.flat = true
	tile.focus_mode = Control.FOCUS_NONE
	tile.tooltip_text = item.to_short_string()
	var none := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		tile.add_theme_stylebox_override(state, none)
	tile.modulate = Color(1, 1, 1, 0.4) if item == _item else Color.WHITE
	tile.mouse_entered.connect(func():
		if item != _item: tile.modulate = Color(1.3, 1.3, 1.3))
	tile.mouse_exited.connect(func():
		tile.modulate = Color(1, 1, 1, 0.4) if item == _item else Color.WHITE)
	tile.pressed.connect(func(): _item = item; _update())
	return tile

func _update() -> void:
	for key in _stations:
		var active: bool = key == _kind
		_stations[key].modulate = Color.WHITE if active else Color(0.75, 0.75, 0.75)
		_slots[key].modulate = Color.WHITE if active else Color(0.85, 0.85, 0.85)
		# The item sits in the slot of the service you are using.
		(_slots[key] as Slot).place(_item if active else null)
		_hints[key].text = _item.name if (active and _item != null) else "DROP ITEM HERE"
	for tile in _tray.get_children():
		if tile is ItemTile:
			(tile as ItemTile).modulate = Color(1, 1, 1, 0.4) if (tile as ItemTile).item == _item else Color.WHITE
	_choices = []
	_modifier.clear()
	_modifier.visible = _kind == "enchant"
	if _kind == "enchant" and _item != null:
		_choices = MerchantServices.modifier_choices(_item)
		for choice in _choices: _modifier.add_item(choice["label"])
	_update_details()

func _update_details() -> void:
	var price := MerchantServices.cost(_kind, int(_context.get("round", 1)), _item.rarity if _item != null else 0)
	var rule := "Rerolls stats; preserves identity, rarity and passives. The result may be weaker." if _kind == "reforge" else "Replaces one passive level with a different passive; preserves stats and rarity."
	if _kind == "enchant" and _item != null and _choices.is_empty(): rule += " This item has no enchantable passive slot."
	var name := _item.to_short_string() if _item != null else "No item selected. Drop an item onto a station."
	_details.text = "Gold: %dg  •  Cost: %dg\n%s\n%s" % [int(_context.get("gold", 0)), price, name, rule]
	_confirm.text = "Confirm %s  •  %dg" % [_kind.capitalize(), price]
	_confirm.disabled = _item == null or int(_context.get("gold", 0)) < price or (_kind == "enchant" and _choices.is_empty())

func _purchase() -> void:
	_confirm.disabled = true
	var modifier := str(_choices[_modifier.selected]["key"]) if _kind == "enchant" and _modifier.selected >= 0 and _modifier.selected < _choices.size() else ""
	purchase_requested.emit(_kind, _item, modifier)

func report(message: String) -> void:
	_result.text = message
	reload()

func _box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color("b79860")
	box.set_border_width_all(2)
	box.set_corner_radius_all(7)
	return box

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		closed.emit()
		get_viewport().set_input_as_handled()
