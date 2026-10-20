extends Node2D
class_name SporeVFX

# Spore owns LIGHT, AIRBORNE FUNGUS: drifting spore motes, small mushroom caps,
# puffball plumes and violet mycelium threads. Colours come from his own model
# -- the violet flowers and pale ochre bulbs on his shoulders -- so he never
# borrows June's language (heavy bark, amber growth, thorned ground) even though
# both are "nature" heroes. Until 2026-10-02 all three of his moves drew the
# shared SkillEffect.NATURE ring, the same one June used, at 32-40px: at board
# size it vanished, which is how the owner found it ("no visual effects").
#
# Three moves, three jobs, three looks:
#   Spore Cloud (passive) MARKS  -- HAZE around him, CAPS on whoever is infested
#   Bloom (skill)        SPREADS -- PATCH of mushrooms on the board
#   Release (ult)        CASHES IN -- RING at him, THREADs out, PUFFs in order
#
# Every animated mode draws a few dozen primitives at most. No per-triangle
# polygon calls: VailVFX's per-triangle ribbons measured 33-120ms/frame.
enum Mode {
	HAZE,     # persistent: the tiles Spore Cloud reaches, rebuilt per step
	CAPS,     # persistent: 1-3 caps at an infested enemy's feet, by stacks
	PUFF,     # one-shot: puffball burst (passive burst, Release pop)
	PATCH,    # persistent for Bloom's duration: mushroom cells on the board
	RING,     # one-shot: Release cast, mycelium cracks around Spore
	THREAD,   # one-shot: Release crack racing from Spore to one target
}

const VIOLET := Color(0.66, 0.38, 0.95)
const OCHRE  := Color(0.95, 0.80, 0.46)
const PALE   := Color(1.00, 0.95, 0.84)
## Value contrast. The board is grass; a violet-on-green mote without a dark
## backing reads as noise, so every readable shape sits on this.
const DUSK   := Color(0.15, 0.07, 0.22)
const PLANE_SQUASH := 0.42
## See JuneVFX.GROUND_Z: 1 is the only z that clears the board art and still
## passes under every unit (units are 2 + row).
const GROUND_Z := 1

var mode: Mode = Mode.PUFF
var elapsed := 0.0
var lifetime := 0.6
var bm: Node = null            ## battle manager, for the battle clock
var target: Node2D = null      ## HAZE: Spore. CAPS: the infested unit. THREAD: the target
var source: Node2D = null      ## THREAD: Spore
var rx := 100.0                ## RING: ground ellipse radius
var scale_k := 1.0             ## PUFF size
var _bucket := -1              ## CAPS: last drawn cap count
var _cells_local: Array = []   ## PATCH / HAZE: cell quads in local space
var _seeds: PackedFloat32Array = PackedFloat32Array()

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 64:
		_seeds.append(rng.randf())

func _s(i: int) -> float:
	return _seeds[i % _seeds.size()]

static func _feet(u: Node2D) -> Vector2:
	var off: float = u.ground_offset() if u.has_method("ground_offset") else 0.0
	return u.global_position + Vector2(0, off)

func setup_haze(spore: Node2D, manager: Node) -> void:
	mode = Mode.HAZE
	target = spore
	bm = manager
	lifetime = INF
	z_index = GROUND_Z

## Spore Cloud on the GRID (owner call 2026-10-04): the haze lights the exact
## tiles the passive reaches instead of a free ellipse. The manager rebuilds
## this when Spore finishes a step -- grid_position only updates then, and
## that is also when the passive's reach moves, so tiles and stacks agree.
## The node is pinned to the board, not to Spore; quads and the outer edge are
## converted to local space once per rebuild.
var _haze_edges: Array = []
func set_tiles(global_quads: Array, global_edges: Array, anchor: Vector2) -> void:
	global_position = anchor
	_cells_local.clear()
	for q in global_quads:
		var l := PackedVector2Array()
		for pt: Vector2 in q:
			l.append(pt - anchor)
		_cells_local.append(l)
	_haze_edges.clear()
	for seg in global_edges:
		_haze_edges.append(PackedVector2Array([seg[0] - anchor, seg[1] - anchor]))
	queue_redraw()

func setup_caps(unit: Node2D, manager: Node) -> void:
	mode = Mode.CAPS
	target = unit
	bm = manager
	lifetime = INF
	z_index = GROUND_Z
	global_position = _feet(unit)

