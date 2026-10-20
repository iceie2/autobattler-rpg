extends Node2D
class_name TerracottaVFX

# The Terracotta Colossus's visual language: A WALL BEING LAID.
#
# Set in Stone adds armor every second it lives (up to +160) — a clock the
# player is racing, which had NO visual: the Colossus looked identical at +0
# and +160. Its body is brick and riveted grey slabs, so the readout is those
# slabs rising out of the ground around its base, one per SLAB_EVERY armor,
# each landing with a dust puff. Full ring = fully fortified.

const OUTLINE := Color(0.07, 0.06, 0.06)
const STONE := Color(0.64, 0.64, 0.61)
const STONE_LIT := Color(0.84, 0.84, 0.80)
const BRICK := Color(0.72, 0.36, 0.22)
const DUST := Color(0.80, 0.72, 0.60)
const SLABS := 10
const PLANE_SQUASH := 0.40

var host = null
var r := 80.0
var ground_y := 60.0
var armor_frac := 0.0        # 0..1 of the cap
var _landed: Array = []      # per-slab time it landed (-1 = not yet)
var _t := 0.0

func setup_on(unit) -> void:
	host = unit
	z_index = 4
	r = MirrorVFX.body_r(unit)
	ground_y = r * 0.80
	global_position = unit.global_position
	for i in SLABS: _landed.append(-1.0)

const MILESTONES := [0.25, 0.50, 0.75, 1.0]
# Orbiting plates (owner, 2026-09-30): one plate of armour circles the Colossus
# for every PLATE_ARMOR points stacked — 16 at the +160 cap — added as armour
# climbs and torn away as Water/Air erode it. Each is the SAME chunk it hurls in
# Weight of Stone (TerracottaStrikeVFX.draw_chunk).
const PLATE_ARMOR := 10.0
const PLATE_DIE_TIME := 0.45
var _plates: Array = []   # {"base": float, "born": float, "dying": float (-1 = alive)}
var _prev_frac := 0.0
var _flash := 0.0            # 1 → 0: the plate-clang flash at each armour milestone
var _last_flash_t := -10.0

func set_armor_frac(f: float) -> void:
	armor_frac = clampf(f, 0.0, 1.0)
	# A plate clangs into place each time armour climbs through 25/50/75/100% —
	# throttled, so eroding and re-hardening around a threshold doesn't strobe.
	for m in MILESTONES:
		if armor_frac >= m and _prev_frac < m and _t - _last_flash_t > 1.0:
			_flash = 1.0
			_last_flash_t = _t
	_prev_frac = armor_frac
	_sync_plates()
	# Ground slabs (one per 10% of the cap): stamp the moment each one lands.
	var built: int = int(floor(armor_frac * float(SLABS) + 0.001))
	for i in SLABS:
		if i < built and float(_landed[i]) < 0.0:
			_landed[i] = _t

func _plate_target() -> int:
	return int(floor(armor_frac * AutoBattleManager.TERRACOTTA_ARMOR_CAP / PLATE_ARMOR + 0.001))

# Grow or shrink the orbit to match the armour. A new plate goes in the widest
# gap of the ring so additions never clump; removal takes the newest plate.
func _sync_plates() -> void:
	var want: int = _plate_target()
	var alive: Array = _plates.filter(func(p): return float(p["dying"]) < 0.0)
	while alive.size() < want:
		var best_a := 0.0
		var best_gap := -1.0
		for i in 16:
			var a: float = TAU * float(i) / 16.0
			var gap := TAU
			for p in alive:
				var pa: float = fposmod(float(p["base"]) + _t * _plate_speed(), TAU)
				gap = minf(gap, absf(angle_difference(pa, a)))
			if gap > best_gap:
				best_gap = gap; best_a = a
		var np := {"base": best_a - _t * _plate_speed(), "born": _t, "dying": -1.0}
		_plates.append(np); alive.append(np)
	while alive.size() > want:
		var last: Dictionary = alive.pop_back()
		last["dying"] = _t

func _plate_speed() -> float:
	return 0.9 + 0.03 * float(_plate_target())

