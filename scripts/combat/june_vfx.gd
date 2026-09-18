extends Node2D
class_name JuneVFX

# June owns LOAM AND OVERGROWTH: wet-earth browns, living green, and a pale
# gold-green bloom highlight. Deliberately heavy and woody — bark, roots,
# thickening growth that sits ON the ground — so she never reads as Spore, the
# game's other nature hero, whose language stays light and airborne.
#
# Everything here that represents a lasting mechanic is drawn on the board
# PLANE (squashed ellipses, per-cell quads) rather than as a screen-facing
# circle, because the board is a faked-perspective trapezoid grid and an
# axis-aligned overlay visibly floats above it.
enum Mode {
	AURA_LATTICE,   # persistent: Verdant Aura's radius, follows June
	AURA_PULSE,     # one regen tick travelling out to an ally it healed
	ROOT_CUFF,      # persistent: bark cuffs on a rooted unit, for as long as it lasts
	AUTO_IMPACT,    # auto attack contact — compact, ~1/3 of a cell
	BLOOM_CAST,     # the ultimate's cast beat: growth erupting toward the band
	BLOOM_FIELD,    # persistent: the thorned ground of the ultimate
	BLOOM_TICK,     # one enemy taking a Bloom tick
}

# THE BOARD IS GRASS. Nemi's wave gets its separation for free — blue water on a
# green field — but June is nature ON nature, so hue contrast is unavailable to
# her and a green-on-green effect disappears into the tiles (user report
# 2026-09-17, confirmed once a z-order bug stopped hiding it under the board).
# She wins on VALUE and WARMTH instead: near-black bramble silhouettes and warm
# amber growth against the cool mid-green of the grass. The greens that remain
# are dark fill tones, never the readable layer.
const LOAM  := Color(0.09, 0.06, 0.03)   # near-black wet earth — the broad body
const BARK  := Color(0.26, 0.16, 0.07)   # dark woody silhouette
const MOSS  := Color(0.13, 0.22, 0.10)   # deep fill green, NOT a readable layer
const GREEN := Color(0.58, 0.72, 0.18)   # olive-amber edge, reads against grass
const AMBER := Color(0.95, 0.70, 0.22)   # THE readable layer — warm, non-grass
const BLOOM := Color(1.00, 0.94, 0.66)   # pale warm focal highlight

## Ground shapes are drawn as ellipses this much flatter than a circle, matching
## the board's 28-degree pitch closely enough to sit ON the plane.
const PLANE_SQUASH := 0.42

var mode: Mode = Mode.AUTO_IMPACT
var elapsed := 0.0
var lifetime := 0.5
var source: Node2D = null
var target: Node2D = null
var radius_px := 100.0
var quads: Array = []          ## BLOOM_FIELD: cell trapezoids, in GLOBAL coords
var aura_cell_count := 0       ## AURA_LATTICE: how many cells the heal reaches
var anchor_cell := Vector2i(-999, -999)  ## the cell the outline was built for
## Local-space copies, computed ONCE per rebuild. Converting 28 cells x 4 corners
## per frame per June cost 15ms at a 15-June roster (41.88ms vs 26.58ms measured)
## — the aura is static between her steps, so it has no business recomputing.
var _aura_edges: Array = []
var _field_local: Array = []
var perimeter: PackedVector2Array = PackedVector2Array()  ## the band's outer edge, GLOBAL
var to_world := Vector2.ZERO   ## BLOOM_CAST: where the growth is heading
## Rolled fresh per cast, the way Nemi's Tidal Wave rolls its own: two Blooms
## should never grow the identical thicket.
var seeds: PackedFloat32Array = PackedFloat32Array()
var _pulse := 0.0

func setup_point(kind: Mode, world_pos: Vector2, life: float = 0.5,
		follow: Node2D = null) -> void:
	mode = kind
	global_position = world_pos
	lifetime = life
	target = follow
	z_index = 7
	queue_redraw()

