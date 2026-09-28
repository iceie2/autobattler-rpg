extends Node
# VD-20 deterministic smoke: no main_game and no save/write method calls.
var failures: Array = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("RELIC_MILESTONES: " + label)

func _ready() -> void:
	_test_conditions()
	_test_state_and_pool()
	_test_battle_facts()
	_test_counters()
	print("RELIC_MILESTONES_SMOKE: %s (%d checks)" % ["ALL PASS" if failures.is_empty() else "FAILED", checks])
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_conditions() -> void:
	# 28 accepted, minus First Strike I/II (cut by the owner, VD-21).
	check(RelicMilestones.TABLE.size() == 26, "26 accepted milestones")
	var seen := {}
	for row: Dictionary in RelicMilestones.TABLE:
		check(not seen.has(row.id), "unique ID " + row.id)
		seen[row.id] = true
		check(not RelicMilestones.members(row.id).is_empty(), "real relic members " + row.id)
		check(not RelicMilestones.matches(row, {}), "missing facts cannot earn " + row.id)
		var facts := {}
		for rule: Array in row.requirements:
			facts[rule[0]] = rule[2] - 0.001 if rule[1] == "lt" else rule[2]
		check(RelicMilestones.matches(row, facts), "positive threshold " + row.id)
		for rule: Array in row.requirements:
			var bad := facts.duplicate()
			match rule[1]:
				"eq": bad[rule[0]] = not rule[2] if rule[2] is bool else rule[2] + 1
				"lt": bad[rule[0]] = rule[2]
				"ge": bad[rule[0]] = rule[2] - 0.001
				"le": bad[rule[0]] = rule[2] + 0.001
			check(not RelicMilestones.matches(row, bad), "negative boundary " + row.id + "/" + rule[0])
	check("execute_1" in RelicMilestones.earned({"won": true, "boss": true, "round": 10, "brutal": false}), "Normal first boss counts")
	check("execute_2" not in RelicMilestones.earned({"won": true, "boss": true, "brutal": false}), "Execute II requires Brutal")
	check("ultrefund_2" in RelicMilestones.earned({"won": false, "ults": 10}), "ult milestone on loss")
	check("ladder_gold_econ" in RelicMilestones.earned({"won": false, "finished": true, "gold": 200}), "held gold on loss")
	check("ladder_start_shield" not in RelicMilestones.earned({"won": false, "shield": 1000}), "shield requires win")

