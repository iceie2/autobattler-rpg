extends CanvasLayer
class_name RoundRewardScreen

signal done

const PANEL_W := 1060.0
const PANEL_H := 560.0
const UNIT_ICON := 72.0

var _panel: Panel
var _title_lbl: Label
var _sub_lbl: Label
var _unit_grid: GridContainer
var _chosen_perk: Dictionary = {}

func _ready() -> void:
	_build_ui()
	visible = false

# The perk is already fully rolled (see RoundReward.roll) and was already shown
# in full on the difficulty panel before the player committed — no separate
# "pick 1 of 3" step here, since that would let the preview lie about the
# reward. The only choice left is which unit receives it.
func present(reward: Dictionary, player_units: Array) -> void:
	_chosen_perk = reward.get("perk", {})
	visible = true
	_show_unit_step(player_units)

# ── Choose which unit receives the (already-rolled) bonus ────────────────────
func _show_unit_step(player_units: Array) -> void:
	_title_lbl.text = "ROUND REWARD — STAT BONUS"
	var v: float = _chosen_perk.get("rolled_value", _chosen_perk.get("value", 0))
	var value_str: String = ("+%.2f" % v) if _chosen_perk.get("id", "") in ["aspd", "regen"] else ("+%d" % int(v))
	_sub_lbl.text = "Who receives %s %s?" % [value_str, _chosen_perk.get("label", "?")]
	_unit_grid.visible = true

	for c in _unit_grid.get_children():
		c.queue_free()

	for unit in player_units:
		if not (unit and is_instance_valid(unit)):
			continue
		_unit_grid.add_child(_make_unit_card(unit))

func _make_unit_card(unit: UnitBase) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(140, 170)
	btn.text = ""
	btn.add_theme_stylebox_override("normal", _flat(Color(0.10, 0.09, 0.16, 0.98), Color(0.35, 0.35, 0.5), 2, 10))
	btn.add_theme_stylebox_override("hover", _flat(Color(0.18, 0.16, 0.26, 1.0), Color(0.83, 0.69, 0.22), 3, 10))
	btn.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10))

	var portrait := TextureRect.new()
	portrait.position = Vector2((140 - UNIT_ICON) / 2.0, 10)
	portrait.size = Vector2(UNIT_ICON, UNIT_ICON)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sprite_path: String = VisualUnit.HERO_SPRITE_PATHS.get(unit.unit_class, "")
	if sprite_path != "":
		var tex := load(sprite_path) as Texture2D
		if tex:
			portrait.texture = tex
	btn.add_child(portrait)

	_lbl(btn, unit.unit_name, 15, Color(0.90, 0.90, 1.0), Vector2(4, 86), Vector2(132, 20), true)
	_lbl(btn, "Lv.%d" % unit.level, 13, Color(0.83, 0.69, 0.22), Vector2(4, 108), Vector2(132, 18), true)

	btn.pressed.connect(_on_unit_chosen.bind(unit))
	return btn

func _on_unit_chosen(unit: UnitBase) -> void:
	if unit and is_instance_valid(unit):
		LevelUpScreen.apply_perk_to_unit(unit, _chosen_perk)
	visible = false
	done.emit()

# ── UI shell ────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.82)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	# UI theme pass 2026-07-04: dobo card panel, gold-tinted for the reward vibe.
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box_tinted(Color(1.15, 1.05, 0.85)))
	overlay.add_child(_panel)

	_title_lbl = Label.new()
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 30)
	_title_lbl.add_theme_color_override("font_color", Color(0.83, 0.69, 0.22))
	_title_lbl.position = Vector2(0, 20)
	_title_lbl.size = Vector2(PANEL_W, 36)
	_panel.add_child(_title_lbl)

	_sub_lbl = Label.new()
	_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_lbl.add_theme_font_size_override("font_size", 16)
	_sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	_sub_lbl.position = Vector2(0, 58)
	_sub_lbl.size = Vector2(PANEL_W, 26)
	_panel.add_child(_sub_lbl)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 110)
	scroll.size = Vector2(PANEL_W - 40, PANEL_H - 130)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	_unit_grid = GridContainer.new()
	_unit_grid.columns = 6
	_unit_grid.add_theme_constant_override("h_separation", 12)
	_unit_grid.add_theme_constant_override("v_separation", 12)
	_unit_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_unit_grid)

	_center_panel()

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1800, 1080)
	_panel.position = (vp - _panel.size) / 2.0

func _lbl(parent: Node, text: String, sz: int, col: Color, pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", UITheme.body_font(sz))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _flat(bg: Color, border: Color = Color.TRANSPARENT, bw: int = 0, radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = bw; s.border_width_right = bw
	s.border_width_top = bw; s.border_width_bottom = bw
	s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius; s.corner_radius_bottom_right = radius
	return s
