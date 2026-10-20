class_name RelicMilestoneScreen
extends CanvasLayer
# Illustrated reward reveal and milestone catalogue. This view performs no IO.
signal collected
var _root: Control
var _grid: GridContainer
var _scroll: ScrollContainer
var _title: Label
var _subtitle: Label
var _summary: Label
var _button: Button
var _earned_tab: Button
var _collection_tab: Button
var _state: RelicMilestoneState
var _catalogue := false
var _read_face: Font

func _ready() -> void:
	layer = 120
	_read_face = UITheme.body_face()
	if _read_face == null:
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(["Segoe UI", "Noto Sans", "Arial"])
		_read_face = fallback
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.018, 0.014, 0.011, 0.97)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 72)
	for side in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 32)
	_root.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	margin.add_child(stack)

	var header := Control.new()
	header.custom_minimum_size.y = 142
	stack.add_child(header)
	var banner := UITheme.menu_header(header, Rect2())
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var header_pad := MarginContainer.new()
	header_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_pad.add_theme_constant_override("margin_left", 190)
	header_pad.add_theme_constant_override("margin_right", 150)
	header_pad.add_theme_constant_override("margin_top", 24)
	header.add_child(header_pad)
	var headings := VBoxContainer.new()
	header_pad.add_child(headings)
	_title = _label("Relics earned", UITheme.FONT_DISPLAY, true)
	headings.add_child(_title)
	_subtitle = _label("", 18)
	headings.add_child(_subtitle)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	stack.add_child(tabs)
	_earned_tab = _tab("Earned this run", false)
	_collection_tab = _tab("Collection", true)
	tabs.add_child(_earned_tab)
	tabs.add_child(_collection_tab)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	_scroll.add_child(_grid)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	var footer_panel := PanelContainer.new()
	footer_panel.add_theme_stylebox_override("panel", UITheme.menu_surface_box())
	stack.add_child(footer_panel)
	footer_panel.add_child(footer)
	var footer_text := VBoxContainer.new()
	footer_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_text)
	_summary = _label("", UITheme.FONT_HEADER, true)
	footer_text.add_child(_summary)
	var next_run := _label("Collected relics enter the pool on your next run.", 18)
	next_run.add_theme_color_override("font_color", UITheme.menu_subtitle_color())
	footer_text.add_child(next_run)
	_button = Button.new()
	_button.custom_minimum_size = Vector2(340, 60)
	UITheme.style_button(_button)
	UITheme.apply_font(_button, UITheme.FONT_HEADER)
	_button.pressed.connect(func(): collected.emit())
	footer.add_child(_button)
	_root.resized.connect(_layout_columns)

func show_collection(state: RelicMilestoneState) -> void:
	_state = state
	_catalogue = state.pending.is_empty()
	var relic_count := 0
	for id: String in state.pending:
		relic_count += RelicMilestones.members(id).size()
	_button.text = "Collect %d relics" % relic_count if relic_count > 0 else "Continue"
	_summary.text = "%d milestones completed  /  %d relics earned" % [state.pending.size(), relic_count] \
		if relic_count > 0 else "%d of %d milestones collected" % [state.unlocked.size(), RelicMilestones.TABLE.size()]
	_earned_tab.text = "Earned this run  (%d)" % state.pending.size()
	_collection_tab.text = "Collection  (%d/%d)" % [state.unlocked.size(), RelicMilestones.TABLE.size()]
	_earned_tab.disabled = state.pending.is_empty()
	_refresh_cards()
	visible = true

func show_glossary(state: RelicMilestoneState) -> void:
	show_collection(state)
	_catalogue = true
	_earned_tab.visible = false
	_button.text = "Close"
	_summary.text = "%d of %d milestones unlocked" % [state.unlocked.size(), RelicMilestones.TABLE.size()]
	_refresh_cards()

