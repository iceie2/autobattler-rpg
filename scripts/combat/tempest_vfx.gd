extends Node2D
class_name TempestVFX

# The Tempest Conduit's visual language: A SERPENT OF CURRENT.
#
# Its body is a coiled black-violet serpent veined with ice-cyan, so its Chain
# Discharge SLITHERS: each link is a smooth S-curve that travels hop by hop,
# ending in a two-fang bite on every hero it strikes. Deliberately NOT the hero
# lightning languages — Static is fast yellow jagged sparks, Zolt a blue/gold
# bolt, the Storm Giant one heavy slate fork. Smooth low-frequency waves + ice
# cyan are this unit's alone.
#
# The chain previously showed a generic LIGHTNING puff on each victim and NO
# arc from the Conduit itself, so the first hero was hit from nowhere and the
# formation lesson (heroes standing close conduct the chain) was invisible.
# Purely presentational: damage still resolves exactly when it did.

const DARK := Color(0.07, 0.05, 0.18)
const ICE := Color(0.55, 0.95, 1.0)
const CORE := Color(0.95, 1.0, 1.0)
const HOP := 0.06            # seconds between one link lighting and the next
const LINK_LIFE := 0.40      # how long each link stays lit

var points: Array = []       # global positions: caster, victim 1, victim 2, ...
var _t := 0.0
var _life := 1.0
var mode := "chain"
var cage := false
var cage_radius := 150.0

func setup_charge(origin: Vector2, target: Vector2, duration: float, is_cage: bool, radius: float = 150.0) -> void:
	cage_radius = radius
	mode = "charge"
	points = [origin, target]
	_life = duration
	cage = is_cage
	z_index = 4

func setup_cage(centre: Vector2, radius: float = 150.0) -> void:
	cage_radius = radius
	mode = "cage"
	points = [centre]
	_life = 0.55
	z_index = 5

func setup_chain(pts: Array) -> void:
	points = pts
	z_index = 5
	_life = HOP * float(maxi(1, pts.size() - 1)) + LINK_LIFE
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	if mode != "chain":
		var k: float = clampf(_t / _life, 0.0, 1.0)
		var centre: Vector2 = to_local(points[-1])
		var radius: float = cage_radius if cage or mode == "cage" else 32.0
		var alpha: float = 1.0 if mode == "charge" else 1.0-k
		draw_circle(centre, radius, Color(0.08, 0.25, 0.4, alpha * 0.18))
		draw_arc(centre, radius, 0, TAU, 64, Color(ICE, alpha), 3.0)
		for i in 8:
			var a: float = i * TAU / 8.0
			var tip := centre + Vector2(cos(a), sin(a)) * radius
			if mode == "cage":
				draw_polyline(PackedVector2Array([tip+Vector2(-8,-160),tip+Vector2(12,-90),tip+Vector2(-5,-45),tip]), Color(CORE, alpha), 4.0)
			else:
				draw_line(tip, centre + (tip-centre) * (0.85-0.45*k), ICE, 2.0)
		if mode == "charge":
			var origin: Vector2 = to_local(points[0]) + Vector2(0,-35)
			draw_arc(origin, 24+12*k, -PI/2, -PI/2+TAU*k, 40, ICE, 4.0)
		return
	for i in range(points.size() - 1):
		var age: float = _t - HOP * float(i)
		if age < 0.0 or age > LINK_LIFE:
			continue
		var k: float = age / LINK_LIFE                  # 0 → 1 over the link's life
		var jump_scale: float = pow(0.78, float(i))     # thinner each jump (falloff)
		var a: float = 1.0 - k * k
		var from: Vector2 = to_local(points[i]) + Vector2(0, -26)
		var to: Vector2 = to_local(points[i + 1]) + Vector2(0, -26)
		# The head of the serpent races along the link in its first 30%.
		var reach: float = minf(1.0, age / (LINK_LIFE * 0.3))
		_serpent(from, to, reach, jump_scale, a, float(i))
		if reach >= 1.0:
			_bite(to, jump_scale, k)

# A smooth S-curve from `from` toward `to`, drawn up to `reach` of its length.
# Amplitude tapers to zero at both ends so it plugs cleanly into the bodies.
func _serpent(from: Vector2, to: Vector2, reach: float, s: float, a: float, seed: float) -> void:
	var d: Vector2 = to - from
	var n: Vector2 = d.orthogonal().normalized()
	var amp: float = clampf(d.length() * 0.12, 8.0, 22.0) * s
	var pts := PackedVector2Array()
	var steps := 24
	for j in range(steps + 1):
		var f: float = float(j) / float(steps) * reach
		var wave: float = sin(f * TAU * 1.5 + _t * 18.0 + seed) * sin(f * PI)
		pts.append(from + d * f + n * wave * amp)
	draw_polyline(pts, Color(DARK.r, DARK.g, DARK.b, 0.85 * a), 13.0 * s)
	draw_polyline(pts, Color(ICE.r, ICE.g, ICE.b, a), 7.5 * s)
	draw_polyline(pts, Color(CORE.r, CORE.g, CORE.b, a), 2.8 * s)

# Two fangs snapping shut on the victim, plus a short cyan flare.
func _bite(c: Vector2, s: float, k: float) -> void:
	var a: float = 1.0 - k * k
	var close: float = minf(1.0, k * 4.0)
	var r: float = 26.0 * s
	draw_circle(c, r * (0.6 + 0.8 * k), Color(ICE.r, ICE.g, ICE.b, 0.30 * a))
	draw_arc(c, r * (0.5 + 1.1 * k), 0, TAU, 24, Color(CORE.r, CORE.g, CORE.b, 0.8 * (1.0 - k)), 3.0 * s)
	for side in [-1.0, 1.0]:
		var tip := c + Vector2(side * r * (1.0 - close) * 0.8, side * r * 0.2)
		var base_a := c + Vector2(side * r * 0.9, -side * r * 0.9)
		var base_b := c + Vector2(side * r * 1.2, -side * r * 0.3)
		draw_colored_polygon(PackedVector2Array([base_a, base_b, tip]), Color(DARK.r, DARK.g, DARK.b, 0.9 * a))
		draw_colored_polygon(PackedVector2Array([base_a.lerp(tip, 0.15), base_b.lerp(tip, 0.15), tip]),
			Color(CORE.r, CORE.g, CORE.b, a))
