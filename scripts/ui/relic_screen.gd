extends CanvasLayer
class_name RelicScreen

# Forced pick-1-of-3 relic screen shown at the start of waves 1 / 11 / 21.
# Mirrors the gacha-card look of the hero shop / level-up screen: each card is
# tinted by its rolled grade colour, with a grade badge in the corner.

signal chosen(relic)

const PANEL_W := 1000.0
const PANEL_H := 520.0
const CARD_W  := 290.0
const CARD_H  := 360.0

var _panel:     Panel
var _sub_lbl:   Label
var _card_row:  HBoxContainer

func _ready() -> void:
	_build_ui()
	visible = false

func present(offers: Array, wave: int) -> void:
	visible = true
	_sub_lbl.text = "Wave %d  ·  choose a relic — it lasts the rest of your run" % wave
	for c in _card_row.get_children():
		c.queue_free()
	for relic in offers:
		_card_row.add_child(_make_card(relic))
	_center_panel()

# ── Card builder ──────────────────────────────────────────────────────────────
func _make_card(relic: Dictionary) -> Button:
	var grade: String = relic.get("grade", "D")
	var grade_col: Color = Relic.grade_color(grade)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
	btn.text = ""

	var bg_base: Color = grade_col.darkened(0.82)
	btn.add_theme_stylebox_override("normal",  _flat(bg_base, grade_col, 3, 12))
	btn.add_theme_stylebox_override("hover",   _flat(bg_base.lightened(0.10), grade_col.lightened(0.25), 4, 12))
	btn.add_theme_stylebox_override("pressed", _flat(bg_base.darkened(0.15), grade_col.lightened(0.1), 4, 12))
	btn.add_theme_stylebox_override("focus",   _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12))

	# Grade badge (top-right)
	var badge_bg := ColorRect.new()
	badge_bg.position = Vector2(CARD_W - 46, 12)
	badge_bg.size     = Vector2(34, 34)
	badge_bg.color    = grade_col.darkened(0.4)
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(badge_bg)
	var badge_lbl := Label.new()
	badge_lbl.text = grade
	badge_lbl.position = badge_bg.position
	badge_lbl.size     = badge_bg.size
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	badge_lbl.add_theme_font_size_override("font_size", 20)
	badge_lbl.add_theme_color_override("font_color", grade_col)
	badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(badge_lbl)

	# "RELIC" kicker
	_lbl(btn, "RELIC", 11, Color(0.55, 0.55, 0.72), Vector2(0, 22), Vector2(CARD_W, 16), true)

	# Icon (centered, above the name)
	var icon_path: String = Relic.icon_path(relic)
	if icon_path != "":
		var icon := TextureRect.new()
		icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture      = load(icon_path) as Texture2D
		icon.position     = Vector2((CARD_W - 80) / 2.0, 44)
		icon.size         = Vector2(80, 80)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon)

	# Name (grade coloured, big)
	_lbl(btn, relic.get("name", "Relic"), 24, grade_col, Vector2(0, 130), Vector2(CARD_W, 34), true)

	# Divider
	var div := ColorRect.new()
	div.position = Vector2(28, 162)
	div.size     = Vector2(CARD_W - 56, 1)
	div.color    = Color(grade_col.r, grade_col.g, grade_col.b, 0.4)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(div)

	# Description (wrapped)
	var desc := Label.new()
	desc.position             = Vector2(24, 182)
	desc.size                 = Vector2(CARD_W - 48, 140)
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.82, 0.82, 0.92))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	desc.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	desc.text                 = relic.get("desc", "")
	btn.add_child(desc)

	btn.pressed.connect(_on_pick.bind(relic))
	return btn

func _on_pick(relic: Dictionary) -> void:
	visible = false
	chosen.emit(relic)

# ── UI shell (built once) ─────────────────────────────────────────────────────
func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color        = Color(0, 0, 0, 0.82)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	# UI theme pass 2026-07-04: dobo card panel instead of flat navy box —
	# matches hero_shop/level_up_screen (this screen's own header comment
	# already says it mirrors their gacha-card look, this was just missed
	# in the original pass).
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	overlay.add_child(_panel)

	_lbl(_panel, "CHOOSE A RELIC", 30, Color(1.0, 0.88, 0.45),
		Vector2(0, 22), Vector2(PANEL_W, 42), true)
	_sub_lbl = _lbl(_panel, "", 14, Color(0.75, 0.75, 0.85),
		Vector2(0, 62), Vector2(PANEL_W, 24), true)

	_card_row = HBoxContainer.new()
	_card_row.add_theme_constant_override("separation", 22)
	_card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_row.position  = Vector2(0, 110)
	_card_row.size      = Vector2(PANEL_W, CARD_H)
	_panel.add_child(_card_row)

	_center_panel()

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_panel.position = (vp - _panel.size) / 2.0

# ── Small helpers (mirrors level_up_screen) ───────────────────────────────────
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
	l.add_theme_font_size_override("font_size", UITheme.body_font(size))
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
