extends CanvasLayer
class_name HeroShop

signal hero_chosen(unit_class: UnitBase.UnitClass, element: UnitBase.Element, rolls: Dictionary)
signal cancelled()
signal reroll_requested()

# Economy v3 (2026-07-03): 30 → 10 — whole economy rescaled to coin-drop size
# (10 starting gold, ~1g coin drops per kill). Tune in balance.gd.
const HERO_COST := Balance.HERO_COST
const REROLL_COST := Balance.REROLL_COST

const SPRITE_FOLDERS := {
	UnitBase.UnitClass.WARRIOR:    "warrior",
	UnitBase.UnitClass.RANGER:     "archer",
	UnitBase.UnitClass.MONK:       "monk",
	UnitBase.UnitClass.THIEF:      "thief",
	UnitBase.UnitClass.BLACK_MAGE: "black_mage",
	UnitBase.UnitClass.WHITE_MAGE: "white_mage",
	UnitBase.UnitClass.RED_MAGE:   "red_mage",
	UnitBase.UnitClass.BLOODHOUND: "warrior",
	UnitBase.UnitClass.BOUNCER:    "bouncer",
	UnitBase.UnitClass.HEADHUNTER: "archer",
}
const IDLE_FRAME := Rect2(0, 640, 64, 64)

# Card layout constants
const CARD_W     := 400.0
const CARD_H     := 780.0
const PANEL_W    := 1340.0
const PANEL_H    := 950.0
# 205, down from 240: the kit block below grew from two ability rows to three,
# and folding the element into the rank line only paid for 24 of the 60 extra
# pixels. The portrait covers the rest so the stat table below keeps the same
# room it had — see _make_card's y arithmetic.
const PORT_SIZE  := 205.0

var _offers:    Array = []
var _card_btns: Array = []

# VD-16 seeking tool: verbs of the seed relics the player owns, set by main_game
# before open(). Heroes with one of these verbs are SEED_WEIGHT times as likely.
const SEED_WEIGHT := 3.0
var favored_verbs: Array = []
# Hero merging (2026-09-28): classes the player already fields/benches are
# OWNED_WEIGHT times as likely, so a second copy to merge turns up more often
# (~11% → ~16% per shop for a given owned hero) without crowding out variety.
const OWNED_WEIGHT := 1.5
var owned_classes: Array = []
# Slot indices the player has pinned so a reroll leaves them alone. Capacity
# comes from the Hold That crystal upgrade; empty (and the toggle hidden) until
# at least one node is bought. Cleared whenever a fresh shop opens.
var _locked:    Dictionary = {}
var _panel:     Panel
var _header:    TextureRect
var _title_lbl: Label
var _sub_lbl:   Label
var _cancel_btn: Button
var _reroll_btn: Button
var _slot_count: int = 3   # hero cards shown (raised by the Merchant's Ledger relic)
var _free_mode:  bool = false  # Call to Arms starting-hero pick (2026-07-10): no cost, no cancel

const CARD_GAP     := 20.0
const SIDE_MARGIN  := 50.0

# ── Slot-machine reveal pacing (2026-07-21, restaggered same day) ─────────────
# Shared by all three reels (hero identity, rank, stat growth) so each takes
# ~REEL_DURATION seconds to land. Cards now OVERLAP like real slot reels
# instead of fully waiting each other out (that read as too slow): CARD_STAGGER
# is HALF a card's full 3-reel cascade, so while card 1 is still spinning,
# card 2 comes on and starts spinning too; by the time card 3 comes on, card 1
# has just finished; card 2 lands next, then card 3 shortly after — all three
# settle in a tight cluster at the end instead of one strictly after another.
const NEUTRAL_COL   := Color(0.14, 0.14, 0.19)   # unrevealed card tint, before its rank reel lands
const REEL_TICKS    := 8
const REEL_START    := 0.035
const REEL_GROWTH   := 1.22
const REEL_DURATION := 0.62   # ~ REEL_START*(REEL_GROWTH^REEL_TICKS-1)/(REEL_GROWTH-1)
const CARD_STAGGER  := REEL_DURATION * 3.0 / 2.0   # half the identity+rank+growth cascade

func _ready() -> void:
	_build_ui()

# free_mode: Call to Arms' starting-hero pick — every card is pickable regardless
# of gold, the cancel button is hidden (you must choose one), and the header
# reads as a free grant rather than a shop.
func open(gold: int, slot_count: int = 3, free_mode: bool = false) -> void:
	_slot_count = maxi(3, slot_count)
	_free_mode = free_mode
	_layout_for_slots()
	_offers.clear()
	_locked.clear()          # locks are per-shop, not carried between rounds
	# NOTE: don't clear _card_btns here — _rebuild_all_cards() frees the previous
	# round's card nodes by iterating _card_btns first, THEN clears it. Emptying
	# the array early orphaned the old cards (never freed), so they lingered
	# behind the freshly rolling ones — the "two layers of heroes" bug (2026-07-22).
	_generate_offers()
	_rebuild_all_cards(gold)
	if _title_lbl:
		_title_lbl.text = "CHOOSE YOUR STARTING HERO" if _free_mode else "CHOOSE A HERO"
	if _sub_lbl:
		_sub_lbl.text = "Call to Arms — pick your first hero, free" if _free_mode \
			else "Each hero has unique stat rolls  ·  %dg each  ·  Roll again next round" % HERO_COST
	if _cancel_btn:
		_cancel_btn.visible = not _free_mode
	if _reroll_btn:
		_reroll_btn.visible = not _free_mode   # the free starting pick can't reroll
		_reroll_btn.disabled = gold < REROLL_COST
	visible = true

