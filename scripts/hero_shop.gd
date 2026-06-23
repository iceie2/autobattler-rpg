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

var _offers: Array = []
var _card_btns: Array = []
var _panel: Panel

func _ready() -> void:
	_build_ui()

func open(gold: int) -> void:
	_offers.clear()
	_generate_offers()
	_refresh_cards(gold)
	visible = true

func _generate_offers() -> void:
	var classes  := UnitFactory.get_all_classes()
	var elements := UnitFactory.get_all_elements()
	var used: Array = []
	while _offers.size() < 3:
		var cls: UnitBase.UnitClass  = classes[randi() % classes.size()]
		var elem: UnitBase.Element   = elements[randi() % elements.size()]
		var key := "%d_%d" % [cls, elem]
		if key not in used:
			used.append(key)
			_offers.append({"class": cls, "element": elem})

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.78)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# Large panel — takes up most of the viewport
	_panel = Panel.new()
	_panel.size = Vector2(1360, 710)
	_panel.add_theme_stylebox_override("panel",
		_flat(Color(0.08, 0.09, 0.14, 0.99), Color(0.45, 0.4, 0.65), 2, 12))
	overlay.add_child(_panel)

	# ── Title ─────────────────────────────────────────────────────────────────
	_lbl(_panel, "CHOOSE A HERO", 30, Color(0.85, 0.85, 1.0),
		Vector2(0, 18), Vector2(1360, 44), true)
	_lbl(_panel, "Click a hero to recruit them · %dg each · You can buy more next round." % HERO_COST,
		14, Color(1.0, 0.82, 0.3, 0.85), Vector2(0, 62), Vector2(1360, 26), true)

	# ── Three full-card buttons ────────────────────────────────────────────────
	var card_w := 420.0
	var card_h := 560.0
	var gap    := 20.0
	var start_x := (1360.0 - 3 * card_w - 2 * gap) / 2.0

	for i in range(3):
		var x := start_x + i * (card_w + gap)
		var card := _build_card(Vector2(x, 96), Vector2(card_w, card_h), i)
		_panel.add_child(card)
		_card_btns.append(card)

	# ── Cancel ────────────────────────────────────────────────────────────────
	var cancel := _btn("Cancel", Rect2(580, 666, 200, 40))
	cancel.pressed.connect(_on_cancel)
	_panel.add_child(cancel)

	visible = false
	_center_panel()

func _build_card(pos: Vector2, sz: Vector2, idx: int) -> Button:
	var btn := Button.new()
	btn.position = pos
	btn.size     = sz
	btn.text     = ""   # content provided by child nodes
	btn.add_theme_stylebox_override("normal",
		_flat(Color(0.1, 0.1, 0.18, 1.0),  Color(0.3, 0.3, 0.5), 1, 10))
	btn.add_theme_stylebox_override("hover",
		_flat(Color(0.16, 0.16, 0.28, 1.0), Color(0.65, 0.6, 1.0), 2, 10))
	btn.add_theme_stylebox_override("pressed",
		_flat(Color(0.08, 0.08, 0.15, 1.0), Color(0.45, 0.4, 0.75), 2, 10))
	btn.pressed.connect(_on_choose.bind(idx))

	# Portrait background
	var pbg := ColorRect.new()
	pbg.position = Vector2((sz.x - 200) / 2, 20)
	pbg.size     = Vector2(200, 200)
	pbg.color    = Color(0.06, 0.06, 0.11)
	pbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(pbg)

	# Portrait sprite
	var portrait := TextureRect.new()
	portrait.position    = pbg.position
	portrait.size        = pbg.size
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.name = "Portrait"
	btn.add_child(portrait)

	# Class name
	var name_lbl := _child_lbl(btn, "", 24, Color.WHITE,
		Vector2(0, 232), Vector2(sz.x, 34), true)
	name_lbl.name = "NameLbl"

	# Element
	var elem_lbl := _child_lbl(btn, "", 16, Color(0.7, 0.7, 0.85),
		Vector2(0, 268), Vector2(sz.x, 26), true)
	elem_lbl.name = "ElemLbl"

	# Divider
	var div := ColorRect.new()
	div.position = Vector2(20, 302)
	div.size     = Vector2(sz.x - 40, 2)
	div.color    = Color(0.3, 0.3, 0.45, 0.6)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(div)

	# Stats block
	var stat_lbl := _child_lbl(btn, "", 15, Color(0.78, 0.78, 0.92),
		Vector2(20, 316), Vector2(sz.x - 40, 60))
	stat_lbl.name = "StatLbl"

	# Skill label
	var skill_hdr := _child_lbl(btn, "SKILL", 12, Color(0.5, 0.55, 0.7),
		Vector2(20, 392), Vector2(sz.x - 40, 20))
	var skill_lbl := _child_lbl(btn, "", 16, Color(1.0, 0.85, 0.35),
		Vector2(20, 414), Vector2(sz.x - 40, 26))
	skill_lbl.name = "SkillLbl"
	var skill_desc := _child_lbl(btn, "", 12, Color(0.65, 0.65, 0.78),
		Vector2(20, 442), Vector2(sz.x - 40, 80))
	skill_desc.name   = "SkillDesc"
	skill_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	return btn

