extends CanvasLayer
class_name RelicScreen

# Forced pick-1-of-3 relic screen shown at the start of every 10th wave (1, 11, … 91).
# Mirrors the gacha-card look of the hero shop / level-up screen: each card is
# tinted by its rolled grade colour, with a grade badge in the corner.

signal chosen(relic)
signal reroll_requested()

const PANEL_W := 1000.0
const PANEL_H := 520.0
const CARD_W  := 290.0
const CARD_H  := 260.0
const CARD_ROW_Y := 136.0

# ── Slot-machine reveal pacing (2026-07-21, restaggered same day) — shared
# with hero_shop/level_up_screen. Only 2 reels here (relics have no numeric
# growth to roll): identity (icon+name), then rank (badge+card tint), each
# fully awaited in turn, so REEL_DURATION*2 is one card's full cascade time.
# CARD_STAGGER is HALF that — cards overlap like real slot reels: card 2
# starts while card 1 is still spinning, card 3 comes on right as card 1
# finishes, then card 2 lands, then card 3 shortly after.
const NEUTRAL_COL   := Color(0.14, 0.14, 0.19)
const REEL_TICKS    := 8
const REEL_START    := 0.035
const REEL_GROWTH   := 1.22
const REEL_DURATION := 0.62
const CARD_STAGGER  := REEL_DURATION   # half of (identity + rank), i.e. one reel's duration

var _panel:      Panel
var _sub_lbl:    Label
var _card_row:   HBoxContainer
var _reroll_btn: Button

var _wave:            int = 0
var _rerolls_left:    int = 0

func _ready() -> void:
	_build_ui()
	visible = false

# charges: how many free rerolls this visit gets (from the "+1 Reroll" crystal
# tree upgrade — Progression.get_bonus("+1 Reroll")). Passed in rather than
# read here so this screen stays decoupled from Progression.
func present(offers: Array, wave: int, charges: int = 0) -> void:
	visible = true
	_wave = wave
	_rerolls_left = charges
	_sub_lbl.text = "Wave %d  ·  choose a relic — it lasts the rest of your run" % wave
	_rebuild_cards(offers)
	_refresh_reroll_btn()
	_center_panel()

# Called by main_game after it rolls fresh offers for a spent reroll charge.
func set_offers(offers: Array, charges_left: int) -> void:
	_rerolls_left = charges_left
	_rebuild_cards(offers)
	_refresh_reroll_btn()

func _rebuild_cards(offers: Array) -> void:
	for c in _card_row.get_children():
		c.queue_free()
	for i in range(offers.size()):
		_card_row.add_child(_make_card(offers[i], i))

func _refresh_reroll_btn() -> void:
	if not _reroll_btn:
		return
	_reroll_btn.visible = _rerolls_left > 0
	_reroll_btn.text = "↻ Reroll (%d left)" % _rerolls_left
	# No reroll charge (the common case) = no button row, so drop the panel's
	# reserved strip instead of leaving it empty under the cards.
	_panel.size.y = PANEL_H if _reroll_btn.visible else CARD_ROW_Y + CARD_H + 48.0
	_center_panel()