# Widen the panel and re-center the header/cancel for the current card count so
# 4-card shops (Merchant's Ledger) fit without cramping the default 3-card layout.
func _layout_for_slots() -> void:
	var panel_w: float = _slot_count * CARD_W + (_slot_count - 1) * CARD_GAP + 2.0 * SIDE_MARGIN
	_panel.size.x = panel_w
	if _header: _header.size.x = panel_w - 36.0
	if _title_lbl: _title_lbl.size.x = panel_w
	if _sub_lbl:   _sub_lbl.size.x = panel_w
	if _cancel_btn: _cancel_btn.position.x = (panel_w - 200) / 2.0
	if _reroll_btn: _reroll_btn.position.x = panel_w - SIDE_MARGIN - 190
	_center_panel()

# Refresh the offers in place (called by main_game after it charges the reroll).
func reroll(gold: int) -> void:
	# Hold That (2026-08-03): locked slots survive the reroll untouched. Grab
	# them BEFORE clearing, then hand them back to _generate_offers by index.
	var keep := {}
	for idx: int in _locked:
		if idx < _offers.size() and _offers[idx] != null:
			keep[idx] = _offers[idx]
	_offers.clear()
	# See open(): _rebuild_all_cards() is what frees the old card nodes (it walks
	# _card_btns then clears it). Clearing here would orphan them behind the new
	# roll — the two-layer bug.
	_generate_offers(keep)
	_rebuild_all_cards(gold)
	if _reroll_btn:
		_reroll_btn.disabled = (not _free_mode) and gold < REROLL_COST

func _generate_offers(preserve: Dictionary = {}) -> void:
	# Element is fixed per class (2026-07-31) — offers are unique by CLASS alone,
	# where they used to be unique by class+element.
	# Crystal Shop hero unlocks (2026-08-01): only classes that are starter
	# heroes or have their hero_unlock_* upgrade purchased can be recruited.
	var classes: Array = []
	for cls in UnitFactory.get_all_classes():
		if Progression.is_hero_unlocked(cls):
			classes.append(cls)
	if classes.is_empty():
		return

	# Slots are filled by index now rather than appended, so a locked slot can
	# keep its exact offer while the rest reroll around it (2026-08-03).
	var out: Array = []
	out.resize(_slot_count)
	var used: Array = []
	for idx: int in preserve:
		if idx >= 0 and idx < _slot_count:
			out[idx] = preserve[idx]
			used.append(preserve[idx]["class"])
	for i in range(_slot_count):
		if out[i] != null:
			continue
		# Unique-by-class, but only while there are classes left to be unique
		# with — fewer unlocked classes than slots used to spin here forever.
		var cls: UnitBase.UnitClass = _pick_class(classes)
		if used.size() < classes.size():
			var guard := 0
			while cls in used and guard < 200:
				cls = _pick_class(classes)
				guard += 1
		used.append(cls)
		out[i] = {
			"class":   cls,
			"element": UnitFactory.element_for_class(cls),
			"rolls":   UnitFactory.generate_recruit_rolls(),
		}
	_offers = out

# With no seed owned this is the plain uniform draw, randi() call for call.
func _pick_class(classes: Array) -> int:
	if favored_verbs.is_empty() and owned_classes.is_empty():
		return classes[randi() % classes.size()]
	var total := 0.0
	for c in classes:
		total += _class_weight(c)
	var r := randf() * total
	for c in classes:
		r -= _class_weight(c)
		if r <= 0.0:
			return c
	return classes[-1]

func _class_weight(cls: int) -> float:
	var w := 1.0
	for v in favored_verbs:
		if HeroVerbs.has_verb(cls, String(v)):
			w = SEED_WEIGHT
			break
	if cls in owned_classes:
		w *= OWNED_WEIGHT
	return w

# ── UI shell (built once) ─────────────────────────────────────────────────────
func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.80)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	# UI theme pass 2026-07-04: dobo card panel instead of flat navy box.
	_panel.add_theme_stylebox_override("panel", UITheme.menu_surface_box())
	overlay.add_child(_panel)
	_header = UITheme.menu_header(_panel, Rect2(18, 6, PANEL_W - 36, 92))

	_title_lbl = _lbl(_panel, "CHOOSE A HERO", 34, UITheme.menu_title_color(),
		Vector2(0, 16), Vector2(PANEL_W, 44), true, false)
	_sub_lbl = _lbl(_panel, "Each hero has unique stat rolls  ·  %dg each  ·  Roll again next round" % HERO_COST,
		15, UITheme.menu_subtitle_color(), Vector2(0, 52), Vector2(PANEL_W, 28), true)

	# Cancel button
	_cancel_btn = _btn("Cancel", Rect2((PANEL_W - 200) / 2.0, PANEL_H - 54, 200, 40))
	_cancel_btn.pressed.connect(_on_cancel)
	_panel.add_child(_cancel_btn)

	# Reroll — refresh the offers for a small gold cost (2026-07-17 economy valve).
	_reroll_btn = _btn("↻ Reroll (%dg)" % REROLL_COST, Rect2(0, PANEL_H - 54, 190, 40))
	_reroll_btn.pressed.connect(func(): reroll_requested.emit())
	_panel.add_child(_reroll_btn)

	visible = false
	_center_panel()

