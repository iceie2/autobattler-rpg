extends Node2D
class_name StitchThreadVFX

## Persistent board-space thread for Stitch's Link. Endpoints are live unit
## nodes, so the strand follows movement. rupture() turns the strand into a
## brief layered snap/impact instead of silently deleting the mechanic.

var endpoint_a: Node2D
var endpoint_b: Node2D
var elapsed := 0.0
var rupturing := false
var rupture_elapsed := 0.0
var rupture_duration := 0.22
var seed_phase := 0.0

func setup(a: Node2D, b: Node2D) -> void:
	endpoint_a = a
	endpoint_b = b
	seed_phase = randf() * TAU
	z_index = 18
	queue_redraw()

func rupture() -> void:
	if rupturing:
		return
	rupturing = true
	rupture_elapsed = 0.0
	z_index = 40

func _process(delta: float) -> void:
	elapsed += delta
	if not (endpoint_a and is_instance_valid(endpoint_a) and endpoint_b and is_instance_valid(endpoint_b)):
		queue_free()
		return
	global_position = endpoint_a.global_position
	if rupturing:
		rupture_elapsed += delta
		if rupture_elapsed >= rupture_duration:
			queue_free()
			return
	queue_redraw()

func _draw() -> void:
	if not (endpoint_a and is_instance_valid(endpoint_a) and endpoint_b and is_instance_valid(endpoint_b)):
		return
	var to := endpoint_b.global_position - endpoint_a.global_position
	var length := to.length()
	if length < 1.0:
		return
	var dir := to / length
	var perp := dir.orthogonal()
	var points := PackedVector2Array()
	var segments := maxi(10, int(length / 18.0))
	var snap_t := clampf(rupture_elapsed / rupture_duration, 0.0, 1.0) if rupturing else 0.0
	for i in range(segments + 1):
		var f := float(i) / float(segments)
		var wave := sin(f * PI * 7.0 + elapsed * 8.0 + seed_phase) * (3.0 + sin(elapsed * 4.0) * 1.2)
		if rupturing:
			wave *= 1.0 + snap_t * 4.0
		points.append(to * f + perp * wave * sin(f * PI))
	var fade := 1.0 - snap_t
	# Broad violet bloom, dark cord, hot core: readable on both grass and units.
	draw_polyline(points, Color(0.55, 0.08, 0.85, 0.22 * fade), 13.0 + snap_t * 12.0, true)
	draw_polyline(points, Color(0.12, 0.01, 0.20, 0.95 * fade), 6.0, true)
	draw_polyline(points, Color(0.95, 0.35, 1.0, 0.95 * fade), 2.4, true)
	# Traveling stitch knots make the connection read as sewn thread.
	for i in range(8):
		var f := fmod(elapsed * 0.9 + float(i) / 8.0, 1.0)
		var p := to * f + perp * sin(f * PI * 7.0 + elapsed * 8.0 + seed_phase) * 3.0 * sin(f * PI)
		draw_line(p - perp * 5.0, p + perp * 5.0, Color(1.0, 0.78, 1.0, 0.85 * fade), 2.0)
	if rupturing:
		var mid := to * 0.5
		var burst := 10.0 + 55.0 * sin(snap_t * PI)
		draw_circle(mid, burst, Color(0.75, 0.08, 1.0, 0.30 * fade))
		draw_arc(mid, burst * 1.25, 0.0, TAU, 28, Color(1.0, 0.7, 1.0, fade), 4.0)
		for i in range(12):
			var angle := seed_phase + float(i) * TAU / 12.0
			var ray := Vector2.from_angle(angle)
			draw_line(mid + ray * 8.0, mid + ray * burst * 1.7,
				Color(0.95, 0.3, 1.0, fade), 3.0 * fade)
