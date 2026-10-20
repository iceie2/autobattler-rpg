extends Node2D
class_name AnthillVFX

# The Ant Hill's visual language: THE MOUND BOILS OVER.
#
# Its threat is a battle-wide, UNCAPPED swarm-rage counter — every Ant bite makes
# every Ant's next bite hit harder — and none of it was visible: ants popped
# onto empty tiles with only a log line, and the counter climbed in silence.
# RAGE (persistent, on the Hill): the counter itself, plus a ground ring whose
#   pulse quickens and reddens as it climbs. It's a DPS check; now you can see
#   the clock.
# BURROW (one-shot, at a spawn cell): dirt clods burst out as an ant emerges.

enum Mode { RAGE, BURROW }

const SOIL := Color(0.40, 0.26, 0.14)
const SOIL_DARK := Color(0.14, 0.08, 0.04)
const RAGE_RED := Color(1.0, 0.18, 0.12)

var mode: Mode = Mode.RAGE
var host = null
var r := 60.0
var stacks := 0
var _t := 0.0
var _life := INF

func setup_rage(hill) -> void:
	mode = Mode.RAGE
	host = hill
	r = MirrorVFX.body_r(hill)
	z_index = 5
	global_position = hill.global_position

func setup_burrow(world_pos: Vector2) -> void:
	mode = Mode.BURROW
	_life = 0.45
	z_index = 4
	global_position = world_pos

func _process(delta: float) -> void:
	_t += delta
	if host != null:
		if not is_instance_valid(host) or host.current_hp <= 0:
			queue_free(); return
		global_position = host.global_position
	if _t >= _life:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	if mode == Mode.RAGE: _draw_rage()
	else: _draw_burrow()

func _draw_rage() -> void:
	# Heat: 0 at no stacks → 1 around 60 stacks (log-shaped so early bites show).
	var heat: float = clampf(log(1.0 + float(stacks)) / log(61.0), 0.0, 1.0)
	var rate: float = lerpf(0.6, 3.0, heat)
	var ph: float = fposmod(_t * rate, 1.0)
	draw_set_transform(Vector2(0, r * 0.55), 0.0, Vector2(1.0, 0.38))
	draw_arc(Vector2.ZERO, r * (0.9 + 0.35 * ph), 0, TAU, 48,
		Color(RAGE_RED.r, RAGE_RED.g, RAGE_RED.b, (0.35 + 0.6 * heat) * (1.0 - ph)), 5.0 + 5.0 * heat)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if stacks <= 0:
		return
	var font: Font = ThemeDB.fallback_font
	var fs := 26
	var label := "RAGE %d" % stacks
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(-tw * 0.5, r * 0.95)   # open ground in front of the mound
	var pulse: float = 1.0 + 0.08 * heat * sin(_t * rate * TAU)
	draw_set_transform(p + Vector2(tw * 0.5, -fs * 0.4), 0.0, Vector2(pulse, pulse))
	var lp := Vector2(-tw * 0.5, fs * 0.4)
	draw_rect(Rect2(lp + Vector2(-5, -fs + 1), Vector2(tw + 10, fs + 5)), Color(0.08, 0.02, 0.02, 0.85))
	draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, RAGE_RED.lerp(Color(1, 0.9, 0.8), 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_burrow() -> void:
	var k: float = _t / _life
	var a: float = 1.0 - k
	draw_set_transform(Vector2(0, 20), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 22.0 * (0.6 + 0.4 * k), Color(SOIL_DARK.r, SOIL_DARK.g, SOIL_DARK.b, 0.6 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 8:
		var ang: float = -PI * 0.1 - PI * 0.8 * float(i) / 7.0
		var dist: float = 10.0 + 34.0 * k
		var p := Vector2(cos(ang) * dist, 16.0 + sin(ang) * dist * 1.2 + 60.0 * k * k)
		var s: float = 4.5 - float(i % 3)
		draw_circle(p, s + 1.5, Color(SOIL_DARK.r, SOIL_DARK.g, SOIL_DARK.b, a))
		draw_circle(p, s, Color(SOIL.r, SOIL.g, SOIL.b, a))
