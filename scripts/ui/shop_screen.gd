extends CanvasLayer
class_name ShopScreen
# Traveling Merchant: responsive two-row storefront; all rewards remain pre-rolled.

signal buy_hero(idx: int, cls: int, element: int, rolls: Dictionary)
signal buy_stat(idx: int, perk: Dictionary)
signal buy_item(idx: int, item: EquipmentItem)
signal buy_relic(idx: int, relic: Dictionary)
signal reroll_requested()
signal closed()
signal service_requested(kind: String, target: Variant, modifier: String)
var services: MerchantWorkshop
var _service_overlay: Control
var _services_btn: Button

const BG_PATH := "res://assets/using/gold_shop.png"
const BG_EMPTY_PATH := "res://assets/using/traveling_merchant_v2/room.png"
const KEEPER_PATH := "res://assets/using/traveling_merchant_v2/merchant.png"
const PANEL_W := 1920.0
const PANEL_H := 1080.0
const CARD_W := 310.0
const CARD_H := 354.0
const BRASS := Color("8e7145")
const CREAM := Color("f3e5c9")
const MUTED := Color("bcb4a4")
const COIN_PATH := "res://assets/UI/generated/coin_label.png"

class ShelfBackdrop extends Control:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1348, 835), Color(0.075, 0.045, 0.025, 0.86))
		for top in [0.0, 414.0]:
			for n in range(9):
				var y: float = top + 30.0 + n * 40.0
				draw_line(Vector2(12, y), Vector2(1336, y + (n % 3 - 1) * 5), Color(0.48, 0.34, 0.20, 0.08), 2.0)
			draw_rect(Rect2(-4, top + 380, 1356, 32), Color(0, 0, 0, 0.65))
			draw_rect(Rect2(-4, top + 380, 1356, 14), Color("674727"))
			draw_rect(Rect2(-4, top + 394, 1356, 14), Color("352217"))
			draw_line(Vector2(-4, top + 380), Vector2(1352, top + 380), Color("b28c55"), 3.0)
var _groups: Dictionary = {}
var _tip_body: RichTextLabel
var _tip_scroll: ScrollContainer
var _reaction: Tween
var _tip_revision := 0
var _keyboard_details := false

var _panel:      Control
var _title_lbl:  Label
var _gold_lbl:   Label
var _bark_lbl:   Label
var _reroll_btn: Button
var _leave_btn:  Button
var _card_row:   Control
var _keeper:     TextureRect
var _tooltip:    Panel

var _stock:      Array = []
var _card_nodes: Array = []
var _round:      int = 1
var _gold:       int = 0
var _reroll_n:   int = 0     # how many times rerolled this visit (escalating cost)

# Element display colors (matches hero_shop's palette).
const ELEM_COLORS := {
	UnitBase.Element.FIRE:      Color(0.95, 0.45, 0.25),
	UnitBase.Element.WATER:     Color(0.35, 0.62, 0.95),
	UnitBase.Element.EARTH:     Color(0.65, 0.52, 0.30),
	UnitBase.Element.AIR:       Color(0.70, 0.90, 0.95),
	UnitBase.Element.LIGHTNING: Color(0.95, 0.88, 0.35),
	UnitBase.Element.NORMAL:    Color(0.80, 0.80, 0.85),
}

func _ready() -> void:
	_build_ui()
	visible = false

# ── Public entry ──────────────────────────────────────────────────────────────
func open(round: int, gold: int, stock: Array) -> void:
	_round = round
	_service_overlay.hide()
	services.hide()
	if _keeper: _keeper.position.x = 36
	_gold = gold
	_reroll_n = 0
	_stock = stock
	_title_lbl.text = "TRAVELING MERCHANT    /    ROUND %d" % round
	_refresh_gold(gold)
	_rebuild_cards()
	_set_bark("Step in, step in — finest wares this side of the wastes!")
	visible = true
	_animate_keeper_intro()

# Called by main_game after it charges the reroll and rolls fresh stock.
func set_stock(gold: int, stock: Array) -> void:
	_gold = gold
	_stock = stock
	_reroll_n += 1
	_refresh_gold(gold)
	_rebuild_cards()
	_set_bark("Fresh stock, fresh prices. Go on, look again.")

# The gold the player has changed (after a buy) — refresh affordability.
func refresh(gold: int) -> void:
	_gold = gold
	_refresh_gold(gold)
	for c in _card_nodes:
		if is_instance_valid(c):
			_update_card_affordability(c)

