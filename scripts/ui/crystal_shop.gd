extends CanvasLayer
class_name CrystalShop

# Branching tree layout, v2 (2026-07-15 design pass). Call to Arms sits at
# the center, always active (not purchasable — deliberately NOT in
# Progression.UPGRADES).
#
# LAYOUT IS DATA (2026-07-31): node positions/sizes/icons/parents live in
# data/crystal_tree.json, loaded through CrystalTree. Nothing in this file
# hardcodes where a node goes — press F9 in a dev build to drag the tree
# around and save it back (see crystal_tree_editor.gd). Upgrade CONTENT
# (name/desc/cost/effect) still lives in Progression.UPGRADES, joined by key.
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
const CALL_TO_ARMS_ICON := CrystalTree.ICON_DIR + "call_to_arms.png"

const PANEL_SIZE := Vector2(1500, 1000)

# Light-on-dark palette for everything floating over the dimmed game screen.
const COL_TITLE    := Color(0.95, 0.82, 0.5)
const COL_SUBTITLE := Color(0.78, 0.68, 0.5, 0.9)
const COL_WALLET   := Color(0.62, 0.85, 1.0)
const COL_MAXED    := Color(1.0, 0.92, 0.55)
const CONN_DIM     := Color(0.4, 0.32, 0.18, 0.55)
const CONN_LIT     := Color(0.9, 0.7, 0.28, 0.95)
const GLOW_GOLD    := Color(1.0, 0.84, 0.35, 0.3)
const DIM_MODULATE := Color(0.5, 0.5, 0.58)
const LOCKED_MODULATE := Color(0.28, 0.28, 0.34)   # darker than dim: "not buyable yet"

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

# Zoom-out goes far enough to see a tree several times the size of the view;
# the old 0.6 floor assumed a hub-sized tree.
const ZOOM_MIN := 0.2
const ZOOM_MAX := 2.0
# How much of the tree's bounding box must stay inside the view. Clamping
# against the CONTENT rect (not the hub) is what makes distant nodes reachable
# — the old hub-based clamp put a hard wall a few hundred px out.
const PAN_MARGIN := 140.0

var _tree: CrystalTree        # layout data (data/crystal_tree.json)
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

var _reset_btn: Button
var _reset_armed := false

var _editor: CrystalTreeEditor   # null until F9 in a dev build

var _detail_bar: Panel
var _detail_prompt: Label
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_desc: Label
var _detail_stats: Label
var _buy_btn: Button

func _ready() -> void:
	_load_tree()
	_build_ui()

# Layout comes off disk on every open in a dev run so the editor's Save is
# visible without restarting the game.
func _load_tree() -> void:
	_tree = CrystalTree.load_from_disk()
	# Keep the game's view of caps/wording in step with whatever just loaded.
	Progression.apply_tree_overrides(_tree)
	var keys := PackedStringArray()
	for u in Progression.catalogue():
		keys.append(String(u["key"]))
	for problem in _tree.validate(keys):
		push_warning("CrystalShop tree: %s" % problem)

func open() -> void:
	if OS.has_feature("editor"):
		_load_tree()      # pick up editor saves without restarting the game
		_build_tree()
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
	_build_tree()
	_build_detail_bar(panel)

	var close_btn := _btn("✕  Close", Rect2((PANEL_SIZE.x - 200) / 2.0, PANEL_SIZE.y - 56, 200, 40))
	close_btn.pressed.connect(_close)
	panel.add_child(close_btn)

	# Full respec (2026-07-17 user request) — two-click confirm so a stray
	# click can't wipe the tree. Refunds every crystal spent.
	_reset_btn = _btn("Reset Upgrades", Rect2(30, PANEL_SIZE.y - 56, 220, 40))
	_reset_btn.pressed.connect(_on_reset_pressed)
	panel.add_child(_reset_btn)

	visible = false

# ── Pan & zoom ────────────────────────────────────────────────────────────────
func _on_tree_view_input(event: InputEvent) -> void:
	# Edit mode claims clicks on nodes (select/drag); anything it doesn't want
	# falls through to the normal pan/zoom below, so panning still works while
	# laying the tree out.
	if _editor != null and _editor.active and _editor.handle_tree_input(event):
		return
	if event is InputEventMouseButton:
		# Middle-drag also pans: in edit mode a left-drag on empty space is the
		# rubber-band select, so panning needs a button the editor never wants.
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE:
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

