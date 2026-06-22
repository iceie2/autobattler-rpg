extends Node2D
class_name MainMenu

const GAME_SCENE := "res://scenes/main_game.tscn"

enum WinMode { WINDOWED, BORDERLESS, FULLSCREEN }
var _win_mode := WinMode.WINDOWED

# Class data for the browser
const CLASS_INFO := [
	{
		"name": "Warrior",    "color": Color(0.9, 0.5, 0.1),
		"hp": 1200, "mana": 300,  "str": 15, "dex": 8,  "int": 5,  "res": 12,
		"move": 2, "range": 1, "skill": "Whirlwind",
		"desc": "Charges into melee and unleashes a spinning blade attack hitting all adjacent enemies."
	},
	{
		"name": "Ranger",     "color": Color(0.2, 0.85, 0.3),
		"hp": 900,  "mana": 400,  "str": 10, "dex": 16, "int": 8,  "res": 7,
		"move": 3, "range": 4, "skill": "Arrow Rain",
		"desc": "Fires a volley of arrows that rains down on multiple enemies in range."
	},
	{
		"name": "Monk",       "color": Color(0.95, 0.9, 0.3),
		"hp": 1000, "mana": 500,  "str": 12, "dex": 12, "int": 10, "res": 10,
		"move": 3, "range": 1, "skill": "Chi Burst",
		"desc": "Releases a radial pulse of energy that damages enemies and restores ally HP."
	},
	{
		"name": "Thief",      "color": Color(0.6, 0.2, 0.9),
		"hp": 800,  "mana": 350,  "str": 8,  "dex": 18, "int": 10, "res": 6,
		"move": 5, "range": 1, "skill": "Shadow Strike",
		"desc": "Vanishes into shadow and reappears behind the target for a devastating critical hit."
	},
	{
		"name": "Black Mage", "color": Color(0.8, 0.1, 0.1),
		"hp": 700,  "mana": 800,  "str": 5,  "dex": 7,  "int": 18, "res": 8,
		"move": 2, "range": 5, "skill": "Inferno",
		"desc": "Calls down a pillar of fire that erupts in a wide area, incinerating multiple foes."
	},
	{
		"name": "White Mage", "color": Color(0.9, 0.9, 1.0),
		"hp": 750,  "mana": 750,  "str": 6,  "dex": 8,  "int": 16, "res": 12,
		"move": 2, "range": 5, "skill": "Holy Light",
		"desc": "Channels divine energy to restore HP to all allied units across the battlefield."
	},
	{
		"name": "Red Mage",   "color": Color(0.9, 0.2, 0.6),
		"hp": 850,  "mana": 650,  "str": 10, "dex": 10, "int": 14, "res": 10,
		"move": 2, "range": 5, "skill": "Chaos Bolt",
		"desc": "Hurls an unstable bolt of chaotic magic that shifts element on every cast."
	},
]

var _class_idx := 0

# Panels
var _options_panel: Control
var _classes_panel: Control
var _class_name_lbl: Label
var _class_color_rect: ColorRect
var _class_stat_lbl: Label
var _class_desc_lbl: Label
var _class_skill_lbl: Label

func _ready() -> void:
	_apply_window_mode(WinMode.WINDOWED)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_build_main(canvas)
	_build_options(canvas)
	_build_classes(canvas)

func _draw() -> void:
	var sz := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.06, 0.07, 0.12))
	for x in range(0, int(sz.x) + 64, 64):
		draw_line(Vector2(x, 0), Vector2(x, sz.y), Color(0.12, 0.13, 0.2, 0.4), 1)
	for y in range(0, int(sz.y) + 64, 64):
		draw_line(Vector2(0, y), Vector2(sz.x, y), Color(0.12, 0.13, 0.2, 0.4), 1)
	var cx := sz.x / 2
	for i in range(4):
		draw_arc(Vector2(cx, 160), 70.0 + i * 18, 0, TAU, 40,
			Color(0.35, 0.4, 0.85, 0.08 - i * 0.015), 2)

# ── Main panel ────────────────────────────────────────────────────────────────
func _build_main(canvas: CanvasLayer) -> void:
	var root := _panel(canvas, Rect2(0, 0, 0, 0))
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_stylebox_override("panel", _flat(Color(0, 0, 0, 0)))

	var cx := 960.0   # approx centre — works for most resolutions

	_lbl(root, "AUTO HEROES", 60, Color(0.82, 0.88, 1.0), Vector2(cx - 300, 80), Vector2(600, 80), true)
	_lbl(root, "an autobattler rpg", 16, Color(0.5, 0.6, 0.85, 0.75), Vector2(cx - 200, 160), Vector2(400, 30), true)

	var btns := [
		["START GAME", _on_start],
		["CLASSES",    _on_classes],
		["OPTIONS",    _on_options],
	]
	var by := 240.0
	for b in btns:
		var btn := _btn(b[0], Rect2(cx - 150, by, 300, 52))
		btn.pressed.connect(b[1])
		root.add_child(btn)
		by += 70

	_lbl(root, "v0.1 – early development", 12, Color(0.3, 0.3, 0.4),
		Vector2(cx - 150, by + 30), Vector2(300, 24), true)

