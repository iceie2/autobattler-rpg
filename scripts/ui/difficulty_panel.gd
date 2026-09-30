class_name DifficultyPanel
extends VBoxContainer

signal difficulty_selected(difficulty: int)

@export var font: Font = preload("res://assets/Fonts/LeagueGothic-Regular.otf")

var current_difficulty: int = WaveScaler.Difficulty.NORMAL
var _diff_btns: Array = []
var _power_by_diff: Dictionary = {}
var _rewards_by_diff: Dictionary = {}

# ── Wave dossier (2026-07-27) ────────────────────────────────────────────────
# Placement swings win rate enormously (measured 0% → ~85% on an identical team)
# and which formation is correct depends on whether the wave's damage is melee
# or ranged — information the player previously had no way to read off a board
# of unfamiliar sprites. These two lines are that information: a name for
# flavour, and a derived count readout that stays true for every wave.
# Deliberately NOT prescriptive ("spread out here") — no formation is right in
# every matchup, so telling the player what to do would flatten real depth.
var _dossier_name: Label
var _dossier_comp: Label
var _heading_lbl: Label

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
# Renamed 2026-08-07 (user): tier 0 is the baseline everyone plays, so calling
# it "Easy" framed the default as a concession. Art filenames still say
# easy/medium/hard — the textures are unchanged, only the wording moved.
const _DIFF_NAMES := ["Normal", "Veteran", "Brutal"]
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
	# Content margins deliberately asymmetric (not 8/8) — text is vertically
	# centered WITHIN the content rect, so a much bigger bottom margin than
	# top shrinks/shifts that rect toward the top of the button, which is
	# where the user wants the (now power-number-only) text to sit.
	sb.content_margin_top = 6
	sb.content_margin_bottom = 32
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

	# ── Wave dossier — sits above the difficulty picker: what you're facing,
	# then how hard you want it. See _dossier_name / set_dossier.
	_dossier_name = Label.new()
	if font:
		_dossier_name.add_theme_font_override("font", font)
	UITheme.apply_font(_dossier_name, UITheme.FONT_HEADER)
	_dossier_name.add_theme_color_override("font_color", Color(0.90, 0.86, 0.74, 1.0))
	_dossier_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dossier_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dossier_name.visible = false
	add_child(_dossier_name)

	_dossier_comp = Label.new()
	if font:
		_dossier_comp.add_theme_font_override("font", font)
	UITheme.apply_font(_dossier_comp, UITheme.FONT_VALUE)
	_dossier_comp.add_theme_color_override("font_color", Color(0.62, 0.70, 0.78, 1.0))
	_dossier_comp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dossier_comp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dossier_comp.visible = false
	add_child(_dossier_comp)

	# Heading (held in a member so briefing mode can retitle it)
	var heading := Label.new()
	_heading_lbl = heading
	heading.text = "ENEMY DIFFICULTY"
	if font:
		heading.add_theme_font_override("font", font)
	UITheme.apply_font(heading, UITheme.FONT_HEADER)
	heading.add_theme_color_override("font_color", Color(0.83, 0.69, 0.22, 1.0))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(heading)

	# Three columns — button + power per difficulty
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)

	# Radio-style group — toggle_mode + a shared ButtonGroup means the
	# selected difficulty's button STAYS drawn with its "pressed" stylebox
	# until a different one is chosen, instead of springing back to "normal"
	# the instant the mouse is released.
	var group := ButtonGroup.new()

	_diff_btns = []
	for i in range(3):
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)

		var btn := Button.new()
		# Text is the power number only (set in update_display); the button's
		# own art already conveys which difficulty it is (green/blue/red).
		btn.text = ""
		if font:
			btn.add_theme_font_override("font", font)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 56)
		UITheme.apply_font(btn, UITheme.FONT_HEADER)
		btn.add_theme_color_override("font_color", Color(0.10, 0.08, 0.04))
		btn.add_theme_color_override("font_hover_color", Color(0.10, 0.08, 0.04))
		btn.add_theme_color_override("font_pressed_color", Color(0.05, 0.04, 0.02))
		var art: Dictionary = _DIFF_ART[i]
		var normal_box := _diff_tex_box(art["normal"])
		var pressed_box := _diff_tex_box(art["pressed"])
		btn.add_theme_stylebox_override("normal", normal_box)
		btn.add_theme_stylebox_override("hover", normal_box)
		btn.add_theme_stylebox_override("pressed", pressed_box)
		# Kill Godot's default focus-ring stylebox — otherwise whichever button
		# was last clicked keeps a light focus box drawn over the pixel art.
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.focus_mode = Control.FOCUS_NONE
		btn.toggle_mode = true
		btn.button_group = group
		btn.button_pressed = (i == current_difficulty)   # Easy selected by default
		btn.pressed.connect(_on_difficulty_button_pressed.bind(i))
		col.add_child(btn)
		_diff_btns.append(btn)

		var name_lbl := Label.new()
		name_lbl.text = _DIFF_NAMES[i]
		if font:
			name_lbl.add_theme_font_override("font", font)
		UITheme.apply_font(name_lbl, UITheme.FONT_HEADER)
		name_lbl.add_theme_color_override("font_color", Color(0.78, 0.78, 0.88))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name_lbl)

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
	UITheme.apply_font(_reward_lbl, UITheme.FONT_HEADER)
	_reward_lbl.add_theme_color_override("font_color", Color(0.83, 0.69, 0.22, 0.95))
	_reward_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reward_box.add_child(_reward_lbl)

	_build_tooltip()

