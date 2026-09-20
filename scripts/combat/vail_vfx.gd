extends Node2D
class_name VailVFX

# Vail owns moving AIR: long tapered sweeps, spiral curls, and the single loose
# feather that is her design signature (it is on her portrait and on her Far
# Winds ability icon).
#
# ── WHY IT DOES NOT LOOK LIKE ZOLT ───────────────────────────────────────────
# The first cut of this file borrowed Zolt's THREE-PASS BOLT stroke to solve a
# legibility problem and imported his identity along with it: hard-edged
# polylines carrying a high-frequency jitter term, radial spike bursts, and a
# gold accent all read as LIGHTNING (user report, 2026-09-19). That grammar
# belongs to Zolt and Static — measured, their accents are GOLD(1.0,0.76,0.22)
# and YELLOW(1.0,0.92,0.18), and the `SUN` added here sat right between them.
# Vail is the AIR healer; she cannot share it, and the lightning decade needs it.
#
# What air looks like here instead, following HarpyVFX (this game's existing
# air creature — thin CURVED arcs, soft blue-grey plume, no saturated accent):
#   • TAPERED SWEEPS, not lines. A stroke that thins to nothing at both ends
#     reads as moving air; a constant-width stroke with a bright core reads as
#     a bolt. `_sweep()` builds a POLYGON, not a polyline, for exactly this.
#   • SMOOTH low-frequency curves. The jitter term is gone. Lightning is jagged
#     because it is a discharge; wind is not.
#   • CURLS AND CRESCENTS, not radial spikes. Air moves around things, so
#     bursts expand as nested crescents and `_curl()` provides the spiral.
#   • NO accent hue. Beats are told apart by SHAPE and SCALE. The palette stays
#     cool, which also keeps her clear of the lightning decade's own effects.
#
# The one thing kept from that first cut is the DARK BACKING pass, which is not
# lightning-specific: her decade (11-20, air) has a tile luminance of 203
# against 28-112 for every other biome, and a pale cyan effect there has nothing
# separating it from the floor without it.
enum Mode {
	AURA_PULSE,        # Far Winds  — the +aspd tick on a nearby ally
	GUST_MUZZLE,       # basic attack, at Vail — she is range 4, so it is a cast
	GUST_IMPACT,       # basic attack, at the enemy
	UPDRAFT_LIFT,      # Updraft    — the funnel the ally is whirled up into
	DOWNBURST_MARK,    # Downburst  — pressure gathering above one enemy
	DOWNBURST_SLAM,    # Downburst  — the column lands and rolls outward
	GROUNDED_RESIDUE,  # Downburst  — the lingering slow, pinned at the feet
}

const CORE  := Color(1.0, 1.0, 1.0)
const PALE  := Color(0.86, 0.97, 1.0)
const PLUME := Color(0.58, 0.74, 0.86)   # HarpyVFX's mid tone, the air family
const DEEP  := Color(0.13, 0.24, 0.34)   # backing only, never a silhouette
const GEM   := Color(0.55, 0.85, 1.0)    # her sternum teardrop

var mode: Mode = Mode.AURA_PULSE
var elapsed := 0.0
var lifetime := 0.5
var target: Node2D = null
var _seeds: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_instance_id()) & 0x7fffffff
	for i in range(12):
		_seeds.append(rng.randf())

func setup_point(kind: Mode, world_pos: Vector2, life: float = 0.5,
		follow: Node2D = null) -> void:
	mode = kind
	global_position = world_pos
	lifetime = life
	target = follow
	z_index = 7
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if target and is_instance_valid(target):
		global_position = target.global_position
	if elapsed >= lifetime:
		queue_free()
		return
	queue_redraw()

func _fade() -> float:
	return clampf((lifetime - elapsed) / minf(lifetime, 0.3), 0.0, 1.0)

func _seed(i: int) -> float:
	return _seeds[i % _seeds.size()] if _seeds.size() > 0 else 0.5

# ── Primitives ───────────────────────────────────────────────────────────────

