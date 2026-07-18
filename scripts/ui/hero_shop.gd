extends CanvasLayer
class_name HeroShop

signal hero_chosen(unit_class: UnitBase.UnitClass, element: UnitBase.Element, rolls: Dictionary)
signal cancelled()
signal reroll_requested()

# Economy v3 (2026-07-03): 30 → 10 — whole economy rescaled to coin-drop size
# (10 starting gold, ~1g coin drops per kill). Tune in balance.gd.
const HERO_COST := Balance.HERO_COST
const REROLL_COST := Balance.REROLL_COST

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
const CARD_H     := 780.0
const PANEL_W    := 1340.0
const PANEL_H    := 950.0
const PORT_SIZE  := 240.0

var _offers:    Array = []
var _card_btns: Array = []
var _panel:     Panel
var _title_lbl: Label
var _sub_lbl:   Label
var _cancel_btn: Button
var _reroll_btn: Button
var _slot_count: int = 3   # hero cards shown (raised by the Merchant's Ledger relic)
var _free_mode:  bool = false  # Call to Arms starting-hero pick (2026-07-10): no cost, no cancel

const CARD_GAP     := 20.0
const SIDE_MARGIN  := 50.0

func _ready() -> void:
	_build_ui()

# free_mode: Call to Arms' starting-hero pick — every card is pickable regardless
# of gold, the cancel button is hidden (you must choose one), and the header
# reads as a free grant rather than a shop.
func open(gold: int, slot_count: int = 3, free_mode: bool = false) -> void:
	_slot_count = maxi(3, slot_count)
	_free_mode = free_mode
	_layout_for_slots()
	_offers.clear()
	_card_btns.clear()
	_generate_offers()
	_rebuild_all_cards(gold)
	if _title_lbl:
		_title_lbl.text = "CHOOSE YOUR STARTING HERO" if _free_mode else "CHOOSE A HERO"
	if _sub_lbl:
		_sub_lbl.text = "Call to Arms — pick your first hero, free" if _free_mode \
			else "Each hero has unique stat rolls  ·  %dg each  ·  Roll again next round" % HERO_COST
	if _cancel_btn:
		_cancel_btn.visible = not _free_mode
	if _reroll_btn:
		_reroll_btn.visible = not _free_mode   # the free starting pick can't reroll
		_reroll_btn.disabled = gold < REROLL_COST
	visible = true

# Widen the panel and re-center the header/cancel for the current card count so
# 4-card shops (Merchant's Ledger) fit without cramping the default 3-card layout.
func _layout_for_slots() -> void:
	var panel_w: float = _slot_count * CARD_W + (_slot_count - 1) * CARD_GAP + 2.0 * SIDE_MARGIN
	_panel.size.x = panel_w
	if _title_lbl: _title_lbl.size.x = panel_w
	if _sub_lbl:   _sub_lbl.size.x = panel_w
	if _cancel_btn: _cancel_btn.position.x = (panel_w - 200) / 2.0
	if _reroll_btn: _reroll_btn.position.x = panel_w - SIDE_MARGIN - 190
	_center_panel()

# Refresh the offers in place (called by main_game after it charges the reroll).
func reroll(gold: int) -> void:
	_offers.clear()
	_card_btns.clear()
	_generate_offers()
	_rebuild_all_cards(gold)
	if _reroll_btn:
		_reroll_btn.disabled = (not _free_mode) and gold < REROLL_COST

