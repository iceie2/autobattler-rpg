extends CanvasLayer
class_name CrystalShop

# Branching tree layout, v2 (2026-07-15 design pass). Call to Arms sits at
# the center, always active (not purchasable — deliberately NOT in
# Progression.UPGRADES). The 4 core upgrades are the compass ring, and the
# old 10-wide stat fan is split into three themed sub-branches gated by
# Might (offense), Warding (defense) and Mana Well (arcane/utility) so no
# fan is wider than 4.
#
# Nodes are the icon art itself (assets/icons/crystalshop, from
# GEMINI_CRYSTAL_SHOP_PROMPTS.md) — no slot frames. State reads from the
# icon: dim = level 0 and unaffordable, gold progress ring = levels bought,
# soft glow = affordable right now, MAX badge = maxed out. Clicking a node
# SELECTS it; the parchment detail bar at the bottom shows the numbers and
# holds the Buy button. The tree itself floats over the dimmed game screen,
# so all text outside the detail bar uses the light COL_* colors below —
# UITheme's parchment browns vanish on the dark backdrop.
signal closed()

const PLACEHOLDER_ICON := "res://assets/UI/Vector_UI_Pack_dobo_ui/Icons/128px/skills_icon_128px.png"
const ICON_DIR := "res://assets/icons/crystalshop/"
const CALL_TO_ARMS_ICON := ICON_DIR + "call_to_arms.png"

# Upgrade key -> icon file. Circles = per-hero stat boosts, squares =
# run-structure/economy upgrades (shape convention from the prompt sheet).
const NODE_ICONS := {
	"team_hp":              "fortified.png",
	"starting_gold":        "head_start.png",
	"bonus_xp":             "quick_learner.png",
	"hero_slots":           "roster_expansion.png",
	"bench_slots":          "warm_bench.png",
	"crystal_drop":         "crystal_surge.png",
	"mana_well":            "mana_well.png",
	"spellpower":           "spellpower.png",
	"might":                "might.png",
	"warding":              "warding.png",
	"fleetfoot":            "fleetfoot.png",
	"vitality_flow":        "vitality_flow.png",
	"mana_flow":            "mana_flow.png",
	"swiftness":            "swiftness.png",
	"lethality":            "lethality.png",
	"killing_blow":         "killing_blow.png",
	"elemental_attunement": "elemental_attunement.png",
}

const PANEL_SIZE := Vector2(1500, 1000)
const TREE_CENTER := Vector2(750, 480)   # relative to panel top-left
const CENTER_NODE_SIZE := 140.0
const RADII := [0.0, 170.0, 300.0, 440.0]        # indexed by tier
const NODE_SIZES := [140.0, 110.0, 96.0, 88.0]   # indexed by tier

# The whole tree, hand-placed. Angles in degrees, standard math convention
# (0 = right, 90 = up, CCW — _angle_offset flips Y for screen space).
# parent "" = the Call to Arms center. Tier-3 nodes sit on one evenly-spaced
# 22°-arc across the top so sibling groups never collide; each group's
# gateway (tier-2) node sits at the mean angle of its children.
const NODE_LAYOUT := {
	"team_hp":       {"tier": 1, "angle": 90.0,  "parent": ""},
	"starting_gold": {"tier": 1, "angle": 0.0,   "parent": ""},
	"bonus_xp":      {"tier": 1, "angle": 270.0, "parent": ""},
	"hero_slots":    {"tier": 1, "angle": 180.0, "parent": ""},

	"might":        {"tier": 2, "angle": 46.0,  "parent": "team_hp"},
	"warding":      {"tier": 2, "angle": 101.0, "parent": "team_hp"},
	"mana_well":    {"tier": 2, "angle": 145.0, "parent": "team_hp"},
	"crystal_drop": {"tier": 2, "angle": 0.0,   "parent": "starting_gold"},
	"bench_slots":  {"tier": 2, "angle": 180.0, "parent": "hero_slots"},

	"killing_blow":         {"tier": 3, "angle": 13.0,  "parent": "might"},
	"lethality":            {"tier": 3, "angle": 35.0,  "parent": "might"},
	"fleetfoot":            {"tier": 3, "angle": 57.0,  "parent": "might"},
	"spellpower":           {"tier": 3, "angle": 79.0,  "parent": "might"},
	"vitality_flow":        {"tier": 3, "angle": 101.0, "parent": "warding"},
	"mana_flow":            {"tier": 3, "angle": 123.0, "parent": "mana_well"},
	"swiftness":            {"tier": 3, "angle": 145.0, "parent": "mana_well"},
	"elemental_attunement": {"tier": 3, "angle": 167.0, "parent": "mana_well"},
}

