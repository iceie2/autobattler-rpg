extends Node2D
class_name MinotaurVFX

# The Minotaur's visual language: HORNS AND HOOF-SCRAPE.
# Two curved horn arcs sweeping forward, plus kicked-up dust at ground level.
# Deliberately distinct from the Bear's straight claw rakes (which it sits next
# to in the same waves and shares the `bear_fury` passive with): the Bear opens
# WOUNDS, the Minotaur delivers IMPACT, so this is iron and dust rather than
# blood and gashes.
#
# Gore Rush reuses the Wind-Up Bot's `windup_punch` key, so it already inherits
# that path's range gate, committed timing and post-mitigation accounting. What
# it lacked was any identity of its own — it drew the generic orange WHIRLWIND —
# and its Savage Charge ramp was invisible.

enum Mode { GORE_WINDUP, GORE_IMPACT, SAVAGE }

# COLD STEEL, not rust/ochre. The Minotaur's sprite is a dark body covered in
# ORANGE FLAME (horns and axe), so warm rust and ochre dust drew straight into
# its own fire and vanished (measured in the first capture — fifth time this
# project has hit "an effect in the creature's own colours is invisible on it").
# Bright steel with a hard dark rim separates from both the dark hide and the
# flames, and iron horns are the honest read anyway.
const IRON := Color(0.90, 0.93, 0.97)
const RUST := Color(0.55, 0.74, 0.88)
const DUST := Color(0.74, 0.78, 0.80)
const DARK := Color(0.06, 0.08, 0.11)

var mode: Mode = Mode.GORE_IMPACT
var elapsed := 0.0
var lifetime := 0.5
var host = null
var reach := 96.0
var rage := 0.0              # SAVAGE: 0..1 across the +0%..+30% ramp
var ground_y := 46.0
var _t := 0.0

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

# One horn: a curved arc that tapers to a bright tip. Dark rim keeps it readable
# on the Minotaur's own brown hide.
func _horn(side: float, spread: float, len: float, a: float, w: float) -> void:
	var pts := PackedVector2Array()
	for i in range(9):
		var f := float(i) / 8.0
		var ang: float = -PI * 0.5 + side * (spread + f * 0.85)
		pts.append(Vector2(cos(ang), sin(ang)) * len * (0.45 + 0.55 * f))
	draw_polyline(pts, Color(DARK.r, DARK.g, DARK.b, a * 0.85), w + 2.4)
	draw_polyline(pts, Color(IRON.r, IRON.g, IRON.b, a), w)
	draw_circle(pts[pts.size() - 1], w * 0.9, Color(1.0, 0.97, 0.90, a))

# Dust kicked along the floor, squashed to sit flat on the perspective board.
func _dust(spread: float, rise: float, a: float, n: int) -> void:
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	for i in range(n):
		var f := (float(i) + 0.5) / float(n)
		var x: float = lerp(-spread, spread, f)
		var puff: float = sin(f * PI) * rise
		draw_circle(Vector2(x, -puff * 0.3), 3.0 + puff * 0.18,
			Color(DUST.r, DUST.g, DUST.b, a * (0.5 + 0.5 * sin(f * PI))))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	match mode:
		Mode.GORE_WINDUP: _draw_windup(t)
		Mode.GORE_IMPACT: _draw_impact(t)
		Mode.SAVAGE:      _draw_savage()

# ── It lowers its head and scrapes ─────────────────────────────────────────
# The horns CLOSE inward as the charge builds, so the tell escalates
# monotonically and is readable across a crowded board.
func _draw_windup(t: float) -> void:
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * (0.30 + t * 0.22), Color(RUST.r, RUST.g, RUST.b, 0.05 + t * 0.10))
	var spread: float = 0.55 - t * 0.30
	for s in [-1.0, 1.0]:
		_horn(s, spread, r * (0.50 + 0.22 * t), 0.40 + 0.50 * t, 2.6 + 1.4 * t)
	# Hoof scrape building at the floor — the classic "about to charge" read.
	_dust(r * (0.30 + 0.24 * t), 6.0 + 10.0 * t, 0.30 + 0.45 * t, 5)
	draw_circle(Vector2(0, -r * 0.10), 3.0 + 4.0 * t, Color(RUST.r, RUST.g, RUST.b, 0.4 + 0.4 * t))

# ── The horns go in ────────────────────────────────────────────────────────
func _draw_impact(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * (0.40 + 0.70 * t), Color(RUST.r, RUST.g, RUST.b, 0.18 * fade))
	# Horns thrust THROUGH and past — they open outward as they pass.
	for s in [-1.0, 1.0]:
		_horn(s, 0.20 + 0.45 * t, r * (0.72 + 0.55 * t), 0.95 * fade, 4.0 * fade + 1.2)
	# Impact wedge: a hard V driven forward from the contact point.
	var w: float = r * (0.30 + 0.45 * t)
	draw_line(Vector2(-w, w * 0.55), Vector2.ZERO, Color(RUST.r, RUST.g, RUST.b, 0.9 * fade), 4.0 * fade + 1.0)
	draw_line(Vector2(w, w * 0.55), Vector2.ZERO, Color(RUST.r, RUST.g, RUST.b, 0.9 * fade), 4.0 * fade + 1.0)
	_dust(r * (0.45 + 0.60 * t), 14.0 + 12.0 * t, 0.75 * fade, 8)
	draw_circle(Vector2.ZERO, (6.0 * fade + 2.0), Color(1.0, 1.0, 1.0, 0.85 * fade))

# ── Persistent: Savage Charge is ramping ──────────────────────────────────
# Ground-anchored so it never fights the health bar. Snort plumes and a hoof
# scrape that both quicken with the ramp, so "this one is winding up" is legible
# without reading its HP bar.
func _draw_savage() -> void:
	if rage <= 0.05:
		return
	var r := reach * 0.5
	var beat: float = 0.5 + 0.5 * sin(_t * (1.8 + 4.0 * rage))
	# Hoof scrape: a widening arc of dust that pulses faster the angrier it is.
	_dust(r * (0.26 + 0.20 * rage), 5.0 + 9.0 * rage, (0.22 + 0.34 * rage) * (0.7 + 0.3 * beat), 6)
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	draw_arc(Vector2.ZERO, r * (0.34 + 0.14 * rage), 0.0, TAU, 24,
		Color(RUST.r, RUST.g, RUST.b, 0.25 + 0.35 * rage), 1.8 + 1.4 * rage)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Twin snort plumes from the muzzle — the unmistakable bull tell.
	for s in [-1.0, 1.0]:
		var f: float = fposmod(_t * (0.9 + 1.4 * rage), 1.0)
		var base := Vector2(s * r * 0.16, -r * 0.02)
		var tip := base + Vector2(s * (6.0 + 14.0 * f), 4.0 + 10.0 * f)
		draw_circle(tip, (2.4 + 3.4 * f) * (1.0 - f * 0.5),
			Color(DUST.r, DUST.g, DUST.b, (1.0 - f) * (0.35 + 0.35 * rage)))
	draw_circle(Vector2(0, -r * 0.04), 2.4 + 2.2 * beat * rage,
		Color(RUST.r, RUST.g, RUST.b, 0.30 + 0.35 * rage))
