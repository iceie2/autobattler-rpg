extends CanvasLayer
class_name HeroShop

signal hero_chosen(unit_class: UnitBase.UnitClass, element: UnitBase.Element)
signal cancelled()

const HERO_COST := 20
const SPRITE_FOLDERS := {
	UnitBase.UnitClass.WARRIOR:    "warrior",
	UnitBase.UnitClass.RANGER:     "archer",
	UnitBase.UnitClass.MONK:       "monk",
	UnitBase.UnitClass.THIEF:      "thief",
	UnitBase.UnitClass.BLACK_MAGE: "black_mage",
	UnitBase.UnitClass.WHITE_MAGE: "white_mage",
	UnitBase.UnitClass.RED_MAGE:   "red_mage",
	UnitBase.UnitClass.BLOODHOUND: "warrior",
	UnitBase.UnitClass.BOUNCER:    "monk",
	UnitBase.UnitClass.HEADHUNTER: "archer",
}
const IDLE_FRAME := Rect2(0, 640, 64, 64)

var _offers: Array = []   # [{class, element}, ...]
var _cards: Array = []
var _panel: Panel

func _ready() -> void:
	_build_ui()

func open(gold: int) -> void:
	_offers.clear()
	_generate_offers()
	_refresh_cards(gold)
	visible = true

func _generate_offers() -> void:
	var classes := UnitFactory.get_all_classes()
	var elements := UnitFactory.get_all_elements()
	# Pick 3 unique class+element combos
	var used: Array = []
	while _offers.size() < 3:
		var cls: UnitBase.UnitClass = classes[randi() % classes.size()]
		var elem: UnitBase.Element  = elements[randi() % elements.size()]
		var key := str(cls) + "_" + str(elem)
		if key not in used:
			used.append(key)
			_offers.append({"class": cls, "element": elem})

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = Vector2(740, 360)
	_panel.add_theme_stylebox_override("panel",
		_flat(Color(0.09, 0.09, 0.15, 0.98), Color(0.5, 0.45, 0.7), 2, 10))
	overlay.add_child(_panel)

	_lbl(_panel, "CHOOSE A HERO", 20, Color(0.85, 0.85, 1.0),
		Vector2(0, 14), Vector2(740, 34), true)
	_lbl(_panel, "Cost: %d gold  ·  Choose wisely — you can buy more next round." % HERO_COST,
		12, Color(1.0, 0.82, 0.3, 0.85), Vector2(0, 48), Vector2(740, 24), true)

	# 3 card slots
	var card_w := 210.0
	var gap    := 20.0
	var start_x := (740 - 3 * card_w - 2 * gap) / 2.0
	for i in range(3):
		var card := _build_card(Vector2(start_x + i * (card_w + gap), 80), card_w, i)
		_panel.add_child(card)
		_cards.append(card)

	# Cancel button
	var cancel := _btn("Cancel", Rect2(290, 314, 160, 36))
	cancel.pressed.connect(_on_cancel)
	_panel.add_child(cancel)

	visible = false
	_center_panel()

func _build_card(pos: Vector2, width: float, idx: int) -> Panel:
	var card := Panel.new()
	card.position = pos
	card.size = Vector2(width, 224)
	card.add_theme_stylebox_override("panel",
		_flat(Color(0.12, 0.12, 0.2, 1.0), Color(0.4, 0.4, 0.6), 1, 6))
	card.set_meta("idx", idx)

	# Sprite portrait
	var portrait_bg := ColorRect.new()
	portrait_bg.position = Vector2(55, 8)
	portrait_bg.size = Vector2(100, 100)
	portrait_bg.color = Color(0.07, 0.07, 0.12)
	portrait_bg.name = "PortraitBg"
	card.add_child(portrait_bg)

	var portrait := TextureRect.new()
	portrait.position = Vector2(55, 8)
	portrait.size = Vector2(100, 100)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.name = "Portrait"
	card.add_child(portrait)

	var name_lbl := Label.new()
	name_lbl.position = Vector2(0, 114)
	name_lbl.size = Vector2(width, 22)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.name = "NameLbl"
	card.add_child(name_lbl)

	var elem_lbl := Label.new()
	elem_lbl.position = Vector2(0, 134)
	elem_lbl.size = Vector2(width, 20)
	elem_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elem_lbl.add_theme_font_size_override("font_size", 11)
	elem_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.85))
	elem_lbl.name = "ElemLbl"
	card.add_child(elem_lbl)

	var stat_lbl := Label.new()
	stat_lbl.position = Vector2(8, 156)
	stat_lbl.size = Vector2(width - 16, 44)
	stat_lbl.add_theme_font_size_override("font_size", 10)
	stat_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.8))
	stat_lbl.name = "StatLbl"
	card.add_child(stat_lbl)

	var choose_btn := _btn("Choose", Rect2(20, 186, width - 40, 32))
	choose_btn.pressed.connect(_on_choose.bind(idx))
	choose_btn.name = "ChooseBtn"
	card.add_child(choose_btn)

	return card

