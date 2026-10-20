extends Node2D
class_name MirrorVFX

# The Mirrorplate Warden's visual language: POLISHED STEEL THAT THROWS IT BACK.
#
# Its body is a mirror-polished steel turtle, so the language is specular:
# a slow SHEEN sliding across the shell (always on — the player must be able to
# see "this reflects" BEFORE they hit it; a reflect with no tell is the
# agency-removing pattern this project has ruled out), a GLINT where a blow
# lands, and a silver SHARD flying back into whoever struck it.
# Normal element — no accent hue, steel and white only.

enum Mode { SHEEN, GLINT, SHARD }

const DARK := Color(0.09, 0.11, 0.15)
const STEEL := Color(0.62, 0.72, 0.86)
const SILVER := Color(0.94, 0.97, 1.0)

var mode: Mode = Mode.GLINT
var host = null
var r := 40.0
var _t := 0.0
var _life := 0.3
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _target = null

func setup_on(k: Mode, unit, life: float) -> void:
	mode = k
	host = unit
	_life = life
	z_index = 5
	r = body_r(unit)
	global_position = unit.global_position
	queue_redraw()

# Shard from the Warden to its attacker; follows the attacker if it moves.
func setup_shard(from_unit, to_unit) -> void:
	mode = Mode.SHARD
	_life = 0.20
	z_index = 5
	_from = from_unit.global_position + Vector2(0, -24)
	_target = to_unit
	_to = to_unit.global_position + Vector2(0, -24)
	global_position = Vector2.ZERO
	queue_redraw()

# Half the drawn body width: a 2×2 unit's shape_size is only its click radius,
# so scale by footprint or every effect on a giant is a sliver.
static func body_r(unit) -> float:
	var sz: float = float(unit.shape_size) if unit and "shape_size" in unit else 66.0
	var cells: int = int(unit.cell_size) if unit and "cell_size" in unit else 1
	return sz * 0.5 * float(maxi(1, cells))

func _process(delta: float) -> void:
	_t += delta
	if host != null:
		if not is_instance_valid(host) or host.current_hp <= 0:
			queue_free(); return
		global_position = host.global_position
	if _target and is_instance_valid(_target):
		_to = _target.global_position + Vector2(0, -24)
	if _t >= _life:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	match mode:
		Mode.SHEEN: _draw_sheen()
		Mode.GLINT: _draw_glint()
		Mode.SHARD: _draw_shard()

# A diagonal band of light crossing the shell every 2.4s.
func _draw_sheen() -> void:
	var ph: float = fposmod(_t / 2.4, 1.0)
	if ph > 0.35:
		return
	var k: float = ph / 0.35
	var x: float = lerpf(-r * 1.2, r * 1.2, k)
	var a: float = sin(k * PI) * 0.55
	var top := Vector2(x + r * 0.35, -r * 1.3)
	var bot := Vector2(x - r * 0.35, -r * 0.05)
	draw_line(top, bot, Color(SILVER.r, SILVER.g, SILVER.b, a), 7.0)
	draw_line(top + Vector2(10, 0), bot + Vector2(10, 0), Color(SILVER.r, SILVER.g, SILVER.b, a * 0.5), 3.0)

# A four-point star on the shell where the blow landed.
func _draw_glint() -> void:
	var k: float = _t / _life
	var a: float = 1.0 - k
	var c := Vector2(0, -r * 0.7)
	var s: float = r * (0.35 + 0.35 * k)
	for layer in 2:
		var col: Color = DARK if layer == 0 else SILVER
		var w: float = 6.0 if layer == 0 else 2.5
		draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), Color(col.r, col.g, col.b, a), w)
		draw_line(c + Vector2(0, -s), c + Vector2(0, s), Color(col.r, col.g, col.b, a), w)
	draw_circle(c, 4.0 + 4.0 * (1.0 - k), Color(SILVER.r, SILVER.g, SILVER.b, a))

# A thin steel shard racing back to the attacker, cracking on arrival.
func _draw_shard() -> void:
	var k: float = _t / _life
	var travel: float = minf(1.0, k / 0.7)
	var from_l: Vector2 = to_local(_from)
	var to_l: Vector2 = to_local(_to)
	var p: Vector2 = from_l.lerp(to_l, travel)
	var dir: Vector2 = (to_l - from_l).normalized()
	if dir == Vector2.ZERO: dir = Vector2.RIGHT
	var n := dir.orthogonal()
	var tip: Vector2 = p + dir * 14.0
	var tail: Vector2 = p - dir * 12.0
	var poly := PackedVector2Array([tip, p + n * 4.0, tail, p - n * 4.0])
	var big := PackedVector2Array([tip + dir * 3.0, p + n * 6.5, tail - dir * 3.0, p - n * 6.5])
	draw_colored_polygon(big, DARK)
	draw_colored_polygon(poly, SILVER)
	draw_line(tail, tail - dir * 22.0 * (1.0 - travel * 0.5), Color(STEEL.r, STEEL.g, STEEL.b, 0.6), 2.0)
	if travel >= 1.0:
		var a: float = 1.0 - (k - 0.7) / 0.3
		for i in 5:
			var ang: float = TAU * float(i) / 5.0
			draw_line(to_l, to_l + Vector2(cos(ang), sin(ang)) * 12.0, Color(SILVER.r, SILVER.g, SILVER.b, a), 2.0)