func _generate_offers() -> void:
	var classes  := UnitFactory.get_all_classes()
	var elements := UnitFactory.get_all_elements()
	var used: Array = []
	while _offers.size() < _slot_count:
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
	# UI theme pass 2026-07-04: dobo card panel instead of flat navy box.
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	overlay.add_child(_panel)

	_title_lbl = _lbl(_panel, "CHOOSE A HERO", 34, Color(0.88, 0.88, 1.0),
		Vector2(0, 18), Vector2(PANEL_W, 44), true)
	_sub_lbl = _lbl(_panel, "Each hero has unique stat rolls  ·  %dg each  ·  Roll again next round" % HERO_COST,
		15, Color(1.0, 0.82, 0.3, 0.80), Vector2(0, 58), Vector2(PANEL_W, 26), true)

	# Cancel button
	_cancel_btn = _btn("Cancel", Rect2((PANEL_W - 200) / 2.0, PANEL_H - 54, 200, 40))
	_cancel_btn.pressed.connect(_on_cancel)
	_panel.add_child(_cancel_btn)

	# Reroll — refresh the offers for a small gold cost (2026-07-17 economy valve).
	_reroll_btn = _btn("↻ Reroll (%dg)" % REROLL_COST, Rect2(0, PANEL_H - 54, 190, 40))
	_reroll_btn.pressed.connect(func(): reroll_requested.emit())
	_panel.add_child(_reroll_btn)

	visible = false
	_center_panel()

