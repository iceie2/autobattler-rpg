extends Node2D
class_name TideVFX

# The Tidecaller's visual language: THE CONCH CALLS THE TIDE.
#
# Its body is a coral-crusted stone warden with sapphire eyes and a glowing
# conch, so its water is SAPPHIRE and FOAM — deliberately not the Coral Husk's
# teal/coral, and not Nemi's bouncing wave (a hero's language, which Tidal Ward
# used to borrow via SkillEffect.TIDE_WAVE).
#
# FONT (persistent, on the Tidecaller): a faint ripple rolls out to the aura's
# TRUE reach every few seconds, and every ally it is healing gets rising
# droplets — the regen used to have no visual at all.
# WARD (one-shot): a stream from the Tidecaller to the shielded ally that closes
# into a bubble dome around them.

enum Mode { FONT, WARD, REEF }
# REEF (one-shot, Call of the Reef ultimate 2026-09-30): a stream arcs from the
# Tidecaller's conch to each spawn spot, then a sapphire splash with pink coral
# spikes bursting up as each husk rises — so the new bodies read as SUMMONED.
const CORAL_PINK := Color(0.96, 0.52, 0.62)
var _spots: Array = []       # REEF: global spawn positions

const NAVY := Color(0.04, 0.08, 0.22)
const SAPPHIRE := Color(0.24, 0.55, 1.0)
const FOAM := Color(0.90, 0.97, 1.0)
const RIPPLE_EVERY := 3.0
const PLANE_SQUASH := 0.55   # board is a faked-perspective plane

var mode: Mode = Mode.FONT
var host = null
var reach_px := 440.0        # FONT: aura radius in board pixels
var recipients: Array = []   # FONT: global positions of allies being healed
var _from := Vector2.ZERO
var _target = null
var _t := 0.0
var _life := INF

func setup_font(unit, radius_px: float) -> void:
	mode = Mode.FONT
	host = unit
	reach_px = radius_px
	z_index = 1              # ground ripple sits under bodies
	global_position = unit.global_position

func setup_ward(caster, target) -> void:
	mode = Mode.WARD
	_life = 0.75
	z_index = 5
	_from = caster.global_position + Vector2(0, -40)
	_target = target
	global_position = target.global_position

func setup_reef(caller, spots: Array) -> void:
	mode = Mode.REEF
	_life = 0.9
	z_index = 6
	_from = caller.global_position + Vector2(0, -44)
	_spots = spots
	global_position = Vector2.ZERO

func set_recipients(pts: Array) -> void:
	recipients = pts

func _process(delta: float) -> void:
	_t += delta
	if host != null:
		if not is_instance_valid(host) or host.current_hp <= 0:
			queue_free(); return
		global_position = host.global_position
	if _target and is_instance_valid(_target):
		global_position = _target.global_position
	if _t >= _life:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	match mode:
		Mode.FONT: _draw_font()
		Mode.WARD: _draw_ward()
		Mode.REEF: _draw_reef()