# Keep the tree's bounding box overlapping the view by at least PAN_MARGIN, so
# every node can be brought on screen but the canvas can't be flung into empty
# space. The allowed range grows with the tree, which the old hub-anchored
# clamp did not.
func _clamp_canvas() -> void:
	var s: float = _canvas.scale.x
	var b: Rect2 = _tree.bounds()
	var lo := Vector2(PAN_MARGIN, PAN_MARGIN) - b.end * s
	var hi := _tree_view.size - Vector2(PAN_MARGIN, PAN_MARGIN) - b.position * s
	_canvas.position = _canvas.position.clamp(lo.min(hi), hi.max(lo))

# Fit the whole tree in the view. The bigger the tree gets, the more this is
# the only practical way to find your way back to it.
func frame_all() -> void:
	var b: Rect2 = _tree.bounds().grow(60.0)
	if b.size.x <= 0.0 or b.size.y <= 0.0:
		return
	var s: float = clampf(minf(_tree_view.size.x / b.size.x, _tree_view.size.y / b.size.y),
			ZOOM_MIN, ZOOM_MAX)
	_canvas.scale = Vector2.ONE * s
	_canvas.position = _tree_view.size / 2.0 - b.get_center() * s
	_clamp_canvas()

# ── Tree construction ─────────────────────────────────────────────────────────
# Rebuildable from scratch: the editor calls this after every structural edit,
# so it must tear down its own layers rather than assuming a fresh canvas.
# Draw order: ambient backdrop glow, connector lines, per-node glows, then the
# node buttons on top.
func _build_tree() -> void:
	for child in _canvas.get_children():
		child.queue_free()
		_canvas.remove_child(child)
	_nodes.clear()
	_connectors.clear()

	_connector_layer = Node2D.new()
	_canvas.add_child(_connector_layer)
	_glow_layer = Control.new()
	_glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_glow_layer)
	var ambient := _make_glow(_tree.center, 380.0, Color(1.0, 0.85, 0.5, 0.055))
	ambient.visible = true
	_glow_layer.move_child(ambient, 0)

	for n in _tree.nodes:
		# One connector per parent link (a node may now hang off several
		# parents) — an empty parents array still draws the single hub line.
		var parent_keys: Array[String] = n.parents.duplicate()
		if parent_keys.is_empty():
			parent_keys.append("")
		for parent_key in parent_keys:
			var line := Line2D.new()
			line.points = PackedVector2Array([_tree.position_of(parent_key), n.pos])
			line.width = 6.0 if parent_key == "" else 4.0
			line.default_color = CONN_DIM
			_connector_layer.add_child(line)
			_connectors.append({"line": line, "parent": parent_key, "child": n.key})

	# Center: Call to Arms — always active, selectable for its info, no buy.
	var center_glow := _make_glow(_tree.center, _tree.center_size, Color(1.0, 0.9, 0.55, 0.45), 2.0)
	center_glow.visible = true
	var center_btn := _make_icon_button(_canvas, CALL_TO_ARMS_ICON, _tree.center, _tree.center_size)
	center_btn.tooltip_text = "Call to Arms — always active"
	center_btn.pressed.connect(_select.bind("call_to_arms"))
	var active_tag := _lbl(_canvas, "ACTIVE", 11, COL_TITLE,
		_tree.center + Vector2(-60, _tree.center_size / 2.0 + 4), Vector2(120, 18), true)
	_outline(active_tag)

	# Driven by the tree data, not by Progression order — a node whose key has
	# no upgrade entry still draws (validate() warns), so the editor can place
	# a slot before its content exists.
	for n in _tree.nodes:
		_add_upgrade_node(_canvas, n)

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
func _add_upgrade_node(canvas: Control, n: CrystalTree.TreeNode) -> void:
	var key: String = n.key
	var pos: Vector2 = n.pos
	var size: float = n.size
	var glow := _make_glow(pos, size, GLOW_GOLD)
	var icon_path: String = n.icon_path() if ResourceLoader.exists(n.icon_path()) else PLACEHOLDER_ICON
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
	_detail_bar = bar

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
	var max_lvl: int = Progression.max_level(key)
	var maxed: bool = lvl >= max_lvl
	var affordable: bool = Progression.can_afford(key)
	var locked: bool = Progression.is_locked(key)

	var ring: NodeRing = entry["ring"]
	# Clamped: lowering a node's max in the editor can leave an old save with
	# more levels than the cap, which would draw an arc past a full circle.
	ring.progress = clampf(float(lvl) / float(maxi(max_lvl, 1)), 0.0, 1.0)
	ring.maxed = maxed
	ring.selected = key == _selected_key
	ring.queue_redraw()

	var icon_col: Color = Color.WHITE if (lvl > 0 or affordable) else DIM_MODULATE
	if locked:
		icon_col = LOCKED_MODULATE
	(entry["icon"] as TextureRect).modulate = icon_col
	(entry["glow"] as TextureRect).visible = affordable
	(entry["badge"] as Label).visible = maxed
	if locked:
		var req_key := String(upgrade.get("requires", ""))
		var req_name := Progression.display_name(req_key) if req_key != "" else "?"
		(entry["button"] as Button).tooltip_text = "%s — locked (requires %s)" % [
			Progression.display_name(key), req_name]
	else:
		(entry["button"] as Button).tooltip_text = "%s — %d/%d" % [Progression.display_name(key), lvl, max_lvl]

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
	var max_lvl: int = Progression.max_level(_selected_key)
	var cost: int = Progression.next_cost(_selected_key)
	var is_float: bool = upgrade.get("is_float", false)
	var per: float = float(upgrade["effect_per_level"])
	var eff_fmt: String = upgrade.get("effect", "%d")
	var cur_txt: String = (eff_fmt % (per * lvl)) if is_float else (eff_fmt % int(per * lvl))
	var next_txt: String = (eff_fmt % (per * (lvl + 1))) if is_float else (eff_fmt % int(per * (lvl + 1)))

	_detail_icon.texture = load(_icon_path_for(_selected_key))
	_detail_name.text = "%s  —  Level %d/%d" % [Progression.display_name(_selected_key), lvl, max_lvl]
	_detail_desc.text = Progression.display_desc(_selected_key)
	if cost < 0:
		_detail_stats.text = "%s  (maxed out)" % cur_txt
		_buy_btn.text = "MAXED"
		_buy_btn.disabled = true
	elif Progression.is_locked(_selected_key):
		var req_key := String(upgrade.get("requires", ""))
		var req_name := Progression.display_name(req_key) if req_key != "" else "?"
		_detail_stats.text = "Locked — buy a level of %s first." % req_name
		_buy_btn.text = "LOCKED"
		_buy_btn.disabled = true
	else:
		_detail_stats.text = "%s   →   %s" % [cur_txt, next_txt]
		_buy_btn.text = "Buy — %d crystals" % cost
		_buy_btn.disabled = not Progression.can_afford(_selected_key)

