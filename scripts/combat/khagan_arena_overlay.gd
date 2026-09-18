extends Node2D
class_name KhaganArenaOverlay

# Wave-10 boss (Khagan) persistent arena-ground treatment — "claimed war
# ground", not a wizard's summoning circle: two off-true concentric rings
# (one solid, one broken into marching segments) plus irregular tick marks,
# so it reads as trampled/marked territory rather than a magic rune. Present
# for the whole encounter; escalates at the dismount swap (Phase 2) and
# shifts palette at a successful possession landing (Phase 3). One instance
# per encounter — AutoBattleManager owns the single reference and all
# lifecycle calls (see _spawn_khagan_overlay/_clear_khagan_overlay,
# escalate_to_phase2/3 call sites in enemy_factory.gd + auto_battle_manager.gd).
#
# Every tween here is created via create_tween() ON THIS NODE, which Godot
# automatically binds to and kills alongside — nothing here can outlive this
# node being queue_free()'d (battle end, sandbox teardown, or otherwise).

const RING_COUNT := 2
const RADIUS_BASE := 150.0
const RADIUS_STEP := 26.0
const TICK_COUNT := 14
const TICK_LEN := 14.0
const SEGMENT_GAP_COUNT := 5   # breaks in the outer ring — "broken", not a clean circle

# Phase 1 — mounted, low presence.
const P1_ALPHA := 0.18
const P1_ROT_SPEED := 0.15      # rad/s
const P1_PULSE_PERIOD := 2.4    # s, ambient alpha breathing
const P1_PULSE_AMPLITUDE := 0.05

# Phase 2 — dismounted, stronger presence. Triggered at the dismount flash
# peak (enemy_factory.gd advance_khagan_phase's play_dismount_transform
# callback), not at the start of the phase-transform logic.
const P2_ALPHA := 0.34
const P2_ROT_SPEED := 0.32
const P2_PULSE_PERIOD := 1.4
const P2_PULSE_AMPLITUDE := 0.07
const ESCALATE_TWEEN_TIME := 0.6

# Phase 3 — possession lands. Short flare, then a stable violet idle state.
const P3_ALPHA := 0.30
const P3_ROT_SPEED := 0.22
const P3_PULSE_PERIOD := 1.8
const P3_PULSE_AMPLITUDE := 0.06
const FLARE_ALPHA := 0.75
const FLARE_ROT_SPEED := 0.70
const FLARE_DURATION := 0.35
const SHIFT_DURATION := 0.5

const COLOR_IRON := Color(0.72, 0.55, 0.22)     # iron/gold/ochre — plain 0-1 range
const COLOR_VIOLET := Color(0.5, 0.15, 0.7)     # hostile violet — plain 0-1 range

# Redraw is throttled to a fixed visual rate rather than every _process tick —
# rotation/pulse state still advances every frame for smooth tween math, only
# the (relatively expensive) draw_arc/draw_line calls are rate-limited.
const REDRAW_INTERVAL := 1.0 / 24.0

enum Phase { P1, P2, P3 }

var _phase: int = Phase.P1
var _rot_ang: float = 0.0
var _rot_speed: float = P1_ROT_SPEED
var _alpha: float = 0.0            # base alpha, tweened on phase change
var _color: Color = COLOR_IRON
var _pulse_t: float = 0.0
var _pulse_period: float = P1_PULSE_PERIOD
var _pulse_amplitude: float = P1_PULSE_AMPLITUDE
var _flare: float = 0.0            # extra transient alpha/rot boost during the phase-3 shift
var _redraw_accum: float = 0.0

# Khagan isn't rooted to his spawn cell — like any unit he walks the grid to
# reach targets — so the ground treatment has to track him, not just be
# planted once at setup(). Weak-ref-style: once Khagan's body is freed (real
# death, phase 3), is_instance_valid() goes false and the overlay simply
# freezes at his last known position instead of erroring or snapping away.
var _follow_target: Node2D = null

func setup(world_pos: Vector2, follow_target: Node2D = null) -> void:
	global_position = world_pos
	_follow_target = follow_target
	z_index = 0   # verified: BackgroundLayer/BattleGrid/SkillEffectContainer are all
	              # z_index=0/z_as_relative=true in the live scene (headless-checked) —
	              # skill_effect_container already renders above the floor purely via
	              # scene-tree add order (the same mechanism KhaganVFX's item-1 ring
	              # already relies on). z_index=0 here keeps this strictly BELOW unit
	              # sprites (explicit z=1), the possession icon (7), damage text (100),
	              # and items 1/2 (0 and 5) via real value comparison, not tie order.
	_alpha = P1_ALPHA
	_rot_speed = P1_ROT_SPEED
	_pulse_period = P1_PULSE_PERIOD
	_pulse_amplitude = P1_PULSE_AMPLITUDE
	_color = COLOR_IRON
	queue_redraw()