func current_reroll_cost() -> int:
	return ShopGenerator.reroll_cost(_reroll_n)

# ── UI shell ──────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color("100e0c")
	add_child(overlay)
	_panel = Control.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.theme = Theme.new()
	_panel.theme.default_font = preload("res://assets/Fonts/Merchant-NotoSans-Regular.ttf")
	overlay.add_child(_panel)
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture = load(BG_EMPTY_PATH if ResourceLoader.exists(BG_EMPTY_PATH) else BG_PATH)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(bg)
	_start_glow_pulse(bg)
	_add_lantern_glow(Vector2(282, 222), Vector2(135, 190), 1.7)
	_add_lantern_glow(Vector2(1814, 198), Vector2(170, 235), 2.3)
	if ResourceLoader.exists(KEEPER_PATH):
		_keeper = TextureRect.new()
		_keeper.texture = load(KEEPER_PATH)
		_keeper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_keeper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_keeper.position = Vector2(36, 240)
		_keeper.size = Vector2(490, 570)
		_keeper.pivot_offset = Vector2(245, 560)
		_keeper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(_keeper)
		_start_keeper_idle()
	var header := Panel.new()
	header.position = Vector2(32, 24)
	header.size = Vector2(1856, 86)
	header.add_theme_stylebox_override("panel", _flat(Color("191510"), BRASS, 1, 8))
	_panel.add_child(header)
	_title_lbl = _mk_label("TRAVELING MERCHANT", 32, CREAM, Vector2(58, 40), Vector2(1300, 52), false)
	_gold_lbl = _mk_label("", 30, Color("ffce70"), Vector2(1490, 40), Vector2(360, 52), false)
	_gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var dialogue := Panel.new()
	dialogue.position = Vector2(40, 820)
	dialogue.size = Vector2(478, 116)
	dialogue.add_theme_stylebox_override("panel", _flat(Color("1c1813"), BRASS, 1, 8))
	_panel.add_child(dialogue)
	_bark_lbl = _clabel(dialogue, "", 20, CREAM, Vector2(22, 18), Vector2(434, 84), true, true)
	_mk_label("CURIOS & COMPANY", 22, Color("d8b879"), Vector2(50, 778), Vector2(460, 40), true)
	var shelves := ShelfBackdrop.new()
	shelves.position = Vector2(545, 120)
	shelves.size = Vector2(1348, 812)
	shelves.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(shelves)
	_card_row = VBoxContainer.new()
	_card_row.position = Vector2(558, 128)
	_card_row.size = Vector2(1322, 808)
	_card_row.add_theme_constant_override("separation", 22)
	_panel.add_child(_card_row)
	for row_kinds in [["hero", "item"], ["stat", "relic"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_card_row.add_child(row)
		for kind in row_kinds:
			var section := VBoxContainer.new()
			section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			section.add_theme_constant_override("separation", 10)
			row.add_child(section)
			var heading := Label.new()
			heading.text = {"hero": "HEROES", "item": "EQUIPMENT", "stat": "STAT UPGRADES", "relic": "RELIC"}[kind]
			UITheme.apply_font(heading, 22)
			heading.add_theme_color_override("font_color", Color("d8b879"))
			section.add_child(heading)
			var offers := HBoxContainer.new()
			offers.add_theme_constant_override("separation", 16)
			offers.size_flags_vertical = Control.SIZE_EXPAND_FILL
			section.add_child(offers)
			_groups[kind] = offers
	var footer := Panel.new()
	footer.position = Vector2(32, 966)
	footer.size = Vector2(1856, 86)
	footer.add_theme_stylebox_override("panel", _flat(Color("191510"), BRASS, 1, 8))
	_panel.add_child(footer)
	var service_button := _mk_button("Merchant Services", Rect2(58, 982, 330, 54))
	_services_btn = service_button
	service_button.pressed.connect(func():
		_hide_tooltip()
		if _keeper: create_tween().tween_property(_keeper, "position:x", -85.0, 0.3)
		_service_overlay.show()
		services.open())
	_panel.add_child(service_button)
	_mk_label("Reforge · Enchant", 20, MUTED, Vector2(410, 991), Vector2(680, 32), false)
	_reroll_btn = _mk_button("", Rect2(1110, 982, 430, 54))
	_reroll_btn.pressed.connect(func():
		_hide_tooltip()
		reroll_requested.emit())
	_panel.add_child(_reroll_btn)
	_leave_btn = _mk_button("Leave Shop  ›", Rect2(1560, 982, 300, 54))
	_leave_btn.pressed.connect(_on_leave)
	_panel.add_child(_leave_btn)
	for action in [_services_btn, _reroll_btn, _leave_btn]:
		action.mouse_entered.connect(_hide_tooltip)
		action.focus_entered.connect(_hide_tooltip)
	_tooltip = Panel.new()
	_tooltip.position = Vector2(40, 140)
	_tooltip.size = Vector2(478, 598)
	_tooltip.add_theme_stylebox_override("panel", _flat(Color("171b1a"), Color("c4a66a"), 2, 10))
	_tooltip.visible = false
	_tooltip.z_index = 10
	_panel.add_child(_tooltip)
	_tip_scroll = ScrollContainer.new()
	_tip_scroll.position = Vector2(22, 22)
	_tip_scroll.size = Vector2(434, 554)
	_tip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tooltip.add_child(_tip_scroll)
	_tip_body = RichTextLabel.new()
	_tip_body.bbcode_enabled = false
	_tip_body.fit_content = true
	_tip_body.scroll_active = false
	_tip_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_rich_font(_tip_body, 20)
	_tip_body.add_theme_color_override("default_color", CREAM)
	_tip_scroll.add_child(_tip_body)
	_service_overlay = Control.new()
	_service_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_service_overlay.z_index = 20
	_panel.add_child(_service_overlay)
	var shade := ColorRect.new()
	shade.position = Vector2(375, 110)
	shade.size = Vector2(1535, 950)
	shade.color = Color(0, 0, 0, 0.76)
	_service_overlay.add_child(shade)
	services = MerchantWorkshop.new()
	_service_overlay.add_child(services)
	services.purchase_requested.connect(func(kind, target, modifier): service_requested.emit(kind, target, modifier))
	services.closed.connect(func():
		_service_overlay.hide()
		if _keeper: create_tween().tween_property(_keeper, "position:x", 36.0, 0.3)
		service_button.grab_focus())
	_service_overlay.hide()
	get_viewport().size_changed.connect(_center_panel)
	_center_panel()

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size
	var ratio := minf(vp.x / PANEL_W, vp.y / PANEL_H)
	_panel.scale = Vector2.ONE * ratio
	_panel.position = (vp - Vector2(PANEL_W, PANEL_H) * ratio) * 0.5

func _rebuild_cards() -> void:
	_hide_tooltip()
	for group in _groups.values():
		for c in group.get_children():
			group.remove_child(c)
			c.queue_free()
	_card_nodes.clear()
	for i in range(_stock.size()):
		var card := _build_card(_stock[i], i, Vector2.ZERO)
		_groups[_stock[i]["kind"]].add_child(card)
		_card_nodes.append(card)
		_update_card_affordability(card)
	# Follow the visual reading order, independently of generator slot indices.
	var focus_order: Array[Control] = []
	for index in [0, 1, 4, 5, 2, 3, 6]:
		if index < _card_nodes.size(): focus_order.append(_card_nodes[index])
	focus_order.append_array([_services_btn, _reroll_btn, _leave_btn])
	for i in range(focus_order.size()):
		focus_order[i].focus_next = focus_order[(i + 1) % focus_order.size()].get_path()
		focus_order[i].focus_previous = focus_order[(i - 1 + focus_order.size()) % focus_order.size()].get_path()

func _build_card(slot: Dictionary, idx: int, _pos: Vector2) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, CARD_H)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.set_meta("slot_idx", idx)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.focus_mode = Control.FOCUS_ALL
	card.add_theme_stylebox_override("normal", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 8))
	card.add_theme_stylebox_override("hover", _flat(Color(0.7, 0.5, 0.25, 0.10), Color(0.8, 0.65, 0.4, 0.32), 1, 8))
	card.add_theme_stylebox_override("pressed", _flat(Color(0, 0, 0, 0.20), Color.TRANSPARENT, 0, 8))
	card.add_theme_stylebox_override("focus", _flat(Color.TRANSPARENT, Color("8ad2cc"), 2, 8))
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 14)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(inset)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(stack)
	var well := Panel.new()
	well.custom_minimum_size.y = 164
	well.add_theme_stylebox_override("panel", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 5))
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(well)
	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_top = 24
	icon.offset_bottom = -4
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _slot_icon(slot)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(icon)
	var grade := Label.new()
	grade.text = slot["item"].get_rarity_name().to_upper() if slot["kind"] == "item" else "GRADE " + _slot_grade_letter(slot)
	UITheme.apply_font(grade, 17)
	grade.add_theme_color_override("font_color", _slot_grade_color(slot).lightened(0.2))
	grade.position = Vector2(0, 0)
	grade.size = Vector2(190, 25)
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(grade)
	var price: int = slot.get("price", 0)
	var original: int = slot.get("original_price", price)
	if original > price:
		var seal := Label.new()
		seal.text = "-%d%%" % roundi(100.0 * (original - price) / original)
		seal.position = Vector2(-76, 5)
		seal.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		seal.size = Vector2(66, 38)
		seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		seal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		seal.add_theme_stylebox_override("normal", _flat(Color("7b392d"), Color("d7ab68"), 2, 20))
		UITheme.apply_font(seal, 18)
		seal.add_theme_color_override("font_color", CREAM)
		seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		well.add_child(seal)
	var claimed := Label.new()
	claimed.text = "SOLD"
	claimed.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	claimed.position = Vector2(-74, -18)
	claimed.size = Vector2(148, 36)
	claimed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	claimed.add_theme_stylebox_override("normal", _flat(Color("382d25"), Color("c39c6b"), 2, 4))
	UITheme.apply_font(claimed, 23)
	claimed.add_theme_color_override("font_color", CREAM)
	claimed.rotation = -0.08
	claimed.visible = false
	claimed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(claimed)
	card.set_meta("claimed", claimed)
	var title := Label.new()
	title.text = _slot_name(slot)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_font(title, 22)
	title.add_theme_color_override("font_color", CREAM)
	title.custom_minimum_size.y = 44
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
	stack.add_child(title)
	var benefit := Label.new()
	benefit.text = _card_benefit(slot)
	benefit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	benefit.max_lines_visible = 1
	benefit.custom_minimum_size.y = 26
	benefit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	benefit.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	benefit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.apply_font(benefit, 20)
	benefit.add_theme_color_override("font_color", MUTED)
	stack.add_child(benefit)
	var sale := Label.new()
	sale.text = "WAS %dg  ·  SAVE %d%%" % [original, roundi(100.0 * (original - price) / original)] if original > price else " "
	UITheme.apply_font(sale, 16)
	sale.add_theme_color_override("font_color", Color("8bd3b2"))
	sale.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(sale)
	var plate := Panel.new()
	plate.custom_minimum_size.y = 42
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(plate)
	var coin := TextureRect.new()
	# Ignore the source texture's minimum size before assigning it or sizing.
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.texture = load(COIN_PATH)
	coin.position = Vector2(13, 11)
	coin.size = Vector2(21, 21)
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(coin)
	var purchase := Label.new()
	purchase.custom_minimum_size.y = 42
	purchase.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	purchase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	purchase.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.apply_font(purchase, 22)
	purchase.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(purchase)
	card.set_meta("purchase", purchase)
	card.set_meta("plate", plate)
	card.set_meta("coin", coin)
	for child in stack.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.mouse_entered.connect(_on_card_hover.bind(idx, card))
	card.mouse_exited.connect(_on_card_unhover)
	card.focus_entered.connect(func():
		_keyboard_details = true
		_show_tooltip(_stock[idx], card))
	card.focus_exited.connect(_hide_tooltip)
	card.pressed.connect(_on_card_pressed.bind(idx))
	card.modulate.a = 0.7
	card.create_tween().tween_property(card, "modulate:a", 1.0, 0.16)
	return card

