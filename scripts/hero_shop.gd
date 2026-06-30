extends CanvasLayer
class_name HeroShop

signal hero_chosen(unit_class: UnitBase.UnitClass, element: UnitBase.Element, rolls: Dictionary)
signal cancelled()

const HERO_COST := 30

const SPRITE_FOLDERS := {
	UnitBase.UnitClass.WARRIOR:    "warrior",
	UnitBase.UnitClass.RANGER:     "archer",
	UnitBase.UnitClass.MONK:       "monk",
	UnitBase.UnitClass.THIEF:      "thief",
	UnitBase.UnitClass.BLACK_MAGE: "black_mage",
	UnitBase.UnitClass.WHITE_MAGE: "white_mage",
	UnitBase.UnitClass.RED_MAGE:   "red_mage",
	UnitBase.UnitClass.BLOODHOUND: "warrior",
	UnitBase.UnitClass.BOUNCER:    "bouncer",
	UnitBase.UnitClass.HEADHUNTER: "archer",
}
const IDLE_FRAME := Rect2(0, 640, 64, 64)

# Card layout constants
const CARD_W     := 400.0
const CARD_H     := 660.0
const PANEL_W    := 1340.0
const PANEL_H    := 830.0
const PORT_SIZE  := 160.0

var _offers:    Array = []
var _card_btns: Array = []
var _panel:     Panel

func _ready() -> void:
	_build_ui()

func open(gold: int) -> void:
	_offers.clear()
	_card_btns.clear()
	_generate_offers()
	_rebuild_all_cards(gold)
	visible = true

func _generate_offers() -> void:
	var classes  := UnitFactory.get_all_classes()
	var elements := UnitFactory.get_all_elements()
	var used: Array = []
	while _offers.size() < 3:
		var cls:  UnitBase.UnitClass = classes[randi() % classes.size()]
		var elem: UnitBase.Element   = elements[randi() % elements.size()]
		var key := "%d_%d" % [cls, elem]
		if key not in used:
			used.append(key)
			_offers.append({
				"class":   cls,
				"element": elem,
				"rolls":   UnitFactory.generate_recruit_rolls(),
			})

# ── UI shell (built once) ─────────────────────────────────────────────────────
func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.80)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.add_theme_stylebox_override("panel",
		_flat(Color(0.07, 0.07, 0.12, 0.99), Color(0.42, 0.38, 0.62), 2, 14))
	overlay.add_child(_panel)

	_lbl(_panel, "CHOOSE A HERO", 30, Color(0.88, 0.88, 1.0),
		Vector2(0, 18), Vector2(PANEL_W, 44), true)
	_lbl(_panel, "Each hero has unique stat rolls  ·  %dg each  ·  Roll again next round" % HERO_COST,
		13, Color(1.0, 0.82, 0.3, 0.80), Vector2(0, 58), Vector2(PANEL_W, 26), true)

	# Cancel button
	var cancel := _btn("Cancel", Rect2((PANEL_W - 200) / 2.0, PANEL_H - 54, 200, 40))
	cancel.pressed.connect(_on_cancel)
	_panel.add_child(cancel)

	visible = false
	_center_panel()

# Destroy and recreate all three cards (called on open())
func _rebuild_all_cards(gold: int) -> void:
	for old in _card_btns:
		if is_instance_valid(old):
			old.queue_free()
	_card_btns.clear()

	var gap     := 20.0
	var start_x := (PANEL_W - 3 * CARD_W - 2 * gap) / 2.0

	for i in range(3):
		var x    := start_x + i * (CARD_W + gap)
		var card := _build_card(Vector2(x, 86), i, gold)
		_panel.add_child(card)
		_card_btns.append(card)

