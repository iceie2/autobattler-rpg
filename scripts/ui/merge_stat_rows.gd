extends RefCounted
class_name MergeStatRows

# One animated "icon  number  +gain" row, shared by the hero merge toast
# (MergeResultScreen) and the equipment merge toast (EquipmentMergeScreen) so
# both merges count up identically.
#
# The row starts on the OLD value with the whole gain beside it ("2047" "+12").
# step(t) drives it 0 -> 1: the main value climbs while the gain counts down to
# nothing ("2059"). Whole numbers step as integers; decimals snap to 0.01 so no
# float noise reaches a label. main + remaining gain always equals the final
# value, so a "2059 -> 2059" state cannot occur. A negative total (a passive
# level the player removed) counts the other way and shows in red.
#
# fmt: "int" or "f2". prefix/suffix wrap the number ("Lv " / "%" / "x").

const TEXT_OLD  := Color(0.80, 0.80, 0.90)
const TEXT_GAIN := Color(0.45, 0.95, 0.50)
const TEXT_LOSS := Color(0.95, 0.52, 0.46)

static func format(fmt: String, v: float, prefix: String = "", suffix: String = "") -> String:
	var body: String = ("%.2f" % v) if fmt == "f2" else str(int(round(v)))
	return prefix + body + suffix

static func total_for(fmt: String, a: float, b: float) -> float:
	if fmt == "int":
		return float(int(round(b)) - int(round(a)))
	return snappedf(b - a, 0.01)

# "+12" / "-3" (empty when there is nothing left).
static func gain_text(fmt: String, remaining: float) -> String:
	if is_zero_approx(remaining):
		return ""
	var body: String = ("%.2f" % absf(remaining)) if fmt == "f2" else str(absi(int(round(remaining))))
	return ("+" if remaining > 0.0 else "−") + body

# Builds the row inside `parent`. `icon` may be null. Returns the row record
# every other function here works on.
static func make_row(parent: Container, icon: Texture2D, a: float, b: float, fmt: String,
		prefix: String = "", suffix: String = "", tip: String = "", row_h: float = 32.0,
		icon_px: float = 30.0) -> Dictionary:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, row_h)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var ic := TextureRect.new()
	ic.custom_minimum_size = Vector2(icon_px, icon_px)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.texture = icon
	ic.tooltip_text = tip
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var total := total_for(fmt, a, b)
	var main := _label(row, format(fmt, a, prefix, suffix), UITheme.FONT_VALUE, TEXT_OLD)
	main.custom_minimum_size = Vector2(58, 0)   # fits 4 digits / "0.00"; keeps the number by its icon
	main.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	main.pivot_offset = Vector2(58, 14)
	var gain := _label(row, gain_text(fmt, total), UITheme.FONT_BODY, TEXT_GAIN if total > 0.0 else TEXT_LOSS)
	gain.custom_minimum_size = Vector2(60, 0)
	return {"row": row, "icon": ic, "main": main, "gain": gain, "fmt": fmt, "a": a, "b": b,
		"total": total, "prefix": prefix, "suffix": suffix}

# t: 0 -> 1.
static func step(t: float, row: Dictionary) -> void:
	var main: Label = row["main"]
	var gain: Label = row["gain"]
	if not is_instance_valid(main):
		return
	var fmt: String = row["fmt"]
	var total: float = row["total"]
	var a: float = row["a"]
	var shown: float
	var left: float
	if fmt == "int":
		var s: int = int(round(total * t))
		shown = float(int(round(a)) + s)
		left = float(int(total) - s)
	else:
		var s2: float = snappedf(total * t, 0.01)
		shown = a + s2
		left = total - s2
	main.text = format(fmt, shown, row["prefix"], row["suffix"])
	gain.text = gain_text(fmt, left)

# Lands exactly on the live value, drops the gain, and gives the number a pop.
static func finish(row: Dictionary, owner: Node) -> void:
	var main: Label = row["main"]
	var gain: Label = row["gain"]
	if not is_instance_valid(main):
		return
	main.text = format(row["fmt"], row["b"], row["prefix"], row["suffix"])
	gain.text = ""
	gain.modulate.a = 0.0
	var pop := owner.create_tween()
	pop.tween_property(main, "scale", Vector2(1.15, 1.15), 0.08)
	pop.tween_property(main, "scale", Vector2.ONE, 0.10)

static func begin_color(row: Dictionary) -> void:
	(row["main"] as Label).add_theme_color_override("font_color",
		TEXT_GAIN if float(row["total"]) >= 0.0 else TEXT_LOSS)

static func _label(row: HBoxContainer, text: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.apply_font(l, px)
	l.add_theme_color_override("font_color", col)
	# Dark outline: the rows sit straight on the board (no panel behind them).
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return l