func _icon_path_for(key: String) -> String:
	var n := _tree.find(key)
	if n != null and ResourceLoader.exists(n.icon_path()):
		return n.icon_path()
	return PLACEHOLDER_ICON

func _select(key: String) -> void:
	_selected_key = key
	_refresh()

func _on_buy() -> void:
	if _selected_key != "" and Progression.buy(_selected_key):
		_refresh()

func _on_reset_pressed() -> void:
	if not _reset_armed:
		var spent: int = Progression.total_spent()
		if spent <= 0:
			return   # nothing to refund
		_reset_armed = true
		_reset_btn.text = "Refund %d — sure?" % spent
		# Disarm automatically if they wander off.
		get_tree().create_timer(4.0).timeout.connect(_disarm_reset)
		return
	var refund: int = Progression.reset_all()
	_disarm_reset()
	_selected_key = ""
	_refresh()

func _disarm_reset() -> void:
	_reset_armed = false
	if is_instance_valid(_reset_btn):
		_reset_btn.text = "Reset Upgrades"

func _close() -> void:
	visible = false
	closed.emit()

func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	# F9 = tree layout editor. Dev-only: res:// is read-only in an exported
	# build, so there would be nothing to save to.
	if OS.has_feature("editor") and event is InputEventKey and event.pressed \
			and not event.echo and event.keycode == KEY_F9:
		_toggle_editor()
		get_viewport().set_input_as_handled()
		return
	if _editor != null and _editor.active and event.is_action_pressed("ui_cancel"):
		_toggle_editor()   # Esc leaves edit mode first, not the whole shop
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_close()

