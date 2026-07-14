extends CanvasLayer
class_name CrystalShop

# Branching tree layout (2026-07-10 user spec): Call to Arms sits at the
# center, always active (not purchasable — see Progression.gd, it's
# deliberately NOT in Progression.UPGRADES). The 4 core upgrades
# (starting_gold/team_hp/bonus_xp/hero_slots) are the first ring out from the
# center, one per compass direction. Everything else added to the stat tree
# so far hangs off whichever core node it thematically belongs to, fanned out
# in a second ring. Placeholder icon for every node until dedicated art
# lands — see GEMINI_CRYSTAL_SHOP_PROMPTS.md for the real ones being drawn up.
signal closed()

const PLACEHOLDER_ICON := "res://assets/UI/Vector_UI_Pack_dobo_ui/Icons/128px/skills_icon_128px.png"

const PANEL_SIZE := Vector2(1500, 1000)
const TREE_CENTER := Vector2(750, 580)   # relative to panel top-left
const TIER1_RADIUS := 170.0
const TIER2_RADIUS := 340.0
const CENTER_NODE_SIZE := 150.0
const TIER1_NODE_SIZE := 120.0
const TIER2_NODE_SIZE := 96.0

# Angle in degrees, standard math convention (0 = right, 90 = up, CCW), since
# the position formula below flips Y for screen space.
const CORE_ANGLES := {
	"team_hp":       90.0,   # top    — Fortified, parent of the stat tree
	"starting_gold": 0.0,    # right  — Head Start, parent of economy branches
	"bonus_xp":      270.0,  # bottom — Quick Learner, parent of XP branches
	"hero_slots":    180.0,  # left   — Roster Expansion, parent of team branches
}

# Extended (tier-2) nodes → which core node they branch off. Add new upgrades
# here as they get implemented (Bargain Hunter → starting_gold, Warm Bench →
# hero_slots, Quick Study → bonus_xp, etc.) — nothing else needs to change,
# the fan-out spacing is computed automatically from how many share a parent.
const EXTENDED_PARENT := {
	"crystal_drop":         "starting_gold",
	"bench_slots":          "hero_slots",
	"mana_well":            "team_hp",
	"spellpower":           "team_hp",
	"might":                "team_hp",
	"warding":              "team_hp",
	"fleetfoot":            "team_hp",
	"vitality_flow":        "team_hp",
	"mana_flow":            "team_hp",
	"swiftness":            "team_hp",
	"lethality":            "team_hp",
	"killing_blow":         "team_hp",
	"elemental_attunement": "team_hp",
}
const MAX_FAN_ARC_DEG := 150.0   # widest a fan is allowed to spread before nodes start crowding

var _wallet_lbl: Label
var _nodes: Array = []   # [{ "button": Button, "key": String }, ...]
var _connector_layer: Node2D

func _ready() -> void:
	_build_ui()

func open() -> void:
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

	_lbl(panel, "✦  CRYSTAL SHOP  ✦", 24, UITheme.TEXT_HEADER,
		Vector2(0, 20), Vector2(PANEL_SIZE.x, 40), true)
	_lbl(panel, "Upgrades persist between runs. Call to Arms is always active.", 13,
		Color(0.45, 0.35, 0.2, 0.85), Vector2(0, 58), Vector2(PANEL_SIZE.x, 22), true)

	_lbl(panel, "Your Crystals:", 15, Color(0.35, 0.25, 0.1),
		Vector2(30, 88), Vector2(200, 26))
	_wallet_lbl = _lbl(panel, "0", 22, Color(0.2, 0.5, 0.85),
		Vector2(230, 84), Vector2(120, 30))

	# Connector lines get their own layer, added BEFORE any node buttons so
	# they render behind them.
	_connector_layer = Node2D.new()
	panel.add_child(_connector_layer)

	_build_tree(panel)

	var close_btn := _btn("✕  Close", Rect2((PANEL_SIZE.x - 200) / 2.0, PANEL_SIZE.y - 56, 200, 40))
	close_btn.pressed.connect(_close)
	panel.add_child(close_btn)

	visible = false

# ── Tree construction ─────────────────────────────────────────────────────────
func _build_tree(panel: Panel) -> void:
	# Center: Call to Arms — always active, not purchasable, no buy button.
	var center_node := _make_node_frame(TREE_CENTER, CENTER_NODE_SIZE)
	center_node.tooltip_text = "Call to Arms\nAlways active — every run starts with 1 free recruited hero instead of starting gold."
	panel.add_child(center_node)

	# Tier 1: the 4 core upgrades, one per compass direction.
	var tier1_pos: Dictionary = {}   # key -> Vector2, so tier-2 fan-out can find its parent
	for upgrade in Progression.UPGRADES:
		var key: String = upgrade["key"]
		if not CORE_ANGLES.has(key):
			continue
		var pos: Vector2 = TREE_CENTER + _angle_offset(CORE_ANGLES[key], TIER1_RADIUS)
		tier1_pos[key] = pos
		_draw_connector(TREE_CENTER, pos)
		_add_upgrade_node(panel, upgrade, pos, TIER1_NODE_SIZE)

	# Tier 2: fan each parent's children evenly across an arc centered on the
	# parent's own angle.
	var children_by_parent: Dictionary = {}   # parent_key -> Array[upgrade dict]
	for upgrade in Progression.UPGRADES:
		var key: String = upgrade["key"]
		if not EXTENDED_PARENT.has(key):
			continue
		var parent_key: String = EXTENDED_PARENT[key]
		if not children_by_parent.has(parent_key):
			children_by_parent[parent_key] = []
		children_by_parent[parent_key].append(upgrade)

	for parent_key: String in children_by_parent:
		if not (CORE_ANGLES.has(parent_key) and tier1_pos.has(parent_key)):
			continue
		var parent_angle: float = CORE_ANGLES[parent_key]
		var kids: Array = children_by_parent[parent_key]
		var n: int = kids.size()
		var arc: float = minf(MAX_FAN_ARC_DEG, 14.0 * n)
		for i in range(n):
			var t: float = 0.5 if n == 1 else float(i) / float(n - 1)   # 0..1 across the fan
			var angle: float = parent_angle - arc / 2.0 + arc * t
			var pos: Vector2 = TREE_CENTER + _angle_offset(angle, TIER2_RADIUS)
			_draw_connector(tier1_pos[parent_key], pos)
			_add_upgrade_node(panel, kids[i], pos, TIER2_NODE_SIZE)