# Light-on-dark palette for everything floating over the dimmed game screen.
const COL_TITLE    := Color(0.95, 0.82, 0.5)
const COL_SUBTITLE := Color(0.78, 0.68, 0.5, 0.9)
const COL_WALLET   := Color(0.62, 0.85, 1.0)
const COL_MAXED    := Color(1.0, 0.92, 0.55)
const CONN_DIM     := Color(0.4, 0.32, 0.18, 0.55)
const CONN_LIT     := Color(0.9, 0.7, 0.28, 0.95)
const GLOW_GOLD    := Color(1.0, 0.84, 0.35, 0.3)
const DIM_MODULATE := Color(0.5, 0.5, 0.58)

# Progress ring drawn around each purchasable node: dark track, gold fill
# proportional to level, brighter when maxed, outer halo when selected.
# (Colors live in here — inner classes can't see outer-class constants.)
class NodeRing extends Control:
	const TRACK  := Color(0.0, 0.0, 0.0, 0.5)
	const FILL   := Color(1.0, 0.82, 0.3)
	const MAXED  := Color(1.0, 0.92, 0.55)
	const SELECT := Color(1.0, 0.95, 0.7, 0.9)
	var progress := 0.0
	var maxed := false
	var selected := false
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 3.0
		draw_arc(c, r, 0.0, TAU, 48, TRACK, 5.0, true)
		if progress > 0.0:
			var col := MAXED if maxed else FILL
			draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * progress, 48, col, 5.0, true)
		if selected:
			draw_arc(c, r + 6.0, 0.0, TAU, 48, SELECT, 2.5, true)

const ZOOM_MIN := 0.6
const ZOOM_MAX := 1.5
const PAN_MARGIN := 140.0   # the tree hub can never get closer than this to leaving the view

var _wallet_lbl: Label
var _nodes: Array = []        # [{button, key, icon, ring, glow, badge}, ...]
var _connectors: Array = []   # [{line: Line2D, parent: String}, ...]
var _connector_layer: Node2D
var _glow_layer: Control
var _selected_key := ""       # "" = nothing, "call_to_arms" = the center node

var _tree_view: Control       # clipped window the tree is seen through
var _canvas: Control          # everything tree-shaped lives here; pan = move it, zoom = scale it
var _canvas_home := Vector2.ZERO
var _dragging := false

var _detail_prompt: Label
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_desc: Label
var _detail_stats: Label
var _buy_btn: Button

func _ready() -> void:
	_build_ui()

func open() -> void:
	_canvas.position = _canvas_home   # reset any pan/zoom from last visit
	_canvas.scale = Vector2.ONE
	_refresh()
	visible = true

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)

	var panel := Panel.new()
	panel.size = PANEL_SIZE
	panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	overlay.add_child(panel)
	_center(panel)

	# Header: title top-left, crystal wallet top-right — the center-top is
	# tree territory now.
	_lbl(panel, "✦  CRYSTAL SHOP  ✦", 26, COL_TITLE, Vector2(36, 22), Vector2(560, 40))
	_lbl(panel, "Upgrades persist between runs.", 12, COL_SUBTITLE,
		Vector2(38, 64), Vector2(560, 22))
	var gem := UITheme.currency_icon("gem")
	gem.position = Vector2(PANEL_SIZE.x - 214, 18)
	panel.add_child(gem)
	_wallet_lbl = _lbl(panel, "0", 26, COL_WALLET, Vector2(PANEL_SIZE.x - 152, 26), Vector2(120, 40))

	# The tree lives on a pannable/zoomable canvas seen through a clipped
	# view: drag an empty spot to pan, mouse-wheel to zoom toward the cursor.
	# Node buttons grab their own clicks, so only empty space starts a drag.
	_tree_view = Control.new()
	_tree_view.position = Vector2(16, 86)
	_tree_view.size = Vector2(PANEL_SIZE.x - 32, 650)
	_tree_view.clip_contents = true
	_tree_view.gui_input.connect(_on_tree_view_input)
	panel.add_child(_tree_view)

	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never eat clicks meant for the view/nodes
	_canvas_home = -_tree_view.position   # canvas coords == panel coords at home position
	_canvas.position = _canvas_home
	_tree_view.add_child(_canvas)

	# Draw order: ambient backdrop glow, connector lines, per-node glows,
	# then the node buttons themselves (added by _build_tree).
	_connector_layer = Node2D.new()
	_canvas.add_child(_connector_layer)
	_glow_layer = Control.new()
	_glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_glow_layer)
	var ambient := _make_glow(TREE_CENTER, 380.0, Color(1.0, 0.85, 0.5, 0.055))
	ambient.visible = true
	_glow_layer.move_child(ambient, 0)

	_build_tree(_canvas)
	_build_detail_bar(panel)

	var close_btn := _btn("✕  Close", Rect2((PANEL_SIZE.x - 200) / 2.0, PANEL_SIZE.y - 56, 200, 40))
	close_btn.pressed.connect(_close)
	panel.add_child(close_btn)

	visible = false

