extends Node2D
class_name SearVFX

# Sear owns SCORCHED EARTH: charcoal ground, deep ember orange, white-hot cores.
# His signature is the ground he has already burned, so the language is BLACKENED
# and COOLING — char that glows in its cracks and fades to ash — rather than
# airborne flame.
#
# The board's other fire users must stay separable:
#   Ember = bright airborne sparks and arrows.
#   Coal  = molten rock, heavy and slow.
#   Sear  = the floor itself is burnt, and it stays burnt.
#
# Everything representing a lasting mechanic draws on the board PLANE (real cell
# quads, squashed ellipses), because the board is a faked-perspective trapezoid
# grid and an axis-aligned overlay visibly floats above it.
enum Mode {
	AUTO_MUZZLE,   # auto attack releases — flame gathering at the cast hand
	AUTO_IMPACT,   # auto attack lands — compact, ~1/3 of a cell
	IGNITE_CAST,   # Ignite: fire gathering and releasing at Sear
	IGNITE_RUN,    # Ignite: the ground fire connecting Sear to the target
	IGNITE_HIT,    # Ignite's dedicated contact (was a shared generic BURN burst)
	SCORCH_TILE,   # persistent: one burning tile of Scorched Path
	BURN_MARK,     # persistent: this unit is on fire, for as long as it burns
	ULT_SPREAD,    # Conflagration: the worst burn reaching another enemy
	ULT_BURST,     # Conflagration: one enemy detonating
}

const CHAR  := Color(0.10, 0.07, 0.06)   # burnt ground — the broad dark body
const EMBER := Color(0.85, 0.30, 0.06)   # deep ember orange, the colour layer
const FLAME := Color(0.99, 0.62, 0.16)   # live flame
const HOT   := Color(1.00, 0.93, 0.72)   # white-hot focal core

## Ground shapes are drawn this much flatter than a circle, matching the board's
## 28-degree pitch closely enough to sit ON the plane.
const PLANE_SQUASH := 0.42

## Above the board art, below every unit. BackgroundLayer and the BattleGrid node
## are siblings at z 0 and units are z_index = 2 + row, so a ground overlay at -1
## renders UNDERNEATH the grass — invisible in the real game. See JuneVFX.
const GROUND_Z := 1

var mode: Mode = Mode.AUTO_IMPACT
var elapsed := 0.0
var lifetime := 0.5
var source: Node2D = null
var target: Node2D = null
var seeds: PackedFloat32Array = PackedFloat32Array()
var _quad_local: PackedVector2Array = PackedVector2Array()

func _roll_seeds() -> void:
	seeds = PackedFloat32Array()
	for i in range(8):
		seeds.append(randf())

func _seed(i: int) -> float:
	return seeds[i % seeds.size()] if not seeds.is_empty() else 0.5

func setup_point(kind: Mode, world_pos: Vector2, life: float = 0.5,
		follow: Node2D = null) -> void:
	mode = kind
	global_position = world_pos
	lifetime = life
	target = follow
	z_index = 7
	_roll_seeds()
	queue_redraw()

func setup_pair(kind: Mode, from: Node2D, to: Node2D, life: float = 0.45) -> void:
	mode = kind
	source = from
	target = to
	lifetime = life
	global_position = from.global_position if (from and is_instance_valid(from)) else Vector2.ZERO
	z_index = 7
	_roll_seeds()
	queue_redraw()

## One burning tile. The quad arrives in GLOBAL coords and is cached in local
## space once — the tile never moves, so it has no business reconverting four
## corners every frame for the whole five seconds it burns.
func setup_tile(cell_quad_global: PackedVector2Array, life: float, centre: Vector2) -> void:
	mode = Mode.SCORCH_TILE
	global_position = centre
	lifetime = life
	z_index = GROUND_Z
	_roll_seeds()
	_quad_local = PackedVector2Array()
	for pt: Vector2 in cell_quad_global:
		_quad_local.append(to_local(pt))
	queue_redraw()