func _refresh_cards(gold: int) -> void:
	for i in range(_card_btns.size()):
		var btn: Button = _card_btns[i]
		var offer: Dictionary = _offers[i]
		var cls:  UnitBase.UnitClass = offer["class"]
		var elem: UnitBase.Element   = offer["element"]
		var stats: Dictionary = UnitFactory.CLASS_BASE_STATS.get(cls, {})
		var elem_col := _elem_color(elem)

		# Portrait
		var folder: String = SPRITE_FOLDERS.get(cls, "warrior")
		var sheet := load("res://assets/sprites/generated/%s/0/single.png" % folder) as Texture2D
		var portrait := btn.get_node("Portrait") as TextureRect
		if sheet and portrait:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet; atlas.region = IDLE_FRAME
			portrait.texture = atlas

		# Name & element
		(btn.get_node("NameLbl") as Label).text = _class_name(cls)
		(btn.get_node("NameLbl") as Label).add_theme_color_override("font_color", elem_col)
		(btn.get_node("ElemLbl") as Label).text = _elem_name(elem)
		(btn.get_node("ElemLbl") as Label).add_theme_color_override("font_color", elem_col.lightened(0.3))

		# Stats
		if stats.size() > 0:
			var atk: int = stats.get("str", 0) + int(stats.get("dex", 0) * 0.5)
			(btn.get_node("StatLbl") as Label).text = (
				"HP: %-6d  MP: %-6d\nATK: %-5d  SPD: %-3d  RNG: %d" % [
				stats.get("hp", 0), stats.get("mana", 0),
				atk, stats.get("move", 0), stats.get("range", 0)]
			)

		# Skill
		var tmp := UnitFactory.create_unit(cls, elem, true)
		(btn.get_node("SkillLbl") as Label).text = tmp.skill_name if tmp.skill_name != "" else "—"
		(btn.get_node("SkillDesc") as Label).text = _skill_short_desc(tmp)
		tmp.free()

		btn.disabled = gold < HERO_COST

func _skill_short_desc(unit: UnitBase) -> String:
	if unit.skill_name == "":
		return ""
	var parts: Array[String] = []
	if unit.skill_damage_multiplier > 0:
		parts.append("%.0f%% DMG" % (unit.skill_damage_multiplier * 100))
	if unit.skill_range > 0:
		parts.append("RNG %d" % unit.skill_range)
	if unit.skill_cooldown_max > 0:
		parts.append("every %d turns" % unit.skill_cooldown_max)
	if unit.skill_mana_cost > 0:
		parts.append("%d MP" % unit.skill_mana_cost)
	return " · ".join(parts)

func _on_choose(idx: int) -> void:
	var offer: Dictionary = _offers[idx]
	hero_chosen.emit(offer["class"], offer["element"])
	visible = false

func _on_cancel() -> void:
	cancelled.emit()
	visible = false

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_panel.position = (vp - _panel.size) / 2.0

# ── Helpers ───────────────────────────────────────────────────────────────────
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
		UnitBase.Element.FIRE:      return Color(1.0, 0.45, 0.1)
		UnitBase.Element.WATER:     return Color(0.3, 0.7,  1.0)
		UnitBase.Element.EARTH:     return Color(0.75, 0.55, 0.25)
		UnitBase.Element.AIR:       return Color(0.75, 1.0,  1.0)
		UnitBase.Element.LIGHTNING: return Color(1.0,  1.0,  0.25)
		_:                          return Color(0.85, 0.85, 0.92)

func _lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos; l.size = size
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _child_lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := _lbl(parent, text, sz, col, pos, size, center)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _btn(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text; b.position = rect.position; b.size = rect.size
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	b.add_theme_stylebox_override("normal",  _flat(Color(0.14, 0.14, 0.22), Color(0.4, 0.4, 0.55), 1, 6))
	b.add_theme_stylebox_override("hover",   _flat(Color(0.22, 0.22, 0.33), Color(0.6, 0.6, 0.8),  1, 6))
	b.add_theme_stylebox_override("pressed", _flat(Color(0.1,  0.1,  0.18), Color(0.3, 0.3, 0.5),  1, 6))
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
