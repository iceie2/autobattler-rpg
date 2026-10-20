extends CanvasLayer
class_name CharacterMenu

# "View Roster": page through your team (or the enemy side) one unit at a time.
#
# Rebuilt 2026-09-27 (screen audit). The old screen had fallen behind the rest
# of the game: a private LPC sprite table (Bloodhound was drawn as a pink-haired
# human), the legacy single-skill readout ("Bite: 130% dmg") instead of the
# passive / active / ultimate kit, a "Lv." label sitting on the portrait's feet,
# and the old striped panel. Now:
#  - portrait: HeroPortrait for heroes (the same art as the shop / reward
#    screens), UnitDetailsController.portrait_texture for everything else;
#  - kit: AbilityFormulas rows for heroes (live numbers), the EnemyFactory
#    passive/skill/ultimate metas for enemies — same sources as Unit Details;
#  - chrome: menu_header banner + menu_surface_box, gold buttons, dark & light.

signal closed()

const PANEL_W := 760.0
const PANEL_H := 800.0
const PORTRAIT := 164.0
const KIT_TOP := 482.0   # stat grid is 3 rows from y 362; the rule sits below it

const SLOT_LABELS := ["PASSIVE", "ACTIVE", "ULTIMATE"]
const SLOT_COLORS := [Color(0.55, 0.78, 0.95), Color(0.95, 0.80, 0.42), Color(0.85, 0.55, 0.98)]
const SLOT_COLORS_LIGHT := [Color(0.16, 0.40, 0.66), Color(0.58, 0.40, 0.04), Color(0.50, 0.20, 0.64)]

# [icon key, label, getter] — getter reads the live unit.
const STAT_ROWS := [
	["atk", "ATK"], ["magic", "MAG"], ["res", "ARM"], ["mres", "MR"],
	["aspd", "AS"], ["hpregen", "HP/s"], ["manaregen", "MP/s"], ["move", "SPD"],
	["range", "RNG"], ["crit_chance", "CRIT"], ["crit_damage", "CDMG"],
]

var _player_units: Array = []
var _enemy_units: Array  = []
var _showing_players := true
var _idx := 0

var _overlay: ColorRect
var _panel: Panel
var _title_lbl: Label
var _sub_lbl: Label
var _team_btn: Button
var _enemy_btn: Button
var _portrait_tex: TextureRect
var _portrait_anim: HeroPortrait
var _name_lbl: Label
var _meta_lbl: Label
var _hp_bar: ProgressBar
var _mp_bar: ProgressBar
var _hp_lbl: Label
var _mp_lbl: Label
var _stat_vals: Dictionary = {}   # icon key -> Label
var _kit_box: VBoxContainer
var _empty_lbl: Label
var _prev_btn: Button
var _next_btn: Button
var _idx_lbl: Label

func _ready() -> void:
	_build_ui()

func open(player_units: Array, enemy_units: Array, start_on_players: bool = true) -> void:
	_player_units = player_units.filter(func(u): return u and is_instance_valid(u))
	_enemy_units  = enemy_units.filter(func(u): return u and is_instance_valid(u))
	_showing_players = start_on_players
	_idx = 0
	visible = true
	_center_panel()
	_refresh()