## Persistent "this unit is on fire" tell. Frees itself off the unit's REAL
## burn_time, so it can never advertise a burn that has already expired.
func setup_burn_mark(unit: Node2D) -> void:
	mode = Mode.BURN_MARK
	target = unit
	lifetime = 9999.0
	global_position = unit.global_position
	_roll_seeds()
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	match mode:
		Mode.SCORCH_TILE:
			pass   # fixed to the board; nothing to follow
		Mode.BURN_MARK:
			if not (target and is_instance_valid(target)) or target.current_hp <= 0 \
					or target.burn_time <= 0.0:
				queue_free()
				return
			global_position = target.global_position
			_track_z(target)
		Mode.ULT_SPREAD, Mode.IGNITE_RUN:
			# Source-anchored: these draw FROM the caster/origin TO the victim, so
			# they must sit on the source. The default branch below would pin them
			# to the target and collapse the line to nothing.
			if not (source and is_instance_valid(source)) \
					or not (target and is_instance_valid(target)):
				queue_free()
				return
			global_position = source.global_position
		_:
			if target and is_instance_valid(target):
				global_position = target.global_position
				_track_z(target)
	if elapsed >= lifetime:
		queue_free()
		return
	queue_redraw()

## Units depth-sort by row (z_index = 2 + row, so 2..10 on a 9-row board), which
## means a FIXED effect z of 7 quietly slides behind anything on row 6 or back.
func _track_z(u: Node2D) -> void:
	if u and is_instance_valid(u):
		z_index = u.z_index + 1

## The board-contact line of the unit this effect is attached to. A unit's origin
## sits well above its feet, so ground flame anchored at the origin climbs the
## body instead of sitting on the floor.
func _ground_y() -> float:
	if target and is_instance_valid(target) and target.has_method("ground_offset"):
		return target.ground_offset()
	return 0.0

func _fade() -> float:
	return clampf((lifetime - elapsed) / minf(lifetime, 0.22), 0.0, 1.0)

func _plane_ellipse(centre: Vector2, r: float, col: Color, width: float = -1.0) -> void:
	draw_set_transform(centre, 0.0, Vector2(1.0, PLANE_SQUASH))
	if width < 0.0:
		draw_circle(Vector2.ZERO, r, col)
	else:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, col, width)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## A tongue of flame: dark base, ember body, bright tip. Flames TAPER upward and
## wobble, which is what separates them from Rift's forked lightning and June's
## rigid thorns at a glance.
func _flame(base: Vector2, height: float, width: float, phase: float, a: float) -> void:
	var lean: float = sin(elapsed * 6.0 + phase) * width * 0.5
	var tip := base + Vector2(lean, -height)
	var mid := base + Vector2(lean * 0.4, -height * 0.55)
	var poly := PackedVector2Array([
		base + Vector2(-width, 0.0),
		mid + Vector2(-width * 0.5, 0.0),
		tip,
		mid + Vector2(width * 0.5, 0.0),
		base + Vector2(width, 0.0),
	])
	draw_colored_polygon(poly, Color(EMBER.r, EMBER.g, EMBER.b, 0.75 * a))
	var inner := PackedVector2Array([
		base + Vector2(-width * 0.5, 0.0),
		tip.lerp(base, 0.25),
		base + Vector2(width * 0.5, 0.0),
	])
	draw_colored_polygon(inner, Color(FLAME.r, FLAME.g, FLAME.b, 0.9 * a))
	draw_circle(base, width * 0.45, Color(HOT.r, HOT.g, HOT.b, 0.7 * a))

func _draw() -> void:
	match mode:
		Mode.AUTO_MUZZLE: _draw_auto_muzzle()
		Mode.AUTO_IMPACT: _draw_auto_impact()
		Mode.IGNITE_CAST: _draw_ignite_cast()
		Mode.IGNITE_RUN:  _draw_ignite_run()
		Mode.IGNITE_HIT:  _draw_ignite_hit()
		Mode.SCORCH_TILE: _draw_scorch_tile()
		Mode.BURN_MARK:   _draw_burn_mark()
		Mode.ULT_SPREAD:  _draw_ult_spread()
		Mode.ULT_BURST:   _draw_ult_burst()

# ── Auto attack ──────────────────────────────────────────────────────────────
# He previously had NO caster-side feedback at all: the ranged branch gates its
# particle behind a played-animation flag, and with no model and no sprite sheet
# that flag is always false, so nothing fired.
func _draw_auto_muzzle() -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	draw_circle(Vector2.ZERO, (8.0 + 6.0 * t) * a, Color(EMBER.r, EMBER.g, EMBER.b, 0.35 * a))
	for i in range(4):
		_flame(Vector2((float(i) - 1.5) * 5.0, 0.0), 14.0 * (1.0 - t * 0.4), 3.4,
				_seed(i) * TAU, a)
	draw_circle(Vector2.ZERO, 3.5 * a, Color(HOT.r, HOT.g, HOT.b, a))

