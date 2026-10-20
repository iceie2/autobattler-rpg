extends Node2D
class_name GaleVFX

# The Gale Warden's visual language: A WING-BEAT THAT MOVES YOU.
#
# AIR grammar (see the Element VFX Language note, derived from HarpyVFX):
# tapered ribbons, smooth low-frequency curves, nested crescents — never jagged,
# never radial spikes, no saturated accent. Pale sky blue on a dark backing pass
# so it survives the bright air board.
#
# GUST: nested crescents sweep from the Warden into its target (the beat).
# SLIDE: ribbons stream along the path the victim was shoved, so the one-tile
# displacement — the Air decade's formation check — reads as the Warden's doing
# instead of a unit silently snapping to a new tile.

enum Mode { GUST, SLIDE, SCATTER }
# SCATTER (flock, 2026-09-28): a flockmate fell — this bird's dodge is gone for
# GALE_SCATTER_TIME. Ruffled feathers burst off it and drift down for exactly
# that long, so "the flock is exposed, hit it now" reads on the board.

const SHADE := Color(0.10, 0.13, 0.20)
const SKY := Color(0.70, 0.84, 1.0)
const WHITE := Color(0.96, 0.98, 1.0)

var mode: Mode = Mode.GUST
var _from := Vector2.ZERO    # global
var _to := Vector2.ZERO      # global
var _t := 0.0
var _life := 0.35

func setup(k: Mode, from_world: Vector2, to_world: Vector2) -> void:
	mode = k
	_from = from_world
	_to = to_world
	_life = 0.35 if k == Mode.GUST else 0.45
	z_index = 5
	queue_redraw()

var _host = null

func setup_scatter(bird) -> void:
	mode = Mode.SCATTER
	_host = bird
	_life = AutoBattleManager.GALE_SCATTER_TIME
	z_index = 6
	global_position = bird.global_position

func _process(delta: float) -> void:
	_t += delta
	if _host != null:
		if not is_instance_valid(_host) or _host.current_hp <= 0:
			queue_free(); return
		global_position = _host.global_position
	if _t >= _life:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	match mode:
		Mode.GUST: _draw_gust()
		Mode.SLIDE: _draw_slide()
		Mode.SCATTER: _draw_scatter()

# One feather: a tapered leaf shape with a dark spine, tumbling as it falls.
func _feather(c: Vector2, ang: float, s: float, a: float) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var n := d.orthogonal()
	var pts := PackedVector2Array([c - d * s, c + n * s * 0.32, c + d * s, c - n * s * 0.32])
	draw_colored_polygon(pts, Color(SHADE.r, SHADE.g, SHADE.b, 0.7 * a))
	var inner := PackedVector2Array([c - d * s * 0.8, c + n * s * 0.2, c + d * s * 0.8, c - n * s * 0.2])
	draw_colored_polygon(inner, Color(SKY.r, SKY.g, SKY.b, a))
	draw_line(c - d * s, c + d * s, Color(SHADE.r, SHADE.g, SHADE.b, a), 1.2)

func _draw_scatter() -> void:
	var k: float = _t / _life
	var a: float = 1.0 - k * k
	for i in 7:
		var seed: float = float(i) * 1.37
		# Burst outward in the first 20%, then drift down and sway.
		var burst: float = minf(1.0, _t / 0.25)
		var ang0: float = -PI * 0.9 + PI * 0.8 * float(i) / 6.0
		# Centred on the (small) bird's body and drifting down past its feet.
		var p := Vector2(cos(ang0), sin(ang0)) * 30.0 * burst + Vector2(0, 8)
		p += Vector2(sin(_t * 3.0 + seed) * 8.0, maxf(0.0, _t - 0.25) * 22.0)
		_feather(p, _t * 2.5 + seed, 7.0, a)

# A crescent: an arc drawn as a tapered band (thin at both tips).
func _crescent(c: Vector2, rad: float, facing: float, span: float, w: float, col: Color) -> void:
	var n := 14
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in n + 1:
		var f: float = float(i) / float(n)
		var ang: float = facing - span * 0.5 + span * f
		var thick: float = w * sin(f * PI)
		outer.append(c + Vector2(cos(ang), sin(ang)) * (rad + thick * 0.5))
		inner.append(c + Vector2(cos(ang), sin(ang)) * (rad - thick * 0.5))
	# Two triangles per segment — a triangle can't self-intersect.
	for i in n:
		draw_colored_polygon(PackedVector2Array([outer[i], outer[i + 1], inner[i]]), col)
		draw_colored_polygon(PackedVector2Array([outer[i + 1], inner[i + 1], inner[i]]), col)

func _draw_gust() -> void:
	var k: float = _t / _life
	var a: float = 1.0 - k * k
	var from: Vector2 = to_local(_from) + Vector2(0, -28)
	var to: Vector2 = to_local(_to) + Vector2(0, -28)
	var dir: Vector2 = (to - from)
	var facing: float = dir.angle()
	for i in 3:
		# Three nested crescents, staggered, racing from Warden to target.
		var lag: float = float(i) * 0.12
		var f: float = clampf((k - lag) / 0.6, 0.0, 1.0)
		if f <= 0.0:
			continue
		var c: Vector2 = from.lerp(to, f * 0.95)
		var rad: float = 22.0 + 10.0 * float(i)
		var al: float = a * (1.0 - float(i) * 0.22)
		_crescent(c, rad, facing, 1.9, 13.0, Color(SHADE.r, SHADE.g, SHADE.b, 0.55 * al))
		_crescent(c, rad, facing, 1.7, 8.0, Color(SKY.r, SKY.g, SKY.b, 0.9 * al))
		_crescent(c, rad, facing, 1.3, 3.0, Color(WHITE.r, WHITE.g, WHITE.b, al))

func _draw_slide() -> void:
	var k: float = _t / _life
	var a: float = 1.0 - k
	var from: Vector2 = to_local(_from)
	var to: Vector2 = to_local(_to)
	var d: Vector2 = to - from
	if d.length() < 1.0:
		return
	var n: Vector2 = d.orthogonal().normalized()
	# Four wind ribbons along the shove path at different heights on the body,
	# each a smooth tapered streak that stretches in behind the victim.
	for i in 4:
		var h: float = -8.0 - float(i) * 16.0
		var off: Vector2 = n * (float(i) - 1.5) * 5.0 + Vector2(0, h)
		var head: float = minf(1.0, k / 0.45)
		var tail: float = clampf((k - 0.15) / 0.8, 0.0, 1.0)
		var p0: Vector2 = from.lerp(to, tail) + off
		var p1: Vector2 = from.lerp(to, head) + off
		var seg := 10
		for layer in 2:
			var col: Color = SHADE if layer == 0 else SKY
			var wmax: float = 7.0 if layer == 0 else 3.5
			for j in seg:
				var f0: float = float(j) / float(seg)
				var f1: float = float(j + 1) / float(seg)
				var q0: Vector2 = p0.lerp(p1, f0) + n * sin(f0 * PI * 2.0 + _t * 10.0) * 3.0
				var q1: Vector2 = p0.lerp(p1, f1) + n * sin(f1 * PI * 2.0 + _t * 10.0) * 3.0
				var w: float = wmax * sin(f0 * PI) + 0.5
				draw_line(q0, q1, Color(col.r, col.g, col.b, a * (0.5 if layer == 0 else 0.9)), w)
