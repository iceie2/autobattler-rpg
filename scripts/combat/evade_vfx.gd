extends Node2D
class_name EvadeVFX

# "That hit missed." — the answer to a question the game could not previously
# answer at all.
#
# UnitBase.take_damage's evasion roll simply `return`s: no damage number, no
# flash, no sound, nothing. A player swinging into a Gale Warden (30% evasion)
# watches roughly one hit in three produce ZERO feedback, indistinguishable from
# a bug or a missed input. The Harpy foreshadows it at 12%.
#
# Deliberately shared rather than per-unit: it is one mechanic off one
# `equipment_passives["Evasion"]` roll, and both users are wind/flight themed, so
# a single wind-sidestep read is correct for all of them. Kept SMALL and brief —
# it fires often, so it must inform without becoming noise.

const WIND := Color(0.86, 0.96, 1.0)
# NEAR-BLACK rim, not a mid blue-grey. BOTH evasion users (Harpy, Gale Warden)
# are pale WHITE bird sprites, so pale streaks drew straight into their wings
# and the dodge was still effectively invisible (measured in the first capture —
# sixth time this project has hit "an effect in the body's own colours").
# A dark rim under a bright core reads on a white bird AND on a dark board.
const WIND_DEEP := Color(0.05, 0.07, 0.12)

var elapsed := 0.0
var lifetime := 0.34
var reach := 70.0
var dir := 1.0               # which way the body slips
var _t := 0.0

func setup(world_pos: Vector2, size: float, life: float, slip: float = 1.0) -> void:
	global_position = world_pos
	reach = size
	lifetime = life
	dir = slip
	z_index = 5              # above the body: it explains an absence
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	_t += delta
	if elapsed >= lifetime:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	var t := clampf(elapsed / lifetime, 0.0, 1.0)
	var fade := 1.0 - t
	var r := reach * 0.5
	# Speed streaks sweeping the way the body slipped — reads as "moved aside",
	# not as an impact.
	for i in range(4):
		var off: float = (float(i) - 1.5) * r * 0.22
		var len: float = r * (0.50 + 0.30 * t) * (1.0 - absf(float(i) - 1.5) * 0.18)
		var y: float = off * 0.6 - reach * 0.10
		draw_line(Vector2(-dir * len * 0.2, y), Vector2(-dir * len, y),
			Color(WIND_DEEP.r, WIND_DEEP.g, WIND_DEEP.b, 0.85 * fade), 5.0)
		draw_line(Vector2(-dir * len * 0.2, y), Vector2(-dir * len * 0.9, y),
			Color(WIND.r, WIND.g, WIND.b, 0.95 * fade), 2.0)
	# A crescent of displaced air at the dodge apex.
	var a0: float = -PI * 0.45
	var c := Vector2(dir * r * 0.18, 0)
	var cr: float = r * (0.34 + 0.18 * t)
	draw_arc(c, cr, a0, a0 + PI * 0.9, 14,
		Color(WIND_DEEP.r, WIND_DEEP.g, WIND_DEEP.b, 0.8 * fade), 4.6 * fade + 1.6)
	draw_arc(c, cr, a0, a0 + PI * 0.9, 14,
		Color(WIND.r, WIND.g, WIND.b, 0.95 * fade), 2.2 * fade + 0.8)
