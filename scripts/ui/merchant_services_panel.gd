extends Panel
class_name MerchantServicesPanel
signal purchase_requested(kind: String, target: Variant, modifier: String)
var provider: Callable
var _kind := "exchange"
var _targets: Array = []
var _choices: Array = []
var _target: OptionButton
var _modifier: OptionButton
var _details: RichTextLabel
var _confirm: Button
var _result: Label
var _context: Dictionary = {}
var _tabs: Dictionary = {}
var _back: Button
var camp_mode := false
var activity_kinds: Array = ["exchange", "enchant"]
var _heading: Label
var _activity_art: TextureRect

func _ready() -> void:
	position = Vector2(410, 180)
	size = Vector2(1100, 720)
	z_index = 30
	var box := StyleBoxFlat.new()
	box.bg_color = Color("1b1c19")
	box.border_color = Color("b79860")
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	add_theme_stylebox_override("panel", box)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	margin.add_child(stack)
	var heading := Label.new()
	_heading = heading
	heading.text = "CAMP ACTIVITIES" if camp_mode else "MERCHANT SERVICES"
	UITheme.apply_font(heading, 30)
	stack.add_child(heading)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	stack.add_child(tabs)
	for kind in activity_kinds:
		var button := Button.new()
		button.text = str(kind).capitalize()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 54
		UITheme.apply_font(button, 22)
		button.pressed.connect(func(): _kind = kind; _result.text = ""; reload())
		_tabs[kind] = button
		_style_button(button)
		tabs.add_child(button)
	if camp_mode:
		_activity_art = TextureRect.new()
		_activity_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_activity_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_activity_art.custom_minimum_size.y = 180
		_activity_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(_activity_art)
	_target = OptionButton.new()
	_target.custom_minimum_size.y = 48
	_target.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UITheme.apply_font(_target, 20)
	_target.item_selected.connect(func(_i): _populate_modifiers(); _update_details())
	stack.add_child(_target)
	_modifier = OptionButton.new()
	_modifier.custom_minimum_size.y = 48
	UITheme.apply_font(_modifier, 20)
	_modifier.item_selected.connect(func(_i): _update_details())
	stack.add_child(_modifier)
	_details = RichTextLabel.new()
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.apply_rich_font(_details, 20)
	stack.add_child(_details)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size.y = 56
	UITheme.apply_font(_result, 20)
	_result.add_theme_color_override("font_color", Color("a9dcc0"))
	stack.add_child(_result)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	stack.add_child(actions)
	_confirm = Button.new()
	_confirm.custom_minimum_size.y = 56
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_font(_confirm, 22)
	_confirm.pressed.connect(func():
		_confirm.disabled = true
		purchase_requested.emit(_kind, _selected_target(), _selected_modifier()))
	actions.add_child(_confirm)
	var back := Button.new()
	_back = back
	_style_button(back)
	_style_button(_confirm)
	back.text = "Leave Camp" if camp_mode else "Back to Stock"
	back.custom_minimum_size = Vector2(270, 56)
	UITheme.apply_font(back, 22)
	back.pressed.connect(hide)
	actions.add_child(back)
	get_viewport().gui_focus_changed.connect(_guard_focus)
	hide()

func open() -> void:
	_result.text = ""
	reload()
	show()
	if _target.visible and _target.item_count > 0:
		_target.grab_focus()
	else:
		_tabs[_kind].grab_focus()

func reload() -> void:
	var selected := maxi(0, _target.selected)
	_context = provider.call() if provider.is_valid() else {}
	if camp_mode:
		_heading.text = "CAMP ACTIVITIES    /    %d ACTIONS LEFT" % int(_context.get("actions", 0))
	_targets = _context.get("heroes", []) if _kind == "training" else _context.get("items", [])
	_target.clear()
	for t in _targets:
		_target.add_item("%s · Lv.%d" % [t.unit_name, t.level] if _kind == "training" else "%s · %s" % [t.name, t.get_rarity_name()])
	if _target.item_count > 0: _target.select(mini(selected, _target.item_count - 1))
	_target.visible = not _kind in ["supplies", "rest"]
	for key in _tabs:
		_tabs[key].add_theme_stylebox_override("normal", _box(Color("49391f") if key == _kind else Color("272720")))
	_populate_modifiers()
	_update_details()

