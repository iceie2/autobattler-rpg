extends CanvasLayer
class_name LevelUpScreen

signal all_done

# Hero sprite paths (matches VisualUnit.HERO_SPRITE_PATHS)
const HERO_SPRITES: Dictionary = {
	UnitBase.UnitClass.NEMI:       "res://assets/using/nemi.png",
	UnitBase.UnitClass.BLOODHOUND: "res://assets/using/bloodhound.png",
	UnitBase.UnitClass.BOUNCER:    "res://assets/using/bouncer.png",
	UnitBase.UnitClass.HEADHUNTER: "res://assets/using/headhunter.png",
	UnitBase.UnitClass.SHAUNA:     "res://assets/using/shauna.png",
	UnitBase.UnitClass.RUSH:       "res://assets/using/rush.png",
	UnitBase.UnitClass.SABLE:      "res://assets/using/sable.png",
	UnitBase.UnitClass.STITCH:     "res://assets/using/stitch.png",
	UnitBase.UnitClass.EMBER:      "res://assets/using/ember.png",
	UnitBase.UnitClass.RIFT:       "res://assets/using/rift.png",
	UnitBase.UnitClass.ZOLT:       "res://assets/using/zolt.png",
	UnitBase.UnitClass.LUMEN:      "res://assets/using/lumen.png",
	UnitBase.UnitClass.STATIC:     "res://assets/using/static.png",
	UnitBase.UnitClass.SPORE:      "res://assets/using/spore.png",
	UnitBase.UnitClass.CROSS:      "res://assets/using/cross.png",
	UnitBase.UnitClass.SEAR:       "res://assets/using/sear.png",
	UnitBase.UnitClass.DOC:        "res://assets/using/doc.png",
	UnitBase.UnitClass.RIOT:       "res://assets/using/riot.png",
	UnitBase.UnitClass.PASTOR:     "res://assets/using/pastor.png",
	UnitBase.UnitClass.SHEILDOR:   "res://assets/using/sheildor.png",
	UnitBase.UnitClass.LORDEE:     "res://assets/using/lordee.png",
	UnitBase.UnitClass.VAIL:       "res://assets/using/vail.png",
	UnitBase.UnitClass.COAL:       "res://assets/using/coal.png",
	UnitBase.UnitClass.JUNE:       "res://assets/using/june.png",
	UnitBase.UnitClass.NECRO:      "res://assets/using/necro.png",
	UnitBase.UnitClass.REED:       "res://assets/using/reed.png",
}

# ── Radar chart (inner class) ─────────────────────────────────────────────────
class RadarChart extends Control:
	const SPOKES := 7
	const RADIUS := 75.0
	const LABELS := ["ATK", "MAG", "DEF", "HP", "MP", "SPD", "AS"]

	var base:    Array = []
	var preview: Array = []

	func set_base(v: Array) -> void:
		base = v.duplicate(); preview = []; queue_redraw()

	func set_preview(v: Array) -> void:
		preview = v.duplicate(); queue_redraw()

	func clear_preview() -> void:
		preview = []; queue_redraw()

	func _draw() -> void:
		var c    := size * 0.5
		var font := ThemeDB.fallback_font

		# Grid rings
		for ring in range(1, 4):
			var pts := PackedVector2Array()
			for i in SPOKES:
				var a := -PI * 0.5 + i * TAU / SPOKES
				pts.append(c + Vector2(cos(a), sin(a)) * (RADIUS * ring / 3.0))
			pts.append(pts[0])
			draw_polyline(pts, Color(0.3, 0.3, 0.55, 0.25), 1.0)

		# Spokes + axis labels
		for i in SPOKES:
			var a   := -PI * 0.5 + i * TAU / SPOKES
			var tip := c + Vector2(cos(a), sin(a)) * RADIUS
			draw_line(c, tip, Color(0.35, 0.35, 0.60, 0.35), 1.0)
			var lp  := c + Vector2(cos(a), sin(a)) * (RADIUS + 13.0)
			draw_string(font, lp - Vector2(14, 5), LABELS[i],
				HORIZONTAL_ALIGNMENT_CENTER, 28, 9, Color(0.72, 0.75, 0.95))

		# Base polygon
		if base.size() >= SPOKES:
			var pts := _poly(c, base)
			draw_colored_polygon(pts, Color(0.38, 0.62, 0.97, 0.28))
			var ol  := pts.duplicate(); ol.append(ol[0])
			draw_polyline(ol, Color(0.55, 0.80, 1.0, 0.90), 2.0)

		# Preview overlay
		if preview.size() >= SPOKES:
			var pts := _poly(c, preview)
			draw_colored_polygon(pts, Color(1.0, 0.92, 0.25, 0.18))
			var ol  := pts.duplicate(); ol.append(ol[0])
			draw_polyline(ol, Color(1.0, 0.95, 0.38, 0.90), 2.0)

	func _poly(c: Vector2, vals: Array) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in SPOKES:
			var a := -PI * 0.5 + i * TAU / SPOKES
			pts.append(c + Vector2(cos(a), sin(a)) * (clampf(vals[i], 0.0, 1.0) * RADIUS))
		return pts

