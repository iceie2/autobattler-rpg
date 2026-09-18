extends Node2D
class_name KhaganPossessionVFX

# Khagan's phase 2→3 possession seizure — a one-shot, self-cleaning three-part
# beat: spirit leaves Khagan's body → travels to the chosen hero → seizes
# them. Deliberately a SEPARATE class from KhaganVFX (the dismount burst):
# that effect is grounded/dusty and already tuned/approved, this one is
# spectral/hostile and needs a live-tracked travel phase KhaganVFX has no use
# for, so composing them would only make KhaganVFX harder to read. Everything
# here is procedural (draw_arc/Line2D/GPUParticles2D-free motes as plain
# Sprite2D with a generated dot texture) — no imported art.
#
# setup(source_pos, target) is called once right after this node is added to
# skill_effect_container. `source_pos` is a plain Vector2 snapshot (see the
# call site in AutoBattleManager.start_khagan_possession) so this effect never
# depends on Khagan's body node surviving past the moment it was captured.

const SOURCE_DURATION := 0.14
const SOURCE_COLOR := Color(0.55, 0.15, 0.75, 0.95)   # hostile violet
const SOURCE_MOTE_COUNT := 8
const SOURCE_RADIUS := 46.0

const TRAIL_DURATION := 0.28
const TRAIL_COLOR := Color(0.6, 0.2, 0.8, 0.85)
const TRAIL_WIDTH_NEAR_SOURCE := 10.0
const TRAIL_WIDTH_NEAR_TARGET := 2.0
const TRAIL_MOTE_COUNT := 4

const ARRIVAL_DURATION := 0.16
const ARRIVAL_COLOR := Color(0.75, 0.1, 0.35, 0.95)   # hostile crimson-violet
const ARRIVAL_MOTE_COUNT := 8
const ARRIVAL_RADIUS := 50.0

var _phase: int = 0   # 0=source, 1=trail, 2=arrival, 3=done
var _phase_t: float = 0.0
var _source_pos: Vector2 = Vector2.ZERO
var _target: Node2D = null
var _last_target_pos: Vector2 = Vector2.ZERO

var _line: Line2D
var _trail_motes: Array = []

func setup(source_pos: Vector2, target: Node2D) -> void:
	_source_pos = source_pos
	_target = target
	_last_target_pos = target.global_position if is_instance_valid(target) else source_pos
	queue_redraw()

func _process(delta: float) -> void:
	match _phase:
		0:
			_phase_t += delta
			queue_redraw()
			if _phase_t >= SOURCE_DURATION:
				_phase = 1
				_phase_t = 0.0
				_begin_trail()
		1:
			if not is_instance_valid(_target):
				# Target vanished mid-travel (edge case — see report). Nothing to
				# arrive at, so clean up now instead of seizing empty air.
				_end_trail()
				queue_free()
				return
			_phase_t += delta
			_last_target_pos = _target.global_position
			_update_trail()
			if _phase_t >= TRAIL_DURATION:
				_end_trail()
				_phase = 2
				_phase_t = 0.0
				_spawn_arrival_motes()
				queue_redraw()
		2:
			_phase_t += delta
			queue_redraw()
			if _phase_t >= ARRIVAL_DURATION:
				queue_free()

func _draw() -> void:
	if _phase == 0:
		var t: float = _phase_t / SOURCE_DURATION
		var col: Color = SOURCE_COLOR
		col.a *= (1.0 - t)
		# Shrinking ring — energy pulling IN on itself before it launches,
		# distinct from the dismount ring which expands outward.
		var radius: float = lerp(SOURCE_RADIUS, SOURCE_RADIUS * 0.35, t)
		draw_arc(to_local(_source_pos), radius, 0.0, TAU, 32, col, 4.0, true)
	elif _phase == 2:
		var t: float = _phase_t / ARRIVAL_DURATION
		var col: Color = ARRIVAL_COLOR
		col.a *= (1.0 - t)
		# Inward-collapsing ring at the target.
		var radius: float = lerp(ARRIVAL_RADIUS, ARRIVAL_RADIUS * 0.2, t)
		draw_arc(to_local(_last_target_pos), radius, 0.0, TAU, 32, col, 4.0, true)

