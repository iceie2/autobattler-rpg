extends Object
class_name UITheme
# ══════════════════════════════════════════════════════════════════════════════
# Central UI theme, "parchment and gold" (2026-07-04) — built on the Vector UI
# pack's warm cream/yellow colorway instead of the navy modal used in the first
# two passes. User feedback: didn't like solid blue/navy anywhere; wanted the
# classic wood/parchment-and-gold look common in mobile RPGs, matching the
# bold-outline painted style of the game's actual monster/hero art (see
# assets/using/Goblin.png) rather than the pack's own candy-bright demo screens.
#
# - panel_dark.png: mail_cream.png with its off-center diamond watermark
#   CROPPED OUT and mirrored into a symmetric clean strip (assets/UI/generated/
#   _panel_clean_source.png) — the original had the watermark fixed near the
#   left edge, which would smear/duplicate when stretched to different panel
#   widths. This one tiles safely at any size.
# - header_black.png / btn_black.png / btn_blue.png / btn_purple.png / slot_*:
#   swapped to header_cream / buttonAdvanced_yellow / buttonAdvanced_cream
#   (hover) / buttonAdvanced_yellow again (pressed, darkened via modulate) /
#   itemSlotAdvanced_yellow+white. Filenames kept as-is so call sites below
#   don't need to change — only the underlying PNGs and colors did.
# - All text colors flipped from light-on-dark to dark-brown-on-cream.
#
# Textures live in assets/UI/generated/ — pre-scaled copies of the pack
# sources. USE THESE HELPERS for any new panel/button/slot — that's what keeps
# the game looking like one product instead of default Godot.
# ══════════════════════════════════════════════════════════════════════════════

const _P := "res://assets/UI/generated/"

# Font size bump (2026-07-04, user request): headers +4, body text +2 over
# whatever the surrounding code already passes to add_theme_font_size_override.
static func header_font(base: int) -> int:
	return base + 4

static func body_font(base: int) -> int:
	return base + 2

# Dark-brown text colors for the cream/parchment surfaces.
const TEXT_HEADER := Color(0.42, 0.29, 0.12)   # section header labels (SET BONUSES...)
const TEXT_BODY    := Color(0.54, 0.42, 0.23)  # muted body copy on parchment
const TEXT_BTN     := Color(0.29, 0.18, 0.03)  # button label text (on gold)

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

# Parchment panel — sidebars, tooltips, popups. (source 150x148, clean corner
# brackets only, no off-center watermark — see swap note above)
static func panel_box() -> StyleBoxTexture:
	return _tex_box("panel_dark.png", 18, 18, 12)

# Same panel, tinted (e.g. victory=green / defeat=red game-over screens) —
# keeps the pack's border art consistent while still signaling game state.
static func panel_box_tinted(tint: Color) -> StyleBoxTexture:
	var sb := panel_box()
	sb.modulate_color = tint
	return sb

# Section header plate (SET BONUSES / RELICS / BAG ...). Slim: tight content.
static func header_box() -> StyleBoxTexture:
	var sb := _tex_box("header_black.png", 20, 12, 12)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

# Item/relic/bag slot.
static func slot_box(purple: bool = false) -> StyleBoxTexture:
	var sb := _tex_box("slot_purple.png" if purple else "slot_black.png", 16, 16, 4)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

# Buttons: normal/hover/pressed as different pack colorways. Source is now a
# rounded rect (buttonAdvanced_*, ~131x81), not the old pill — bigger margins.
static func button_boxes() -> Dictionary:
	var pressed := _tex_box("btn_purple.png", 20, 16, 10)
	pressed.modulate_color = Color(0.82, 0.82, 0.82)   # darken on press
	return {
		"normal":  _tex_box("btn_black.png", 20, 16, 10),
		"hover":   _tex_box("btn_blue.png", 20, 16, 10),
		"pressed": pressed,
	}

static func style_button(b: Button) -> Button:
	var boxes := button_boxes()
	b.add_theme_stylebox_override("normal", boxes["normal"])
	b.add_theme_stylebox_override("hover", boxes["hover"])
	b.add_theme_stylebox_override("pressed", boxes["pressed"])
	var dis: StyleBoxTexture = _tex_box("btn_black.png", 20, 16, 10)
	dis.modulate_color = Color(0.75, 0.75, 0.75)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_color_override("font_color", TEXT_BTN)
	b.add_theme_color_override("font_hover_color", TEXT_BTN)
	b.add_theme_color_override("font_pressed_color", TEXT_BTN)
	return b

# Currency plates with the coin/gem art baked into the left side of the label.
static func coin_label_box() -> StyleBoxTexture:
	var sb := _tex_box("coin_label.png", 14, 14, 8)
	sb.content_margin_left = 44   # clear the coin art
	return sb

static func gem_label_box() -> StyleBoxTexture:
	var sb := _tex_box("gem_label.png", 14, 14, 8)
	sb.content_margin_left = 44   # clear the gem art
	return sb
