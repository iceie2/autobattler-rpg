class_name RecapMetricBar
extends Control
# One cumulative bar in the run recap's contribution panel (2026-10-07).
# Colour AND pattern carry the metric, so meaning never rests on colour alone:
#   DAMAGE      red,   diagonal stripes   (sword icon)
#   PROTECTION  blue,  dot grid           (shield icon)
#   HEALING     green, plus marks         (cross)
# fill = value / scale, where scale is that metric's fixed run-wide maximum. A
# zero value draws an empty track - never a fake sliver. The number beside the
# bar is a separate label; the bar never stands alone.

enum Metric { DAMAGE, PROTECTION, HEALING }

var metric: int = Metric.DAMAGE
var value: float = 0.0
var scale_max: float = 1.0
var dim: bool = false                  # a hero not yet joined at this replay point

func _init() -> void:
	custom_minimum_size = Vector2(40, 12)
	mouse_filter = Control.MOUSE_FILTER_PASS

static func fill_color(m: int) -> Color:
	var light := UITheme.is_light()
	match m:
		Metric.DAMAGE:
			return Color(0.70, 0.13, 0.12) if light else Color(0.92, 0.32, 0.28)
		Metric.PROTECTION:
			return Color(0.13, 0.33, 0.72) if light else Color(0.42, 0.64, 1.0)
		_:
			return Color(0.10, 0.48, 0.22) if light else Color(0.38, 0.84, 0.50)

static func pattern_color(m: int) -> Color:
	return fill_color(m).darkened(0.45) if not UITheme.is_light() else fill_color(m).lightened(0.55)

func set_value(v: float) -> void:
	if not is_equal_approx(v, value):
		value = v
		queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var track := Color(0, 0, 0, 0.10) if UITheme.is_light() else Color(0.02, 0.02, 0.03, 0.80)
	draw_rect(r, track)
	var ratio: float = clampf(value / scale_max, 0.0, 1.0) if scale_max > 0.0 else 0.0
	if value > 0.0:
		var w: float = maxf(2.0, r.size.x * ratio)
		var fr := Rect2(0, 0, w, r.size.y)
		var col := fill_color(metric)
		if dim:
			col.a = 0.45
		draw_rect(fr, col)
		draw_pattern(self, metric, fr, pattern_color(metric))
	var edge := Color(0.30, 0.22, 0.10, 0.55) if UITheme.is_light() else Color(0.55, 0.47, 0.30, 0.55)
	draw_rect(r, edge, false, 1.0)

# The metric's pattern inside `fr`, clipped by construction (no _draw clipping
# exists). Static so the legend swatches draw the same thing.
static func draw_pattern(ci: CanvasItem, m: int, fr: Rect2, col: Color) -> void:
	if fr.size.x < 3.0 or fr.size.y < 3.0:
		return
	match m:
		Metric.DAMAGE:
			# 45-degree stripes: x - y = c, clipped to the rect.
			var step := 6.0
			var c := -fr.size.y
			while c < fr.size.x:
				var x0: float = maxf(0.0, c)
				var y0: float = x0 - c
				var x1: float = minf(fr.size.x, c + fr.size.y)
				var y1: float = x1 - c
				if x1 > x0:
					ci.draw_line(fr.position + Vector2(x0, y0), fr.position + Vector2(x1, y1), col, 1.5, true)
				c += step
		Metric.PROTECTION:
			var gx := 5.0
			var y := 3.0
			while y < fr.size.y - 1.0:
				var x := 3.0 + (2.5 if int(y / gx) % 2 == 1 else 0.0)
				while x < fr.size.x - 1.0:
					ci.draw_circle(fr.position + Vector2(x, y), 1.1, col)
					x += gx
				y += gx
		_:
			var s := 7.0
			var arm := minf(2.0, fr.size.y * 0.25)
			var cy: float = fr.size.y * 0.5
			var x2 := 4.0
			while x2 < fr.size.x - 2.0:
				var p := fr.position + Vector2(x2, cy)
				ci.draw_line(p - Vector2(arm, 0), p + Vector2(arm, 0), col, 1.4)
				ci.draw_line(p - Vector2(0, arm), p + Vector2(0, arm), col, 1.4)
				x2 += s