# ── Pan & zoom ────────────────────────────────────────────────────────────────
func _on_tree_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			_tree_view.mouse_default_cursor_shape = Control.CURSOR_MOVE if _dragging else Control.CURSOR_ARROW
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.1, event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / 1.1, event.position)
	elif event is InputEventMouseMotion and _dragging:
		_canvas.position += event.relative
		_clamp_canvas()

# Zoom about the cursor: the canvas point under the mouse stays under it.
# (Canvas pivot is its origin, so position math below assumes scale-about-0,0.)
func _zoom_at(factor: float, mouse_pos: Vector2) -> void:
	var old: float = _canvas.scale.x
	var new_scale: float = clampf(old * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(old, new_scale):
		return
	_canvas.position = mouse_pos - (mouse_pos - _canvas.position) * (new_scale / old)
	_canvas.scale = Vector2.ONE * new_scale
	_clamp_canvas()

# Keep the Call to Arms hub on screen no matter how far the user flings the
# canvas — everything else is reachable by panning from there.
func _clamp_canvas() -> void:
	var hub: Vector2 = _canvas.position + TREE_CENTER * _canvas.scale.x
	hub.x = clampf(hub.x, PAN_MARGIN, _tree_view.size.x - PAN_MARGIN)
	hub.y = clampf(hub.y, PAN_MARGIN, _tree_view.size.y - PAN_MARGIN)
	_canvas.position = hub - TREE_CENTER * _canvas.scale.x

# ── Tree construction ─────────────────────────────────────────────────────────
func _build_tree(canvas: Control) -> void:
	# Every position is derivable straight from NODE_LAYOUT (angles are
	# absolute), so compute them all up front — Progression.UPGRADES order
	# doesn't put parents before children.
	var positions: Dictionary = {"": TREE_CENTER}
	for key: String in NODE_LAYOUT:
		var l: Dictionary = NODE_LAYOUT[key]
		positions[key] = TREE_CENTER + _angle_offset(l["angle"], RADII[l["tier"]])

	for key: String in NODE_LAYOUT:
		var l: Dictionary = NODE_LAYOUT[key]
		var line := Line2D.new()
		line.points = PackedVector2Array([positions[l["parent"]], positions[key]])
		line.width = 6.0 if l["parent"] == "" else 4.0
		line.default_color = CONN_DIM
		_connector_layer.add_child(line)
		_connectors.append({"line": line, "parent": l["parent"]})

	# Center: Call to Arms — always active, selectable for its info, no buy.
	var center_glow := _make_glow(TREE_CENTER, CENTER_NODE_SIZE, Color(1.0, 0.9, 0.55, 0.45), 2.0)
	center_glow.visible = true
	var center_btn := _make_icon_button(canvas, CALL_TO_ARMS_ICON, TREE_CENTER, CENTER_NODE_SIZE)
	center_btn.tooltip_text = "Call to Arms — always active"
	center_btn.pressed.connect(_select.bind("call_to_arms"))
	var active_tag := _lbl(canvas, "ACTIVE", 11, COL_TITLE,
		TREE_CENTER + Vector2(-60, CENTER_NODE_SIZE / 2.0 + 4), Vector2(120, 18), true)
	_outline(active_tag)

	for upgrade in Progression.UPGRADES:
		var key: String = upgrade["key"]
		if not NODE_LAYOUT.has(key):
			push_warning("CrystalShop: upgrade '%s' has no tree slot — add it to NODE_LAYOUT" % key)
			continue
		var tier: int = NODE_LAYOUT[key]["tier"]
		_add_upgrade_node(canvas, upgrade, positions[key], NODE_SIZES[tier])

func _angle_offset(angle_deg: float, radius: float) -> Vector2:
	var rad: float = deg_to_rad(angle_deg)
	return Vector2(cos(rad), -sin(rad)) * radius   # -sin: screen Y grows downward

# Frameless icon button — the medallion/plaque art IS the node.
func _make_icon_button(parent: Control, icon_path: String, pos: Vector2, size: float) -> Button:
	var btn := Button.new()
	btn.position = pos - Vector2.ONE * size / 2.0
	btn.size = Vector2.ONE * size
	btn.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, empty)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = load(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 5; icon.offset_top = 5
	icon.offset_right = -5; icon.offset_bottom = -5
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)
	parent.add_child(btn)
	return btn