# ── Build ─────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0, 0, 0, 0.65)
	_overlay.gui_input.connect(_on_overlay_input)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.add_theme_stylebox_override("panel", UITheme.menu_surface_box())
	_overlay.add_child(_panel)
	UITheme.menu_header(_panel, Rect2(18, 18, PANEL_W - 36, 100))

	_title_lbl = _t("CHARACTER ROSTER", UITheme.FONT_DISPLAY, UITheme.menu_title_color(),
		Vector2(0, 30), Vector2(PANEL_W, 48))
	_sub_lbl = _t("", UITheme.FONT_BODY, UITheme.menu_subtitle_color(),
		Vector2(0, 76), Vector2(PANEL_W, 24))

	var close := _gold("✕", Rect2(PANEL_W - 70, 44, 44, 44))
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(_close)

	# Team / enemy toggle — two tabs; the inactive one is the secondary style.
	_team_btn = _gold("Your Team", Rect2(30, 130, 160, 40))
	_team_btn.pressed.connect(func(): _set_side(true))
	_enemy_btn = _gold("Enemies", Rect2(198, 130, 160, 40))
	_enemy_btn.pressed.connect(func(): _set_side(false))

	# ── Portrait + identity ───────────────────────────────────────────────────
	_portrait_tex = TextureRect.new()
	_portrait_tex.position = Vector2(30, 186)
	_portrait_tex.size = Vector2(PORTRAIT, PORTRAIT)
	_portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_portrait_tex)
	_portrait_anim = HeroPortrait.new()
	_portrait_anim.position = _portrait_tex.position
	_portrait_anim.size = _portrait_tex.size
	_portrait_anim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_portrait_anim)

	var x0 := 220.0
	var w := PANEL_W - x0 - 30.0
	_name_lbl = _t("", UITheme.FONT_DISPLAY, UITheme.menu_title_color(),
		Vector2(x0, 186), Vector2(w, 50), HORIZONTAL_ALIGNMENT_LEFT)
	_meta_lbl = _t("", UITheme.FONT_VALUE, UITheme.menu_subtitle_color(),
		Vector2(x0, 236), Vector2(w, 26), HORIZONTAL_ALIGNMENT_LEFT)

	_t("HP", UITheme.FONT_BODY, UITheme.BAR_HP, Vector2(x0, 280), Vector2(34, 22),
		HORIZONTAL_ALIGNMENT_LEFT)
	_hp_bar = _bar(Rect2(x0 + 38, 282, w - 170, 18), "hp")
	_hp_lbl = _t("", UITheme.FONT_VALUE, UITheme.menu_body_color(),
		Vector2(PANEL_W - 30 - 124, 280), Vector2(124, 22), HORIZONTAL_ALIGNMENT_RIGHT)
	_t("MP", UITheme.FONT_BODY, UITheme.BAR_MP, Vector2(x0, 310), Vector2(34, 22),
		HORIZONTAL_ALIGNMENT_LEFT)
	_mp_bar = _bar(Rect2(x0 + 38, 312, w - 170, 18), "mp")
	_mp_lbl = _t("", UITheme.FONT_VALUE, UITheme.menu_body_color(),
		Vector2(PANEL_W - 30 - 124, 310), Vector2(124, 22), HORIZONTAL_ALIGNMENT_RIGHT)

	# ── Stat grid: icon + label + value, 4 columns ────────────────────────────
	var grid := GridContainer.new()
	grid.columns = 4
	grid.position = Vector2(30, 362)
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 4)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(grid)
	for spec in STAT_ROWS:
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(152, 24)
		cell.add_theme_constant_override("separation", 6)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.tooltip_text = str(UnitFactory.STAT_NAMES.get(spec[0], spec[1]))
		grid.add_child(cell)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.texture = load(UnitFactory.STAT_ICONS[spec[0]]) as Texture2D
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon)
		cell.add_child(_cell_lbl(spec[1], UITheme.menu_subtitle_color(), 48))
		_stat_vals[spec[0]] = _cell_lbl("", UITheme.menu_body_color(), 72)
		cell.add_child(_stat_vals[spec[0]])

	var rule := ColorRect.new()
	rule.position = Vector2(30, KIT_TOP - 12)
	rule.size = Vector2(PANEL_W - 60, 1)
	rule.color = Color(UITheme.menu_subtitle_color(), 0.35)
	_panel.add_child(rule)

	# ── Kit: rows flow in a VBox, so a long description pushes the next row
	# down instead of running into it (the hero-shop bug, not repeated here).
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30, KIT_TOP)
	scroll.size = Vector2(PANEL_W - 60, PANEL_H - KIT_TOP - 86)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_kit_box = VBoxContainer.new()
	_kit_box.custom_minimum_size = Vector2(PANEL_W - 76, 0)
	_kit_box.add_theme_constant_override("separation", 12)
	scroll.add_child(_kit_box)

	_empty_lbl = _t("", UITheme.FONT_VALUE, UITheme.menu_subtitle_color(),
		Vector2(0, 300), Vector2(PANEL_W, 30))

	# ── Paging ────────────────────────────────────────────────────────────────
	_prev_btn = _gold("◀  Prev", Rect2(30, PANEL_H - 70, 150, 44))
	_prev_btn.pressed.connect(_prev)
	_idx_lbl = _t("", UITheme.FONT_VALUE, UITheme.menu_subtitle_color(),
		Vector2(0, PANEL_H - 66), Vector2(PANEL_W, 36))
	_next_btn = _gold("Next  ▶", Rect2(PANEL_W - 180, PANEL_H - 70, 150, 44))
	_next_btn.pressed.connect(_next)

	visible = false
	_center_panel()

