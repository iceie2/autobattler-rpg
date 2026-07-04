extends Object
class_name UITheme
# ══════════════════════════════════════════════════════════════════════════════
# Central UI theme built on the "Fantasy RPG UI (dobo)" pack (panels/buttons) +
# the Vector UI pack (headers/slots/currency). Swapped panel/button source
# 2026-07-04 after user feedback on the first pass: the original panel texture
# was a two-tone CARD asset (dark header strip + a light cream content field
# meant for card text) misused as a full opaque panel background — that's
# exactly the "black/blue top fades to white/pearl, text doesn't read" issue.
# Modal12 (solid navy gradient, no light band) fixes it.
#
# Textures live in assets/UI/generated/ — pre-scaled copies of the pack
# sources (see the PIL job in session notes) so 9-patch corners render at sane
# on-screen sizes. USE THESE HELPERS for any new panel/button/slot — that's
# what keeps the game looking like one product instead of default Godot.
# ══════════════════════════════════════════════════════════════════════════════

const _P := "res://assets/UI/generated/"

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

# Dark navy modal panel — sidebars, tooltips, popups. (source 139x139, solid
# gradient, no light band — see swap note above)
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

# Buttons: normal/hover/pressed as different pack colorways. Pill-shaped source
# (120x32) — small vertical margin since the rounded caps run the full height.
static func button_boxes() -> Dictionary:
	return {
		"normal":  _tex_box("btn_black.png", 14, 8, 10),
		"hover":   _tex_box("btn_blue.png", 14, 8, 10),
		"pressed": _tex_box("btn_purple.png", 14, 8, 10),
	}

static func style_button(b: Button) -> Button:
	var boxes := button_boxes()
	b.add_theme_stylebox_override("normal", boxes["normal"])
	b.add_theme_stylebox_override("hover", boxes["hover"])
	b.add_theme_stylebox_override("pressed", boxes["pressed"])
	var dis: StyleBoxTexture = _tex_box("btn_black.png", 14, 8, 10)
	dis.modulate_color = Color(0.55, 0.55, 0.6)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_color_override("font_color", Color(0.92, 0.92, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.95, 0.9, 1.0))
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