# Build a tapered ribbon polygon around a curve: zero width at both ends, w at
# the middle. THE core shape of this whole file — the taper is what separates
# "a gust" from "a bolt", and it is why these are polygons and not polylines.
func _ribbon(src: PackedVector2Array, w: float) -> Array:
	# Drop consecutive duplicates first: a repeated point gives a zero-length
	# tangent, and a curve that doubles back on itself (a tight _curl) produces
	# a self-intersecting ring the triangulator also rejects.
	var pts := PackedVector2Array()
	for p in src:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 0.01:
			pts.append(p)
	if pts.size() < 3:
		return []
	var n := pts.size()
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in range(n):
		var t := float(i) / float(n - 1)
		var tangent: Vector2
		if i == 0:
			tangent = pts[1] - pts[0]
		elif i == n - 1:
			tangent = pts[n - 1] - pts[n - 2]
		else:
			tangent = pts[i + 1] - pts[i - 1]
		if tangent.length() < 0.0001:
			tangent = Vector2.RIGHT
		var nrm := tangent.normalized().orthogonal()
		# sin() gives a smooth swell that vanishes toward both tips — but it must
		# NOT reach exactly zero. At hw == 0 the top and bottom edges share their
		# endpoint and the ring is degenerate.
		const MIN_HW := 0.35
		var hw: float = maxf(sin(t * PI) * w * 0.5, MIN_HW)
		# CURVATURE CLAMP. Where the curve turns tighter than the ribbon is wide
		# — which a tight `_curl` does constantly — the INNER edge folds back
		# through itself and the ring self-intersects. That, not the tips, is
		# what produced "Invalid polygon data, triangulation failed" once per
		# frame per ribbon. Local turn radius ~= segment length / turn angle;
		# staying under three-quarters of it keeps the inner edge convex.
		if i > 0 and i < n - 1:
			var v1 := pts[i] - pts[i - 1]
			var v2 := pts[i + 1] - pts[i]
			var turn: float = absf(v1.angle_to(v2))
			if turn > 0.0001:
				var radius: float = minf(v1.length(), v2.length()) / turn
				hw = minf(hw, maxf(radius * 0.75, MIN_HW))
		top.append(pts[i] + nrm * hw)
		bot.append(pts[i] - nrm * hw)
	return [top, bot]

# Three nested tapered ribbons: wide dark backing, mid plume, pale centre.
#
# Tuned once, here, rather than per beat. Switching from hard-edged bolt strokes
# to tapered ribbons cost real presence — measured on the air board, coverage
# fell from 5977 ink px to 4308 and mean contrast from 51 to 33 — because a
# taper gives up hard edges by design. The answer is MORE RIBBON, not a harder
# edge: widening here recovers the mass without touching the grammar that makes
# it read as air rather than as lightning.
func _layered(pts: PackedVector2Array, w: float, alpha: float) -> void:
	if alpha <= 0.004 or w <= 0.0:
		return
	_poly(_ribbon(pts, w * 2.5), Color(DEEP.r, DEEP.g, DEEP.b, alpha * 0.72))
	_poly(_ribbon(pts, w * 1.55), Color(PLUME.r, PLUME.g, PLUME.b, alpha * 0.95))
	_poly(_ribbon(pts, w * 0.62), Color(PALE.r, PALE.g, PALE.b, alpha))

# Draw the ribbon as one convex QUAD PER SEGMENT rather than as a single ring.
#
# A ring is the obvious shape and it cannot be made to work here: a spiral of
# more than half a turn overlaps a DISTANT part of itself, which is global
# self-intersection, and `draw_colored_polygon` needs a simple polygon. A local
# curvature clamp fixes the inner-edge fold but cannot see that case. Per-segment
# quads are always convex, so they always triangulate, at the cost of a faint
# seam where two quads overlap at a joint — invisible at these alphas.
func _poly(edges: Array, col: Color) -> void:
	if edges.size() != 2:
		return
	var top: PackedVector2Array = edges[0]
	var bot: PackedVector2Array = edges[1]
	# TWO TRIANGLES per segment, not one quad. Where the curve's tangent
	# reverses, the two edges cross and the quad becomes a BOWTIE, which is
	# self-intersecting and fails to triangulate just like the ring did. A
	# triangle cannot self-intersect, so this is the end of that whole class of
	# error.
	for i in range(top.size() - 1):
		_tri(top[i], top[i + 1], bot[i + 1], col)
		_tri(top[i], bot[i + 1], bot[i], col)