func _test_state_and_pool() -> void:
	var original := Progression.relic_milestones
	var state := RelicMilestoneState.new()
	Progression.relic_milestones = state
	state.restore({})
	check(state.pending.is_empty() and state.pool.is_empty(), "old saves default empty")
	check(not Progression.is_relic_unlocked("a_execute") and not Progression.is_relic_unlocked("s_execute"), "A/S Execute gated")
	check(Progression.is_relic_unlocked("b_goldscale") and Progression.is_relic_unlocked("d_underdog"), "free low rungs preserved")
	var earned := state.record({"won": true, "elapsed": 5.9, "max_hp": 3000})
	check(earned.has("opening_1") and earned.has("ladder_max_hp"), "pending awards recorded")
	check(not Progression.is_relic_unlocked("d_opening") and not Progression.is_ladder_unlocked("max_hp"), "pending never in active pool")
	check(state.record({"won": true, "elapsed": 5.9, "max_hp": 3000}).is_empty(), "duplicate award suppressed")
	var snapshot := state.pool.duplicate()
	var restored := RelicMilestoneState.new()
	restored.restore(JSON.parse_string(JSON.stringify(state.to_dict())))
	check(restored.pending == state.pending, "pending survives actual JSON round trip")
	restored.collect()
	restored.resume_pool(snapshot)
	check(restored.pool.is_empty(), "resumed run stays frozen after collection")
	Progression.relic_milestones = restored
	restored.begin_run()
	check(Progression.is_relic_unlocked("d_opening") and Progression.is_relic_unlocked("b_opening"), "tier I opens D-B next run")
	check(not Progression.is_relic_unlocked("a_opening"), "tier I does not open A-S")
	check(Progression.is_ladder_unlocked("max_hp"), "ladder opens next run")
	# Earns Execute II only: Execute I needs round 10, and no boss token is passed.
	restored.record({"won": true, "boss": true, "brutal": true, "round": 20})
	restored.collect()
	check(not Progression.is_relic_unlocked("s_execute"), "collect leaves this run fixed")
	restored.begin_run()
	check(Progression.is_relic_unlocked("a_execute") and Progression.is_relic_unlocked("s_execute"), "tier II opens A/S Execute")
	check(not Progression.is_relic_unlocked("b_execute"), "tiers remain independent")
	var boss := {"won": true, "boss": true}
	restored.record(boss, "one:10")
	restored.record(boss, "one:10")
	check(restored.boss_wins.size() == 1, "replayed boss deduplicated")
	restored.record(boss, "one:20")
	restored.record(boss, "two:10")
	check(restored.pending.has("ladder_vs_boss"), "three bosses across runs")
	var again := RelicMilestoneState.new()
	again.restore(JSON.parse_string(JSON.stringify(restored.to_dict())))
	check(again.boss_wins.size() == 3 and again.unlocked == restored.unlocked, "boss count and collection persist")
	# Exhaustive real offer gating: exclude every relic except one, forcing the
	# production draw to either offer that relic or return empty at all grades.
	Progression.relic_milestones = RelicMilestoneState.new()
	var ids: Array = []
	for relic: Dictionary in Relic.POOL: ids.append(relic.id)
	for relic: Dictionary in Relic.POOL:
		var others := ids.duplicate()
		others.erase(relic.id)
		var gate := "ladder_" + String(relic.get("ladder", "")) if relic.get("ladder_gated", false) else RelicMilestones.relic_gate(relic.id)
		check(Relic._draw_one(1, [], others).is_empty() == (gate != ""), "locked draw " + relic.id)
	for row: Dictionary in RelicMilestones.TABLE: Progression.relic_milestones.pool[row.id] = true
	for relic: Dictionary in Relic.POOL:
		var others := ids.duplicate()
		others.erase(relic.id)
		check(Relic._draw_one(1, [], others).get("id", "") == relic.id, "unlocked draw " + relic.id)
	Progression.relic_milestones = original

func _test_battle_facts() -> void:
	var heroes: Array = []
	for i in range(5):
		var u := UnitBase.new()
		u.trait_class = UnitBase.TraitClass.TANK
		u.home_position = Vector2i(i, 5 if i < 4 else 8)
		u.is_player_unit = true
		heroes.append(u)
	var summon := UnitBase.new()
	summon.is_summoned = true
	heroes.append(summon)
	var tracker := RelicMilestoneBattle.new()
	tracker.begin(heroes, 150, 10, true)
	check(tracker.heroes.size() == 5 and tracker.facts.front == 4 and tracker.facts.tanks == 5, "starting comp excludes summons")
	check("goldscale_2" in RelicMilestones.earned(tracker.facts), "start gold evaluated immediately")
	heroes[0].home_position.y = 8
	heroes[0].milestone_ult_casts = 3
	heroes[1].milestone_ult_casts = 1
	heroes[0].milestone_double_attacks = 15
	heroes[0].milestone_shield_absorbed = 1000
	heroes[0].kill_count = 8
	tracker.death(heroes[0], false, 3.0)
	tracker.death(heroes[0], false, 4.0)
	tracker.death(heroes[1], false, 5.0)
	check(not tracker.sample().lost_half, "distinct fallen heroes; odd team rounds up")
	tracker.death(heroes[2], false, 6.0)
	var enemy := UnitBase.new()
	tracker.death(enemy, true, 2.0)
	enemy.is_elite = true
	tracker.death(enemy, true, 5.0)
	var facts := tracker.finish(true, 60, 200)
	check(facts.front == 4 and facts.lost_half, "formation and deaths survive movement/revival")
	check(facts.ults == 4 and facts.max_ults == 3 and facts.doubles == 15 and facts.shield == 1000 and facts.max_kills == 8, "per-fight aggregates")
	check(facts.first_kill == 2 and facts.first_elite_kill == 5, "actual elite kill time")
	check("underdog_2" in RelicMilestones.earned(facts) and "momentum_2" in RelicMilestones.earned(facts), "boss/underdog integration")
	tracker.begin(heroes, 0, 1, false)
	check(not tracker.facts.has("first_kill") and tracker.fallen.is_empty(), "battle reset clears kill times/deaths")
	for u in heroes: u.free()
	enemy.free()