# ── Perk definitions ──────────────────────────────────────────────────────────
# weights keys match TraitClass enum: 0=TANK,1=MAGE,2=FIGHTER,3=RANGED,4=HEALER,5=SUMMONER
const PERKS: Array[Dictionary] = [
	{id="atk",   label="ATK",   stat="attack_damage", value=8,
	 desc="Increases physical attack damage.",
	 color=Color(0.88, 0.28, 0.18),
	 weights={0:2, 1:1, 2:4, 3:1, 4:1, 5:1}},
	{id="aspd",  label="AS",    stat="attack_speed",  value=0.15,
	 desc="Increases attacks per second.",
	 color=Color(0.22, 0.78, 0.38),
	 weights={0:1, 1:1, 2:2, 3:4, 4:1, 5:2}},
	{id="magic", label="MAG",   stat="magic_power",   value=8,
	 desc="Amplifies magic damage and healing output.",
	 color=Color(0.28, 0.52, 0.95),
	 weights={0:1, 1:4, 2:1, 3:1, 4:3, 5:3}},
	{id="hp",    label="HP",    stat="max_hp",         value=60,
	 desc="Increases maximum HP.",
	 color=Color(0.88, 0.18, 0.28),
	 weights={0:4, 1:1, 2:2, 3:1, 4:2, 5:2}},
	{id="res",   label="RES",   stat="resistance",     value=7,
	 desc="Reduces all incoming physical and magic damage.",
	 color=Color(0.55, 0.38, 0.90),
	 weights={0:4, 1:2, 2:2, 3:1, 4:3, 5:2}},
	{id="regen", label="REGEN", stat="regen",          value=0,
	 desc="Boosts HP and mana regeneration each second.",
	 color=Color(0.95, 0.72, 0.18),
	 weights={0:2, 1:2, 2:1, 3:1, 4:4, 5:3}},
	{id="spd",   label="SPD",   stat="movement_speed", value=1,
	 desc="Moves faster, reaching targets and repositioning more often.",
	 color=Color(0.88, 0.85, 0.18),
	 weights={0:1, 1:1, 2:2, 3:3, 4:1, 5:1}},
]

# ── Perk grade roll (gacha-style — how much of the perk's stat you actually get) ──
# Weighted so C/B are common, S is rare. Mirrors UnitFactory's recruit-roll grades.
const PERK_GRADE_TABLE: Array[Dictionary] = [
	{grade="F", mult=0.5,  weight=8},
	{grade="D", mult=0.75, weight=18},
	{grade="C", mult=1.0,  weight=32},
	{grade="B", mult=1.3,  weight=24},
	{grade="A", mult=1.6,  weight=13},
	{grade="S", mult=2.2,  weight=5},
]
# Same grey/dark-green/blue/purple/gold progression as item rarity — matches
# UnitFactory.GRADE_COLORS so every roll's quality reads consistently.
const PERK_GRADE_COLORS := {
	"F": Color(0.45, 0.45, 0.48),
	"D": Color(0.65, 0.65, 0.68),
	"C": Color(0.20, 0.62, 0.28),
	"B": Color(0.30, 0.55, 0.95),
	"A": Color(0.68, 0.35, 0.95),
	"S": Color(1.0,  0.85, 0.0),
}