func _card_benefit(slot: Dictionary) -> String:
	match slot["kind"]:
		"hero": return "Recruit this %s hero" % _elem_name(slot["element"]).to_lower()
		"stat": return _slot_summary(slot)
		"relic": return str(slot["relic"].get("desc", ""))
		"item":
			var bits: Array[String] = []
			for row in EquipmentItem._STAT_DISPLAY + [["magic_resist", "MARM", "int"], ["cdr", "Haste", "int"], ["ten", "Tenacity", "int"]]:
				var val := float(slot["item"].stat_bonus.get(row[0], 0))
				if val > 0: bits.append(EquipmentItem.format_bonus(row, val))
			return " · ".join(bits)
	return ""

func _update_card_affordability(card: Button) -> void:
	var idx: int = card.get_meta("slot_idx", -1)
	if idx < 0 or idx >= _stock.size(): return
	var slot: Dictionary = _stock[idx]
	var sold: bool = slot.get("sold", false)
	var price: int = slot.get("price", 0)
	# Keep every card focusable, including sold/unaffordable rewards, for details.
	var label: Label = card.get_meta("purchase")
	label.text = "SOLD" if sold else ("Buy  ·  %dg" % price if _gold >= price else "Need %dg  ·  %dg" % [price - _gold, price])
	label.add_theme_color_override("font_color", Color("c0b6a4") if sold else (Color("ffda8a") if _gold >= price else Color("e6a393")))
	var plate: Panel = card.get_meta("plate")
	plate.add_theme_stylebox_override("panel", _flat(Color("171511") if sold or _gold < price else Color("49391f"), BRASS, 1, 5))
	var coin: TextureRect = card.get_meta("coin")
	coin.visible = not sold
	coin.modulate.a = 0.45 if _gold < price else 1.0
	var claimed: Label = card.get_meta("claimed")
	claimed.visible = sold
	card.add_theme_stylebox_override("normal", _flat(Color(0, 0, 0, 0.12) if sold else Color.TRANSPARENT, Color.TRANSPARENT, 0, 8))

