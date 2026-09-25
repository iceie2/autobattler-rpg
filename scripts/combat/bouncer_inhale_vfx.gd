extends Node2D
class_name BouncerInhaleVFX
## Bouncer's Gravity Drop, "The Big Inhale" (2026-09-24). Physical, not magic —
## owner: "he doesnt use magic like a zolt or nemi would". Air, dust and dirt only.
##
## v2 (owner: "needs to be turned up a good bit ... not the same quality as
## nemi's"). Nemi's Tidal Wave is the bar: FILLED masses in 3-4 tones, soft
## glows, motion that never stops, a footprint you can read from across the
## board. v1 was thin lines and a 0.3 s puff. Now two layers:
##
##   ground (z 1: over the grass, under every unit — see JuneVFX.GROUND_Z)
##     inhale   filled suction disc, ripple rings flowing INWARD, dust dragged
##              along the ground toward him, dust billows behind pulled enemies
##     exhale   crater + cracks, a thick layered shockwave band
##   air (z 20: over every unit)
##     inhale   tapered 3-tone wind ribbons spiralling into his belly and
##              speeding up, pebbles/grass torn up and sucked in, a compressed
##              air ball growing at the belly, speed lines on dragged enemies
##     exhale   white flash, a rolling ring of shaded dust clouds that lingers,
##              debris thrown out on gravity arcs, radial speed lines
##
## Runs on BATTLE time like RubberArm (delta * time_scale, 0 while paused), so it
## stays on the same beats as the pull and the damage in AutoBattleManager.
## end_time is visual only: the dust settles after his action lock has ended.

const OUTLINE := Color(0.09, 0.07, 0.12)
const AIR_DEEP := Color(0.42, 0.68, 0.86)
const AIR_MID := Color(0.74, 0.91, 1.0)
const AIR_HI := Color(1.0, 1.0, 1.0)
const DUST_SH := Color(0.55, 0.44, 0.32)
const DUST := Color(0.84, 0.73, 0.55)
const DUST_HI := Color(0.97, 0.92, 0.78)
const SOIL := Color(0.30, 0.22, 0.15)
const GRASS := Color(0.45, 0.63, 0.27)
const GROUND_Z := 1
const AIR_Z := 20
const RIBBONS := 10
const DEBRIS_IN := 18
const PUFFS := 40
const CHUNKS := 14
const CRACKS := 7

var caster: Node2D = null
var radius := Vector2(400, 250)        # canvas px: x = horizontal, y = foreshortened
var pull_start := 0.18
var pull_end := 0.60
var impact := 0.66
var end_time := 1.9
var pulled: Array = []                 # Node2D units being dragged in

var _t := 0.0
var _rib: Array = []                   # Vector3(angle, phase, speed mult)
var _deb: Array = []                   # [angle, r0 frac, delay, size, kind]
var _puff: Array = []                  # [angle, dist mult, size mult, rise mult]
var _chunk: Array = []                 # [angle, speed, up, size]
var _crack: Array = []                 # PackedVector2Array in unit-radius space
var _ground: Node2D = null

class _GroundLayer extends Node2D:
	var fx = null
	func _draw() -> void:
		if fx: fx._draw_ground(self)

func setup(p_caster: Node2D, p_radius: Vector2, p_pulled: Array) -> void:
	caster = p_caster
	radius = p_radius
	pulled = p_pulled
	top_level = true
	z_as_relative = false
	z_index = AIR_Z
	global_position = Vector2.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in RIBBONS:
		_rib.append(Vector3(TAU * (i + rng.randf() * 0.6) / RIBBONS, rng.randf(), 0.8 + rng.randf() * 0.5))
	for i in DEBRIS_IN:
		_deb.append([rng.randf() * TAU, 0.55 + rng.randf() * 0.5, rng.randf() * 0.16,
			2.5 + rng.randf() * 2.5, rng.randi() % 3])
	for i in PUFFS:
		_puff.append([TAU * (i + rng.randf() * 0.5) / PUFFS, 0.85 + rng.randf() * 0.3,
			0.8 + rng.randf() * 0.5, 0.6 + rng.randf() * 0.8])
	for i in CHUNKS:
		_chunk.append([rng.randf() * TAU, 0.9 + rng.randf() * 0.8, 0.7 + rng.randf() * 0.6,
			2.5 + rng.randf() * 2.5])
	for i in CRACKS:
		var a := TAU * (i + rng.randf() * 0.5) / CRACKS
		var pts := PackedVector2Array([Vector2.ZERO])
		var p := Vector2.ZERO
		for j in 4:
			var aj := a + rng.randf_range(-0.45, 0.45)
			p += Vector2(cos(aj), sin(aj)) * (0.07 + rng.randf() * 0.05)
			pts.append(p)
		_crack.append(pts)
	_ground = _GroundLayer.new()
	_ground.fx = self
	_ground.top_level = true
	_ground.z_as_relative = false
	_ground.z_index = GROUND_Z
	add_child(_ground)

