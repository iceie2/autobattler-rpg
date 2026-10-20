extends Node

var fails: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok:
		fails.append(message)

func _ready() -> void:
	var grid := BattleGrid.new()
	add_child(grid)
	var mgr := AutoBattleManager.new()
	add_child(mgr)
	mgr.battle_grid = grid
	mgr.unit_summoned.connect(func(u): add_child(u))
	var boss := EnemyFactory.create_cloven_titan()
	add_child(boss)
	boss.grid_position = Vector2i(4, 1)
	grid.place_unit(boss, boss.grid_position)
	mgr.enemy_units = [boss]
	mgr.spawn_cloven_halves(boss)
	check(mgr.enemy_units.size() == 3, "Split must create exactly two fragments")
	var fist = mgr.enemy_units[1]
	var heart = mgr.enemy_units[2]
	var victim := VisualUnit.new()
	add_child(victim)
	victim.battle_manager = mgr
	victim.max_hp = 10000
	victim.current_hp = 10000
	victim.resistance = 100
	victim.magic_resist = 100
	victim.take_damage(100, UnitBase.Element.NORMAL, boss)
	victim.take_magic_damage(100, UnitBase.Element.NORMAL, boss)
	check(victim.get_meta("cloven_defense_loss", 0) == 10, "Intact Titan hits must stack five armor/MR loss")
	mgr.propagate_damage_links(victim, 100, fist)
	mgr.propagate_damage_links(victim, 100, heart)
	mgr.propagate_damage_links(victim, 0, boss)
	check(victim.get_meta("cloven_defense_loss", 0) == 10, "Fragments and missed damage must not add scars")
	check(victim.resistance == 100 and victim.magic_resist == 100, "Scars must not mutate permanent hero stats")
	victim.current_shield = 1000
	var shield_hp: int = victim.current_hp
	victim.take_damage(100, UnitBase.Element.NORMAL, boss)
	check(victim.current_hp == shield_hp, "Shield must absorb the entire test hit")
	check(victim.get_meta("cloven_defense_loss", 0) == 15, "Shielded hit must still apply five defense loss")
	victim.take_magic_damage(100, UnitBase.Element.NORMAL, boss)
	check(victim.get_meta("cloven_defense_loss", 0) == 20, "Shielded magic hit must apply exactly one stack")
	victim.take_damage(100, UnitBase.Element.NORMAL, fist)
	check(victim.get_meta("cloven_defense_loss", 0) == 20, "Shielded fragment hit must not scar defenses")
	victim.current_shield = 0
	victim.set_meta("cloven_defense_loss", 50)
	var scar_hp: int = victim.current_hp
	victim.take_damage(300, UnitBase.Element.NORMAL, fist)
	var scar_damage: int = scar_hp - victim.current_hp
	victim.set_meta("cloven_defense_loss", 0)
	scar_hp = victim.current_hp
	victim.take_damage(300, UnitBase.Element.NORMAL, fist)
	check(scar_damage > scar_hp - victim.current_hp, "Scars must increase subsequent physical damage")
	victim.set_meta("cloven_defense_loss", 50)
	scar_hp = victim.current_hp
	victim.take_magic_damage(300, UnitBase.Element.NORMAL, heart)
	scar_damage = scar_hp - victim.current_hp
	victim.set_meta("cloven_defense_loss", 0)
	scar_hp = victim.current_hp
	victim.take_magic_damage(300, UnitBase.Element.NORMAL, heart)
	check(scar_damage > scar_hp - victim.current_hp, "Scars must increase subsequent magic damage")
	check(fist.get_meta("cloven_role", "") == "fist", "Missing fist role")
	check(heart.get_meta("cloven_role", "") == "heart", "Missing heart role")
	check(not fist.has_meta("cloven_split") and not heart.has_meta("cloven_split"), "Fragments must not split again")
	check(fist.attack_damage > heart.attack_damage * 4, "Fist must own the damage")
	check(heart.model3d != null and fist.model3d != null, "Both fragment models must load")
	fist.current_hp = fist.max_hp / 2
	var before: int = fist.current_hp
	var reserve: int = heart.get_meta("cloven_mend_reserve")
	mgr._cloven_heart_turn(heart, [], 0.1)
	check(fist.current_hp > before, "Heart must heal its own fist")
	check(heart.get_meta("cloven_mend_reserve") < reserve, "Healing must spend finite reserve")
	before = fist.current_hp
	mgr._cloven_heart_turn(heart, [], 0.1)
	check(fist.current_hp == before, "Heal cooldown must prevent spam")
	var attacker := EnemyFactory.create_cloven_titan()
	attacker.cell_size = 1
	add_child(attacker)
	attacker.grid_position = Vector2i(heart.grid_position.x, 3)
	grid.place_unit(attacker, attacker.grid_position)
	heart.set_meta("cloven_roam_cd", 0.0)
	var origin: Vector2i = heart.grid_position
	mgr._cloven_heart_turn(heart, [attacker], 0.1)
	check(heart.is_moving and heart.grid_position != origin, "Heart must retreat with real grid movement")
	check(grid.get_unit_at(heart.grid_position) == heart, "Moving heart must retain grid ownership")
	fist.current_hp = 0
	heart.current_hp = heart.max_hp / 2
	heart.is_moving = false
	heart.set_meta("cloven_mend_cd", 0.0)
	before = heart.current_hp
	mgr._cloven_heart_turn(heart, [], 0.1)
	check(heart.current_hp > before, "Lone heart must heal itself")
	heart.set_meta("cloven_mend_reserve", 0)
	heart.set_meta("cloven_mend_cd", 0.0)
	before = heart.current_hp
	mgr._cloven_heart_turn(heart, [], 10.0)
	check(heart.current_hp == before, "Exhausted reserve must stop healing")
	victim.is_player_unit = true
	victim.grid_position = Vector2i(0, 8)
	grid.place_unit(victim, victim.grid_position)
	victim.set_meta("cloven_defense_loss", 25)
	mgr.start_battle()
	check(victim.get_meta("cloven_defense_loss", -1) == 0, "Next battle must clear defense scars")
	for f in fails:
		print("CLOVEN_SPLIT: FAIL ", f)
	print("CLOVEN_SPLIT: ALL PASS" if fails.is_empty() else "CLOVEN_SPLIT: FAILED")
	get_tree().quit(0 if fails.is_empty() else 1)
