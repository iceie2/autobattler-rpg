class_name DifficultyPanel
extends VBoxContainer

signal difficulty_selected(difficulty: int)

@export var font: Font = preload("res://assets/Fonts/LeagueGothic-Regular.otf")

var current_difficulty: int = WaveScaler.Difficulty.EASY
var _diff_btns: Array = []
var _diff_labels: Array = ["★ Easy", "★★ Normal", "★★★ Hard"]
var _rewards_by_diff: Dictionary = {}

# Difficulty button art (2026-07-04, user-picked tiles from the pixel-button
# sheet — see assets/UI/Pixel Buttom.png, 32px grid). Each button is a 2-tile
# (64x32 native) pill, cropped+3x-scaled into assets/UI/generated/. The user
# supplied exact (row, col) coords per difficulty; normal/pressed are genuinely
# distinct art (raised bevel + drop-shadow "foot" vs. flat sunken look), not a
# modulate trick — pressing these buttons now visibly animates.
const _DIFF_ART := [
	{"normal": "diff_easy_normal.png",   "pressed": "diff_easy_pressed.png"},
	{"normal": "diff_medium_normal.png", "pressed": "diff_medium_pressed.png"},
	{"normal": "diff_hard_normal.png",   "pressed": "diff_hard_pressed.png"},
]
const _DIFF_ART_PATH := "res://assets/UI/generated/"
# Margins found by sampling the source pixel art directly (see session notes):
# the left/right end-caps end by ~x=20 of the 192px-wide (3x) texture, and
# rows 40-55 of the 96px-tall texture sit inside a single flat-color band, so
# stretching there is invisible — these margins keep every cap/bevel detail
# fixed and only stretch through genuinely flat regions.
const _DIFF_BTN_MARGIN_H := 30
const _DIFF_BTN_MARGIN_V := 40

static func _diff_tex_box(path: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(_DIFF_ART_PATH + path) as Texture2D
	sb.texture_margin_left = _DIFF_BTN_MARGIN_H
	sb.texture_margin_right = _DIFF_BTN_MARGIN_H
	sb.texture_margin_top = _DIFF_BTN_MARGIN_V
	sb.texture_margin_bottom = _DIFF_BTN_MARGIN_V
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

# Single reward display (only the CURRENTLY selected difficulty's reward is
# shown — switch difficulty to see the others).
var _reward_box: VBoxContainer
var _reward_slot: PanelContainer   # 1x1 item-bag-style slot (rarity-tinted bg/border)
var _reward_icon: TextureRect
var _reward_lbl: Label
const REWARD_SLOT_SIZE := 36.0

# Hover tooltip for item rewards (name / rarity / stats / passive)
var _tip_layer: CanvasLayer
var _tip_panel: PanelContainer
var _tip_name_lbl: Label
var _tip_stats_vb: VBoxContainer
var _tip_passive_lbl: Label
var _tip_passive_desc: Label
var _hovered_item: EquipmentItem = null

func _ready() -> void:
	_build_ui()

func _process(_delta: float) -> void:
	if _tip_panel and _tip_panel.visible:
		_tip_panel.global_position = get_viewport().get_mouse_position() + Vector2(16, -_tip_panel.size.y * 0.5)

func _build_ui() -> void:
	add_theme_constant_override("separation", 5)
	visible = false

	# Heading
	var heading := Label.new()
	heading.text = "ENEMY DIFFICULTY"
	if font:
		heading.add_theme_font_override("font", font)
	heading.add_theme_font_size_override("font_size", 26)
	heading.add_theme_color_override("font_color", Color(0.83, 0.69, 0.22, 1.0))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(heading)

	# Three columns — button + power per difficulty
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)

	_diff_btns = []
	for i in range(3):
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)

		var btn := Button.new()
		# Power text is now the button's own second line (see update_display) —
		# moved onto the button per user request, replacing the separate label
		# that used to sit below it.
		btn.text = _diff_labels[i]
		if font:
			btn.add_theme_font_override("font", font)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 56)
		btn.add_theme_font_size_override("font_size", 18)
		btn.add_theme_color_override("font_color", Color(0.10, 0.08, 0.04))
		btn.add_theme_color_override("font_hover_color", Color(0.10, 0.08, 0.04))
		btn.add_theme_color_override("font_pressed_color", Color(0.05, 0.04, 0.02))
		var art: Dictionary = _DIFF_ART[i]
		var normal_box := _diff_tex_box(art["normal"])
		var pressed_box := _diff_tex_box(art["pressed"])
		btn.add_theme_stylebox_override("normal", normal_box)
		btn.add_theme_stylebox_override("hover", normal_box)
		btn.add_theme_stylebox_override("pressed", pressed_box)
		btn.pressed.connect(_on_difficulty_button_pressed.bind(i))
		col.add_child(btn)
		_diff_btns.append(btn)

	# Single reward display for whichever difficulty is currently selected —
	# item icon sits centered in its own 1x1 bag-style slot, name/rarity below.
	_reward_box = VBoxContainer.new()
	_reward_box.add_theme_constant_override("separation", 3)
	_reward_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_reward_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_reward_box)

	_reward_slot = PanelContainer.new()
	_reward_slot.custom_minimum_size = Vector2(REWARD_SLOT_SIZE, REWARD_SLOT_SIZE)
	_reward_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reward_slot.mouse_filter = Control.MOUSE_FILTER_STOP
	_reward_slot.visible = false
	_reward_slot.mouse_entered.connect(_on_reward_icon_hover)
	_reward_slot.mouse_exited.connect(_on_reward_icon_unhover)
	_reward_box.add_child(_reward_slot)

	_reward_icon = TextureRect.new()
	_reward_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_reward_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_reward_icon.custom_minimum_size = Vector2(REWARD_SLOT_SIZE - 8, REWARD_SLOT_SIZE - 8)
	_reward_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_mg := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		icon_mg.add_theme_constant_override(k, 4)
	icon_mg.add_child(_reward_icon)
	_reward_slot.add_child(icon_mg)

	_reward_lbl = Label.new()
	_reward_lbl.text = ""
	if font:
		_reward_lbl.add_theme_font_override("font", font)
	_reward_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward_lbl.add_theme_font_size_override("font_size", 22)
	_reward_lbl.add_theme_color_override("font_color", Color(0.83, 0.69, 0.22, 0.95))
	_reward_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reward_box.add_child(_reward_lbl)

	_build_tooltip()