func _draw_reef() -> void:
	var k: float = _t / _life
	var from: Vector2 = to_local(_from)
	for sp in _spots:
		var to: Vector2 = to_local(sp) + Vector2(0, 20)
		# Stream pours in over the first 35%.
		var pour: float = minf(1.0, k / 0.35)
		var fade: float = 1.0 - clampf((k - 0.35) / 0.3, 0.0, 1.0)
		if fade > 0.0:
			var pts := PackedVector2Array()
			for i in 13:
				var f: float = float(i) / 12.0 * pour
				pts.append(from.lerp(to, f) + Vector2(0, -sin(f * PI) * 50.0))
			draw_polyline(pts, Color(NAVY.r, NAVY.g, NAVY.b, 0.8 * fade), 12.0)
			draw_polyline(pts, Color(SAPPHIRE.r, SAPPHIRE.g, SAPPHIRE.b, fade), 7.0)
			draw_polyline(pts, Color(FOAM.r, FOAM.g, FOAM.b, fade), 2.5)
		if k < 0.3:
			continue
		# Splash + coral spikes erupting at the spawn spot.
		var e: float = (k - 0.3) / 0.7
		var a: float = 1.0 - e
		draw_set_transform(to, 0.0, Vector2(1.0, PLANE_SQUASH))
		draw_arc(Vector2.ZERO, 16.0 + 38.0 * e, 0, TAU, 32, Color(NAVY.r, NAVY.g, NAVY.b, 0.7 * a), 8.0)
		draw_arc(Vector2.ZERO, 16.0 + 38.0 * e, 0, TAU, 32, Color(FOAM.r, FOAM.g, FOAM.b, a), 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var rise: float = minf(1.0, e / 0.4)
		for j in 5:
			var x: float = (float(j) - 2.0) * 11.0
			var h: float = (22.0 + float((j * 7) % 3) * 8.0) * rise
			var base := to + Vector2(x, 0)
			var spike := PackedVector2Array([base + Vector2(-5, 0), base + Vector2(5, 0), base + Vector2(0, -h)])
			draw_colored_polygon(spike, Color(NAVY.r, NAVY.g, NAVY.b, a))
			draw_colored_polygon(PackedVector2Array([base + Vector2(-3, 0), base + Vector2(3, 0), base + Vector2(0, -h + 3)]),
				Color(CORAL_PINK.r, CORAL_PINK.g, CORAL_PINK.b, a))

func _draw_font() -> void:
	var ph: float = fposmod(_t, RIPPLE_EVERY) / RIPPLE_EVERY
	if ph < 0.6:
		var k: float = ph / 0.6
		var a: float = sin(k * PI) * 0.75
		draw_set_transform(Vector2(0, 30), 0.0, Vector2(1.0, PLANE_SQUASH))
		draw_arc(Vector2.ZERO, reach_px * k, 0, TAU, 64, Color(NAVY.r, NAVY.g, NAVY.b, a * 0.8), 10.0)
		draw_arc(Vector2.ZERO, reach_px * k, 0, TAU, 64, Color(SAPPHIRE.r, SAPPHIRE.g, SAPPHIRE.b, a), 5.0)
		draw_arc(Vector2.ZERO, reach_px * k * 0.96, 0, TAU, 64, Color(FOAM.r, FOAM.g, FOAM.b, a), 2.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Droplets rising off every ally being healed.
	for i in recipients.size():
		var base: Vector2 = to_local(recipients[i])
		for j in 3:
			var dph: float = fposmod(_t * 0.8 + float(j) / 3.0 + float(i) * 0.37, 1.0)
			var p := base + Vector2((float(j) - 1.0) * 10.0, -10.0 - dph * 50.0)
			var s: float = 6.5 * (1.0 - dph * 0.5)
			draw_circle(p, s + 2.5, Color(NAVY.r, NAVY.g, NAVY.b, 0.6 * (1.0 - dph)))
			draw_circle(p, s, Color(SAPPHIRE.r, SAPPHIRE.g, SAPPHIRE.b, 0.9 * (1.0 - dph)))
			draw_circle(p + Vector2(-1.5, -1.5), s * 0.55, Color(FOAM.r, FOAM.g, FOAM.b, 0.9 * (1.0 - dph)))

func _draw_ward() -> void:
	var k: float = _t / _life
	var from: Vector2 = to_local(_from)
	var to := Vector2(0, -34)
	# Stream: a smooth arcing ribbon that pours in over the first 40%.
	var pour: float = minf(1.0, k / 0.4)
	var fade: float = 1.0 - clampf((k - 0.4) / 0.3, 0.0, 1.0)
	if fade > 0.0:
		var pts := PackedVector2Array()
		for i in 17:
			var f: float = float(i) / 16.0 * pour
			pts.append(from.lerp(to, f) + Vector2(0, -sin(f * PI) * 60.0))
		draw_polyline(pts, Color(NAVY.r, NAVY.g, NAVY.b, 0.85 * fade), 15.0)
		draw_polyline(pts, Color(SAPPHIRE.r, SAPPHIRE.g, SAPPHIRE.b, fade), 9.0)
		draw_polyline(pts, Color(FOAM.r, FOAM.g, FOAM.b, fade), 4.0)
	# Dome: rises around the target once the stream lands.
	if k > 0.35:
		var dk: float = clampf((k - 0.35) / 0.35, 0.0, 1.0)
		var a: float = 1.0 - clampf((k - 0.75) / 0.25, 0.0, 1.0)
		var rad: float = 56.0 * (0.4 + 0.6 * dk)
		draw_circle(to, rad, Color(FOAM.r, FOAM.g, FOAM.b, 0.16 * a))
		draw_arc(to, rad, 0, TAU, 40, Color(NAVY.r, NAVY.g, NAVY.b, 0.8 * a), 8.0)
		draw_arc(to, rad, 0, TAU, 40, Color(FOAM.r, FOAM.g, FOAM.b, 0.95 * a), 3.5)
		draw_arc(to, rad * 0.8, -PI * 0.85, -PI * 0.55, 10, Color(FOAM.r, FOAM.g, FOAM.b, a), 3.0)
