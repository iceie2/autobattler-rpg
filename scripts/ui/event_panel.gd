extends CanvasLayer
class_name EventPanel

signal event_choice_made(choice_index: int)

var _panel: Panel
var _current_event: EventBlessing = null
var _choice_buttons: Array[Button] = []

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.8)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = Vector2(800, 500)
	# UI theme pass 2026-07-04: dobo card panel instead of flat navy box.
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	overlay.add_child(_panel)

	# Title
	var title_lbl = _lbl(_panel, "", 28, Color.WHITE,
		Vector2(20, 20), Vector2(760, 50), true)
	title_lbl.name = "TitleLabel"

	# Description
	var desc_lbl = _lbl(_panel, "", 18, Color(0.8, 0.8, 0.8),
		Vector2(20, 80), Vector2(760, 80), true)
	desc_lbl.name = "DescLabel"
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Choices container
	var choices_container = VBoxContainer.new()
	choices_container.position = Vector2(100, 180)
	choices_container.size = Vector2(600, 260)
	choices_container.add_theme_constant_override("separation", 12)
	_panel.add_child(choices_container)
	choices_container.name = "ChoicesContainer"

	visible = false
	_center_panel()

func show_event(event: EventBlessing) -> void:
	_current_event = event
	_refresh_display()
	visible = true

func _refresh_display() -> void:
	if not _current_event:
		return

	# Update title and description
	var title_lbl = _panel.get_node("TitleLabel") as Label
	var desc_lbl = _panel.get_node("DescLabel") as Label
	var color = _current_event.get_type_color()

	title_lbl.text = _current_event.title
	title_lbl.add_theme_color_override("font_color", color)
	desc_lbl.text = _current_event.description

	# Clear previous choice buttons
	var choices_container = _panel.get_node("ChoicesContainer") as VBoxContainer
	for child in choices_container.get_children():
		child.queue_free()

	_choice_buttons.clear()

	# Add choice buttons
	for i in range(_current_event.choices.size()):
		var choice = _current_event.choices[i]
		var btn = Button.new()
		btn.text = choice.text
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
		btn.custom_minimum_size = Vector2(600, 50)
		btn.add_theme_stylebox_override("normal",
			_flat(Color(0.12, 0.12, 0.20, 0.8), Color(0.4, 0.4, 0.55), 2, 6))
		btn.add_theme_stylebox_override("hover",
			_flat(Color(0.18, 0.18, 0.28, 0.8), Color(0.6, 0.6, 0.8), 2, 6))
		btn.pressed.connect(_on_choice_selected.bind(i))
		choices_container.add_child(btn)
		_choice_buttons.append(btn)

func _on_choice_selected(choice_index: int) -> void:
	event_choice_made.emit(choice_index)
	visible = false

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
