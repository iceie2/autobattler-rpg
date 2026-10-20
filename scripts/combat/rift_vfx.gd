extends Node2D
class_name RiftVFX

# Rift owns PURPLE LIGHTNING: the same forked-discharge language as Zolt's storm
# and Static's grid, but in void violet rather than celestial blue-white — so the
# three lightning heroes stay instantly separable in a crowded fight.
#
#   Zolt   = royal blue + gold, sky-to-ground, cloud mass.
#   Static = cyan, grid-aligned, geometric and mechanical.
#   Rift   = violet/magenta, space TEARING — every shape either implodes inward
#            or splits open along a seam. Nothing here expands for its own sake.
#
# Layering follows the house rule: broad low-alpha body, readable color layer,
# bright focal core.
enum Mode {
	AUTO_MUZZLE,     # auto attack releases — discharge off the casting hand
	AUTO_IMPACT,     # auto attack lands — compact implosion, ~1/3 of a grid cell
	BACKLASH_AURA,   # persistent: Rift's passive is armed (follows him, lives 9999)
	BACKLASH_ARC,    # one Backlash proc — Rift -> the enemy that ate the redirect
	TEAR_SEAM,       # Tear: space splits open at a cell (origin AND destination)
	COLLAPSE_WELL,   # Collapse: the centre void well, telegraph -> implosion
	COLLAPSE_DRAG,   # Collapse: one enemy's streak from where it stood to centre
	PORTAL_IN,       # Tear: the mouth the victim FALLS INTO, at the old tile
	PORTAL_OUT,      # Tear: the mouth the victim DROPS OUT OF, at the new tile
}

const VOID  := Color(0.10, 0.01, 0.24)   # near-black indigo — the broad body
const DEEP  := Color(0.30, 0.04, 0.62)   # mid violet
const ARC   := Color(0.62, 0.16, 1.00)   # the readable colour layer
const CORE  := Color(0.96, 0.78, 1.00)   # hot magenta-white focal core

## Backlash is a small, constant chip of redirected damage, and its aura is the
## one Rift effect that is on screen ALL the time. It earns a tell, not a share
## of the attention his abilities get, so the whole passive — persistent aura and
## proc arc alike — renders at half alpha. One knob so the two never drift apart.
const PASSIVE_ALPHA := 0.5

var mode: Mode = Mode.AUTO_IMPACT
var elapsed := 0.0
var lifetime := 0.4
var source: Node2D = null
var target: Node2D = null
var from_world := Vector2.ZERO
var to_world := Vector2.ZERO
var _pulse := 0.0          # BACKLASH_AURA: brief brighten when the passive fires

func setup_point(kind: Mode, world_pos: Vector2, life: float = 0.4,
		follow: Node2D = null) -> void:
	mode = kind
	global_position = world_pos
	lifetime = life
	target = follow
	# House layering: ground marks sit at z 1 (over the grass, UNDER the units,
	# matching JuneVFX.GROUND_Z) so the body visibly sinks INTO the mouth instead
	# of the mouth being painted over the body. Everything else stays at 7.
	z_index = 1 if kind in [Mode.PORTAL_IN, Mode.PORTAL_OUT] else 7
	queue_redraw()

func setup_pair(kind: Mode, from: Node2D, to: Node2D, life: float = 0.34) -> void:
	mode = kind
	source = from
	target = to
	lifetime = life
	global_position = from.global_position if (from and is_instance_valid(from)) else Vector2.ZERO
	z_index = 7
	queue_redraw()

func setup_streak(kind: Mode, start: Vector2, finish: Vector2, life: float = 0.30) -> void:
	mode = kind
	from_world = start
	to_world = finish
	global_position = start
	lifetime = life
	z_index = 6
	queue_redraw()

## BACKLASH_AURA only: a proc just fired — flare the ring for a moment. The aura
## itself is persistent, so it is never respawned per hit (that would stack a new
## node on every point of damage Rift takes).
func pulse() -> void:
	_pulse = 1.0