static func _roll_perk_grade() -> Dictionary:
	var total := 0
	for g in PERK_GRADE_TABLE:
		total += int(g.weight)
	var roll := randi() % total
	var acc := 0
	for g in PERK_GRADE_TABLE:
		acc += int(g.weight)
		if roll < acc:
			return g
	return PERK_GRADE_TABLE[2]   # fallback: C

# Stat rows shown in the info panel (order matches radar axes ATK/MAG/DEF/HP/MP/SPD/AS)
const STAT_DEFS := [
	{id="atk",  label="ATK"},
	{id="mag",  label="MAG"},
	{id="def",  label="DEF"},
	{id="hp",   label="HP "},
	{id="mana", label="MP "},
	{id="spd",  label="SPD"},
	{id="aspd", label="AS "},
]

# Radar normalisation maxima [ATK, MAG, DEF, HP, MP, SPD, AS]
const RADAR_MAX := [40.0, 30.0, 30.0, 2000.0, 1000.0, 7.0, 2.0]

const PANEL_W := 1060.0
const PANEL_H := 640.0
const CARD_W  := 318.0
const CARD_H  := 308.0
const INFO_Y  := 78.0

var _queue:      Array       = []
var _panel:      Panel       = null
var _hero_lbl:   Label       = null
var _level_lbl:  Label       = null
var _portrait:   TextureRect = null
var _stat_rows:  Array       = []   # [{val_lbl, prev_lbl}] one per STAT_DEFS entry
var _radar:      RadarChart  = null
var _card_btns:  Array       = []
var _cur_offers: Array       = []
var _cur_unit:   UnitBase    = null

func _ready() -> void:
	_build_ui()
	visible = false

# ── Public entry point ────────────────────────────────────────────────────────
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

# ── Per-hero display ──────────────────────────────────────────────────────────
func _show_hero(unit: UnitBase) -> void:
	_cur_unit = unit
	_hero_lbl.text  = unit.unit_name.to_upper() + " — LEVEL UP!"
	_level_lbl.text = "Now level %d  ·  Choose a bonus stat" % unit.level

	# Load sprite — TextureRect is 250×250 with STRETCH_KEEP_ASPECT_CENTERED
	var sprite_path: String = HERO_SPRITES.get(unit.unit_class, "")
	if sprite_path != "":
		var tex := load(sprite_path) as Texture2D
		if tex:
			_portrait.texture = tex
			var portrait_r = _portrait.get_meta("portrait_r")
			if portrait_r:
				portrait_r.texture = tex

	var stats := _compute_stats(unit)
	_refresh_stat_display(stats, stats, Color.WHITE)
	_radar.set_base(_stats_to_radar(stats))

	_cur_offers = _pick_perks(unit.trait_class, 3)
	_rebuild_cards()

# ── Stat computation ──────────────────────────────────────────────────────────
func _compute_stats(u: UnitBase) -> Dictionary:
	return {
		"hp":   u.max_hp,
		"mana": u.max_mana,
		"atk":  u.attack_damage,
		"mag":  u.magic_power,
		"def":  u.resistance,
		"spd":  u.movement_speed,
		"aspd": u.attack_speed,
	}

func _preview_stats(u: UnitBase, perk: Dictionary) -> Dictionary:
	var s := _compute_stats(u)
	var v: float = perk.get("rolled_value", perk.value)
	match perk.id:
		"atk":
			s["atk"] = u.attack_damage + int(v)
		"aspd":
			s["aspd"] = u.attack_speed + v
		"magic":
			s["mag"] = u.magic_power + int(v)
		"hp":
			s["hp"] = u.max_hp + int(v)
		"res":
			s["def"] = u.resistance + int(v)
		"regen":
			pass   # regen isn't shown on the stat rows/radar; no preview delta
		"spd":
			s["spd"] = mini(u.movement_speed + int(v), 8)
	return s

func _stats_to_radar(s: Dictionary) -> Array:
	return [
		s.get("atk", 0)  / RADAR_MAX[0],
		s.get("mag", 0)  / RADAR_MAX[1],
		s.get("def", 0)  / RADAR_MAX[2],
		s.get("hp",  0)  / RADAR_MAX[3],
		s.get("mana", 0) / RADAR_MAX[4],
		s.get("spd", 0)  / RADAR_MAX[5],
		s.get("aspd", 0) / RADAR_MAX[6],
	]

