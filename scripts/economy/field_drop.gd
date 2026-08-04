extends Node2D
class_name FieldDrop
# ══════════════════════════════════════════════════════════════════════════════
# Generic physical field pickup (2026-07-21) — same toss/idle/vacuum state
# machine as GoldCoin (see gold_coin.gd), generalized so crystal and item
# drops don't need their own copy of it. `payload` is whatever the collector
# needs on pickup (an int crystal amount, an EquipmentItem, ...) — this class
# doesn't interpret it, just carries it through to the `collected` signal.
# ══════════════════════════════════════════════════════════════════════════════

signal collected(payload)

enum State { TOSS, IDLE, VACUUM }

var payload = null
var state: State = State.TOSS

const TOSS_TIME := 0.45
const TOSS_GRAVITY := 460.0
const PULL_ACCEL := 2400.0      # inward gravity during vacuum
const ARRIVE_RADIUS := 8.0

var _sprite: Sprite2D
var _vel: Vector2
var _toss_t: float = 0.0
var _ground_y: float = 0.0
var _bob_phase: float = 0.0
# vacuum spiral state (polar around the collection point)
var _target: Vector2
var _angle: float = 0.0
var _radius: float = 0.0
var _radial_speed: float = 60.0
var _delay: float = 0.0

# Called by the spawning system right after new()/before add_child(), so the
# sprite exists before the first _ready()/_process() tick.
func setup(texture: Texture2D, display_scale: float = 0.3, tint: Color = Color(1, 1, 1, 1)) -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.scale = Vector2(display_scale, display_scale)
	_sprite.modulate = tint
	add_child(_sprite)

func _ready() -> void:
	z_index = 40
	_bob_phase = randf() * TAU
	# Pop out of the corpse: small sideways toss with an upward kick.
	_vel = Vector2(randf_range(-70.0, 70.0), randf_range(-150.0, -90.0))
	_ground_y = position.y + randf_range(-6.0, 14.0)
	# Spawn slightly squashed and pop to full size — reads as "dropped".
	scale = Vector2(0.4, 0.4)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	match state:
		State.TOSS:
			_toss_t += delta
			_vel.y += TOSS_GRAVITY * delta
			position += _vel * delta
			# Land once the arc comes back down past the resting line.
			if _toss_t >= TOSS_TIME or (_vel.y > 0.0 and position.y >= _ground_y):
				state = State.IDLE
		State.IDLE:
			# Gentle glint-bob so the field reads as alive, not static.
			_bob_phase += delta * 3.0
			if _sprite:
				_sprite.position.y = sin(_bob_phase) * 1.5
		State.VACUUM:
			if _delay > 0.0:
				_delay -= delta
				return
			_radial_speed += PULL_ACCEL * delta
			_radius = maxf(_radius - _radial_speed * delta, 0.0)
			# Orbit speeds up as gravity wins — classic sink-spiral.
			_angle += (3.0 + 320.0 / maxf(_radius, 45.0)) * delta
			position = _target + Vector2(cos(_angle), sin(_angle)) * _radius
			# Shrink as it closes so it reads as "sucked into" the counter.
			var s: float = clampf(_radius / 260.0 + 0.45, 0.45, 1.0)
			scale = Vector2(s, s)
			if _radius <= ARRIVE_RADIUS:
				collected.emit(payload)
				queue_free()

# Begin the spiral pull toward `target` (local space to whatever this drop's
# parent system is). `delay` staggers several drops into a wave (round-end);
# hover-collect passes delay=0 for an immediate individual pickup.
func start_vacuum(target: Vector2, delay: float = 0.0) -> void:
	if state == State.VACUUM:
		return
	state = State.VACUUM
	_target = target
	_delay = delay
	var off: Vector2 = position - target
	_radius = maxf(off.length(), ARRIVE_RADIUS + 1.0)
	_angle = off.angle()
	_radial_speed = 60.0
