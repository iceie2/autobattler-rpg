extends Node2D
class_name WyvernVFX

# The Sky Wyvern's venom: BARBED STINGER AND VIOLET TOXIN.
#
# It rides `rat_bite`, whose DoT flavour defaults to "fire" — so before this the
# Wyvern's *poison* literally rendered as a fire burn while its description
# promised venom. Same key, three fictions now: Rat "disease" (bile motes),
# Hellhound "fire" (correct default), Sky Wyvern "venom" (this).
#
# Violet toxin, chosen against its own art: the Wyvern is a pale blue-grey AIR
# creature, so a cool blue effect would vanish into it (the trap this project has
# hit seven times). Violet-magenta reads hard against pale blue, and is also the
# only place in the enemy palette using it.
#
# Shape separation from the Rat: the Rat's plague is soft round drifting motes;
# venom is sharp angular DROPLETS that fall and a barbed sting mark.

enum Mode { STING_WINDUP, STING_IMPACT, VENOM, WOUNDED_DIVE }

const TOXIN := Color(0.78, 0.30, 0.92)
const TOXIN_DEEP := Color(0.24, 0.05, 0.32)
const PALE := Color(0.96, 0.86, 1.0)
const BLOOD := Color(0.85, 0.20, 0.30)

var mode: Mode = Mode.STING_IMPACT
var elapsed := 0.0
var lifetime := 0.5
var host = null
var reach := 120.0
var rage := 0.0              # WOUNDED_DIVE: 0..1 across the +0%..+30% ramp
var ground_y := 72.0
var _t := 0.0
var _seeds: Array = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_instance_id()) & 0x7fffffff
	for i in range(10):
		_seeds.append(Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 1.0)))

func setup_point(kind: Mode, world_pos: Vector2, size: float, life: float) -> void:
	mode = kind
	global_position = world_pos
	reach = size
	lifetime = life
	z_index = 4
	queue_redraw()

func setup_on(kind: Mode, unit, size: float, life: float) -> void:
	mode = kind
	host = unit
	reach = size
	lifetime = life
	z_index = 3
	if unit and "shape_size" in unit:
		ground_y = float(unit.shape_size) * 0.72
	queue_redraw()

func set_rage(v: float) -> void:
	rage = clampf(v, 0.0, 1.0)
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	_t += delta
	if host != null:
		if not is_instance_valid(host):
			queue_free()
			return
		global_position = host.global_position
	if elapsed >= lifetime:
		queue_free()
	else:
		queue_redraw()

# An angular venom droplet — a diamond, not a circle, so it never reads as the
# Rat's soft plague motes.
func _droplet(p: Vector2, s: float, a: float) -> void:
	var pts := PackedVector2Array([
		p + Vector2(0, -s * 1.5), p + Vector2(s * 0.75, 0),
		p + Vector2(0, s * 1.1), p + Vector2(-s * 0.75, 0)])
	draw_colored_polygon(pts, Color(TOXIN_DEEP.r, TOXIN_DEEP.g, TOXIN_DEEP.b, a))
	var inner := PackedVector2Array([
		p + Vector2(0, -s * 1.0), p + Vector2(s * 0.45, 0),
		p + Vector2(0, s * 0.7), p + Vector2(-s * 0.45, 0)])
	draw_colored_polygon(inner, Color(TOXIN.r, TOXIN.g, TOXIN.b, a))

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	match mode:
		Mode.STING_WINDUP: _draw_windup(t)
		Mode.STING_IMPACT: _draw_impact(t)
		Mode.VENOM:        _draw_venom()
		Mode.WOUNDED_DIVE: _draw_dive()

# ── The stinger cocks back and beads venom ────────────────────────────────
func _draw_windup(t: float) -> void:
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * (0.24 + 0.16 * t), Color(TOXIN.r, TOXIN.g, TOXIN.b, 0.06 + 0.12 * t))
	# The barb itself, drawing back and sharpening.
	var tip := Vector2(0, -r * (0.34 + 0.24 * t))
	draw_line(Vector2(0, r * 0.10), tip, Color(TOXIN_DEEP.r, TOXIN_DEEP.g, TOXIN_DEEP.b, 0.85), 6.0)
	draw_line(Vector2(0, r * 0.10), tip, Color(TOXIN.r, TOXIN.g, TOXIN.b, 0.45 + 0.50 * t), 2.8)
	# A bead of venom swelling at the point.
	_droplet(tip, 2.0 + 3.5 * t, 0.5 + 0.5 * t)

