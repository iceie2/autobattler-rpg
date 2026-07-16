extends CanvasLayer
class_name EventPanel

# Event panel v2 (2026-07-16 design pass, user-approved list):
# - Type identity: dark tinted backdrop + "✦ BLESSING/CURSE/CROSSROADS ✦"
#   banner, not just a colored title.
# - No dead space: the panel's height is computed from its content each event.
# - Risk-colored outcomes: each choice's outcome line is colored by what it
#   does — green gain, red cost, orange mixed, gold gamble.
# - Art slot: if assets/events/<slug>.png exists for the event's title, it
#   renders as a wide scene between the description and the choices. Drop in
#   art (see tools/sprite_pipeline/GEMINI_EVENT_PROMPTS.md) and it lights up —
#   no code change needed.
signal event_choice_made(choice_index: int)

const PANEL_W := 800.0
const CONTENT_X := 20.0
const CONTENT_W := PANEL_W - CONTENT_X * 2.0
const CHOICE_W := 620.0
const ART_H := 280.0

# Dark mood backdrops per event type (the parchment panel texture is mostly
# transparent, so this is what actually sets the tone).
const BACKDROPS := {
	EventBlessing.EventType.BLESSING: Color(0.05, 0.11, 0.06, 0.96),
	EventBlessing.EventType.CURSE:    Color(0.13, 0.05, 0.05, 0.96),
	EventBlessing.EventType.NEUTRAL:  Color(0.11, 0.09, 0.04, 0.96),
}
const BANNERS := {
	EventBlessing.EventType.BLESSING: "✦  BLESSING  ✦",
	EventBlessing.EventType.CURSE:    "✦  CURSE  ✦",
	EventBlessing.EventType.NEUTRAL:  "✦  CROSSROADS  ✦",
}

# Outcome-line colors — dark variants, they sit on the gold button texture.
const OUT_GAIN    := Color(0.10, 0.42, 0.12)
const OUT_COST    := Color(0.62, 0.10, 0.06)
const OUT_MIXED   := Color(0.55, 0.28, 0.02)
const OUT_GAMBLE  := Color(0.45, 0.22, 0.55)
const OUT_NEUTRAL := Color(0.40, 0.35, 0.25)

var _panel: Panel
var _backdrop: ColorRect
var _banner: Label
var _title: Label
var _desc: Label
var _art: TextureRect
var _choices_box: VBoxContainer
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
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	overlay.add_child(_panel)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.offset_left = 6; _backdrop.offset_top = 6
	_backdrop.offset_right = -6; _backdrop.offset_bottom = -6
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_backdrop)
	_panel.move_child(_backdrop, 0)   # behind the parchment frame's corners

	_banner = _lbl(_panel, "", 12, Color.WHITE, Vector2.ZERO, Vector2(PANEL_W, 24), true)
	_title  = _lbl(_panel, "", 26, Color.WHITE, Vector2.ZERO, Vector2(PANEL_W, 44), true)
	_desc   = _lbl(_panel, "", 15, Color(0.82, 0.8, 0.75), Vector2.ZERO, Vector2(CONTENT_W, 48), true)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.clip_contents = true
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_art)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 12)
	_panel.add_child(_choices_box)

	visible = false

func show_event(event: EventBlessing) -> void:
	_current_event = event
	_refresh_display()
	visible = true

# assets/events/<slug>.png — "Gambler's Table" → gamblers_table.png
static func art_path(title: String) -> String:
	var slug := title.to_lower().replace("'", "").replace("!", "").replace(" ", "_")
	return "res://assets/events/%s.png" % slug

func _refresh_display() -> void:
	if not _current_event:
		return
	var etype: int = _current_event.event_type
	var color: Color = _current_event.get_type_color()
	_backdrop.color = BACKDROPS.get(etype, BACKDROPS[EventBlessing.EventType.NEUTRAL])

	# Manual top-to-bottom layout; the panel then shrinks to exactly fit.
	var y := 20.0
	_banner.text = BANNERS.get(etype, BANNERS[EventBlessing.EventType.NEUTRAL])
	_banner.add_theme_color_override("font_color", color)
	_banner.position = Vector2(0, y); y += 30.0

	_title.text = _current_event.title
	_title.add_theme_color_override("font_color", Color(0.96, 0.93, 0.86))
	_title.position = Vector2(0, y); y += 46.0

	_desc.text = _current_event.description
	_desc.position = Vector2(CONTENT_X, y); y += 50.0

	var apath := art_path(_current_event.title)
	if ResourceLoader.exists(apath):
		_art.visible = true
		_art.texture = load(apath)
		_art.position = Vector2(CONTENT_X, y)
		_art.size = Vector2(CONTENT_W, ART_H)
		y += ART_H + 14.0
	else:
		_art.visible = false

	for child in _choices_box.get_children():
		child.queue_free()
	_choice_buttons.clear()
	for i in range(_current_event.choices.size()):
		_choices_box.add_child(_make_choice_button(_current_event.choices[i], i))
	_choices_box.position = Vector2((PANEL_W - CHOICE_W) / 2.0, y)
	y += _current_event.choices.size() * 76.0 - 12.0

	_panel.size = Vector2(PANEL_W, y + 24.0)
	_center_panel()

# Two lines per choice: what you do, then what happens — outcome colored by
# whether it's a gain, a cost, a bit of both, or a gamble.
func _make_choice_button(choice, index: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CHOICE_W, 64)
	btn.focus_mode = Control.FOCUS_NONE
	var boxes: Dictionary = UITheme.button_boxes()
	btn.add_theme_stylebox_override("normal", boxes["normal"])
	btn.add_theme_stylebox_override("hover", boxes["hover"])
	btn.add_theme_stylebox_override("pressed", boxes["pressed"])
	btn.pressed.connect(_on_choice_selected.bind(index))

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 18; col.offset_right = -18
	col.offset_top = 7;  col.offset_bottom = -7
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)

	var title := Label.new()
	title.text = choice.text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UITheme.body_font(15))
	title.add_theme_color_override("font_color", UITheme.TEXT_BTN)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)

	if choice.description != "":
		var outcome := Label.new()
		outcome.text = choice.description
		outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outcome.add_theme_font_size_override("font_size", UITheme.body_font(11))
		outcome.add_theme_color_override("font_color", _outcome_color(choice.effects))
		outcome.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(outcome)
	return btn

# Classify a choice's effects: pure gain (green), pure cost (red), trade-off
# (orange), coin-flip gamble (purple), or nothing (muted).
func _outcome_color(effects: Dictionary) -> Color:
	if effects.has("gold_if_win") or effects.has("gold_if_lose"):
		return OUT_GAMBLE
	var gain := false
	var cost := false
	for k in effects:
		var v: float = float(effects[k])
		match k:
			"gold":
				if v > 0.0: gain = true
				elif v < 0.0: cost = true
			"heal_all", "restore_mana", "max_units", "max_level":
				gain = true
			"hero_damage":
				cost = true
			"team_dmg_mult", "team_def_mult", "team_spd_mult", "max_hp_mult":
				if v > 1.0: gain = true
				elif v < 1.0: cost = true
	if gain and cost:
		return OUT_MIXED
	if cost:
		return OUT_COST
	if gain:
		return OUT_GAIN
	return OUT_NEUTRAL

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
