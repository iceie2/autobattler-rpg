extends Node
# Gale Warden flock probe (2026-09-28 owner design), driving the REAL manager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/gale_flock_probe.tscn

var _fail: Array = []

func _check(c: bool, m: String) -> void:
	if not c: _fail.append(m)

func _fresh() -> Dictionary:
	var grid := BattleGrid.new(); var mgr := AutoBattleManager.new(); var fx := Node2D.new()
	add_child(grid); add_child(mgr); add_child(fx)
	mgr.initialize(grid, null); mgr.skill_effect_container = fx
	return {"grid": grid, "mgr": mgr}

func _mk(mgr, grid, u, cell: Vector2i, player: bool):
	add_child(u); u.battle_manager = mgr; u.is_player_unit = player
	assert(grid.place_unit(u, cell)); u.grid_position = cell
	return u

func _ready() -> void:
	_test_flock_sizes()
	_test_spread()
	_test_scatter()
	if _fail.is_empty():
		print("GALE_FLOCK_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("GALE_FLOCK_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_flock_sizes() -> void:
	for d in 3:
		var n := 0
		for e in WaveScaler.build_elite_formation(15, d, 9):
			if e["code"] == "GW": n += 1
		_check(n == WaveScaler.GALE_FLOCK_SIZE[d],
			"difficulty %d fielded %d birds, want %d" % [d, n, WaveScaler.GALE_FLOCK_SIZE[d]])

# Four birds, four heroes: every hero should get exactly one bird.
func _test_spread() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var birds: Array = []
	for x in 4:
		birds.append(_mk(mgr, g, EnemyFactory.create_by_type("gale_warden"), Vector2i(x * 2, 1), false))
	var heroes: Array = []
	for x in 4:
		heroes.append(_mk(mgr, g, EnemyFactory.create_by_type("goblin"), Vector2i(x * 2 + 1, 6), true))
	mgr.enemy_units = birds; mgr.player_units = heroes
	for _pass in 3:   # a few frames of retargeting, like the real tick
		for b in birds:
			b.target_unit = mgr._choose_target(b, heroes)
	var per := {}
	for b in birds:
		per[b.target_unit] = int(per.get(b.target_unit, 0)) + 1
	_check(per.size() == 4, "4 birds covered %d heroes — they should spread one per hero" % per.size())

# Kill one bird: the others lose their dodge for GALE_SCATTER_TIME, then regain it.
func _test_scatter() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var birds: Array = []
	for x in 3:
		birds.append(_mk(mgr, g, EnemyFactory.create_by_type("gale_warden"), Vector2i(x * 2, 1), false))
	mgr.enemy_units = birds; mgr.player_units = []
	for b in birds: mgr._tick_mob_passive(b, [], birds, 0.1)   # learn the flock size
	birds[0].current_hp = 0
	for b in birds.slice(1): mgr._tick_mob_passive(b, [], birds, 0.1)
	_check(float(birds[1].get_meta("scatter_t", 0.0)) > 0.0, "a flockmate died but the survivor did not scatter")
	# Scattered: 200 direct hits should never be dodged.
	var hp0: int = birds[1].current_hp
	birds[1].max_hp = 999999; birds[1].current_hp = 999999
	var times0: int = birds[1].times_hit
	for i in 200: birds[1].take_damage(1, UnitBase.Element.NORMAL, null)
	_check(birds[1].times_hit - times0 == 200, "a scattered bird still dodged %d of 200 hits" % (200 - (birds[1].times_hit - times0)))
	for i in 30: mgr._tick_mob_passive(birds[1], [], birds, 0.1)
	_check(float(birds[1].get_meta("scatter_t", 0.0)) <= 0.0, "scatter never wore off")