func _angle_offset(angle_deg: float, radius: float) -> Vector2:
	var rad: float = deg_to_rad(angle_deg)
	return Vector2(cos(rad), -sin(rad)) * radius   # -sin: screen Y grows downward

func _draw_connector(from: Vector2, to: Vector2) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.width = 5.0
	line.default_color = Color(0.55, 0.4, 0.15, 0.7)
	_connector_layer.add_child(line)

# Plain frame (no upgrade behind it) — used for the always-active center node.
# slot_box(false) = the gold slot texture (reserved for "special/always active"
# here); slot_box(true) = the plain white slot, used for disabled/maxed nodes.
func _make_node_frame(pos: Vector2, size: float) -> Control:
	var frame := Panel.new()
	frame.position = pos - Vector2.ONE * size / 2.0
	frame.size = Vector2.ONE * size
	frame.add_theme_stylebox_override("panel", UITheme.slot_box(false))
	var icon := TextureRect.new()
	icon.texture = load(PLACEHOLDER_ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(icon)
	return frame

# One purchasable node: icon + level pips, click to buy, tooltip has the full
# name/desc/cost (refreshed in _refresh_card).
func _add_upgrade_node(panel: Panel, upgrade: Dictionary, pos: Vector2, size: float) -> void:
	var key: String = upgrade["key"]
	var btn := Button.new()
	btn.position = pos - Vector2.ONE * size / 2.0
	btn.size = Vector2.ONE * size
	# NOT flat — flat buttons skip drawing the "normal" stylebox entirely, and
	# the slot frame needs to stay visible at all times, not just on hover.
	# Gold slot = actionable (can afford / not maxed); white/plain slot = maxed
	# out or can't afford right now (see _refresh_node's disabled toggle).
	btn.add_theme_stylebox_override("normal", UITheme.slot_box(false))
	btn.add_theme_stylebox_override("hover", UITheme.slot_box(false))
	btn.add_theme_stylebox_override("pressed", UITheme.slot_box(false))
	btn.add_theme_stylebox_override("disabled", UITheme.slot_box(true))
	btn.pressed.connect(_on_buy.bind(key))
	panel.add_child(btn)

	var icon := TextureRect.new()
	icon.texture = load(PLACEHOLDER_ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_bottom = -18   # leave room for the level label below the icon
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)

	var level_lbl := Label.new()
	level_lbl.name = "LevelLbl"
	level_lbl.anchor_top = 1.0; level_lbl.anchor_bottom = 1.0
	level_lbl.offset_top = -18; level_lbl.offset_bottom = 0
	level_lbl.anchor_right = 1.0
	level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_lbl.add_theme_font_size_override("font_size", UITheme.body_font(12))
	level_lbl.add_theme_color_override("font_color", Color(0.35, 0.25, 0.1))
	level_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(level_lbl)

	_nodes.append({"button": btn, "key": key})

# ── Refresh (tooltips + level pips + afford-gating) ───────────────────────────
func _refresh() -> void:
	_wallet_lbl.text = "%d" % Progression.crystals
	for entry in _nodes:
		_refresh_node(entry["button"], entry["key"])

func _refresh_node(btn: Button, key: String) -> void:
	var upgrade := Progression._find(key)
	if upgrade.is_empty():
		return

	var lvl: int = Progression.get_level(key)
	var max_lvl: int = int(upgrade["max_level"])
	var cost: int = Progression.next_cost(key)
	var is_float: bool = upgrade.get("is_float", false)
	var bonus_f: float = Progression.get_bonus_float(key) if is_float else float(Progression.get_bonus(key))
	var eff_fmt: String = upgrade.get("effect", "%d")
	var eff_text: String = (eff_fmt % bonus_f) if is_float else (eff_fmt % int(bonus_f))

	(btn.get_node("LevelLbl") as Label).text = "%d/%d" % [lvl, max_lvl]

	if cost < 0:
		btn.disabled = true
		btn.tooltip_text = "%s (MAXED)\n%s\nCurrent: %s" % [upgrade["name"], upgrade["desc"], eff_text]
	else:
		btn.disabled = not Progression.can_afford(key)
		btn.tooltip_text = "%s — Level %d/%d\n%s\nCurrent: %s\nNext level: %d crystals" % [
			upgrade["name"], lvl, max_lvl, upgrade["desc"], eff_text, cost]

func _on_buy(key: String) -> void:
	if Progression.buy(key):
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
	b.add_theme_font_size_override("font_size", 14)
	UITheme.style_button(b)
	return b