# ── Buy flow ──────────────────────────────────────────────────────────────────
func _on_card_pressed(idx: int) -> void:
	if idx < 0 or idx >= _stock.size():
		return
	var slot: Dictionary = _stock[idx]
	if slot.get("sold", false):
		return
	if _gold < int(slot.get("price", 0)):
		_set_bark("Coin first, friend. No coin, no wares.")
		return
	# main_game validates + charges + fulfils via the matching signal, then calls
	# mark_sold(idx) if it succeeded (e.g. hero not blocked by a full roster).
	match slot.get("kind", ""):
		"hero":  buy_hero.emit(idx, slot["class"], slot["element"], slot["rolls"])
		"stat":  buy_stat.emit(idx, slot["perk"])
		"item":  buy_item.emit(idx, slot["item"])
		"relic": buy_relic.emit(idx, slot["relic"])

# main_game calls this after a successful purchase.
func purchase_rejected(message: String) -> void:
	_set_bark(message)

func mark_sold(idx: int) -> void:
	if idx < 0 or idx >= _stock.size():
		return
	_stock[idx]["sold"] = true
	if idx < _card_nodes.size() and is_instance_valid(_card_nodes[idx]):
		_update_card_affordability(_card_nodes[idx])
	_hide_tooltip()
	_set_bark(_buy_bark(_stock[idx].get("kind", "")))
	_keeper_react()

