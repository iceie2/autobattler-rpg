extends Node2D
class_name ClovenVFX

# Amber seams join the two fragments; healing is a visible repair, not a
# generic green sparkle. Null recipient is the split's burst of broken stone.
var source = null
var recipient = null
var origin := Vector2.ZERO
var elapsed := 0.0

func setup(caster, target) -> void:
	source = caster
	recipient = target
	origin = caster.global_position
	z_index = 6

func _process(dt: float) -> void:
	elapsed += dt
	if elapsed >= 0.75:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var k: float = clampf(elapsed / 0.75, 0.0, 1.0)
	var amber := Color(1.0, 0.65, 0.22, 1.0 - k)
	if is_instance_valid(recipient) and is_instance_valid(source):
		var a: Vector2 = to_local(source.global_position) + Vector2(0, -35)
		var b: Vector2 = to_local(recipient.global_position) + Vector2(0, -40)
		var points := PackedVector2Array()
		for i in 13:
			var f: float = float(i) / 12.0
			points.append(a.lerp(b, f) + Vector2(0, sin(f * PI * 6.0 + elapsed * 15.0) * 5.0))
		draw_polyline(points, Color(0.16, 0.10, 0.05, 1.0-k), 7.0)
		draw_polyline(points, amber, 3.0)
		draw_circle(a.lerp(b, k), 6.0, Color(1.0, 0.92, 0.65, 1.0-k))
	else:
		var centre := to_local(origin)
		for i in 18:
			var angle: float = float(i) * TAU / 18.0
			var p := centre + Vector2(cos(angle), sin(angle)*0.5) * k * 100.0
			p.y -= sin(k * PI) * 35.0
			draw_rect(Rect2(p-Vector2(4,4), Vector2(8,8)), amber)
