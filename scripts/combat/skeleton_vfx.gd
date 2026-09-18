extends Node2D
class_name SkeletonVFX

# The Skeleton's visual language: BONE SHARDS AND NECROTIC GREEN.
#
# Ivory shards with a sickly green glow between them. The shard SHAPE is what
# separates it from everything else green in this project — the Rat's plague is
# drifting round motes, the Slime's is heavy droplets, the Troll's is braided
# sinew. These are hard angular splinters.
#
# The headline gap: "Undying" reassembles the Skeleton once at 35% HP the first
# time it would die, and that had NO visual whatsoever. A unit dying and standing
# back up is one of the most important things a player can be told, and it was
# silent — indistinguishable from a bad damage roll.

enum Mode { REASSEMBLE, BONE_SHIELD }

const IVORY := Color(0.93, 0.91, 0.82)
const NECRO := Color(0.48, 0.85, 0.45)
const DARK := Color(0.10, 0.12, 0.10)

var mode: Mode = Mode.REASSEMBLE
var elapsed := 0.0
var lifetime := 0.7
var host = null
var reach := 88.0
var ground_y := 46.0
var _t := 0.0
var _seeds: Array = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_instance_id()) & 0x7fffffff
	for i in range(9):
		_seeds.append(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
			rng.randf_range(0.7, 1.5)))

func setup_on(kind: Mode, unit, size: float, life: float) -> void:
	mode = kind
	host = unit
	reach = size
	lifetime = life
	z_index = 4
	if unit and "shape_size" in unit:
		ground_y = float(unit.shape_size) * 0.72
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

# One bone shard: a short tapered sliver with a dark rim.
func _shard(p: Vector2, dir: Vector2, len: float, a: float, w: float) -> void:
	var tip: Vector2 = p + dir * len
	draw_line(p, tip, Color(DARK.r, DARK.g, DARK.b, a * 0.9), w + 2.0)
	draw_line(p, tip, Color(IVORY.r, IVORY.g, IVORY.b, a), w)

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	match mode:
		Mode.REASSEMBLE:  _draw_reassemble(t)
		Mode.BONE_SHIELD: _draw_shield(t)

# ── It falls apart and pulls itself back together ─────────────────────────
# Runs BACKWARDS on purpose: shards start scattered and converge. Collapse-then-
# reform would read as a death; converging reads as "it is getting back up",
# which is the actual mechanic.
func _draw_reassemble(t: float) -> void:
	var r := reach * 0.5
	# Necrotic pull-in glow, brightest as the pieces meet.
	var gather: float = sin(clampf(t, 0.0, 1.0) * PI)
	draw_circle(Vector2.ZERO, r * (0.30 + 0.30 * gather),
		Color(NECRO.r, NECRO.g, NECRO.b, 0.10 + 0.22 * gather))
	# Shards flying INWARD from scattered positions to the body.
	for i in range(_seeds.size()):
		var sd: Vector3 = _seeds[i]
		var from := Vector2(sd.x, sd.y).normalized() * r * (1.25 - 0.95 * t)
		var dir := (Vector2.ZERO - from).normalized()
		_shard(from, dir, (9.0 + 6.0 * sd.z) * (0.5 + 0.5 * (1.0 - t)),
			0.35 + 0.6 * t, 2.2 * sd.z)
	# Ground pool of the same necrotic light, contracting as it rises.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	draw_arc(Vector2.ZERO, r * (0.70 - 0.32 * t), 0.0, TAU, 26,
		Color(NECRO.r, NECRO.g, NECRO.b, 0.30 + 0.40 * t), 2.0 + 2.0 * t)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The snap: a bright flash right at the end, when it is standing again.
	if t > 0.78:
		var f: float = (t - 0.78) / 0.22
		draw_circle(Vector2.ZERO, r * (0.20 + 0.45 * f),
			Color(IVORY.r, IVORY.g, IVORY.b, 0.85 * (1.0 - f)))

# ── Bone Shield: plates of rib rattling into place ───────────────────────
# Its own look instead of the generic HOLY_LIGHT burst the key ships with.
func _draw_shield(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	draw_circle(Vector2.ZERO, r * 0.52, Color(NECRO.r, NECRO.g, NECRO.b, 0.10 * fade))
	# A cage of ribs closing around the body.
	var n := 7
	for i in range(n):
		var a0: float = float(i) * TAU / float(n) + _t * 0.3
		var d := Vector2(cos(a0), sin(a0))
		var rr: float = r * lerp(0.75, 0.48, t)
		_shard(d * rr, d.orthogonal(), 12.0, (0.45 + 0.45 * t) * fade + 0.25, 2.6)
	draw_arc(Vector2.ZERO, r * lerp(0.75, 0.48, t), 0.0, TAU, 28,
		Color(IVORY.r, IVORY.g, IVORY.b, (0.35 + 0.40 * t) * fade + 0.2), 2.2)
