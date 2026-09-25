extends Node2D
class_name RubberArm
## Bouncer's rubber arm (2026-09-24). Drawn in 2D, not stretched in 3D: it has
## to reach ANY distance (his grab has unlimited range), bend into a travelling
## wave, and the 3D model's viewport can hold none of that. His 3D clips tuck
## the real lead arm away (LeftArm keyed to ~0 scale) for exactly the window
## this is out, so the two never show at once.
##
## Runs on BATTLE time (delta * battle_manager.time_scale, 0 while paused) —
## the same clock as the hit it lands and the clip it pairs with, so the three
## stay locked at any battle speed.
##
## Timeline (seconds after spawn):
##   [0, launch_delay)        invisible (3D wind-up is playing)
##   launch .. +out_time      glove whips out, overshoots the target, settles
##   contact                  impact flash + squash (damage lands on the same beat
##                            in the battle manager)
##   .. +hold_time            holds on the target (a grab drags it here)
##   .. +back_time            snaps back with a decaying wave down the arm
##   end                      glove is back at the shoulder; the 3D arm unfurls

const OUTLINE := Color(0.09, 0.07, 0.12)       # == Model3DSprite.outline_color
const BASE := Color(1.0, 0.565, 0.0)            # his rendered body orange (255,144,0)
const SHADE := Color(0.78, 0.36, 0.02)
const LIGHT := Color(1.0, 0.80, 0.50)
const SEGMENTS := 18

var owner_unit: Node2D = null          # the VisualUnit throwing the arm
var target: Node2D = null
var bone := "LeftArm"
var launch_delay := 0.19
var out_time := 0.07
var hold_time := 0.05
var back_time := 0.16
var overshoot := 0.14                  # reach past the target at the whip's peak
var wave_amp := 0.55                   # lateral wobble, in glove radii
var on_contact: Callable = Callable()  # optional (the grab uses it)

var _t := 0.0
var _unit := 12.0                      # px: body scale reference, set at spawn
var _last_target_pos := Vector2.ZERO
var _contact_fired := false
var _glove := Vector2.ZERO
var _glove_dir := Vector2.RIGHT
var _glove_speed := 0.0
var _impact := 0.0
var _visible_arm := false
var _pts: PackedVector2Array = PackedVector2Array()
var _front: Node2D = null              # glove layer over every unit
var _glove_front := false

## Layering (owner 2026-09-25: the punch "comes out of his chest"). The arm is
## drawn at HIS row z — above his shadow, UNDER his body sprite (Model3DSprite
## sits at +1) — so its root is hidden and it emerges from behind him. The glove
## rides the same layer until it is clear of his body, then moves to this
## overlay so an impact on a target in a nearer row is never hidden.
class _GloveLayer extends Node2D:
	var arm = null
	func _draw() -> void:
		if arm and arm._visible_arm and arm._glove_front:
			arm._draw_glove(self)

func setup(p_owner: Node2D, p_target: Node2D) -> void:
	owner_unit = p_owner
	target = p_target
	top_level = true
	z_as_relative = false
	z_index = int(owner_unit.z_index)
	global_position = Vector2.ZERO
	_front = _GloveLayer.new()
	_front.arm = self
	_front.top_level = true
	_front.z_as_relative = false
	_front.z_index = 20
	add_child(_front)
	var m = owner_unit.get("model3d")
	if m:
		# head_end -> Hips is ~0.85 world units on Bouncer; everything is sized off
		# it so the arm matches the body at any board depth / zoom.
		_unit = maxf((m.bone_canvas_position("head_end") - m.bone_canvas_position("Hips")).length(), 6.0)
	_last_target_pos = _aim_point()

func total_time() -> float:
	return launch_delay + out_time + hold_time + back_time

func contact_time() -> float:
	return launch_delay + out_time

func _clock() -> float:
	var bm = owner_unit.get("battle_manager") if owner_unit else null
	if bm == null:
		return 1.0
	if bm.get("paused"):
		return 0.0
	return float(bm.get("time_scale")) if bm.get("time_scale") != null else 1.0

