class_name RecapHeroDetail
extends PanelContainer
# ══════════════════════════════════════════════════════════════════════════════
# One hero's damage, broken down (2026-10-07, owner: "click any of the bars ...
# a breakdown of all its damage. auto/skill/ult attack/magic/true"). Opened from
# the run recap's hero chart, cumulative to the replay point.
#
# Rows are SOURCES, columns TYPES (RecapFightTap): every number is HP removed
# from enemies, the same definition as the chart's Damage bar, so the rows sum to
# that bar. What cannot be split is shown as such, never spread over the rows:
#   * "Other" - damage the recorder could not tie to an auto / skill / ult /
#     status / summon / passive
#   * fights recorded before the breakdown existed ("not broken down")
# ══════════════════════════════════════════════════════════════════════════════

signal closed

# Indexed by RecapFightTap source; ROW_ORDER is how they are listed.
const SOURCE_NAMES := ["Auto attacks", "Skill", "Ultimate", "Status damage", "Summons", "Other", "Passive"]
const SOURCE_TIPS := [
	"Basic attacks, including their projectiles and the item effects that trigger on a basic hit.",
	"This hero's active skill: hits inside its cast, the projectiles, channels and delayed strikes it sets off, and Spell Echo copies.",
	"This hero's ultimate: hits inside its cast and the projectiles, channels and delayed strikes it sets off.",
	"Damage over time this hero applied: burn, bleed and poison ticks, and spore bursts.",
	"Damage dealt by this hero's summons.",
	"Damage the recorder could not tie to one of the rows above.",
	"This hero's passive ability: on-hit effects of its attacks, its passive's own ticks, and reactive effects such as reflects and redirects.",
]
const ROW_ORDER := [RecapFightTap.SRC_AUTO, RecapFightTap.SRC_SKILL, RecapFightTap.SRC_ULT,
	RecapFightTap.SRC_PASSIVE, RecapFightTap.SRC_DOT, RecapFightTap.SRC_SUMMON, RecapFightTap.SRC_OTHER]
const TYPE_NAMES := ["Physical", "Magic", "True"]

static func type_color(t: int) -> Color:
	var light := UITheme.is_light()
	match t:
		0: return Color(0.72, 0.38, 0.08) if light else Color(0.95, 0.62, 0.28)
		1: return Color(0.42, 0.26, 0.78) if light else Color(0.70, 0.55, 1.0)
		_: return Color(0.45, 0.40, 0.25) if light else Color(0.95, 0.92, 0.78)

var _close_btn: Button

