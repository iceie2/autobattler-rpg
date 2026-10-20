extends Object
class_name UITheme
# ══════════════════════════════════════════════════════════════════════════════
# Central UI theme, "parchment and gold" — built on the Vector UI pack's warm
# cream/yellow colorway. User feedback across two earlier passes: didn't like
# solid blue/navy anywhere; wanted the classic wood/parchment-and-gold look
# common in mobile RPGs, matching the bold-outline painted style of the game's
# actual monster/hero art (see assets/using/Goblin.png) rather than the pack's
# own candy-bright demo screens.
#
# Filenames in assets/UI/generated/ are HONEST as of 2026-07-04 — panel_cream,
# header_cream, btn_gold, btn_cream_hover, slot_gold, slot_white. Earlier
# passes kept stale names (panel_dark.png, btn_black.png, header_black.png)
# from the original navy theme to avoid touching call sites across three
# texture swaps — that shortcut left filenames actively lying about their
# contents (btn_black.png held a gold button) and confused review of the
# actual art. Renamed once, for good: if you add a new colorway, name the
# file for what's IN it, not what an earlier draft called it.
#
# - panel_cream.png: mail_cream.png (Vector pack) with its off-center diamond
#   watermark cropped out and mirrored into a symmetric clean strip — the
#   original had the watermark fixed near the left edge, which would smear/
#   duplicate when stretched to different panel widths. This tiles safely.
# - header_cream.png / btn_gold.png / btn_cream_hover.png / slot_gold.png /
#   slot_white.png: header_cream.png, buttonAdvanced_yellow.png,
#   buttonAdvanced_cream.png, itemSlotAdvanced_yellow.png,
#   itemSlotAdvanced_white.png from the Vector pack.
# - Pressed button state reuses btn_gold.png darkened via modulate_color
#   rather than a separate file — same source pack asset either way.
# - All text colors are dark-brown-on-cream (see TEXT_* below).
#
# Textures live in assets/UI/generated/. USE THESE HELPERS for any new panel/
# button/slot — that's what keeps the game looking like one product instead
# of default Godot.
# ══════════════════════════════════════════════════════════════════════════════

const _P := "res://assets/UI/generated/"

# Shared menu title art. Titles remain live text so every screen can use the
# same banner and localized/dynamic names remain readable.
const MENU_HEADER_DARK := preload("res://assets/UI/generated/menu_header_dark.jpg")
const MENU_HEADER_LIGHT := preload("res://assets/UI/generated/menu_header_light.jpg")
const SETTINGS_PATH := "user://settings.json"
static var _ui_style_cache := ""

static func ui_style() -> String:
	# Capture harnesses can preview either style without changing player settings.
	for arg in OS.get_cmdline_user_args():
		if arg == "--ui-style=light": return "light"
		if arg == "--ui-style=dark": return "dark"
	if _ui_style_cache != "":
		return _ui_style_cache
	_ui_style_cache = "dark"
	if FileAccess.file_exists(SETTINGS_PATH):
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary and parsed.get("ui_style", "") == "light":
				_ui_style_cache = "light"
	return _ui_style_cache

static func set_ui_style(style: String) -> void:
	_ui_style_cache = "light" if style == "light" else "dark"
	var data: Dictionary = {}
	if FileAccess.file_exists(SETTINGS_PATH):
		var source := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if source:
			var parsed = JSON.parse_string(source.get_as_text())
			if parsed is Dictionary:
				data = parsed
	data["ui_style"] = _ui_style_cache
	var target := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if target:
		target.store_string(JSON.stringify(data))

static func is_light() -> bool:
	return ui_style() == "light"

# ── Reduced motion (2026-10-07, run recap) ────────────────────────────────────
# Long decorative animations (the end-of-run journey) open on their finished
# state instead. Stored beside ui_style in settings.json; --reduced-motion
# previews it without touching player settings, like --ui-style.
static var _reduced_motion_cache: int = -1

static func reduced_motion() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--reduced-motion":
			return true
	if _reduced_motion_cache >= 0:
		return _reduced_motion_cache == 1
	_reduced_motion_cache = 0
	if FileAccess.file_exists(SETTINGS_PATH):
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary and bool(parsed.get("reduced_motion", false)):
				_reduced_motion_cache = 1
	return _reduced_motion_cache == 1

