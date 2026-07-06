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

# Font size bump (2026-07-04, user request): headers +4, body text +2 over
# whatever the surrounding code already passes to add_theme_font_size_override.
# WIRED via each screen's _lbl()/_clbl() label factory (body) and main_game's
# _sb_heading()/_sb_accordion() (header) — labels built through those
# factories get the bump automatically. (Found sitting at "+30" on 2026-07-04:
# a test value cranked up to check whether the bump did anything — it didn't,
# because no call site used these helpers until this wiring pass.)
static func header_font(base: int) -> int:
	return base + 10

static func body_font(base: int) -> int:
	return base + 8


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