func setup(recap: RunRecap, hero: Dictionary, point: int, state_text: String, available: Vector2) -> void:
	var uid: int = int(hero["uid"])
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.97, 0.94, 0.87) if UITheme.is_light() else Color(0.09, 0.085, 0.08)
	box.border_color = DefeatReportView.gold()
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(16)
	add_theme_stylebox_override("panel", box)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	var upto_round: int = int(recap.fights[point]["round"]) if point >= 0 and point < recap.fights.size() else 0
	var totals: Array = [0, 0, 0]
	if point >= 0:
		var pt: Dictionary = recap.prefix_totals()[point]
		totals = pt.get(uid, [0, 0, 0])

	# Header: portrait, name, state, close.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var path: String = String(VisualUnit.HERO_SPRITE_PATHS.get(int(hero["cls"]), ""))
	var tex: Texture2D = DefeatReportView._enemy_texture(path) if path != "" else null
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(56, 56)
		head.add_child(tr)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(_lbl(String(hero["name"]), UITheme.FONT_HEADER + 6, DefeatReportView.gold()))
	hv.add_child(_lbl("%s  ·  whole run%s" % [state_text, (", up to Wave %d" % upto_round) if upto_round > 0 else ""],
		UITheme.FONT_BODY, DefeatReportView.muted()))
	_close_btn = Button.new()
	_close_btn.text = "✕  Close"
	UITheme.style_button_secondary(_close_btn)
	UITheme.apply_font(_close_btn, UITheme.FONT_VALUE)
	_close_btn.custom_minimum_size = Vector2(120, 44)
	_close_btn.add_theme_stylebox_override("focus", UITheme.selection_ring_box(DefeatReportView.gold()))
	_close_btn.pressed.connect(func(): closed.emit())
	head.add_child(_close_btn)

	# Damage headline + the three other totals for context.
	var dmg: int = int(totals[0])
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 18)
	v.add_child(line)
	line.add_child(_lbl("DAMAGE  %s" % DefeatReportView.fmt_n(dmg), UITheme.FONT_HEADER, DefeatReportView.ink()))
	line.add_child(_lbl("Protection %s  ·  Healing %s" % [DefeatReportView.fmt_n(int(totals[1])),
		DefeatReportView.fmt_n(int(totals[2]))], UITheme.FONT_VALUE, DefeatReportView.muted()))

	var split: Dictionary = recap.damage_split(uid, point)
	var cells: Array = split["cells"]
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for hdr in ["Source"] + TYPE_NAMES + ["Total", "By type"]:
		var hl := _lbl(hdr, UITheme.FONT_BODY, DefeatReportView.muted())
		if hdr in TYPE_NAMES:
			hl.add_theme_color_override("font_color", type_color(TYPE_NAMES.find(hdr)))
		grid.add_child(hl)
	var col_tot: Array = [0, 0, 0]
	var covered := 0
	for src in ROW_ORDER:
		var row_total := 0
		var parts: Array = []
		for t in range(RecapFightTap.TYPES):
			var c: int = int(cells[src * RecapFightTap.TYPES + t])
			parts.append(c)
			row_total += c
			col_tot[t] += c
		covered += row_total
		var src_name: String = SOURCE_NAMES[src]
		if src == RecapFightTap.SRC_SKILL and String(hero.get("skill", "")) != "":
			src_name = "Skill: %s" % hero["skill"]
		elif src == RecapFightTap.SRC_ULT and String(hero.get("ult", "")) != "":
			src_name = "Ultimate: %s" % hero["ult"]
		elif src == RecapFightTap.SRC_PASSIVE and String(hero.get("passive", "")) != "":
			src_name = "Passive: %s" % hero["passive"]
		var dim: bool = row_total == 0
		var nl := _lbl(src_name, UITheme.FONT_VALUE, Color(DefeatReportView.ink(), 0.45 if dim else 1.0))
		nl.tooltip_text = SOURCE_TIPS[src]
		nl.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(nl)
		for t in range(3):
			grid.add_child(_num(int(parts[t]), dim))
		grid.add_child(_num(row_total, dim, true))
		grid.add_child(_TypeBar.new(parts, maxi(1, dmg)))
	grid.add_child(_lbl("All sources", UITheme.FONT_VALUE, DefeatReportView.gold()))
	for t in range(3):
		grid.add_child(_num(int(col_tot[t]), false, true))
	grid.add_child(_num(covered, false, true))
	grid.add_child(_TypeBar.new(col_tot, maxi(1, dmg)))

	var notes: Array = []
	var unsplit: int = int(split["unsplit"])
	if unsplit > 0:
		var rounds: Array = split["unsplit_rounds"]
		var lo: int = int(rounds[0])
		var hi: int = int(rounds[rounds.size() - 1])
		notes.append("%s damage from %s was recorded before this breakdown existed: it is in the DAMAGE total above but not in these rows." % [
			DefeatReportView.fmt_n(unsplit), ("Wave %d" % lo) if lo == hi else ("Waves %d-%d" % [lo, hi])])
	var gap: int = dmg - covered - unsplit
	if gap != 0:
		notes.append("%s damage could not be matched to a source (recorder mismatch)." % DefeatReportView.fmt_n(gap))
	if int(split["enemy_shields"]) > 0:
		notes.append("Another %s went into enemy shields; that is not counted as damage." % DefeatReportView.fmt_n(int(split["enemy_shields"])))
	notes.append("Every number is HP removed from enemies - overkill and enemy-shield soak excluded%s. Hover a source for what it covers." % (
		"" if unsplit > 0 else " - so the rows add up to the Damage bar"))
	for n in notes:
		var l := _lbl(n, UITheme.FONT_BODY, DefeatReportView.muted(), true)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(320, 0)
		v.add_child(l)
	var w: float = minf(980.0, available.x - 40.0)
	custom_minimum_size = Vector2(w, 0)

func focus_close() -> void:
	if _close_btn:
		_close_btn.grab_focus()

func _lbl(text: String, px: int, col: Color, read: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if read:
		UITheme.apply_read_font(l, px)
	else:
		UITheme.apply_font(l, px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _num(v: int, dim: bool, strong: bool = false) -> Label:
	var l := _lbl(DefeatReportView.fmt_n(v) if v > 0 else "-", UITheme.FONT_VALUE,
		Color(DefeatReportView.ink(), 0.45 if dim else 1.0) if not strong else DefeatReportView.ink())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(84, 0)
	return l

# A row's type mix as one bar (its length = share of the hero's damage). The
# numbers beside it carry the meaning; colour only reinforces it.
class _TypeBar extends Control:
	var parts: Array
	var total: int
	func _init(p: Array, t: int) -> void:
		parts = p.duplicate()
		total = t
		custom_minimum_size = Vector2(180, 14)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.10) if UITheme.is_light() else Color(0.02, 0.02, 0.03, 0.8))
		var x := 0.0
		for t in range(3):
			var w: float = size.x * float(parts[t]) / float(maxi(1, total))
			if w > 0.0:
				draw_rect(Rect2(x, 0, maxf(1.0, w), size.y), RecapHeroDetail.type_color(t))
				x += w
		draw_rect(r, Color(0, 0, 0, 0.4), false, 1.0)