# Destroy and recreate all hero cards (called on open()).
func _rebuild_all_cards(gold: int) -> void:
	for old in _card_btns:
		if is_instance_valid(old):
			old.queue_free()
	_card_btns.clear()

	var total_w: float = _slot_count * CARD_W + (_slot_count - 1) * CARD_GAP
	var start_x: float = (_panel.size.x - total_w) / 2.0

	for i in range(_slot_count):
		var x    := start_x + i * (CARD_W + CARD_GAP)
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
	# Whole card is tinted by its rolled grade at all times (gacha-style FOMO) —
	# hover/pressed just intensify the same grade color rather than switching to a
	# neutral one.
	var bg_base: Color = grade_col.darkened(0.82)
	btn.add_theme_stylebox_override("normal",
		_flat(bg_base, grade_col, 3, 12))
	btn.add_theme_stylebox_override("hover",
		_flat(bg_base.lightened(0.10), grade_col.lightened(0.25), 4, 12))
	btn.add_theme_stylebox_override("pressed",
		_flat(bg_base.darkened(0.15), grade_col.lightened(0.1), 4, 12))
	btn.add_theme_stylebox_override("focus",
		_flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12))
	btn.disabled = (not _free_mode) and gold < HERO_COST
	btn.pressed.connect(_on_choose.bind(idx))

	# ── Portrait ──────────────────────────────────────────────────────────────
	# No backing box — the model sits directly on the card's grade-tinted
	# background so the area behind it reads as the roll's colour.
	var port_pos := Vector2((CARD_W - PORT_SIZE) / 2.0, 14)
	var portrait := TextureRect.new()
	portrait.position    = port_pos
	portrait.size        = Vector2(PORT_SIZE, PORT_SIZE)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_portrait(portrait, cls)
	btn.add_child(portrait)

	# ── Grade badge (top-right of portrait) ───────────────────────────────────
	var badge_bg := ColorRect.new()
	badge_bg.position = Vector2(port_pos.x + PORT_SIZE - 38, port_pos.y)
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
	badge_lbl.add_theme_font_size_override("font_size", 26)
	badge_lbl.add_theme_color_override("font_color", grade_col)
	badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(badge_lbl)

	# ── Name ──────────────────────────────────────────────────────────────────
	var y_name := port_pos.y + PORT_SIZE + 8.0
	var name_lbl := _clbl(btn, _class_name(cls), 22, elem_col,
		Vector2(0, y_name), Vector2(CARD_W, 30), true)

	# ── Element ───────────────────────────────────────────────────────────────
	_clbl(btn, _elem_name(elem), 13, elem_col.lightened(0.25),
		Vector2(0, y_name + 32), Vector2(CARD_W, 20), true)

	# ── Grade summary ─────────────────────────────────────────────────────────
	# avg_pct is the average GROWTH ROLL MULTIPLIER (1.0 = neutral); show it as a
	# +/- % relative to that baseline so "1.1" reads as "+10%", not "110%".
	var avg_rel: float = (avg_pct - 1.0) * 100.0
	var avg_sign := "+" if avg_rel >= 0.0 else ""
	var grade_line := "%s-RANK  ·  growth %s%.1f%%" % [grade, avg_sign, avg_rel]
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

	var tmp := UnitFactory.create_unit(cls, elem, true)

	# ── Skill (below the portrait, so the player sees what the hero does
	# before scanning the stat table) ──────────────────────────────────────────
	var skill_y := div_y + 8.0
	_clbl(btn, "SKILL", 9, Color(0.42, 0.46, 0.62),
		Vector2(14, skill_y), Vector2(CARD_W - 28, 14))
	_clbl(btn, tmp.skill_name if tmp.skill_name != "" else "—", 15,
		Color(1.0, 0.85, 0.35),
		Vector2(14, skill_y + 14), Vector2(CARD_W - 28, 22))
	var skill_desc_lbl := Label.new()
	skill_desc_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	skill_desc_lbl.position      = Vector2(14, skill_y + 38)
	skill_desc_lbl.size          = Vector2(CARD_W - 28, 40)
	skill_desc_lbl.add_theme_font_size_override("font_size", 20)
	skill_desc_lbl.add_theme_color_override("font_color", Color(0.62, 0.62, 0.76))
	skill_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_desc_lbl.text          = _skill_short_desc(tmp)
	btn.add_child(skill_desc_lbl)

	# ── Divider ───────────────────────────────────────────────────────────────
	var div_skill_y := skill_y + 88.0
	var div_skill := ColorRect.new()
	div_skill.position = Vector2(16, div_skill_y)
	div_skill.size     = Vector2(CARD_W - 32, 1)
	div_skill.color    = Color(0.3, 0.3, 0.5, 0.5)
	div_skill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(div_skill)

	# ── Ultimate ────────────────────────────────────────────────────────────────
	var ult_y := div_skill_y + 8.0
	_clbl(btn, "ULTIMATE", 9, Color(0.62, 0.46, 0.22),
		Vector2(14, ult_y), Vector2(CARD_W - 28, 14))
	_clbl(btn, tmp.ultimate_name if tmp.ultimate_name != "" else "—", 15,
		Color(1.0, 0.65, 0.25),
		Vector2(14, ult_y + 14), Vector2(CARD_W - 28, 22))
	var ult_desc_lbl := Label.new()
	ult_desc_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	ult_desc_lbl.position      = Vector2(14, ult_y + 38)
	ult_desc_lbl.size          = Vector2(CARD_W - 28, 58)
	ult_desc_lbl.add_theme_font_size_override("font_size", 20)
	ult_desc_lbl.add_theme_color_override("font_color", Color(0.62, 0.62, 0.76))
	ult_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ult_desc_lbl.text          = _ultimate_short_desc(tmp, cls)
	btn.add_child(ult_desc_lbl)
	tmp.free()

	# ── Divider ───────────────────────────────────────────────────────────────
	var div_ult_y := ult_y + 106.0
	var div_ult := ColorRect.new()
	div_ult.position = Vector2(16, div_ult_y)
	div_ult.size     = Vector2(CARD_W - 32, 1)
	div_ult.color    = Color(0.3, 0.3, 0.5, 0.5)
	div_ult.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(div_ult)

	# ── Stat roll table ───────────────────────────────────────────────────────
	# Each row shows: LABEL   stat value   +growth-per-level
	# We deliberately don't expose the base/bonus roll breakdown here (2026-07-04
	# clarity pass, user request) — just the number and how much it goes up per
	# level (can be negative from bad-roll effects).
	var table_y := div_ult_y + 8.0
	var ROW_H   := 22.0

	# [roll_key, display_name, base_key, is_small_float]
	var GROWTH_ROWS := [
		["hp",        "HP",       "hp",        false],
		["mana",      "MP",       "mana",      false],
		["atk",       "ATK",      "atk",       false],
		["magic",     "MAG",      "magic",     false],
		["res",       "ARM",      "res",       false],   # rendered as an ARM|MR column pair below
		["aspd",      "AS",       "aspd",      true],
		["hpregen",   "HP/S",     "hpregen",   true],
		["manaregen", "MP/S",     "manaregen", true],
	]

	var class_growth: Dictionary = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(cls, {})

	var row_y := table_y
	for row in GROWTH_ROWS:
		var roll_key: String       = row[0]
		var disp_name: String      = row[1]
		var base_key: String       = row[2]
		var is_small_float: bool   = row[3]

		var roll_entry: Dictionary = stats_dict.get(roll_key, {"flat": 0.0, "growth": 1.0})
		var class_base: float      = base.get(base_key, 0)
		var flat: float            = roll_entry.get("flat", 0.0)
		var current_val: float     = class_base * (1.0 + flat)

		# Additive growth: fixed per-class amount + this recruit's personalized
		# bonus (base_growth * rolled multiplier). e.g. base 18, growth 3, bonus 4
		# → 25. See UnitBase.stat_growth()/UnitFactory.apply_recruit_rolls.
		var base_growth: float = class_growth.get(base_key, 0.0)
		var mult: float         = roll_entry.get("growth", 1.0)
		var bonus: float        = snappedf(base_growth * mult, 0.01) if is_small_float else float(round(base_growth * mult))
		var next_val: float     = current_val + base_growth + bonus
		var delta: float        = base_growth + bonus

		# Growth (the delta) is tier-colored by the ROLL MULTIPLIER, so color
		# always tells you the QUALITY of this roll. The stat value itself is
		# plain white.
		var growth_col: Color = UnitFactory.grade_color_for_growth(mult)

		var base_str: String
		var growth_str: String
		if is_small_float:
			base_str = "%.2f" % next_val
			growth_str = "%+.2f" % delta
		else:
			base_str = "%d" % int(next_val)
			growth_str = "%+d" % int(delta)

		if roll_key == "res":
			# Armor + Magic Armor side by side, SPD/RNG-style (2026-07-16 user
			# request). Both stats ride the same "res" roll and growth today.
			var res_col_w := CARD_W / 2.0 - 10.0
			for pair2 in [["res", "ARM"], ["mres", "MR"]]:
				var col2: int = 0 if pair2[0] == "res" else 1
				var ox2 := 14.0 + col2 * (res_col_w + 16.0)
				_add_stat_icon(btn, pair2[0], Vector2(ox2, row_y + 2), 18.0)
				_clbl(btn, pair2[1], 10, Color(0.55, 0.55, 0.72),
					Vector2(ox2 + 20, row_y), Vector2(34, ROW_H))
				_clbl(btn, base_str, 12, Color(0.92, 0.92, 0.96),
					Vector2(ox2 + 56, row_y), Vector2(40, ROW_H))
				_clbl(btn, growth_str, 11, growth_col,
					Vector2(ox2 + 96, row_y), Vector2(res_col_w - 96, ROW_H))
			row_y += ROW_H
			continue

		_add_stat_icon(btn, roll_key, Vector2(14, row_y + 2), 18.0)
		_clbl(btn, disp_name, 10, Color(0.55, 0.55, 0.72),
			Vector2(34, row_y), Vector2(40, ROW_H))
		_clbl(btn, base_str, 12, Color(0.92, 0.92, 0.96),
			Vector2(74, row_y), Vector2(44, ROW_H))
		_clbl(btn, growth_str, 11, growth_col,
			Vector2(118, row_y), Vector2(CARD_W - 132, ROW_H))
		row_y += ROW_H

	# ── Move / Range (no per-level growth) ────────────────────────────────────
	var COL_W := CARD_W / 2.0 - 10.0
	for pair in [["move", "SPD", "move"], ["range", "RNG", "range"]]:
		var col_i: int = ["move", "range"].find(pair[0])
		var roll_entry: Dictionary = stats_dict.get(pair[0], {"flat": 0.0})
		var val: int = int(base.get(pair[2], 0)) + int(roll_entry.get("flat", 0.0))
		var ox := 14.0 + col_i * (COL_W + 16.0)
		_add_stat_icon(btn, pair[0], Vector2(ox, row_y + 2), 18.0)
		_clbl(btn, pair[1], 10, Color(0.55, 0.55, 0.72),
			Vector2(ox + 20, row_y), Vector2(30, ROW_H))
		_clbl(btn, str(val), 12, Color(0.86, 0.86, 1.0),
			Vector2(ox + 54, row_y), Vector2(70, ROW_H))
	row_y += ROW_H

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
	# Try AI sprite first — filename = class name lowercased, spaces → underscores.
	var ai_path := "res://assets/using/%s.png" % _class_name(cls).to_lower().replace(" ", "_")
	if ResourceLoader.exists(ai_path):
		var tex := load(ai_path) as Texture2D
		if tex:
			portrait.texture = tex
			return
	# Fall back to LPC sprite sheet (old RPG classes and any hero without AI art yet).
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
	if unit.skill_description != "":
		return unit.skill_description
	# Legacy fallback for old classes without a written description
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

