extends CanvasLayer
class_name LevelUpScreen

signal all_done

# ── Perk definitions ──────────────────────────────────────────────────────────
# weights keys match TraitClass enum: 0=TANK,1=MAGE,2=FIGHTER,3=RANGED,4=HEALER,5=SUMMONER
const PERKS: Array[Dictionary] = [
	{id="str",  label="Strength",     stat="strength",       value=8,
	 desc="Increases physical damage output.",
	 color=Color(0.88, 0.28, 0.18),
	 weights={0:2, 1:1, 2:4, 3:1, 4:1, 5:1}},
	{id="dex",  label="Dexterity",    stat="dexterity",      value=8,
	 desc="Attacks faster and with greater precision.",
	 color=Color(0.22, 0.78, 0.38),
	 weights={0:1, 1:1, 2:2, 3:4, 4:1, 5:2}},
	{id="int",  label="Intelligence", stat="intelligence",   value=8,
	 desc="Amplifies magic damage and healing output.",
	 color=Color(0.28, 0.52, 0.95),
	 weights={0:1, 1:4, 2:1, 3:1, 4:3, 5:3}},
	{id="hp",   label="Vitality",     stat="max_hp",         value=60,
	 desc="Increases maximum HP.",
	 color=Color(0.88, 0.18, 0.28),
	 weights={0:4, 1:1, 2:2, 3:1, 4:2, 5:2}},
	{id="res",  label="Resistance",   stat="resistance",     value=7,
	 desc="Reduces all incoming damage.",
	 color=Color(0.55, 0.38, 0.90),
	 weights={0:4, 1:2, 2:2, 3:1, 4:3, 5:2}},
	{id="spr",  label="Spirit",       stat="spirit",         value=6,
	 desc="Boosts HP and mana regeneration each round.",
	 color=Color(0.95, 0.72, 0.18),
	 weights={0:2, 1:2, 2:1, 3:1, 4:4, 5:3}},
	{id="spd",  label="Speed",        stat="movement_speed", value=1,
	 desc="Moves faster across the battlefield.",
	 color=Color(0.88, 0.85, 0.18),
	 weights={0:1, 1:1, 2:2, 3:3, 4:1, 5:1}},
]

const CARD_W  := 320.0
const CARD_H  := 370.0
const PANEL_W := 1080.0
const PANEL_H := 650.0

var _queue:      Array    = []
var _panel:      Panel    = null
var _hero_lbl:   Label    = null
var _level_lbl:  Label    = null
var _portrait:   TextureRect = null
var _card_btns:  Array    = []
var _cur_offers: Array    = []
var _cur_unit:   UnitBase = null

func _ready() -> void:
	_build_ui()
	visible = false

# Entry point — pass all player units; only those with perk_points > 0 are shown.
func present(heroes: Array) -> void:
	_queue = []
	for u in heroes:
		if u and is_instance_valid(u) and u.perk_points > 0:
			_queue.append(u)
	if _queue.is_empty():
		all_done.emit()
		return
	visible = true
	_next()

func _next() -> void:
	while not _queue.is_empty():
		var u = _queue.pop_front()
		if u and is_instance_valid(u) and u.perk_points > 0:
			_show_hero(u)
			return
	visible = false
	all_done.emit()

func _show_hero(unit: UnitBase) -> void:
	_cur_unit = unit
	_hero_lbl.text  = unit.unit_name.to_upper() + " — LEVEL UP!"
	_level_lbl.text = "Now level %d  ·  Choose a bonus stat" % unit.level

	# Portrait — try AI art first, no fallback needed (just blank if missing)
	var ai_path := "res://assets/using/%s.png" % unit.unit_name.to_lower()
	_portrait.texture = null
	if ResourceLoader.exists(ai_path):
		var tex := load(ai_path) as Texture2D
		if tex and tex.get_width() > 0:
			_portrait.texture = tex

	_cur_offers = _pick_perks(unit.trait_class, 3)
	_rebuild_cards()

func _pick_perks(trait_class: int, count: int) -> Array:
	var pool: Array = []
	for p: Dictionary in PERKS:
		var w: int = p.weights.get(trait_class, 1)
		for _i in range(w):
			pool.append(p)
	pool.shuffle()
	var picked: Array  = []
	var seen:   Array  = []
	for p: Dictionary in pool:
		if p.id not in seen:
			seen.append(p.id)
			picked.append(p)
		if picked.size() >= count:
			break
	# Fallback: fill with any remaining perks if pool was too small
	if picked.size() < count:
		for p: Dictionary in PERKS:
			if p.id not in seen:
				seen.append(p.id)
				picked.append(p)
			if picked.size() >= count:
				break
	return picked