func _clock() -> float:
	var bm = caster.get("battle_manager") if caster and is_instance_valid(caster) else null
	if bm == null:
		return 1.0
	if bm.get("paused"):
		return 0.0
	return float(bm.get("time_scale")) if bm.get("time_scale") != null else 1.0

func _ground_pt() -> Vector2:
	var p: Vector2 = caster.global_position
	if caster.has_method("ground_offset"):
		p.y += float(caster.ground_offset())
	return p

func _belly() -> Vector2:
	var m = caster.get("model3d")
	return m.bone_canvas_position("Spine01") if m else caster.global_position

func _unit_ground(u: Node2D) -> Vector2:
	var p: Vector2 = u.global_position
	if u.has_method("ground_offset"):
		p.y += float(u.ground_offset())
	return p

func _process(delta: float) -> void:
	if not (caster and is_instance_valid(caster)):
		queue_free()
		return
	_t += delta * _clock()
	if _t >= end_time:
		queue_free()
		return
	queue_redraw()
	_ground.queue_redraw()

# ── helpers ─────────────────────────────────────────────────────────────────

static func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

func _ell(c: Vector2, r: Vector2, n: int = 56) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts

func _ring(ci: CanvasItem, c: Vector2, r: Vector2, col: Color, w: float) -> void:
	ci.draw_polyline(_ell(c, r), col, w, true)

func _disc(ci: CanvasItem, c: Vector2, r: Vector2, col: Color) -> void:
	var pts := _ell(c, r, 40)
	pts.remove_at(pts.size() - 1)
	ci.draw_colored_polygon(pts, col)

func _glow(ci: CanvasItem, c: Vector2, r: float, col: Color, layers: int = 6) -> void:
	for i in range(layers, 0, -1):
		var f := float(i) / layers
		ci.draw_circle(c, r * f, Color(col, col.a * (1.0 - f) * 0.9))

## A toon dust cloud: a FLAT lumpy cluster, not a ball — shadow lumps along the
## ground, lit lumps piled on top, a faint rim light. (v2's single shaded circle
## with a specular dot read as a ring of beige pearls on the first capture.)
const _LUMPS := [   # [x, y, r] in cloud-radius units; first 3 = base row
	[-0.70, 0.10, 0.55], [0.0, 0.18, 0.62], [0.72, 0.08, 0.52],
	[-0.32, -0.30, 0.55], [0.34, -0.26, 0.50], [0.02, -0.62, 0.38],
]
func _puff_draw(ci: CanvasItem, p: Vector2, r: float, a: float, v: int = 0) -> void:
	if a <= 0.01 or r <= 0.5:
		return
	var lumps: Array = []
	for i in _LUMPS.size():
		var l: Array = _LUMPS[i]
		var jit := 0.85 + 0.3 * fmod((v * 7 + i * 3) * 0.618, 1.0)
		lumps.append([p + Vector2(l[0], l[1]) * r, float(l[2]) * r * jit])
	for l in lumps:
		ci.draw_circle(l[0], l[1] + 2.0, Color(OUTLINE, 0.35 * a))
	for i in 3:
		ci.draw_circle(lumps[i][0], lumps[i][1], Color(DUST_SH, a))
	for i in range(3, lumps.size()):
		ci.draw_circle(lumps[i][0] + Vector2(0, 0.1 * r), lumps[i][1], Color(DUST_SH, a))
		ci.draw_circle(lumps[i][0], lumps[i][1] * 0.92, Color(DUST, a))
	ci.draw_circle(lumps[5][0] + Vector2(-0.10, -0.12) * r, lumps[5][1] * 0.55, Color(DUST_HI, 0.55 * a))

func _pebble(ci: CanvasItem, p: Vector2, r: float, kind: int, a: float, spin: float) -> void:
	if kind == 2:   # grass tuft
		var d := Vector2(cos(spin), sin(spin)) * r * 2.2
		ci.draw_line(p - d, p + d, Color(OUTLINE, 0.7 * a), 4.0, true)
		ci.draw_line(p - d, p + d, Color(GRASS, a), 2.0, true)
		return
	ci.draw_circle(p, r + 1.5, Color(OUTLINE, 0.8 * a))
	ci.draw_circle(p, r, Color(SOIL if kind == 0 else DUST_SH, a))
	ci.draw_circle(p + Vector2(-0.3, -0.3) * r, r * 0.4, Color(DUST, a))