# Single-target, so the footprint stays inside roughly a third of a cell — the
# same restraint as Sheildor's bash.
func _draw_auto_impact() -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	var g := Vector2(0, _ground_y())
	_plane_ellipse(g, 10.0 + 22.0 * t, Color(CHAR.r, CHAR.g, CHAR.b, 0.5 * a))
	_plane_ellipse(g, 12.0 + 24.0 * t, Color(EMBER.r, EMBER.g, EMBER.b, 0.85 * a), 2.4)
	for i in range(5):
		var ang := float(i) * TAU / 5.0 + _seed(i)
		var base := g + Vector2(cos(ang), sin(ang) * PLANE_SQUASH) * (8.0 + 18.0 * t)
		_flame(base, 13.0 * (1.0 - t * 0.5), 3.0, _seed(i) * TAU, a)
	draw_circle(g + Vector2(0, -6.0), 4.0 * a, Color(HOT.r, HOT.g, HOT.b, a))

# ── Active: Ignite ───────────────────────────────────────────────────────────
# Was SkillEffect.Type.BURN, one of NINE call sites sharing that effect — plus a
# second copy on the caster from _use_skill's generic tail. Then it was a single
# 0.55s puff, which is not what a 60 MP cast should look like. It is three beats
# now: Sear throws it, fire crosses the ground, the target goes up.
#
# All three start on the SAME frame. Ignite's damage resolves the instant it is
# cast, so a travelling flame with real flight time would put the damage number
# before the visual — the run is drawn already-connected and burns AWAY instead.

## Beat 1 — the cast. Fire gathers low and throws forward off the release.
func _draw_ignite_cast() -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	var g := Vector2(0, _ground_y())
	var swell: float = sin(clampf(t / 0.35, 0.0, 1.0) * PI * 0.5)
	var throw_out: float = clampf((t - 0.3) / 0.7, 0.0, 1.0)
	_plane_ellipse(g, (16.0 + 30.0 * swell) * (1.0 - throw_out * 0.4),
			Color(EMBER.r, EMBER.g, EMBER.b, 0.35 * a))
	for i in range(6):
		var ang := float(i) * TAU / 6.0 + _seed(i)
		var base := g + Vector2(cos(ang), sin(ang) * PLANE_SQUASH) * (10.0 + 14.0 * swell)
		_flame(base, (30.0 + _seed(i) * 12.0) * swell * (1.0 - throw_out * 0.7),
				5.0, _seed(i) * TAU, a)
	draw_circle(g + Vector2(0, -22.0 * swell), (9.0 + 5.0 * swell) * a * (1.0 - throw_out),
			Color(HOT.r, HOT.g, HOT.b, a))

## Beat 2 — the ground fire linking caster to victim. Drawn at full length from
## frame one (see the note above), then burned away from the caster's end so the
## eye is pulled toward the target rather than away from it.
func _draw_ignite_run() -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	var dest := to_local(target.global_position) + Vector2(0, _ground_y())
	var start := Vector2(0, source.ground_offset() if source.has_method("ground_offset") else 0.0)
	# The trailing end eats forward; the head stays pinned on the victim.
	var from := start.lerp(dest, t * 0.8)
	var side := (dest - start).orthogonal().normalized() if (dest - start).length() > 0.01 else Vector2.RIGHT
	var pts := PackedVector2Array()
	for k in range(10):
		var f := float(k) / 9.0
		var wob: float = sin(_seed(0) * 5.0 + f * 8.0 + elapsed * 14.0) * 10.0 * sin(f * PI)
		pts.append(from.lerp(dest, f) + side * wob)
	if pts.size() >= 2:
		draw_polyline(pts, Color(CHAR.r, CHAR.g, CHAR.b, 0.55 * a), 13.0)
		draw_polyline(pts, Color(EMBER.r, EMBER.g, EMBER.b, 0.95 * a), 7.0)
		draw_polyline(pts, Color(FLAME.r, FLAME.g, FLAME.b, a), 3.0)
	# Flames standing up off the line, tallest at the leading end.
	for i in range(5):
		var f2: float = 0.25 + float(i) * 0.18
		var p := from.lerp(dest, f2)
		_flame(p, (16.0 + 14.0 * f2) * (1.0 - t * 0.6), 4.0, _seed(i) * TAU, a * 0.9)

