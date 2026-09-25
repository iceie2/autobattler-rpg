
extends CanvasLayer
class_name RoundRewardScreen

signal done

const PANEL_W := 1060.0
const PANEL_H := 560.0
const UNIT_ICON := 88.0

# Card geometry. Kept as constants because the labels are absolutely positioned
# inside the Button — when the 2026-09 type pass snapped body_font(13/15) up to
# FONT_BODY (16), the old 140x170 card had no room left and the stat line was
# clipped by the slot frame. Anything that changes a font step here must
# re-check CARD_H against the last label's bottom edge.
const CARD_W := 150.0
const CARD_H := 216.0
const CARD_PAD := 4.0

# The card sits on the reward panel, which is panel_box_tinted(1.15,1.05,0.85).
# CARD_TINT is a step brighter so the card reads as raised off it; the text is
# light because panel_cream.png is a DARK navy texture despite the name, and
# UITheme.TEXT_* are parchment browns that vanish on it.
const CARD_TINT            := Color(1.62, 1.52, 1.28)
const CARD_TINT_HOVER      := Color(2.10, 1.88, 1.35)
const CARD_TEXT_NAME       := Color(0.96, 0.91, 0.79)
const CARD_TEXT_MUTED      := Color(0.75, 0.75, 0.85)
const CARD_TEXT_STAT       := Color(0.82, 0.80, 0.90)
const CARD_TEXT_STAT_HOVER := Color(1.0, 0.84, 0.35)

const GRID_TOP := 110.0
const GRID_COLS := 5

var _panel: Panel
var _title_lbl: Label
var _sub_lbl: Label
var _unit_grid: GridContainer
var _scroll: ScrollContainer
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

	var value_str: String = LevelUpScreen.format_perk_value(_chosen_perk)

	_sub_lbl.text = "Who receives %s %s?" % [value_str, _chosen_perk.get("label", "?")]
	_unit_grid.visible = true

	for c in _unit_grid.get_children():
		c.queue_free()

	var shown := 0
	for unit in player_units:
		if not (unit and is_instance_valid(unit)):
			continue
		_unit_grid.add_child(_make_unit_card(unit))
		shown += 1

	_fit_panel_to_rows(shown)


# The modal was a fixed 1060x560 regardless of team size, so the common 3-unit
# case rendered one row of cards in a mostly empty box. Height now follows the
# rows actually present; width still doesn't, so a short row stays centred.
func _fit_panel_to_rows(count: int) -> void:
	var rows: int = maxi(1, ceili(float(count) / float(GRID_COLS)))
	var wanted: float = GRID_TOP + rows * (CARD_H + 14.0) + 24.0
	_panel.size = Vector2(PANEL_W, clampf(wanted, 340.0, PANEL_H))
	_scroll.size = Vector2(PANEL_W - 40, _panel.size.y - GRID_TOP - 20.0)
	_title_lbl.size.x = PANEL_W
	_sub_lbl.size.x = PANEL_W
	_center_panel()