func _selected_target() -> Variant:
	return _targets[_target.selected] if not _kind in ["supplies", "rest"] and _target.selected >= 0 and _target.selected < _targets.size() else null

func _selected_modifier() -> String:
	return str(_choices[_modifier.selected]["key"]) if _modifier.selected >= 0 and _modifier.selected < _choices.size() else ""

func _populate_modifiers() -> void:
	_modifier.clear()
	_choices.clear()
	_modifier.visible = _kind == "enchant"
	var t = _selected_target()
	if camp_mode:
		var paths := {"rest": "res://assets/icons/map_nodes/node_rest.png",
			"training": "res://assets/icons/stat_icons/xp_bonus.png",
			"reforge": "res://assets/icons/stat_icons/strength.png",
			"supplies": "res://assets/icons/stat_icons/hp_regen.png"}
		_activity_art.texture = load(paths[_kind]) if ResourceLoader.exists(paths[_kind]) else null
	if _kind == "enchant" and t is EquipmentItem:
		_choices = MerchantServices.modifier_choices(t)
		for choice in _choices: _modifier.add_item(choice["label"])

func _update_details() -> void:
	var t = _selected_target()
	var price := MerchantServices.cost(_kind, int(_context.get("round", 1)), t.rarity if t is EquipmentItem else 0)
	var allowed := t != null or _kind in ["supplies", "rest"]
	var text := ""
	match _kind:
		"rest":
			text = "Restore 50% of maximum HP and mana to every fielded and benched hero, capped at full. Rest twice to fully recover."
		"reforge":
			text = "Reroll the selected bag item’s stats. Keep its identity, rarity, passive modifiers and counters. The new stats may be weaker. Equipped items must first be returned to your bag."
		"exchange":
			text = "Trade one bag item for a random item of exactly the same rarity. The original is consumed. Stats, modifiers and item counters are replaced. The result may be weaker.\\nEquipped items must first be returned to your bag."
		"enchant":
			text = "Add a random modifier in an available slot, or replace the selected modifier. Component gear replaces ONE passive level, keeping the rarity budget and all stats. A different modifier is guaranteed.\\nCommon gear must be combined first. Equipped items must first be returned to your bag."
			allowed = allowed and not _choices.is_empty()
		"training":
			if t != null:
				text = "Give %s %d XP. Current XP: %d / %d. Level cap: %d. Any earned perk choice follows immediately." % [t.unit_name, MerchantServices.training_xp(t), t.current_xp, t.xp_to_level, Progression.hero_level_cap()]
				allowed = t.level < Progression.hero_level_cap()
		"supplies":
			text = "Prepare supplies: +10%% ATK and MAG to fielded heroes for the next battle only. Repeat to stack another +10%%. Consumed when battle begins; stats return to normal afterward.\\n\\nPacks ready: %d" % int(_context.get("supplies_count", 0))
	if t is EquipmentItem: text += "\\n\\nSelected: " + t.to_short_string()
	if t == null and not _kind in ["supplies", "rest"]: text += "\\n\\nNo eligible targets."
	text += "\\n\\nUses 1 camp action. No gold cost. Repeat any activity." if camp_mode else "\\n\\nGold: %dg    •    Cost: %dg" % [int(_context.get("gold", 0)), price]
	_details.text = text.replace("\\n", "\n")
	_confirm.text = "Confirm %s · 1 action" % _kind.capitalize() if camp_mode else "Confirm %s · %dg" % [_kind.capitalize(), price]
	_confirm.disabled = not allowed or (int(_context.get("actions", 0)) <= 0 if camp_mode else int(_context.get("gold", 0)) < price)

func report(message: String) -> void:
	reload()
	_result.text = message

func _box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color("8e7145")
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	return box

func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _box(Color("49391f")))
	button.add_theme_stylebox_override("hover", _box(Color("66502f")))
	button.add_theme_stylebox_override("pressed", _box(Color("29241b")))
	button.add_theme_stylebox_override("disabled", _box(Color("24211d")))
	var focus := _box(Color.TRANSPARENT)
	focus.border_color = Color("8ad2cc")
	focus.set_border_width_all(3)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", Color("f3e5c9"))

func _guard_focus(control: Control) -> void:
	if is_visible_in_tree() and control != null and not is_ancestor_of(control):
		_back.grab_focus.call_deferred()

func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()