func setup_pair(kind: Mode, from: Node2D, to: Node2D, life: float = 0.4) -> void:
	mode = kind
	source = from
	target = to
	lifetime = life
	global_position = from.global_position if (from and is_instance_valid(from)) else Vector2.ZERO
	z_index = 7
	queue_redraw()

## The aura, the Bloom field and the cast beat are GROUND overlays: they belong
## above the board art but under the units standing on them.
##
## GROUND_Z is 1, not -1, and that is not cosmetic. BackgroundLayer and the
## BattleGrid node are SIBLINGS, both at z 0, and units set z_index = 2 + row.
## At -1 these overlays sorted BELOW the background and were drawn underneath the
## grass — invisible in the real game, while a test scene with no BackgroundLayer
## showed them perfectly (user report 2026-09-17: "there is no animation in game").
## 1 is the only value that clears the board art and still passes under every unit.
const GROUND_Z := 1

func setup_ground(kind: Mode, world_pos: Vector2, life: float, radius: float = 100.0,
		follow: Node2D = null) -> void:
	mode = kind
	global_position = world_pos
	lifetime = life
	radius_px = radius
	target = follow
	z_index = GROUND_Z
	queue_redraw()

func setup_field(cell_quads: Array, life: float, centre: Vector2,
		band_edge: PackedVector2Array = PackedVector2Array()) -> void:
	mode = Mode.BLOOM_FIELD
	quads = cell_quads
	perimeter = band_edge
	lifetime = life
	global_position = centre
	z_index = GROUND_Z
	_roll_seeds()
	# Same caching reason as the aura: this node never moves once placed, so its
	# local quads are computed once instead of 15 cells x 4 corners per frame.
	_field_local.clear()
	for q in cell_quads:
		var l := PackedVector2Array()
		for pt: Vector2 in q:
			l.append(to_local(pt))
		_field_local.append(l)
	queue_redraw()

func setup_cast(from: Vector2, to: Vector2, life: float = 0.7) -> void:
	mode = Mode.BLOOM_CAST
	global_position = from
	to_world = to
	lifetime = life
	z_index = GROUND_Z
	_roll_seeds()
	queue_redraw()

## Rebuild the aura outline. Caches local-space copies and freezes the node's
## transform, so the per-frame draw is pure geometry it already owns.
func set_aura_edges(global_segments: Array, cell_count: int) -> void:
	aura_cell_count = cell_count
	_aura_edges.clear()
	for seg in global_segments:
		var l := PackedVector2Array()
		for pt: Vector2 in seg:
			l.append(to_local(pt))
		_aura_edges.append(l)
	queue_redraw()

func _roll_seeds() -> void:
	seeds = PackedFloat32Array()
	for i in range(10):
		seeds.append(randf())

func _seed(i: int) -> float:
	return seeds[i % seeds.size()] if not seeds.is_empty() else 0.5

## AURA_LATTICE / BLOOM_FIELD: a tick just landed — brighten briefly.
func pulse() -> void:
	_pulse = 1.0

func _process(delta: float) -> void:
	elapsed += delta
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta * 2.6)
	match mode:
		Mode.AURA_LATTICE:
			if not (target and is_instance_valid(target)) or target.current_hp <= 0:
				queue_free()
				return
			# Deliberately does NOT follow the unit: the lit tiles belong to the
			# BOARD, not to her body, and a moving transform would invalidate the
			# cached local quads every frame. The manager rebuilds them when her
			# grid cell changes, which is the only time they can change.
			if _pulse > 0.0:
				queue_redraw()
			return
		Mode.ROOT_CUFF:
			# Self-freeing on the REAL timer: the cuffs have to disappear the
			# instant the unit can walk again, or they promise CC that is over.
			if not (target and is_instance_valid(target)) or target.current_hp <= 0 \
					or target.root_time <= 0.0:
				queue_free()
				return
			global_position = target.global_position
		Mode.AURA_PULSE:
			if not (source and is_instance_valid(source)) \
					or not (target and is_instance_valid(target)):
				queue_free()
				return
			global_position = source.global_position
		_:
			if target and is_instance_valid(target):
				global_position = target.global_position
				if mode != Mode.BLOOM_CAST:
					_track_z(target)
	if elapsed >= lifetime:
		queue_free()
		return
	queue_redraw()