func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	# Skip slivers: a zero-area triangle is also rejected by the triangulator.
	if absf((b - a).cross(c - a)) < 0.01:
		return
	draw_colored_polygon(PackedVector2Array([a, b, c]), col)

# A long smooth curved sweep of air. No jitter: a single low-frequency bow, so
# it reads as flow rather than as a discharge.
func _sweep(from: Vector2, to: Vector2, bow: float, w: float, alpha: float) -> void:
	var side := (to - from).normalized().orthogonal()
	var pts := PackedVector2Array()
	for i in range(14):
		var t := float(i) / 13.0
		pts.append(from.lerp(to, t) + side * sin(t * PI) * bow)
	_layered(pts, w, alpha)

# A spiral curl. Air curls around things; this is the motif that most separates
# her from anything electrical.
func _curl(centre: Vector2, r0: float, r1: float, turns: float, phase: float,
		w: float, alpha: float, squash: float = 1.0) -> void:
	var pts := PackedVector2Array()
	for i in range(22):
		var t := float(i) / 21.0
		var ang := phase + t * TAU * turns
		var r: float = lerpf(r0, r1, t)
		pts.append(centre + Vector2(cos(ang) * r, sin(ang) * r * squash))
	_layered(pts, w, alpha)

# A crescent sweep on the ground plane. Bursts expand as nested crescents
# rather than as radiating spikes. Default squash matches the board's fake
# 28-degree perspective, so a ground crescent lies flat instead of standing up.
func _crescent(r: float, from_ang: float, span: float, w: float, alpha: float,
		squash: float = 0.42) -> void:
	var pts := PackedVector2Array()
	for i in range(18):
		var t := float(i) / 17.0
		var ang := from_ang + span * t
		pts.append(Vector2(cos(ang) * r, sin(ang) * r * squash))
	_layered(pts, w, alpha)

# Her signature: one loose feather, tumbling. Small, never more than two.
func _feather(at: Vector2, ang: float, scale: float, alpha: float) -> void:
	var quill := Vector2.from_angle(ang) * 10.0 * scale
	var perp := quill.orthogonal().normalized() * 4.0 * scale
	draw_line(at - quill, at + quill, Color(DEEP.r, DEEP.g, DEEP.b, alpha * 0.6), 4.0 * scale)
	draw_line(at - quill, at + quill, Color(PALE.r, PALE.g, PALE.b, alpha), 2.0 * scale)
	draw_line(at, at + perp - quill * 0.3, Color(CORE.r, CORE.g, CORE.b, alpha * 0.8), 1.3 * scale)
	draw_line(at, at - perp - quill * 0.3, Color(CORE.r, CORE.g, CORE.b, alpha * 0.8), 1.3 * scale)

func _draw() -> void:
	match mode:
		Mode.AURA_PULSE:       _draw_aura_pulse()
		Mode.GUST_MUZZLE:      _draw_gust_muzzle()
		Mode.GUST_IMPACT:      _draw_gust_impact()
		Mode.UPDRAFT_LIFT:     _draw_updraft_lift()
		Mode.DOWNBURST_MARK:   _draw_downburst_mark()
		Mode.DOWNBURST_SLAM:   _draw_downburst_slam()
		Mode.GROUNDED_RESIDUE: _draw_grounded_residue()