func _center_panel() -> void:
	var vp_sz := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_panel.position = (vp_sz - _panel.size) / 2

# ── Refresh ───────────────────────────────────────────────────────────────────
func _current_units() -> Array:
	return _player_units if _showing_players else _enemy_units

func _refresh() -> void:
	var units := _current_units()
	_title_lbl.text = "YOUR TEAM" if _showing_players else "ENEMIES"
	_paint_tabs()
	for c in _kit_box.get_children():
		c.queue_free()

	var has := not units.is_empty()
	for n in [_portrait_tex, _portrait_anim, _name_lbl, _meta_lbl, _hp_bar, _mp_bar,
			_hp_lbl, _mp_lbl, _prev_btn, _next_btn, _idx_lbl]:
		(n as CanvasItem).visible = has
	for k in _stat_vals:
		(_stat_vals[k] as Label).get_parent().visible = has
	_empty_lbl.visible = not has
	if not has:
		_sub_lbl.text = ""
		_empty_lbl.text = "No heroes on your team yet." if _showing_players \
			else "No enemies on the board right now."
		return

	_idx = clampi(_idx, 0, units.size() - 1)
	var u: UnitBase = units[_idx]
	var is_hero: bool = VisualUnit.HERO_SPRITE_PATHS.has(u.unit_class)
	_sub_lbl.text = "%s %d of %d" % ["Hero" if _showing_players else "Enemy", _idx + 1, units.size()]
	_idx_lbl.text = "%d / %d" % [_idx + 1, units.size()]
	_prev_btn.disabled = units.size() < 2
	_next_btn.disabled = units.size() < 2

	# Portrait
	_portrait_anim.visible = is_hero
	_portrait_tex.visible = not is_hero
	if is_hero:
		_portrait_anim.setup(u.unit_class)
	else:
		_portrait_tex.texture = UnitDetailsController.portrait_texture(u)

	# Identity — class name for heroes (the element is on the next line), the
	# unit's own name for enemies (their class names are internal).
	var elem_col: Color = SynergyData.element_color(u.current_element)
	if UITheme.is_light():
		elem_col = elem_col.darkened(0.45)
	_name_lbl.text = u.get_class_name_string() if is_hero else u.unit_name
	_name_lbl.add_theme_color_override("font_color", elem_col)
	var parts: Array[String] = [u.get_element_name_string()]
	if is_hero:
		parts.append(HeroShop.role_name(u.unit_class))
	parts.append("Lv %d" % u.level)
	_meta_lbl.text = "  ·  ".join(parts)

	_hp_bar.max_value = u.max_hp;   _hp_bar.value = u.current_hp
	_mp_bar.max_value = u.max_mana; _mp_bar.value = u.current_mana
	_hp_lbl.text = "%d / %d" % [u.current_hp, u.max_hp]
	_mp_lbl.text = "%d / %d" % [u.current_mana, u.max_mana]

	var vals := {
		"atk": str(u.attack_damage), "magic": str(u.magic_power),
		"res": str(u.resistance), "mres": str(u.magic_resist),
		"aspd": "%.2f" % u.attack_speed, "hpregen": "%.2f" % u.hp_regen,
		"manaregen": "%.2f" % u.mana_regen, "move": str(u.movement_speed),
		"range": str(u.attack_range), "crit_chance": "%d%%" % int(round(u.crit_chance * 100.0)),
		"crit_damage": "%.2fx" % u.crit_damage,
	}
	for k in _stat_vals:
		(_stat_vals[k] as Label).text = vals.get(k, "")

	for row in _kit_rows(u):
		_add_kit_row(row[0], row[1], row[2])

