class_name RelicMilestoneScreen
extends CanvasLayer
# A self-contained end-of-run collection/catalogue; no save IO in this view.
signal collected
var _rows: VBoxContainer
var _subtitle: Label
var _button: Button

func _ready() -> void:
	layer = 120
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 80)
	for side in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 32)
	root.add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.menu_surface_box())
	margin.add_child(panel)
	var inset := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: inset.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(inset)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	inset.add_child(stack)
	stack.add_child(_label("RELIC MILESTONES", 32, true))
	_subtitle = _label("", 19)
	stack.add_child(_subtitle)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(_rows)
	_button = Button.new()
	_button.custom_minimum_size.y = 52
	UITheme.style_button(_button)
	UITheme.apply_font(_button, UITheme.FONT_HEADER)
	_button.pressed.connect(func(): collected.emit())
	stack.add_child(_button)

func show_collection(state: RelicMilestoneState) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_subtitle.text = "%d new milestones earned. Collect their relics for future runs." % state.pending.size() \
		if not state.pending.is_empty() else "Discover the conditions below to expand the relic pool in future runs."
	_button.text = "COLLECT & CONTINUE" if not state.pending.is_empty() else "CONTINUE"
	# New awards first, then goals, then the collection already earned.
	for status in ["NEW", "LOCKED", "COLLECTED"]:
		for row: Dictionary in RelicMilestones.TABLE:
			var row_status := "NEW" if state.pending.has(row.id) else ("COLLECTED" if state.unlocked.has(row.id) else "LOCKED")
			if row_status != status: continue
			var box := PanelContainer.new()
			box.add_theme_stylebox_override("panel", UITheme.menu_surface_box())
			_rows.add_child(box)
			var pad := MarginContainer.new()
			for side in ["left", "right", "top", "bottom"]: pad.add_theme_constant_override("margin_" + side, 12)
			box.add_child(pad)
			var content := VBoxContainer.new()
			pad.add_child(content)
			content.add_child(_label("%s  /  %s" % [row.name, status], 22, true))
			content.add_child(_label(row.condition, 18))
			var names: PackedStringArray = []
			for relic: Dictionary in RelicMilestones.members(row.id):
				names.append("%s [%s]" % [relic.name, relic.grade])
			content.add_child(_label("Unlocks: " + ", ".join(names), 16))
	visible = true

func _label(text: String, size: int, header := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.apply_font(label, UITheme.header_font(size) if header else UITheme.body_font(size))
	label.add_theme_color_override("font_color", UITheme.menu_title_color() if header else UITheme.menu_body_color())
	return label