## The board-contact line of whatever unit this effect is attached to. A unit's
## origin sits well above its feet, so ground growth anchored at the origin
## climbs the body instead of sitting on the floor.
func _ground_y() -> float:
	if target and is_instance_valid(target) and target.has_method("ground_offset"):
		return target.ground_offset()
	return 0.0

## Sit one layer above the unit this effect belongs to. Units depth-sort by row
## (z_index = 2 + row, so 2..10 on a 9-row board), which means a FIXED effect z
## of 7 quietly slides behind any unit standing on row 6 or further back.
func _track_z(u: Node2D) -> void:
	if u and is_instance_valid(u):
		z_index = u.z_index + 1

func _fade() -> float:
	return clampf((lifetime - elapsed) / minf(lifetime, 0.25), 0.0, 1.0)

## An ellipse on the board plane. draw_circle can't be squashed directly, so the
## transform does it — same trick VisualUnit uses for unit shadows.
func _plane_ellipse(centre: Vector2, r: float, col: Color, width: float = -1.0) -> void:
	draw_set_transform(centre, 0.0, Vector2(1.0, PLANE_SQUASH))
	if width < 0.0:
		draw_circle(Vector2.ZERO, r, col)
	else:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, col, width)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## A gnarled root/vine run. Unlike a lightning bolt this does not jitter per
## frame — growth is slow and STAYS put, so the shape is seeded off `seed`.
func _root_run(from: Vector2, to: Vector2, width: float, alpha: float,
		seed_v: float, grow: float = 1.0) -> void:
	var dir := to - from
	if dir.length() < 0.01:
		return
	var side := dir.normalized().orthogonal()
	var pts := PackedVector2Array()
	for i in range(9):
		var t := float(i) / 8.0
		if t > grow:
			break
		var wob := sin(seed_v + t * 5.3) * 7.0 * sin(t * PI)
		pts.append(from.lerp(to, t) + side * wob)
	if pts.size() < 2:
		return
	draw_polyline(pts, Color(LOAM.r, LOAM.g, LOAM.b, alpha * 0.7), width * 2.6)
	draw_polyline(pts, Color(BARK.r, BARK.g, BARK.b, alpha), width * 1.6)
	draw_polyline(pts, Color(AMBER.r, AMBER.g, AMBER.b, alpha), width * 0.8)

func _draw() -> void:
	match mode:
		Mode.AURA_LATTICE: _draw_aura_lattice()
		Mode.AURA_PULSE:   _draw_aura_pulse()
		Mode.ROOT_CUFF:    _draw_root_cuff()
		Mode.AUTO_IMPACT:  _draw_auto_impact()
		Mode.BLOOM_CAST:   _draw_bloom_cast()
		Mode.BLOOM_FIELD:  _draw_bloom_field()
		Mode.BLOOM_TICK:   _draw_bloom_tick()

# ── Passive: Verdant Aura, persistent ─────────────────────────────────────────
# The aura healed all fight with nothing on screen. It then spent a version as an
# ELLIPSE, which was the wrong primitive: this game resolves everything on a
# grid, so a smooth ring tells the player "about this far" when the rule is
# "these exact squares" — and the two disagree at every edge (user call
# 2026-09-17). It now lights the literal cells the heal reaches, built from the
# same distance test _tick_passive uses, so the highlight cannot drift from the
# gameplay.
func _draw_aura_lattice() -> void:
	var p := _pulse
	# EDGES ONLY. Filling each cell lit up the board as a grid of squares and
	# competed with the units standing in it; the outline says the same thing —
	# "these squares" — while leaving the board readable underneath.
	for seg in _aura_edges:
		draw_polyline(seg, Color(LOAM.r, LOAM.g, LOAM.b, 0.45 + p * 0.20), 4.0)
		draw_polyline(seg, Color(AMBER.r, AMBER.g, AMBER.b, 0.70 + p * 0.30), 2.0)