func _shoulder() -> Vector2:
	var m = owner_unit.get("model3d") if owner_unit and is_instance_valid(owner_unit) else null
	if m:
		# A quarter of the way from the shoulder joint toward the hips: his joint
		# sits right under the big head, and from the board camera an arm leaving
		# the joint itself reads as coming out of his face.
		return m.bone_canvas_position(bone).lerp(m.bone_canvas_position("Hips"), 0.25)
	return owner_unit.global_position if owner_unit and is_instance_valid(owner_unit) else global_position

func _aim_point() -> Vector2:
	if target and is_instance_valid(target):
		var p: Vector2 = target.global_position
		# body centre, not the feet: VisualUnit keeps its foot line and half height
		if target.has_method("ground_offset"):
			p.y += float(target.ground_offset()) - float(target.get("_sprite_half_h")) * 0.9
		_last_target_pos = p
	return _last_target_pos

func _process(delta: float) -> void:
	if not (owner_unit and is_instance_valid(owner_unit)):
		queue_free()
		return
	_t += delta * _clock()
	var t := _t - launch_delay
	if t < 0.0:
		_visible_arm = false
		queue_redraw()
		return
	var s := _shoulder()
	var aim := _aim_point()
	var reach := 0.0
	var wave := 0.0
	var prev := _glove
	if t < out_time:
		var u := t / out_time
		# whip: fast out, past the target, and back onto it
		reach = 1.0 - pow(1.0 - u, 3.0) + overshoot * sin(PI * u)
		wave = 0.35 * (1.0 - u)
	elif t < out_time + hold_time:
		var u := (t - out_time) / hold_time
		reach = 1.0 + overshoot * 0.25 * sin(TAU * u) * (1.0 - u)
		wave = 0.0
	elif t < out_time + hold_time + back_time:
		var u := (t - out_time - hold_time) / back_time
		reach = pow(1.0 - u, 2.2)
		# the snap-back rings: a decaying wave that travels down the arm
		wave = exp(-2.2 * u) * sin(TAU * 2.0 * u)
	else:
		queue_free()
		return
	if not _contact_fired and t >= out_time:
		_contact_fired = true
		_impact = 1.0
		if on_contact.is_valid():
			on_contact.call()
	_impact = maxf(0.0, _impact - delta * _clock() * 6.0)
	_glove = s.lerp(aim, reach)
	var travel := _glove - prev
	if travel.length() > 0.01:
		_glove_dir = travel.normalized()
	_glove_speed = travel.length() / maxf(delta, 0.001)
	_build_points(s, _glove, wave, t)
	_visible_arm = true
	z_index = int(owner_unit.z_index)   # follows his row if he is moved
	_glove_front = _glove.distance_to(s) > _unit * 1.0
	queue_redraw()
	_front.queue_redraw()

func _build_points(s: Vector2, g: Vector2, wave: float, t: float) -> void:
	_pts.resize(SEGMENTS + 1)
	var d := g - s
	var n := Vector2(-d.y, d.x).normalized() if d.length() > 0.5 else Vector2.UP
	var amp := wave * wave_amp * _unit * 0.3 * clampf(d.length() / (_unit * 1.5), 0.3, 2.5)
	# The root is hidden under his body; a straight line to a target up the board
	# left the silhouette through his big head ("comes out of his chest"). A real
	# arm leaves the SIDE of the torso first: a short upper-arm stub straight out
	# to his lead side at shoulder height (grows in as the arm extends), then a
	# rounded elbow (quadratic, continuing the stub's direction) into the reach.
	var side := _lead_side(g, s)
	var grow := clampf(d.length() / (_unit * 1.5), 0.0, 1.0)
	var c := s + Vector2(side * _unit * 0.60, _unit * 0.06) * grow
	var e := c + Vector2(side * _unit * 0.40, 0.0) * grow
	var stub := 4
	for i in SEGMENTS + 1:
		var k := float(i) / SEGMENTS
		var base: Vector2
		if i <= stub:
			base = s.lerp(c, float(i) / stub)
		else:
			var q := float(i - stub) / (SEGMENTS - stub)
			base = c.lerp(e, q).lerp(e.lerp(g, q), q)
		# travelling wave, pinned at the shoulder and the glove
		var lat := amp * sin(TAU * (1.2 * k - 3.0 * t)) * sin(PI * k)
		_pts[i] = base + n * lat