# ── Card builder ──────────────────────────────────────────────────────────────
func _make_card(relic: Dictionary, idx: int) -> Button:
	var grade: String = relic.get("grade", "D")
	var grade_col: Color = Relic.grade_color(grade)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
	btn.text = ""
	# Card stays neutral-tinted until its OWN rank reel lands (2026-07-21) —
	# see hero_shop.gd's _paint_card_grade for why. Hidden via modulate/mouse
	# filter rather than `visible` because _card_row is an HBoxContainer,
	# which excludes invisible children from layout entirely — hiding with
	# `visible=false` would collapse the row and shift cards as they revealed
	# instead of each just popping in at its already-reserved slot.
	_paint_card_grade(btn, NEUTRAL_COL)
	btn.modulate = Color(1, 1, 1, 0)
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Grade badge (top-right)
	var badge_bg := ColorRect.new()
	badge_bg.position = Vector2(CARD_W - 46, 12)
	badge_bg.size     = Vector2(34, 34)
	badge_bg.color    = NEUTRAL_COL.darkened(0.3)
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(badge_bg)
	var badge_lbl := Label.new()
	badge_lbl.text = ""
	badge_lbl.position = badge_bg.position
	badge_lbl.size     = badge_bg.size
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	UITheme.apply_font(badge_lbl, UITheme.FONT_HEADER + 2)
	badge_lbl.add_theme_color_override("font_color", grade_col)
	badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(badge_lbl)

	# "RELIC" kicker
	_lbl(btn, "RELIC", 11, Color(0.55, 0.55, 0.72), Vector2(0, 16), Vector2(CARD_W, 24), true)

	# Icon (centered, above the name) — always created (even if this relic has
	# no art yet) so the identity reel has a stable node to paint into.
	# 104 (was 80): the card had a band of dead space under the description.
	var icon := TextureRect.new()
	icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position     = Vector2((CARD_W - 104) / 2.0, 40)
	icon.size         = Vector2(104, 104)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)

	# Name (grade coloured). Header step, like hero names in the hero shop —
	# base 24 snapped up to DISPLAY (42), three one-per-screen headlines at once.
	var name_lbl := _lbl(btn, "", 14, grade_col, Vector2(0, 150), Vector2(CARD_W, 30), true)

	# Divider — BELOW the name. At y 162 it sat on the 42px name's baseline and
	# read as a strikethrough.
	var div := ColorRect.new()
	div.position = Vector2(28, 188)
	div.size     = Vector2(CARD_W - 56, 1)
	div.color    = Color(grade_col.r, grade_col.g, grade_col.b, 0.4)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(div)

	# Description (wrapped)
	var desc := Label.new()
	desc.position             = Vector2(24, 196)
	desc.size                 = Vector2(CARD_W - 48, 58)
	UITheme.apply_font(desc, UITheme.FONT_VALUE + 2)
	desc.add_theme_color_override("font_color", Color(0.82, 0.82, 0.92))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	desc.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	desc.text                 = relic.get("desc", "")
	btn.add_child(desc)

	btn.pressed.connect(_on_pick.bind(relic))
	_run_card_reveal(idx * CARD_STAGGER, btn, icon, name_lbl, badge_lbl, badge_bg, relic)
	return btn

# Repaints a card's normal/hover/pressed background+border — called once with
# NEUTRAL_COL at build time, then on every tick of the rank reel so the tint
# genuinely rolls with the rank instead of showing the final grade up front.
func _paint_card_grade(btn: Button, col: Color) -> void:
	UITheme.paint_card(btn, col)

# Wait for this card's turn -> fade in -> identity reel (icon+name cycle
# through other relics) -> rank reel (badge + card tint), sequential.
func _run_card_reveal(delay: float, btn: Button, icon: TextureRect, name_lbl: Label,
		badge_lbl: Label, badge_bg: ColorRect, relic: Dictionary) -> void:
	var tree := get_tree()
	if not tree:
		return
	if delay > 0.0:
		await tree.create_timer(delay).timeout
	if not is_instance_valid(btn):
		return
	btn.modulate = Color(1, 1, 1, 1)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	# Reel 1: relic identity — icon and name change TOGETHER each tick.
	var identity_pool: Array = []
	for _i in range(8):
		identity_pool.append(Relic.POOL[randi() % Relic.POOL.size()])
	var paint_identity := func(v: Dictionary) -> void:
		var ipath: String = Relic.icon_path(v)
		icon.texture = (load(ipath) as Texture2D) if ipath != "" else null
		name_lbl.text = str(v.get("name", "Relic"))
	var punch_identity := func() -> void: GradeRoll.land_punch(icon)
	await GradeRoll.spin(btn, identity_pool, relic, paint_identity,
		0.0, REEL_TICKS, REEL_START, REEL_GROWTH, punch_identity)
	if not is_instance_valid(btn):
		return

	# Reel 2: rank badge + card/badge background tint.
	var final_grade: String = relic.get("grade", "D")
	var paint_rank := func(g: String) -> void:
		var gcol := Relic.grade_color(g)
		badge_lbl.text = g
		badge_lbl.add_theme_color_override("font_color", gcol)
		badge_bg.color = gcol.darkened(0.4)
		_paint_card_grade(btn, gcol)
	var punch_rank := func() -> void: GradeRoll.land_punch(badge_lbl)
	# Relic.GRADE_ORDER, not GradeRoll.GRADE_SEQUENCE — relics never roll an
	# F grade (see Relic.gd header), so the reel shouldn't flash one either.
	await GradeRoll.spin(btn, Relic.GRADE_ORDER, final_grade, paint_rank,
		0.0, REEL_TICKS, REEL_START, REEL_GROWTH, punch_rank)