# ── ground layer (z 1, under the units) ─────────────────────────────────────

func _draw_ground(ci: CanvasItem) -> void:
	if not (caster and is_instance_valid(caster)):
		return
	var g := _ground_pt()
	if _t < impact:
		var k := clampf((_t - 0.04) / (pull_start - 0.04), 0.0, 1.0)
		var pk := clampf((_t - pull_start) / (pull_end - pull_start), 0.0, 1.0)
		var shrink := 1.0 - 0.10 * pk
		var r := radius * shrink * (0.6 + 0.4 * _ease_out(k))
		# suction disc: two filled tones, darker toward the rim like a bowl
		_disc(ci, g, r, Color(AIR_DEEP, 0.16 * k))
		_disc(ci, g, r * 0.62, Color(AIR_MID, 0.10 * k))
		# ripple rings flowing INWARD (Nemi's rings, reversed): thin at the rim,
		# thickening as they close on him
		for i in 4:
			var ph := fposmod(_t * (1.3 + 1.2 * pk) + i / 4.0, 1.0)
			var rr := r * (1.0 - 0.85 * ph)
			var a := k * sin(PI * ph) * 0.75
			_ring(ci, g, rr, Color(OUTLINE, 0.25 * a), 2.0 + 5.0 * ph + 2.5)
			_ring(ci, g, rr, Color(AIR_HI, a), 1.5 + 5.0 * ph)
		# rim
		_ring(ci, g, r, Color(OUTLINE, 0.40 * k), 6.0)
		_ring(ci, g, r, Color(AIR_MID, 0.85 * k), 3.0)
		# dust dragged along the ground toward him
		for i in 20:
			var ang := TAU * i / 20.0 + 0.13 * i
			var s := fposmod(0.37 * i + _t * (0.9 + 1.4 * pk), 1.0)
			var dir := Vector2(cos(ang) * r.x, sin(ang) * r.y)
			var p0 := g + dir * (1.0 - s * 0.85)
			var p1 := g + dir * (1.0 - minf(1.0, s + 0.10) * 0.85)
			var a := k * sin(PI * s) * 0.8
			ci.draw_line(p0, p1, Color(DUST_SH, a * 0.6), 5.0, true)
			ci.draw_line(p0, p1, Color(DUST, a), 2.5, true)
		# brace: little puffs at his own feet as he plants
		if _t < pull_start + 0.1:
			var b := clampf(_t / 0.18, 0.0, 1.0)
			for sd in [-1.0, 1.0]:
				_puff_draw(ci, g + Vector2(sd * (14.0 + 10.0 * b), -3.0 * b), 5.0 + 5.0 * b,
					0.8 * (1.0 - clampf((_t - pull_start) / 0.1, 0.0, 1.0)))
		# dust billows behind whoever is being dragged
		if pk > 0.0 and pk < 1.0:
			for u in pulled:
				if not (u and is_instance_valid(u)):
					continue
				var up := _unit_ground(u)
				var away := (up - g).normalized()
				for j in 4:
					var d := 12.0 + j * 13.0
					_puff_draw(ci, up + away * d + Vector2(0, -j * 2.0),
						(7.0 + j * 2.0) * (0.7 + 0.5 * pk), 0.85 * (1.0 - j * 0.2) * (1.0 - pk * 0.4))
	else:
		var e := _t - impact
		var life := end_time - impact
		var fade := clampf(1.0 - e / life, 0.0, 1.0)
		# crater: a dark dent where he slammed the air out
		var dent := _ease_out(e / 0.10)
		_disc(ci, g, radius * Vector2(0.26, 0.26) * dent, Color(SOIL, 0.40 * fade))
		_disc(ci, g, radius * Vector2(0.16, 0.16) * dent, Color(OUTLINE, 0.25 * fade))
		# cracks
		for c in _crack:
			var pts := PackedVector2Array()
			for p in c:
				pts.append(g + Vector2(p.x * radius.x, p.y * radius.y) * 1.05 * dent)
			ci.draw_polyline(pts, Color(OUTLINE, 0.75 * fade), 3.5, true)
			ci.draw_polyline(pts, Color(SOIL, 0.9 * fade), 1.5, true)
		# dust haze under the cloud ring, so the clouds read as one rolling band
		var hp := _ease_out(e / 0.60)
		var hr := radius * (0.12 + 0.62 * hp)
		var ha := clampf(e / 0.06, 0.0, 1.0) * (1.0 - smoothstep(0.25, 1.0, e / life))
		_ring(ci, g, hr, Color(DUST_SH, 0.30 * ha), 30.0 + 26.0 * hp)
		_ring(ci, g, hr, Color(DUST, 0.30 * ha), 16.0 + 14.0 * hp)
		# shockwave band: thick, layered, leading edge brightest
		for w in 2:
			var we := e - w * 0.10
			if we <= 0.0:
				continue
			var p := clampf(we / 0.45, 0.0, 1.0)
			var rr := radius * (0.15 + 1.0 * _ease_out(p))
			var a := (1.0 - p) * (1.0 if w == 0 else 0.6)
			var th := (22.0 * (1.0 - p) + 5.0) * (1.0 if w == 0 else 0.55)
			_ring(ci, g, rr, Color(OUTLINE, 0.45 * a), th + 4.0)
			_ring(ci, g, rr, Color(DUST, 0.85 * a), th)
			_ring(ci, g, rr * 0.985, Color(DUST_HI, 0.9 * a), th * 0.45)
			_ring(ci, g, rr * 1.01, Color(AIR_HI, 0.95 * a), maxf(1.5, th * 0.18))

