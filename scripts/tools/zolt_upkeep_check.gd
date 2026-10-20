extends Node
## Zolt storm upkeep ramp check (2026-10-07): each storm 1 mana/s, +1 every 2s,
## max 10/s, storms age independently; 0 mana still dispels them all.
##   godot --headless --path autobattler-rpg res://scenes/tools/zolt_upkeep_check.tscn
func _ready() -> void:
	var mgr = AutoBattleManager.new()
	add_child(mgr)
	var z: UnitBase = UnitFactory.create_unit(UnitBase.UnitClass.ZOLT, UnitBase.Element.LIGHTNING, true)
	add_child(z)
	z.max_mana = 100000
	z.current_mana = 100000
	var s1 := StormHazard.new()
	s1.caster = z
	mgr.storms.append(s1)
	var dt := 1.0 / 30.0
	var last := z.current_mana
	for sec in 30:
		if sec == 6:
			var s2 := StormHazard.new()
			s2.caster = z
			mgr.storms.append(s2)
		for f in 30:
			mgr._tick_storm_upkeep(dt)
		print("UPKEEP t=%2ds drained=%d storms=%d" % [sec + 1, last - z.current_mana, mgr.storms.size()])
		last = z.current_mana
	get_tree().quit()