# [slot index, ability name, bbcode description] per filled slot.
func _kit_rows(u: UnitBase) -> Array:
	var out: Array = []
	if u.is_player_unit and AbilityFormulas.has_entry(u.unit_class, AbilityFormulas.PASSIVE):
		var slots := [AbilityFormulas.PASSIVE, AbilityFormulas.ACTIVE, AbilityFormulas.ULTIMATE]
		for i in 3:
			var r: Dictionary = AbilityFormulas.resolve(u, slots[i])
			var body: String = str(r.get("template", ""))
			for t in r.get("terms", []):
				body = body.replace("{%s}" % t["id"], "[color=#%s]%s[/color]"
					% [_value_hex(), t["display"]])
			out.append([i, str(r.get("name", "")), body])
		return out
	# Enemies: the same metas Unit Details reads (EnemyFactory sets them).
	var enemy_slots := [
		[String(u.get_meta("passive_name", "")), AutoBattleManager.magma_pulse_description(u)
			if u.get_meta("mob_passive", "") == "magma_pulse" else String(u.get_meta("passive_desc", ""))],
		[u.skill_name, u.skill_description],
		[u.ultimate_name, String(u.get_meta("ultimate_desc", ""))],
	]
	for i in 3:
		if enemy_slots[i][0] != "" or enemy_slots[i][1] != "":
			out.append([i, enemy_slots[i][0], enemy_slots[i][1]])
	if out.is_empty():
		out.append([1, "No abilities", "Basic attacks only."])
	return out

func _add_kit_row(slot: int, aname: String, body: String) -> void:
	var cols: Array = SLOT_COLORS_LIGHT if UITheme.is_light() else SLOT_COLORS
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := Label.new()
	tag.text = SLOT_LABELS[slot]
	tag.custom_minimum_size = Vector2(96, 0)
	UITheme.apply_font(tag, UITheme.FONT_BODY)
	tag.add_theme_color_override("font_color", cols[slot])
	head.add_child(tag)
	var nm := Label.new()
	nm.text = aname if aname != "" else "—"
	UITheme.apply_font(nm, UITheme.FONT_VALUE)
	nm.add_theme_color_override("font_color", cols[slot])
	head.add_child(nm)

	var desc := RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.scroll_active = false
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(PANEL_W - 76, 0)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_read_rich(desc)
	desc.add_theme_color_override("default_color", UITheme.menu_body_color())
	desc.text = body

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(head)
	row.add_child(desc)
	_kit_box.add_child(row)

func _value_hex() -> String:
	return "5a3a0a" if UITheme.is_light() else "ffffff"

func _paint_tabs() -> void:
	# Active side = full gold button; the other = the dimmed secondary style.
	UITheme.style_button(_team_btn if _showing_players else _enemy_btn)
	UITheme.style_button_secondary(_enemy_btn if _showing_players else _team_btn)

# ── Navigation ────────────────────────────────────────────────────────────────
func _prev() -> void:
	_idx = (_idx - 1 + _current_units().size()) % maxi(_current_units().size(), 1)
	_refresh()

func _next() -> void:
	_idx = (_idx + 1) % maxi(_current_units().size(), 1)
	_refresh()

func _set_side(players: bool) -> void:
	if _showing_players == players:
		return
	_showing_players = players
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
	elif event.is_action_pressed("ui_left"):
		_prev()
	elif event.is_action_pressed("ui_right"):
		_next()

# ── Helpers ───────────────────────────────────────────────────────────────────
func _t(text: String, px: int, col: Color, pos: Vector2, size: Vector2,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UITheme.apply_font(l, px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(l)
	return l

func _cell_lbl(text: String, col: Color, min_w: float) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(min_w, 0)
	UITheme.apply_font(l, UITheme.FONT_VALUE)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _gold(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	UITheme.style_button(b)
	UITheme.apply_font(b, UITheme.FONT_HEADER)
	_panel.add_child(b)
	return b

func _bar(rect: Rect2, kind: String) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.position = rect.position
	pb.size = rect.size
	UITheme.style_stat_bar(pb, kind)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(pb)
	return pb