func setup_puff(at: Vector2, k: float, manager: Node) -> void:
	mode = Mode.PUFF
	global_position = at
	scale_k = k
	bm = manager
	lifetime = 0.75
	z_index = 9     # the plume rises over the body it burst from

func setup_patch(cell_quads: Array, life: float, centre: Vector2, manager: Node) -> void:
	mode = Mode.PATCH
	global_position = centre
	lifetime = life
	bm = manager
	z_index = GROUND_Z
	_cells_local.clear()
	for q in cell_quads:
		var l := PackedVector2Array()
		for pt: Vector2 in q:
			l.append(pt - centre)
		_cells_local.append(l)

func setup_ring(at: Vector2, radius_px: float, manager: Node) -> void:
	mode = Mode.RING
	global_position = at
	rx = radius_px
	bm = manager
	lifetime = 0.7
	z_index = GROUND_Z

func setup_thread(from: Node2D, to: Node2D, travel: float, manager: Node) -> void:
	mode = Mode.THREAD
	source = from
	target = to
	bm = manager
	lifetime = travel + 0.22
	rx = travel             # reused: how long the crack takes to arrive
	z_index = GROUND_Z
	global_position = _feet(from)

## Battle clock (see RiftVFX._clock): effects slow with the pace control and
## stop while paused.
func _clock() -> float:
	if bm == null or not is_instance_valid(bm):
		return 1.0
	if bm.get("paused"):
		return 0.0
	var ts = bm.get("time_scale")
	return float(ts) if ts != null else 1.0

func _process(delta: float) -> void:
	elapsed += delta * _clock()
	match mode:
		Mode.HAZE:
			if not (target and is_instance_valid(target)) or target.current_hp <= 0:
				queue_free()
				return
		Mode.CAPS:
			if not (target and is_instance_valid(target)) or target.current_hp <= 0 \
					or float(target.get("spore_stacks")) <= 0.0:
				queue_free()
				return
			global_position = _feet(target)
			var b := _cap_bucket()
			if b != _bucket:
				_bucket = b
			elif b < 3:
				return          # static until the bucket changes: no redraw
		Mode.THREAD:
			if source and is_instance_valid(source):
				global_position = _feet(source)
	if elapsed >= lifetime:
		queue_free()
		return
	queue_redraw()

func _cap_bucket() -> int:
	var st: float = float(target.get("spore_stacks"))
	return clampi(int(ceil(st / 10.0 * 3.0)), 1, 3)

func _fade_out() -> float:
	return clampf((lifetime - elapsed) / 0.3, 0.0, 1.0)

# ── Primitives ───────────────────────────────────────────────────────────────

func _ellipse(rx_: float, ry: float, n: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a) * rx_, sin(a) * ry))
	return pts

## A small mushroom: dark rim, violet cap, two ochre spots, pale stem.
func _cap(at: Vector2, k: float, alpha: float) -> void:
	if k <= 0.02 or alpha <= 0.01:
		return
	var w := 7.0 * k
	var h := 5.0 * k
	draw_rect(Rect2(at + Vector2(-1.6 * k, -h * 0.9), Vector2(3.2 * k, h)),
		Color(PALE.r, PALE.g, PALE.b, alpha))
	var dome := PackedVector2Array()
	for i in 9:
		var a := PI + PI * float(i) / 8.0
		dome.append(at + Vector2(cos(a) * w, -h * 0.8 + sin(a) * h))
	var rim := dome.duplicate()
	draw_colored_polygon(_grow(dome, at + Vector2(0, -h * 0.8), 1.25 * k),
		Color(DUSK.r, DUSK.g, DUSK.b, alpha * 0.9))
	draw_colored_polygon(rim, Color(VIOLET.r, VIOLET.g, VIOLET.b, alpha))
	draw_circle(at + Vector2(-2.6 * k, -h * 1.25), 1.1 * k, Color(OCHRE.r, OCHRE.g, OCHRE.b, alpha))
	draw_circle(at + Vector2(2.2 * k, -h * 1.45), 0.9 * k, Color(OCHRE.r, OCHRE.g, OCHRE.b, alpha))

func _grow(poly: PackedVector2Array, c: Vector2, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + (p - c).normalized() * by)
	return out

