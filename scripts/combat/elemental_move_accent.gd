extends Node2D
class_name ElementalMoveAccent
# Small accent only: each family's existing ability effect remains the main read.
var host: UnitBase
var elapsed := 0.0
var lifetime := 0.6

func setup(unit: UnitBase, duration: float) -> void:
	host = unit
	lifetime = maxf(duration,0.1)
	z_index = 5

func _process(delta: float) -> void:
	if not is_instance_valid(host) or host.current_hp <= 0 or host.stun_time > 0:
		queue_free()
		return
	elapsed += delta * host._battle_clock()
	position = host.body_visual_offset() + Vector2(8,-8)
	if elapsed >= lifetime: queue_free()
	else: queue_redraw()

func _draw() -> void:
	if not is_instance_valid(host): return
	LizardVFX.draw_accent(self,host.current_element,Vector2.ZERO,7.0,elapsed,0.65 * (1.0 - elapsed/lifetime))