static func set_reduced_motion(on: bool) -> void:
	_reduced_motion_cache = 1 if on else 0
	var data: Dictionary = {}
	if FileAccess.file_exists(SETTINGS_PATH):
		var source := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if source:
			var parsed = JSON.parse_string(source.get_as_text())
			if parsed is Dictionary:
				data = parsed
	data["reduced_motion"] = on
	var target := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if target:
		target.store_string(JSON.stringify(data))

static func menu_title_color() -> Color:
	return Color(0.28, 0.19, 0.10) if is_light() else Color(1.0, 0.89, 0.63)

static func menu_subtitle_color() -> Color:
	return Color(0.34, 0.27, 0.20) if is_light() else Color(0.80, 0.80, 0.85)

static func menu_body_color() -> Color:
	return Color(0.25, 0.21, 0.17) if is_light() else Color(0.94, 0.91, 0.85)

static func menu_header(parent: Control, rect: Rect2) -> TextureRect:
	var banner := TextureRect.new()
	banner.texture = MENU_HEADER_LIGHT if is_light() else MENU_HEADER_DARK
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_SCALE
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(banner)
	banner.custom_minimum_size = Vector2.ZERO
	banner.position = rect.position
	banner.size = rect.size
	return banner

# Neutral body under the illustrated title plate. The older panel texture has
# its own ornamental border, which competes with the new header frame.
static func menu_surface_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.91, 0.87, 0.78) if is_light() else Color(0.105, 0.10, 0.10)
	box.border_color = Color(0.42, 0.34, 0.22) if is_light() else Color(0.31, 0.29, 0.27)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(12)
	return box

# ══ TYPE SCALE (2026-09-16) ═══════════════════════════════════════════════════
# FIVE steps, and only five. Before this pass scenes/main_game.tscn alone
# carried THIRTEEN distinct font sizes (10/11/12/13/14/16/18/20/22/24/26/28/42),
# and the drift was concentrated in exactly the places the player most needs to
# read: the synergy list, the sidebar toggles, the combat log and the bottom
# info strip (the game's ONLY confirmation that a hero was bought, sitting at
# 10-12px).
#
# HEADER IS 22, not 26 — that keeps the pre-existing standing convention
# ("section headers 22 / value text 20") intact and was the smaller diff:
# 4 header sites in the scene move to 22 vs 7 that would have had to move to 26.
#
# NOTHING renders below FONT_BODY except a genuine caption (a column header or
# chip that sits beside the value it labels and is never read on its own).
const FONT_CAPTION := 12   # column heads / chips ONLY — never running text
const FONT_BODY    := 16   # the floor for anything a player actually reads
const FONT_VALUE   := 20   # stat values, list rows, log lines
const FONT_HEADER  := 22   # section headers, panel titles, buttons
const FONT_DISPLAY := 42   # one-per-screen hero text (READY, game over)

const FONT_SCALE: Array[int] = [FONT_CAPTION, FONT_BODY, FONT_VALUE, FONT_HEADER, FONT_DISPLAY]

# Snap an arbitrary pixel size onto the ladder. Ties round UP — when a size sits
# exactly between two steps, the legible one wins. The result is floored at
# FONT_BODY on purpose: captions are opt-in via FONT_CAPTION, never something a
# helper can produce by accident, which is how the 10-13px drift happened.
static func snap(px: int) -> int:
	var best: int = FONT_BODY
	var best_d: int = 1 << 30
	for step in FONT_SCALE:
		if step < FONT_BODY:
			continue
		var d: int = abs(step - px)
		# <= makes the LARGER step win a tie, because FONT_SCALE ascends.
		if d <= best_d:
			best_d = d
			best = step
	return best

# Font size bump (2026-07-04, user request), now scale-aware: these still take
# the "base" size the call site used to pass and still bump it (+10 header /
# +8 body), but the result is snapped onto FONT_SCALE instead of being whatever
# arbitrary number the addition produced. That is what makes a screen land on
# the five steps without every call site having to be rewritten.
# WIRED via each screen's _lbl()/_clbl() label factory (body) and main_game's
# _sb_heading()/_sb_accordion() (header) — labels built through those factories
# get the bump automatically. Route new labels through the factory or they miss
# it entirely (CONVENTIONS.md section 6).
static func header_font(base: int) -> int:
	return snap(base + 10)

static func body_font(base: int) -> int:
	return snap(base + 8)