# Build one fully-populated card button for offer[idx]
func _build_card(pos: Vector2, idx: int, gold: int) -> Button:
	var offer:   Dictionary        = _offers[idx]
	var cls:     UnitBase.UnitClass = offer["class"]
	var elem:    UnitBase.Element   = offer["element"]
	var rolls:   Dictionary        = offer["rolls"]
	var stats_dict: Dictionary     = rolls.get("stats", {})
	var grade:   String            = rolls.get("grade", "B")
	var avg_pct: float             = rolls.get("avg_pct", 0.0)
	var base:    Dictionary        = UnitFactory.CLASS_BASE_STATS.get(cls, {})
	var elem_col := _elem_color(elem)
	var grade_col := _grade_color(grade)

	var btn := Button.new()
	btn.position = pos
	btn.size     = Vector2(CARD_W, CARD_H)
	btn.text     = ""
	btn.add_theme_stylebox_override("normal",
		_flat(Color(0.09, 0.09, 0.16, 1.0), Color(0.28, 0.28, 0.48), 1, 10))
	btn.add_theme_stylebox_override("hover",
		_flat(Color(0.15, 0.15, 0.26, 1.0), grade_col.darkened(0.1), 2, 10))
	btn.add_theme_stylebox_override("pressed",
		_flat(Color(0.07, 0.07, 0.13, 1.0), Color(0.4, 0.35, 0.7), 2, 10))
	btn.disabled = gold < HERO_COST
	btn.pressed.connect(_on_choose.bind(idx))

	# ── Portrait ──────────────────────────────────────────────────────────────
	var pbg := ColorRect.new()
	pbg.position = Vector2((CARD_W - PORT_SIZE) / 2.0, 14)
	pbg.size     = Vector2(PORT_SIZE, PORT_SIZE)
	pbg.color    = Color(0.05, 0.05, 0.10)
	pbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(pbg)

	var portrait := TextureRect.new()
	portrait.position    = pbg.position
	portrait.size        = pbg.size
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_portrait(portrait, cls)
	btn.add_child(portrait)

	# ── Grade badge (top-right of portrait) ───────────────────────────────────
	var badge_bg := ColorRect.new()
	badge_bg.position = Vector2(pbg.position.x + PORT_SIZE - 38, pbg.position.y)
	badge_bg.size     = Vector2(38, 38)
	badge_bg.color    = grade_col.darkened(0.4)
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(badge_bg)

	var badge_lbl := Label.new()
	badge_lbl.text = grade
	badge_lbl.position = badge_bg.position
	badge_lbl.size     = badge_bg.size
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	badge_lbl.add_theme_font_size_override("font_size", 22)
	badge_lbl.add_theme_color_override("font_color", grade_col)
	badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(badge_lbl)

	# ── Name ──────────────────────────────────────────────────────────────────
	var y_name := pbg.position.y + PORT_SIZE + 8.0
	var name_lbl := _clbl(btn, _class_name(cls), 22, elem_col,
		Vector2(0, y_name), Vector2(CARD_W, 30), true)

	# ── Element ───────────────────────────────────────────────────────────────
	_clbl(btn, _elem_name(elem), 13, elem_col.lightened(0.25),
		Vector2(0, y_name + 32), Vector2(CARD_W, 20), true)

	# ── Grade summary ─────────────────────────────────────────────────────────
	var avg_sign := "+" if avg_pct >= 0.0 else ""
	var grade_line := "%s-RANK  ·  avg %s%.1f%%" % [grade, avg_sign, avg_pct * 100.0]
	_clbl(btn, grade_line, 13, grade_col,
		Vector2(0, y_name + 56), Vector2(CARD_W, 20), true)

	# ── Divider ───────────────────────────────────────────────────────────────
	var div_y := y_name + 82.0
	var div := ColorRect.new()
	div.position = Vector2(16, div_y)
	div.size     = Vector2(CARD_W - 32, 1)
	div.color    = Color(0.3, 0.3, 0.5, 0.5)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(div)

	# ── Stat roll table ───────────────────────────────────────────────────────
	var table_y := div_y + 8.0
	var ROW_H   := 20.0
	var COL_W   := CARD_W / 2.0 - 10.0   # ~190px per column

	# [key, display_name, base_key_in_CLASS_BASE_STATS, is_int]
	var STAT_PAIRS := [
		[["hp",    "HP",   "hp",    false], ["mana",  "MP",   "mana",  false]],
		[["str",   "STR",  "str",   false], ["dex",   "DEX",  "dex",   false]],
		[["int",   "INT",  "int",   false], ["res",   "RES",  "res",   false]],
		[["spr",   "SPR",  "spr",   false], ["move",  "SPD",  "move",  true ]],
		[["range", "RNG",  "range", true],  [null,    null,   null,    false]],
	]

	for row_i in STAT_PAIRS.size():
		var row_data = STAT_PAIRS[row_i]
		for col_i in 2:
			var cell = row_data[col_i]
			var roll_key = cell[0]
			if roll_key == null:
				continue
			var disp_name: String  = cell[1]
			var base_key:  String  = cell[2]
			var is_int:    bool    = cell[3]

			var ox := 14.0 + col_i * (COL_W + 16.0)
			var oy := table_y + row_i * ROW_H

			# Stat name
			_clbl(btn, disp_name, 10, Color(0.55, 0.55, 0.72),
				Vector2(ox, oy), Vector2(34, ROW_H))

			# Compute modified value
			var roll_entry = stats_dict.get(roll_key, {"flat": 0.0})
			var base_val: int = base.get(base_key, 0)
			var delta: float  = roll_entry.get("flat", 0.0)
			var new_val: int
			if is_int:
				new_val = base_val + int(delta)
			else:
				new_val = int(float(base_val) * (1.0 + delta))

			_clbl(btn, str(new_val), 11, Color(0.86, 0.86, 1.0),
				Vector2(ox + 36, oy), Vector2(38, ROW_H))

			# Delta label
			var delta_str: String
			var delta_col: Color
			if is_int:
				var di := int(delta)
				delta_str = "+%d" % di if di >= 0 else str(di)
				delta_col = Color(0.3, 0.9, 0.45) if di > 0 else (Color(0.92, 0.3, 0.3) if di < 0 else Color(0.5, 0.5, 0.6))
			else:
				var pct := delta * 100.0
				delta_str = "+%.0f%%" % pct if pct >= 0 else "%.0f%%" % pct
				delta_col = Color(0.3, 0.9, 0.45) if pct > 1.0 else (Color(0.92, 0.3, 0.3) if pct < -1.0 else Color(0.5, 0.5, 0.6))
			_clbl(btn, delta_str, 10, delta_col,
				Vector2(ox + 76, oy), Vector2(56, ROW_H))

	# ── Growth summary line ───────────────────────────────────────────────────
	var growth_y := table_y + STAT_PAIRS.size() * ROW_H + 4.0
	_clbl(btn, "GROWTH PER LVL", 9, Color(0.4, 0.4, 0.55),
		Vector2(14, growth_y), Vector2(CARD_W - 28, 14))

	var GRW_STATS := [["hp","HP"],["str","STR"],["dex","DEX"],["int","INT"],["res","RES"],["spr","SPR"]]
	var grw_parts: Array[String] = []
	for pair in GRW_STATS:
		var g: float = stats_dict.get(pair[0], {}).get("growth", 0.0) * 100.0
		var s := "+%.0f%%" % g if g >= 0 else "%.0f%%" % g
		grw_parts.append("%s%s" % [pair[1], s])
	var grw_lbl := _clbl(btn, "  ".join(grw_parts), 9, Color(0.55, 0.7, 0.55),
		Vector2(14, growth_y + 14), Vector2(CARD_W - 28, 14))
	grw_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# ── Divider ───────────────────────────────────────────────────────────────
	var div2_y := growth_y + 33.0
	var div2 := ColorRect.new()
	div2.position = Vector2(16, div2_y)
	div2.size     = Vector2(CARD_W - 32, 1)
	div2.color    = Color(0.3, 0.3, 0.5, 0.5)
	div2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(div2)

	# ── Skill ─────────────────────────────────────────────────────────────────
	var skill_y := div2_y + 8.0
	_clbl(btn, "SKILL", 9, Color(0.42, 0.46, 0.62),
		Vector2(14, skill_y), Vector2(CARD_W - 28, 14))

	var tmp := UnitFactory.create_unit(cls, elem, true)
	_clbl(btn, tmp.skill_name if tmp.skill_name != "" else "—", 15,
		Color(1.0, 0.85, 0.35),
		Vector2(14, skill_y + 14), Vector2(CARD_W - 28, 22))
	_clbl(btn, _skill_short_desc(tmp), 11, Color(0.62, 0.62, 0.76),
		Vector2(14, skill_y + 38), Vector2(CARD_W - 28, 36))
	tmp.free()

	return btn