## Beat 3 — the target goes up. A COLUMN, tall and brief, so a single-target burn
## still lands like a real ability without painting an AoE footprint.
func _draw_ignite_hit() -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	var g := Vector2(0, _ground_y())
	var rise: float = 1.0 - t
	# Opening flash: one bright frame-and-a-bit so the contact has a hard accent.
	if t < 0.14:
		var fl: float = 1.0 - t / 0.14
		draw_circle(g + Vector2(0, -34.0), 46.0 * fl, Color(HOT.r, HOT.g, HOT.b, 0.75 * fl))
	# Ground catches, and a shockwave ring runs out and fades.
	_plane_ellipse(g, 16.0 + 30.0 * t, Color(CHAR.r, CHAR.g, CHAR.b, 0.6 * a))
	_plane_ellipse(g, 18.0 + 34.0 * t, Color(EMBER.r, EMBER.g, EMBER.b, 0.95 * a), 4.0 * rise)
	_plane_ellipse(g, 20.0 + 64.0 * t, Color(FLAME.r, FLAME.g, FLAME.b, 0.55 * rise), 2.5)
	# The column: TALL, not wide. A unit renders ~138px, so flame that tops out
	# near 50 read as "feet on fire" rather than engulfed — but widening it would
	# paint an AoE footprint for a single-target burn. The height goes up and the
	# ground rings stay put, which keeps the silhouette narrow and vertical.
	for i in range(9):
		var ang := float(i) * TAU / 9.0 + _seed(i) * 0.5
		var base := g + Vector2(cos(ang), sin(ang) * PLANE_SQUASH) * (7.0 + 13.0 * t)
		_flame(base, (104.0 + _seed(i) * 30.0) * rise, 7.5, _seed(i) * TAU, a)
	for i in range(7):
		var ang2 := float(i) * TAU / 7.0 + 0.4 + _seed(i)
		var base2 := g + Vector2(cos(ang2), sin(ang2) * PLANE_SQUASH) * (24.0 + 20.0 * t)
		_flame(base2, (44.0 + _seed(i) * 18.0) * rise, 4.6, _seed(i) * TAU, a * 0.85)
	# Sparks thrown clear of the column, arcing up and falling back under gravity.
	for i in range(14):
		var sa: float = _seed(i) * TAU + float(i)
		var sp: float = 26.0 + _seed(i) * 60.0
		var sx: float = cos(sa) * sp * t
		var sy: float = -sp * 2.0 * t + 190.0 * t * t
		draw_circle(g + Vector2(sx, sy), (4.5 - 2.4 * t) * a,
				Color(FLAME.r, FLAME.g, FLAME.b, a))
	draw_circle(g + Vector2(0, -62.0 * rise), 15.0 * a * rise, Color(HOT.r, HOT.g, HOT.b, a))

# ── Passive: Scorched Path, persistent ───────────────────────────────────────
# The trail existed only as a manager dictionary — NOTHING drew it anywhere in
# the codebase, so the player had no way to see burning ground they were meant to
# path around. It is drawn as the literal cell it damages, and it COOLS: char
# stays, the cracks dim, so the remaining duration is readable at a glance.
func _draw_scorch_tile() -> void:
	if _quad_local.size() < 3:
		return
	var t: float = clampf(elapsed / lifetime, 0.0, 1.0)
	var heat: float = 1.0 - t                      # embers cool over the tile's life
	var settle: float = clampf(elapsed / 0.3, 0.0, 1.0)
	# Char body: arrives fast and stays dark for the whole burn, so the tile is
	# legible even once the glow has died down.
	draw_colored_polygon(_quad_local, Color(CHAR.r, CHAR.g, CHAR.b, 0.62 * settle))
	# An ember rim on the tile's own edge. This is a POSITIONAL mechanic — the
	# player is being asked which exact squares to avoid — so the boundary has to
	# be unambiguous, not inferred from where the char happens to fade out.
	var rim := _quad_local + PackedVector2Array([_quad_local[0]])
	draw_polyline(rim, Color(CHAR.r, CHAR.g, CHAR.b, 0.7 * settle), 4.0)
	draw_polyline(rim, Color(EMBER.r, EMBER.g, EMBER.b, (0.35 + 0.5 * heat) * settle), 2.0)

	var c := Vector2.ZERO
	for pt: Vector2 in _quad_local:
		c += pt
	c /= float(_quad_local.size())

	# Ember veins: cracks running out from the centre, glowing while hot.
	for i in range(5):
		var ang: float = _seed(i) * TAU + float(i) * 1.25
		var dir := Vector2(cos(ang), sin(ang) * PLANE_SQUASH)
		var pts := PackedVector2Array()
		for k in range(4):
			var f := float(k) / 3.0
			var wob: float = sin(_seed(i) * 9.0 + f * 6.0) * 5.0
			pts.append(c + dir * (f * 34.0 * settle) + dir.orthogonal() * wob)
		draw_polyline(pts, Color(EMBER.r, EMBER.g, EMBER.b, (0.25 + 0.6 * heat) * settle), 3.0)
		draw_polyline(pts, Color(FLAME.r, FLAME.g, FLAME.b, 0.55 * heat * settle), 1.4)
	# Live flame only while the tile is genuinely hot, so a nearly-spent tile
	# reads as ash rather than a threat.
	if heat > 0.35:
		var fa: float = (heat - 0.35) / 0.65
		for i in range(3):
			var ang2: float = _seed(i + 3) * TAU
			var base := c + Vector2(cos(ang2), sin(ang2) * PLANE_SQUASH) * 16.0
			_flame(base, 16.0 * fa, 4.0, _seed(i) * TAU, fa * settle)