# Afford-glows stay tight (1.55x the node) so a rich wallet doesn't melt the
# whole tree into gold fog — only the center hub gets a wide halo.
func _make_glow(pos: Vector2, node_size: float, col: Color, glow_scale := 1.55) -> TextureRect:
	var g := TextureRect.new()
	var s := node_size * glow_scale
	g.texture = _radial_glow_tex(col)
	g.position = pos - Vector2.ONE * s / 2.0
	g.size = Vector2.ONE * s
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_SCALE
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.visible = false
	_glow_layer.add_child(g)
	return g

static func _radial_glow_tex(col: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, col)
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex

# One purchasable node: bare icon + progress ring + afford-glow + MAX badge.
# Click = select (the detail bar handles buying).
func _add_upgrade_node(canvas: Control, upgrade: Dictionary, pos: Vector2, size: float) -> void:
	var key: String = upgrade["key"]
	var glow := _make_glow(pos, size, GLOW_GOLD)
	var icon_path: String = (ICON_DIR + NODE_ICONS[key]) if NODE_ICONS.has(key) else PLACEHOLDER_ICON
	var btn := _make_icon_button(canvas, icon_path, pos, size)
	btn.pressed.connect(_select.bind(key))

	var ring := NodeRing.new()
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(ring)

	var badge := Label.new()
	badge.text = "MAX"
	badge.anchor_top = 1.0; badge.anchor_bottom = 1.0; badge.anchor_right = 1.0
	badge.offset_top = 0; badge.offset_bottom = 18
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", UITheme.body_font(20))
	badge.add_theme_color_override("font_color", COL_MAXED)
	_outline(badge)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	btn.add_child(badge)

	_nodes.append({
		"button": btn, "key": key, "icon": btn.get_node("Icon"),
		"ring": ring, "glow": glow, "badge": badge,
	})

# ── Detail bar (parchment strip along the bottom) ─────────────────────────────
func _build_detail_bar(panel: Panel) -> void:
	var bar := Panel.new()
	bar.position = Vector2(150, 742)
	bar.size = Vector2(1200, 168)
	bar.add_theme_stylebox_override("panel", UITheme.panel_box())
	panel.add_child(bar)

	_detail_prompt = _lbl(bar, "Select an upgrade to inspect it.", 16, UITheme.TEXT_BODY,
		Vector2(0, 66), Vector2(1200, 30), true)

	_detail_icon = TextureRect.new()
	_detail_icon.position = Vector2(28, 30)
	_detail_icon.size = Vector2(108, 108)
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bar.add_child(_detail_icon)

	_detail_name = _lbl(bar, "", 20, UITheme.TEXT_HEADER, Vector2(160, 16), Vector2(700, 34))
	_detail_desc = _lbl(bar, "", 13, UITheme.TEXT_BODY, Vector2(160, 56), Vector2(700, 54))
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_stats = _lbl(bar, "", 14, Color(0.55, 0.38, 0.1), Vector2(160, 114), Vector2(700, 30))

	_buy_btn = _btn("Buy", Rect2(910, 54, 250, 60))
	_buy_btn.pressed.connect(_on_buy)
	bar.add_child(_buy_btn)