func _draw_plates() -> void:
	# Keep the orbit around the lower body, near the hips and feet.
	var c := Vector2(0, r * 0.45)
	for p in _plates:
		var dying: bool = float(p["dying"]) >= 0.0
		var age_born: float = _t - float(p["born"])
		var ang: float = float(p["base"]) + _t * _plate_speed()
		var depth: float = sin(ang)                   # +1 front of the body, -1 behind it
		var pos: Vector2 = c + Vector2(cos(ang) * r * 1.55, depth * r * 0.42 + r * 0.05)
		var size: float = (17.0 + 6.0 * depth) * (r / 100.0)
		var alpha: float = 0.55 + 0.45 * (depth * 0.5 + 0.5)
		if age_born < 0.25:
			size *= clampf(age_born / 0.25, 0.0, 1.0)   # pops in
		if dying:
			var d: float = (_t - float(p["dying"])) / PLATE_DIE_TIME
			pos += Vector2(cos(ang), 0.0) * 46.0 * d + Vector2(0.0, 120.0 * d * d)   # flung off, then falls
			alpha *= clampf(1.0 - d, 0.0, 1.0)
		# A pale halo under each plate: the body is brick-red and grey, and a same-coloured
		# plate vanishes into it.
		draw_circle(pos, size * 1.35, Color(1.0, 0.97, 0.85, 0.22 * alpha))
		TerracottaStrikeVFX.draw_chunk(self, pos, _t * 3.0 + float(p["base"]), size, alpha)

func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 2.5)
	_plates = _plates.filter(func(p): return float(p["dying"]) < 0.0 or _t - float(p["dying"]) < PLATE_DIE_TIME)
	if not (host and is_instance_valid(host)) or host.current_hp <= 0:
		queue_free(); return
	global_position = host.global_position
	queue_redraw()

func _draw() -> void:
	# Milestone clang: a bright ring and radiating sparks off the torso.
	if _flash > 0.0:
		var c := Vector2(0, -r * 0.55)
		var e: float = 1.0 - _flash
		draw_arc(c, r * (0.5 + 0.9 * e), 0, TAU, 40, Color(OUTLINE.r, OUTLINE.g, OUTLINE.b, 0.6 * _flash), 10.0)
		draw_arc(c, r * (0.5 + 0.9 * e), 0, TAU, 40, Color(1.0, 1.0, 0.9, _flash), 4.0)
		for i in 8:
			var ang: float = TAU * float(i) / 8.0 + 0.3
			var dir := Vector2(cos(ang), sin(ang))
			draw_line(c + dir * r * (0.55 + 0.9 * e), c + dir * r * (0.75 + 1.1 * e),
				Color(1.0, 0.92, 0.55, _flash), 3.0)
	# Slabs sit on the FRONT half of a ground ellipse (the half facing the
	# viewer), left to right, so they never hide behind the body.
	for i in SLABS:
		var ang: float = PI - PI * (float(i) + 0.5) / float(SLABS)
		var base := Vector2(cos(ang) * r * 1.05, ground_y + sin(ang) * r * 1.05 * PLANE_SQUASH)
		var t_land: float = float(_landed[i])
		var w: float = r * 0.24
		if t_land < 0.0:
			# Empty footing: a faint outline of the slab still to come.
			draw_rect(Rect2(base + Vector2(-w * 0.5, -3.0), Vector2(w, 4.0)),
				Color(OUTLINE.r, OUTLINE.g, OUTLINE.b, 0.35))
			continue
		var age: float = _t - t_land
		var rise: float = clampf(age / 0.18, 0.0, 1.0)        # slams up fast
		var h: float = r * 0.50 * (0.8 + 0.2 * sin(float(i) * 1.7)) * rise
		var rect := Rect2(base + Vector2(-w * 0.5, -h), Vector2(w, h))
		draw_rect(rect.grow(2.0), OUTLINE)
		draw_rect(rect, STONE)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3.0)), STONE_LIT)
		draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 4.0), Vector2(rect.size.x, 4.0)), BRICK)
		if h > 10.0:
			draw_circle(rect.position + Vector2(w * 0.28, 6.0), 1.6, OUTLINE)
			draw_circle(rect.position + Vector2(w * 0.72, 6.0), 1.6, OUTLINE)
		# Dust puff for the first 0.4s after landing.
		if age < 0.4:
			var dk: float = age / 0.4
			for s in [-1.0, 1.0]:
				draw_circle(base + Vector2(s * (w * 0.6 + dk * 10.0), -2.0 - dk * 5.0),
					4.0 * (1.0 - dk) + 1.0, Color(DUST.r, DUST.g, DUST.b, 0.8 * (1.0 - dk)))
	# Fully fortified: a slow glint travels along the finished wall.
	if armor_frac >= 1.0:
		var gi: int = int(fposmod(_t * 4.0, float(SLABS)))
		var ang2: float = PI - PI * (float(gi) + 0.5) / float(SLABS)
		var gp := Vector2(cos(ang2) * r * 1.05, ground_y + sin(ang2) * r * 1.05 * PLANE_SQUASH - r * 0.15)
		draw_circle(gp, 3.5, Color(1, 1, 1, 0.9))
	_draw_plates()   # orbiting armour plates, drawn over the wall
