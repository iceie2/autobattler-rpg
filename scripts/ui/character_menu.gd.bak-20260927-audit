extends CanvasLayer
class_name CharacterMenu

signal closed()

var _player_units: Array = []
var _enemy_units: Array  = []
var _showing_players := true
var _idx := 0

# Live UI refs
var _overlay: ColorRect
var _panel: Panel
var _team_btn: Button
var _unit_idx_lbl: Label
var _unit_name_lbl: Label
var _unit_class_lbl: Label
var _unit_elem_lbl: Label
var _unit_level_lbl: Label
var _portrait: TextureRect
var _hp_bar: ProgressBar
var _mp_bar: ProgressBar
var _hp_lbl: Label
var _mp_lbl: Label
var _stat_lbl: Label
var _skill_lbl: Label
var _skill_desc_lbl: Label
var _prev_btn: Button
var _next_btn: Button

func _ready() -> void:
	_build_ui()

func open(player_units: Array, enemy_units: Array, start_on_players: bool = true) -> void:
	_player_units = player_units.filter(func(u): return u and is_instance_valid(u))
	_enemy_units  = enemy_units.filter(func(u): return u and is_instance_valid(u))
	_showing_players = start_on_players
	_idx = 0
	visible = true
	_refresh()

func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0, 0, 0, 0.65)
	_overlay.gui_input.connect(_on_overlay_input)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	_panel = Panel.new()
	_panel.size     = Vector2(680, 540)
	_panel.position = Vector2(0, 0)   # centered in _update_panel_pos
	# UI theme pass 2026-07-04: dobo card panel instead of flat navy box.
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	_overlay.add_child(_panel)

	# ── Title row ──────────────────────────────────────────────────────────────
	_lbl(_panel, "CHARACTER ROSTER", 22, Color(0.8, 0.8, 1.0),
		Vector2(0, 14), Vector2(680, 32), true)

	# Team toggle button
	_team_btn = _btn("YOUR TEAM", Rect2(20, 10, 160, 32))
	_team_btn.pressed.connect(_toggle_team)
	_panel.add_child(_team_btn)

	# Close button
	var close := _btn("✕", Rect2(638, 8, 34, 32))
	close.pressed.connect(_close)
	_panel.add_child(close)

	var sep1 := HSeparator.new()
	sep1.position = Vector2(0, 52); sep1.size = Vector2(680, 4)
	_panel.add_child(sep1)

	# ── Portrait area ──────────────────────────────────────────────────────────
	# Sprite sits directly on the panel — no intermediate background box
	# (2026-07-04 user report: panel > box > sprite should just be panel >
	# sprite).
	_portrait = TextureRect.new()
	_portrait.position = Vector2(24, 68)
	_portrait.size = Vector2(120, 120)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_panel.add_child(_portrait)

	# Class letter overlay on portrait
	_unit_level_lbl = _lbl(_panel, "", 15, Color(0, 0, 0, 0.8),
		Vector2(24, 168), Vector2(120, 22), true)

	# ── Name / class / element ─────────────────────────────────────────────────
	_unit_name_lbl  = _lbl(_panel, "", 30, Color(1, 0.9, 0.6), Vector2(160, 66), Vector2(380, 38))
	_unit_class_lbl = _lbl(_panel, "", 16, Color(0.75, 0.75, 0.9), Vector2(160, 106), Vector2(280, 24))
	_unit_elem_lbl  = _lbl(_panel, "", 16, Color(0.75, 0.9, 0.75), Vector2(160, 130), Vector2(280, 24))

	# Navigation
	_prev_btn = _btn("◀ Prev", Rect2(160, 158, 100, 32))
	_prev_btn.pressed.connect(_prev)
	_panel.add_child(_prev_btn)

	_unit_idx_lbl = _lbl(_panel, "", 16, Color(0.6, 0.6, 0.8),
		Vector2(268, 162), Vector2(100, 26), true)

	_next_btn = _btn("Next ▶", Rect2(376, 158, 100, 32))
	_next_btn.pressed.connect(_next)
	_panel.add_child(_next_btn)

	var sep2 := HSeparator.new()
	sep2.position = Vector2(0, 202); sep2.size = Vector2(680, 4)
	_panel.add_child(sep2)

	# ── HP / MP bars ──────────────────────────────────────────────────────────
	_lbl(_panel, "HP", 14, Color(0.4, 0.9, 0.4), Vector2(24, 216), Vector2(30, 18))
	_hp_bar = _bar(_panel, Rect2(58, 214, 300, 18), Color(0.2, 0.78, 0.3))
	_hp_lbl = _lbl(_panel, "", 14, Color(0.7, 0.9, 0.7), Vector2(368, 216), Vector2(140, 18))

	_lbl(_panel, "MP", 14, Color(0.4, 0.6, 1.0), Vector2(24, 240), Vector2(30, 18))
	_mp_bar = _bar(_panel, Rect2(58, 238, 300, 18), Color(0.25, 0.4, 0.9))
	_mp_lbl = _lbl(_panel, "", 14, Color(0.6, 0.7, 1.0), Vector2(368, 240), Vector2(140, 18))

	var sep3 := HSeparator.new()
	sep3.position = Vector2(0, 268); sep3.size = Vector2(680, 4)
	_panel.add_child(sep3)

	# ── Stats grid ────────────────────────────────────────────────────────────
	_lbl(_panel, "STATS", 15, Color(0.6, 0.65, 0.9), Vector2(24, 278), Vector2(100, 22))
	_stat_lbl = _lbl(_panel, "", 15, Color(0.8, 0.8, 0.95), Vector2(24, 300), Vector2(640, 100))

	var sep4 := HSeparator.new()
	sep4.position = Vector2(0, 410); sep4.size = Vector2(680, 4)
	_panel.add_child(sep4)

	# ── Skill ─────────────────────────────────────────────────────────────────
	_lbl(_panel, "SKILL", 15, Color(1.0, 0.85, 0.35), Vector2(24, 422), Vector2(80, 22))
	_skill_lbl      = _lbl(_panel, "", 17, Color(1.0, 0.85, 0.3), Vector2(110, 420), Vector2(400, 24))
	_skill_desc_lbl = _lbl(_panel, "", 14, Color(0.7, 0.7, 0.8),  Vector2(24,  448), Vector2(640, 60))
	_skill_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	visible = false
	_center_panel()