# ── air layer (z 20, over the units) ────────────────────────────────────────

func _draw() -> void:
	if not (caster and is_instance_valid(caster)):
		return
	var g := _ground_pt()
	var belly := _belly()
	if _t < impact:
		_draw_inhale(g, belly)
	else:
		_draw_exhale(g, belly)

func _draw_inhale(g: Vector2, belly: Vector2) -> void:
	var k := clampf((_t - 0.04) / (pull_start - 0.04), 0.0, 1.0)
	var pk := clampf((_t - pull_start) / (pull_end - pull_start), 0.0, 1.0)
	var shrink := 1.0 - 0.10 * pk
	var speed := 1.3 + 1.3 * pk          # the draw accelerates as he fills up
	# wind ribbons: tapered, outlined, three tones, spiralling into his belly
	for s in _rib:
		var ang: float = s.x
		var head := fposmod(s.y + _t * speed * s.z, 1.0)
		var tail := maxf(0.0, head - 0.42)
		var a := k * (0.45 + 0.55 * head) * (1.0 - smoothstep(0.86, 1.0, head))
		if a <= 0.02:
			continue
		var pts: Array = []
		var ws: Array = []
		var n := 10
		for j in n:
			var f := float(j) / (n - 1)
			var sp := lerpf(tail, head, f)
			var sw := ang + 1.4 * sp
			var edge := g + Vector2(cos(sw) * radius.x, sin(sw) * radius.y) * shrink
			pts.append(edge.lerp(belly, sp * sp * (3.0 - 2.0 * sp)))
			ws.append(16.0 * sin(PI * clampf(f * 1.05, 0.0, 1.0)) * (1.0 - 0.55 * sp) + 1.0)
		for layer in 3:
			for j in n - 1:
				var w: float = (ws[j] + ws[j + 1]) * 0.5
				var col: Color
				match layer:
					0: col = Color(OUTLINE, 0.45 * a); w += 3.5
					1: col = Color(AIR_DEEP.lerp(AIR_MID, 0.5), 0.80 * a)
					_: col = Color(AIR_HI, 0.95 * a); w *= 0.32
				draw_line(pts[j], pts[j + 1], col, w, true)
				if layer < 2:
					draw_circle(pts[j + 1], w * 0.5, col)
	# debris torn up and sucked in
	for d in _deb:
		var u := clampf((_t - pull_start * 0.6 - d[2]) / 0.42, 0.0, 1.0)
		if u <= 0.0 or u >= 0.97:
			continue
		var uu := u * u
		var aa: float = d[0] + 2.0 * uu
		var gp: Vector2 = g + Vector2(cos(aa) * radius.x, sin(aa) * radius.y) * float(d[1]) * (1.0 - uu)
		var p: Vector2 = gp.lerp(belly, uu * u)
		p.y -= sin(PI * u) * 18.0
		_pebble(self, p, d[3] * (1.0 - 0.4 * u), d[4], k * (1.0 - smoothstep(0.85, 0.97, u)), aa * 3.0)
	# compressed air ball at the belly
	var fill := clampf((_t - pull_start * 0.5) / (impact - pull_start * 0.5), 0.0, 1.0)
	_glow(self, belly, 18.0 + 34.0 * fill, Color(AIR_MID, 0.85 * k))
	for i in 2:
		var ph := fposmod(_t * 3.0 + i * 0.5, 1.0)
		var rr := (46.0 + 20.0 * fill) * (1.0 - ph)
		draw_arc(belly, rr, 0, TAU, 32, Color(AIR_HI, k * ph * 0.8), 2.0 + 2.0 * ph, true)
	draw_circle(belly, 5.0 + 5.0 * fill, Color(AIR_HI, 0.9 * k))
	# speed lines on dragged enemies (body height, streaming away from him)
	if pk > 0.0 and pk < 1.0:
		for unit in pulled:
			if not (unit and is_instance_valid(unit)):
				continue
			var up := _unit_ground(unit)
			var away := (up - g).normalized()
			var side := away.orthogonal()
			for j in 4:
				var o := side * (j - 1.5) * 11.0 + Vector2(0, -26.0 - j * 7.0)
				var st := up + o + away * (22.0 + 8.0 * fmod(j * 0.61 + _t * 5.0, 1.0) * 10.0)
				var en := st + away * (26.0 + 10.0 * j)
				var a := 0.9 * sin(PI * pk)
				draw_line(st, en, Color(OUTLINE, 0.5 * a), 5.0, true)
				draw_line(st, en, Color(AIR_HI, a), 2.5, true)

