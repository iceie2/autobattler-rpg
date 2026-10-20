extends Node

var failures: Array[String] = []
var last_source = null

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _ready() -> void:
	var mgr := AutoBattleManager.new()
	add_child(mgr)
	var victim := UnitBase.new()
	add_child(victim)
	victim.battle_manager = mgr
	victim.max_hp = 1000
	victim.current_hp = 1000
	victim.took_damage.connect(func(_damage, source, _animate): last_source = source)
	var source := UnitBase.new()
	source.set_meta("cloven_split", true)
	mgr.apply_burn(victim, 10.0, 5.0, source)
	source.free()
	check(not is_instance_valid(source), "source is actually freed")
	mgr.apply_cloven_fracture(victim, source)
	check(not victim.has_meta("cloven_defense_loss"), "freed source cannot apply fracture")
	mgr._tick_statuses(victim, 1.0)
	check(victim.current_hp == 990, "burn continues after source is freed")
	check(last_source == null, "damage signal receives no freed source")
	check(victim.damage_taken_from.is_empty(), "freed source is excluded from damage attribution")
	mgr._kindling_mult = 2.0
	mgr.apply_burn(victim, 10.0, 5.0, source)
	check(victim.burn_dps == 10.0, "burn spread with freed source is safe and has no source bonus")
	var titan := UnitBase.new()
	titan.set_meta("cloven_split", true)
	victim.current_shield = 100
	victim.take_damage(10, UnitBase.Element.NORMAL, titan, true)
	check(victim.get_meta("cloven_defense_loss", 0) == 8, "live Titan still fractures a shielded target")
	check(victim.current_hp == 990 and victim.current_shield == 90, "shield still absorbs live Titan damage")
	titan.set_meta("cloven_half", true)
	mgr.apply_cloven_fracture(victim, titan)
	check(victim.get_meta("cloven_defense_loss", 0) == 8, "split half cannot apply fracture")
	titan.free()
	victim.current_shield = 0
	victim.take_damage(2000, UnitBase.Element.FIRE, source, true)
	check(victim.current_hp <= 0, "lethal damage with freed source completes")
	for message in failures: print("FAIL: ", message)
	print("FREED_BURN_SOURCE_PROBE: ", "ALL PASS" if failures.is_empty() else str(failures.size()) + " FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)