func _on_difficulty_button_pressed(diff: int) -> void:
	if briefing_only or diff == current_difficulty:
		return
	current_difficulty = diff
	_update_button_colors()
	_refresh_reward_display()
	difficulty_selected.emit(diff)

# ── Briefing mode (2026-09-19, RUN_MAP_PLAN §3.4) ─────────────────────────────
# When the run map is driving, INTENSITY IS A PATHING CHOICE: you picked it on
# the map, before the board was dealt. This panel then stops being a picker and
# becomes the briefing — the wave dossier and the reward that the node you chose
# has already rolled. The tier buttons stay on screen (they're how the player
# reads which tier they took) but no longer take input.
#
# The dossier is the part that MUST survive the move: placement legibility was
# measured as the real gap (see the placement_sensitivity work), and a map that
# took the dossier away would trade a measured win for a new feature.
var briefing_only: bool = false

func set_briefing_only(on: bool) -> void:
	briefing_only = on
	for b in _diff_btns:
		if b:
			b.mouse_default_cursor_shape = Control.CURSOR_ARROW if on else Control.CURSOR_POINTING_HAND
	if _heading_lbl:
		_heading_lbl.text = "THIS FIGHT" if on else "ENEMY DIFFICULTY"

func set_panel_visible(show: bool) -> void:
	visible = show
	if not show:
		_hide_tooltip()

# Wave dossier. `wave_name` may be "" (elite/boss rounds name themselves,
# generated Act 7 waves have no fixed identity) — that line just hides.
# `profile` is WaveScaler.threat_profile(spec); zero-count buckets are omitted
# so the line stays short and every term on it carries information.
func set_dossier(wave_name: String, profile: Dictionary) -> void:
	if not _dossier_name:
		return
	_dossier_name.text = wave_name
	_dossier_name.visible = wave_name != ""

	var parts := PackedStringArray()
	if int(profile.get("melee", 0))   > 0: parts.append("%d melee"   % profile["melee"])
	if int(profile.get("ranged", 0))  > 0: parts.append("%d ranged"  % profile["ranged"])
	if int(profile.get("support", 0)) > 0: parts.append("%d support" % profile["support"])
	if int(profile.get("large", 0))   > 0: parts.append("%d large"   % profile["large"])
	_dossier_comp.text = " · ".join(parts)
	_dossier_comp.visible = not parts.is_empty()

