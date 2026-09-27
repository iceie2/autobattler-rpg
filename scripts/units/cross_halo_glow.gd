extends Node2D
class_name CrossHaloGlow
## Soft gold light around Cross's 3D halo (owner 2026-09-25: "his halo needs
## work maybe we layer a glow on it?"). The toon renderer has no bloom, so the
## glow is drawn in 2D, additively, around where the halo lands on screen.
##
## Placement comes from the rig: the halo mesh is weighted to Head and sits just
## above head_end, so its screen centre is head_end pushed a little further along
## Head -> head_end, and its size scales with that same span. That keeps the glow
## locked to the halo through every clip, facing and knock-up.
##
## Brightness breathes slowly at rest, lifts on Absolution (skill) and blazes on
## Judgment (ult), easing between states so a cast doesn't pop.

const GOLD := Color(1.0, 0.84, 0.42)
const WHITE := Color(1.0, 0.97, 0.86)
## halo centre = head_end + (head_end - Head) * CENTRE_PUSH (fitted to v002 at
## pixel scale: 0.14 sat the glow on his forehead, under the ring)
const CENTRE_PUSH := 0.34
## halo radius on screen, as a fraction of the Head -> head_end span
const RADIUS_K := 0.62
const FLATTEN := 0.36          # ring seen from the 28 degree board camera
const LEVEL := {"skill": 1.8, "ult": 2.4}

var unit: Node2D = null
var _t := 0.0
var _level := 1.0

func setup(p_unit: Node2D) -> void:
	unit = p_unit
	z_index = 3                 # over his own sprite (+1), still under the next row
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

func _process(delta: float) -> void:
	if not (unit and is_instance_valid(unit)):
		queue_free()
		return
	_t += delta
	var m = unit.get("model3d")
	var clip: String = str(m.get("_current")) if m else ""
	var want: float = LEVEL.get(clip, 1.0)
	if bool(unit.get("_is_dying")):
		want = 0.0
	_level = lerpf(_level, want, clampf(delta * 6.0, 0.0, 1.0))
	queue_redraw()

func _draw() -> void:
	var m = unit.get("model3d") if unit and is_instance_valid(unit) else null
	if m == null or _level < 0.02:
		return
	var top: Vector2 = m.bone_canvas_position("head_end")
	var base: Vector2 = m.bone_canvas_position("Head")
	var span: Vector2 = top - base
	if span.length() < 1.0:
		return
	var c := to_local(top + span * CENTRE_PUSH)
	var rx := span.length() * RADIUS_K
	var r := Vector2(rx, rx * FLATTEN)
	var breathe := 0.85 + 0.15 * sin(_t * 2.2)
	var k := _level * breathe
	# soft body of light inside the ring
	for i in 4:
		var f := 1.0 - i * 0.22
		_ellipse_fill(c, r * f, Color(GOLD, 0.06 * k))
	# the ring itself: wide faint halo -> narrow bright core
	var w := maxf(2.0, rx * 0.16)
	_ring(c, r, Color(GOLD, 0.07 * k), w * 5.0)
	_ring(c, r, Color(GOLD, 0.15 * k), w * 3.0)
	_ring(c, r, Color(GOLD, 0.26 * k), w * 1.8)
	_ring(c, r, Color(WHITE, 0.40 * k), w * 0.8)
	# a few motes drifting up off it when it's lit by an ability
	if _level > 1.2:
		var a := clampf((_level - 1.2) / 1.0, 0.0, 1.0)
		for i in 6:
			var ph := fposmod(_t * 0.9 + i / 6.0, 1.0)
			var ang := TAU * i / 6.0 + _t * 0.6
			var p := c + Vector2(cos(ang) * r.x, sin(ang) * r.y) - Vector2(0, ph * rx * 1.2)
			draw_circle(p, maxf(1.0, w * 0.5) * (1.0 - ph), Color(WHITE, 0.6 * a * (1.0 - ph)))

func _ellipse_pts(c: Vector2, r: Vector2, n: int = 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts

func _ring(c: Vector2, r: Vector2, col: Color, w: float) -> void:
	draw_polyline(_ellipse_pts(c, r), col, w, true)

func _ellipse_fill(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := _ellipse_pts(c, r, 32)
	pts.remove_at(pts.size() - 1)
	draw_colored_polygon(pts, col)