# ══ BODY TYPEFACE ═════════════════════════════════════════════════════════════
# LeagueGothic (project.godot gui/theme/custom_font) is a CONDENSED DISPLAY
# face. Condensed faces lose their counters — the enclosed white inside a, e,
# s, g — faster than normal-width faces as the glyph shrinks, because the
# narrowing scales with the letter. That is why the small UI text read as a
# grey smear rather than merely small, and it is a property of the face, not
# of the size: collapsing the type scale fixed the symptom, not the cause.
#
# So: LeagueGothic keeps the CHROME (headers, titles, the READY button), and a
# normal-width companion takes the RUNNING TEXT (log lines, toasts, synergy
# rows, stat readouts). SUPERSEDED 2026-09-27: the face is now chosen by role
# via apply_read_font / apply_read_rich (see "Role, not size" below).
# BODY_FACE_MAX_PX survives only for event_panel.gd's own opt-in.
#
# Drop the companion into assets/Fonts/ and point BODY_FACE_PATH at it. Until
# then body_face() returns null and every helper below falls through to
# LeagueGothic, so the game looks exactly as it does today rather than
# erroring on a missing resource.
const BODY_FACE_PATH := "res://assets/Fonts/Inter-Regular.ttf"
const BODY_FACE_MAX_PX := FONT_VALUE

static var _body_face_cache: Variant = null
static var _body_face_tried := false

static func body_face() -> Font:
	if not _body_face_tried:
		_body_face_tried = true
		if ResourceLoader.exists(BODY_FACE_PATH):
			_body_face_cache = load(BODY_FACE_PATH) as Font
	return _body_face_cache as Font

# ── Role, not size (2026-09-27) ───────────────────────────────────────────────
# Inter landed in assets/Fonts/ on 2026-09-27 (owner: "descriptions are a hair
# too small ... in most games it feels so much easier"). Switching by SIZE, as
# this file originally planned, was wrong in practice: it flipped every small
# LABEL (PASSIVE, STATS, sidebar buttons) to the wider face — they collided and
# overflowed — while the actual descriptions, drawn at 24px, stayed condensed.
#
# So the face is chosen by ROLE:
#   apply_font / apply_rich_font  → LeagueGothic: titles, labels, tags,
#                                   buttons, numbers. Everything, by default.
#   apply_read_font / apply_read_rich → Inter: prose the player READS —
#                                   ability/perk/relic descriptions, flavour.
#
# FONT_READ is Inter's own step. It is NOT a sixth LeagueGothic size: Inter's
# open counters and taller x-height read larger at 18 than LeagueGothic at 24,
# and take about the same line width, so it drops into the old 24px slots.
const FONT_READ := 18

static func apply_font(ctrl: Control, px: int) -> Control:
	ctrl.add_theme_font_size_override("font_size", px)
	return ctrl

# RichTextLabel keys its default size off "normal_font_size", not "font_size".
static func apply_rich_font(rt: RichTextLabel, px: int) -> RichTextLabel:
	rt.add_theme_font_size_override("normal_font_size", px)
	return rt

static func apply_read_font(ctrl: Control, px: int = FONT_READ) -> Control:
	ctrl.add_theme_font_size_override("font_size", px)
	var f := body_face()
	if f:
		ctrl.add_theme_font_override("font", f)
	return ctrl

# Godot's built-in hover tooltips (every `tooltip_text` in the game — 54 of
# them) draw with the default theme's TooltipLabel font, i.e. the project
# font LeagueGothic. Tooltips are prose, so point that one theme type at
# Inter. Idempotent; called from main_game and main_menu _ready.
static func install_read_tooltips() -> void:
	var f := body_face()
	if f == null:
		return
	var t := ThemeDB.get_default_theme()
	t.set_font("font", "TooltipLabel", f)
	t.set_font_size("font_size", "TooltipLabel", FONT_BODY)

static func apply_read_rich(rt: RichTextLabel, px: int = FONT_READ) -> RichTextLabel:
	rt.add_theme_font_size_override("normal_font_size", px)
	var f := body_face()
	if f:
		rt.add_theme_font_override("normal_font", f)
	return rt


# Dark-brown text colors for the cream/parchment surfaces.
const TEXT_HEADER := Color(0.42, 0.29, 0.12)   # section header labels (SET BONUSES...)
const TEXT_BODY    := Color(0.54, 0.42, 0.23)  # muted body copy on parchment
const TEXT_BTN     := Color(0.29, 0.18, 0.03)  # button label text (on gold)