func _center_panel() -> void:
	var vp_sz := get_viewport().get_visible_rect().size
	_panel.position = (vp_sz - _panel.size) / 2

func _current_units() -> Array:
	return _player_units if _showing_players else _enemy_units

func _refresh() -> void:
	var units := _current_units()
	_team_btn.text = "YOUR TEAM" if _showing_players else "ENEMIES"

	if units.is_empty():
		_unit_name_lbl.text  = "No units"
		_portrait.texture = null
		_unit_class_lbl.text = ""
		_unit_elem_lbl.text  = ""
		_unit_level_lbl.text = ""
		_unit_idx_lbl.text   = "0 / 0"
		_hp_bar.value = 0;  _mp_bar.value = 0
		_hp_lbl.text = "";  _mp_lbl.text = ""
		_stat_lbl.text = ""
		_skill_lbl.text = ""; _skill_desc_lbl.text = ""
		return

	_idx = clamp(_idx, 0, units.size() - 1)
	var u: UnitBase = units[_idx]

	var sprite_path := "res://assets/sprites/generated/%s/0/single.png" % _class_folder(u.unit_class)
	var sheet := load(sprite_path) as Texture2D
	if sheet:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(0, 640, 64, 64)
		_portrait.texture = atlas
	else:
		_portrait.texture = null
	_unit_name_lbl.text  = u.unit_name
	_unit_class_lbl.text = "Class: " + u.get_class_name_string()
	_unit_elem_lbl.text  = "Element: " + u.get_element_name_string()
	_unit_level_lbl.text = "Lv. %d" % u.level
	_unit_idx_lbl.text   = "%d / %d" % [_idx + 1, units.size()]

	_hp_bar.max_value = u.max_hp;   _hp_bar.value = u.current_hp
	_mp_bar.max_value = u.max_mana; _mp_bar.value = u.current_mana
	_hp_lbl.text = "%d / %d" % [u.current_hp, u.max_hp]
	_mp_lbl.text = "%d / %d" % [u.current_mana, u.max_mana]

	_stat_lbl.text = (
		"ATK: %-5d   MAG: %-5d   ARM: %-4d   MR: %d\n" +
		"AS: %-4.2f   HP/s: %-4.2f   MP/s: %-4.2f\n" +
		"Speed: %-4d   Range: %d"
	) % [u.attack_damage, u.magic_power, u.resistance, u.magic_resist,
		 u.attack_speed, u.hp_regen, u.mana_regen,
		 u.movement_speed, u.attack_range]

	_skill_lbl.text = u.skill_name if u.skill_name != "" else "—"
	var cd_str := ""
	if u.skill_cooldown_max > 0:
		cd_str = "  (every %ds)" % u.skill_cooldown_max
	_skill_desc_lbl.text = "Deals %d%% dmg · Range %d%s" % [
		int(u.skill_damage_multiplier * 100), u.skill_range, cd_str]

