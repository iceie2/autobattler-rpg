extends CanvasLayer
class_name CrystalShop

signal closed()

var _wallet_lbl: Label
var _cards: Array = []   # one Panel per upgrade

func _ready() -> void:
	_build_ui()

func open() -> void:
	_refresh()
	visible = true

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)

	# Main panel — grows to fit all upgrade cards
	var card_h    := 180.0
	var padding   := 20.0
	var panel_h   := 130.0 + len(Progression.UPGRADES) * (card_h + 12) + 60.0
	var panel     := Panel.new()
	panel.size    = Vector2(680, panel_h)
	panel.add_theme_stylebox_override("panel",
		_flat(Color(0.08, 0.09, 0.14, 0.98), Color(0.35, 0.55, 0.85), 2, 10))
	overlay.add_child(panel)
	_center(panel)

	# Title
	_lbl(panel, "✦  CRYSTAL SHOP  ✦", 22, Color(0.55, 0.8, 1.0),
		Vector2(0, 16), Vector2(680, 36), true)
	_lbl(panel, "Upgrades persist between runs.", 12, Color(0.5, 0.6, 0.75, 0.8),
		Vector2(0, 52), Vector2(680, 22), true)

	# Wallet row
	_lbl(panel, "Your Crystals:", 14, Color(0.6, 0.75, 1.0),
		Vector2(30, 82), Vector2(200, 26))
	_wallet_lbl = _lbl(panel, "0", 22, Color(0.4, 0.85, 1.0),
		Vector2(230, 78), Vector2(120, 30))

	var sep := HSeparator.new()
	sep.position = Vector2(0, 114); sep.size = Vector2(680, 4)
	panel.add_child(sep)

	# One card per upgrade
	var cy := 126.0
	for upgrade in Progression.UPGRADES:
		var card := _build_card(panel, upgrade, cy)
		_cards.append({"panel": card, "key": upgrade["key"]})
		cy += card_h + 12

	# Close
	var close_btn := _btn("✕  Close", Rect2(240, cy + 4, 200, 40))
	close_btn.pressed.connect(_close)
	panel.add_child(close_btn)

	visible = false

func _build_card(parent: Node, upgrade: Dictionary, y: float) -> Panel:
	var card := Panel.new()
	card.position = Vector2(20, y)
	card.size     = Vector2(640, 178)
	card.add_theme_stylebox_override("panel",
		_flat(Color(0.1, 0.12, 0.2, 1.0), Color(0.3, 0.45, 0.7), 1, 6))
	parent.add_child(card)

	# Upgrade name
	var name_lbl := _lbl(card, upgrade["name"], 18, Color(0.9, 0.9, 1.0),
		Vector2(14, 12), Vector2(400, 28))
	name_lbl.name = "NameLbl"

	# Max level badge
	var max_lbl := _lbl(card, "MAX LV %d" % upgrade["max_level"],
		11, Color(0.5, 0.55, 0.65), Vector2(490, 16), Vector2(140, 20), true)

	# Level bar
	var bar_bg := ColorRect.new()
	bar_bg.position = Vector2(14, 46)
	bar_bg.size     = Vector2(612, 12)
	bar_bg.color    = Color(0.12, 0.15, 0.25)
	card.add_child(bar_bg)

	var bar_fill := ColorRect.new()
	bar_fill.position = Vector2(14, 46)
	bar_fill.size     = Vector2(0, 12)   # updated in _refresh_card
	bar_fill.color    = Color(0.35, 0.7, 1.0)
	bar_fill.name     = "BarFill"
	card.add_child(bar_fill)

	# Level text
	var level_lbl := _lbl(card, "Level 0 / %d" % upgrade["max_level"],
		12, Color(0.65, 0.72, 0.88), Vector2(14, 62), Vector2(300, 20))
	level_lbl.name = "LevelLbl"

	# Description
	_lbl(card, upgrade["desc"], 13, Color(0.7, 0.75, 0.85),
		Vector2(14, 86), Vector2(612, 22))

	# Current effect
	var effect_lbl := _lbl(card, "", 13, Color(0.4, 0.85, 1.0),
		Vector2(14, 110), Vector2(440, 22))
	effect_lbl.name = "EffectLbl"

	# Cost label
	var cost_lbl := _lbl(card, "", 13, Color(0.9, 0.85, 0.3),
		Vector2(14, 134), Vector2(440, 22))
	cost_lbl.name = "CostLbl"

	# Buy button
	var buy_btn := _btn("Upgrade", Rect2(480, 108, 148, 58))
	buy_btn.name = "BuyBtn"
	buy_btn.pressed.connect(_on_buy.bind(upgrade["key"]))
	card.add_child(buy_btn)

	return card

func _refresh() -> void:
	_wallet_lbl.text = "%d" % Progression.crystals
	for entry in _cards:
		_refresh_card(entry["panel"], entry["key"])

func _refresh_card(card: Panel, key: String) -> void:
	var upgrade := Progression._find(key)
	if upgrade.is_empty():
		return

	var lvl     := Progression.get_level(key)
	var max_lvl := int(upgrade["max_level"])
	var cost    := Progression.next_cost(key)
	var bonus   := Progression.get_bonus(key)
	var bar_w   := 612.0 * (float(lvl) / max_lvl)

	(card.get_node("BarFill") as ColorRect).size.x = bar_w
	(card.get_node("LevelLbl") as Label).text = "Level %d / %d" % [lvl, max_lvl]

	var eff_fmt: String = upgrade.get("effect", "%d")
	(card.get_node("EffectLbl") as Label).text = "Current: " + (eff_fmt % bonus)

	var cost_lbl := card.get_node("CostLbl") as Label
	var buy_btn  := card.get_node("BuyBtn")  as Button
	if cost < 0:
		cost_lbl.text    = "MAXED OUT"
		cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4))
		buy_btn.disabled = true
		buy_btn.text     = "Maxed"
	else:
		cost_lbl.text    = "Next level: %d ✦" % cost
		cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.3))
		buy_btn.disabled = not Progression.can_afford(key)
		buy_btn.text     = "Upgrade"

func _on_buy(key: String) -> void:
	if Progression.buy(key):
		_refresh()

func _close() -> void:
	visible = false
	closed.emit()

func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_close()

func _center(control: Control) -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	control.position = (vp - control.size) / 2.0

func _lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos; l.size = size
	l.add_theme_font_size_override("font_size", UITheme.body_font(sz))
	l.add_theme_color_override("font_color", col)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _btn(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text; b.position = rect.position; b.size = rect.size
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	b.add_theme_stylebox_override("normal",  _flat(Color(0.15, 0.2,  0.35), Color(0.35, 0.55, 0.85), 1, 5))
	b.add_theme_stylebox_override("hover",   _flat(Color(0.2,  0.28, 0.48), Color(0.5,  0.72, 1.0),  1, 5))
	b.add_theme_stylebox_override("pressed", _flat(Color(0.1,  0.14, 0.25), Color(0.25, 0.4,  0.65), 1, 5))
	b.add_theme_stylebox_override("disabled",_flat(Color(0.1,  0.12, 0.2),  Color(0.25, 0.3,  0.45), 1, 5))
	return b

func _flat(bg: Color, border: Color = Color.TRANSPARENT,
		bw: int = 0, radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.border_width_left = bw; s.border_width_right = bw
	s.border_width_top = bw;  s.border_width_bottom = bw
	s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius; s.corner_radius_bottom_right = radius
	return s