# ── Stat bars — ONE look for every HP/MP/XP/ULT bar in the game ───────────────
# (2026-07-05, user request — take two.) The beveled strip textures in
# assets/UI/stat_bar/ are the INTENDED bar art (the in-world unit bars had
# them first); the sidebar's flat StyleBoxFlat bars were the old look. The
# first unification pass got that backwards and flattened everything — this
# routes BOTH through the strips. fill_xp/fill_enemy were hue-shifted from
# fill_hp (same bevel art, gold and red) so all five strips are one family.
const _BAR_TEX := {
	"hp":    preload("res://assets/UI/stat_bar/fill_hp.png"),
	"mp":    preload("res://assets/UI/stat_bar/fill_mp.png"),
	"ult":   preload("res://assets/UI/stat_bar/fill_ult.png"),
	"xp":    preload("res://assets/UI/stat_bar/fill_xp.png"),
	"enemy": preload("res://assets/UI/stat_bar/fill_enemy.png"),
}
# Label/text tint companions (e.g. the HP/MP/XP row labels in Team Status).
const BAR_HP  := Color(0.2, 0.78, 0.3)
const BAR_MP  := Color(0.25, 0.4, 0.9)
const BAR_XP  := Color(0.85, 0.65, 0.1)
# Dark track behind every bar (same as the unit bars always had).
const BAR_TRACK_BG     := Color(0.06, 0.06, 0.08, 0.92)
const BAR_TRACK_BORDER := Color(0.0, 0.0, 0.0, 0.85)

static func stat_bar_fill(kind: String) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = _BAR_TEX[kind]
	# 1px margins keep the bevel's highlight/shadow rows and end pixels crisp
	# while the flat middle stretches to any bar size.
	s.texture_margin_left = 1; s.texture_margin_right = 1
	s.texture_margin_top = 1;  s.texture_margin_bottom = 1
	return s

static func stat_bar_bg() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BAR_TRACK_BG
	s.border_color = BAR_TRACK_BORDER
	s.set_border_width_all(1)
	return s

static func style_stat_bar(bar: ProgressBar, kind: String) -> ProgressBar:
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", stat_bar_fill(kind))
	bar.add_theme_stylebox_override("background", stat_bar_bg())
	return bar

# ── Stylebox factories ────────────────────────────────────────────────────────