# Destroy and recreate all hero cards (called on open()).
func _rebuild_all_cards(gold: int) -> void:
	for old in _card_btns:
		if is_instance_valid(old):
			old.queue_free()
	_card_btns.clear()

	var total_w: float = _slot_count * CARD_W + (_slot_count - 1) * CARD_GAP
	var start_x: float = (_panel.size.x - total_w) / 2.0

	for i in range(_slot_count):
		var x    := start_x + i * (CARD_W + CARD_GAP)
		var card := _build_card(Vector2(x, 100), i, gold)
		_panel.add_child(card)
		_card_btns.append(card)

# Build one fully-populated card button for offer[idx]
func _build_card(pos: Vector2, idx: int, gold: int) -> Button:
	var offer:   Dictionary        = _offers[idx]
	var cls:     UnitBase.UnitClass = offer["class"]
	var elem:    UnitBase.Element   = offer["element"]
	var rolls:   Dictionary        = offer["rolls"]
	var stats_dict: Dictionary     = rolls.get("stats", {})
	var grade:   String            = rolls.get("grade", "B")
	var avg_pct: float             = rolls.get("avg_pct", 0.0)
	var base:    Dictionary        = UnitFactory.CLASS_BASE_STATS.get(cls, {})
	var elem_col := _elem_color(elem)
	var grade_col := _grade_color(grade)

	var btn := Button.new()
	btn.position = pos
	btn.size     = Vector2(CARD_W, CARD_H)
	btn.text     = ""
	# Card stays visually NEUTRAL until its own rank reel actually lands — the
	# rank roll IS what sets the tint now (2026-07-21 user request: the card
	# used to show its final grade's color from the very start, spoiling the
	# roll before the badge even spun). _paint_card_grade repaints this live,
	# every tick of the rank reel, and only settles on the true grade_col when
	# that reel lands.
	_paint_card_grade(btn, NEUTRAL_COL)
	# Picking a card is free — HERO_COST is charged up front when the roll is
	# opened (see main_game._on_spawn_hero_pressed), not per-pick — so there's
	# nothing left to gate on gold here (2026-07-24: this stale check disabled
	# every card once gold dropped below HERO_COST from paying for the roll
	# itself, making the shop look broken/unclickable right after opening it).
	btn.disabled = false
	btn.pressed.connect(_on_choose.bind(idx))
	# Hidden until this card's turn in the left-to-right cascade below — see
	# _run_card_reveal(). Works for any _slot_count (3 default, 4 with the
	# Merchant's Ledger relic): each card just waits idx * CARD_STAGGER.
	btn.visible = false

	# ── Portrait ──────────────────────────────────────────────────────────────
	# No backing box — the model sits directly on the card's grade-tinted
	# background so the area behind it reads as the roll's colour.
	var port_pos := Vector2((CARD_W - PORT_SIZE) / 2.0, 14)
	var portrait := TextureRect.new()
	portrait.position    = port_pos
	portrait.size        = Vector2(PORT_SIZE, PORT_SIZE)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(portrait)

	# ── Grade badge (top-right of portrait) ───────────────────────────────────
	var badge_bg := ColorRect.new()
	badge_bg.position = Vector2(port_pos.x + PORT_SIZE - 38, port_pos.y)
	badge_bg.size     = Vector2(38, 38)
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

	# ── Name ──────────────────────────────────────────────────────────────────
	var y_name := port_pos.y + PORT_SIZE + 8.0
	var name_lbl := _clbl(btn, "", 22, elem_col,
		Vector2(0, y_name), Vector2(CARD_W, 30), true)

	# ── Element · rank · growth, all on ONE line (2026-08-02, user request) ───
	# Element used to own a row of its own above the rank; folding it in buys the
	# vertical space the three-ability block below needs. RichTextLabel because
	# the element keeps its element colour while the rank keeps its grade colour,
	# and each reel fills in its own segment as it lands (see _run_card_reveal).
	# avg_pct is the average GROWTH ROLL MULTIPLIER (1.0 = neutral); shown as a
	# +/- % relative to that baseline so "1.1" reads as "+10%", not "110%".
	var avg_rel: float = (avg_pct - 1.0) * 100.0
	var sub_rt := RichTextLabel.new()
	sub_rt.bbcode_enabled = true
	sub_rt.scroll_active  = false
	sub_rt.fit_content    = true
	sub_rt.position       = Vector2(0, y_name + 32)
	sub_rt.size           = Vector2(CARD_W, 24)
	sub_rt.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_rich_font(sub_rt, UITheme.body_font(13) + 2)
	btn.add_child(sub_rt)

	# Tactical identity belongs beside the name, before the player starts
	# parsing ability prose. Rank already owns the corner badge, so the subtitle
	# is reserved for element and growth rather than repeating the same grade.
	var role_lbl := _clbl(btn, role_name(cls).to_upper(), 12,
		Color(0.72, 0.74, 0.86), Vector2(0, y_name + 60), Vector2(CARD_W, 20), true)
	role_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ── Slot-machine reveal sequencing (2026-07-21) ────────────────────────────
	# Cards resolve strictly left to right: card N stays hidden until card N-1
	# has fully finished all three of its reels (hero identity -> rank+color ->
	# stat growth), each awaited in turn rather than fired in parallel with
	# guessed delays — so the background-color paint truly only happens during
	# the rank reel's own spin, never before it starts.
	var card_delay: float = idx * CARD_STAGGER
	_run_card_reveal(card_delay, btn, portrait, name_lbl, sub_rt,
		badge_lbl, badge_bg, cls, elem, grade, avg_rel)

	# ── Divider ───────────────────────────────────────────────────────────────
	var div_y := y_name + 83.0
	var div := ColorRect.new()
	div.position = Vector2(16, div_y)
	div.size     = Vector2(CARD_W - 32, 1)
	div.color    = Color(0.3, 0.3, 0.5, 0.5)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(div)

	var tmp := UnitFactory.create_unit(cls, elem, true)

	# ── Kit (below the portrait, so the player sees what the hero does before
	# scanning the stat table). Same three-row style as the level-up screen and
	# the unit details panel, driven by AbilityFormulas — the shop used to show
	# only the active + ultimate as curated prose, so the passive was invisible
	# at the one moment the player is choosing between heroes. ────────────────
	var kit_y := div_y + 8.0
	var kit_end: float = _add_ability_rows(btn, tmp, cls, kit_y)
	tmp.free()

	# ── Divider ───────────────────────────────────────────────────────────────
	var div_ult_y := kit_end + 4.0
	var div_ult := ColorRect.new()
	div_ult.position = Vector2(16, div_ult_y)
	div_ult.size     = Vector2(CARD_W - 32, 1)
	div_ult.color    = Color(0.3, 0.3, 0.5, 0.5)
	div_ult.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(div_ult)

	# ── Compact stat footer ───────────────────────────────────────────────────
	# The old eight-row spreadsheet competed with the abilities for attention.
	# Keep the comparison stats available, but compress them into two quiet rows.
	var footer_y := div_ult_y + 10.0
	var stat_specs := [
		["HP", "hp", "hp", false], ["ATK", "atk", "atk", false],
		["MAG", "magic", "magic", false], ["ARM", "res", "res", false],
		["MP", "mana", "mana", false], ["AS", "aspd", "aspd", true],
		["SPD", "move", "move", false], ["RNG", "range", "range", false],
	]
	for s in range(stat_specs.size()):
		var spec: Array = stat_specs[s]
		var flat: float = float((stats_dict.get(spec[1], {}) as Dictionary).get("flat", 0.0))
		var value: float = float(base.get(spec[2], 0.0))
		# Mirror UnitFactory.apply_recruit_rolls exactly, so the card can't
		# promise a different hero than the one you get. That function never
		# applies the move/range rolls (2026-09-27 audit: Bouncer showed RNG 0
		# or -1 while its real range was 1), and it TRUNCATES the int stats.
		if spec[1] not in ["move", "range"]:
			value = value * (1.0 + flat)
		var value_text := "%.2f" % value if bool(spec[3]) else str(maxi(1, int(value)))
		var col: int = s % 4
		var row: int = s / 4
		_clbl(btn, "%s  %s" % [spec[0], value_text], 11,
			Color(0.70, 0.71, 0.80), Vector2(18 + col * 94, footer_y + row * 23),
			Vector2(88, 20), false)

	# Selection is an affordance, not another permanent headline. It appears only
	# when the player commits attention to a card.
	var recruit := _clbl(btn, "RECRUIT", 16, Color(1.0, 0.88, 0.42),
		Vector2(118, CARD_H - 45), Vector2(CARD_W - 236, 28), true)
	var recruit_box := StyleBoxFlat.new()
	recruit_box.bg_color = Color(0.06, 0.06, 0.09, 0.88)
	recruit_box.border_color = Color(1.0, 0.75, 0.22, 0.75)
	recruit_box.set_border_width_all(1)
	recruit_box.corner_radius_top_left = 3
	recruit_box.corner_radius_top_right = 3
	recruit_box.corner_radius_bottom_left = 3
	recruit_box.corner_radius_bottom_right = 3
	recruit.add_theme_stylebox_override("normal", recruit_box)
	recruit.visible = false
	btn.mouse_entered.connect(func(): recruit.visible = true)
	btn.mouse_exited.connect(func(): recruit.visible = false)

	_add_lock_toggle(btn, idx)
	return btn

