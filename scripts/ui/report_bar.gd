class_name ReportBar
extends Control
# A labelled-by-its-row compact bar for the defeat report. Two modes:
#   VALUE    - fill = value / max_value (clamped), against a track.
#   LIFELINE - `intervals` ([[start,end],...] in seconds) painted over a
#              0..span track, so "time alive" shows WHEN, not just how long.
# The bar itself never carries meaning alone: the row beside it always prints
# the number, and a zero value draws an empty track (never a fake sliver).

enum Mode { VALUE, LIFELINE }

var mode: int = Mode.VALUE
var value: float = 0.0
var max_value: float = 1.0
var fill: Color = Color(0.9, 0.6, 0.2)
var intervals: Array = []
var span: float = 1.0
var death_times: Array = []          # drawn as notches on a LIFELINE
var revive_times: Array = []

func _init() -> void:
	custom_minimum_size = Vector2(60, 14)
	mouse_filter = Control.MOUSE_FILTER_PASS   # keeps the row tooltip reachable

func _track_color() -> Color:
	return Color(0.0, 0.0, 0.0, 0.10) if UITheme.is_light() else Color(0.02, 0.02, 0.03, 0.85)

func _edge_color() -> Color:
	return Color(0.30, 0.22, 0.10, 0.55) if UITheme.is_light() else Color(0.55, 0.47, 0.30, 0.55)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, _track_color())
	if mode == Mode.LIFELINE:
		_draw_lifeline(r)
	else:
		var ratio: float = clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0
		if value > 0.0:
			# A real but tiny value still gets 2px so it is visibly non-zero.
			var w: float = maxf(2.0, r.size.x * ratio)
			draw_rect(Rect2(0, 0, w, r.size.y), fill)
			# Hatch the top edge so the bar reads as filled even in greyscale.
			draw_rect(Rect2(0, 0, w, 2), fill.lightened(0.35))
	draw_rect(r, _edge_color(), false, 1.0)

func _draw_lifeline(r: Rect2) -> void:
	if span <= 0.0:
		return
	for pair in intervals:
		var x0: float = r.size.x * clampf(float(pair[0]) / span, 0.0, 1.0)
		var x1: float = r.size.x * clampf(float(pair[1]) / span, 0.0, 1.0)
		if x1 - x0 < 1.5:
			x1 = x0 + 1.5
		draw_rect(Rect2(x0, 0, x1 - x0, r.size.y), fill)
		draw_rect(Rect2(x0, 0, x1 - x0, 2), fill.lightened(0.35))
	var dead := Color(0.86, 0.22, 0.22) if not UITheme.is_light() else Color(0.62, 0.10, 0.10)
	for t in death_times:
		var x: float = r.size.x * clampf(float(t) / span, 0.0, 1.0)
		draw_rect(Rect2(clampf(x - 1.5, 0.0, r.size.x - 3.0), 0, 3, r.size.y), dead)
	for t in revive_times:
		var x: float = r.size.x * clampf(float(t) / span, 0.0, 1.0)
		var up := Color(0.95, 0.85, 0.40)
		draw_rect(Rect2(clampf(x - 1.0, 0.0, r.size.x - 2.0), 0, 2, r.size.y), up)