# ── Refresh (node states + connectors + wallet + detail bar) ──────────────────
func _refresh() -> void:
	_wallet_lbl.text = "%d" % Progression.crystals
	for entry in _nodes:
		_refresh_node(entry)
	for c in _connectors:
		var lit: bool = c["parent"] == "" or Progression.get_level(c["parent"]) > 0
		(c["line"] as Line2D).default_color = CONN_LIT if lit else CONN_DIM
	_refresh_detail()

func _refresh_node(entry: Dictionary) -> void:
	var key: String = entry["key"]
	var upgrade := Progression._find(key)
	if upgrade.is_empty():
		return
	var lvl: int = Progression.get_level(key)
	var max_lvl: int = int(upgrade["max_level"])
	var maxed: bool = lvl >= max_lvl
	var affordable: bool = Progression.can_afford(key)

	var ring: NodeRing = entry["ring"]
	ring.progress = float(lvl) / float(max_lvl)
	ring.maxed = maxed
	ring.selected = key == _selected_key
	ring.queue_redraw()

	(entry["icon"] as TextureRect).modulate = Color.WHITE if (lvl > 0 or affordable) else DIM_MODULATE
	(entry["glow"] as TextureRect).visible = affordable
	(entry["badge"] as Label).visible = maxed
	(entry["button"] as Button).tooltip_text = "%s — %d/%d" % [upgrade["name"], lvl, max_lvl]

func _refresh_detail() -> void:
	var has_selection := _selected_key != ""
	_detail_prompt.visible = not has_selection
	_detail_icon.visible = has_selection
	_detail_name.visible = has_selection
	_detail_desc.visible = has_selection
	_detail_stats.visible = has_selection
	_buy_btn.visible = has_selection
	if not has_selection:
		return

	if _selected_key == "call_to_arms":
		_detail_icon.texture = load(CALL_TO_ARMS_ICON)
		_detail_name.text = "Call to Arms"
		_detail_desc.text = "Every run starts with 1 free recruited hero instead of starting gold."
		_detail_stats.text = "Always active — the heart of the tree."
		_buy_btn.visible = false
		return

	var upgrade := Progression._find(_selected_key)
	if upgrade.is_empty():
		return
	var lvl: int = Progression.get_level(_selected_key)
	var max_lvl: int = int(upgrade["max_level"])
	var cost: int = Progression.next_cost(_selected_key)
	var is_float: bool = upgrade.get("is_float", false)
	var per: float = float(upgrade["effect_per_level"])
	var eff_fmt: String = upgrade.get("effect", "%d")
	var cur_txt: String = (eff_fmt % (per * lvl)) if is_float else (eff_fmt % int(per * lvl))
	var next_txt: String = (eff_fmt % (per * (lvl + 1))) if is_float else (eff_fmt % int(per * (lvl + 1)))

	_detail_icon.texture = load((ICON_DIR + NODE_ICONS[_selected_key]) if NODE_ICONS.has(_selected_key) else PLACEHOLDER_ICON)
	_detail_name.text = "%s  —  Level %d/%d" % [upgrade["name"], lvl, max_lvl]
	_detail_desc.text = upgrade["desc"]
	if cost < 0:
		_detail_stats.text = "%s  (maxed out)" % cur_txt
		_buy_btn.text = "MAXED"
		_buy_btn.disabled = true
	else:
		_detail_stats.text = "%s   →   %s" % [cur_txt, next_txt]
		_buy_btn.text = "Buy — %d crystals" % cost
		_buy_btn.disabled = not Progression.can_afford(_selected_key)

func _select(key: String) -> void:
	_selected_key = key
	_refresh()

func _on_buy() -> void:
	if _selected_key != "" and Progression.buy(_selected_key):
		_refresh()

func _close() -> void:
	visible = false
	closed.emit()

func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_close()

func _center(control: Control) -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	control.position = (vp - control.size) / 2.0

# Dark outline for small labels that sit on top of connector lines/glows.
func _outline(l: Label) -> void:
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.02, 0.9))
	l.add_theme_constant_override("outline_size", 6)

func _lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos; l.size = size
	l.add_theme_font_size_override("font_size", UITheme.body_font(sz))
	l.add_theme_color_override("font_color", col)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _btn(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text; b.position = rect.position; b.size = rect.size
	b.add_theme_font_size_override("font_size", 22)
	UITheme.style_button(b)
	return b