# ── Hold That (2026-08-03) ────────────────────────────────────────────────────
# A pin in the card's top-right corner. Hidden entirely until the crystal
# upgrade is owned, so shops look unchanged for anyone who hasn't bought it.
# Capacity is the upgrade's level: locking past it releases the oldest lock
# rather than refusing the click, which reads better than a dead button.
func lock_capacity() -> int:
	return Progression.get_bonus("item_lock")

const LOCK_PIN_NAME := "LockPin"

func _add_lock_toggle(card: Button, idx: int) -> void:
	if lock_capacity() <= 0:
		return
	var pin := Button.new()
	# Named so _refresh_lock_visual can find it directly. Scanning the card for
	# "a Button child" would silently retitle any other button added later.
	pin.name = LOCK_PIN_NAME
	pin.size = Vector2(66, 28)
	pin.position = Vector2(CARD_W - 76, 8)
	pin.focus_mode = Control.FOCUS_NONE
	# Plain ASCII on purpose: the project font is LeagueGothic and a padlock
	# emoji would render as tofu.
	pin.pressed.connect(_on_lock_pressed.bind(idx))
	card.add_child(pin)
	_paint_pin(pin, idx)

func _paint_pin(pin: Button, idx: int) -> void:
	var held: bool = _locked.has(idx)
	pin.text = "HELD" if held else "LOCK"
	pin.tooltip_text = "Held — a reroll will keep this hero" if held \
		else "Hold this slot so a reroll keeps it"
	pin.modulate = Color(1, 0.86, 0.4) if held else Color(0.62, 0.62, 0.72)

