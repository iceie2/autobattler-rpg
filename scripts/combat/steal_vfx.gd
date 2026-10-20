extends Node2D
class_name StealVFX

# The Stat Stealer's visual language: SAND RUNNING THROUGH ITS HOURGLASS.
#
# Its body is a hooded skeletal thief with a glowing teal hourglass amulet and
# floating stat runes, so: teal hourglass SAND for what it takes, robe VIOLET
# for its own magic. Its whole mechanic was invisible — the 10s drain showed one
# generic spark at cast, and the stats it keeps until death showed nothing.
#
# SIPHON (persistent, per victim while draining): sand streams from the victim
#   into the Stealer, labelled with the stat being taken.
# HELD (persistent, on the Stealer): one rune orbits it per stat it is holding —
#   "kill it and you get these back".
# WARD (one-shot): its Siphon Ward shield, a violet rune circle (replaces the
#   Monk hero's CHI_BURST it used to borrow).

enum Mode { SIPHON, HELD, WARD }

const DARK := Color(0.07, 0.04, 0.10)
const SAND := Color(0.35, 0.95, 0.85)
const VIOLET := Color(0.70, 0.45, 1.0)
const LABELS := {"attack_damage": "ATK", "crit_chance": "CRIT", "crit_damage": "CDMG",
	"attack_speed": "SPD", "magic_power": "MAG", "resistance": "ARM"}

var mode: Mode = Mode.SIPHON
var host = null              # SIPHON: the victim; HELD/WARD: the Stealer
var source = null            # SIPHON: the Stealer
var stat := ""
var held := 0                # HELD: number of stats currently held
var r := 33.0
var _t := 0.0
var _life := INF

func setup(k: Mode, unit, src = null, stat_name: String = "") -> void:
	mode = k
	host = unit
	source = src
	stat = stat_name
	r = MirrorVFX.body_r(unit)
	z_index = 5
	if k == Mode.WARD:
		_life = 0.6
	global_position = unit.global_position

func _process(delta: float) -> void:
	_t += delta
	if not (host and is_instance_valid(host)) or host.current_hp <= 0:
		queue_free(); return
	global_position = host.global_position
	if _t >= _life:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	match mode:
		Mode.SIPHON: _draw_siphon()
		Mode.HELD:   _draw_held()
		Mode.WARD:   _draw_ward()

func _draw_siphon() -> void:
	if not (source and is_instance_valid(source)):
		return
	var from := Vector2(0, -r * 0.7)
	var to: Vector2 = to_local(source.global_position) + Vector2(0, -source.shape_size * 0.5)
	var d: Vector2 = to - from
	var n: Vector2 = d.orthogonal().normalized()
	# Faint channel, then grains of sand running along it toward the Stealer.
	draw_line(from, to, Color(DARK.r, DARK.g, DARK.b, 0.5), 10.0)
	draw_line(from, to, Color(SAND.r, SAND.g, SAND.b, 0.45), 4.0)
	for i in 14:
		var f: float = fposmod(_t * 0.7 + float(i) / 14.0, 1.0)
		var p: Vector2 = from + d * f + n * sin(f * PI * 3.0 + float(i)) * 5.0
		draw_circle(p, 5.5, DARK)
		draw_circle(p, 3.8, SAND)
	# What is being taken, over the victim's head.
	var label: String = LABELS.get(stat, "?")
	var font: Font = ThemeDB.fallback_font
	var fs := 15
	var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var lp := Vector2(-tw * 0.5 - r * 0.9, -r * 1.05)
	draw_rect(Rect2(lp + Vector2(-4, -fs + 1), Vector2(tw + 20, fs + 4)), Color(DARK.r, DARK.g, DARK.b, 0.85))
	draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, SAND)
	# Drawn down-arrow (the fallback font has no arrow glyph).
	var ax: float = lp.x + tw + 9.0
	draw_colored_polygon(PackedVector2Array([Vector2(ax - 5, lp.y - 9), Vector2(ax + 5, lp.y - 9), Vector2(ax, lp.y - 1)]), Color(1, 0.4, 0.4))

func _draw_held() -> void:
	if held <= 0:
		return
	for i in held:
		var ang: float = _t * 1.4 + TAU * float(i) / float(held)
		var p := Vector2(cos(ang) * r * 1.35, -r * 0.9 + sin(ang) * r * 0.4)
		draw_rect(Rect2(p - Vector2(9, 9), Vector2(18, 18)), DARK)
		draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), SAND)
		draw_circle(p, 2.5, Color(1, 1, 1))

func _draw_ward() -> void:
	var k: float = _t / _life
	var a: float = 1.0 - k
	var c := Vector2(0, -r * 0.6)
	var rad: float = r * (0.9 + 0.3 * k)
	draw_arc(c, rad, 0, TAU, 48, Color(DARK.r, DARK.g, DARK.b, 0.7 * a), 9.0)
	draw_arc(c, rad, 0, TAU, 48, Color(VIOLET.r, VIOLET.g, VIOLET.b, a), 4.0)
	for i in 6:
		var ang: float = TAU * float(i) / 6.0 + k * 1.5
		var p: Vector2 = c + Vector2(cos(ang), sin(ang)) * rad
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Color(DARK.r, DARK.g, DARK.b, a))
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(SAND.r, SAND.g, SAND.b, a))