# ── Stat display (live update) ────────────────────────────────────────────────
func _refresh_stat_display(base: Dictionary, preview: Dictionary, perk_col: Color) -> void:
	for i in STAT_DEFS.size():
		var id: String  = STAT_DEFS[i].id
		var row: Dictionary = _stat_rows[i]
		var bv: float = base.get(id, 0)
		var pv: float = preview.get(id, 0)
		var is_float: bool = (id == "aspd")
		row.val_lbl.text = ("%.2f" % bv) if is_float else str(int(bv))
		if pv != bv:
			row.prev_lbl.text = ("→ %.2f" % pv) if is_float else ("→ %d" % int(pv))
			row.prev_lbl.add_theme_color_override("font_color", perk_col)
			row.prev_lbl.visible = true
		else:
			row.prev_lbl.visible = false

func _clear_stat_preview() -> void:
	if not _cur_unit or not is_instance_valid(_cur_unit):
		return
	var s := _compute_stats(_cur_unit)
	_refresh_stat_display(s, s, Color.WHITE)
	_radar.clear_preview()

# ── Hover handlers ────────────────────────────────────────────────────────────
func _on_perk_hover(perk: Dictionary) -> void:
	if not _cur_unit or not is_instance_valid(_cur_unit):
		return
	var base    := _compute_stats(_cur_unit)
	var preview := _preview_stats(_cur_unit, perk)
	_refresh_stat_display(base, preview, perk.color)
	_radar.set_preview(_stats_to_radar(preview))

func _on_perk_unhover() -> void:
	_clear_stat_preview()

# ── Perk selection ────────────────────────────────────────────────────────────
func _pick_perks(trait_class: int, count: int) -> Array:
	var pool: Array = []
	for p: Dictionary in PERKS:
		var w: int = p.weights.get(trait_class, 1)
		for _i in range(w):
			pool.append(p)
	pool.shuffle()
	var picked: Array = []
	var seen:   Array = []
	for p: Dictionary in pool:
		if p.id not in seen:
			seen.append(p.id)
			picked.append(p)
		if picked.size() >= count:
			break
	if picked.size() < count:
		for p: Dictionary in PERKS:
			if p.id not in seen:
				seen.append(p.id)
				picked.append(p)
			if picked.size() >= count:
				break
	# Each offer independently rolls a gacha grade (F–S) that scales how much of
	# the perk's stat you actually get — three random stats, three random rolls.
	var rolled: Array = []
	for p: Dictionary in picked:
		rolled.append(roll_perk_offer(p))
	return rolled

# Scale a perk's base value by its rolled grade multiplier, respecting the stat's
# natural precision (float stats like attack_speed keep decimals; integer stats
# round and never drop to 0). Static so other systems (round rewards) can reuse
# the exact same gacha math without needing a LevelUpScreen instance.
static func _scale_perk_value(perk: Dictionary, mult: float) -> float:
	var scaled: float = float(perk.value) * mult
	match perk.id:
		"aspd":
			return snappedf(max(0.02, scaled), 0.01)
		"regen":
			return snappedf(max(0.05, 0.3 * mult), 0.01)   # HP regen/sec; mana regen derived as 2x in apply_perk_to_unit
		_:
			return float(maxi(1, int(round(scaled))))

# Roll a full offer (grade + rolled value) for a random or specific perk def.
# Shared by the level-up screen and any other system that hands out perk-style
# rewards (e.g. round rewards) so they stay on identical gacha math/colors.
static func roll_perk_offer(perk: Dictionary) -> Dictionary:
	var g: Dictionary = _roll_perk_grade()
	var offer: Dictionary = perk.duplicate()
	offer["grade"] = g.grade
	offer["grade_color"] = PERK_GRADE_COLORS.get(g.grade, Color.WHITE)
	offer["grade_mult"] = float(g.mult)
	offer["rolled_value"] = _scale_perk_value(perk, float(g.mult))
	return offer