func _on_lock_pressed(idx: int) -> void:
	if _locked.has(idx):
		_locked.erase(idx)
	else:
		# Oldest hold gives way once we're at capacity — that reads better than
		# a dead button. Dictionary keys iterate in insertion order in Godot,
		# so keys()[0] is the oldest.
		while _locked.size() >= lock_capacity() and not _locked.is_empty():
			var oldest: int = int(_locked.keys()[0])
			_locked.erase(oldest)
			_refresh_lock_visual(oldest)
		_locked[idx] = true
	_refresh_lock_visual(idx)

func _refresh_lock_visual(idx: int) -> void:
	if idx < 0 or idx >= _card_btns.size():
		return
	var card = _card_btns[idx]
	if not is_instance_valid(card):
		return
	var pin := card.get_node_or_null(LOCK_PIN_NAME) as Button
	if pin:
		_paint_pin(pin, idx)

# ── Signal handlers ───────────────────────────────────────────────────────────
func _on_choose(idx: int) -> void:
	var offer: Dictionary = _offers[idx]
	# Hide BEFORE emitting. The handler (main_game._on_hero_chosen) spends the roll
	# with clear_offers(), which deliberately refuses while the picker is visible.
	# Emitting first left the roll alive, so B re-opened the same offers and every
	# pick after the first was free (owner report 2026-09-30).
	visible = false
	hero_chosen.emit(offer["class"], offer["element"], offer["rolls"])

func _on_cancel() -> void:
	cancelled.emit()
	visible = false

# ── Pending-roll persistence (2026-07-24) ──────────────────────────────────────
# Cancel no longer discards the roll you just paid for: the card nodes stay
# alive (just hidden) until you either pick one (clear_offers, below) or a new
# prep phase starts. Cancel → check the field/bag → press Buy Hero again just
# re-shows the SAME offers via reopen(), no second charge and no re-roll.
func has_pending_offer() -> bool:
	return not _offers.is_empty()

func reopen(gold: int) -> void:
	if _offers.is_empty():
		return
	visible = true
	# Gold may have moved (items bought, etc.) since this roll was last shown —
	# only the reroll button's afford-gate needs a refresh; picks are free.
	if _reroll_btn:
		_reroll_btn.disabled = (not _free_mode) and gold < REROLL_COST

# Called once a hero is actually picked (or the roll is otherwise spent) so
# the NEXT Buy Hero press pays for and generates a fresh roll instead of
# re-showing stale offers. Also called on prep-phase start so a roll never
# survives into a new round.
func clear_offers() -> void:
	# NEVER strip the cards out of a picker the player is still looking at.
	# _enter_player_turn() calls this at the start of every prep phase to retire
	# a stale roll; with the run map that could fire while the free Call to Arms
	# picker was open, which emptied the panel mid-decision and soft-locked a
	# first playthrough (no cards, no cancel button in free mode, no way out).
	if visible:
		return
	for old in _card_btns:
		if is_instance_valid(old):
			old.queue_free()
	_card_btns.clear()
	_offers.clear()

# ── Portrait loader ───────────────────────────────────────────────────────────
# Resolves a class's portrait texture — used both for the final card art and
# by the identity-roll animation to build its flicker pool (_build_card).
func _portrait_tex(cls: UnitBase.UnitClass) -> Texture2D:
	# Try AI sprite first — filename = class name lowercased, spaces → underscores.
	var ai_path := "res://assets/using/%s.png" % _class_name(cls).to_lower().replace(" ", "_")
	if ResourceLoader.exists(ai_path):
		var tex := load(ai_path) as Texture2D
		if tex:
			return tex
	# Fall back to LPC sprite sheet (old RPG classes and any hero without AI art yet).
	var folder: String = SPRITE_FOLDERS.get(cls, "warrior")
	var sheet := load("res://assets/sprites/generated/%s/0/single.png" % folder) as Texture2D
	if sheet:
		var atlas := AtlasTexture.new()
		atlas.atlas  = sheet
		atlas.region = IDLE_FRAME
		return atlas
	return null

# ── Helpers ───────────────────────────────────────────────────────────────────
static func role_name(cls: UnitBase.UnitClass) -> String:
	# A few kits are more specific than their synergy trait; the fallback keeps
	# future heroes useful without requiring UI work before they can ship.
	match cls:
		UnitBase.UnitClass.DOC, UnitBase.UnitClass.JUNE, UnitBase.UnitClass.REED, UnitBase.UnitClass.VAIL:
			return "Support"
		UnitBase.UnitClass.PASTOR, UnitBase.UnitClass.STITCH, UnitBase.UnitClass.STATIC:
			return "Disruptor"
		UnitBase.UnitClass.SABLE, UnitBase.UnitClass.EMBER:
			return "Ranged Carry"
		UnitBase.UnitClass.SEAR, UnitBase.UnitClass.RIFT:
			return "Magic Fighter"
		UnitBase.UnitClass.ZOLT, UnitBase.UnitClass.LUMEN, UnitBase.UnitClass.SPORE:
			return "Magic Carry"
	var trait_id: int = int(UnitFactory.TRAIT_CLASS_MAP.get(cls, UnitBase.TraitClass.FIGHTER))
	match trait_id:
		UnitBase.TraitClass.TANK: return "Tank"
		UnitBase.TraitClass.MAGE: return "Mage"
		UnitBase.TraitClass.RANGED: return "Ranged"
		UnitBase.TraitClass.HEALER: return "Support"
		UnitBase.TraitClass.SUMMONER: return "Summoner"
		_: return "Fighter"

