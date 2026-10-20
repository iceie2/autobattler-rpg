extends Node

var fails: Array[String] = []
var checks := 0
var game

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails.append(message)

func fixture() -> Dictionary:
	var grid := BattleGrid.new()
	var mgr := AutoBattleManager.new()
	add_child(grid); add_child(mgr)
	mgr.initialize(grid, null)
	var fx := Node2D.new(); add_child(fx); mgr.skill_effect_container = fx
	var boss := EnemyFactory.create_arcfang()
	add_child(boss); boss.battle_manager = mgr
	boss.grid_position = Vector2i(1, 1); grid.place_unit(boss, boss.grid_position)
	boss.position = mgr._world_pos_for(boss, boss.grid_position)
	var heroes: Array = []
	for cell in [Vector2i(6, 6), Vector2i(5, 6), Vector2i(6, 7)]:
		var h := UnitBase.new(); add_child(h)
		h.is_player_unit = true; h.max_hp = 100000; h.current_hp = 100000
		h.max_mana = 0; h.unit_name = "Hero %d" % heroes.size()
		h.battle_manager = mgr; h.grid_position = cell
		grid.place_unit(h, cell); h.position = grid.grid_to_world(cell)
		heroes.append(h)
	mgr.enemy_units = [boss]; mgr.player_units = heroes
	return {"grid": grid, "mgr": mgr, "boss": boss, "heroes": heroes, "hunt": mgr._arcfang_controller(boss, heroes)}

func display(boss: UnitBase, reduced: bool) -> void:
	game.show_unit_details(boss); game._details.refresh_live()
	for entry in [["CellDef", boss.effective_armor()], ["CellMagRes", boss.effective_magic_resist()]]:
		var value: Label = game._details.combat_grid.get_node(entry[0] + "/Value")
		check(value.text.ends_with(str(entry[1])), "UI defense agrees with combat accessor: " + entry[0])
		check(value.tooltip_text.contains("Spent Storm") == reduced, "Recovery tooltip appears and expires: " + entry[0])
	check(game._details.skill_desc_lbl.text.contains("Last Howl"), "Live kit explains Last Howl")

func simulate(seed_value: int, hero_level: int) -> void:
	seed(seed_value)
	var saved_cap: int = Progression.hero_level_cap_override
	Progression.hero_level_cap_override = hero_level
	var board := Node2D.new(); add_child(board)
	var grid := BattleGrid.new(); board.add_child(grid)
	var mgr := AutoBattleManager.new(); board.add_child(mgr); mgr.initialize(grid, null)
	mgr.set_process(false)
	var shots := Node2D.new(); board.add_child(shots); mgr.projectile_container = shots
	var fx := Node2D.new(); board.add_child(fx); mgr.skill_effect_container = fx
	var wolf := EnemyFactory.create_arcfang(WaveScaler.boss_level(60))
	board.add_child(wolf); wolf.battle_manager = mgr; wolf.grid_position = Vector2i(3, 1)
	grid.place_unit(wolf, wolf.grid_position); wolf.position = mgr._world_pos_for(wolf, wolf.grid_position)
	var classes := [UnitBase.UnitClass.RIOT, UnitBase.UnitClass.BOUNCER, UnitBase.UnitClass.SHAUNA,
		UnitBase.UnitClass.DOC, UnitBase.UnitClass.HEADHUNTER, UnitBase.UnitClass.REED, UnitBase.UnitClass.EMBER]
	for i in classes.size():
		var hero := UnitFactory.create_unit(classes[i], UnitFactory.element_for_class(classes[i]), true)
		hero.set_level(hero_level); board.add_child(hero); hero.battle_manager = mgr
		check(hero.level == hero_level, "Simulation hero reaches its declared level")
		hero.grid_position = Vector2i(1 + i % 4 * 2, 5 + i / 4 * 2)
		grid.place_unit(hero, hero.grid_position); hero.position = mgr._world_pos_for(hero, hero.grid_position)
	var marks := [0]
	mgr.action_logged.connect(func(text: String, _side: bool):
		if text.begins_with("Eye of the Storm"): marks[0] += 1)
	mgr.start_battle(); mgr.time_scale = 1.0
	for frame in 3600:
		if not mgr.battle_active: break
		mgr._process(1.0 / 30.0)
		for shot in shots.get_children():
			if not shot.is_queued_for_deletion(): shot._process(1.0 / 30.0)
		if frame % 30 == 0: await get_tree().process_frame
	check(not mgr.battle_active, "Real wave-60 fixture completes without a stall")
	check(marks[0] > 0 or mgr.battle_elapsed < 10, "Real wave-60 fixture exercises marked hunts unless killed before opening")
	print("ARCFANG_SIM: seed=%d heroes_level=%d boss_level=%d duration=%.1fs marks=%d heroes_alive=%d boss_hp=%d" % [seed_value, hero_level, wolf.level, mgr.battle_elapsed, marks[0], mgr.player_units.size(), wolf.current_hp if is_instance_valid(wolf) else 0])
	board.queue_free()
	await get_tree().process_frame
	Progression.hero_level_cap_override = saved_cap