## A drifting mote with a dark backing so it reads on grass.
func _mote(at: Vector2, r: float, col: Color, alpha: float) -> void:
	if alpha <= 0.01:
		return
	draw_circle(at, r + 1.2, Color(DUSK.r, DUSK.g, DUSK.b, alpha * 0.45))
	draw_circle(at, r, Color(col.r, col.g, col.b, alpha))

# ── Modes ────────────────────────────────────────────────────────────────────

func _draw() -> void:
	match mode:
		Mode.HAZE:   _draw_haze()
		Mode.CAPS:   _draw_caps()
		Mode.PUFF:   _draw_puff()
		Mode.PATCH:  _draw_patch()
		Mode.RING:   _draw_ring()
		Mode.THREAD: _draw_thread()

# Spore Cloud's reach: the exact tiles it covers, tinted dusk-violet, with the
# region's OUTER edge traced (internal tile borders dropped, so it reads as one
# area, the same call as June's aura) and motes drifting up off the tiles.
# Quiet on purpose -- it is on screen the whole fight.
func _draw_haze() -> void:
	if _cells_local.is_empty():
		return
	for q: PackedVector2Array in _cells_local:
		draw_colored_polygon(q, Color(DUSK.r, DUSK.g, DUSK.b, 0.16))
		draw_colored_polygon(q, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.08))
	for seg: PackedVector2Array in _haze_edges:
		draw_line(seg[0], seg[1], Color(DUSK.r, DUSK.g, DUSK.b, 0.55), 4.0, true)
	for seg: PackedVector2Array in _haze_edges:
		draw_line(seg[0], seg[1], Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.70), 1.8, true)
	var n: int = _cells_local.size()
	for i in 18:
		var q: PackedVector2Array = _cells_local[int(_s(i + 40) * n) % n]
		var cycle := 2.6 + _s(i) * 1.8
		var ph: float = fmod(elapsed / cycle + _s(i + 20), 1.0)
		var u := 0.2 + 0.6 * _s(i + 7)
		var v := 0.25 + 0.6 * _s(i + 11)
		var base: Vector2 = q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), v)
		var col := VIOLET if i % 3 != 0 else OCHRE
		_mote(base + Vector2(sin(elapsed + i) * 3.0, -ph * 34.0), 1.5 + _s(i + 3) * 1.3,
			col, sin(ph * PI) * 0.75)

# Infestation progress: 1-3 caps at the feet. The third cap pulses -- this
# unit is about to pop.
func _draw_caps() -> void:
	var b: int = max(_bucket, 1)
	var spots := [Vector2(-11, 2), Vector2(10, 3), Vector2(0, 7)]
	var pulse := 1.0
	if b >= 3:
		pulse = 1.0 + 0.12 * sin(elapsed * 9.0)
	for i in b:
		_cap(spots[i], (0.95 + 0.15 * float(i)) * pulse, 0.95)

# Puffball burst: the cap swells, then a spore plume climbs and spreads.
func _draw_puff() -> void:
	var t := elapsed / lifetime
	var k := scale_k
	if t < 0.16:
		_cap(Vector2.ZERO, (1.3 + t / 0.16 * 1.1) * k, 1.0)
		return
	var u := (t - 0.16) / 0.84
	var a := 1.0 - u
	# ground ring of motes thrown out on the plane
	for i in 10:
		var ang := TAU * float(i) / 10.0 + _s(i)
		var dist := (10.0 + 26.0 * u) * k * (0.7 + 0.3 * _s(i + 11))
		_mote(Vector2(cos(ang) * dist, sin(ang) * dist * PLANE_SQUASH), 1.6 * k,
			OCHRE if i % 2 == 0 else VIOLET, a * 0.9)
	# the plume -- first board check (2026-10-02) read only the swelling cap;
	# the plume needed more mass and more opacity to register at 1x.
	for i in 9:
		var rise := (14.0 + 46.0 * _s(i + 5)) * u * k
		var x := (_s(i + 13) - 0.5) * 30.0 * k * (0.4 + u)
		var r := (7.0 + 10.0 * u) * k * (0.7 + 0.5 * _s(i + 17))
		var c := Vector2(x, -rise)
		draw_circle(c, r + 2.5, Color(DUSK.r, DUSK.g, DUSK.b, a * 0.50))
		draw_circle(c, r, Color(VIOLET.r, VIOLET.g, VIOLET.b, a * 0.78))
		draw_circle(c + Vector2(-r * 0.25, -r * 0.25), r * 0.45, Color(PALE.r, PALE.g, PALE.b, a * 0.55))

