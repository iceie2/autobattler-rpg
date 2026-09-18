extends Node2D
class_name GargoyleVFX

# The Gargoyle's "Stone Skin": MASONRY SEAMS THAT SEAL, AND MOLTEN CRACKS THAT
# SPLIT.
#
# It rides `troll_regen` like the Troll and the Ember Phoenix, but its passive is
# named "Stone Skin", so by the name-match rule it gets its own fiction rather
# than the Troll's sinew or the Phoenix's embers.
#
# Colour choice is deliberate and learned: the Gargoyle's sprite is GREY STONE,
# and this project has repeatedly lost effects by drawing them in the body's own
# colours (grey ash on a grey Troll being the closest miss). So the regen is a
# warm amber SEAM light and the blocked state is a hot molten CRACK — both of
# which read instantly against grey, and "a Fire or Lightning hit cracks the
# stone" is exactly what the description already promises.

enum Mode { STONE_SKIN, CRACKED }

# COOL pale cyan, not amber. I assumed "stone" meant grey; the Gargoyle's sprite
# is actually warm SANDSTONE, so warm amber seams drew straight into it and the
# sealing state was nearly invisible while the molten cracks read fine (measured
# in the first capture — seventh time this project has hit the same trap, and the
# first time it came from assuming a body colour instead of looking).
# Cool seal vs hot crack is also a cleaner opposition than warm vs warm.
const SEAM := Color(0.72, 0.95, 1.0)
const MOLTEN := Color(1.0, 0.44, 0.16)
const SLAB := Color(0.20, 0.20, 0.22)

var mode: Mode = Mode.STONE_SKIN
var elapsed := 0.0
var lifetime := 0.5
var host = null
var reach := 100.0
var ground_y := 46.0
var _t := 0.0
var _seeds: Array = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_instance_id()) & 0x7fffffff
	for i in range(8):
		_seeds.append(rng.randf_range(-1.0, 1.0))

func setup_on(kind: Mode, unit, size: float, life: float) -> void:
	mode = kind
	host = unit
	reach = size
	lifetime = life
	z_index = 3
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

# A jagged seam between two slabs — dark groove with a glowing line inside it.
func _seam(from: Vector2, to: Vector2, glow: Color, a: float, w: float, jag: float) -> void:
	var pts := PackedVector2Array()
	var steps := 5
	for i in range(steps + 1):
		var f := float(i) / float(steps)
		var p: Vector2 = from.lerp(to, f)
		if i > 0 and i < steps:
			p += (to - from).normalized().orthogonal() * _seeds[i % _seeds.size()] * jag
		pts.append(p)
	draw_polyline(pts, Color(SLAB.r, SLAB.g, SLAB.b, a), w + 3.0)
	draw_polyline(pts, Color(glow.r, glow.g, glow.b, a), w)

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0) if is_finite(lifetime) else 0.0
	match mode:
		Mode.STONE_SKIN: _draw_stone_skin()
		Mode.CRACKED:    _draw_cracked(t)

# ── Persistent: the stone is knitting itself closed ──────────────────────
# Calm and slow — it can sit for a whole fight. Seams pulse warm as they seal.
func _draw_stone_skin() -> void:
	var r := reach * 0.5
	var pulse: float = 0.5 + 0.5 * sin(_t * 1.3)
	# Three masonry seams across the body, breathing warm.
	for i in range(3):
		var y: float = -r * 0.18 + float(i) * r * 0.26
		var w: float = r * (0.34 - float(i) * 0.05)
		_seam(Vector2(-w, y), Vector2(w, y), SEAM,
			(0.45 + 0.30 * pulse) * (1.0 - float(i) * 0.15), 2.4, 2.4)
	# A settling dust ring at the feet — stone working, not flesh healing.
	draw_set_transform(Vector2(0, ground_y), 0.0, Vector2(1.0, 0.40))
	draw_arc(Vector2.ZERO, r * (0.38 + 0.03 * pulse), 0.0, TAU, 24,
		Color(SEAM.r, SEAM.g, SEAM.b, 0.30 + 0.22 * pulse), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ── The counterplay landing: Fire/Lightning cracks the stone ─────────────
# The description literally says the stone CRACKS, so the blocked state is
# molten fractures spidering outward — unmistakable against grey, and the exact
# inverse of the calm sealing seams above.
func _draw_cracked(t: float) -> void:
	var fade := 1.0 - t
	var r := reach * 0.5
	# Fractures splitting outward from the chest.
	for i in range(5):
		var a0: float = -PI * 0.5 + (float(i) - 2.0) * 0.55
		var d := Vector2(cos(a0), sin(a0))
		_seam(Vector2.ZERO, d * r * (0.34 + 0.44 * t), MOLTEN, 0.95 * fade,
			3.2 * fade + 1.0, 4.0)
	# Chips knocked loose and falling.
	for i in range(_seeds.size()):
		var x: float = _seeds[i] * r * 0.40
		var y: float = -r * 0.10 + t * t * 26.0 + _seeds[(i + 2) % _seeds.size()] * 6.0
		draw_circle(Vector2(x, y), 2.2 * fade + 0.8, Color(SLAB.r, SLAB.g, SLAB.b, 0.9 * fade))
		draw_circle(Vector2(x, y), 1.2 * fade + 0.4, Color(MOLTEN.r, MOLTEN.g, MOLTEN.b, 0.8 * fade))
	draw_circle(Vector2.ZERO, (9.0 * fade + 2.0), Color(MOLTEN.r, MOLTEN.g, MOLTEN.b, 0.8 * fade))