# ── Far Winds: a tailwind pushing a nearby ally ──────────────────────────────
# Reads as SPEED: long sweeps overtake the ally from behind, a feather rides past.
func _draw_aura_pulse() -> void:
	var a := _fade()
	var t: float = elapsed / lifetime
	for i in range(3):
		var y := -12.0 - float(i) * 15.0
		var phase: float = fmod(t * 1.5 + _seed(i), 1.0)
		var x0 := -52.0 + phase * 74.0
		_sweep(Vector2(x0, y), Vector2(x0 + 56.0, y - 6.0), 7.0, 8.5,
			a * 0.9 * sin(phase * PI))
	_curl(Vector2(-30.0, -20.0), 4.0, 17.0, 0.7, elapsed * 2.0, 5.5, a * 0.8, 0.6)
	_feather(Vector2(26.0 - t * 34.0, -34.0 - sin(t * TAU) * 9.0),
		-0.5 + sin(t * TAU) * 0.5, 1.15, a)

# ── Basic attack, at Vail: air gathers into her open palms ───────────────────
# Curls spiralling inward, not spokes converging — the difference between wind
# being drawn in and a spark gap.
func _draw_gust_muzzle() -> void:
	var a := _fade()
	var t: float = elapsed / lifetime
	var pull: float = 1.0 - t
	for i in range(3):
		var phase := float(i) * TAU / 3.0 + elapsed * 3.0
		_curl(Vector2(0, -16), 10.0 + 26.0 * pull, 6.0, 0.55, phase, 7.5, a * 0.9, 0.75)
	draw_circle(Vector2(0, -16), 8.0 * (0.4 + t * 0.6), Color(GEM.r, GEM.g, GEM.b, a * 0.5))
	draw_circle(Vector2(0, -16), 3.5, Color(CORE.r, CORE.g, CORE.b, a * 0.9))

# ── Basic attack, at the enemy: a crescent of cutting wind ───────────────────
func _draw_gust_impact() -> void:
	var a := _fade()
	var t: float = elapsed / lifetime
	for i in range(3):
		var r := (26.0 + 30.0 * t) - float(i) * 9.0
		_crescent(r, -2.5 + float(i) * 0.18, 2.0, 9.5 - float(i) * 1.8,
			a * (1.0 - t * 0.35) * (1.0 - float(i) * 0.18), 0.85)
	_feather(Vector2(18.0 + t * 14.0, -16.0 - t * 18.0), 0.7 + t, 0.9, a * 0.8)

# ── Updraft: the funnel the ally is lifted into ──────────────────────────────
# A continuous helix climbing the ally, held for the whole lift.
func _draw_updraft_lift() -> void:
	var a: float = minf(1.0, elapsed / 0.18) * _fade()
	var spin := elapsed * 3.0
	var height := 132.0
	for s in range(2):
		var pts := PackedVector2Array()
		for i in range(26):
			var t := float(i) / 25.0
			var ang := spin + float(s) * PI + t * TAU * 1.6
			var r: float = 40.0 * (1.0 - t * 0.7)
			pts.append(Vector2(cos(ang) * r, -t * height + sin(ang) * r * 0.32))
		_layered(pts, 9.0, a)
	for i in range(7):
		var climb: float = fmod(elapsed * 1.3 + _seed(i), 1.0)
		var r2: float = 34.0 * (1.0 - climb * 0.7) * (0.65 + _seed(i + 3) * 0.35)
		var ang2 := spin * 1.4 + _seed(i) * TAU
		draw_circle(Vector2(cos(ang2) * r2, -climb * height + sin(ang2) * r2 * 0.32),
			2.8 * (1.0 - climb * 0.5), Color(CORE.r, CORE.g, CORE.b, a * (1.0 - climb)))
	_crescent(44.0, -0.4, 3.6, 7.0, a * 0.8)
	_feather(Vector2(sin(elapsed * 2.0) * 28.0, -height * 0.78), elapsed * 1.4, 1.2, a)

