extends CanvasLayer
class_name CampScreen

signal activity_requested(kind: String, target: Variant, modifier: String)
signal closed()
var activities: MerchantServicesPanel
var _root: Control
var _actions: Label
var _journal: Label

func _ready() -> void:
	_root = Control.new()
	_root.size = Vector2(1920, 1080)
	_root.theme = Theme.new()
	_root.theme.default_font = preload("res://assets/Fonts/Merchant-NotoSans-Regular.ttf")
	add_child(_root)
	var background := TextureRect.new()
	background.texture = preload("res://assets/events/rest_camp.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.04, 0.025, 0.22)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	var header := Panel.new()
	header.position = Vector2(40, 28)
	header.size = Vector2(1840, 94)
	header.add_theme_stylebox_override("panel", UITheme.header_box())
	_root.add_child(header)
	_label(header, "MAKE CAMP", 34, Vector2(28, 19), Vector2(950, 55))
	_actions = _label(header, "", 28, Vector2(1080, 24), Vector2(720, 50))
	_actions.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var journal := Panel.new()
	journal.position = Vector2(48, 790)
	journal.size = Vector2(820, 232)
	journal.add_theme_stylebox_override("panel", UITheme.panel_box())
	_root.add_child(journal)
	var caption := _label(journal, "A MOMENT BY THE FIRE", 28, Vector2(24, 18), Vector2(770, 48))
	caption.add_theme_color_override("font_color", Color("f3e5c9"))
	_journal = _label(journal, "", 22, Vector2(24, 76), Vector2(770, 140))
	_journal.add_theme_color_override("font_color", Color("f3e5c9"))
	_journal.clip_text = true
	_journal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.apply_read_font(_journal, UITheme.FONT_VALUE)   # prose -> Inter (2026-09-29)
	activities = MerchantServicesPanel.new()
	activities.camp_mode = true
	activities.activity_kinds = ["rest", "training", "supplies"]
	activities._kind = "rest"
	_root.add_child(activities)
	activities.position = Vector2(920, 165)
	activities.size = Vector2(950, 857)
	activities.purchase_requested.connect(func(kind, target, modifier): activity_requested.emit(kind, target, modifier))
	activities.visibility_changed.connect(func():
		if visible and not activities.visible:
			visible = false
			closed.emit())
	get_viewport().size_changed.connect(_resize)
	_resize()
	visible = false

func _label(parent: Control, text: String, font_size: int, pos: Vector2, extent: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = extent
	UITheme.apply_font(label, font_size)
	label.add_theme_color_override("font_color", UITheme.TEXT_BODY)
	parent.add_child(label)
	return label

func _resize() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var ratio := minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0)
	_root.scale = Vector2.ONE * ratio
	_root.position = (viewport_size - Vector2(1920, 1080) * ratio) * 0.5

func open() -> void:
	visible = true
	activities.open()
	refresh()

func refresh(message: String = "") -> void:
	activities.report(message)
	var context: Dictionary = activities.provider.call() if activities.provider.is_valid() else {}
	var remaining := int(context.get("actions", 0))
	_actions.text = "%s    %d / 2 ACTIONS LEFT" % ["● ●" if remaining == 2 else ("● ○" if remaining == 1 else "○ ○"), remaining]
	var history: Array = context.get("history", [])
	_journal.text = "Choose two activities. Repeat any option.\n\n" + ("\n".join(history.slice(maxi(0, history.size() - 2))) if not history.is_empty() else "Rest your heroes, practice, work your gear,\nor prepare for the road.")