# ── Passive: one regen tick reaching an ally ─────────────────────────────────
func _draw_aura_pulse() -> void:
	var a := _fade()
	var dest := to_local(target.global_position)
	var grow := clampf(elapsed / 0.16, 0.0, 1.0)
	_root_run(Vector2.ZERO, dest, 1.8, a, 11.0, grow)
	if grow > 0.9:
		# Leaves opening at the ally: this is a HEAL, so it resolves as bloom,
		# not as impact.
		for i in range(4):
			var ang := float(i) * TAU / 4.0 + elapsed * 1.5
			draw_circle(dest + Vector2.from_angle(ang) * 9.0, 3.4 * a,
					Color(BLOOM.r, BLOOM.g, BLOOM.b, a * 0.9))
		draw_circle(dest, 4.0 * a, Color(GREEN.r, GREEN.g, GREEN.b, a))

# ── Active: Root, persistent for the CC's real duration ──────────────────────
# Before this, the game's ONLY status tell was the stun icon, so a rooted enemy
# was pixel-identical to one that simply had nowhere to walk.
func _draw_root_cuff() -> void:
	var grow := clampf(elapsed / 0.22, 0.0, 1.0)
	# Fade out over the last half-second of the root rather than at a fixed
	# lifetime, so the visual expires exactly when the unit can move again.
	var a: float = clampf(target.root_time / 0.5, 0.0, 1.0)
	var foot := Vector2(0, _ground_y())
	_plane_ellipse(foot, 26.0 * grow, Color(LOAM.r, LOAM.g, LOAM.b, 0.55 * a))
	_plane_ellipse(foot, 26.0 * grow, Color(BARK.r, BARK.g, BARK.b, 0.85 * a), 3.0)
	# Bark cuffs climbing the ankles, plus a couple of thorn tips.
	for i in range(6):
		var ang := float(i) * TAU / 6.0 + 0.3
		var base := foot + Vector2(cos(ang) * 22.0, sin(ang) * 22.0 * PLANE_SQUASH)
		var top := base + Vector2(sin(float(i) * 2.1) * 4.0, -16.0 * grow)
		draw_line(base, top, Color(LOAM.r, LOAM.g, LOAM.b, 0.8 * a), 5.0)
		draw_line(base, top, Color(BARK.r, BARK.g, BARK.b, a), 3.0)
		draw_line(top, top + Vector2(sin(float(i)) * 3.0, -4.0),
				Color(AMBER.r, AMBER.g, AMBER.b, a), 2.0)

# ── Auto attack contact ──────────────────────────────────────────────────────
# Single-target melee, so the footprint stays inside roughly a third of a cell —
# the same restraint as Sheildor's bash.
func _draw_auto_impact() -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	_plane_ellipse(Vector2.ZERO, (14.0 + 20.0 * t), Color(LOAM.r, LOAM.g, LOAM.b, 0.45 * a))
	_plane_ellipse(Vector2.ZERO, (16.0 + 22.0 * t), Color(BARK.r, BARK.g, BARK.b, 0.8 * a), 2.5)
	# Thorns snapping outward and back down.
	for i in range(5):
		var ang := float(i) * TAU / 5.0 + 0.5
		var dir := Vector2(cos(ang), sin(ang) * PLANE_SQUASH)
		var tip: float = (10.0 + 24.0 * t)
		draw_line(dir * 6.0, dir * tip, Color(AMBER.r, AMBER.g, AMBER.b, a), 2.6 * (1.0 - t * 0.5))
	draw_circle(Vector2.ZERO, 4.0 * a, Color(BLOOM.r, BLOOM.g, BLOOM.b, a))

