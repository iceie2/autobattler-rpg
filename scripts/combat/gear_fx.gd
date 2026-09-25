extends Node2D
class_name GearFX

# Procedural in-combat cues for the 36 item passives (EQUIPMENT_GREEN_PAIRS.md
# cue table). Standing rule: every passive must be SEEN firing. Shared language:
# violet = "an item did this", gold = crits, green = heals, blue = mana. No cue
# borrows an element's look. Everything is drawn here, so no art is required.

enum Kind { BUBBLE, TEXT, WISP, STREAK, MOTES, RINGS, SPARK, SPEED, MARK, BURST, SWIRL, FLARE }

const VIOLET := Color(0.69, 0.42, 1.0)          # #B06CFF, same as the item shield
const GOLD := Color(1.0, 0.84, 0.0)
const HEAL := Color(0.25, 0.95, 0.35)
const MANA := Color(0.35, 0.65, 1.0)
const BLOOD := Color(0.9, 0.15, 0.2)
const STEEL := Color(0.78, 0.82, 0.88)
const BRASS := Color(0.85, 0.65, 0.25)
const WHITE := Color(1, 1, 1)
const THROTTLE := 0.25   # seconds between repeats of one cue on one unit

var kind: int = Kind.BUBBLE
var color: Color = VIOLET
var life: float = 0.5
var age: float = 0.0
var size: float = 40.0
var text: String = ""
var to_pos: Vector2 = Vector2.ZERO
var count: int = 1
var follow: Node2D = null
var _seed: int = 0

static var _last: Dictionary = {}   # "unit_id:key" -> engine time (s)
static var spawn_counts: Dictionary = {}   # Kind name -> cues drawn (capture/arena telemetry)

static func _host(unit: Node) -> Node:
	var mgr = unit.get("battle_manager") if unit else null
	if mgr == null or not is_instance_valid(mgr):
		return null
	var host = mgr.get("skill_effect_container")
	return host if host and is_instance_valid(host) else mgr

# True when this cue may fire now (per-unit throttle).
static func can(unit: Node, key: String, gap: float = THROTTLE) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var id := "%d:%s" % [unit.get_instance_id(), key]
	if now - float(_last.get(id, -99.0)) < gap:
		return false
	_last[id] = now
	return true

static func spawn(unit: Node2D, p_kind: int, p_color: Color, p_life: float = 0.5,
		p_size: float = 40.0, p_text: String = "", p_to: Vector2 = Vector2.ZERO,
		p_count: int = 1, p_follow: bool = true) -> GearFX:
	if unit == null or not is_instance_valid(unit):
		return null
	var host := _host(unit)
	if host == null:
		return null
	var kname: String = Kind.keys()[p_kind]
	spawn_counts[kname] = int(spawn_counts.get(kname, 0)) + 1
	var fx := GearFX.new()
	fx.kind = p_kind
	fx.color = p_color
	fx.life = p_life
	fx.size = p_size
	fx.text = p_text
	fx.to_pos = p_to
	fx.count = p_count
	fx.follow = unit if p_follow else null
	fx._seed = randi()
	fx.z_index = 60
	host.add_child(fx)
	fx.global_position = unit.global_position
	return fx

# ── Convenience wrappers named after what they show ──────────────────────────
static func bubble(unit: Node2D, c: Color = VIOLET, r: float = 46.0) -> void:
	spawn(unit, Kind.BUBBLE, c, 0.45, r)

static func pop(unit: Node2D, t: String, c: Color = VIOLET, big: bool = false) -> void:
	spawn(unit, Kind.TEXT, c, 0.9, 22.0 if big else 16.0, t)

static func wisp(from_unit: Node2D, to_unit: Node2D, c: Color) -> void:
	if to_unit and is_instance_valid(to_unit):
		spawn(from_unit, Kind.WISP, c, 0.4, 7.0, "", to_unit.global_position, 1, false)

static func streak(from_unit: Node2D, to_unit: Node2D, c: Color = WHITE) -> void:
	if to_unit and is_instance_valid(to_unit):
		spawn(from_unit, Kind.STREAK, c, 0.3, 4.0, "", to_unit.global_position, 1, false)

static func motes(unit: Node2D, c: Color, n: int = 3) -> void:
	spawn(unit, Kind.MOTES, c, 0.8, 26.0, "", Vector2.ZERO, n)

static func rings(unit: Node2D, n: int, c: Color = VIOLET) -> void:
	spawn(unit, Kind.RINGS, c, 0.6, 30.0, "", Vector2.ZERO, n)