## Battle clock, matching CrossVFX/DocVFX/BouncerInhaleVFX. RiftVFX ran on RAW
## delta until 2026-10-01, so every effect played at real speed no matter what
## the pace control said: at 0.25x the board crawled and the Tear portals still
## flashed past in a third of a second, which is exactly how the owner found it.
## Returns 0 while paused so an effect cannot age behind a pause screen either.
func _clock() -> float:
	var src: Node2D = source if source and is_instance_valid(source) else target
	var bm = src.get("battle_manager") if src and is_instance_valid(src) else null
	if bm == null:
		return 1.0
	if bm.get("paused"):
		return 0.0
	return float(bm.get("time_scale")) if bm.get("time_scale") != null else 1.0

func _process(delta: float) -> void:
	var dt: float = delta * _clock()
	elapsed += dt
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - dt * 3.2)
	if mode == Mode.BACKLASH_AURA:
		# Self-freeing: the aura advertises a passive that only a living Rift has.
		if not (target and is_instance_valid(target)) or target.current_hp <= 0:
			queue_free()
			return
		global_position = target.global_position
	elif mode == Mode.BACKLASH_ARC:
		if not (source and is_instance_valid(source)) or not (target and is_instance_valid(target)):
			queue_free()
			return
		global_position = source.global_position
	elif target and is_instance_valid(target):
		global_position = target.global_position
	if elapsed >= lifetime:
		queue_free()
		return
	queue_redraw()

func _fade() -> float:
	return clampf((lifetime - elapsed) / minf(lifetime, 0.22), 0.0, 1.0)

## One forked violet discharge. Same three-pass build as ZoltVFX._bolt (dark
## spread, colour body, white-hot filament) so Rift reads as the same PHENOMENON
## as the other lightning heroes while never sharing their palette.
func _bolt(from: Vector2, to: Vector2, width: float, alpha: float, seed: float = 0.0,
		jag: float = 9.0) -> void:
	var dir := to - from
	if dir.length() < 0.01:
		return
	var side := dir.normalized().orthogonal()
	var points := PackedVector2Array()
	for i in range(10):
		var t := float(i) / 9.0
		var jitter := sin(seed + float(i) * 8.71 + elapsed * 47.0) * jag * sin(t * PI)
		points.append(from.lerp(to, t) + side * jitter)
	draw_polyline(points, Color(VOID.r, VOID.g, VOID.b, alpha * 0.55), width * 3.4)
	draw_polyline(points, Color(ARC.r, ARC.g, ARC.b, alpha), width * 1.8)
	draw_polyline(points, Color(CORE.r, CORE.g, CORE.b, alpha), width)

func _draw() -> void:
	match mode:
		Mode.AUTO_MUZZLE:   _draw_auto_muzzle()
		Mode.AUTO_IMPACT:   _draw_auto_impact()
		Mode.BACKLASH_AURA: _draw_backlash_aura()
		Mode.BACKLASH_ARC:  _draw_backlash_arc()
		Mode.TEAR_SEAM:     _draw_tear_seam()
		Mode.PORTAL_IN:     _draw_portal(true)
		Mode.PORTAL_OUT:    _draw_portal(false)
		Mode.COLLAPSE_WELL: _draw_collapse_well()
		Mode.COLLAPSE_DRAG: _draw_collapse_drag()

# ── Auto attack muzzle ────────────────────────────────────────────────────────
# Fires on the authored release frame (spawn_delay = 0.34 of the live attack
# interval, shared with the projectile), so the discharge and the bolt leaving
# the hand are the same beat at every attack speed.
func _draw_auto_muzzle() -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	draw_circle(Vector2.ZERO, (9.0 + 7.0 * t) * a, Color(VOID.r, VOID.g, VOID.b, 0.4 * a))
	for i in range(5):
		var ang := float(i) * TAU / 5.0 + elapsed * 6.0
		_bolt(Vector2.ZERO, Vector2.from_angle(ang) * (10.0 + 17.0 * t), 1.3, a,
				float(i) * 6.0, 4.5)
	draw_circle(Vector2.ZERO, 4.0 * a, Color(CORE.r, CORE.g, CORE.b, a))