# ── It goes in ───────────────────────────────────────────────────────────
func _draw_impact(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * (0.28 + 0.55 * t), Color(TOXIN.r, TOXIN.g, TOXIN.b, 0.20 * fade))
	# A barbed puncture: one hard stab line with a splayed barb at the entry.
	draw_line(Vector2(0, -r * 0.42), Vector2(0, r * 0.14),
		Color(TOXIN_DEEP.r, TOXIN_DEEP.g, TOXIN_DEEP.b, 0.9 * fade), 7.0 * fade + 1.5)
	draw_line(Vector2(0, -r * 0.42), Vector2(0, r * 0.14),
		Color(PALE.r, PALE.g, PALE.b, 0.95 * fade), 2.4 * fade + 0.8)
	for s in [-1.0, 1.0]:
		draw_line(Vector2.ZERO, Vector2(s * r * (0.14 + 0.16 * t), r * 0.16),
			Color(TOXIN.r, TOXIN.g, TOXIN.b, 0.85 * fade), 3.0 * fade + 1.0)
	# Venom flung clear as angular droplets.
	for i in range(_seeds.size()):
		var sd: Vector2 = _seeds[i]
		var p: Vector2 = Vector2(sd.x, -sd.y).normalized() * r * (0.22 + 0.70 * t) + Vector2(0, t * t * 18.0)
		_droplet(p, (1.8 + absf(sd.x) * 1.6) * fade, 0.9 * fade)

# ── Persistent: the victim is envenomed ─────────────────────────────────
# Droplets run DOWN the body and pool — deliberately the inverse of the Rat's
# plague motes, which drift up. Same shared burn timer, opposite motion, so two
# DoTs from two different mobs never read alike.
func _draw_venom() -> void:
	var r := reach * 0.5
	var pulse: float = 0.5 + 0.5 * sin(_t * 2.0)
	draw_circle(Vector2(0, r * 0.10), r * (0.34 + 0.04 * pulse),
		Color(TOXIN.r, TOXIN.g, TOXIN.b, 0.15 + 0.09 * pulse))
	for i in range(_seeds.size()):
		var sd: Vector2 = _seeds[i]
		var phase: float = fposmod(_t * 0.62 + float(i) / float(_seeds.size()), 1.0)
		var x: float = sd.x * r * 0.34
		var y: float = -r * 0.24 + phase * (r * 0.30 + ground_y * 0.7)
		_droplet(Vector2(x, y), 1.6 + 1.2 * (1.0 - phase),
			0.40 + (1.0 - phase) * 0.55)
	# Pooled venom at the feet.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, r * (0.22 + 0.03 * pulse),
		Color(TOXIN_DEEP.r, TOXIN_DEEP.g, TOXIN_DEEP.b, 0.34 + 0.12 * pulse))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ── Persistent: Wounded Dive (aspd ramps with missing HP) ───────────────
# Its own fiction on the shared `bear_fury` key — the Bear rages, the Minotaur
# scrapes, this one commits to a steeper dive as it is hurt.
func _draw_dive() -> void:
	if rage <= 0.05:
		return
	var r := reach * 0.5
	var beat: float = 0.5 + 0.5 * sin(_t * (2.0 + 4.0 * rage))
	# Dive lines swept back off the wings, steeper and faster with the ramp.
	for i in range(4):
		var f: float = fposmod(_t * (1.0 + 1.8 * rage) + float(i) / 4.0, 1.0)
		var x: float = (float(i) - 1.5) * r * 0.30
		var y0: float = -r * 0.24 + f * r * 0.20
		draw_line(Vector2(x, y0), Vector2(x - r * (0.14 + 0.12 * rage), y0 + r * 0.22),
			Color(BLOOD.r, BLOOD.g, BLOOD.b, (1.0 - f) * (0.35 + 0.40 * rage)), 2.2 + 1.4 * rage)
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.38))
	draw_arc(Vector2.ZERO, r * (0.28 + 0.12 * rage), 0.0, TAU, 22,
		Color(BLOOD.r, BLOOD.g, BLOOD.b, 0.22 + 0.34 * rage), 1.8 + 1.4 * rage * beat)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