# Applies an already-rolled perk offer's stat bonus directly to any unit. Static
# so it works outside the level-up flow too (round-reward stat bonuses).
static func apply_perk_to_unit(unit: UnitBase, perk: Dictionary) -> void:
	var v: float = perk.get("rolled_value", perk.value)
	match perk.stat:
		"attack_damage": unit.attack_damage += int(v)
		"attack_speed":  unit.attack_speed  += v
		"magic_power":   unit.magic_power   += int(v)
		"max_hp":
			unit.max_hp     += int(v)
			unit.current_hp  = mini(unit.current_hp + int(v), unit.max_hp)
		"resistance":    unit.resistance    += int(v)
		"regen":
			unit.hp_regen   += v
			unit.mana_regen += v * 2.0
		"movement_speed": unit.movement_speed = mini(unit.movement_speed + int(v), 8)
	unit.update_visuals()

func _apply_perk(perk: Dictionary) -> void:
	if not (_cur_unit and is_instance_valid(_cur_unit)):
		_next()
		return
	apply_perk_to_unit(_cur_unit, perk)
	_cur_unit.perk_points -= 1
	if _cur_unit.perk_points > 0:
		_queue.push_front(_cur_unit)
	_next()

# ── Card builder ──────────────────────────────────────────────────────────────
func _rebuild_cards() -> void:
	for b in _card_btns:
		if is_instance_valid(b):
			b.queue_free()
	_card_btns.clear()

	var gap     := 13.0
	var total_w := CARD_W * 3.0 + gap * 2.0
	var start_x := (PANEL_W - total_w) / 2.0
	var card_y  := PANEL_H - CARD_H - 16.0

	for i in range(_cur_offers.size()):
		var card := _make_card(_cur_offers[i], Vector2(start_x + i * (CARD_W + gap), card_y))
		_panel.add_child(card)
		_card_btns.append(card)

func _make_card(perk: Dictionary, pos: Vector2) -> Button:
	var btn := Button.new()
	btn.position = pos
	btn.size     = Vector2(CARD_W, CARD_H)
	btn.text     = ""

	var grade: String = perk.get("grade", "C")
	var grade_col: Color = perk.get("grade_color", Color(0.72, 0.72, 0.72))
	var rolled_value: float = perk.get("rolled_value", perk.value)

	# Whole card tinted by its rolled grade (gacha-style) — same treatment as the
	# hero recruit cards, so an "S" perk visually screams for attention.
	var bg_base: Color = grade_col.darkened(0.82)
	btn.add_theme_stylebox_override("normal",
		_flat(bg_base, grade_col, 3, 12))
	btn.add_theme_stylebox_override("hover",
		_flat(bg_base.lightened(0.10), grade_col.lightened(0.25), 4, 12))
	btn.add_theme_stylebox_override("pressed",
		_flat(bg_base.darkened(0.15), grade_col.lightened(0.1), 4, 12))
	btn.add_theme_stylebox_override("focus",
		_flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12))

	# Grade badge (top-right)
	var badge_bg := ColorRect.new()
	badge_bg.position = Vector2(CARD_W - 40, 8)
	badge_bg.size     = Vector2(32, 32)
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

	# Perk id → STAT_ICONS key (regen/spd don't have a 1:1 icon yet, use the
	# closest match).
	const PERK_ICON_KEY := {
		"atk": "atk", "aspd": "aspd", "magic": "magic", "hp": "hp",
		"res": "res", "regen": "hpregen", "spd": "move",
	}
	# Icon + big number get the freed-up middle of the card; label and
	# description are anchored to the bottom so the number can grow.
	const DESC_H := 76.0
	const LABEL_H := 24.0
	var desc_y: float  = CARD_H - 16.0 - DESC_H
	var label_y: float = desc_y - LABEL_H - 4.0

	_add_perk_icon(btn, PERK_ICON_KEY.get(perk.id, ""), Vector2((CARD_W - 44) / 2.0, 8), 44.0)

	var value_str: String = ("+%.2f" % rolled_value) if perk.id in ["aspd", "regen"] else ("+%d" % int(rolled_value))
	_lbl(btn, value_str, 58, grade_col,
		Vector2(0, 58), Vector2(CARD_W, label_y - 58.0), true)
	_lbl(btn, perk.label.to_upper(), 14, Color(0.92, 0.90, 1.0),
		Vector2(0, label_y), Vector2(CARD_W, LABEL_H), true)

	var desc := Label.new()
	desc.position             = Vector2(16, desc_y)
	desc.size                 = Vector2(CARD_W - 32, DESC_H)
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.72, 0.70, 0.82))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	desc.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	desc.text                 = perk.desc
	btn.add_child(desc)

	btn.mouse_entered.connect(_on_perk_hover.bind(perk))
	btn.mouse_exited.connect(_on_perk_unhover)
	btn.pressed.connect(_apply_perk.bind(perk))
	return btn