func _on_difficulty_button_pressed(diff: int) -> void:
	if diff == current_difficulty:
		return
	current_difficulty = diff
	_update_button_colors()
	_refresh_reward_display()
	difficulty_selected.emit(diff)

func set_panel_visible(show: bool) -> void:
	visible = show
	if not show:
		_hide_tooltip()

# power_by_diff:   {EASY: 45.0, NORMAL: 90.0, HARD: 180.0}
# rewards_by_diff: {EASY: {type:...}, NORMAL: {...}, HARD: {...}} — already
# rolled once for the round (see main_game.gd). Only the currently selected
# difficulty's reward is shown; switch difficulty to see the others.
func update_display(power_by_diff: Dictionary, rewards_by_diff: Dictionary = {}) -> void:
	_update_button_colors()
	for i in range(3):
		var power: float = power_by_diff.get(i, 0.0)
		_diff_btns[i].text = "%s\nPower: %d" % [_diff_labels[i], int(power)]
	_rewards_by_diff = rewards_by_diff
	_refresh_reward_display()

func _refresh_reward_display() -> void:
	var reward: Dictionary = _rewards_by_diff.get(current_difficulty, {})
	_hide_tooltip()
	_hovered_item = null
	_reward_slot.visible = false
	_reward_icon.texture = null

	match reward.get("type", RoundReward.Type.NOTHING):
		RoundReward.Type.ITEM:
			var item: EquipmentItem = reward.get("item")
			if item:
				_hovered_item = item
				var icon_path: String = EquipmentManager.ITEM_ICONS.get(item.name, "")
				if icon_path != "":
					var tex: Texture2D = load(icon_path)
					if tex:
						_reward_icon.texture = tex
						_reward_icon.modulate = item.icon_color
				# Bag-slot look: rarity-tinted background + border, same as the
				# inventory/bag slots elsewhere in the UI.
				var slot_bg := StyleBoxFlat.new()
				slot_bg.bg_color = item.icon_color.darkened(0.55)
				slot_bg.border_color = item.icon_color
				slot_bg.set_border_width_all(1)
				slot_bg.corner_radius_top_left = 4; slot_bg.corner_radius_top_right = 4
				slot_bg.corner_radius_bottom_left = 4; slot_bg.corner_radius_bottom_right = 4
				_reward_slot.add_theme_stylebox_override("panel", slot_bg)
				_reward_slot.visible = true
				_reward_lbl.text = "Reward: %s (%s)" % [item.name, item.get_rarity_name()]
			else:
				_reward_lbl.text = "Reward: Item"
		RoundReward.Type.STAT_BONUS:
			var p: Dictionary = reward.get("perk", {})
			if not p.is_empty():
				var v: float = p.get("rolled_value", p.get("value", 0))
				var val_str: String = ("+%.2f" % v) if p.get("id", "") in ["aspd", "regen"] else ("+%d" % int(v))
				_reward_lbl.text = "Reward: %s %s" % [p.get("label", "?"), val_str]
			else:
				_reward_lbl.text = "Reward: Stat Bonus"
		RoundReward.Type.GOLD:
			_reward_lbl.text = "Reward: +%d Gold" % int(reward.get("gold", 0))
		_:
			_reward_lbl.text = "Reward: Nothing"

