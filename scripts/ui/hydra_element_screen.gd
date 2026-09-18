extends CanvasLayer
class_name HydraElementScreen

# Pick-1-of-6 element screen shown once at the start of wave 30 (the Hydra
# finale) — the player chooses which element the Hydra fights as. It's a
# matchup/strategy call, not a difficulty toggle: the Hydra hits just as hard
# whichever element gets picked (see WaveScaler.boss_code_for). Mirrors
# RelicScreen's shell (overlay + centered panel), simplified to a plain
# button grid since there's no card art here.

signal chosen(element: int)

# Widened/heightened 2026-07-24 (user report) — 6 buttons at 110w/18-sep
# summed to 750px, leaving only 5px margin inside a 760px panel (buttons
# nearly touching the border); bottom margin was similarly cramped.
const PANEL_W := 840.0
const PANEL_H := 360.0
const BTN_W   := 110.0
const BTN_H   := 140.0

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

	var bg_base: Color = col.darkened(0.82)
	btn.add_theme_stylebox_override("normal",  _flat(bg_base, col, 3, 12))
	btn.add_theme_stylebox_override("hover",   _flat(bg_base.lightened(0.10), col.lightened(0.25), 4, 12))
	btn.add_theme_stylebox_override("pressed", _flat(bg_base.darkened(0.15), col.lightened(0.1), 4, 12))
	btn.add_theme_stylebox_override("focus",   _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12))

	_lbl(btn, ELEMENT_NAMES[element], 20, col, Vector2(0, BTN_H / 2.0 - 14), Vector2(BTN_W, 28), true)

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
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	overlay.add_child(_panel)

	_lbl(_panel, "CHOOSE THE HYDRA'S ELEMENT", 28, Color(1.0, 0.88, 0.45),
		Vector2(0, 22), Vector2(PANEL_W, 38), true)
	_lbl(_panel, "The final boss — it hits just as hard whichever you pick.", 14, Color(0.75, 0.75, 0.85),
		Vector2(0, 60), Vector2(PANEL_W, 24), true)

	_btn_row = HBoxContainer.new()
	_btn_row.add_theme_constant_override("separation", 18)
	_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_row.position  = Vector2(0, 130)
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