# ── UI shell (built once) ─────────────────────────────────────────────────────
func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color        = Color(0, 0, 0, 0.82)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	# UI theme pass 2026-07-04: dobo card panel instead of flat navy box.
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	overlay.add_child(_panel)

	# Header
	_hero_lbl = _lbl(_panel, "", 28, Color(1.0, 0.88, 0.45),
		Vector2(0, 14), Vector2(PANEL_W, 38), true)
	_level_lbl = _lbl(_panel, "", 15, Color(0.75, 0.72, 0.90, 0.85),
		Vector2(0, 52), Vector2(PANEL_W, 22), true)

	# Info section — portrait | stat list | radar

	# Portrait on left
	var pbg := ColorRect.new()
	pbg.position     = Vector2(55, INFO_Y - 30)
	pbg.size         = Vector2(250, 250)
	pbg.color        = Color(0.05, 0.05, 0.10, 0.5)
	pbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(pbg)

	_portrait = TextureRect.new()
	_portrait.position     = pbg.position
	_portrait.size         = pbg.size
	_portrait.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_portrait)

	# Radar chart (center)
	_radar = RadarChart.new()
	_radar.position     = Vector2(360, INFO_Y - 10)
	_radar.size         = Vector2(280, 208)
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_radar)

	# Portrait right (mirror)
	var pbg_r := ColorRect.new()
	pbg_r.position     = Vector2(755, INFO_Y - 30)
	pbg_r.size         = Vector2(250, 250)
	pbg_r.color        = Color(0.05, 0.05, 0.10, 0.3)
	pbg_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(pbg_r)

	var portrait_r := TextureRect.new()
	portrait_r.position     = pbg_r.position
	portrait_r.size         = pbg_r.size
	portrait_r.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	portrait_r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_r.flip_h       = true
	_panel.add_child(portrait_r)
	_portrait.set_meta("portrait_r", portrait_r)

	# Stat list on right
	const STAT_X  := 650.0
	const ROW_H   := 26.0
	_lbl(_panel, "STATS", 12, Color(0.48, 0.50, 0.70),
		Vector2(STAT_X, INFO_Y), Vector2(200, 18))

	_stat_rows.clear()
	for i in STAT_DEFS.size():
		var sd: Dictionary = STAT_DEFS[i]
		var ry := INFO_Y + 22.0 + i * ROW_H

		_lbl(_panel, sd.label, 13, Color(0.52, 0.54, 0.72),
			Vector2(STAT_X, ry), Vector2(36, ROW_H))

		var val_lbl := _lbl(_panel, "0", 15, Color(0.90, 0.90, 1.0),
			Vector2(STAT_X + 40, ry), Vector2(54, ROW_H))

		var prev_lbl := _lbl(_panel, "", 14, Color(0.35, 0.92, 0.45),
			Vector2(STAT_X + 96, ry), Vector2(80, ROW_H))
		prev_lbl.visible = false

		_stat_rows.append({val_lbl = val_lbl, prev_lbl = prev_lbl})

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

# Small stat icon (see UnitFactory.STAT_ICONS) — silently does nothing if that
# stat doesn't have an icon yet.
func _add_perk_icon(parent: Control, stat_key: String, pos: Vector2, size: float) -> void:
	var path: String = UnitFactory.STAT_ICONS.get(stat_key, "")
	if path == "":
		return
	var tex: Texture2D = load(path) as Texture2D
	if not tex:
		return
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = tex
	icon.position = pos
	icon.size = Vector2(size, size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