# Ultimates don't carry their own written description on UnitBase — reuse the
# flavor text already authored in ClassBrowser (the "[ULTIMATE ...] Name —
# description" segment of its skill_desc) so the recruit card and the class
# compendium never drift apart.
func _ultimate_short_desc(unit: UnitBase, cls: UnitBase.UnitClass) -> String:
	if unit.ultimate_name == "":
		return ""
	var full := _ultimate_desc_from_browser(cls)
	if full != "":
		return full
	# Fallback for any ultimate without browser flavor text yet
	var parts: Array[String] = []
	if unit.ultimate_damage_mult > 0:
		parts.append("%.0f%% DMG" % (unit.ultimate_damage_mult * 100))
	if unit.ultimate_range > 0:
		parts.append("RNG %d" % unit.ultimate_range)
	if unit.ultimate_charge_max > 0:
		parts.append("%d charge" % unit.ultimate_charge_max)
	return " · ".join(parts)

func _ultimate_desc_from_browser(cls: UnitBase.UnitClass) -> String:
	for entry in ClassBrowser.CLASSES:
		if entry.get("unit_class") != cls:
			continue
		var full: String = entry.get("skill_desc", "")
		var idx := full.find("[ULTIMATE")
		if idx == -1:
			return ""
		var seg := full.substr(idx)
		var bracket_end := seg.find("] ")
		if bracket_end != -1:
			seg = seg.substr(bracket_end + 2)
		var dash_idx := seg.find(" — ")
		if dash_idx != -1:
			seg = seg.substr(dash_idx + 3)
		return seg.strip_edges()
	return ""

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

# Same grey/dark-green/blue/purple/gold progression as item rarity — matches
# UnitFactory.GRADE_COLORS so every roll's quality reads consistently.
func _grade_color(grade: String) -> Color:
	match grade:
		"S": return Color(1.0,  0.85, 0.0)
		"A": return Color(0.68, 0.35, 0.95)
		"B": return Color(0.30, 0.55, 0.95)
		"C": return Color(0.20, 0.62, 0.28)
		"D": return Color(0.65, 0.65, 0.68)
		_:   return Color(0.60, 0.60, 0.72)

func _lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos; l.size = size
	l.add_theme_font_size_override("font_size", UITheme.body_font(sz))
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

# Small stat icon (see UnitFactory.STAT_ICONS) — silently does nothing if that
# stat doesn't have an icon yet.
func _add_stat_icon(parent: Node, stat_key: String, pos: Vector2, size: float) -> void:
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

func _btn(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text; b.position = rect.position; b.size = rect.size
	b.add_theme_font_size_override("font_size", 20)
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
