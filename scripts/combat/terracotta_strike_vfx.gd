extends Node2D
class_name TerracottaStrikeVFX

# One-shot effects for the Terracotta Colossus (2026-09-30). The persistent wall
# of slabs lives in TerracottaVFX; this is everything that happens in a moment:
#
#   WINDUP   the slam gathering — rings converging at its feet, armour plates
#            sliding out from the torso, both green eyes flaring. A legibility
#            cue (the fight is an autobattle: nobody can dodge it), not counterplay.
#   IMPACT   the slam landing — a crack racing along the floor to the victim,
#            dust ring, flung brick shards. Bigger and more of it the more
#            hardened the Colossus is, so "Weight of Stone" visibly gets heavier.
#   HIT      a blow landing ON it. Early on: clay chips flying off. Once it is
#            hardened: hard steel sparks pinging away instead — so how tough it
#            has become is readable from the hit feedback alone. `eroded` adds a
#            dark wet stain and crumbling flakes: Water/Air just stripped armour.
#   BOULDER  the thrown plate of its own armour, tumbling across the board in an
#            arc with a dust trail and a shadow on the ground beneath it; it
#            follows its victim, and lands as an IMPACT (without the floor crack).
#   RUBBLE   its death — the body collapsing into falling masonry.
#
# Its palette is its own: brick-red and slate stone under a green eye-glow (the
# glow on its own sprite), on dark under-strokes so it survives every biome.

enum Mode { WINDUP, IMPACT, HIT, RUBBLE, BOULDER }

const INK := Color(0.07, 0.06, 0.06)
const STONE := Color(0.62, 0.62, 0.58)
const STONE_LIT := Color(0.86, 0.86, 0.80)
const BRICK := Color(0.72, 0.36, 0.22)
const DUST := Color(0.80, 0.72, 0.60)
const EYE := Color(0.40, 1.0, 0.60)
const SPARK := Color(1.0, 0.92, 0.55)
const WET := Color(0.18, 0.22, 0.30)
const FLAKE := Color(0.55, 0.40, 0.28)

var mode: Mode = Mode.HIT
var host = null
var r := 100.0
var armor_frac := 0.0         # 0..1 of the armour cap — scales the drama
var eroded := false           # HIT: a Water/Air hit stripped armour
var _target_pos := Vector2.ZERO   # IMPACT: global position of the victim
var _origin_pos := Vector2.ZERO
var _t := 0.0
var _life := 0.5
var _hit_c := Vector2.ZERO
var _with_crack := true
var _victim = null            # BOULDER: the hero it is flying at (followed in flight)
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = int(get_instance_id()) & 0x7fffffff

func setup_windup(unit, life: float, frac: float) -> void:
	mode = Mode.WINDUP
	host = unit
	_life = life
	armor_frac = frac
	r = MirrorVFX.body_r(unit)
	z_index = 6
	global_position = unit.global_position

func setup_impact(unit, target_world: Vector2, frac: float, with_crack: bool = true) -> void:
	mode = Mode.IMPACT
	_with_crack = with_crack
	_life = 0.65
	armor_frac = frac
	r = MirrorVFX.body_r(unit)
	z_index = 6
	_origin_pos = unit.global_position
	_target_pos = target_world
	global_position = Vector2.ZERO

func setup_boulder(unit, victim, flight: float, frac: float) -> void:
	mode = Mode.BOULDER
	_life = flight
	armor_frac = frac
	r = MirrorVFX.body_r(unit)
	z_index = 7
	_victim = victim
	_origin_pos = unit.global_position + Vector2(0, -r * 0.7)
	_target_pos = victim.global_position + Vector2(0, -26)
	global_position = Vector2.ZERO

func setup_hit(unit, frac: float, was_eroded: bool) -> void:
	mode = Mode.HIT
	host = unit
	_life = 0.42
	armor_frac = frac
	eroded = was_eroded
	r = MirrorVFX.body_r(unit)
	z_index = 7
	global_position = unit.global_position
	# Where on the body the blow lands — rolled ONCE (a per-frame roll flickers).
	_hit_c = Vector2(_rng.randf_range(-r * 0.45, r * 0.45), -r * _rng.randf_range(0.25, 0.95))

func setup_rubble(unit) -> void:
	mode = Mode.RUBBLE
	_life = 1.4
	r = MirrorVFX.body_r(unit)
	z_index = 5
	global_position = unit.global_position