# ── Phase A: source release motes ─────────────────────────────────────────
# Small upward/outward sprite motes at the captured source position — spawned
# alongside the shrinking ring drawn in _draw(). Free themselves independently
# so a slow frame doesn't stall the phase transition.
func _spawn_source_motes() -> void:
	for i in range(SOURCE_MOTE_COUNT):
		var m := Sprite2D.new()
		m.texture = _dot_texture()
		m.modulate = SOURCE_COLOR
		m.z_index = 0
		add_child(m)
		m.global_position = _source_pos
		var ang: float = randf() * TAU
		var dist: float = lerp(30.0, 70.0, randf())
		var dest: Vector2 = _source_pos + Vector2(cos(ang), sin(ang) - 0.6) * dist
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(m, "global_position", dest, SOURCE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_property(m, "modulate:a", 0.0, SOURCE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t.set_parallel(false)
		t.tween_callback(m.queue_free)

# ── Phase B: target-tracking trail ────────────────────────────────────────
func _begin_trail() -> void:
	_spawn_source_motes()
	_line = Line2D.new()
	_line.width = TRAIL_WIDTH_NEAR_SOURCE
	_line.default_color = TRAIL_COLOR
	_line.z_index = 0
	var widths := Curve.new()
	widths.add_point(Vector2(0.0, 1.0))
	widths.add_point(Vector2(1.0, TRAIL_WIDTH_NEAR_TARGET / TRAIL_WIDTH_NEAR_SOURCE))
	_line.width_curve = widths
	var grad := Gradient.new()
	grad.set_color(0, TRAIL_COLOR)
	grad.set_color(1, Color(TRAIL_COLOR.r, TRAIL_COLOR.g, TRAIL_COLOR.b, 0.0))
	_line.gradient = grad
	add_child(_line)
	_line.points = [to_local(_source_pos), to_local(_last_target_pos)]

	_trail_motes.clear()
	for i in range(TRAIL_MOTE_COUNT):
		var m := Sprite2D.new()
		m.texture = _dot_texture()
		m.modulate = TRAIL_COLOR
		m.scale = Vector2(0.8, 0.8)
		add_child(m)
		# Staggered start so motes read as a stream, not one clump.
		_trail_motes.append({"node": m, "delay": float(i) / float(TRAIL_MOTE_COUNT) * 0.5})

func _update_trail() -> void:
	var target_pos: Vector2 = _last_target_pos
	if _line and is_instance_valid(_line):
		_line.points = [to_local(_source_pos), to_local(target_pos)]
	var f: float = clamp(_phase_t / TRAIL_DURATION, 0.0, 1.0)
	for entry in _trail_motes:
		var m: Sprite2D = entry["node"]
		if not is_instance_valid(m):
			continue
		var local_f: float = clamp((f - entry["delay"]) / max(0.001, 1.0 - entry["delay"]), 0.0, 1.0)
		m.global_position = _source_pos.lerp(target_pos, local_f)
		m.visible = f >= entry["delay"]

func _end_trail() -> void:
	if _line and is_instance_valid(_line):
		_line.queue_free()
		_line = null
	for entry in _trail_motes:
		var m: Sprite2D = entry["node"]
		if is_instance_valid(m):
			m.queue_free()
	_trail_motes.clear()

# ── Phase C: arrival motes ─────────────────────────────────────────────────
# Mirror of _spawn_source_motes but converging INWARD onto the target, paired
# with the collapsing ring drawn in _draw(). Read together as "seized", not
# "hit" — no impact-flash red, no ground debris.
func _spawn_arrival_motes() -> void:
	if is_instance_valid(_target) and _target.has_method("play_possession_arrival_flash"):
		_target.play_possession_arrival_flash()
	var center: Vector2 = _last_target_pos
	for i in range(ARRIVAL_MOTE_COUNT):
		var m := Sprite2D.new()
		m.texture = _dot_texture()
		m.modulate = ARRIVAL_COLOR
		add_child(m)
		var ang: float = randf() * TAU
		var dist: float = lerp(45.0, 80.0, randf())
		var start: Vector2 = center + Vector2(cos(ang), sin(ang)) * dist
		m.global_position = start
		m.modulate.a = 0.0
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(m, "global_position", center, ARRIVAL_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t.tween_property(m, "modulate:a", ARRIVAL_COLOR.a, ARRIVAL_DURATION * 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.set_parallel(false)
		t.tween_callback(m.queue_free)

# ── Shared: small procedural dot texture (duplicated from KhaganVFX on
# purpose — this file stays decoupled so touching one boss beat can never
# regress the other; both are ~10 lines and trivially cheap to keep in sync
# by eye if the "soft dot" look ever needs to change). ──────────────────────
static func _dot_texture() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var center := Vector2(8, 8)
	for y in range(16):
		for x in range(16):
			var dist: float = Vector2(x, y).distance_to(center)
			var a: float = pow(clamp(1.0 - dist / 7.0, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