# ── Tooltip (hover preview: exactly what you'd get) ───────────────────────────
func _on_card_hover(idx: int, card: Button) -> void:
	if _keyboard_details and get_viewport().gui_get_focus_owner() != card: return
	if idx < 0 or idx >= _stock.size():
		return
	_show_tooltip(_stock[idx], card)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.relative.length_squared() > 0:
		_keyboard_details = false

func _on_card_unhover() -> void:
	# Details stay available for scrolling until another offer is inspected or
	# a footer action is entered. This avoids a pointer-travel race at 1920px.
	pass

func _hide_tooltip() -> void:
	_tip_revision += 1
	if _tooltip: _tooltip.visible = false

func _show_tooltip(slot: Dictionary, card: Button) -> void:
	_tip_revision += 1
	var revision := _tip_revision
	var lines := _tooltip_lines(slot)
	var text := str(lines[0]) + "\n\n"
	for i in range(1, lines.size()):
		text += str(lines[i][0]) + "\n"
	text += "\n" + ("Sold — this offer has been claimed." if slot.get("sold", false) else "Price: %dg" % slot.get("price", 0))
	_tip_body.text = text
	_tip_scroll.scroll_vertical = 0
	_tooltip.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	if revision != _tip_revision or not is_instance_valid(card): return
	var body_height := minf(490.0, _tip_body.get_content_height())
	_tooltip.size = Vector2(478, body_height + 44)
	_tip_scroll.size = Vector2(434, body_height)
	var card_pos := _panel.get_global_transform().affine_inverse() * card.global_position
	_tooltip.position = Vector2(40, clampf(card_pos.y, 128, 770 - _tooltip.size.y))

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not _tooltip.visible: return
	if event.is_action_pressed("ui_page_down"):
		_tip_scroll.scroll_vertical += 180
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_up"):
		_tip_scroll.scroll_vertical -= 180
		get_viewport().set_input_as_handled()