func _on_pick(relic: Dictionary) -> void:
	visible = false
	chosen.emit(relic)

# ── UI shell (built once) ─────────────────────────────────────────────────────
func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color        = Color(0, 0, 0, 0.62)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	# UI theme pass 2026-07-04: dobo card panel instead of flat navy box —
	# matches hero_shop/level_up_screen (this screen's own header comment
	# already says it mirrors their gacha-card look, this was just missed
	# in the original pass).
	_panel.add_theme_stylebox_override("panel", UITheme.menu_surface_box())
	overlay.add_child(_panel)
	UITheme.menu_header(_panel, Rect2(18, 18, PANEL_W - 36, 112))

	# Titles start below the panel texture's top stripe (they sat on it at y 22).
	_lbl(_panel, "CHOOSE A RELIC", 30, UITheme.menu_title_color(),
		Vector2(0, 39), Vector2(PANEL_W, 42), true, false)
	_sub_lbl = _lbl(_panel, "", 14, UITheme.menu_subtitle_color(),
		Vector2(0, 79), Vector2(PANEL_W, 24), true)

	_card_row = HBoxContainer.new()
	_card_row.add_theme_constant_override("separation", 22)
	_card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_row.position  = Vector2(0, CARD_ROW_Y)
	_card_row.size      = Vector2(PANEL_W, CARD_H)
	_panel.add_child(_card_row)

	_reroll_btn = Button.new()
	_reroll_btn.text = "↻ Reroll"
	# Gold like every other action button (it was the only unstyled default
	# Godot button left), and above the panel's bottom stripe instead of on it.
	UITheme.style_button(_reroll_btn)
	UITheme.apply_font(_reroll_btn, UITheme.FONT_HEADER + 2)
	_reroll_btn.position = Vector2(PANEL_W / 2.0 - 100, CARD_ROW_Y + CARD_H + 16)
	_reroll_btn.size     = Vector2(200, 44)
	_reroll_btn.pressed.connect(func(): reroll_requested.emit())
	_panel.add_child(_reroll_btn)

	_center_panel()

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_panel.position = (vp - _panel.size) / 2.0

# ── Small helpers (mirrors level_up_screen) ───────────────────────────────────
func _flat(bg: Color, border: Color, bw: float, radius: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(int(bw))
	s.set_corner_radius_all(int(radius))
	return s

func _lbl(parent: Control, text: String, size: int, color: Color,
		pos: Vector2, sz: Vector2, centered: bool = false, enlarge: bool = true) -> Label:
	var l := Label.new()
	l.text     = text
	l.position = pos
	l.size     = sz
	# This screen's supporting text gets a 2px readability bump. Its title keeps
	# the existing display size (enlarge=false at the title call).
	UITheme.apply_font(l, UITheme.body_font(size) + (2 if enlarge else 0))
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