# ── Options panel ─────────────────────────────────────────────────────────────
func _build_options(canvas: CanvasLayer) -> void:
	_options_panel = _panel(canvas, Rect2(660, 200, 600, 400))
	_options_panel.visible = false

	_lbl(_options_panel, "OPTIONS", 22, Color(0.8, 0.8, 1.0), Vector2(0, 20), Vector2(600, 40), true)

	var sep := _separator(_options_panel, 70, 560)
	_lbl(_options_panel, "Window Mode", 16, Color(0.7, 0.7, 0.9), Vector2(30, 90), Vector2(200, 28))

	var modes := [["Windowed", WinMode.WINDOWED],
	              ["Borderless Windowed", WinMode.BORDERLESS],
	              ["Fullscreen", WinMode.FULLSCREEN]]
	var my := 130.0
	for m in modes:
		var b := _btn(m[0], Rect2(30, my, 240, 42))
		b.pressed.connect(_on_window_mode.bind(m[1]))
		_options_panel.add_child(b)
		my += 54

	var close := _btn("✕ Close", Rect2(220, 340, 160, 40))
	close.pressed.connect(func(): _options_panel.visible = false)
	_options_panel.add_child(close)

# ── Classes panel ─────────────────────────────────────────────────────────────
func _build_classes(canvas: CanvasLayer) -> void:
	_classes_panel = _panel(canvas, Rect2(300, 80, 800, 620))
	_classes_panel.visible = false

	_lbl(_classes_panel, "CLASS ROSTER", 22, Color(0.8, 0.8, 1.0), Vector2(0, 16), Vector2(800, 40), true)

	# Left / right nav
	var prev_btn := _btn("◀", Rect2(16, 260, 50, 50))
	prev_btn.pressed.connect(_class_prev)
	_classes_panel.add_child(prev_btn)

	var next_btn := _btn("▶", Rect2(734, 260, 50, 50))
	next_btn.pressed.connect(_class_next)
	_classes_panel.add_child(next_btn)

	# Class icon (coloured square)
	_class_color_rect = ColorRect.new()
	_class_color_rect.position = Vector2(320, 80)
	_class_color_rect.size = Vector2(160, 160)
	_classes_panel.add_child(_class_color_rect)

	_class_name_lbl = _lbl(_classes_panel, "", 28, Color.WHITE, Vector2(0, 258), Vector2(800, 44), true)
	_class_stat_lbl = _lbl(_classes_panel, "", 14, Color(0.75, 0.75, 0.9), Vector2(80, 315), Vector2(640, 160))
	_class_skill_lbl = _lbl(_classes_panel, "", 15, Color(1.0, 0.85, 0.4), Vector2(80, 435), Vector2(640, 28))
	_class_desc_lbl = _lbl(_classes_panel, "", 13, Color(0.7, 0.7, 0.8), Vector2(80, 465), Vector2(640, 80))
	_class_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var close2 := _btn("✕ Close", Rect2(320, 568, 160, 40))
	close2.pressed.connect(func(): _classes_panel.visible = false)
	_classes_panel.add_child(close2)

	_refresh_class()

func _refresh_class() -> void:
	var c: Dictionary = CLASS_INFO[_class_idx]
	_class_color_rect.color = c["color"]
	_class_name_lbl.text = c["name"] + "  (%d/%d)" % [_class_idx + 1, CLASS_INFO.size()]
	_class_stat_lbl.text = (
		"HP: %-6d   Mana: %-6d   STR: %-4d   DEX: %-4d\n" +
		"INT: %-5d   RES: %-6d   Move: %-3d   Range: %d"
	) % [c["hp"], c["mana"], c["str"], c["dex"], c["int"], c["res"], c["move"], c["range"]]
	_class_skill_lbl.text = "Skill: " + c["skill"]
	_class_desc_lbl.text = c["desc"]

func _class_prev() -> void:
	_class_idx = (_class_idx - 1 + CLASS_INFO.size()) % CLASS_INFO.size()
	_refresh_class()

func _class_next() -> void:
	_class_idx = (_class_idx + 1) % CLASS_INFO.size()
	_refresh_class()

# ── Button handlers ───────────────────────────────────────────────────────────
func _on_start() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_options() -> void:
	_options_panel.visible = not _options_panel.visible
	_classes_panel.visible = false

func _on_classes() -> void:
	_classes_panel.visible = not _classes_panel.visible
	_options_panel.visible = false
	_class_idx = 0
	_refresh_class()

func _on_window_mode(mode: WinMode) -> void:
	_win_mode = mode
	_apply_window_mode(mode)

func _apply_window_mode(mode: WinMode) -> void:
	match mode:
		WinMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		WinMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		WinMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# ── UI helpers ────────────────────────────────────────────────────────────────
func _panel(parent: Node, rect: Rect2) -> Panel:
	var p := Panel.new()
	if rect.size != Vector2.ZERO:
		p.position = rect.position
		p.size = rect.size
	p.add_theme_stylebox_override("panel", _flat(Color(0.1, 0.1, 0.16, 0.97),
		Color(0.4, 0.4, 0.6), 2, 6))
	parent.add_child(p)
	return p

func _btn(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	b.add_theme_stylebox_override("normal", _flat(Color(0.18, 0.18, 0.28), Color(0.45, 0.45, 0.6), 1, 4))
	b.add_theme_stylebox_override("hover",  _flat(Color(0.25, 0.25, 0.38), Color(0.6, 0.6, 0.8), 1, 4))
	b.add_theme_stylebox_override("pressed",_flat(Color(0.12, 0.12, 0.22), Color(0.3, 0.3, 0.5), 1, 4))
	return b

func _lbl(parent: Node, text: String, size: int, color: Color,
		pos: Vector2, sz: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = sz
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _separator(parent: Node, y: float, width: float) -> HSeparator:
	var s := HSeparator.new()
	s.position = Vector2(0, y)
	s.size = Vector2(width, 4)
	parent.add_child(s)
	return s

func _flat(bg: Color, border: Color = Color.TRANSPARENT,
		bw: int = 0, radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = bw;  s.border_width_right = bw
	s.border_width_top = bw;   s.border_width_bottom = bw
	s.corner_radius_top_left = radius;    s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius; s.corner_radius_bottom_right = radius
	return s