# Returns [title_string, [line, color], [line, color], ...]
func _tooltip_lines(slot: Dictionary) -> Array:
	var out: Array = []
	match slot.get("kind", ""):
		"hero":
			var cls: int = slot["class"]
			var elem: int = slot["element"]
			var rolls: Dictionary = slot["rolls"]
			out.append("%s %s  (%s)" % [_elem_name(elem), _class_name(cls), rolls.get("grade", "?")])
			var tmp := UnitFactory.create_unit(cls, elem, true)
			UnitFactory.apply_recruit_rolls(tmp, rolls)
			var rows := [
				["HP",  str(tmp.max_hp)], ["ATK", str(tmp.attack_damage)],
				["MAG", str(tmp.magic_power)], ["ARM", str(tmp.resistance)],
				["AS",  "%.2f" % tmp.attack_speed], ["SPD", str(tmp.movement_speed)],
			]
			for r in rows:
				out.append(["%s  %s" % [r[0], r[1]], Color(0.82, 0.86, 0.96)])
			if tmp.skill_name != "":
				out.append(["Skill: %s" % tmp.skill_name, Color(1.0, 0.85, 0.4)])
			tmp.free()
		"stat":
			var perk: Dictionary = slot["perk"]
			var _v: float = perk.get("rolled_value", perk.get("value", 0))
			var vs: String = LevelUpScreen.format_perk_value(perk)
			out.append("%s %s  (%s roll)" % [perk.get("label", "?"), vs, perk.get("grade", "?")])
			out.append([str(perk.get("desc", "")), Color(0.82, 0.86, 0.96)])
			out.append(["You choose which hero receives it.", Color(0.7, 0.72, 0.85)])
		"item":
			var item: EquipmentItem = slot["item"]
			out.append("%s  (%s)" % [item.name, item.get_rarity_name()])
			for row in EquipmentItem._STAT_DISPLAY:
				var val: float = float(item.stat_bonus.get(row[0], 0))
				if val > 0.0:
					out.append([EquipmentItem.format_bonus(row, val), Color(0.82, 0.86, 0.96)])
			for extra in [["magic_resist", "MARM", "int"], ["cdr", "Haste", "int"], ["ten", "Tenacity", "int"]]:
				var value := float(item.stat_bonus.get(extra[0], 0))
				if value > 0: out.append([EquipmentItem.format_bonus(extra, value), Color(0.82, 0.86, 0.96)])
			for line in item.get_passive_lines():
				out.append(["◆ %s" % line, Color(1.0, 0.85, 0.30)])
			out.append(["Goes to your bag — equip from the Equipment panel.", Color(0.7, 0.72, 0.85)])
		"relic":
			var relic: Dictionary = slot["relic"]
			out.append("%s  (%s)" % [relic.get("name", "?"), relic.get("grade", "?")])
			out.append([str(relic.get("desc", "")), Color(0.82, 0.86, 0.96)])
	return out

# ── Slot display helpers ──────────────────────────────────────────────────────
func _kind_title(kind: String) -> String:
	match kind:
		"hero": return "Hero"
		"stat": return "Stat Upgrade"
		"item": return "Item"
		"relic": return "Relic"
	return kind

func _slot_name(slot: Dictionary) -> String:
	match slot.get("kind", ""):
		"hero":  return "%s %s" % [_elem_name(slot["element"]), _class_name(slot["class"])]
		"stat":  return str(slot["perk"].get("label", "?"))
		"item":  return str(slot["item"].name)
		"relic": return str(slot["relic"].get("name", "?"))
	return "?"

func _slot_summary(slot: Dictionary) -> String:
	match slot.get("kind", ""):
		"hero":
			return "%s-rank recruit" % slot["rolls"].get("grade", "?")
		"stat":
			var perk: Dictionary = slot["perk"]
			var _v: float = perk.get("rolled_value", perk.get("value", 0))
			return "%s %s" % [LevelUpScreen.format_perk_value(perk), perk.get("label", "")]
		"item":
			return slot["item"].get_rarity_name()
		"relic":
			return str(slot["relic"].get("grade", "?")) + "-grade relic"
	return ""