func _process(delta: float) -> void:
	_t += delta
	if host != null:
		if not is_instance_valid(host) or host.current_hp <= 0:
			queue_free(); return
		global_position = host.global_position
	if mode == Mode.BOULDER and _victim != null and is_instance_valid(_victim):
		_target_pos = _victim.global_position + Vector2(0, -26)   # homing: keeps the throw honest
	if _t >= _life:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	match mode:
		Mode.WINDUP: _draw_windup()
		Mode.IMPACT: _draw_impact()
		Mode.HIT:    _draw_hit()
		Mode.RUBBLE: _draw_rubble()
		Mode.BOULDER: _draw_boulder()

func _ca(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

# ── WINDUP ───────────────────────────────────────────────────────────────────
func _draw_windup() -> void:
	var k: float = clampf(_t / _life, 0.0, 1.0)
	var ground := Vector2(0, r * 0.80)
	# Two rings closing in on its feet: weight gathering.
	draw_set_transform(ground, 0.0, Vector2(1.0, 0.40))
	for i in 2:
		var rad: float = r * (1.9 - 0.9 * k) - float(i) * r * 0.25
		draw_arc(Vector2.ZERO, rad, 0, TAU, 40, _ca(INK, 0.5 * k), 9.0)
		draw_arc(Vector2.ZERO, rad, 0, TAU, 40, _ca(STONE_LIT, 0.85 * k), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Armour plates sliding out from the torso, then locking.
	var torso := Vector2(0, -r * 0.55)
	for side in [-1.0, 1.0]:
		for j in 2:
			var out: float = r * (0.45 + 0.30 * k) + float(j) * r * 0.16
			var p: Vector2 = torso + Vector2(side * out, float(j) * r * 0.22 - r * 0.10)
			var rect := Rect2(p - Vector2(r * 0.11, r * 0.14), Vector2(r * 0.22, r * 0.28))
			draw_rect(rect.grow(2.5), _ca(INK, k))
			draw_rect(rect, _ca(STONE, k))
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3.0)), _ca(STONE_LIT, k))
			draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 5.0), Vector2(rect.size.x, 5.0)), _ca(BRICK, k))
	# Eyes flare: two green points that swell as the slam nears.
	var head := Vector2(0, -r * 1.05)
	var flare: float = 0.35 + 0.65 * k
	for side in [-1.0, 1.0]:
		var e: Vector2 = head + Vector2(side * r * 0.13, 0)
		draw_circle(e, r * 0.11 * flare, _ca(EYE, 0.30 * flare))
		draw_circle(e, r * 0.055 * flare, _ca(EYE, 0.95))
		draw_circle(e, r * 0.022 * flare, Color(1, 1, 1, 0.95))