# ── Item tooltip (name / rarity / stats / passive) ────────────────────────────
func _build_tooltip() -> void:
	_tip_layer = CanvasLayer.new()
	_tip_layer.layer = 30
	add_child(_tip_layer)

	_tip_panel = PanelContainer.new()
	_tip_panel.custom_minimum_size = Vector2(190, 0)
	_tip_panel.visible = false
	var s := StyleBoxFlat.new()
	s.bg_color     = Color(0.06, 0.05, 0.10, 0.97)
	s.border_color = Color(0.50, 0.42, 0.72, 0.9)
	s.set_border_width_all(1)
	s.corner_radius_top_left = 5; s.corner_radius_top_right = 5
	s.corner_radius_bottom_left = 5; s.corner_radius_bottom_right = 5
	_tip_panel.add_theme_stylebox_override("panel", s)
	_tip_layer.add_child(_tip_panel)

	var mg := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mg.add_theme_constant_override(k, 8)
	_tip_panel.add_child(mg)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	mg.add_child(vb)

	_tip_name_lbl = Label.new()
	_tip_name_lbl.add_theme_font_size_override("font_size", 15)
	vb.add_child(_tip_name_lbl)

	var sep := HSeparator.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0.4, 0.35, 0.55, 0.6)
	sep.add_theme_stylebox_override("separator", ss)
	vb.add_child(sep)

	_tip_stats_vb = VBoxContainer.new()
	_tip_stats_vb.add_theme_constant_override("separation", 2)
	vb.add_child(_tip_stats_vb)

	_tip_passive_lbl = Label.new()
	_tip_passive_lbl.add_theme_font_size_override("font_size", 13)
	_tip_passive_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_tip_passive_lbl.visible = false
	vb.add_child(_tip_passive_lbl)

	_tip_passive_desc = Label.new()
	_tip_passive_desc.add_theme_font_size_override("font_size", 12)
	_tip_passive_desc.add_theme_color_override("font_color", Color(0.70, 0.70, 0.82))
	_tip_passive_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_passive_desc.custom_minimum_size = Vector2(174, 0)
	_tip_passive_desc.visible = false
	vb.add_child(_tip_passive_desc)

func _on_reward_icon_hover() -> void:
	if not _hovered_item:
		return
	var item := _hovered_item
	_tip_name_lbl.text = "%s  ·  %s" % [item.name, item.get_rarity_name()]
	_tip_name_lbl.add_theme_color_override("font_color", item.icon_color.lightened(0.25))

	for c in _tip_stats_vb.get_children():
		c.free()
	const STAT_NAMES := {
		"hp": "HP", "mana": "Mana", "atk": "ATK", "magic": "Magic Power",
		"res": "Defense", "aspd": "Attack Speed", "hpregen": "HP Regen", "manaregen": "MP Regen",
	}
	const FLOAT_STATS := ["aspd", "hpregen", "manaregen"]
	for stat in ["hp", "mana", "atk", "magic", "res", "aspd", "hpregen", "manaregen"]:
		var v: float = float(item.stat_bonus.get(stat, 0))
		if v > 0:
			var lbl := Label.new()
			lbl.text = ("+%.2f  %s" % [v, STAT_NAMES.get(stat, stat.to_upper())]) if stat in FLOAT_STATS \
				else ("+%d  %s" % [int(v), STAT_NAMES.get(stat, stat.to_upper())])
			lbl.add_theme_font_size_override("font_size", 13)
			lbl.add_theme_color_override("font_color", Color(0.82, 0.96, 0.72))
			_tip_stats_vb.add_child(lbl)

	if item.passive_effect != "":
		_tip_passive_lbl.text = "◆ " + item.passive_effect
		_tip_passive_lbl.visible = true
		_tip_passive_desc.text = item.description
		_tip_passive_desc.visible = true
	else:
		_tip_passive_lbl.visible = false
		_tip_passive_desc.visible = false

	_tip_panel.visible = true

func _on_reward_icon_unhover() -> void:
	_hide_tooltip()

func _hide_tooltip() -> void:
	if _tip_panel:
		_tip_panel.visible = false

func _update_button_colors() -> void:
	# Color now comes from the art itself (green/blue/red per difficulty) —
	# modulate only handles the selected/unselected dimming.
	for i in range(_diff_btns.size()):
		var btn: Button = _diff_btns[i]
		btn.modulate = Color(1, 1, 1) if i == current_difficulty else Color(0.6, 0.6, 0.6)