## +1 / -1: which side of his body the punching arm is on, on screen.
func _lead_side(g: Vector2, s: Vector2) -> float:
	var m = owner_unit.get("model3d") if owner_unit and is_instance_valid(owner_unit) else null
	if m:
		var dx: float = m.bone_canvas_position(bone).x - m.bone_canvas_position("Spine01").x
		if absf(dx) > 1.5:
			return signf(dx)
	return 1.0 if g.x >= s.x else -1.0

func _arm_width() -> float:
	# rubber thins as it stretches (area roughly kept), never below a readable line
	var rest := _unit * 0.55
	var length := _glove.distance_to(_pts[0]) if _pts.size() > 0 else rest
	return clampf(_unit * 0.13 * sqrt(rest / maxf(length, rest)), 2.0, _unit * 0.13)

func _draw() -> void:
	if not _visible_arm or _pts.size() < 2:
		return
	var w := _arm_width()
	# arm: outline, fill, one-sided shade, highlight — the toon look of the body
	for layer in 4:
		var col: Color = [OUTLINE, BASE, SHADE, LIGHT][layer]
		var ww: float = [w + 3.0, w, w * 0.45, maxf(1.0, w * 0.28)][layer]
		var off: float = [0.0, 0.0, w * 0.28, -w * 0.22][layer]
		for i in SEGMENTS:
			var a: Vector2 = _pts[i]; var b: Vector2 = _pts[i + 1]
			var dn := (b - a).normalized()
			var nn := Vector2(-dn.y, dn.x) * off
			draw_line(a + nn, b + nn, col, ww)
			draw_circle(a + nn, ww * 0.5, col)
	if not _glove_front:
		_draw_glove(self)

func _draw_glove(ci: CanvasItem) -> void:
	# glove: squash along travel when fast, flatten on impact
	var r := _unit * 0.30
	# capped low: a stronger smear flattens the glove into a disc at game scale
	var speed_k := clampf(_glove_speed / (_unit * 40.0), 0.0, 0.18)
	var along := 1.0 + speed_k - 0.30 * _impact
	var across := 1.0 / along
	ci.draw_set_transform(_glove, _glove_dir.angle(), Vector2(along, across))
	ci.draw_circle(Vector2.ZERO, r + 1.8, OUTLINE)
	ci.draw_circle(Vector2.ZERO, r, BASE)
	ci.draw_circle(Vector2(-r * 0.15, r * 0.25), r * 0.72, SHADE)
	ci.draw_circle(Vector2(-r * 0.05, -r * 0.05), r * 0.70, BASE)
	ci.draw_circle(Vector2(-r * 0.25, -r * 0.35), r * 0.28, LIGHT)
	# thumb nub
	ci.draw_circle(Vector2(-r * 0.35, r * 0.70), r * 0.36 + 1.2, OUTLINE)
	ci.draw_circle(Vector2(-r * 0.35, r * 0.70), r * 0.36, BASE)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# impact: a quick burst of ticks around the glove
	if _impact > 0.0:
		var rr := r * (1.4 + (1.0 - _impact) * 1.4)
		for i in 8:
			var ang := TAU * i / 8.0 + 0.3
			var dirv := Vector2(cos(ang), sin(ang))
			ci.draw_line(_glove + dirv * rr, _glove + dirv * (rr + r * 0.8 * _impact),
				Color(1, 1, 0.85, _impact), 2.0)