# Bloom: mushrooms sprouting across the patch cells, a dusk tint on the ground
# and motes rising off it for as long as it lasts.
func _draw_patch() -> void:
	var grow := clampf(elapsed / 0.45, 0.0, 1.0)
	var a := _fade_out()
	for ci in _cells_local.size():
		var q: PackedVector2Array = _cells_local[ci]
		draw_colored_polygon(q, Color(DUSK.r, DUSK.g, DUSK.b, 0.30 * a * grow))
		var ring := q.duplicate()
		ring.append(q[0])
		draw_polyline(ring, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.30 * a * grow), 1.2, true)
		for m in 3:
			var su := 0.2 + 0.6 * _s(ci * 7 + m)
			var sv := 0.3 + 0.55 * _s(ci * 7 + m + 3)
			var top: Vector2 = q[0].lerp(q[1], su)
			var bot: Vector2 = q[3].lerp(q[2], su)
			var p: Vector2 = top.lerp(bot, sv)
			var stagger := clampf(grow * 1.6 - _s(ci + m) * 0.6, 0.0, 1.0)
			_cap(p, (0.8 + 0.4 * _s(ci + m + 9)) * stagger, a)
		for m in 2:
			var ph: float = fmod(elapsed / 1.7 + _s(ci * 5 + m + 30), 1.0)
			var c: Vector2 = (q[0] + q[1] + q[2] + q[3]) * 0.25
			var off := Vector2((_s(ci + m + 50) - 0.5) * 30.0, -ph * 30.0)
			_mote(c + off, 1.6, VIOLET if m == 0 else OCHRE, sin(ph * PI) * 0.8 * a * grow)

# Release cast: mycelium cracks splitting the ground around Spore.
func _draw_ring() -> void:
	var t := elapsed / lifetime
	var a := 1.0 - t
	var r := rx * (0.35 + 0.65 * t)
	var e := _ellipse(r, r * PLANE_SQUASH, 40)
	e.append(e[0])
	draw_polyline(e, Color(DUSK.r, DUSK.g, DUSK.b, a * 0.7), 5.0, true)
	draw_polyline(e, Color(VIOLET.r, VIOLET.g, VIOLET.b, a), 2.2, true)
	for i in 8:
		var ang := TAU * float(i) / 8.0 + _s(i) * 0.4
		var pts := PackedVector2Array()
		for j in 5:
			var wob := (_s(i * 5 + j) - 0.5) * 8.0
			var d := r * (0.25 + 0.75 * float(j) / 4.0)
			pts.append(Vector2(cos(ang) * d + wob * -sin(ang),
				(sin(ang) * d + wob * cos(ang)) * PLANE_SQUASH))
		draw_polyline(pts, Color(DUSK.r, DUSK.g, DUSK.b, a * 0.7), 4.0, true)
		draw_polyline(pts, Color(OCHRE.r, OCHRE.g, OCHRE.b, a * 0.9), 1.6, true)

# Release: one crack racing along the ground from Spore to a target. Arrival
# is the moment that target pops.
func _draw_thread() -> void:
	if not (target and is_instance_valid(target)):
		return
	var to: Vector2 = to_local(_feet(target))
	var p := clampf(elapsed / maxf(rx, 0.001), 0.0, 1.0)
	var a := _fade_out()
	var n := 12
	var side := to.normalized().orthogonal()
	var pts := PackedVector2Array()
	var last := int(ceil(p * float(n)))
	for i in range(last + 1):
		var f := minf(float(i) / float(n), p)
		var wob := sin(f * TAU * 1.5 + _s(1) * TAU) * 6.0 * sin(f * PI)
		pts.append(to * f + side * wob)
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(DUSK.r, DUSK.g, DUSK.b, 0.7 * a), 5.0, true)
	draw_polyline(pts, Color(VIOLET.r, VIOLET.g, VIOLET.b, a), 2.4, true)
	if p < 1.0:
		_mote(pts[pts.size() - 1], 3.0, PALE, a)