func _apply_perk(perk: Dictionary) -> void:
	if not (_cur_unit and is_instance_valid(_cur_unit)):
		_next()
		return
	var unit := _cur_unit
	match perk.stat:
		"strength":       unit.strength       += perk.value
		"dexterity":      unit.dexterity      += perk.value
		"intelligence":   unit.intelligence   += perk.value
		"max_hp":
			unit.max_hp     += perk.value
			unit.current_hp  = mini(unit.current_hp + perk.value, unit.max_hp)
		"resistance":     unit.resistance     += perk.value
		"spirit":         unit.spirit         += perk.value
		"movement_speed": unit.movement_speed  = mini(unit.movement_speed + perk.value, 8)
	unit.perk_points -= 1
	unit.update_visuals()
	# If the hero still has more perk points (leveled up twice), re-queue them first
	if unit.perk_points > 0:
		_queue.push_front(unit)
	_next()

# ── Card builder ──────────────────────────────────────────────────────────────
func _rebuild_cards() -> void:
	for b in _card_btns:
		if is_instance_valid(b):
			b.queue_free()
	_card_btns.clear()

	var gap     := 30.0
	var total_w := CARD_W * 3.0 + gap * 2.0
	var start_x := (PANEL_W - total_w) / 2.0
	var card_y  := 234.0

	for i in range(_cur_offers.size()):
		var card := _make_card(_cur_offers[i], Vector2(start_x + i * (CARD_W + gap), card_y))
		_panel.add_child(card)
		_card_btns.append(card)

func _make_card(perk: Dictionary, pos: Vector2) -> Button:
	var btn := Button.new()
	btn.position = pos
	btn.size     = Vector2(CARD_W, CARD_H)
	btn.text     = ""
	btn.add_theme_stylebox_override("normal",
		_flat(Color(0.10, 0.09, 0.16, 0.98), perk.color.darkened(0.35), 2, 12))
	btn.add_theme_stylebox_override("hover",
		_flat(Color(0.18, 0.14, 0.26, 1.0),  perk.color,                2, 12))
	btn.add_theme_stylebox_override("pressed",
		_flat(Color(0.22, 0.18, 0.30, 1.0),  perk.color.lightened(0.2), 3, 12))
	btn.add_theme_stylebox_override("focus",
		_flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12))

	# Big "+N" value
	_lbl(btn, "+%d" % perk.value, 54, perk.color,
		Vector2(0, 32), Vector2(CARD_W, 70), true)

	# Stat name
	_lbl(btn, perk.label.to_upper(), 15, Color(0.92, 0.90, 1.0),
		Vector2(0, 110), Vector2(CARD_W, 28), true)

	# Divider
	_lbl(btn, "──────────────", 10, Color(perk.color.r, perk.color.g, perk.color.b, 0.4),
		Vector2(0, 146), Vector2(CARD_W, 20), true)

	# Description (wrapping)
	var desc := Label.new()
	desc.text              = perk.desc
	desc.position          = Vector2(18, 174)
	desc.size              = Vector2(CARD_W - 36, 100)
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.72, 0.70, 0.82))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	desc.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	btn.add_child(desc)

	btn.pressed.connect(_apply_perk.bind(perk))
	return btn

# ── UI shell ──────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color        = Color(0, 0, 0, 0.82)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.add_theme_stylebox_override("panel",
		_flat(Color(0.06, 0.06, 0.11, 0.99), Color(0.50, 0.42, 0.72), 2, 16))
	overlay.add_child(_panel)

	_hero_lbl = _lbl(_panel, "", 26, Color(1.0, 0.88, 0.45),
		Vector2(0, 18), Vector2(PANEL_W, 42), true)
	_level_lbl = _lbl(_panel, "", 14, Color(0.75, 0.72, 0.90, 0.85),
		Vector2(0, 62), Vector2(PANEL_W, 26), true)

	# Portrait
	var pbg := ColorRect.new()
	pbg.position     = Vector2((PANEL_W - 100.0) / 2.0, 96.0)
	pbg.size         = Vector2(100.0, 120.0)
	pbg.color        = Color(0.05, 0.05, 0.10, 0.8)
	pbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(pbg)

	_portrait = TextureRect.new()
	_portrait.position     = pbg.position
	_portrait.size         = pbg.size
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_portrait)

	_center_panel()

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_panel.position = (vp - _panel.size) / 2.0

# ── Helpers ───────────────────────────────────────────────────────────────────
func _flat(bg: Color, border: Color, bw: float, radius: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(int(bw))
	s.set_corner_radius_all(int(radius))
	return s

func _lbl(parent: Control, text: String, size: int, color: Color,
		pos: Vector2, sz: Vector2, centered: bool) -> Label:
	var l := Label.new()
	l.text     = text
	l.position = pos
	l.size     = sz
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