func _process(delta: float) -> void:
	if is_instance_valid(_follow_target):
		global_position = _follow_target.global_position
	_rot_ang = wrapf(_rot_ang + _rot_speed * delta, 0.0, TAU)
	_pulse_t += delta
	if _flare > 0.0:
		_flare = maxf(0.0, _flare - delta / FLARE_DURATION)
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		queue_redraw()

func escalate_to_phase2() -> void:
	if _phase != Phase.P1:
		return   # idempotent — a duplicate/out-of-order call can't restart or fight the tween
	_phase = Phase.P2
	var t := create_tween()
	t.set_parallel(true)
	t.tween_method(_set_alpha, _alpha, P2_ALPHA, ESCALATE_TWEEN_TIME)
	t.tween_method(_set_rot_speed, _rot_speed, P2_ROT_SPEED, ESCALATE_TWEEN_TIME)
	t.tween_method(_set_pulse_period, _pulse_period, P2_PULSE_PERIOD, ESCALATE_TWEEN_TIME)
	t.tween_method(_set_pulse_amplitude, _pulse_amplitude, P2_PULSE_AMPLITUDE, ESCALATE_TWEEN_TIME)

func escalate_to_phase3() -> void:
	if _phase == Phase.P3:
		return   # idempotent
	_phase = Phase.P3
	var t := create_tween()
	# Flare: quick punch up in alpha/rotation...
	t.tween_method(_set_flare, 0.0, 1.0, FLARE_DURATION * 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_method(_set_flare, 1.0, 0.0, FLARE_DURATION * 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# ...color shift runs in parallel with the flare, then settle to the P3 idle values.
	var shift := create_tween()
	shift.set_parallel(true)
	shift.tween_method(_set_color, _color, COLOR_VIOLET, SHIFT_DURATION)
	shift.tween_method(_set_alpha, _alpha, P3_ALPHA, SHIFT_DURATION)
	shift.tween_method(_set_rot_speed, _rot_speed, P3_ROT_SPEED, SHIFT_DURATION)
	shift.tween_method(_set_pulse_period, _pulse_period, P3_PULSE_PERIOD, SHIFT_DURATION)
	shift.tween_method(_set_pulse_amplitude, _pulse_amplitude, P3_PULSE_AMPLITUDE, SHIFT_DURATION)

func _set_alpha(v: float) -> void: _alpha = v
func _set_rot_speed(v: float) -> void: _rot_speed = v
func _set_color(v: Color) -> void: _color = v
func _set_pulse_period(v: float) -> void: _pulse_period = maxf(0.05, v)
func _set_pulse_amplitude(v: float) -> void: _pulse_amplitude = v
func _set_flare(v: float) -> void: _flare = v

func _draw() -> void:
	var pulse: float = sin(_pulse_t * TAU / _pulse_period) * _pulse_amplitude
	var eff_alpha: float = clamp(_alpha + pulse + _flare * (FLARE_ALPHA - _alpha), 0.0, 1.0)
	var eff_rot: float = _rot_ang + _flare * FLARE_ROT_SPEED * 0.5
	var col := Color(_color.r, _color.g, _color.b, eff_alpha)

	# Inner ring — solid, slow counter-rotation for a "marching" read.
	draw_arc(Vector2.ZERO, RADIUS_BASE, 0.0, TAU, 48, col, 3.0, true)

	# Outer ring — broken into segments (trampled war-ground, not a clean
	# summoning circle) rotating the opposite way.
	var outer_r: float = RADIUS_BASE + RADIUS_STEP
	var seg_span: float = TAU / float(SEGMENT_GAP_COUNT) * 0.7
	for i in range(SEGMENT_GAP_COUNT):
		var start_a: float = (TAU / float(SEGMENT_GAP_COUNT)) * i - eff_rot * 1.3
		draw_arc(Vector2.ZERO, outer_r, start_a, start_a + seg_span, 16, col, 4.0, true)

	# Irregular tick marks — varied length reads as "hastily staked ground",
	# not a precise ritual diagram.
	for i in range(TICK_COUNT):
		var a: float = (TAU / float(TICK_COUNT)) * i + eff_rot
		var len_variance: float = 1.0 + 0.35 * sin(float(i) * 2.399963)  # deterministic, no randf() per-frame
		var inner: Vector2 = Vector2(cos(a), sin(a)) * (RADIUS_BASE - 6.0)
		var outer: Vector2 = Vector2(cos(a), sin(a)) * (RADIUS_BASE - 6.0 - TICK_LEN * len_variance)
		draw_line(inner, outer, col, 2.0)