# ── IMPACT ───────────────────────────────────────────────────────────────────
func _draw_impact() -> void:
	var k: float = clampf(_t / _life, 0.0, 1.0)
	var from: Vector2 = to_local(_origin_pos) + Vector2(0, r * 0.80)
	var to: Vector2 = to_local(_target_pos) + Vector2(0, 26)
	var grow: float = minf(1.0, k / 0.25) if _with_crack else 1.0
	var a: float = 1.0 - clampf((k - 0.5) / 0.5, 0.0, 1.0)
	# The crack: dark under-stroke, slate body, pale core, racing to the victim.
	var d: Vector2 = to - from
	var n: Vector2 = d.orthogonal().normalized()
	if _with_crack:
		# An EARTH crack, not a discharge: dark and uneven (two mismatched sine
		# wobbles, not an alternating zigzag — that read as lightning), with a dark-
		# soil core, a thin dust lip, and a few short side-cracks branching off it.
		var pts := PackedVector2Array()
		for i in 17:
			var f: float = float(i) / 16.0 * grow
			var wob: float = sin(float(i) * 2.3 + 0.7) + 0.6 * sin(float(i) * 5.1)
			var jag: float = wob * (4.0 + 5.0 * armor_frac) * sin(f * PI)
			pts.append(from + d * f + n * jag)
		draw_polyline(pts, _ca(INK, 0.85 * a), 11.0 + 5.0 * armor_frac)
		draw_polyline(pts, _ca(Color(0.20, 0.13, 0.09), a), 6.0 + 3.0 * armor_frac)
		draw_polyline(pts, _ca(DUST, 0.55 * a), 1.6)
		for b in [5, 9, 13]:
			if b < pts.size():
				var side: float = 1.0 if b % 2 == 1 else -1.0
				var q: Vector2 = pts[b]
				var tip: Vector2 = q + n * side * (14.0 + 10.0 * armor_frac) + d.normalized() * 8.0
				draw_line(q, tip, _ca(INK, 0.85 * a), 6.0)
				draw_line(q, tip, _ca(Color(0.20, 0.13, 0.09), a), 3.0)
	if grow < 1.0:
		return
	# Landing: flash, dust ring, brick shards — more of everything when heavier.
	var e: float = (k - 0.25) / 0.75 if _with_crack else k
	var flash: float = clampf(1.0 - e * 4.0, 0.0, 1.0)
	if flash > 0.0:
		draw_circle(to, (26.0 + 26.0 * armor_frac) * (0.6 + 0.6 * e), _ca(Color.WHITE, 0.75 * flash))
	draw_set_transform(to, 0.0, Vector2(1.0, 0.42))
	var ring: float = (28.0 + 46.0 * e) * (1.0 + 0.7 * armor_frac)
	draw_arc(Vector2.ZERO, ring, 0, TAU, 40, _ca(INK, 0.55 * a), 9.0)
	draw_arc(Vector2.ZERO, ring, 0, TAU, 40, _ca(DUST, 0.85 * a), 4.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var shards: int = 5 + int(armor_frac * 7.0)
	for i in shards:
		var ang: float = -PI * 0.95 + PI * 0.9 * float(i) / float(maxi(1, shards - 1))
		var sp: float = 40.0 + float((i * 13) % 5) * 9.0
		var p: Vector2 = to + Vector2(cos(ang) * sp * e, sin(ang) * sp * e * 1.2 + 70.0 * e * e)
		var s: float = 5.0 - float(i % 3)
		draw_rect(Rect2(p - Vector2(s + 1.5, s + 1.5), Vector2(s + 1.5, s + 1.5) * 2.0), _ca(INK, a))
		draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), _ca(BRICK if i % 2 == 0 else STONE, a))

# ── HIT ──────────────────────────────────────────────────────────────────────
func _draw_hit() -> void:
	var k: float = clampf(_t / _life, 0.0, 1.0)
	var a: float = 1.0 - k * k
	var c: Vector2 = _hit_c
	if eroded:
		# Wet, darkened patch and flakes crumbling away: armour stripped.
		draw_set_transform(c, 0.0, Vector2(1.0, 0.7))
		draw_circle(Vector2.ZERO, r * 0.28, _ca(WET, 0.55 * (1.0 - k)))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in 7:
			var p: Vector2 = c + Vector2((float(i) - 3.0) * 7.0, 0) + Vector2(0, 10.0 + 46.0 * k * k + float(i % 3) * 5.0)
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), _ca(INK, a))
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), _ca(FLAKE, a))
		return
	if armor_frac < 0.5:
		# Soft clay: chips fly off.
		for i in 6:
			var ang: float = -PI * 0.9 + PI * 0.8 * float(i) / 5.0
			var p: Vector2 = c + Vector2(cos(ang), sin(ang)) * (12.0 + 34.0 * k) + Vector2(0, 22.0 * k * k)
			draw_rect(Rect2(p - Vector2(3.5, 3.5), Vector2(7, 7)), _ca(INK, a))
			draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), _ca(BRICK, a))
	else:
		# Hardened: the blow rings off — hard sparks and a bright ping.
		draw_circle(c, 9.0 * (1.0 - k) + 3.0, _ca(Color.WHITE, 0.9 * (1.0 - k)))
		for i in 7:
			var ang2: float = TAU * float(i) / 7.0 + 0.4
			var dir := Vector2(cos(ang2), sin(ang2))
			draw_line(c + dir * (8.0 + 12.0 * k), c + dir * (16.0 + 34.0 * k), _ca(INK, a), 5.0)
			draw_line(c + dir * (8.0 + 12.0 * k), c + dir * (16.0 + 34.0 * k), _ca(SPARK, a), 2.4)