func _refresh_cards(gold: int) -> void:
	for i in range(_cards.size()):
		var card: Panel = _cards[i]
		var offer: Dictionary = _offers[i]
		var cls: UnitBase.UnitClass  = offer["class"]
		var elem: UnitBase.Element   = offer["element"]

		# Load sprite
		var folder: String = SPRITE_FOLDERS.get(cls, "warrior")
		var sheet := load("res://assets/sprites/generated/%s/0/single.png" % folder) as Texture2D
		var portrait := card.get_node("Portrait") as TextureRect
		if sheet and portrait:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = IDLE_FRAME
			portrait.texture = atlas

		# Stat preview (from factory base stats)
		var stats: Dictionary = UnitFactory.CLASS_BASE_STATS.get(cls, {})

		var name_lbl := card.get_node("NameLbl") as Label
		var elem_col := _elem_color(elem)
		name_lbl.text = _class_name(cls)
		name_lbl.add_theme_color_override("font_color", elem_col)

		var elem_lbl := card.get_node("ElemLbl") as Label
		elem_lbl.text = _elem_name(elem)

		var stat_lbl := card.get_node("StatLbl") as Label
		if stats.size() > 0:
			stat_lbl.text = "HP:%d  MP:%d\nATK:%d  SPD:%d  RNG:%d" % [
				stats.get("hp", 0), stats.get("mana", 0),
				stats.get("str", 0) + int(stats.get("dex", 0) * 0.5),
				stats.get("move", 0), stats.get("range", 0)
			]

		var btn := card.get_node("ChooseBtn") as Button
		btn.disabled = gold < HERO_COST
		btn.text = "Choose  (%dg)" % HERO_COST

func _on_choose(idx: int) -> void:
	var offer: Dictionary = _offers[idx]
	hero_chosen.emit(offer["class"], offer["element"])
	visible = false

func _on_cancel() -> void:
	cancelled.emit()
	visible = false

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1800, 1080)
	_panel.position = (vp - _panel.size) / 2.0

func _class_name(cls: UnitBase.UnitClass) -> String:
	match cls:
		UnitBase.UnitClass.WARRIOR:    return "Warrior"
		UnitBase.UnitClass.RANGER:     return "Ranger"
		UnitBase.UnitClass.MONK:       return "Monk"
		UnitBase.UnitClass.THIEF:      return "Thief"
		UnitBase.UnitClass.BLACK_MAGE: return "Black Mage"
		UnitBase.UnitClass.WHITE_MAGE: return "White Mage"
		UnitBase.UnitClass.RED_MAGE:   return "Red Mage"
		UnitBase.UnitClass.BLOODHOUND: return "Bloodhound"
		UnitBase.UnitClass.BOUNCER:    return "Bouncer"
		UnitBase.UnitClass.HEADHUNTER: return "Headhunter"
		_: return "Unknown"

func _elem_name(elem: UnitBase.Element) -> String:
	match elem:
		UnitBase.Element.FIRE:      return "Fire"
		UnitBase.Element.WATER:     return "Water"
		UnitBase.Element.EARTH:     return "Earth"
		UnitBase.Element.AIR:       return "Air"
		UnitBase.Element.LIGHTNING: return "Lightning"
		_:                          return "Normal"

func _elem_color(elem: UnitBase.Element) -> Color:
	match elem:
		UnitBase.Element.FIRE:      return Color(1.0, 0.4, 0.1)
		UnitBase.Element.WATER:     return Color(0.3, 0.7, 1.0)
		UnitBase.Element.EARTH:     return Color(0.7, 0.55, 0.25)
		UnitBase.Element.AIR:       return Color(0.75, 1.0, 1.0)
		UnitBase.Element.LIGHTNING: return Color(1.0, 1.0, 0.2)
		_:                          return Color(0.85, 0.85, 0.9)

func _lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos; l.size = size
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _btn(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text; b.position = rect.position; b.size = rect.size
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	b.add_theme_stylebox_override("normal",  _flat(Color(0.18, 0.18, 0.28), Color(0.45, 0.45, 0.6), 1, 4))
	b.add_theme_stylebox_override("hover",   _flat(Color(0.26, 0.26, 0.38), Color(0.6, 0.6, 0.8),  1, 4))
	b.add_theme_stylebox_override("pressed", _flat(Color(0.12, 0.12, 0.22), Color(0.3, 0.3, 0.5),  1, 4))
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
