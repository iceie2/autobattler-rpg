extends Node2D
class_name MergeVFX

# "Two copies became one stronger hero." (hero merging, 2026-09-28)
#
# Plays over the survivor after main_game._play_merge_effect has drawn the
# consumed copy into it. Three beats, all procedural (no art asset):
#   1. a bright flash + ring that punches outward — the fuse moment,
#   2. rays and sparks rising — "power went up",
#   3. the NEW grade letter popping in the grade's own colour, then drifting up.
# Dark rim under every bright stroke: a gold-only effect vanished into the
# amber board highlights and into gold-armoured heroes (see EvadeVFX notes).

const PULL_TIME := 0.38     # consumed copy's flight into the survivor
const LIFETIME  := 1.35
const RIM := Color(0.06, 0.04, 0.02)
const GOLD := Color(1.0, 0.86, 0.36)

var grade: String = "A"
var label := ""                 # replaces the grade letter, e.g. "+1/2" for a partial merge
var sub_text := "GRADE UP"      # the small line under it
var elapsed := 0.0
var _sparks: Array = []     # [angle, speed, size]
var _font: Font

func _ready() -> void:
	z_index = 60              # above units, damage numbers sit higher still
	# The game's chrome face (LeagueGothic, project gui/theme/custom_font) — the
	# Node2D has no theme to inherit it from.
	var path := str(ProjectSettings.get_setting("gui/theme/custom_font", ""))
	_font = load(path) as Font if path != "" and ResourceLoader.exists(path) else null
	if _font == null:
		_font = ThemeDB.fallback_font
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(14):
		_sparks.append([rng.randf_range(-PI * 0.95, -PI * 0.05),
			rng.randf_range(60.0, 130.0), rng.randf_range(2.0, 4.0)])

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= LIFETIME:
		queue_free()
	else:
		queue_redraw()

func _grade_color() -> Color:
	return UnitFactory.GRADE_COLORS.get(grade, GOLD)

func _draw() -> void:
	var t := elapsed
	var gc := _grade_color()

	# 1 ── flash + expanding ring (first ~0.45s)
	var ft := clampf(t / 0.45, 0.0, 1.0)
	if ft < 1.0:
		var ease_out := 1.0 - pow(1.0 - ft, 3.0)
		var fade := 1.0 - ft
		draw_circle(Vector2.ZERO, 26.0 * (1.0 - ft * 0.6), Color(1.0, 0.97, 0.85, 0.85 * fade))
		var r := 18.0 + 70.0 * ease_out
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(RIM, 0.75 * fade), 9.0 * fade + 2.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(gc, 0.95 * fade), 5.0 * fade + 1.0)

	# 2 ── rising rays + sparks (0.05s – 1.0s)
	var rt := clampf((t - 0.05) / 0.95, 0.0, 1.0)
	if rt > 0.0 and rt < 1.0:
		var fade2 := 1.0 - rt
		for i in range(7):
			var x := (float(i) - 3.0) * 11.0
			var h := (40.0 + 26.0 * sin(float(i) * 1.7)) * (0.4 + rt)
			var a := Vector2(x, 8.0)
			var b := Vector2(x * 1.25, 8.0 - h)
			draw_line(a, b, Color(RIM, 0.55 * fade2), 6.0)
			draw_line(a, b, Color(GOLD, 0.85 * fade2), 2.5)
		for s in _sparks:
			var d: float = float(s[1]) * rt
			var p := Vector2(cos(float(s[0])), sin(float(s[0]))) * d + Vector2(0, -30.0 * rt * rt)
			draw_circle(p, float(s[2]) + 1.5, Color(RIM, 0.6 * fade2))
			draw_circle(p, float(s[2]), Color(gc.lerp(Color.WHITE, 0.35), fade2))

	# 3 ── grade letter pop (0.12s on), overshoot then drift up and fade
	var lt := t - 0.12
	if lt > 0.0:
		var pop := minf(lt / 0.22, 1.0)
		var sc := 0.4 + 0.9 * pop - 0.3 * clampf((lt - 0.22) / 0.2, 0.0, 1.0)
		var alpha := 1.0 - clampf((t - (LIFETIME - 0.35)) / 0.35, 0.0, 1.0)
		var y := -58.0 - 22.0 * clampf(lt / (LIFETIME - 0.12), 0.0, 1.0)
		var txt := label if label != "" else grade
		var fs := int(46.0 * sc)
		if fs > 4:
			var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos := Vector2(-w * 0.5, y)
			draw_string_outline(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(RIM, alpha))
			draw_string(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(gc, alpha))
			var sub := sub_text
			var sfs := 15
			var sw := _font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
			var spos := Vector2(-sw * 0.5, y + 20.0)
			draw_string_outline(_font, spos, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, 5, Color(RIM, alpha))
			draw_string(_font, spos, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color(1, 1, 1, alpha))
