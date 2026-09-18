extends CanvasLayer
class_name GameOverScreen

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

var _crystal_lbl: Label
var _round_lbl:   Label
var _dmg_lbl:     Label
var _kills_lbl:   Label
var _title_lbl:   Label
var _subtitle_lbl: Label
var _verdict_lbl: Label
var _panel: Panel

# Empty verdict just hides the line, so callers that don't supply one are safe.
func _set_verdict(verdict: String) -> void:
	if not _verdict_lbl:
		return
	_verdict_lbl.text = verdict
	_verdict_lbl.visible = verdict != ""

func _ready() -> void:
	_build_ui()

func show_defeat(crystals: int, rounds_survived: int,
		total_damage: int, kills: int, verdict: String = "") -> void:
	_set_verdict(verdict)
	_title_lbl.text    = "☠  DEFEATED"
	_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	_subtitle_lbl.text = "Your heroes have fallen. Gold and heroes are lost."
	# UI theme pass 2026-07-04: dobo card panel, red-tinted for defeat.
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box_tinted(Color(1.35, 0.75, 0.75)))
	_crystal_lbl.text = "%d" % crystals
	_crystal_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	_round_lbl.text   = "Rounds Survived:    %d" % rounds_survived
	_dmg_lbl.text     = "Total Damage Dealt: %d" % total_damage
	_kills_lbl.text   = "Enemies Defeated:   %d" % kills
	visible = true

func show_victory(crystals: int, rounds_cleared: int,
		total_damage: int, kills: int, verdict: String = "") -> void:
	_set_verdict(verdict)
	_title_lbl.text    = "✦  VICTORY"
	_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.2))
	_subtitle_lbl.text = "Your heroes have triumphed! Crystals saved for the next run."
	# UI theme pass 2026-07-04: dobo card panel, green-tinted for victory.
	_panel.add_theme_stylebox_override("panel", UITheme.panel_box_tinted(Color(0.8, 1.25, 0.8)))
	_crystal_lbl.text = "%d" % crystals
	_crystal_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
	_round_lbl.text   = "Rounds Cleared:     %d" % rounds_cleared
	_dmg_lbl.text     = "Total Damage Dealt: %d" % total_damage
	_kills_lbl.text   = "Enemies Defeated:   %d" % kills
	visible = true

func _build_ui() -> void:
	# ── Dark overlay ──────────────────────────────────────────────────────────
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.82)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# ── Main panel ────────────────────────────────────────────────────────────
	_panel = Panel.new()
	var panel := _panel
	panel.size = Vector2(560, 520)   # +60 for the after-action verdict line
	# UI theme pass 2026-07-04: dobo card panel (retinted by show_defeat/show_victory).
	panel.add_theme_stylebox_override("panel", UITheme.panel_box_tinted(Color(1.35, 0.75, 0.75)))
	overlay.add_child(panel)
	_center(panel)

	# ── Skull decoration at top ───────────────────────────────────────────────
	var skull_lbl := Label.new()
	skull_lbl.text = "☠"
	skull_lbl.position = Vector2(0, 18)
	skull_lbl.size = Vector2(560, 60)
	skull_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skull_lbl.add_theme_font_size_override("font_size", 56)
	skull_lbl.add_theme_color_override("font_color", Color(0.75, 0.12, 0.12))
	panel.add_child(skull_lbl)

	# ── Title (set dynamically by show_defeat / show_victory) ────────────────
	_title_lbl = _lbl(panel, "☠  DEFEATED", 38, Color(0.95, 0.3, 0.3),
		Vector2(0, 78), Vector2(560, 46), true)
	_subtitle_lbl = _lbl(panel, "Your heroes have fallen. The gold and heroes are lost.",
		15, Color(0.65, 0.55, 0.55, 0.9), Vector2(40, 124), Vector2(480, 24), true)

	# ── Divider ───────────────────────────────────────────────────────────────
	var sep1 := HSeparator.new()
	sep1.position = Vector2(0, 156); sep1.size = Vector2(560, 4)
	panel.add_child(sep1)

	# ── Crystal reward (highlighted) ──────────────────────────────────────────
	_lbl(panel, "CRYSTALS EARNED", 16, Color(0.5, 0.75, 1.0, 0.8),
		Vector2(0, 170), Vector2(560, 24), true)
	_crystal_lbl = _lbl(panel, "0", 58, Color(0.4, 0.8, 1.0),
		Vector2(0, 196), Vector2(560, 66), true)

	var sep2 := HSeparator.new()
	sep2.position = Vector2(0, 270); sep2.size = Vector2(560, 4)
	panel.add_child(sep2)

	# ── Run summary stats ─────────────────────────────────────────────────────
	_lbl(panel, "RUN SUMMARY", 15, Color(0.6, 0.6, 0.75, 0.7),
		Vector2(0, 282), Vector2(560, 22), true)

	_round_lbl = _lbl(panel, "Rounds Survived:    0", 17, Color(0.8, 0.8, 0.9),
		Vector2(80, 310), Vector2(400, 24))
	_dmg_lbl   = _lbl(panel, "Total Damage Dealt: 0", 17, Color(0.8, 0.8, 0.9),
		Vector2(80, 336), Vector2(400, 24))
	_kills_lbl = _lbl(panel, "Enemies Defeated:   0", 17, Color(0.8, 0.8, 0.9),
		Vector2(80, 362), Vector2(400, 24))

	# ── After-action verdict ──────────────────────────────────────────────────
	# One sentence on HOW the last fight went, not just how much damage it did.
	# Sits directly under the run stats because it's the line that explains them.
	_verdict_lbl = _lbl(panel, "", 15, Color(1.0, 0.78, 0.45, 0.95),
		Vector2(40, 396), Vector2(480, 48), true)
	_verdict_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# ── Tip ───────────────────────────────────────────────────────────────────
	_lbl(panel, "Crystals carry over — spend them to unlock stronger heroes next run.",
		13, Color(0.5, 0.55, 0.65, 0.7), Vector2(40, 452), Vector2(480, 22), true)

	# ── Return button ─────────────────────────────────────────────────────────
	var btn := Button.new()
	btn.text = "Return to Main Menu"
	btn.position = Vector2(155, 478)
	btn.size = Vector2(250, 44)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	btn.add_theme_stylebox_override("normal",
		_flat(Color(0.22, 0.1, 0.1), Color(0.6, 0.2, 0.2), 2, 6))
	btn.add_theme_stylebox_override("hover",
		_flat(Color(0.35, 0.12, 0.12), Color(0.85, 0.3, 0.3), 2, 6))
	btn.add_theme_stylebox_override("pressed",
		_flat(Color(0.15, 0.07, 0.07), Color(0.4, 0.15, 0.15), 2, 6))
	btn.pressed.connect(_on_return)
	panel.add_child(btn)

	visible = false

func _on_return() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _center(control: Control) -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1800, 1080)
	control.position = (vp - control.size) / 2.0

func _lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos; l.size = size
	l.add_theme_font_size_override("font_size", UITheme.body_font(sz))
	l.add_theme_color_override("font_color", col)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _flat(bg: Color, border: Color = Color.TRANSPARENT,
		bw: int = 0, radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.border_width_left = bw; s.border_width_right = bw
	s.border_width_top = bw;  s.border_width_bottom = bw
	s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius; s.corner_radius_bottom_right = radius
	return s
