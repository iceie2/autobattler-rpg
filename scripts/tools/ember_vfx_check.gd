extends Node
class Clock extends Node:
	var paused := false
	var time_scale := 1.0
func _ready() -> void:
	var clock := Clock.new()
	add_child(clock)
	var caster := UnitBase.new()
	add_child(caster)
	caster.global_position = Vector2(10, 100)
	caster.battle_manager = clock
	caster.unit_class = UnitBase.UnitClass.EMBER
	var victim := UnitBase.new()
	add_child(victim)
	victim.current_hp = 100
	victim.global_position = Vector2(1000, 100)
	var shot := Projectile.new()
	shot.is_ember_arrow = true
	shot.caster = caster
	shot.spawn_delay = 0.9
	shot.setup(Vector2(10, 100), victim.global_position, 1, UnitBase.Element.FIRE, victim)
	add_child(shot)
	shot.set_process(false)
	clock.paused = true
	shot._process(0.5)
	assert(is_equal_approx(shot.spawn_delay, 0.9))
	clock.paused = false
	clock.time_scale = 0.25
	shot._process(1.0)
	assert(is_equal_approx(shot.spawn_delay, 0.65))
	assert(not shot._launched)
	clock.time_scale = 4.0
	shot._process(0.2)
	assert(shot._launched)
	victim.burn_time = 3
	victim.burn_source = caster
	assert(EmberVFX.has_ember_burn(victim))
	caster.unit_class = UnitBase.UnitClass.COAL
	assert(not EmberVFX.has_ember_burn(victim))
	victim.burn_parts[int(UnitBase.UnitClass.EMBER)] = [2.0, 1.0, caster]
	assert(EmberVFX.has_ember_burn(victim))
	print("EMBER_CLOCK_AND_OWNERSHIP PASS")
	get_tree().quit()