# ── Downburst, beat 1: pressure gathers overhead ─────────────────────────────
func _draw_downburst_mark() -> void:
	var a := _fade()
	var charge: float = clampf(elapsed / lifetime, 0.0, 1.0)
	var y := -150.0 + charge * 26.0
	# A flattening cloud mass, built from overlapping soft arcs rather than
	# storm-cloud discs (those belong to Zolt's ULT_MARK).
	for i in range(3):
		var cx := (float(i) - 1.0) * 30.0
		var pts := PackedVector2Array()
		for j in range(16):
			var t := float(j) / 15.0
			pts.append(Vector2(cx - 34.0 + t * 68.0, y + sin(t * PI) * -13.0))
		_poly(_ribbon(pts, 26.0 - charge * 7.0),
			Color(DEEP.r, DEEP.g, DEEP.b, 0.40 * a))
		_poly(_ribbon(pts, 15.0 - charge * 5.0),
			Color(PLUME.r, PLUME.g, PLUME.b, 0.55 * a))
	for i in range(2):
		_curl(Vector2((float(i) - 0.5) * 34.0, y + 34.0 + 30.0 * charge),
			14.0, 5.0, 0.6, elapsed * 2.2 + float(i) * PI, 5.0, a * 0.7 * charge, 0.8)
	_crescent(22.0 + charge * 34.0, -0.3, 3.7, 4.5, a * 0.55 * charge)

# ── Downburst, beat 2: the column lands and rolls outward ────────────────────
# A ROLL, not a shockwave of spikes: nested crescents chase each other outward
# along the floor, which is how a downburst actually spreads.
func _draw_downburst_slam() -> void:
	var a := _fade()
	var drop: float = clampf(elapsed / 0.12, 0.0, 1.0)
	if drop < 1.0:
		var pts := PackedVector2Array()
		for i in range(16):
			var t := float(i) / 15.0
			pts.append(Vector2(sin(t * PI) * 9.0, -168.0 + 168.0 * drop * t))
		_layered(pts, 20.0, a)
	else:
		var shock: float = clampf((elapsed - 0.12) / maxf(lifetime - 0.12, 0.01), 0.0, 1.0)
		var ia: float = (1.0 - shock) * a
		for i in range(3):
			var lag: float = maxf(shock - float(i) * 0.16, 0.0)
			var r: float = 22.0 + 116.0 * lag
			var wid: float = 14.0 - float(i) * 3.0
			var al: float = ia * (1.0 - float(i) * 0.22)
			_crescent(r, -3.05, TAU * 0.46, wid, al)
			_crescent(r, 0.09, TAU * 0.46, wid, al)
		# Curls kicked up at the spreading front — the signature of a downburst.
		for i in range(2):
			var sx: float = (-1.0 if i == 0 else 1.0) * (34.0 + 96.0 * shock)
			_curl(Vector2(sx, -6.0), 6.0, 20.0, 0.8,
				elapsed * 3.0 + float(i) * PI, 8.0, ia * 0.95, 0.8)
		draw_circle(Vector2.ZERO, 20.0 * ia, Color(PALE.r, PALE.g, PALE.b, ia * 0.6))

# ── Downburst, lingering: grounded. Pinned down, 35% slower ──────────────────
func _draw_grounded_residue() -> void:
	var a: float = minf(1.0, elapsed / 0.12) * _fade()
	var pulse: float = 0.55 + 0.45 * sin(elapsed * 3.0)
	# A slow pair of crescents orbiting the feet: present for the whole five
	# seconds without competing with the unit it is attached to.
	_crescent(31.0, elapsed * 0.9, TAU * 0.42, 7.0, a * 0.85 * pulse)
	_crescent(31.0, elapsed * 0.9 + PI, TAU * 0.42, 7.0, a * 0.85 * pulse)
	for i in range(2):
		_curl(Vector2(cos(elapsed * 0.9 + float(i) * PI) * 30.0,
				sin(elapsed * 0.9 + float(i) * PI) * 30.0 * 0.42),
			3.0, 11.0, 0.6, elapsed * 2.0, 4.8, a * 0.8, 0.8)