func _toggle_editor() -> void:
	if _editor == null:
		_editor = CrystalTreeEditor.new()
		_editor.shop = self
		# Sits on the shop's panel, above the tree view.
		(_tree_view.get_parent() as Control).add_child(_editor)
	_editor.set_active(not _editor.active)

# ── Editor support ────────────────────────────────────────────────────────────
# Everything below exists for CrystalTreeEditor (dev-only, F9). The shop keeps
# ownership of the canvas and its coordinate space; the editor asks it to move
# things and rebuild. Kept as a thin surface so the play-mode path above stays
# unaware that an editor exists.

func tree_data() -> CrystalTree:
	return _tree

func rebuild_tree() -> void:
	_build_tree()
	_refresh()
	if _editor != null:
		_editor.on_tree_rebuilt()

# Screen position inside _tree_view -> canvas coordinates (the space node
# positions are stored in), undoing the pan offset and zoom scale.
func view_to_canvas(view_pos: Vector2) -> Vector2:
	return (view_pos - _canvas.position) / _canvas.scale.x

# Middle of whatever the user is currently looking at — where a newly added
# node should land, now that the canvas is big enough to pan far from the hub.
func view_center_canvas() -> Vector2:
	return view_to_canvas(_tree_view.size / 2.0)

# Topmost node whose icon box contains this canvas point, or "" for empty space.
# Walks backwards so later-added nodes (drawn on top) win the hit test.
func node_at(canvas_pos: Vector2) -> String:
	for i in range(_nodes.size() - 1, -1, -1):
		var entry: Dictionary = _nodes[i]
		var n := _tree.find(entry["key"])
		if n == null:
			continue
		if canvas_pos.distance_to(n.pos) <= n.size / 2.0:
			return n.key
	return ""

# Move a node's visuals without a full rebuild — called every mouse-motion
# frame during a drag, so it must stay allocation-free.
func move_node_visual(key: String, pos: Vector2) -> void:
	var n := _tree.find(key)
	if n == null:
		return
	n.pos = pos
	for entry: Dictionary in _nodes:
		if entry["key"] != key:
			continue
		var btn: Button = entry["button"]
		btn.position = pos - Vector2.ONE * n.size / 2.0
		var glow: TextureRect = entry["glow"]
		glow.position = pos - glow.size / 2.0
		break
	refresh_connectors()

# Re-point every connector line at its current parent/child positions. Looked
# up by key rather than by parallel index, since a node can now have several
# connectors (one per parent) so _connectors and _tree.nodes no longer line
# up 1:1.
func refresh_connectors() -> void:
	for c: Dictionary in _connectors:
		var n := _tree.find(String(c["child"]))
		if n == null:
			continue
		(c["line"] as Line2D).points = PackedVector2Array([
			_tree.position_of(String(c["parent"])), n.pos])

# In edit mode the buttons must stop eating clicks so the tree view's input
# handler can run drag/hit-test logic uniformly over every node.
func set_nodes_clickable(on: bool) -> void:
	var filter := Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	for entry: Dictionary in _nodes:
		(entry["button"] as Button).mouse_filter = filter

func editor_canvas() -> Control:
	return _canvas

# Edit mode has no use for the parchment detail bar (buying is not the point),
# so hand that strip to the tree view — ~200 extra px of authoring height.
func set_tree_view_expanded(on: bool) -> void:
	_detail_bar.visible = not on
	_tree_view.size = Vector2(PANEL_SIZE.x - 32,
			(PANEL_SIZE.y - _tree_view.position.y - 66) if on else 650.0)
	_clamp_canvas()

func highlight_nodes(keys: PackedStringArray) -> void:
	for entry: Dictionary in _nodes:
		var ring: NodeRing = entry["ring"]
		ring.selected = keys.has(entry["key"])
		ring.queue_redraw()

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