func _slot_icon(slot: Dictionary) -> Texture2D:
	match slot.get("kind", ""):
		"hero":
			var path: String = VisualUnit.HERO_SPRITE_PATHS.get(slot["class"], "")
			if path != "":
				return load(path) as Texture2D
		"stat":
			var ptex := LevelUpScreen.perk_icon(str(slot["perk"].get("id", "")))
			if ptex:
				return ptex
		"item":
			var item: EquipmentItem = slot["item"]
			var itex: Texture2D = GearIcons.icon_for(item)   # legacy art or component composite
			if itex:
				return itex
			return load(EquipmentManager.ITEM_ICONS["Sword"]) as Texture2D
		"relic":
			var rpath: String = Relic.icon_path(slot["relic"])
			if rpath != "":
				return load(rpath) as Texture2D
	return null

func _slot_grade_letter(slot: Dictionary) -> String:
	match slot.get("kind", ""):
		"hero":  return str(slot["rolls"].get("grade", ""))
		"stat":  return str(slot["perk"].get("grade", ""))
		"relic": return str(slot["relic"].get("grade", ""))
		"item":  return _RARITY_LETTER[clampi(slot["item"].rarity, 0, 4)]
	return ""

const _RARITY_LETTER := ["D", "C", "B", "A", "S"]

func _slot_grade_color(slot: Dictionary) -> Color:
	match slot.get("kind", ""):
		"hero":  return UnitFactory.GRADE_COLORS.get(slot["rolls"].get("grade", "C"), Color.WHITE)
		"stat":  return slot["perk"].get("grade_color", Color.WHITE)
		"relic": return Relic.grade_color(slot["relic"].get("grade", "C"))
		"item":  return slot["item"].icon_color
	return Color(0.7, 0.7, 0.75)

func _elem_name(elem: int) -> String:
	match elem:
		UnitBase.Element.FIRE:      return "Fire"
		UnitBase.Element.WATER:     return "Water"
		UnitBase.Element.EARTH:     return "Earth"
		UnitBase.Element.AIR:       return "Air"
		UnitBase.Element.LIGHTNING: return "Lightning"
		_: return "Normal"

func _class_name(cls: int) -> String:
	match cls:
		UnitBase.UnitClass.WARRIOR:    return "Warrior"
		UnitBase.UnitClass.RANGER:     return "Ranger"
		UnitBase.UnitClass.MONK:       return "Monk"
		UnitBase.UnitClass.THIEF:      return "Thief"
		UnitBase.UnitClass.BLACK_MAGE: return "Black Mage"
		UnitBase.UnitClass.WHITE_MAGE: return "White Mage"
		UnitBase.UnitClass.RED_MAGE:   return "Red Mage"
		UnitBase.UnitClass.BLOODHOUND: return "Bloodhound"
		UnitBase.UnitClass.BOUNCER:    return "Bouncer"
		UnitBase.UnitClass.HEADHUNTER: return "Headhunter"
		UnitBase.UnitClass.SHAUNA:     return "Shauna"
		UnitBase.UnitClass.NEMI:       return "Nemi"
		UnitBase.UnitClass.SHEILDOR:   return "Sheildor"
		UnitBase.UnitClass.LORDEE:     return "Lordee"
		UnitBase.UnitClass.NECRO:      return "Necro"
		UnitBase.UnitClass.DOC:        return "Doc"
		UnitBase.UnitClass.RIOT:       return "Riot"
		UnitBase.UnitClass.PASTOR:     return "Pastor"
		UnitBase.UnitClass.SABLE:      return "Sable"
		UnitBase.UnitClass.RUSH:       return "Rush"
		UnitBase.UnitClass.STITCH:     return "Stitch"
		UnitBase.UnitClass.COAL:       return "Coal"
		UnitBase.UnitClass.JUNE:       return "June"
		UnitBase.UnitClass.CROSS:      return "Cross"
		UnitBase.UnitClass.SEAR:       return "Sear"
		UnitBase.UnitClass.EMBER:      return "Ember"
		UnitBase.UnitClass.RIFT:       return "Rift"
		UnitBase.UnitClass.ZOLT:       return "Zolt"
		UnitBase.UnitClass.LUMEN:      return "Lumen"
		UnitBase.UnitClass.STATIC:     return "Static"
		UnitBase.UnitClass.REED:       return "Reed"
		UnitBase.UnitClass.VAIL:       return "Vail"
		UnitBase.UnitClass.SPORE:      return "Spore"
		_: return "Unknown"