# ── Persistent: this unit is on fire ─────────────────────────────────────────
# Burn had no tell at all — STATUS_ICON_SHEETS still contains only "stun", so a
# five-second burn showed nothing but damage numbers ticking up.
func _draw_burn_mark() -> void:
	if not (target and is_instance_valid(target)):
		return
	# Fade out over the burn's last half-second rather than at a fixed lifetime,
	# so the flames die exactly when the damage does.
	var a: float = clampf(target.burn_time / 0.5, 0.0, 1.0)
	var g := Vector2(0, _ground_y())
	_plane_ellipse(g, 20.0, Color(EMBER.r, EMBER.g, EMBER.b, 0.18 * a))
	for i in range(4):
		var x: float = (float(i) - 1.5) * 9.0
		var h: float = 20.0 + sin(elapsed * 5.0 + _seed(i) * TAU) * 5.0
		_flame(g + Vector2(x, 0.0), h, 4.0, _seed(i) * TAU, 0.85 * a)

# ── Ultimate: Conflagration ──────────────────────────────────────────────────
func _draw_ult_spread() -> void:
	var a := _fade()
	var dest := to_local(target.global_position)
	var reach := clampf(elapsed / 0.16, 0.0, 1.0)
	var tip := Vector2.ZERO.lerp(dest, reach)
	# Fire running along the ground from the worst-burning enemy to this one, so
	# "the worst burn SPREADS" is something the player watches happen.
	var pts := PackedVector2Array()
	for k in range(8):
		var f := float(k) / 7.0
		if f > reach:
			break
		var wob: float = sin(_seed(0) * 6.0 + f * 7.0 + elapsed * 9.0) * 9.0 * sin(f * PI)
		pts.append(Vector2.ZERO.lerp(dest, f) + (dest - Vector2.ZERO).orthogonal().normalized() * wob)
	if pts.size() >= 2:
		draw_polyline(pts, Color(CHAR.r, CHAR.g, CHAR.b, 0.6 * a), 8.0)
		draw_polyline(pts, Color(EMBER.r, EMBER.g, EMBER.b, 0.95 * a), 4.5)
		draw_polyline(pts, Color(FLAME.r, FLAME.g, FLAME.b, a), 2.0)
	if reach > 0.9:
		draw_circle(dest, 8.0 * a, Color(HOT.r, HOT.g, HOT.b, 0.8 * a))
	else:
		draw_circle(tip, 5.0 * a, Color(HOT.r, HOT.g, HOT.b, a))

func _draw_ult_burst() -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	var g := Vector2(0, _ground_y())
	var rise: float = 1.0 - t
	_plane_ellipse(g, 18.0 + 30.0 * t, Color(CHAR.r, CHAR.g, CHAR.b, 0.55 * a))
	_plane_ellipse(g, 20.0 + 34.0 * t, Color(EMBER.r, EMBER.g, EMBER.b, a), 3.4 * rise)
	# A column, not a sphere: the detonation goes UP off the burning ground.
	for i in range(8):
		var ang := float(i) * TAU / 8.0 + _seed(i) * 0.5
		var base := g + Vector2(cos(ang), sin(ang) * PLANE_SQUASH) * (10.0 + 22.0 * t)
		_flame(base, (40.0 + _seed(i) * 16.0) * rise, 5.4, _seed(i) * TAU, a)
	draw_circle(g + Vector2(0, -26.0 * (1.0 - t * 0.5)), 10.0 * a * rise,
			Color(HOT.r, HOT.g, HOT.b, a))