func _make_unit_card(unit: UnitBase) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
	btn.text = ""
	btn.clip_contents = false
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pivot_offset = btn.custom_minimum_size * 0.5

	# NOT slot_box(): that texture is a note-page (ruled lines, corner tab and a
	# dog-eared corner baked into the art) sized for a ~48px item slot. Stretched
	# to a character card it draws its ruling straight through the portrait and
	# the dog-ear lands on the stat line. A card is a small panel, so it uses the
	# panel texture, tinted a step brighter than the panel it sits on so it still
	# reads as raised.
	btn.add_theme_stylebox_override("normal", UITheme.panel_box_tinted(CARD_TINT))
	var hover_box := UITheme.panel_box_tinted(CARD_TINT_HOVER)
	btn.add_theme_stylebox_override("hover", hover_box)
	btn.add_theme_stylebox_override("pressed", hover_box)
	btn.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10))

	var portrait := TextureRect.new()
	portrait.position = Vector2((CARD_W - UNIT_ICON) / 2.0, 12.0)
	portrait.size = Vector2(UNIT_ICON, UNIT_ICON)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.pivot_offset = portrait.size * 0.5

	var sprite_path: String = VisualUnit.HERO_SPRITE_PATHS.get(unit.unit_class, "")
	if sprite_path != "":
		var tex := load(sprite_path) as Texture2D
		if tex:
			portrait.texture = tex
	btn.add_child(portrait)
	portrait.visible = false

	var portrait_anim := HeroPortrait.new()
	portrait_anim.position = portrait.position
	portrait_anim.size = portrait.size
	portrait_anim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(portrait_anim)
	portrait_anim.setup(unit.unit_class)

	var inner := Vector2(CARD_W - CARD_PAD * 2.0, 22.0)
	_lbl(btn, unit.unit_name, UITheme.FONT_BODY, CARD_TEXT_NAME,
		Vector2(CARD_PAD, 104), inner, true)
	_lbl(btn, "Lv.%d" % unit.level, UITheme.FONT_CAPTION, CARD_TEXT_MUTED,
		Vector2(CARD_PAD, 128), Vector2(inner.x, 18), true)

	var perk_id: String = _chosen_perk.get("id", "")
	var current_value: float = _get_unit_stat_value(unit, perk_id)
	var bonus_value: float = _chosen_perk.get("rolled_value", _chosen_perk.get("value", 0))
	var upgraded_value: float = current_value + bonus_value

	# Stat icon + value, centered as a row (2026-07-16: cards now use the real
	# stat icons instead of a bare text abbreviation).
	var icon_key: String = PERK_STAT_ICON.get(perk_id, "")
	if icon_key != "":
		var srow := HBoxContainer.new()
		srow.position = Vector2(CARD_PAD, 148)
		srow.size = Vector2(CARD_W - CARD_PAD * 2.0, 22)
		srow.alignment = BoxContainer.ALIGNMENT_CENTER
		srow.add_theme_constant_override("separation", 5)
		srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(srow)
		var sicon := TextureRect.new()
		sicon.custom_minimum_size = Vector2(18, 18)
		sicon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sicon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sicon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sicon.texture = load(UnitFactory.STAT_ICONS[icon_key]) as Texture2D
		sicon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		srow.add_child(sicon)

	var stat_lbl := _lbl(
		btn,
		_format_idle_stat(perk_id, current_value),
		UITheme.FONT_BODY,
		CARD_TEXT_STAT,
		Vector2(CARD_PAD, 172),
		inner,
		true
	)

	btn.mouse_entered.connect(func() -> void:
		if not is_instance_valid(stat_lbl):
			return
		stat_lbl.text = _format_hover_stat(perk_id, current_value, upgraded_value)
		stat_lbl.add_theme_color_override("font_color", CARD_TEXT_STAT_HOVER)
		_tween_card_hover(btn, portrait, true)
	)

	btn.mouse_exited.connect(func() -> void:
		if not is_instance_valid(stat_lbl):
			return
		stat_lbl.text = _format_idle_stat(perk_id, current_value)
		stat_lbl.add_theme_color_override("font_color", CARD_TEXT_STAT)
		_tween_card_hover(btn, portrait, false)
	)

	btn.pressed.connect(_on_unit_chosen.bind(unit))
	return btn


func _on_unit_chosen(unit: UnitBase) -> void:
	if unit and is_instance_valid(unit):
		LevelUpScreen.apply_perk_to_unit(unit, _chosen_perk)
	visible = false
	done.emit()


# ── Hover preview helpers ─────────────────────────────────────────────────────
# Reads the perk's actual `stat` property off the unit (2026-07-16 fix: this
# used to match a stale id list — "speed"/"armor"/"health" — that no perk uses,
# so every card showed "0" as the current value).
func _get_unit_stat_value(unit: UnitBase, _perk_id: String) -> float:
	var stat: String = _chosen_perk.get("stat", "")
	if stat == "regen":
		return unit.hp_regen   # the regen perk boosts hp+mana regen; preview shows HP/s
	if stat != "" and stat in unit:
		return float(unit.get(stat))
	return 0.0

# Perk id -> UnitFactory.STAT_ICONS key, so reward cards show the real icons.
const PERK_STAT_ICON := {
	"atk": "atk", "aspd": "aspd", "magic": "magic", "hp": "hp",
	"res": "res", "regen": "hpregen", "spd": "move",
	"crit": "crit_chance", "critdmg": "crit_damage",
}


