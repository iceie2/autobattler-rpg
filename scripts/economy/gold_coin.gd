extends Node2D
class_name GoldCoin
# ══════════════════════════════════════════════════════════════════════════════
# Physical gold drop (2026-07-03 economy rework). Enemies drop these on death;
# they scatter with a little toss, glint on the field for the rest of the fight,
# then — when the round is won — every coin gets VACUUMED: a spiral orbit that
# tightens under accelerating "gravity" toward the gold counter, crediting gold
# only when a coin actually arrives. This is THE gold-collection mechanic now.
# ══════════════════════════════════════════════════════════════════════════════

signal collected(value: int)

enum State { TOSS, IDLE, VACUUM }

var value: int = 1
var state: State = State.TOSS

const TEX: Texture2D = preload("res://assets/UI/Vector_UI_Pack_dobo_ui/Icons/64px/coin_icon_64px.png")
const TOSS_TIME := 0.85         # hard cap; the arc normally lands well before
const TOSS_GRAVITY := 700.0     # px/s^2 pulling the coin back to the plane
const TOSS_SPEED_MIN := 40.0    # ground-plane drift off the corpse
const TOSS_SPEED_MAX := 118.0
const TOSS_LIFT_MIN := 180.0    # upward kick — sets the height of the arc
const TOSS_LIFT_MAX := 245.0
const GROUND_SQUASH := 0.55     # faked-perspective board: less travel on Y
const SHADOW_SCALE := 0.36
const SHADOW_SQUASH := 0.34
const PULL_ACCEL := 2400.0      # inward gravity during vacuum
const ARRIVE_RADIUS := 8.0

var _sprite: Sprite2D
var _shadow: Sprite2D
var _vel: Vector2               # ground-plane drift during the toss
var _h: float = 0.0             # height ABOVE the board plane (px, positive up)
var _vh: float = 0.0            # vertical speed of the arc
var _toss_t: float = 0.0
var _bob_phase: float = 0.0
# Burst fan: set by GoldCoinSystem before add_child so a handful of coins leaves
# the corpse as a spread instead of every coin picking the same random cone.
var toss_index: int = 0
var toss_total: int = 1
var toss_power: float = 1.0
# vacuum spiral state (polar around the collection point)
var _target: Vector2
var _angle: float = 0.0
var _radius: float = 0.0
var _radial_speed: float = 60.0
var _delay: float = 0.0

func _ready() -> void:
	# Landing shadow FIRST so it draws under the coin. It is the coin texture
	# crushed flat and blacked out — without it the arc reads as "floating
	# disc", which is exactly what the 2026-09-16 burst report described.
	_shadow = Sprite2D.new()
	_shadow.texture = TEX
	_shadow.modulate = Color(0, 0, 0, 0.45)
	_shadow.scale = Vector2(SHADOW_SCALE, SHADOW_SCALE * SHADOW_SQUASH)
	add_child(_shadow)

	_sprite = Sprite2D.new()
	_sprite.texture = TEX
	_sprite.scale = Vector2(0.3, 0.3)   # 64px source → ~19px on the field
	add_child(_sprite)
	z_index = 40
	_bob_phase = randf() * TAU

	# Burst out of the corpse: an even fan on the ground plane plus an upward
	# kick, so every coin's path traces back to the body it came from.
	var base_a: float = TAU * (float(toss_index) + 0.5) / float(maxi(toss_total, 1))
	var a: float = base_a + randf_range(-0.25, 0.25)
	var speed: float = randf_range(TOSS_SPEED_MIN, TOSS_SPEED_MAX) * toss_power
	# The board is drawn in faked perspective, so horizontal travel reads
	# further than vertical — squash the ground-plane drift on Y to match.
	_vel = Vector2(cos(a), sin(a) * GROUND_SQUASH) * speed
	_vh = randf_range(TOSS_LIFT_MIN, TOSS_LIFT_MAX)
	_h = 0.0
	# Spawn slightly squashed and pop to full size — reads as "dropped".
	scale = Vector2(0.4, 0.4)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_apply_height()

# Lift the coin sprite off the board plane and shrink/fade its shadow with
# height. `position` itself always stays ON the plane, so y-sorting, the hover
# check and the vacuum all keep working against the real ground point.
func _apply_height() -> void:
	_sprite.position.y = -_h
	var k: float = clampf(1.0 - _h / 90.0, 0.35, 1.0)
	_shadow.scale = Vector2(SHADOW_SCALE * k, SHADOW_SCALE * SHADOW_SQUASH * k)
	_shadow.modulate.a = 0.45 * k
	_shadow.visible = state != State.VACUUM

func _process(delta: float) -> void:
	match state:
		State.TOSS:
			_toss_t += delta
			# Arc: height is a real parabola over the board plane while the
			# coin drifts outward along it. Drag bleeds the drift off so coins
			# settle in a tight ring around the corpse, not across the field.
			_vh -= TOSS_GRAVITY * delta
			_h = maxf(_h + _vh * delta, 0.0)
			position += _vel * delta
			_vel = _vel.lerp(Vector2.ZERO, minf(delta * 2.2, 1.0))
			_apply_height()
			# Land once the arc comes back down to the plane.
			if _h <= 0.0 or _toss_t >= TOSS_TIME:
				_h = 0.0
				_vh = 0.0
				_apply_height()
				state = State.IDLE
		State.IDLE:
			# Gentle glint-bob so the field of coins feels alive, not static.
			_bob_phase += delta * 3.0
			_sprite.position.y = sin(_bob_phase) * 1.5
		State.VACUUM:
			if _delay > 0.0:
				_delay -= delta
				return
			if _shadow.visible:
				_shadow.visible = false
			_radial_speed += PULL_ACCEL * delta
			_radius = maxf(_radius - _radial_speed * delta, 0.0)
			# Orbit speeds up as gravity wins — classic sink-spiral.
			_angle += (3.0 + 320.0 / maxf(_radius, 45.0)) * delta
			position = _target + Vector2(cos(_angle), sin(_angle)) * _radius
			# Shrink as it closes so it reads as "sucked into" the counter.
			var s: float = clampf(_radius / 260.0 + 0.45, 0.45, 1.0)
			scale = Vector2(s, s)
			if _radius <= ARRIVE_RADIUS:
				collected.emit(value)
				queue_free()

# Begin the spiral pull toward `target` (screen/world coords are the same here —
# the battlefield has no moving camera). `delay` staggers coins into a wave.
func start_vacuum(target: Vector2, delay: float = 0.0) -> void:
	if state == State.VACUUM:
		return
	state = State.VACUUM
	_shadow.visible = false
	_sprite.position.y = 0.0     # drop the arc/bob offset before the spiral
	_target = target
	_delay = delay
	var off: Vector2 = position - target
	_radius = maxf(off.length(), ARRIVE_RADIUS + 1.0)
	_angle = off.angle()
	_radial_speed = 60.0