func _tab(text: String, catalogue: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(230, 46)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UITheme.apply_font(button, UITheme.FONT_HEADER)
	button.pressed.connect(func():
		_catalogue = catalogue
		_refresh_cards())
	return button

func _refresh_cards() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_title.text = "Relic collection" if _catalogue else "Relics earned"
	_subtitle.text = "Choose a milestone to chase. Its relics become permanent additions to future runs." \
		if _catalogue else "Your achievements have unlocked new treasures. Collect them for your next adventure."
	UITheme.style_button_secondary(_earned_tab) if _catalogue else UITheme.style_button(_earned_tab)
	UITheme.style_button(_collection_tab) if _catalogue else UITheme.style_button_secondary(_collection_tab)
	for status in ["NEW", "LOCKED", "COLLECTED"]:
		for row: Dictionary in RelicMilestones.TABLE:
			var row_status := "NEW" if _state.pending.has(row.id) else ("COLLECTED" if _state.unlocked.has(row.id) else "LOCKED")
			if row_status != status or (not _catalogue and row_status != "NEW"): continue
			_grid.add_child(_milestone_card(row, row_status, not _catalogue))
	_layout_columns()
	_scroll.scroll_vertical = 0

func _layout_columns() -> void:
	if not _grid or not _root: return
	var available := _root.size.x - 144.0
	_grid.columns = maxi(1, mini(2 if _catalogue else 3, int(available / 400.0)))

func _milestone_card(row: Dictionary, status: String, featured: bool) -> Control:
	var members := RelicMilestones.members(row.id)
	var top: Dictionary = members[-1] if not members.is_empty() else {}
	var grade_color: Color = Relic.grade_color(str(top.get("grade", "D")))
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var surface := UITheme.menu_surface_box()
	surface.set_content_margin_all(0)
	surface.border_color = grade_color.darkened(0.45) if status == "NEW" else surface.border_color
	surface.set_border_width_all(2 if status == "NEW" else 1)
	box.add_theme_stylebox_override("panel", surface)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: pad.add_theme_constant_override("margin_" + side, 24 if featured else 18)
	box.add_child(pad)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16 if featured else 12)
	pad.add_child(content)

	var heading := HBoxContainer.new()
	content.add_child(heading)
	var name := _label(row.name, 32 if featured else UITheme.FONT_HEADER, true)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(name)
	var status_label := _label("EARNED" if status == "NEW" else status, UITheme.FONT_BODY, true)
	status_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_label.custom_minimum_size.x = 72
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", _grade_ink(str(top.get("grade", "D"))) if status == "NEW" else UITheme.menu_subtitle_color())
	heading.add_child(status_label)

	var condition := _label(row.condition, 18)
	condition.custom_minimum_size.y = 52 if featured else 44
	content.add_child(condition)
	var separator := HSeparator.new()
	separator.modulate = Color(0.65, 0.53, 0.34, 0.5)
	content.add_child(separator)
	var rewards := HBoxContainer.new()
	rewards.add_theme_constant_override("separation", 10)
	rewards.alignment = BoxContainer.ALIGNMENT_CENTER if featured else BoxContainer.ALIGNMENT_BEGIN
	content.add_child(rewards)
	for relic: Dictionary in members:
		rewards.add_child(_relic_art(relic, status, featured, members.size()))
	if featured:
		var note := _label("%d relics unlocked" % members.size(), 16)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_color_override("font_color", UITheme.menu_subtitle_color())
		content.add_child(note)
	return box

func _relic_art(relic: Dictionary, status: String, featured: bool, member_count: int) -> Control:
	var item := VBoxContainer.new()
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL if featured else Control.SIZE_SHRINK_BEGIN
	item.custom_minimum_size.x = 82 if featured else 64
	item.add_theme_constant_override("separation", 8)
	item.tooltip_text = "%s [%s]\n%s" % [relic.name, relic.grade, relic.desc]
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(96 if member_count > 3 else 128, 152) if featured else Vector2(60, 60)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var path := Relic.icon_path(relic)
	icon.texture = load(path) as Texture2D if path != "" else null
	icon.modulate.a = 0.5 if status == "LOCKED" else 1.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_child(icon)
	if featured:
		var name := _label(relic.name, 16)
		name.custom_minimum_size.y = 42
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item.add_child(name)
	var grade := _label(relic.grade + " GRADE", UITheme.FONT_BODY, true)
	grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grade.add_theme_color_override("font_color", _grade_ink(relic.grade))
	item.add_child(grade)
	if path == "":
		icon.tooltip_text = relic.name
		var fallback := _label(relic.name, 16)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item.add_child(fallback)
	return item

func _grade_ink(grade: String) -> Color:
	var color := Relic.grade_color(grade)
	return color.darkened(0.45) if UITheme.is_light() else color

func _label(text: String, size: int, heading := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if heading:
		UITheme.apply_font(label, UITheme.header_font(size))
	else:
		label.add_theme_font_override("font", _read_face)
		label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", UITheme.menu_title_color() if heading else UITheme.menu_body_color())
	return label
