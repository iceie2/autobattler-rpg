extends Node
# Boss signature probe (2026-09-28 owner ruling: signatures do what their
# tooltips say; range measured from the BODY). Drives the REAL manager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/boss_signature_probe.tscn

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

func _hero(mgr, grid, cell: Vector2i):
	var h = _mk(mgr, grid, EnemyFactory.create_by_type("goblin"), cell, true)
	h.max_hp = 99999; h.current_hp = 99999
	return h

func _ready() -> void:
	_test_every_signature_is_mapped()
	_test_single_hits_one()
	_test_area_hits_far_side_of_2x2()
	_test_out_of_reach_is_not_ready()
	if _fail.is_empty():
		print("BOSS_SIGNATURE_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("BOSS_SIGNATURE_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

# No Warrior-class boss may silently fall back to the hero Whirlwind again.
func _test_every_signature_is_mapped() -> void:
	for code in ["khagan", "triarch", "drowned_maw", "cloven_titan", "emberhollow",
			"ember_heart", "arcfang", "gravekeeper", "the_architect"]:
		var b = EnemyFactory.create_by_type(code); add_child(b)
		_check(AutoBattleManager.BOSS_SIGNATURES.has(b.skill_name),
			"%s's '%s' is not in BOSS_SIGNATURES — it would cast the hero Whirlwind" % [code, b.skill_name])
		# No declared ultimate => no charge pool. The inherited 300 made the generic
		# ult re-cast the signature ~1/s, cooldown-free (found 2026-09-28).
		_check(b.ultimate_charge_max == 0,
			"%s inherits an ultimate pool (%d) — it would spam its signature" % [code, b.ultimate_charge_max])
	for code in ["skyrender", "hydra_normal"]:
		var b2 = EnemyFactory.create_by_type(code); add_child(b2)
		_check(b2.ultimate_charge_max == 0,
			"%s inherits an ultimate pool (%d)" % [code, b2.ultimate_charge_max])

# Drowned Maw (2×2) with two heroes in reach: Undertow bites exactly one.
func _test_single_hits_one() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var maw = _mk(mgr, g, EnemyFactory.create_by_type("drowned_maw"), Vector2i(2, 1), false)
	var a = _hero(mgr, g, Vector2i(1, 1))      # flush west
	var b = _hero(mgr, g, Vector2i(4, 2))      # flush east (far side from the origin)
	mgr.enemy_units = [maw]; mgr.player_units = [a, b]
	mgr._use_skill(maw, mgr.player_units, mgr.enemy_units)
	var hit: int = int(a.current_hp < 99999) + int(b.current_hp < 99999)
	_check(hit == 1, "Undertow hit %d heroes, the tooltip says one" % hit)
	_check(maw.damage_dealt > 0, "signature damage was not credited to the boss")

# Gravekeeper (2×2) sweep: a hero flush against the FAR side of the body must be
# hit — the old corner-measured whirlwind missed exactly this one.
func _test_area_hits_far_side_of_2x2() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var gk = _mk(mgr, g, EnemyFactory.create_by_type("gravekeeper"), Vector2i(2, 1), false)
	var near = _hero(mgr, g, Vector2i(1, 1))
	var far = _hero(mgr, g, Vector2i(4, 2))
	var away = _hero(mgr, g, Vector2i(6, 4))
	mgr.enemy_units = [gk]; mgr.player_units = [near, far, away]
	mgr._use_skill(gk, mgr.player_units, mgr.enemy_units)
	_check(near.current_hp < 99999, "sweep missed the hero on the origin side")
	_check(far.current_hp < 99999, "sweep missed the hero on the FAR side of the 2×2 body")
	_check(away.current_hp == 99999, "sweep hit a hero out of reach")

func _test_out_of_reach_is_not_ready() -> void:
	var s := _fresh(); var mgr = s["mgr"]; var g = s["grid"]
	var arc = _mk(mgr, g, EnemyFactory.create_by_type("arcfang"), Vector2i(1, 1), false)
	var h = _hero(mgr, g, Vector2i(6, 5))
	mgr.enemy_units = [arc]; mgr.player_units = [h]
	_check(not mgr._skill_trigger_ready(arc, mgr.player_units),
		"Sunder Bite is ready with nobody in reach — it would swing at air")