func _prev() -> void:
	_idx = (_idx - 1 + _current_units().size()) % max(_current_units().size(), 1)
	_refresh()

func _next() -> void:
	_idx = (_idx + 1) % max(_current_units().size(), 1)
	_refresh()

func _toggle_team() -> void:
	_showing_players = not _showing_players
	_idx = 0
	_refresh()

func _close() -> void:
	visible = false
	closed.emit()

func _on_overlay_input(event: InputEvent) -> void:
	# Close on click outside the panel
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := _overlay.get_local_mouse_position()
		if not _panel.get_rect().has_point(mouse):
			_close()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close()

# ── UI helpers ────────────────────────────────────────────────────────────────
func _class_folder(unit_class: UnitBase.UnitClass) -> String:
	match unit_class:
		UnitBase.UnitClass.WARRIOR:    return "warrior"
		UnitBase.UnitClass.RANGER:     return "archer"
		UnitBase.UnitClass.MONK:       return "monk"
		UnitBase.UnitClass.THIEF:      return "thief"
		UnitBase.UnitClass.BLACK_MAGE: return "black_mage"
		UnitBase.UnitClass.WHITE_MAGE: return "white_mage"
		UnitBase.UnitClass.RED_MAGE:   return "red_mage"
		UnitBase.UnitClass.BLOODHOUND: return "warrior"
		UnitBase.UnitClass.BOUNCER:    return "monk"
		UnitBase.UnitClass.HEADHUNTER: return "archer"
		UnitBase.UnitClass.SHAUNA:    return "shauna"
		UnitBase.UnitClass.NEMI:      return "nemi"
		_: return "warrior"

func _lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos; l.size = size
	UITheme.apply_font(l, UITheme.body_font(sz))
	l.add_theme_color_override("font_color", col)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _btn(text: String, rect: Rect2, sz: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size if sz == Vector2.ZERO else sz
	UITheme.apply_font(b, UITheme.FONT_HEADER)
	b.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	b.add_theme_stylebox_override("normal",  _flat(Color(0.18, 0.18, 0.28), Color(0.45, 0.45, 0.6), 1, 4))
	b.add_theme_stylebox_override("hover",   _flat(Color(0.25, 0.25, 0.38), Color(0.6, 0.6, 0.8),  1, 4))
	b.add_theme_stylebox_override("pressed", _flat(Color(0.12, 0.12, 0.22), Color(0.3, 0.3, 0.5),  1, 4))
	return b

func _bar(parent: Node, rect: Rect2, fill_col: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.position = rect.position; pb.size = rect.size
	pb.show_percentage = false
	var fill := StyleBoxFlat.new(); fill.bg_color = fill_col
	fill.corner_radius_top_left = 3; fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_left = 3; fill.corner_radius_bottom_right = 3
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(fill_col.r*0.2, fill_col.g*0.2, fill_col.b*0.2)
	pb.add_theme_stylebox_override("fill", fill)
	pb.add_theme_stylebox_override("background", bg)
	parent.add_child(pb)
	return pb

func _flat(bg: Color, border: Color = Color.TRANSPARENT,
		bw: int = 0, radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.border_width_left = bw; s.border_width_right = bw
	s.border_width_top = bw;  s.border_width_bottom = bw
	s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius; s.corner_radius_bottom_right = radius
	return s