static func spark(unit: Node2D, c: Color = VIOLET) -> void:
	spawn(unit, Kind.SPARK, c, 0.3, 18.0)

static func speed(unit: Node2D) -> void:
	spawn(unit, Kind.SPEED, WHITE, 0.5, 34.0)

static func mark(unit: Node2D, glyph: String, c: Color) -> void:
	spawn(unit, Kind.MARK, c, 0.7, 18.0, glyph)

static func burst(unit: Node2D, c: Color, n: int = 8) -> void:
	spawn(unit, Kind.BURST, c, 0.35, 38.0, "", Vector2.ZERO, n)

static func swirl(unit: Node2D, c: Color) -> void:
	spawn(unit, Kind.SWIRL, c, 0.6, 30.0)

static func flare(unit: Node2D, c: Color = STEEL) -> void:
	spawn(unit, Kind.FLARE, c, 0.4, 44.0)

func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	if follow and is_instance_valid(follow):
		global_position = follow.global_position
	queue_redraw()

func _draw() -> void:
	var t := clampf(age / life, 0.0, 1.0)
	var a := 1.0 - t
	var c := Color(color, a)
	var head := Vector2(0, -48)   # roughly chest/head height above the feet anchor
	match kind:
		Kind.BUBBLE:
			draw_arc(head * 0.6, size * (0.7 + 0.3 * t), 0, TAU, 40, c, 4.0 * a + 1.0, true)
			draw_circle(head * 0.6, size * (0.7 + 0.3 * t), Color(color, 0.18 * a))
		Kind.FLARE:
			var s := size * (0.6 + 0.6 * t)
			var pts := PackedVector2Array([head * 0.6 + Vector2(-s * 0.5, -s * 0.6),
				head * 0.6 + Vector2(s * 0.5, -s * 0.6), head * 0.6 + Vector2(s * 0.45, s * 0.1),
				head * 0.6 + Vector2(0, s * 0.7), head * 0.6 + Vector2(-s * 0.45, s * 0.1)])
			draw_colored_polygon(pts, Color(color, 0.35 * a))
			pts.append(pts[0])
			draw_polyline(pts, c, 3.0)
		Kind.TEXT:
			var font := ThemeDB.fallback_font
			var fs := int(size)
			var pos := head + Vector2(-font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / 2.0, -26.0 * t)
			draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, a))
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		Kind.WISP, Kind.STREAK:
			var target := to_pos - global_position
			var from := head * 0.5
			var to := target + head * 0.5
			if kind == Kind.STREAK:
				draw_line(from, to, c, size * a + 1.0, true)
			else:
				var p := from.lerp(to, t)
				for i in range(5):
					var q := from.lerp(to, maxf(0.0, t - i * 0.05))
					draw_circle(q, size * (1.0 - i * 0.17), Color(color, a * (1.0 - i * 0.2)))
				draw_circle(p, size, c)
		Kind.MOTES:
			var rng := RandomNumberGenerator.new()
			rng.seed = _seed
			for i in range(count):
				var x := rng.randf_range(-size, size)
				draw_circle(Vector2(x, -10.0 - 50.0 * t - i * 6.0), 3.0, c)
		Kind.RINGS:
			for i in range(count):
				draw_arc(Vector2(0, -4), size * (1.0 + i * 0.28), 0, TAU, 32,
					Color(color, a * 0.8), 2.0, true)
		Kind.SPARK:
			for i in range(6):
				var ang := TAU * i / 6.0 + _seed % 7
				var d := Vector2.from_angle(ang)
				draw_line(head * 0.5 + d * size * 0.3 * t, head * 0.5 + d * size * (0.4 + 0.6 * t), c, 2.0)
		Kind.BURST:
			for i in range(count):
				var d := Vector2.from_angle(TAU * i / count)
				draw_line(head * 0.4 + d * size * 0.4, head * 0.4 + d * size * (0.6 + 0.5 * t), c, 3.0)
		Kind.SPEED:
			for i in range(4):
				var y := -20.0 - i * 12.0
				var x := size * (0.5 + t)
				draw_line(Vector2(-x, y), Vector2(-x + 22.0, y), c, 2.0)
				draw_line(Vector2(x - 22.0, y), Vector2(x, y), c, 2.0)
		Kind.MARK:
			var font := ThemeDB.fallback_font
			var fs := int(size)
			var pos := head + Vector2(-fs * 0.3, -18.0)
			draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, a))
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		Kind.SWIRL:
			for i in range(3):
				draw_arc(head * 0.5, size * (0.5 + 0.2 * i), t * TAU + i * 2.0, t * TAU + i * 2.0 + 2.2,
					16, c, 2.5, true)
