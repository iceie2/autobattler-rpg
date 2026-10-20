extends Node

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func place(mgr: AutoBattleManager, grid: BattleGrid, unit: VisualUnit, cell: Vector2i) -> VisualUnit:
	add_child(unit)
	unit.battle_manager = mgr
	unit.grid_position = cell
	unit.position = mgr._world_pos_for(unit, cell)
	check(grid.place_unit(unit, cell), "fixture unit places successfully")
	return unit

func _ready() -> void:
	var director := WaveDirector.new()
	for difficulty in [WaveScaler.Difficulty.NORMAL, WaveScaler.Difficulty.VETERAN, WaveScaler.Difficulty.BRUTAL]:
		var spec := director.generate_wave_spec(50, difficulty, 9, -1, 77)
		var hearts: int = 0
		var occupied: Dictionary = {}
		for entry in spec:
			var pos: Vector2i = entry["pos"]
			if entry["code"] == "EMB": check(pos == Vector2i(4, 2), "body starts in yellow forward footprint")
			if entry["code"] == "EMH":
				hearts += 1
				check(pos in [Vector2i(1, 3), Vector2i(7, 3)], "hearts spawn at blue circles")
			var size: int = WaveScaler.cell_size_for_code(entry["code"])
			for dy in size:
				for dx in size:
					var cell := pos + Vector2i(dx, dy)
					check(not occupied.has(cell), "formation has no overlapping cells")
					occupied[cell] = true
		check(hearts == 2, "every difficulty has exactly two Hearts")
		check(not occupied.has(Vector2i(1, 1)) and not occupied.has(Vector2i(7, 1)), "rear return tiles are free of escorts")
		if difficulty == WaveScaler.Difficulty.NORMAL: check(spec.size() == 3, "Normal has only body and two Hearts")
	var grid := BattleGrid.new()
	var mgr := AutoBattleManager.new()
	add_child(grid); add_child(mgr)
	mgr.initialize(grid, null)
	var boss := place(mgr, grid, EnemyFactory.create_emberhollow(), Vector2i(4, 2))
	var left := place(mgr, grid, EnemyFactory.create_ember_heart(), Vector2i(1, 3))
	var right := place(mgr, grid, EnemyFactory.create_ember_heart(), Vector2i(7, 3))
	var hero := EnemyFactory.create_goblin()
	hero.is_player_unit = true
	place(mgr, grid, hero, Vector2i(1, 5))
	mgr.start_battle()
	mgr.battle_active = true
	boss.current_hp = int(boss.max_hp / 2)
	check(mgr._ember_heart_shifts.is_empty(), "boss half-health does not move Hearts")
	left.max_hp = 1000; left.current_hp = 1000
	right.max_hp = 1000; right.current_hp = 1000
	check(left.movement_speed == 0 and right.movement_speed == 0, "Hearts display and use zero movement speed")
	left.take_damage(499, UnitBase.Element.NORMAL, hero, true)
	check(left.visible and not left.has_meta("ember_heart_shifted"), "Heart stays at 50.1 percent")
	left.current_shield = 20
	left.take_damage(10, UnitBase.Element.NORMAL, hero, true)
	check(not left.has_meta("ember_heart_shifted"), "shielded hit above half HP cannot trigger shift")
	left.take_damage(11, UnitBase.Element.NORMAL, hero, true)
	check(left.current_hp == 500 and not left.visible, "Heart disappears at exactly half its own HP")
	check(right.visible and right.grid_position == Vector2i(7, 3), "other Heart stays in place")
	check(not grid.occupied_cells.values().has(left), "vanished Heart leaves no phantom blocker")
	check(mgr.emberhollow_hearts_alive(boss), "vanished Heart still gates Hollow Return")
	left.take_damage(100, UnitBase.Element.FIRE, hero, true)
	check(left.current_hp == 500, "vanished Heart cannot take area/projectile damage")
	mgr.paused = true
	mgr._process(1.0)
	check(not left.visible, "pause freezes disappearance timer")
	mgr.paused = false; mgr.time_scale = 0.25
	for u in [boss, left, right, hero]: u.stun_time = 20.0
	mgr._process(0.4)
	check(not left.visible and is_equal_approx(mgr._ember_heart_shifts[0]["time"], 0.2), "slow motion scales reappearance timer")
	mgr._tick_ember_heart_shifts(0.21)
	check(left.visible and left.grid_position == Vector2i(1, 1), "left Heart returns at left green arrow")
	check(left.current_hp == 500 and grid.get_unit_at(Vector2i(1, 1)) == left, "return preserves HP and grid registration")
	left.take_damage(1, UnitBase.Element.NORMAL, hero, true)
	check(mgr._ember_heart_shifts.is_empty(), "Heart retreats only once")
	right.take_damage(600, UnitBase.Element.NORMAL, hero, true)
	check(not right.visible and right.current_hp == 400, "crossing below half triggers right Heart independently")
	mgr._tick_ember_heart_shifts(0.31)
	check(right.visible and right.grid_position == Vector2i(7, 1), "right Heart returns at right green arrow")
	# Stationary melee units must not take the special diagonal approach step.
	grid.purge_unit(hero); hero.grid_position = Vector2i(2, 2); grid.place_unit(hero, hero.grid_position)
	left.stun_time = 0; left.action_time = 0; left.skill_cd_time = 99
	mgr._tick_unit(left, 0.1)
	check(left.grid_position == Vector2i(1, 1) and not left.is_moving, "Heart stays fixed even against a diagonal target")
	left.current_hp = 1000; right.current_hp = 1000
	mgr.start_battle()
	check(not left.has_meta("ember_heart_shifted"), "battle restart clears the one-time retreat flag")
	left.take_damage(500, UnitBase.Element.NORMAL, hero, true)
	check(not left.visible, "fresh battle permits one new retreat")
	mgr.end_battle(true)
	check(left.visible and not left.has_meta("ember_heart_shifting") and mgr._ember_heart_shifts.is_empty(), "battle ending mid-retreat restores visibility and clears pending state")
	check(grid.get_unit_at(left.grid_position) == left, "cancelled retreat restores grid registration")
	mgr.start_battle()
	boss.take_damage(boss.max_hp * 2, UnitBase.Element.NORMAL, hero, true)
	check(boss.current_hp == int(boss.max_hp * AutoBattleManager.EMBERHOLLOW_REVIVE_HP), "Hollow Return still revives with a living Heart")
	left.take_damage(5000, UnitBase.Element.NORMAL, hero, true)
	right.take_damage(5000, UnitBase.Element.NORMAL, hero, true)
	check(not mgr.emberhollow_hearts_alive(boss), "destroyed Hearts do not return or gate revival")
	check(mgr._ember_heart_shifts.is_empty(), "lethal damage cannot resurrect a Heart")
	mgr.battle_active = false
	for message in failures: print("FAIL: ", message)
	print("EMBER_HEART_LAYOUT_PROBE: ", "ALL PASS" if failures.is_empty() else str(failures.size()) + " FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)