# ── Barks (reactive flavor) ───────────────────────────────────────────────────
func _set_bark(text: String) -> void:
	if _bark_lbl:
		_bark_lbl.text = "“%s”" % text

func _buy_bark(kind: String) -> String:
	match kind:
		"hero":  return "A fine hire! Treat 'em well, hey?"
		"stat":  return "Sharper already. Heh heh."
		"item":  return "Ah, good eye — that one's got history."
		"relic": return "Oho! You know real power when you see it."
	return "Sold! Pleasure doing business."

# ── Keeper / room animation ───────────────────────────────────────────────────
func _start_keeper_idle() -> void:
	if not _keeper:
		return
	var tw := create_tween().set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_keeper, "scale", Vector2(1.012, 0.99), 1.8)
	tw.tween_property(_keeper, "scale", Vector2(1.0, 1.0), 1.8)
	_keeper.set_meta("idle_tween", tw)

func _keeper_react() -> void:
	if not _keeper:
		return
	if _reaction: _reaction.kill()
	_reaction = create_tween()
	_reaction.tween_property(_keeper, "rotation", -0.025, 0.10)
	_reaction.tween_property(_keeper, "rotation", 0.0, 0.22)

func _animate_keeper_intro() -> void:
	if not _keeper:
		return
	_keeper.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(_keeper, "modulate", Color.WHITE, 0.35)

func _add_lantern_glow(center: Vector2, extent: Vector2, period: float) -> void:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0, 0.62, 0.16, 0.15), Color(1.0, 0.5, 0.1, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var glow := TextureRect.new()
	glow.texture = texture
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.size = extent
	glow.position = center - extent * 0.5
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(glow)
	var flicker := glow.create_tween().set_loops()
	flicker.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	flicker.tween_property(glow, "modulate:a", 0.35, period * 0.4)
	flicker.tween_property(glow, "modulate:a", 0.9, period * 0.15)
	flicker.tween_property(glow, "modulate:a", 0.6, period * 0.45)

func _start_glow_pulse(bg: TextureRect) -> void:
	# Gentle warm-light breathing on the flat image so it isn't dead-static.
	var tw := create_tween().set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(bg, "modulate", Color(1.015, 1.005, 0.99), 2.4)
	tw.tween_property(bg, "modulate", Color(0.985, 0.98, 0.97), 2.4)

# ── Close ─────────────────────────────────────────────────────────────────────
func _on_leave() -> void:
	visible = false
	_hide_tooltip()
	closed.emit()

func _refresh_gold(gold: int) -> void:
	if _gold_lbl:
		_gold_lbl.text = "%d  GOLD" % gold
	if _reroll_btn:
		var cost := current_reroll_cost()
		_reroll_btn.text = "Refresh Stock  ·  %dg" % cost
		_reroll_btn.disabled = gold < cost

# ── Small widget factories ────────────────────────────────────────────────────
func _mk_label(text: String, sz: int, col: Color, pos: Vector2, size: Vector2, center: bool) -> Label:
	return _mk_label_on(_panel, text, sz, col, pos, size, center)

func _mk_label_on(parent: Node, text: String, sz: int, col: Color, pos: Vector2, size: Vector2, center: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	UITheme.apply_font(l, sz)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _clabel(parent: Node, text: String, sz: int, col: Color, pos: Vector2, size: Vector2, center: bool, wrap: bool = false) -> Label:
	var l := _mk_label_on(parent, text, sz, col, pos, size, center)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return l

func _mk_button(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.add_theme_stylebox_override("normal", _flat(Color("483820"), BRASS, 1, 6))
	b.add_theme_stylebox_override("hover", _flat(Color("624c2a"), CREAM, 2, 6))
	b.add_theme_stylebox_override("pressed", _flat(Color("261f16"), BRASS, 1, 6))
	b.add_theme_stylebox_override("disabled", _flat(Color("24211d"), Color("62594c"), 1, 6))
	b.add_theme_stylebox_override("focus", _flat(Color.TRANSPARENT, Color("8ad2cc"), 3, 6))
	b.add_theme_color_override("font_color", CREAM)
	UITheme.apply_font(b, 22)
	return b

func _flat(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	return s

func _frame_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.05, 0.08)
	s.border_color = Color(0.83, 0.69, 0.22)
	s.set_border_width_all(4)
	s.corner_radius_top_left = 14
	s.corner_radius_top_right = 14
	s.corner_radius_bottom_left = 14
	s.corner_radius_bottom_right = 14
	return s