# ── Signal handlers ───────────────────────────────────────────────────────────
func _on_choose(idx: int) -> void:
	var offer: Dictionary = _offers[idx]
	hero_chosen.emit(offer["class"], offer["element"], offer["rolls"])
	visible = false

func _on_cancel() -> void:
	cancelled.emit()
	visible = false

# ── Portrait loader ───────────────────────────────────────────────────────────
func _load_portrait(portrait: TextureRect, cls: UnitBase.UnitClass) -> void:
	# Try custom sprites first (Nemi, Bloodhound, etc.)
	const CUSTOM := {
		UnitBase.UnitClass.NEMI:       "res://assets/using/nemi.png",
		UnitBase.UnitClass.BLOODHOUND: "res://assets/using/bloodhound.png",
	}
	if CUSTOM.has(cls):
		var tex := load(CUSTOM[cls]) as Texture2D
		if tex:
			portrait.texture = tex
			return
	# Fall back to generated sprite sheet
	var folder: String = SPRITE_FOLDERS.get(cls, "warrior")
	var sheet := load("res://assets/sprites/generated/%s/0/single.png" % folder) as Texture2D
	if sheet:
		var atlas := AtlasTexture.new()
		atlas.atlas  = sheet
		atlas.region = IDLE_FRAME
		portrait.texture = atlas

