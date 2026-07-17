extends Node2D
class_name MainMenu

const GAME_SCENE := "res://scenes/main_game.tscn"

enum WinMode { WINDOWED, BORDERLESS, FULLSCREEN }
var _win_mode := WinMode.WINDOWED

var _options_panel: Control
var _class_browser: ClassBrowser
var _crystal_shop: CrystalShop

func _ready() -> void:
	_apply_window_mode(WinMode.WINDOWED)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_build_main(canvas)
	_build_options(canvas)

	var cb_scene := load("res://scenes/class_browser.tscn") as PackedScene
	_class_browser = cb_scene.instantiate() as ClassBrowser
	add_child(_class_browser)

	var cs_scene := load("res://scenes/crystal_shop.tscn") as PackedScene
	_crystal_shop = cs_scene.instantiate() as CrystalShop
	add_child(_crystal_shop)

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

	var cx := 960.0
	_lbl(root, "AUTO HEROES", 60, Color(0.82, 0.88, 1.0),
		Vector2(cx - 300, 80), Vector2(600, 80), true)
	_lbl(root, "an autobattler rpg", 16, Color(0.5, 0.6, 0.85, 0.75),
		Vector2(cx - 200, 162), Vector2(400, 30), true)

	var btns := [
		["START GAME",    _on_start],
		["CLASSES",       _on_classes],
		["CRYSTAL SHOP",  _on_crystal_shop],
		["ARENA",         _on_arena],
		["OPTIONS",       _on_options],
		["QUIT",          _on_quit],
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
	_options_panel = _panel(canvas, Rect2(660, 200, 600, 380))
	_options_panel.visible = false

	_lbl(_options_panel, "OPTIONS", 22, Color(0.8, 0.8, 1.0),
		Vector2(0, 20), Vector2(600, 40), true)
	var sep := HSeparator.new()
	sep.position = Vector2(0, 68); sep.size = Vector2(600, 4)
	_options_panel.add_child(sep)

	_lbl(_options_panel, "Window Mode", 15, Color(0.7, 0.7, 0.9),
		Vector2(30, 86), Vector2(240, 28))

	var modes := [
		["Windowed",          WinMode.WINDOWED],
		["Borderless Windowed", WinMode.BORDERLESS],
		["Fullscreen",        WinMode.FULLSCREEN],
	]
	var my := 122.0
	for m in modes:
		var b := _btn(m[0], Rect2(30, my, 260, 44))
		b.pressed.connect(_on_window_mode.bind(m[1]))
		_options_panel.add_child(b)
		my += 54

	var close := _btn("✕  Close", Rect2(220, 326, 160, 40))
	close.pressed.connect(func(): _options_panel.visible = false)
	_options_panel.add_child(close)

# ── Handlers ──────────────────────────────────────────────────────────────────
func _on_start() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_classes() -> void:
	_options_panel.visible = false
	_class_browser.open(0)

func _on_crystal_shop() -> void:
	_options_panel.visible = false
	_crystal_shop.open()

func _on_arena() -> void:
	# Test sandbox — arena_main.gd defaults to interactive sandbox mode when
	# there's a window (headless CLI runs keep probe as their default).
	get_tree().change_scene_to_file("res://scenes/arena.tscn")

func _on_options() -> void:
	_options_panel.visible = not _options_panel.visible

func _on_quit() -> void:
	get_tree().quit()

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
		p.position = rect.position; p.size = rect.size
	p.add_theme_stylebox_override("panel",
		_flat(Color(0.1, 0.1, 0.16, 0.97), Color(0.4, 0.4, 0.6), 2, 6))
	parent.add_child(p)
	return p

func _btn(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text; b.position = rect.position; b.size = rect.size
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	b.add_theme_stylebox_override("normal",  _flat(Color(0.18, 0.18, 0.28), Color(0.45, 0.45, 0.6), 1, 4))
	b.add_theme_stylebox_override("hover",   _flat(Color(0.25, 0.25, 0.38), Color(0.6, 0.6, 0.8),  1, 4))
	b.add_theme_stylebox_override("pressed", _flat(Color(0.12, 0.12, 0.22), Color(0.3, 0.3, 0.5),  1, 4))
	return b

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
