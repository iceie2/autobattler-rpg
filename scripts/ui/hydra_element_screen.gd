extends CanvasLayer
class_name HydraElementScreen

# Pick-1-of-6 element screen shown once at the start of wave 80 (the Hydra
# encounter) — the player chooses which element the Hydra fights as. It's a
# matchup/strategy call, not a difficulty toggle: the Hydra hits just as hard
# whichever element gets picked (see WaveScaler.boss_code_for). Mirrors
# RelicScreen's shell (overlay + centered panel), simplified to a plain
# button grid since there's no card art here.

signal chosen(element: int)

# Widened/heightened 2026-07-24 (user report) — 6 buttons at 110w/18-sep
# summed to 750px, leaving only 5px margin inside a 760px panel (buttons
# nearly touching the border); bottom margin was similarly cramped.
# 2026-09-27 screen audit: cards were a coloured box with one word — no icon
# and no hint what the pick changes. Wider cards now carry the element icon and
# the actual rule (Balance.AFFINITY_* — stated, not summarised, because the
# +50 attack and +25 block roughly cancel; a "strong vs" line would be wrong).
const PANEL_W := 1260.0
const PANEL_H := 640.0
const BTN_W   := 180.0
const BTN_H   := 450.0

const ELEMENT_NAMES := {
	UnitBase.Element.NORMAL:    "Normal",
	UnitBase.Element.FIRE:      "Fire",
	UnitBase.Element.WATER:     "Water",
	UnitBase.Element.EARTH:     "Earth",
	UnitBase.Element.AIR:       "Air",
	UnitBase.Element.LIGHTNING: "Lightning",
}
const ELEMENT_COLORS := {
	UnitBase.Element.NORMAL:    Color(0.6, 0.6, 0.6),
	UnitBase.Element.FIRE:      Color(1.0, 0.2, 0.0),
	UnitBase.Element.WATER:     Color(0.0, 0.7, 1.0),
	UnitBase.Element.EARTH:     Color(0.55, 0.35, 0.2),
	UnitBase.Element.AIR:       Color(0.8, 1.0, 1.0),
	UnitBase.Element.LIGHTNING: Color(1.0, 1.0, 0.0),
}
# Order matches every other elemental-variant sprite sheet in the project.
const ELEMENT_ORDER: Array = [
	UnitBase.Element.NORMAL, UnitBase.Element.FIRE, UnitBase.Element.WATER,
	UnitBase.Element.EARTH, UnitBase.Element.AIR, UnitBase.Element.LIGHTNING,
]

var _panel:    Panel
var _btn_row:  HBoxContainer

func _ready() -> void:
	_build_ui()
	visible = false

func present() -> void:
	visible = true
	_center_panel()

func _make_button(element: int) -> Button:
	var col: Color = ELEMENT_COLORS[element]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(BTN_W, BTN_H)
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE

	var bg_base: Color = col.darkened(0.82)
	btn.add_theme_stylebox_override("normal",  _flat(bg_base, col, 3, 12))
	btn.add_theme_stylebox_override("hover",   _flat(bg_base.lightened(0.10), col.lightened(0.25), 4, 12))
	btn.add_theme_stylebox_override("pressed", _flat(bg_base.darkened(0.15), col.lightened(0.1), 4, 12))
	btn.add_theme_stylebox_override("focus",   _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12))

	var icon := TextureRect.new()
	icon.texture = load(UnitFactory.ELEMENT_ICONS.get(element, "")) as Texture2D
	icon.position = Vector2((BTN_W - 64) / 2.0, 18)
	icon.size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)

	var name: String = ELEMENT_NAMES[element]
	_lbl(btn, name, 20, col.lightened(0.15), Vector2(0, 88), Vector2(BTN_W, 32), true)

	var rule := Label.new()
	rule.text = HydraKit.MOVE_NAMES[element] + "\n" + HydraKit.SUMMARIES[element] + "\n\nYour %s heroes:\n+%d%% damage to it\n\nIt blocks %s:\n+%d defence" % [
		name, int(Balance.AFFINITY_OWN_OFF_BONUS), name, int(Balance.AFFINITY_OWN_DEF_BONUS)]
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_read_font(rule, UITheme.FONT_BODY)
	rule.add_theme_color_override("font_color", Color(0.86, 0.86, 0.92))
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(rule)
	# Size AFTER parenting: set before, the wrap width wasn't honoured and the
	# text ran past the card edge.
	rule.custom_minimum_size = Vector2(BTN_W - 20, 0)
	rule.position = Vector2(10, 124)
	rule.size = Vector2(BTN_W - 20, BTN_H - 130)

	btn.pressed.connect(_on_pick.bind(element))
	return btn

func _on_pick(element: int) -> void:
	visible = false
	chosen.emit(element)

# ── UI shell (built once) ─────────────────────────────────────────────────────
func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color        = Color(0, 0, 0, 0.82)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.add_theme_stylebox_override("panel", UITheme.menu_surface_box())
	overlay.add_child(_panel)
	UITheme.menu_header(_panel, Rect2(14, 8, PANEL_W - 28, 108))

	_lbl(_panel, "CHOOSE THE HYDRA'S ELEMENT", 28, UITheme.menu_title_color(),
		Vector2(0, 29), Vector2(PANEL_W, 38), true)
	_lbl(_panel, "Wave 80 — sever all three heads to win. Choose the elemental move your team can handle.", 14, UITheme.menu_subtitle_color(),
		Vector2(0, 66), Vector2(PANEL_W, 24), true)

	_btn_row = HBoxContainer.new()
	_btn_row.add_theme_constant_override("separation", 16)
	_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_row.position  = Vector2(0, 138)
	_btn_row.size      = Vector2(PANEL_W, BTN_H)
	_panel.add_child(_btn_row)

	for element in ELEMENT_ORDER:
		_btn_row.add_child(_make_button(element))

	_center_panel()

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_panel.position = (vp - _panel.size) / 2.0

# ── Small helpers (mirrors relic_screen) ──────────────────────────────────────
func _flat(bg: Color, border: Color, bw: float, radius: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(int(bw))
	s.set_corner_radius_all(int(radius))
	return s

func _lbl(parent: Control, text: String, size: int, color: Color,
		pos: Vector2, sz: Vector2, centered: bool = false) -> Label:
	var l := Label.new()
	l.text     = text
	l.position = pos
	l.size     = sz
	UITheme.apply_font(l, UITheme.body_font(size))
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
