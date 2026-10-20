extends CanvasLayer
class_name RewardChoiceScreen

# ══════════════════════════════════════════════════════════════════════════════
# ROUND REWARD — PICK 1 OF 3 (VD-19, owner 2026-09-27)
# "change our round reward to a 1 of 3 reward. like item or stat reward will pop
# up 3 and u get to pick 1."
#
# The map only promised a KIND of reward (item or stat). The three candidates
# are rolled after the fight (RoundReward.roll_options) and shown here; the pick
# is emitted as an index. A picked stat then goes on to RoundRewardScreen, which
# asks which hero receives it — this screen never touches the team.
#
# Same shell as RelicScreen (menu surface, header, card row) so the run's
# pick-one moments look like one family, without its slot-machine reveal: this
# screen appears after almost every fight, and a reel on every one would be a
# toll.
# ══════════════════════════════════════════════════════════════════════════════

signal chosen(index: int)

const PANEL_W := 1000.0
const CARD_W  := 290.0
const CARD_H  := 300.0
const CARD_ROW_Y := 136.0
const PANEL_H := CARD_ROW_Y + CARD_H + 44.0

var _panel: Panel
var _title_lbl: Label
var _sub_lbl: Label
var _card_row: HBoxContainer

func _ready() -> void:
	layer = 20
	_build_ui()
	visible = false

# options: Array of EquipmentItem (reward_type ITEM) or perk Dictionaries
# (reward_type STAT_BONUS), as returned by RoundReward.roll_options().
func present(options: Array, reward_type: int, round_no: int) -> void:
	var is_item: bool = reward_type == RoundReward.Type.ITEM
	_title_lbl.text = "CHOOSE AN ITEM" if is_item else "CHOOSE A STAT BONUS"
	_sub_lbl.text = "Wave %d reward  ·  pick one of %d" % [round_no, options.size()]
	# remove_child before queue_free: a queued card stays in the row until the
	# frame ends, so the new three were laid out beside the old three — the row
	# grew to six cards wide (1850px), never shrank back, and centred the new
	# cards 468px right, off the panel's edge.
	for c in _card_row.get_children():
		_card_row.remove_child(c)
		c.queue_free()
	for i in range(options.size()):
		_card_row.add_child(_item_card(options[i], i) if is_item else _perk_card(options[i], i))
	_card_row.size = Vector2(PANEL_W, CARD_H)
	visible = true
	_center_panel()

func _item_card(item: EquipmentItem, idx: int) -> Button:
	var col: Color = item.icon_color
	var btn := _card_shell(col, "ITEM")
	var icon := _icon(btn)
	icon.texture = GearIcons.icon_for(item)
	icon.modulate = col
	_lbl(btn, item.name, UITheme.FONT_HEADER, col, Vector2(0, 150), Vector2(CARD_W, 30), true)
	_lbl(btn, item.get_rarity_name(), UITheme.FONT_BODY, col.lightened(0.2),
		Vector2(0, 178), Vector2(CARD_W, 22), true)
	# to_short_string() is "Name (Rarity): stats | passives" — the name and
	# rarity are already on the card, so only what follows the colon is shown.
	var text: String = item.to_short_string()
	var colon: int = text.find(": ")
	if colon >= 0:
		text = text.substr(colon + 2)
	_body(btn, text.replace(" | ", "\n"))
	btn.pressed.connect(_on_pick.bind(idx))
	return btn

func _perk_card(perk: Dictionary, idx: int) -> Button:
	var grade: String = String(perk.get("grade", "C"))
	var col: Color = UnitFactory.GRADE_COLORS.get(grade, Color.WHITE)
	var btn := _card_shell(col, "STAT BONUS")
	var icon := _icon(btn)
	icon.texture = LevelUpScreen.perk_icon(String(perk.get("id", "")))
	_lbl(btn, "%s %s" % [LevelUpScreen.format_perk_value(perk), perk.get("label", "?")],
		UITheme.FONT_HEADER, col, Vector2(0, 150), Vector2(CARD_W, 30), true)
	_lbl(btn, "Grade %s" % grade, UITheme.FONT_BODY, col.lightened(0.2),
		Vector2(0, 178), Vector2(CARD_W, 22), true)
	_body(btn, String(LevelUpScreen.PERK_FULL_NAME.get(String(perk.get("id", "")), ""))
		+ "\nFor one hero of your choice.")
	btn.pressed.connect(_on_pick.bind(idx))
	return btn

func _card_shell(accent: Color, kicker: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
	btn.text = ""
	UITheme.paint_card(btn, accent)
	_lbl(btn, kicker, UITheme.FONT_CAPTION, Color(0.62, 0.62, 0.76),
		Vector2(0, 14), Vector2(CARD_W, 22), true)
	return btn

func _icon(btn: Button) -> TextureRect:
	var icon := TextureRect.new()
	icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position     = Vector2((CARD_W - 100) / 2.0, 40)
	icon.size         = Vector2(100, 100)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)
	return icon

func _body(btn: Button, text: String) -> void:
	var desc := Label.new()
	desc.position = Vector2(20, 208)
	desc.size     = Vector2(CARD_W - 40, CARD_H - 220)
	UITheme.apply_read_font(desc, UITheme.FONT_BODY)   # prose -> Inter (2026-09-29)
	desc.add_theme_color_override("font_color", Color(0.84, 0.84, 0.92))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	desc.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	desc.clip_text            = true
	desc.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	desc.text                 = text
	btn.add_child(desc)

func _on_pick(idx: int) -> void:
	visible = false
	chosen.emit(idx)

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color        = Color(0, 0, 0, 0.62)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.add_theme_stylebox_override("panel", UITheme.menu_surface_box())
	overlay.add_child(_panel)
	UITheme.menu_header(_panel, Rect2(18, 18, PANEL_W - 36, 112))

	_title_lbl = _lbl(_panel, "", UITheme.FONT_HEADER, UITheme.menu_title_color(),
		Vector2(0, 39), Vector2(PANEL_W, 42), true)
	_sub_lbl = _lbl(_panel, "", UITheme.FONT_BODY, UITheme.menu_subtitle_color(),
		Vector2(0, 79), Vector2(PANEL_W, 24), true)

	_card_row = HBoxContainer.new()
	_card_row.add_theme_constant_override("separation", 22)
	_card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_row.position  = Vector2(0, CARD_ROW_Y)
	_card_row.size      = Vector2(PANEL_W, CARD_H)
	_panel.add_child(_card_row)
	_center_panel()

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_panel.position = (vp - _panel.size) / 2.0

func _lbl(parent: Control, text: String, px: int, color: Color,
		pos: Vector2, sz: Vector2, centered: bool = false) -> Label:
	var l := Label.new()
	l.text     = text
	l.position = pos
	l.size     = sz
	UITheme.apply_font(l, px)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