static func _tex_box(file: String, mh: int, mv: int, cm: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(_P + file) as Texture2D
	sb.texture_margin_left = mh
	sb.texture_margin_right = mh
	sb.texture_margin_top = mv
	sb.texture_margin_bottom = mv
	sb.content_margin_left = cm
	sb.content_margin_right = cm
	sb.content_margin_top = cm * 0.6
	sb.content_margin_bottom = cm * 0.6
	return sb

# Parchment panel — sidebars, tooltips, popups. Clean corner brackets only,
# no off-center watermark (see cropping note above).
static func panel_box() -> StyleBoxTexture:
	return _tex_box("panel_cream.png", 18, 18, 12)

# Same panel, tinted (e.g. victory=green / defeat=red game-over screens) —
# keeps the pack's border art consistent while still signaling game state.
static func panel_box_tinted(tint: Color) -> StyleBoxTexture:
	var sb := panel_box()
	sb.modulate_color = tint
	return sb

# Section header plate (SET BONUSES / RELICS / BAG ...). Slim: tight content.
static func header_box() -> StyleBoxTexture:
	var sb := _tex_box("header_cream.png", 20, 12, 12)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

# Item/relic/bag slot.
static func slot_box(white: bool = false) -> StyleBoxTexture:
	var sb := _tex_box("slot_white.png" if white else "slot_gold.png", 16, 16, 4)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

# Buttons: normal/hover/pressed. Source is a rounded rect (buttonAdvanced_*,
# ~131x81), not a pill — generous margins to preserve the corner radius.
static func button_boxes() -> Dictionary:
	var pressed := _tex_box("btn_gold.png", 20, 16, 10)
	pressed.modulate_color = Color(0.82, 0.82, 0.82)   # darken on press
	return {
		"normal":  _tex_box("btn_gold.png", 20, 16, 10),
		"hover":   _tex_box("btn_cream_hover.png", 20, 16, 10),
		"pressed": pressed,
	}

static func style_button(b: Button) -> Button:
	var boxes := button_boxes()
	b.add_theme_stylebox_override("normal", boxes["normal"])
	b.add_theme_stylebox_override("hover", boxes["hover"])
	b.add_theme_stylebox_override("pressed", boxes["pressed"])
	var dis: StyleBoxTexture = _tex_box("btn_gold.png", 20, 16, 10)
	dis.modulate_color = Color(0.75, 0.75, 0.75)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_color_override("font_color", TEXT_BTN)
	b.add_theme_color_override("font_hover_color", TEXT_BTN)
	b.add_theme_color_override("font_pressed_color", TEXT_BTN)
	return b

# Secondary/tier-2 button (2026-09 main-menu hierarchy pass) — the same gold
# pill art, just dimmed a touch so it visibly sits a rung below a primary
# style_button() in the same screen (e.g. CLASSES/CRYSTAL SHOP next to a big
# START GAME). Never use this INSTEAD of style_button() for a screen's only
# action button — it's for when both tiers appear together.
static func style_button_secondary(b: Button) -> Button:
	style_button(b)
	for key in ["normal", "hover", "pressed"]:
		var sb: StyleBoxTexture = b.get_theme_stylebox(key) as StyleBoxTexture
		if sb:
			var dim := sb.duplicate() as StyleBoxTexture
			dim.modulate_color = Color(0.82, 0.82, 0.8, 1.0)
			b.add_theme_stylebox_override(key, dim)
	return b

# Plain text-link button (Options/Quit tier) — no plate at all, just dark-brown
# text that reads as a link rather than a button. Caller sets focus_mode /
# a focus stylebox override themselves if it sits in a radio-style group (see
# CONVENTIONS.md section 6).
static func style_text_link(b: Button) -> Button:
	b.flat = true
	b.add_theme_color_override("font_color", TEXT_HEADER)
	b.add_theme_color_override("font_hover_color", Color(0.65, 0.46, 0.14))
	b.add_theme_color_override("font_pressed_color", Color(0.32, 0.20, 0.05))
	return b

# Selection-ring overlay for a card that's the "chosen" one in a picker (e.g.
# relic_screen) — a bright border only, layered OVER an identical background
# to the unselected option so the unselected card never reads as broken/
# unloaded (2026-09 fix: they used to differ in background color instead).
static func selection_ring_box(col: Color = Color(1.0, 0.85, 0.35)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = col
	s.set_border_width_all(4)
	s.set_corner_radius_all(14)
	return s

# ── Picker cards — ONE look for every "choose one" card (2026-09-23) ─────────
# Dark body darkened from an accent colour, accent border, rounded corners. The
# hero shop, level-up perks, relic picker and stat-reward screen each carried a
# private copy of this as _paint_card_grade(); they all route here now so the
# pickers can't drift apart again. `accent` is whatever the card is keyed on —
# a rolled grade for offers, the hero's element for the reward screen's cards.
static func card_box(accent: Color, state: String = "normal") -> StyleBoxFlat:
	var bg: Color = accent.darkened(0.82)
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(12)
	match state:
		"hover":
			s.bg_color = bg.lightened(0.10)
			s.border_color = accent.lightened(0.25)
			s.set_border_width_all(4)
		"pressed":
			s.bg_color = bg.darkened(0.15)
			s.border_color = accent.lightened(0.1)
			s.set_border_width_all(4)
		_:
			s.bg_color = bg
			s.border_color = accent
			s.set_border_width_all(3)
	return s

static func paint_card(btn: Button, accent: Color) -> void:
	btn.add_theme_stylebox_override("normal", card_box(accent))
	btn.add_theme_stylebox_override("hover", card_box(accent, "hover"))
	btn.add_theme_stylebox_override("pressed", card_box(accent, "pressed"))
	btn.add_theme_stylebox_override("disabled", card_box(accent))
	var none := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("focus", none)

# Currency icons (2026-07-05, user's own art — Coins.png/gems.png, copied in
# from assets/using/icons/, source untouched). These are square icons, NOT
# stretchable pill plates — a previous pass tried loading them as 9-slice
# StyleBoxTexture backgrounds (coin_label_box/gem_label_box), which squished
# them because 9-slice stretches everything outside the texture_margin, and
# these icons have no border to protect. Rendered as plain TextureRects
# instead: fixed 50x50, STRETCH_SCALE so the source scales cleanly up or down
# to fit, sitting to the left of the gold/crystal number in an HBoxContainer
# (see main_game.gd _build_right_panel).
const CURRENCY_ICON_SIZE := 50.0

static func currency_icon(kind: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(_P + ("coin_label.png" if kind == "coin" else "gem_label.png")) as Texture2D
	icon.custom_minimum_size = Vector2(CURRENCY_ICON_SIZE, CURRENCY_ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	return icon