func _format_idle_stat(perk_id: String, value: float) -> String:
	var short_name := _short_stat_name(perk_id)
	if perk_id == "crit":
		return "%s %d%%" % [short_name, int(round(value * 100.0))]
	if perk_id == "critdmg":
		return "%s %.2fx" % [short_name, value]
	if perk_id in ["aspd", "regen"]:
		return "%s %.2f" % [short_name, value]
	return "%s %d" % [short_name, int(value)]


func _format_hover_stat(perk_id: String, from_value: float, to_value: float) -> String:
	var short_name := _short_stat_name(perk_id)
	if perk_id == "crit":
		return "%s %d%% -> %d%%" % [short_name, int(round(from_value * 100.0)), int(round(to_value * 100.0))]
	if perk_id == "critdmg":
		return "%s %.2fx -> %.2fx" % [short_name, from_value, to_value]
	if perk_id in ["aspd", "regen"]:
		return "%s %.2f -> %.2f" % [short_name, from_value, to_value]
	return "%s %d -> %d" % [short_name, int(from_value), int(to_value)]


func _short_stat_name(perk_id: String) -> String:
	match perk_id:
		"speed":
			return "SPD"
		"aspd":
			return "ASPD"
		"regen":
			return "REG"
		"damage":
			return "DMG"
		"armor":
			return "ARM"
		"health":
			return "HP"
		"crit":
			return "CRIT"
		"critdmg":
			return "CRITDMG"
		_:
			return perk_id.to_upper()


func _tween_card_hover(btn: Button, portrait: TextureRect, hovered: bool) -> void:
	var old_tween: Variant = btn.get_meta("hover_tween", null)

	if old_tween is Tween:
		old_tween.kill()

	var tw: Tween = create_tween()
	btn.set_meta("hover_tween", tw)

	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)

	if hovered:
		tw.tween_property(btn, "scale", Vector2(1.06, 1.06), 0.12)
		tw.tween_property(portrait, "scale", Vector2(1.10, 1.10), 0.12)
		tw.tween_property(
			portrait,
			"modulate",
			Color(1.08, 1.08, 1.08, 1.0),
			0.12
		)
	else:
		tw.tween_property(btn, "scale", Vector2.ONE, 0.10)
		tw.tween_property(portrait, "scale", Vector2.ONE, 0.10)
		tw.tween_property(portrait, "modulate", Color.WHITE, 0.10)


# ── UI shell ───────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.82)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box_tinted(Color(1.15, 1.05, 0.85)))
	overlay.add_child(_panel)

	_title_lbl = Label.new()
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_font(_title_lbl, UITheme.FONT_HEADER)
	_title_lbl.add_theme_color_override("font_color", Color(0.83, 0.69, 0.22))
	_title_lbl.position = Vector2(0, 20)
	_title_lbl.size = Vector2(PANEL_W, 36)
	_panel.add_child(_title_lbl)

	_sub_lbl = Label.new()
	_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_font(_sub_lbl, UITheme.FONT_VALUE)
	_sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	_sub_lbl.position = Vector2(0, 58)
	_sub_lbl.size = Vector2(PANEL_W, 26)
	_panel.add_child(_sub_lbl)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(20, GRID_TOP)
	_scroll.size = Vector2(PANEL_W - 40, PANEL_H - GRID_TOP - 20)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)

	# CenterContainer, or the GridContainer packs its row hard against the left
	# edge and a 3-unit team leaves the rest of the modal empty.
	var centerer := CenterContainer.new()
	centerer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centerer.custom_minimum_size = Vector2(PANEL_W - 40, 0)
	_scroll.add_child(centerer)

	_unit_grid = GridContainer.new()
	_unit_grid.columns = GRID_COLS
	_unit_grid.add_theme_constant_override("h_separation", 14)
	_unit_grid.add_theme_constant_override("v_separation", 14)
	centerer.add_child(_unit_grid)

	_center_panel()


func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1800, 1080)
	_panel.position = (vp - _panel.size) / 2.0


func _lbl(
	parent: Node,
	text: String,
	sz: int = 13,
	col: Color = Color(1, 1, 1),
	pos: Vector2 = Vector2.ZERO,
	size: Vector2 = Vector2(132, 20),
	center: bool = false
) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	UITheme.apply_font(l, UITheme.body_font(sz))
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
	s.border_width_left = bw
	s.border_width_right = bw
	s.border_width_top = bw
	s.border_width_bottom = bw
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	return s