# ── Auto attack impact ────────────────────────────────────────────────────────
# Deliberately COMPACT: the auto is a single-target 2-range poke, so its visual
# footprint stays inside roughly a third of a 110px cell. Same restraint as
# Sheildor's bash — a single-target hit must never paint like an AoE.
func _draw_auto_impact() -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	# Space closing back up: the ring travels INWARD, the opposite of every
	# expanding shockwave on the board, which is what sells "void" over "blast".
	var r: float = 34.0 * (1.0 - t) + 6.0
	draw_circle(Vector2.ZERO, r * 0.9, Color(VOID.r, VOID.g, VOID.b, 0.30 * a))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(ARC.r, ARC.g, ARC.b, 0.85 * a), 2.5)
	for i in range(6):
		var ang := float(i) * TAU / 6.0 + sin(float(i) * 2.3) * 0.2
		var dir := Vector2.from_angle(ang)
		_bolt(dir * (r + 4.0), dir * 5.0, 1.4, a, float(i) * 7.0, 4.0)
	draw_circle(Vector2.ZERO, (3.0 + 5.0 * (1.0 - t)) * a, Color(CORE.r, CORE.g, CORE.b, a))

# ── Passive: Backlash, persistent ─────────────────────────────────────────────
# Backlash is always on, so it gets a permanent tell. Kept low-alpha and small
# on purpose: it must say "this one redirects" without competing with the
# abilities that actually resolve.
func _draw_backlash_aura() -> void:
	var p := _pulse
	var base_a: float = (0.26 + p * 0.55) * PASSIVE_ALPHA
	var r: float = 30.0 + p * 5.0
	draw_circle(Vector2(0, -6.0), r * 0.72,
			Color(VOID.r, VOID.g, VOID.b, (0.10 + p * 0.16) * PASSIVE_ALPHA))
	for i in range(3):
		var ang := elapsed * 1.7 + float(i) * TAU / 3.0
		var span := 0.7 + sin(elapsed * 3.1 + float(i)) * 0.14
		draw_arc(Vector2(0, -6.0), r, ang, ang + span, 14,
				Color(ARC.r, ARC.g, ARC.b, base_a), 2.2 + p * 1.6)
		var tip := Vector2(0, -6.0) + Vector2.from_angle(ang + span) * r
		draw_circle(tip, 2.0 + p * 2.0,
				Color(CORE.r, CORE.g, CORE.b, base_a + 0.2 * PASSIVE_ALPHA))

# ── Passive: one redirect proc ────────────────────────────────────────────────
# Fires FROM Rift TO the enemy that took the redirected damage, so the stray
# damage number on the far side of the board finally has a visible cause.
func _draw_backlash_arc() -> void:
	var a := _fade() * PASSIVE_ALPHA
	var reveal := clampf(elapsed / 0.10, 0.0, 1.0)
	var dest := to_local(target.global_position)
	var tip := Vector2.ZERO.lerp(dest, reveal)
	_bolt(Vector2(0, -6.0), tip, 2.6, a, 3.0, 11.0)
	# A second thinner fork sells discharge rather than a drawn beam.
	_bolt(Vector2(0, -6.0), tip, 1.2, a * 0.7, 19.0, 17.0)
	if reveal > 0.9:
		# The landing seed keeps its size — it is what ties the remote damage
		# number to Rift — but fades with everything else.
		draw_circle(dest, 13.0 * a, Color(ARC.r, ARC.g, ARC.b, 0.30 * a))
		draw_circle(dest, 5.0, Color(CORE.r, CORE.g, CORE.b, a))