# ── RUBBLE ───────────────────────────────────────────────────────────────────
func _draw_rubble() -> void:
	var k: float = clampf(_t / _life, 0.0, 1.0)
	var a: float = 1.0 - clampf((k - 0.65) / 0.35, 0.0, 1.0)
	# Dust cloud billowing at the base.
	draw_set_transform(Vector2(0, r * 0.75), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, r * (0.6 + 0.9 * k), _ca(DUST, 0.35 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Chunks dropping from the body's height and settling on the ground.
	for i in 16:
		var seed: float = float(i) * 2.399
		var x: float = sin(seed) * r * 0.85
		var y0: float = -r * (0.2 + fposmod(seed * 0.37, 1.0) * 0.9)
		var fall: float = clampf(k * 1.6 - float(i % 5) * 0.06, 0.0, 1.0)
		var y: float = lerpf(y0, r * 0.72 + float(i % 4) * 5.0, fall * fall)
		var s: float = 5.0 + float(i % 4) * 2.5
		var col: Color = BRICK if i % 3 != 0 else STONE
		draw_rect(Rect2(Vector2(x, y) - Vector2(s + 2, s + 2), Vector2(s + 2, s + 2) * 2.0), _ca(INK, a))
		draw_rect(Rect2(Vector2(x, y) - Vector2(s, s), Vector2(s, s) * 2.0), _ca(col, a))

# ── BOULDER ──────────────────────────────────────────────────────────────────
# A chunk of armour plate — brick on one face, slate stone on the other, one
# rivet — tumbling along a lofted arc. Bigger the more hardened the Colossus is.
func _draw_boulder() -> void:
	var k: float = clampf(_t / _life, 0.0, 1.0)
	var from: Vector2 = to_local(_origin_pos)
	var to: Vector2 = to_local(_target_pos)
	var dist: float = from.distance_to(to)
	var arc: float = 36.0 + dist * 0.16
	var size: float = 26.0 + 16.0 * armor_frac   # boulder-sized: the Colossus is ~200px wide
	# Ground shadow slides along the straight line beneath the rock.
	var sh: Vector2 = from.lerp(to, k) + Vector2(0, 46.0)
	draw_set_transform(sh, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, size * (0.9 - 0.2 * sin(k * PI)), _ca(INK, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Dust trail: fading puffs at earlier points on the same arc.
	for i in 7:
		var kk: float = maxf(0.0, k - float(i + 1) * 0.045)
		var tp: Vector2 = from.lerp(to, kk) + Vector2(0, -sin(kk * PI) * arc)
		draw_circle(tp, size * (0.55 - 0.05 * float(i)), _ca(DUST, 0.42 * (1.0 - float(i) / 7.0)))
	var c: Vector2 = from.lerp(to, k) + Vector2(0, -sin(k * PI) * arc)
	var rot: float = _t * 11.0
	draw_chunk(self, c, rot, size)

# One plate of the Colossus's armour: a 7-sided slate chunk, brick on one face,
# a rivet each side. THE shared shape — the thrown boulder and the plates
# orbiting the Colossus (TerracottaVFX) are the same object at different sizes,
# so the throw reads as one of its own plates leaving. Call only from `ci`'s _draw.
static func draw_chunk(ci: CanvasItem, c: Vector2, rot: float, size: float, alpha: float = 1.0) -> void:
	var pts := PackedVector2Array()
	for i in 7:
		var ang: float = rot + TAU * float(i) / 7.0
		var rad: float = size * (0.82 + 0.28 * sin(float(i) * 2.9 + 1.0))
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	var grown := PackedVector2Array()
	for p in pts: grown.append(c + (p - c) * 1.18)
	ci.draw_colored_polygon(grown, Color(INK.r, INK.g, INK.b, alpha))
	ci.draw_colored_polygon(pts, Color(STONE.r, STONE.g, STONE.b, alpha))
	var half := PackedVector2Array([c])
	for i in 4: half.append(pts[i])
	ci.draw_colored_polygon(half, Color(BRICK.r, BRICK.g, BRICK.b, alpha))
	ci.draw_circle(c + Vector2(cos(rot + 1.0), sin(rot + 1.0)) * size * 0.35, maxf(1.2, size * 0.09), Color(INK.r, INK.g, INK.b, alpha))
	ci.draw_circle(c + Vector2(cos(rot + 3.6), sin(rot + 3.6)) * size * 0.30, maxf(1.0, size * 0.075), Color(STONE_LIT.r, STONE_LIT.g, STONE_LIT.b, alpha))