# power_by_diff:   {EASY: 45.0, NORMAL: 90.0, HARD: 180.0}
# rewards_by_diff: {EASY: {type:...}, NORMAL: {...}, HARD: {...}} — already
# rolled once for the round (see main_game.gd). Only the currently selected
# difficulty's reward is shown; switch difficulty to see the others.
func update_display(power_by_diff: Dictionary, rewards_by_diff: Dictionary = {}) -> void:
	_power_by_diff = power_by_diff
	_update_button_colors()
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
				var tex: Texture2D = GearIcons.icon_for(item)   # legacy art or component composite
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
				var _v: float = p.get("rolled_value", p.get("value", 0))
				var val_str: String = LevelUpScreen.format_perk_value(p)
				_reward_lbl.text = "Reward: %s %s" % [p.get("label", "?"), val_str]
			else:
				_reward_lbl.text = "Reward: Stat Bonus"
		RoundReward.Type.GOLD:
			_reward_lbl.text = "Reward: +%d Gold" % int(reward.get("gold", 0))
		_:
			# No bonus reward this round — leave the area blank instead of
			# calling it out ("Reward: Nothing" read as needlessly blunt).
			_reward_lbl.text = ""

# ── Item tooltip (name / rarity / stats / passive) ────────────────────────────
func _build_tooltip() -> void:
	_tip_layer = CanvasLayer.new()
	_tip_layer.layer = 30
	add_child(_tip_layer)

	_tip_panel = PanelContainer.new()
	_tip_panel.custom_minimum_size = Vector2(320, 0)
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
	UITheme.apply_font(_tip_name_lbl, UITheme.FONT_HEADER)
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
	UITheme.apply_font(_tip_passive_lbl, UITheme.FONT_HEADER)
	_tip_passive_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_tip_passive_lbl.visible = false
	vb.add_child(_tip_passive_lbl)

	_tip_passive_desc = Label.new()
	UITheme.apply_font(_tip_passive_desc, UITheme.FONT_VALUE)
	_tip_passive_desc.add_theme_color_override("font_color", Color(0.70, 0.70, 0.82))
	_tip_passive_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_passive_desc.custom_minimum_size = Vector2(304, 0)
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
		"res": "Armor", "aspd": "Attack Speed", "hpregen": "HP Regen", "manaregen": "MP Regen",
		"crit": "Crit Chance", "critdmg": "Crit Damage",
	}
	const FLOAT_STATS := ["aspd", "hpregen", "manaregen"]
	for stat in ["hp", "mana", "atk", "magic", "res", "aspd", "hpregen", "manaregen", "crit", "critdmg"]:
		var v: float = float(item.stat_bonus.get(stat, 0))
		if v > 0:
			var lbl := Label.new()
			if stat == "crit":
				lbl.text = "+%d%%  %s" % [int(round(v * 100.0)), STAT_NAMES[stat]]
			elif stat == "critdmg":
				lbl.text = "+%.2fx  %s" % [v, STAT_NAMES[stat]]
			else:
				lbl.text = ("+%.2f  %s" % [v, STAT_NAMES.get(stat, stat.to_upper())]) if stat in FLOAT_STATS \
					else ("+%d  %s" % [int(v), STAT_NAMES.get(stat, stat.to_upper())])
			UITheme.apply_font(lbl, UITheme.FONT_VALUE)
			lbl.add_theme_color_override("font_color", Color(0.82, 0.96, 0.72))
			_tip_stats_vb.add_child(lbl)

	# One resolved line per passive rather than a bare list of names.
	if not item.passives.is_empty():
		_tip_passive_lbl.text = "◆ Passives"
		_tip_passive_lbl.visible = true
		_tip_passive_desc.text = "\n".join(item.get_passive_lines())
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
	# modulate only handles the selected/unselected dimming. button_pressed
	# is re-synced here too since main_game sets current_difficulty directly
	# (e.g. resetting to EASY each round) without going through the click
	# handler, and the ButtonGroup's own auto-untoggle only fires on click.
	# Keep every power number visible, including the selected tier. The map
	# promised this exact threat value, so the battle briefing should confirm it
	# rather than replacing the number with an empty pressed tile.
	for i in range(_diff_btns.size()):
		var btn: Button = _diff_btns[i]
		var selected: bool = (i == current_difficulty)
		btn.modulate = Color(1, 1, 1) if selected else Color(0.6, 0.6, 0.6)
		btn.button_pressed = selected
		btn.text = "%d" % int(_power_by_diff.get(i, 0.0))