# ── Ultimate: Bloom, the thorned ground ──────────────────────────────────────
# Built to the Tidal Wave bar, because the first pass was not: a flat per-cell
# tint, a cell outline and six frozen sticks. That read as scattered debris, it
# was identical on every cast, nothing moved, and the ultimate had no cast beat
# at all. What Nemi's wave does and this now does too:
#
#   * ONE silhouette. The band is drawn as a single shape with its own
#     perimeter, not as fifteen separate cells that happen to touch.
#   * FOUR tonal layers — deep loam body, inset moss for depth, bramble mass,
#     and a bright growth rim as the focal layer.
#   * PER-CAST SEEDS, so no two thickets are the same.
#   * TWO MOTION LAYERS — a slow sway plus a brighter growth surge that travels
#     across the band — while the footprint stays exactly the damaged cells.
#   * A GROWTH-IN and a WITHER, so the start and the end are both events.
func _draw_bloom_field() -> void:
	var p := _pulse
	# Growth rises over the first half-second; withering takes the last second.
	var grow: float = clampf(elapsed / 0.55, 0.0, 1.0)
	grow = grow * grow * (3.0 - 2.0 * grow)
	var wither: float = clampf((lifetime - elapsed) / 1.0, 0.0, 1.0)
	var a: float = wither
	var scroll: float = elapsed * 0.9

	var edge := PackedVector2Array()
	for pt: Vector2 in perimeter:
		edge.append(to_local(pt))

	# ── Layer 1: deep loam body, the whole band as one mass ──────────────────
	if edge.size() >= 3:
		draw_colored_polygon(edge, Color(LOAM.r, LOAM.g, LOAM.b, 0.62 * a * grow))
		# ── Layer 2: inset moss, for depth under the rim ─────────────────────
		var c := Vector2.ZERO
		for pt2: Vector2 in edge:
			c += pt2
		c /= float(edge.size())
		var inset := PackedVector2Array()
		for pt3: Vector2 in edge:
			inset.append(pt3.lerp(c, 0.11))
		draw_colored_polygon(inset, Color(MOSS.r, MOSS.g, MOSS.b, 0.46 * a * grow))
	else:
		# No perimeter supplied (older callers) — fall back to per-cell fills so
		# the field is never invisible.
		for q in quads:
			var lq := PackedVector2Array()
			for pt4: Vector2 in q:
				lq.append(to_local(pt4))
			if lq.size() >= 3:
				draw_colored_polygon(lq, Color(LOAM.r, LOAM.g, LOAM.b, 0.5 * a * grow))

	# ── Layer 3: the bramble mass ────────────────────────────────────────────
	# Thorns are seeded off their own cell so they stay put, but they SWAY, and a
	# growth surge travels across the band lighting them as it passes.
	var idx := 0
	for local in _field_local:
		if local.size() < 3:
			continue
		var cc := Vector2.ZERO
		for pt6: Vector2 in local:
			cc += pt6
		cc /= float(local.size())
		# Surge position: a bright band sweeping left-to-right, repeatedly.
		var surge: float = 1.0 - clampf(absf(fmod(scroll, 2.2) * 420.0 - 210.0 - cc.x) / 90.0, 0.0, 1.0)
		var sv: float = _seed(idx) * TAU + absf(cc.x * 0.02 + cc.y * 0.05)
		for i in range(7):
			var ang: float = sv + float(i) * 0.92
			var rad: float = 12.0 + fmod(sv * 9.1 + float(i) * 13.7, 19.0)
			var base := cc + Vector2(cos(ang) * rad, sin(ang) * rad * PLANE_SQUASH)
			var h: float = (15.0 + sin(sv + float(i)) * 6.0) * grow
			# Sway: the tip drifts, the base does not — growth bending, not sliding.
			var sway: float = sin(scroll * 1.7 + sv + float(i) * 0.6) * 2.6
			var tip := base + Vector2(sway, -h)
			draw_line(base, tip, Color(LOAM.r, LOAM.g, LOAM.b, 0.55 * a), 4.2)
			draw_line(base, tip, Color(BARK.r, BARK.g, BARK.b, 0.92 * a), 2.6)
			draw_line(base.lerp(tip, 0.5), tip,
					Color(AMBER.r, AMBER.g, AMBER.b, (0.9 + surge * 0.1) * a), 1.9)
			if surge > 0.05 or p > 0.05:
				draw_circle(tip, (1.2 + 1.8 * maxf(surge, p)) * a,
						Color(BLOOM.r, BLOOM.g, BLOOM.b, maxf(surge, p) * 0.9 * a))
		idx += 1

	# ── Layer 4: the bright growth rim, the focal layer ──────────────────────
	if edge.size() >= 3:
		var closed := edge + PackedVector2Array([edge[0]])
		draw_polyline(closed, Color(LOAM.r, LOAM.g, LOAM.b, 0.75 * a), 6.0)
		draw_polyline(closed, Color(AMBER.r, AMBER.g, AMBER.b, (0.85 + p * 0.15) * a), 2.8)
		# On the growth-in, a bright runner races around the perimeter before the
		# thicket fills — the anticipation beat the first version had none of.
		if grow < 0.999:
			var n := closed.size()
			var head: float = grow * float(n - 1)
			var seg := PackedVector2Array()
			for i in range(n):
				if float(i) <= head:
					seg.append(closed[i])
			if seg.size() >= 2:
				draw_polyline(seg, Color(BLOOM.r, BLOOM.g, BLOOM.b, 0.95), 3.4)
				draw_circle(seg[seg.size() - 1], 5.0, BLOOM)