# ── Active: Tear ──────────────────────────────────────────────────────────────
# A vertical seam that splits open and snaps shut. Spawned at BOTH ends of the
# banish, so the player can read where the target went instead of seeing it
# vanish and reappear across the board.
func _draw_tear_seam() -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	# Open fast, hold, snap shut — the hold is what makes the destination legible.
	var open: float = sin(clampf(t / 0.28, 0.0, 1.0) * PI * 0.5) if t < 0.28 \
			else (1.0 - clampf((t - 0.62) / 0.38, 0.0, 1.0))
	var h: float = 54.0
	var w: float = 17.0 * open
	if w > 0.2:
		var lens := PackedVector2Array()
		for i in range(11):
			var f := float(i) / 10.0
			lens.append(Vector2(w * sin(f * PI), -h * 0.5 + h * f))
		for i in range(11):
			var f := float(10 - i) / 10.0
			lens.append(Vector2(-w * sin(f * PI), -h * 0.5 + h * f))
		draw_colored_polygon(lens, Color(VOID.r, VOID.g, VOID.b, 0.88 * a))
		draw_polyline(lens, Color(DEEP.r, DEEP.g, DEEP.b, 0.9 * a), 3.0)
	# Crackle running the length of the split.
	for i in range(3):
		var off := (float(i) - 1.0) * 4.0
		_bolt(Vector2(off, -h * 0.5), Vector2(off, h * 0.5), 1.5,
				a * (0.55 + 0.45 * open), float(i) * 13.0, 6.0 * open)
	draw_line(Vector2(0, -h * 0.5), Vector2(0, h * 0.5), Color(CORE.r, CORE.g, CORE.b, a), 1.6)

## Tear's two mouths (owner 2026-10-01: "a portal under the enemy, they fall in,
## then fall out a new portal at the new location"). A flat ellipse on the GROUND,
## not the old vertical seam -- you have to believe a body can go DOWN through it.
##
## The ellipse is foreshortened to 0.42 of its width because the board fakes a
## 28 deg downward tilt (BoardPerspective.PITCH_DEG); a true circle would read as
## a disc standing upright in the grass.
##
## IN opens fast and holds while the victim is still falling through it; OUT
## holds, then snaps shut behind them. An iris curve drives the radius, so the
## mouth DILATES rather than fading in -- that is what reads as an opening.
func _draw_portal(is_entry: bool) -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	var iris: float
	if is_entry:
		iris = sin(clampf(t / 0.22, 0.0, 1.0) * PI * 0.5) - clampf((t - 0.70) / 0.30, 0.0, 1.0)
	else:
		iris = sin(clampf(t / 0.16, 0.0, 1.0) * PI * 0.5) - clampf((t - 0.74) / 0.26, 0.0, 1.0)
	iris = clampf(iris, 0.0, 1.0)
	if iris <= 0.01:
		return
	# Sized against the board, not by eye: BackgroundLayer.CELL is 110, and a mouth
	# a whole unit drops through has to read as most of the tile it is under. 30.0
	# was 55% of a cell wide and the owner could not pick it out at 0.25x pace.
	var rx: float = 46.0 * iris
	var ry: float = rx * 0.42
	var ring := PackedVector2Array()
	for i in range(29):
		var th := TAU * float(i) / 28.0
		ring.append(Vector2(cos(th) * rx, sin(th) * ry))
	# The mouth is a HOLE, so its body is the broad near-black void.
	draw_colored_polygon(ring, Color(VOID.r, VOID.g, VOID.b, 0.92 * a))
	draw_polyline(ring, Color(DEEP.r, DEEP.g, DEEP.b, 0.95 * a), 3.0)
	# An inset hot lip, so the rim reads as depth rather than a flat disc.
	var lip := PackedVector2Array()
	for i in range(29):
		var th2 := TAU * float(i) / 28.0
		lip.append(Vector2(cos(th2) * rx * 0.62, sin(th2) * ry * 0.62))
	draw_polyline(lip, Color(ARC.r, ARC.g, ARC.b, 0.55 * a), 2.0)
	# Forked discharge spitting off the rim -- the house language, kept sparse so
	# the mouth stays the subject.
	for i in range(5):
		var th3 := TAU * (float(i) / 5.0) + (0.6 if is_entry else -0.6)
		var p0 := Vector2(cos(th3) * rx * 0.9, sin(th3) * ry * 0.9)
		var p1 := Vector2(cos(th3) * rx * 1.5, sin(th3) * ry * 1.5 - 11.0 * iris)
		_bolt(p0, p1, 1.6, a * 0.8 * iris, float(i) * 7.0, 5.0 * iris)
	draw_line(Vector2(-rx * 0.5, 0.0), Vector2(rx * 0.5, 0.0),
			Color(CORE.r, CORE.g, CORE.b, 0.5 * a * iris), 1.4)