func _skill_short_desc(unit: UnitBase) -> String:
	if unit.skill_name == "":
		return ""
	if unit.skill_description != "":
		return unit.skill_description
	# Legacy fallback for old classes without a written description
	var parts: Array[String] = []
	if unit.skill_damage_multiplier > 0:
		parts.append("%.0f%% DMG" % (unit.skill_damage_multiplier * 100))
	if unit.skill_range > 0:
		parts.append("RNG %d" % unit.skill_range)
	if unit.skill_cooldown_max > 0:
		parts.append("every %ds" % unit.skill_cooldown_max)
	if unit.skill_mana_cost > 0:
		parts.append("%d MP" % unit.skill_mana_cost)
	return " · ".join(parts)

func _center_panel() -> void:
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	_panel.position = (vp - _panel.size) / 2.0

func _class_name(cls: UnitBase.UnitClass) -> String:
	match cls:
		UnitBase.UnitClass.WARRIOR:    return "Warrior"
		UnitBase.UnitClass.RANGER:     return "Ranger"
		UnitBase.UnitClass.MONK:       return "Monk"
		UnitBase.UnitClass.THIEF:      return "Thief"
		UnitBase.UnitClass.BLACK_MAGE: return "Black Mage"
		UnitBase.UnitClass.WHITE_MAGE: return "White Mage"
		UnitBase.UnitClass.RED_MAGE:   return "Red Mage"
		UnitBase.UnitClass.BLOODHOUND: return "Bloodhound"
		UnitBase.UnitClass.BOUNCER:    return "Bouncer"
		UnitBase.UnitClass.HEADHUNTER: return "Headhunter"
		UnitBase.UnitClass.SHAUNA:     return "Shauna"
		UnitBase.UnitClass.NEMI:       return "Nemi"
		UnitBase.UnitClass.SHEILDOR:   return "Sheildor"
		UnitBase.UnitClass.LORDEE:     return "Lordee"
		UnitBase.UnitClass.NECRO:      return "Necro"
		UnitBase.UnitClass.DOC:        return "Doc"
		UnitBase.UnitClass.RIOT:       return "Riot"
		UnitBase.UnitClass.PASTOR:     return "Pastor"
		UnitBase.UnitClass.SABLE:      return "Sable"
		UnitBase.UnitClass.RUSH:       return "Rush"
		UnitBase.UnitClass.STITCH:     return "Stitch"
		UnitBase.UnitClass.COAL:       return "Coal"
		UnitBase.UnitClass.JUNE:       return "June"
		UnitBase.UnitClass.CROSS:      return "Cross"
		UnitBase.UnitClass.SEAR:       return "Sear"
		UnitBase.UnitClass.EMBER:      return "Ember"
		UnitBase.UnitClass.RIFT:       return "Rift"
		UnitBase.UnitClass.ZOLT:       return "Zolt"
		UnitBase.UnitClass.LUMEN:      return "Lumen"
		UnitBase.UnitClass.STATIC:     return "Static"
		UnitBase.UnitClass.REED:       return "Reed"
		UnitBase.UnitClass.VAIL:       return "Vail"
		UnitBase.UnitClass.SPORE:      return "Spore"
		_: return "Unknown"

func _elem_name(elem: UnitBase.Element) -> String:
	match elem:
		UnitBase.Element.FIRE:      return "Fire"
		UnitBase.Element.WATER:     return "Water"
		UnitBase.Element.EARTH:     return "Earth"
		UnitBase.Element.AIR:       return "Air"
		UnitBase.Element.LIGHTNING: return "Lightning"
		_:                          return "Normal"

func _elem_color(elem: UnitBase.Element) -> Color:
	match elem:
		UnitBase.Element.FIRE:      return Color(1.0,  0.45, 0.1)
		UnitBase.Element.WATER:     return Color(0.3,  0.7,  1.0)
		UnitBase.Element.EARTH:     return Color(0.75, 0.55, 0.25)
		UnitBase.Element.AIR:       return Color(0.75, 1.0,  1.0)
		UnitBase.Element.LIGHTNING: return Color(1.0,  1.0,  0.25)
		_:                          return Color(0.85, 0.85, 0.92)

# Same grey/dark-green/blue/purple/gold progression as item rarity — matches
# UnitFactory.GRADE_COLORS so every roll's quality reads consistently.
func _grade_color(grade: String) -> Color:
	match grade:
		"S": return Color(1.0,  0.85, 0.0)
		"A": return Color(0.68, 0.35, 0.95)
		"B": return Color(0.30, 0.55, 0.95)
		"C": return Color(0.20, 0.62, 0.28)
		"D": return Color(0.65, 0.65, 0.68)
		_:   return Color(0.60, 0.60, 0.72)

# Repaints a card's normal/hover/pressed background+border to `col` — called
# once with NEUTRAL_COL at build time, then on every tick of the rank reel
# (2026-07-21) so the card's tint genuinely rolls with the rank instead of
# showing the final grade's color from frame one.
func _paint_card_grade(btn: Button, col: Color) -> void:
	UITheme.paint_card(btn, col)

