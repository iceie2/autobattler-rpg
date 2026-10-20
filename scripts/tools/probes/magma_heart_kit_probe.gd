extends Node

var failures: Array[String] = []
var hits: Dictionary = {}

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func hero(mgr, grid, cell: Vector2i, shield: int = 0) -> VisualUnit:
	var u := EnemyFactory.create_goblin()
	u.is_player_unit = true
	add_child(u)
	u.battle_manager = mgr
	u.grid_position = cell
	grid.place_unit(u, cell)
	u.max_hp = 10000; u.current_hp = 10000; u.current_shield = shield
	u.resistance = 500; u.magic_resist = 500
	hits[u.get_instance_id()] = 0
	u.took_damage.connect(func(_amount, _source, _animate): hits[u.get_instance_id()] += 1)
	return u

func _ready() -> void:
	var grid := BattleGrid.new()
	var mgr := AutoBattleManager.new()
	add_child(grid); add_child(mgr)
	mgr.initialize(grid, null)
	var boss := EnemyFactory.create_magma_heart()
	add_child(boss)
	boss.battle_manager = mgr
	boss.grid_position = Vector2i(3, 1)
	grid.place_unit(boss, boss.grid_position)
	var near := hero(mgr, grid, Vector2i(3, 3))
	var shielded := hero(mgr, grid, Vector2i(5, 3), 25)
	var far := hero(mgr, grid, Vector2i(0, grid.grid_height - 1))
	var targets: Array = [near, shielded, far]
	mgr.player_units = targets; mgr.enemy_units = [boss]
	check(boss.health_bar.ability_timers.size() == 1 and boss.health_bar.ability_timers[0][0] == 0.0, "eruption bar exists and starts empty")
	boss.set_meta("magma_pulse_t", AutoBattleManager.MAGMA_PULSE_FIRST_DELAY * 0.5)
	mgr._sync_magma_heart(boss)
	check(is_equal_approx(float(boss.health_bar.ability_timers[0][0]), 0.5), "eruption bar is half full at half cooldown")
	boss.set_meta("magma_pulse_t", AutoBattleManager.MAGMA_PULSE_FIRST_DELAY)
	check(AutoBattleManager.magma_pulse_damage(150, 1) == 75, "pulse retains current first-hit damage")
	mgr._tick_mob_passive(boss, targets, [boss], AutoBattleManager.MAGMA_PULSE_FIRST_DELAY + 0.01)
	check(is_equal_approx(float(boss.get_meta("magma_pulse_t")), 3.74), "first pulse shortens next interval and carries clock overshoot")
	check("3.75s" in AutoBattleManager.magma_pulse_description(boss), "tooltip shares current cadence accessor")
	check(is_equal_approx(float(boss.health_bar.ability_timers[0][0]), 0.01 / 3.75), "bar resets against the accelerated interval")
	check(mgr._magma_waves.size() == 1, "eruption creates one wave")
	check(near.current_hp == 10000 and far.current_hp == 10000, "damage waits for wave arrival")
	mgr._tick_magma_waves(0.1)
	check(near.current_hp == 9925, "near hero receives one 75 true Fire hit")
	check(shielded.current_shield == 0 and shielded.current_hp == 9950, "one pulse consumes shield then deals the remainder")
	check(far.current_hp == 10000, "far hero waits for its tile")
	mgr._tick_magma_waves(0.3)
	check(far.current_hp == 9925, "wave reaches the board edge by 0.4 seconds")
	for u in targets:
		check(hits[u.get_instance_id()] == 1 and u.burn_time == 0.0, "one hit and no lingering burn")
	mgr._tick_magma_waves(0.9)
	check(mgr._magma_waves.is_empty(), "cooling wave is removed")
	for u in targets: check(hits[u.get_instance_id()] == 1, "cooling tiles cannot hit twice")
	mgr._tick_mob_passive(boss, targets, [boss], AutoBattleManager.magma_pulse_interval(1))
	mgr._tick_magma_waves(0.4)
	check(near.current_hp == 9850, "second pulse deals the same 75 damage")
	check(is_equal_approx(float(boss.get_meta("magma_pulse_t")), 3.49), "second interval shortens again")
	check(AutoBattleManager.magma_pulse_damage(150, 99) == 75, "damage stays fixed through prolonged fights")
	check(AutoBattleManager.magma_pulse_interval(12) == 1.0 and AutoBattleManager.magma_pulse_interval(99) == 1.0, "cadence reaches and holds one-second floor")
	check(AutoBattleManager.magma_pulse_damage(180) == 90, "pulse power still respects current magic power")
	mgr._clear_board_effects()
	check(mgr._magma_waves.is_empty(), "battle cleanup removes pending damage")
	boss.set_meta("magma_pulses", 8)
	boss.set_meta("magma_pulse_t", 4.0)
	mgr.start_battle()
	mgr.battle_active = false
	check(boss.get_meta("magma_pulses") == 0 and boss.get_meta("magma_pulse_t") == AutoBattleManager.MAGMA_PULSE_FIRST_DELAY, "battle restart resets acceleration and first delay")
	check(boss.health_bar.ability_timers[0][0] == 0.0, "battle restart empties eruption bar immediately")
	mgr._begin_magma_wave(boss, targets, 1)
	mgr.battle_active = true
	mgr.paused = true
	mgr._process(0.4)
	check(mgr._magma_waves[0]["elapsed"] == 0.0, "pause freezes both pulse hits and tile clock")
	mgr.paused = false; mgr.time_scale = 0.25
	mgr._process(0.4)
	check(is_equal_approx(mgr._magma_waves[0]["elapsed"], 0.1), "slow motion scales wave and damage arrival together")
	mgr.battle_active = false
	mgr._clear_board_effects()
	for message in failures: print("FAIL: ", message)
	print("MAGMA_HEART_KIT_PROBE: ", "ALL PASS" if failures.is_empty() else str(failures.size()) + " FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)