# ── Helpers ───────────────────────────────────────────────────────────────────
func _skill_short_desc(unit: UnitBase) -> String:
	if unit.skill_name == "":
		return ""
	var parts: Array[String] = []
	if unit.skill_damage_multiplier > 0:
		parts.append("%.0f%% DMG" % (unit.skill_damage_multiplier * 100))
	if unit.skill_range > 0:
		parts.append("RNG %d" % unit.skill_range)
	if unit.skill_cooldown_max > 0:
		parts.append("every %ds" % unit.skill_cooldown_max)
	if unit.skill_mana_cost > 0:
		parts.append("%d MP" % unit.skill_mana_cost)
	return " · ".join(parts)

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
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
		UnitBase.UnitClass.SHAUNA:     return "Shauna"
		UnitBase.UnitClass.NEMI:       return "Nemi"
		UnitBase.UnitClass.SHEILDOR:   return "Sheildor"
		UnitBase.UnitClass.LORDEE:     return "Lordee"
		UnitBase.UnitClass.NECRO:      return "Necro"
		UnitBase.UnitClass.DOC:        return "Doc"
		UnitBase.UnitClass.RIOT:       return "Riot"
		UnitBase.UnitClass.PASTOR:     return "Pastor"
		UnitBase.UnitClass.SABLE:      return "Sable"
		UnitBase.UnitClass.RUSH:       return "Rush"
		UnitBase.UnitClass.STITCH:     return "Stitch"
		UnitBase.UnitClass.COAL:       return "Coal"
		UnitBase.UnitClass.JUNE:       return "June"
		UnitBase.UnitClass.CROSS:      return "Cross"
		UnitBase.UnitClass.SEAR:       return "Sear"
		UnitBase.UnitClass.EMBER:      return "Ember"
		UnitBase.UnitClass.RIFT:       return "Rift"
		UnitBase.UnitClass.ZOLT:       return "Zolt"
		UnitBase.UnitClass.LUMEN:      return "Lumen"
		UnitBase.UnitClass.STATIC:     return "Static"
		UnitBase.UnitClass.REED:       return "Reed"
		UnitBase.UnitClass.VAIL:       return "Vail"
		UnitBase.UnitClass.SPORE:      return "Spore"
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
		UnitBase.Element.FIRE:      return Color(1.0,  0.45, 0.1)
		UnitBase.Element.WATER:     return Color(0.3,  0.7,  1.0)
		UnitBase.Element.EARTH:     return Color(0.75, 0.55, 0.25)
		UnitBase.Element.AIR:       return Color(0.75, 1.0,  1.0)
		UnitBase.Element.LIGHTNING: return Color(1.0,  1.0,  0.25)
		_:                          return Color(0.85, 0.85, 0.92)

func _grade_color(grade: String) -> Color:
	match grade:
		"S": return Color(1.0,  0.85, 0.0)
		"A": return Color(0.25, 0.90, 0.45)
		"B": return Color(0.40, 0.68, 1.0)
		"C": return Color(0.72, 0.72, 0.72)
		"D": return Color(0.95, 0.30, 0.30)
		_:   return Color(0.60, 0.60, 0.72)

func _lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos; l.size = size
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

# Child label with MOUSE_FILTER_IGNORE so clicks reach the parent button
func _clbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := _lbl(parent, text, sz, col, pos, size, center)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _btn(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text; b.position = rect.position; b.size = rect.size
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	b.add_theme_stylebox_override("normal",  _flat(Color(0.14, 0.14, 0.22), Color(0.38, 0.38, 0.55), 1, 6))
	b.add_theme_stylebox_override("hover",   _flat(Color(0.22, 0.22, 0.33), Color(0.6,  0.6,  0.8),  1, 6))
	b.add_theme_stylebox_override("pressed", _flat(Color(0.10, 0.10, 0.18), Color(0.3,  0.3,  0.5),  1, 6))
	return b

func _flat(bg: Color, border: Color = Color.TRANSPARENT,
		bw: int = 0, radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.border_width_left = bw; s.border_width_right  = bw
	s.border_width_top  = bw; s.border_width_bottom = bw
	s.corner_radius_top_left     = radius; s.corner_radius_top_right    = radius
	s.corner_radius_bottom_left  = radius; s.corner_radius_bottom_right = radius
	return s