# Runs one card's full reveal: wait for its turn -> become visible -> hero
# identity reel -> rank reel (also repaints the card tint every tick) ->
# stat-growth reel — each fully awaited before the next starts, so cards
# resolve strictly left to right and reels within a card never overlap.
# Fire-and-forget from _build_card (not awaited there).
# ── Ability rows ──────────────────────────────────────────────────────────────
# Mirrors LevelUpScreen's ability panel: slot badge and name share the title
# line, and the resolved numbers are sized up rather than bolded (RichTextLabel
# has no bold cut of the project font, so [b] falls back to a face that reads
# smaller than the body around it).
const ABIL_ROW_H   := 104.0
const ABIL_BADGE_W := 92.0
const ABIL_TITLE_H := 28.0
const ABIL_VALUE_FONT := 20
const ABIL_SLOT_LABELS := ["PASSIVE", "ACTIVE", "ULTIMATE"]
const ABIL_SLOT_COLORS := [
	Color(0.55, 0.78, 0.95),
	Color(0.95, 0.80, 0.42),
	Color(0.85, 0.55, 0.98),
]
const ABIL_VALUE_COL := "eef0ff"

# Returns the y just below the last row. Rows used to be a fixed ABIL_ROW_H
# each, so a three-line description (Bouncer's "Reel In", 2026-09-27 audit)
# ran into the next row's title and got clipped. Each row is now sized to its
# own wrapped text, with ABIL_ROW_H kept as the minimum so short kits look
# exactly as before.
func _add_ability_rows(btn: Button, unit: UnitBase, cls: UnitBase.UnitClass,
		top_y: float) -> float:
	var slots := [AbilityFormulas.PASSIVE, AbilityFormulas.ACTIVE, AbilityFormulas.ULTIMATE]
	var has_registry := AbilityFormulas.has_entry(cls, AbilityFormulas.PASSIVE)
	var ry := top_y
	for i in 3:
		var row_top := ry

		_clbl(btn, ABIL_SLOT_LABELS[i], 10, ABIL_SLOT_COLORS[i],
			Vector2(14, ry), Vector2(ABIL_BADGE_W, ABIL_TITLE_H))

		var r: Dictionary = AbilityFormulas.resolve(unit, slots[i]) if has_registry else {}
		var aname: String = str(r.get("name", ""))
		if aname == "":
			# No registry entry (shouldn't happen for a recruitable hero, but the
			# shop must never render a blank card): fall back to the unit's own
			# names, and leave the passive row empty rather than inventing text.
			aname = unit.skill_name if i == 1 else (unit.ultimate_name if i == 2 else "")
		_clbl(btn, aname if aname != "" else "—", 15, ABIL_SLOT_COLORS[i],
			Vector2(14 + ABIL_BADGE_W, ry), Vector2(CARD_W - 28 - ABIL_BADGE_W, ABIL_TITLE_H))

		var desc := RichTextLabel.new()
		desc.bbcode_enabled = true
		desc.scroll_active  = false
		desc.fit_content    = false
		desc.position       = Vector2(14, ry + ABIL_TITLE_H + 2.0)
		desc.size           = Vector2(CARD_W - 28, ABIL_ROW_H - ABIL_TITLE_H - 6.0)
		desc.mouse_filter   = Control.MOUSE_FILTER_IGNORE
		UITheme.apply_read_rich(desc)
		desc.add_theme_color_override("default_color", Color(0.78, 0.80, 0.90))
		btn.add_child(desc)

		var plain := ""
		if r.is_empty() or (r["terms"] as Array).is_empty():
			desc.text = _skill_short_desc(unit) if i == 1 else ""
			plain = desc.text
		else:
			var body: String = str(r["template"])
			plain = body
			for t in r["terms"]:
				body = body.replace("{%s}" % t["id"],
					"[font_size=%d][color=#%s]%s[/color][/font_size]"
						% [UITheme.FONT_READ + 2, ABIL_VALUE_COL, t["display"]])
				plain = plain.replace("{%s}" % t["id"], str(t["display"]))
			desc.text = body

		# Size this row to its wrapped text. Measured on the plain string with
		# the row's own font; +8% covers the slightly larger value numbers and
		# word-wrap waste at line ends.
		var px: int = UITheme.FONT_READ
		var font: Font = desc.get_theme_font("normal_font")
		var line_h: float = font.get_height(px) + 2.0
		var text_w: float = font.get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x * 1.08
		var lines: int = maxi(1, ceili(text_w / (CARD_W - 28.0)))
		var desc_h: float = lines * line_h + 4.0
		desc.size.y = maxf(desc.size.y, desc_h)
		ry = row_top + maxf(ABIL_ROW_H, ABIL_TITLE_H + 2.0 + desc_h + 6.0)
	return ry