func _ready() -> void:
	game = load("res://scenes/main_game.tscn").instantiate(); add_child(game)
	for frame in 20: await get_tree().process_frame
	var s := fixture(); var mgr: AutoBattleManager = s.mgr; var boss: VisualUnit = s.boss
	var hunt: ArcfangHunt = s.hunt; var heroes: Array = s.heroes; var grid: BattleGrid = s.grid
	check(boss.health_bar.ability_timers.size() == 5, "One standard timer strip per move")
	check(boss.health_bar.ability_timers.all(func(row): return row.size() == 2), "Arcfang uses the same fraction/color bar data as other bosses")
	check(is_equal_approx(boss.health_bar.total_height(), 46.8), "Five strips use standard boss height and spacing")
	var rows := ArcfangHunt.timer_rows(boss)
	check(rows[0][2].contains("10.0s") and rows[1][2].contains("11.5s"), "Initial mark and pounce countdowns use actual schedule")
	check(rows[4][2].contains("40% HP") and rows[4][0] == 0, "Last Howl uses HP gate, not a fake cooldown")
	heroes[0].damage_dealt = 500; heroes[1].damage_dealt = 100
	hunt.tick(9.9, heroes)
	check(hunt.state == "idle", "Opening hunt waits ten seconds")
	hunt.tick(0.11, heroes)
	check(hunt.state == "warning" and hunt.prey == heroes[0], "Warning selects highest recent damage")
	check(hunt.blocks_actions(), "Warning blocks attacks and movement")
	rows = ArcfangHunt.timer_rows(boss)
	check(rows[0][2].contains("MARKED") and rows[1][2].contains("CHARGE 1.5s"), "Warning rows distinguish mark from pounce charge")
	check(hunt.bursts.any(func(b): return b.kind == "mark"), "Mark gets its own effect")
	check(boss.health_bar != null, "Real health bar available for telegraph")
	var origin := boss.grid_position
	hunt.tick(1.49, heroes)
	check(boss.grid_position == origin, "Boss waits for full warning")
	hunt.tick(0.02, heroes)
	check(hunt.state == "hunt" and boss.grid_position != origin, "Pounce resolves after warning")
	check(hunt.bursts.any(func(b): return b.kind == "pounce"), "Pounce gets departure and landing effect")
	var cells := 0
	for c in grid.occupied_cells:
		if grid.occupied_cells[c] == boss: cells += 1
	check(cells == 4, "Pounce registers all four footprint cells")
	check(mgr._choose_target(boss, heroes) == heroes[0], "Hunt locks selected prey")
	boss.taunt_time = 1; boss.taunt_source = heroes[1]
	check(mgr._choose_target(boss, heroes) == heroes[1], "Taunt overrides hunt")
	boss.taunt_time = 0; boss.taunt_source = null
	heroes[0].untargetable_time = 1
	check(mgr._choose_target(boss, heroes) != heroes[0], "Untargetable prey cannot be attacked")
	heroes[0].untargetable_time = 0
	# Different armor channels, with shield absorption on BOTH bite contacts.
	var victim: UnitBase = heroes[0]
	victim.resistance = 100; victim.magic_resist = 0; victim.current_shield = 10000
	boss.attack_damage = 100; boss.target_unit = victim
	var before := victim.current_shield
	mgr._use_skill(boss, heroes, [boss])
	check(victim.current_shield == before - 47, "Physical bite uses armor before shields")
	check(victim.current_hp == victim.max_hp, "Shielded bite does not harm HP")
	check(hunt.bursts.any(func(b): return b.kind == "bite"), "Physical contact creates serrated jaws")
	check(ArcfangHunt.timer_rows(boss)[2][2].contains("SNAP 0.6s"), "Thunderjaw bar shows delayed contact")
	hunt.tick(0.59, heroes)
	check(victim.current_shield == before - 47, "Lightning waits 0.6s")
	hunt.tick(0.02, heroes)
	check(victim.current_shield == before - 97, "Lightning snap uses magic resist and shields")
	check(boss.damage_dealt == 97, "Bite damage meter records actual shield damage")
	check(hunt.bursts.any(func(b): return b.kind == "snap") and hunt.snap_target == null, "Snap effect survives clearing its target reference")
	boss.skill_cd_time = 1.5; boss._update_arcfang_cooldown_bars()
	check(is_equal_approx(boss.health_bar.ability_timers[2][0], 0.5), "Thunderjaw bar follows the real three-second cooldown")
	# Recovery has no actions and exposes the same values UI and damage use.
	hunt.tick(4.0, heroes)
	check(hunt.state == "recovery" and hunt.remaining == 2.0, "Hunt ends in two-second recovery")
	check(ArcfangHunt.timer_rows(boss)[3][2].contains("ACTIVE 2.0s"), "Spent Storm row shows actual active duration")
	check(hunt.bursts.any(func(b): return b.kind == "spent"), "Recovery has extinguishing-electricity effect")
	check(boss.effective_armor() == 14 and boss.effective_magic_resist() == 14, "Recovery cuts both defenses by 40%")
	display(boss, true)
	boss.current_shield = 1000
	var damage_hp := boss.current_hp
	boss.take_damage(100, UnitBase.Element.NORMAL, null)
	check(boss.current_shield == 913 and boss.current_hp == damage_hp, "Recovery armor also governs a shielded incoming hit")
	boss.take_damage(100, UnitBase.Element.NORMAL, null, false, 0, true)
	check(boss.current_shield == 826, "Recovery magic resist governs shielded magic")
	var prey_hp: int = victim.current_hp
	boss.skill_cd_time = 0; boss.attack_cooldown = 0
	mgr._tick_unit(boss, 0.1)
	check(victim.current_hp == prey_hp and not boss.is_moving, "Recovery takes no combat action")
	hunt.tick(2, heroes)
	check(boss.effective_armor() == 24 and boss.effective_magic_resist() == 24, "Defense returns after recovery")
	display(boss, false)
	# Recent damage replaces lifetime leader on the NEXT primary mark.
	heroes[0].damage_dealt = 501; heroes[1].damage_dealt = 400
	hunt.tick(2.51, heroes)
	check(hunt.state == "warning" and hunt.prey == heroes[1], "Next mark uses recent damage, not lifetime leader")
	# A dead mark gets a completely fresh warning.
	heroes[1].current_hp = 0; hunt.tick(1.0, heroes)
	check(hunt.state == "warning" and hunt.prey != heroes[1] and hunt.remaining == 1.5, "Lost prey gets fresh full warning")
	heroes[1].current_hp = heroes[1].max_hp
	hunt.tick(1.5, heroes)
	var first: UnitBase = hunt.prey
	boss.current_hp = int(boss.max_hp * 0.39)
	hunt.tick(4.0, heroes)
	check(hunt.last_howl_used and hunt.second_hunt and hunt.state == "warning", "Last Howl adds a warned second hunt")
	check(hunt.bursts.any(func(b): return b.kind == "howl"), "Last Howl creates distinct violet shockwaves")
	check(ArcfangHunt.timer_rows(boss)[4][2].contains("SECOND HUNT"), "Last Howl row tracks its second hunt")
	check(hunt.prey != first, "Second hunt selects a different living hero")
	hunt.tick(1.5, heroes); hunt.tick(4.0, heroes)
	check(hunt.state == "recovery" and hunt.remaining == 3, "Double hunt earns three-second recovery")
	hunt.tick(3.0, heroes); hunt.tick(10.0, heroes); hunt.tick(1.5, heroes); hunt.tick(4.0, heroes)
	check(hunt.state == "recovery" and hunt.remaining == 2, "Last Howl cannot repeat")
	check(ArcfangHunt.timer_rows(boss)[4][2].contains("USED"), "Consumed Last Howl row never claims ready")
	# Round reset clears temporary stats, prey, pending bite, and controller.
	mgr._clear_board_effects()
	check(mgr._arcfang_hunts.is_empty() and not boss.has_meta("arcfang_state"), "Round end clears hunt and marker")
	check(hunt.bursts.is_empty(), "Round cleanup clears every move effect")
	check(boss.effective_armor() == 24, "Round end restores defense immediately")
	display(boss, false)
	mgr.player_units = [] # Bare damage dummies deliberately have no visual bars.
	mgr._init_unit_timers()
	mgr.player_units = heroes
	var fresh := mgr._arcfang_controller(boss, heroes)
	check(fresh.remaining == 10 and not fresh.last_howl_used, "Fresh battle resets hunt clock and Last Howl")
	# A target walking out of bite range avoids the second contact.
	boss.target_unit = victim
	before = victim.current_shield
	fresh.bite(victim)
	grid.purge_unit(victim); victim.grid_position = Vector2i(8, 0); grid.place_unit(victim, victim.grid_position)
	var after_bite := victim.current_shield
	fresh.tick(0.61, heroes)
	check(victim.current_shield == after_bite, "Lightning cannot hit an out-of-range target")
	# Boss death cancels all pending contacts and clears live defense state.
	boss.current_hp = 0; boss.died.emit()
	check(mgr._arcfang_hunts.is_empty() and not boss.has_meta("arcfang_prey"), "Death clears controller and mark")
	# No different hero: bounded recovery, never a second hit on the same prey.
	var solo := fixture(); var solo_hunt: ArcfangHunt = solo.hunt
	var solo_heroes: Array = [solo.heroes[0]]
	solo.boss.current_hp = int(solo.boss.max_hp * 0.39)
	solo_hunt.tick(10, solo_heroes); solo_hunt.tick(1.5, solo_heroes); solo_hunt.tick(4, solo_heroes)
	check(solo_hunt.state == "recovery" and solo_hunt.remaining == 3, "Solo prey goes straight to recovery after Last Howl")
	# Board completely packed: removing the wolf exposes only its old footprint.
	var crowded := fixture(); var crowded_grid: BattleGrid = crowded.grid
	for y in 9:
		for x in 9:
			var cell := Vector2i(x, y)
			if not crowded_grid.is_cell_occupied(cell):
				var filler := UnitBase.new(); add_child(filler); crowded_grid.place_unit(filler, cell)
	var crowded_hunt: ArcfangHunt = crowded.hunt
	crowded_hunt.tick(10, crowded.heroes); crowded_hunt.tick(1.5, crowded.heroes)
	check(crowded_grid.get_unit_at(crowded.boss.grid_position) == crowded.boss, "Crowded blink never strands the boss off-grid")
	# Pause / speed use the actual manager clock; no wall timers resolve contacts.
	var clock := fixture(); var clock_mgr: AutoBattleManager = clock.mgr
	clock_mgr.battle_active = true; clock_mgr.paused = true
	clock_mgr._process(2.0)
	check(clock.hunt.remaining == 10, "Pause freezes the hunt clock")
	var paused_rows := ArcfangHunt.timer_rows(clock.boss)
	clock_mgr._process(2.0)
	check(ArcfangHunt.timer_rows(clock.boss) == paused_rows, "Pause freezes all ability timer rows")
	clock_mgr.paused = false; clock_mgr.time_scale = 2.0
	clock_mgr._process(0.5)
	check(is_equal_approx(clock.hunt.remaining, 9.0), "Hunt follows combat speed")
	clock_mgr.battle_active = false
	await simulate(60, 36)
	await simulate(61, 40)
	await simulate(62, 44)
	for f in fails: print("ARCFANG_HUNT: FAIL ", f)
	print("ARCFANG_HUNT: ALL PASS (%d checks)" % checks if fails.is_empty() else "ARCFANG_HUNT: FAILED")
	get_tree().quit(0 if fails.is_empty() else 1)