# ── Ultimate: Collapse ────────────────────────────────────────────────────────
# Telegraph -> convergence -> implosion. The footprint is honestly board-wide
# because the gameplay footprint is every enemy on the field.
func _draw_collapse_well() -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	if t < 0.30:
		# Telegraph: a ring closing in, warning where the board is about to fold.
		var p := t / 0.30
		var r: float = 230.0 * (1.0 - p * 0.55)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(ARC.r, ARC.g, ARC.b, 0.55 * p), 3.0)
		for i in range(8):
			var ang := float(i) * TAU / 8.0
			var outer := Vector2.from_angle(ang) * r
			draw_line(outer * 0.86, outer, Color(DEEP.r, DEEP.g, DEEP.b, 0.8 * p), 2.5)
		draw_circle(Vector2.ZERO, 14.0 * p, Color(VOID.r, VOID.g, VOID.b, 0.55 * p))
	elif t < 0.62:
		# Convergence: arcs spiral inward into the well.
		var p := (t - 0.30) / 0.32
		draw_circle(Vector2.ZERO, 30.0 + 26.0 * p, Color(VOID.r, VOID.g, VOID.b, 0.38))
		for i in range(10):
			var ang := float(i) * TAU / 10.0 + p * 2.4
			var far := Vector2.from_angle(ang) * (200.0 * (1.0 - p) + 40.0)
			var near := Vector2.from_angle(ang + 0.5) * 16.0
			_bolt(far, near, 2.0, 0.85, float(i) * 5.0, 10.0)
		draw_circle(Vector2.ZERO, 9.0 + 7.0 * p, Color(CORE.r, CORE.g, CORE.b, 0.9))
	else:
		# Implosion: the one bright beat, where the damage has just landed.
		var p := (t - 0.62) / 0.38
		var ia := (1.0 - p) * a
		# The void body stays translucent on purpose: at full opacity it hid the
		# units and HP bars standing under the well, which is where the player is
		# looking when the ultimate lands.
		draw_circle(Vector2.ZERO, 64.0 * (1.0 - p * 0.4), Color(VOID.r, VOID.g, VOID.b, 0.42 * ia))
		draw_circle(Vector2.ZERO, 26.0 * ia, Color(CORE.r, CORE.g, CORE.b, 0.9 * ia))
		draw_arc(Vector2.ZERO, 40.0 + 150.0 * p, 0.0, TAU, 56,
				Color(ARC.r, ARC.g, ARC.b, ia), 6.0 * ia)
		for i in range(10):
			var ang := float(i) * TAU / 10.0 + sin(float(i) * 4.4) * 0.2
			_bolt(Vector2.ZERO, Vector2.from_angle(ang) * (60.0 + 120.0 * p), 1.8, ia, float(i) * 9.0)

func _draw_collapse_drag() -> void:
	var a := _fade()
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	var dest := to_local(to_world)
	# The tail retracts toward the well, so the eye follows the enemy inward
	# rather than seeing it teleport.
	var tail := Vector2.ZERO.lerp(dest, t * 0.85)
	_bolt(tail, dest, 2.2, a * (1.0 - t * 0.5), 2.0, 8.0)
	draw_circle(tail, 6.0 * a, Color(ARC.r, ARC.g, ARC.b, 0.55 * a))