# ── Ultimate: the cast beat ──────────────────────────────────────────────────
# Roots tearing out of the ground at June and running to the band she is raising,
# so the ultimate has a visible source instead of a field that simply appears.
func _draw_bloom_cast() -> void:
	var a := _fade()
	var t: float = clampf(elapsed / lifetime, 0.0, 1.0)
	var dest := to_local(to_world)
	var reach: float = clampf(t / 0.55, 0.0, 1.0)
	reach = reach * reach * (3.0 - 2.0 * reach)
	var g := Vector2(0, _ground_y())
	# Ground heave under June.
	_plane_ellipse(g, (18.0 + 44.0 * t), Color(LOAM.r, LOAM.g, LOAM.b, 0.5 * a))
	_plane_ellipse(g, (20.0 + 48.0 * t), Color(BARK.r, BARK.g, BARK.b, 0.8 * a), 3.0)
	# Five roots racing out toward the band.
	for i in range(5):
		var spread: float = (float(i) - 2.0) * 0.16
		var aim := g.lerp(dest, 1.0)
		var side := (dest - g).orthogonal().normalized() if (dest - g).length() > 0.01 else Vector2.RIGHT
		var target_pt := aim + side * spread * 120.0
		_root_run(g, target_pt, 2.4, a, _seed(i) * TAU + float(i) * 2.3, reach)
	if reach > 0.85:
		draw_circle(dest, 10.0 * a, Color(BLOOM.r, BLOOM.g, BLOOM.b, 0.7 * a))

func _draw_bloom_tick() -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	# Thorns closing around the victim's feet — the tick is a grab, not a blast.
	var g := Vector2(0, _ground_y())
	for i in range(6):
		var ang := float(i) * TAU / 6.0 + 0.25
		var base := g + Vector2(cos(ang), sin(ang) * PLANE_SQUASH) * (30.0 - 12.0 * t)
		draw_line(base, base + Vector2(0, -14.0 * (1.0 - t * 0.4)),
				Color(BARK.r, BARK.g, BARK.b, a), 2.8)
		draw_line(base + Vector2(0, -8.0), base + Vector2(0, -15.0),
				Color(AMBER.r, AMBER.g, AMBER.b, a), 1.8)
	draw_circle(g + Vector2(0, -6.0), 5.0 * a, Color(BLOOM.r, BLOOM.g, BLOOM.b, a * 0.9))