func _run_card_reveal(delay: float, btn: Button, portrait: TextureRect,
		name_lbl: Label, sub_rt: RichTextLabel, badge_lbl: Label, badge_bg: ColorRect,
		cls: UnitBase.UnitClass, elem: UnitBase.Element,
		grade: String, avg_rel: float) -> void:
	var tree := get_tree()
	if not tree:
		return

	# Element, rank and growth share one line, but they land on three different
	# reels — so each paint writes only its own segment into this dict and the
	# whole line is rebuilt. Segments that haven't rolled yet simply aren't shown,
	# which keeps the progressive reveal intact. Dictionary (not local vars)
	# because lambdas capture by value — see CONVENTIONS landmine #5.
	var seg := {"elem": "", "elem_col": Color.WHITE,
				"rank_col": Color.WHITE, "growth": ""}
	var refresh_sub := func() -> void:
		if not is_instance_valid(sub_rt):
			return
		var parts: Array[String] = []
		if seg["elem"] != "":
			parts.append("[color=#%s]%s[/color]"
				% [(seg["elem_col"] as Color).to_html(false), seg["elem"]])
		if seg["growth"] != "":
			parts.append("[color=#%s]%s[/color]"
				% [(seg["rank_col"] as Color).to_html(false), seg["growth"]])
		sub_rt.text = "[center]%s[/center]" % "  ·  ".join(parts)
	if delay > 0.0:
		await tree.create_timer(delay).timeout
	if not is_instance_valid(btn):
		return
	btn.visible = true

	# Reel 1: hero identity — portrait, name and element change TOGETHER each
	# tick (a mismatched portrait/name mid-spin would look like a bug, not a
	# roll), landing on the true class+element.
	# The reel now spins on class only — each ticked class drags its own fixed
	# element along, so mid-spin frames stay legal hero identities.
	var all_classes  := UnitFactory.get_all_classes()
	var identity_pool: Array = []
	for _i in range(8):
		var rc: UnitBase.UnitClass = all_classes[randi() % all_classes.size()]
		identity_pool.append({"cls": rc, "elem": UnitFactory.element_for_class(rc)})
	var paint_identity := func(v: Dictionary) -> void:
		var vcls: UnitBase.UnitClass = v["cls"]
		var velem: UnitBase.Element  = v["elem"]
		var vcol := _elem_color(velem)
		portrait.texture = _portrait_tex(vcls)
		name_lbl.text = _class_name(vcls)
		name_lbl.add_theme_color_override("font_color", vcol)
		seg["elem"] = _elem_name(velem)
		seg["elem_col"] = vcol.lightened(0.25)
		refresh_sub.call()
	var punch_identity := func() -> void: GradeRoll.land_punch(portrait)
	await GradeRoll.spin(btn, identity_pool, {"cls": cls, "elem": elem}, paint_identity,
		0.0, REEL_TICKS, REEL_START, REEL_GROWTH, punch_identity)
	if not is_instance_valid(btn):
		return

	# Landed on the true hero — HeroPortrait takes over entirely from here
	# (idle animation when generated frames exist, its own static fallback
	# otherwise), so hide the old static portrait to avoid double-drawing.
	portrait.visible = false
	var portrait_anim := HeroPortrait.new()
	portrait_anim.position = portrait.position
	portrait_anim.size = portrait.size
	portrait_anim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(portrait_anim)
	portrait_anim.setup(cls)

	# Reel 2: rank badge — also repaints the card + badge background every
	# tick, so the "what color is this card" question rolls WITH the rank
	# instead of being decided (and shown) before the reel even spins.
	var paint_rank := func(g: String) -> void:
		var gcol := _grade_color(g)
		badge_lbl.text = g
		badge_lbl.add_theme_color_override("font_color", gcol)
		badge_bg.color = gcol.darkened(0.4)
		_paint_card_grade(btn, gcol)
		seg["rank_col"] = gcol
		refresh_sub.call()
	var punch_rank := func() -> void: GradeRoll.land_punch(badge_lbl)
	await GradeRoll.spin(btn, GradeRoll.GRADE_SEQUENCE, grade, paint_rank,
		0.0, REEL_TICKS, REEL_START, REEL_GROWTH, punch_rank)
	if not is_instance_valid(btn):
		return

	# Reel 3: stat growth %.
	var growth_pool: Array = []
	for _i in range(8):
		growth_pool.append(randf_range(-60.0, 100.0))
	var paint_growth := func(v: float) -> void:
		var sign := "+" if v >= 0.0 else ""
		seg["growth"] = "growth %s%.1f%%" % [sign, v]
		refresh_sub.call()
	await GradeRoll.spin(sub_rt, growth_pool, avg_rel, paint_growth,
		0.0, REEL_TICKS, REEL_START, REEL_GROWTH)

func _lbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false, enlarge: bool = true) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos; l.size = size
	UITheme.apply_font(l, UITheme.body_font(sz) + (2 if enlarge else 0))
	l.add_theme_color_override("font_color", col)
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

# Child label with MOUSE_FILTER_IGNORE so clicks reach the parent button
func _clbl(parent: Node, text: String, sz: int, col: Color,
		pos: Vector2, size: Vector2, center: bool = false) -> Label:
	var l := _lbl(parent, text, sz, col, pos, size, center)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Small stat icon (see UnitFactory.STAT_ICONS) — silently does nothing if that
# stat doesn't have an icon yet.
func _add_stat_icon(parent: Node, stat_key: String, pos: Vector2, size: float) -> void:
	var path: String = UnitFactory.STAT_ICONS.get(stat_key, "")
	if path == "":
		return
	var tex: Texture2D = load(path) as Texture2D
	if not tex:
		return
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = tex
	icon.position = pos
	icon.size = Vector2(size, size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)

func _btn(text: String, rect: Rect2) -> Button:
	var b := Button.new()
	b.text = text; b.position = rect.position; b.size = rect.size
	UITheme.style_button(b)
	UITheme.apply_font(b, UITheme.body_font(16) + 2)
	return b

func _flat(bg: Color, border: Color = Color.TRANSPARENT,
		bw: int = 0, radius: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.border_width_left = bw; s.border_width_right  = bw
	s.border_width_top  = bw; s.border_width_bottom = bw
	s.corner_radius_top_left     = radius; s.corner_radius_top_right    = radius
	s.corner_radius_bottom_left  = radius; s.corner_radius_bottom_right = radius
	return s