func _draw_exhale(g: Vector2, belly: Vector2) -> void:
	var e := _t - impact
	var life := end_time - impact
	var fade := clampf(1.0 - e / life, 0.0, 1.0)
	# the air ball bursts: white flash
	if e < 0.16:
		var f := e / 0.16
		_glow(self, belly.lerp(g, 0.4), 70.0 + 110.0 * f, Color(AIR_HI, 1.0 - f), 7)
	# radial speed lines riding just ahead of the shockwave
	var p := clampf(e / 0.45, 0.0, 1.0)
	if p < 1.0:
		var rr := radius * (0.15 + 1.0 * _ease_out(p))
		for i in 20:
			var ang := TAU * i / 20.0 + 0.11
			var dir := Vector2(cos(ang), sin(ang))
			var a0 := g + Vector2(dir.x * rr.x, dir.y * rr.y) * 0.80
			var a1 := g + Vector2(dir.x * rr.x, dir.y * rr.y) * (1.06 + 0.10 * (i % 3))
			var a := (1.0 - p) * 0.95
			draw_line(a0, a1, Color(OUTLINE, 0.4 * a), 5.5, true)
			draw_line(a0, a1, Color(AIR_HI, a), 2.5, true)
	# debris thrown outward on gravity arcs
	for c in _chunk:
		var dir := Vector2(cos(float(c[0])), sin(float(c[0])))
		var tt := e * 1.0
		var out: Vector2 = Vector2(dir.x * radius.x, dir.y * radius.y) * 0.9 * float(c[1]) * _ease_out(tt / 0.7)
		var hop: float = 150.0 * c[2] * tt - 330.0 * tt * tt
		if hop < -4.0:
			continue
		var pos := g + out + Vector2(0, -maxf(hop, 0.0))
		_pebble(self, pos, c[3], 0 if int(c[3] * 10) % 2 == 0 else 1, fade, c[0] + e * 9.0)
	# rolling dust ring: shaded clouds that ride the shockwave out, then hang
	var order: Array = []
	for i in PUFFS:
		order.append(i)
	order.sort_custom(func(a, b): return sin(_puff[a][0]) < sin(_puff[b][0]))
	for i in order:
		var pf: Array = _puff[i]
		var dp := _ease_out(e / 0.60)
		var dir := Vector2(cos(float(pf[0])), sin(float(pf[0])))
		# rides the shockwave out to ~3/4 of the radius, then hangs and thins
		var pos: Vector2 = g + Vector2(dir.x * radius.x, dir.y * radius.y) * (0.12 + 0.62 * dp) * float(pf[1])
		pos.y -= 16.0 * pf[3] * _ease_out(e / 0.9)
		var sz: float = (9.0 + 16.0 * _ease_out(e / 0.5) + 8.0 * e) * pf[2]
		var a := clampf(e / 0.05, 0.0, 1.0) * (1.0 - smoothstep(0.20, 0.95, e / life))
		_puff_draw(self, pos, sz, 0.88 * a, i)
	# impact ticks
	if e < 0.2:
		for i in 12:
			var ang := TAU * i / 12.0 + 0.2
			var dir := Vector2(cos(ang), sin(ang) * radius.y / radius.x)
			var q := e / 0.2
			draw_line(g + dir * radius.x * (0.08 + 0.10 * q), g + dir * radius.x * (0.2 + 0.12 * q),
				Color(1, 1, 0.9, 1.0 - q), 3.0, true)