func _test_counters() -> void:
	var manager := AutoBattleManager.new()
	var hero := UnitFactory.create_unit(UnitBase.UnitClass.SHAUNA, UnitBase.Element.NORMAL, true)
	add_child(hero)
	hero.is_player_unit = true
	hero.unit_class = UnitBase.UnitClass.SHAUNA
	manager.player_units = [hero]
	hero.milestone_ult_casts = 9
	hero.milestone_double_attacks = 9
	hero.milestone_shield_absorbed = 9
	manager._init_unit_timers()
	check(hero.milestone_ult_casts == 0 and hero.milestone_double_attacks == 0 and hero.milestone_shield_absorbed == 0, "real timer init resets all three counters")
	# Ultimate path needs the manager's effect container, but never a game scene.
	add_child(manager)
	manager.skill_effect_container = Node2D.new()
	manager.add_child(manager.skill_effect_container)
	manager._use_ultimate(hero, [], [hero])
	check(hero.milestone_ult_casts == 1, "real ultimate dispatch increments")
	hero.current_shield = 100
	hero.take_damage(40, UnitBase.Element.NORMAL, null, true)
	check(hero.milestone_shield_absorbed == 40, "actual shield absorption counts")
	hero.take_damage(100, UnitBase.Element.NORMAL, null, true)
	check(hero.milestone_shield_absorbed == 100, "shield counts absorption, not overkill")
	hero.gear_levels = {"mana_shield": 1}
	GearPassives.battle_start(hero)
	hero.resistance = 0
	hero.magic_resist = 0
	hero.current_mana = 100
	hero.milestone_shield_absorbed = 0
	hero.take_damage(100, UnitBase.Element.NORMAL, null)
	check(hero.milestone_shield_absorbed == 3 and hero.current_mana == 98, "Mana Shield absorption counted (absorbed %d, mana %d)" % [hero.milestone_shield_absorbed, hero.current_mana])
	hero.gear_levels = {"guardians_pact": 1}
	GearPassives.battle_start(hero)
	hero.gear_shield = 40
	hero.milestone_shield_absorbed = 0
	hero.take_damage(20, UnitBase.Element.NORMAL, null, true)
	check(hero.milestone_shield_absorbed == 20, "equipment shield absorption counted")
	hero.gear.clear()
	hero.gear_levels.clear()
	var foe := EnemyFactory.create_by_type("goblin")
	add_child(foe)
	foe.max_hp = 100000
	foe.current_hp = foe.max_hp
	foe.grid_position = Vector2i(0, 4)
	hero.grid_position = Vector2i(0, 5)
	hero.target_unit = foe
	hero.relic_double_atk_chance = 1.0
	hero.overdrive_time = 0
	hero.ultimate_ready = false
	hero.skill_cd_time = 999
	hero.attack_cooldown = 0
	hero.action_time = 0
	manager.enemy_units = [foe]
	manager._tick_unit(hero, 0.0)
	check(hero.milestone_double_attacks == 1, "guaranteed real double attack increments once")
	foe.queue_free()
	hero.queue_free()
	manager.queue_free()
