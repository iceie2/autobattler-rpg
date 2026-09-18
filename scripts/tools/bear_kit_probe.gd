extends Node
# Isolated Bear kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/bear_kit_probe.tscn

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
	_test_ultimate()
	_test_range_gate()
	_test_swipe_committed()
	_test_swipe_interrupt()
	_test_bleed_visual_tracks_movement()
	_test_fury()
	_test_shared_keys_unchanged()
	if _fail.is_empty():
		print("BEAR_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("BEAR_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ultimate() -> void:
	var b := EnemyFactory.create_bear_normal(); add_child(b)
	_check(b.ultimate_charge_max == 0,
		"Bear still inherits an ultimate pool (%d) — ~4 free swipes per fight at 1200 HP" % b.ultimate_charge_max)
	_check(bool(b.get_meta("bear", false)), "bear marker meta missing")

func _test_range_gate() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var b = _mk(mgr, s["grid"], EnemyFactory.create_bear_normal(), Vector2i(2, 2), false)
	var far = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(8, 2), true)
	mgr.enemy_units = [b]; mgr.player_units = [far]
	_check(not mgr._skill_trigger_ready(b, mgr.player_units),
		"Rending Swipe triggered on a target 6 tiles away")
	var near = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.player_units = [near, far]
	_check(mgr._skill_trigger_ready(b, mgr.player_units), "Rending Swipe did not fire on an adjacent target")

func _test_swipe_committed() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var b = _mk(mgr, s["grid"], EnemyFactory.create_bear_normal(), Vector2i(2, 2), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	v.max_hp = 9999; v.current_hp = 9999
	mgr.enemy_units = [b]; mgr.player_units = [v]
	var hp0: int = v.current_hp
	mgr._use_skill(b, mgr.player_units, mgr.enemy_units)
	_check(v.current_hp == hp0, "Rending Swipe dealt damage before its contact frame")
	_check(v.bleed_time == 0.0, "Rending Swipe opened the bleed before contact")
	mgr._tick_bear_swipes(AutoBattleManager.BEAR_SWIPE_CONTACT + 0.01)
	var removed: int = hp0 - v.current_hp
	_check(removed > 0, "Rending Swipe never dealt damage at contact")
	_check(b.damage_dealt == removed,
		"damage meter recorded %d but %d HP was removed" % [b.damage_dealt, removed])
	# Bleed numbers must match the printed description: 30% ATK/s for 4s.
	_check(absf(v.bleed_dps - float(b.attack_damage) * 0.3) < 0.01,
		"bleed dps is %.2f, description promises 30 percent of ATK" % v.bleed_dps)
	_check(absf(v.bleed_time - 4.0) < 0.01,
		"bleed lasts %.2fs, description promises 4s" % v.bleed_time)
	_check(not b.get_meta("hill_giant_committed", false), "committed flag never released")

func _test_swipe_interrupt() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var b = _mk(mgr, s["grid"], EnemyFactory.create_bear_normal(), Vector2i(2, 2), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	mgr.enemy_units = [b]; mgr.player_units = [v]
	var hp0: int = v.current_hp
	mgr._use_skill(b, mgr.player_units, mgr.enemy_units)
	b.stun_time = 2.0
	mgr._tick_bear_swipes(AutoBattleManager.BEAR_SWIPE_CONTACT + 0.01)
	_check(v.current_hp == hp0, "a stunned Bear still landed its swipe")
	_check(v.bleed_time == 0.0, "an interrupted swipe still opened the bleed")
	_check(not b.get_meta("hill_giant_committed", false),
		"interrupted swipe left the Bear committed forever")

# THE headline: the bleed doubles while the victim moves, and the visual must
# actually show that — otherwise the one interesting decision stays invisible.
func _test_bleed_visual_tracks_movement() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var b = _mk(mgr, s["grid"], EnemyFactory.create_bear_normal(), Vector2i(2, 2), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_goblin(), Vector2i(3, 2), true)
	v.max_hp = 9999; v.current_hp = 9999
	mgr.enemy_units = [b]; mgr.player_units = [v]
	mgr._sync_bleed_vfx()
	_check(mgr._bleed_vfx.is_empty(), "an unbled unit already has a bleed visual")
	mgr._use_skill(b, mgr.player_units, mgr.enemy_units)
	mgr._tick_bear_swipes(AutoBattleManager.BEAR_SWIPE_CONTACT + 0.01)
	v.is_moving = false
	mgr._sync_bleed_vfx()
	_check(mgr._bleed_vfx.size() == 1, "a bleeding unit has no persistent visual")
	var still: float = mgr._bleed_vfx.values()[0].intensity
	v.is_moving = true
	mgr._sync_bleed_vfx()
	var moving: float = mgr._bleed_vfx.values()[0].intensity
	_check(moving > still,
		"bleed visual does not intensify while the target moves (%.2f then %.2f)" % [still, moving])
	# And it must genuinely tick faster while moving, so the visual is honest.
	# NOTE: reset HP before BOTH samples — the swipe's own damage is still on the
	# books here, and leaving it in made the standing sample look bigger than the
	# moving one purely from the hit that opened the bleed.
	v.current_hp = 9999
	v.bleed_accum = 0.0
	v.bleed_time = 4.0
	v.is_moving = false
	mgr._tick_statuses(v, 1.0)
	var slow_dmg: int = 9999 - v.current_hp
	v.current_hp = 9999; v.bleed_accum = 0.0; v.bleed_time = 4.0
	v.is_moving = true
	mgr._tick_statuses(v, 1.0)
	var fast_dmg: int = 9999 - v.current_hp
	_check(fast_dmg > slow_dmg,
		"bleed did not tick faster while moving (%d vs %d) — the visual would be lying" % [fast_dmg, slow_dmg])
	v.bleed_time = 0.0
	mgr._sync_bleed_vfx()
	_check(mgr._bleed_vfx.is_empty(), "bleed visual outlived the bleed")

func _test_fury() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var b = _mk(mgr, s["grid"], EnemyFactory.create_bear_normal(), Vector2i(2, 2), false)
	mgr.enemy_units = [b]; mgr.player_units = []
	mgr._tick_passive(b, mgr.player_units, mgr.enemy_units, 0.1)
	_check(mgr._fury_vfx.is_empty(), "a full-HP Bear already shows Fury")
	b.current_hp = int(b.max_hp * 0.25)
	mgr._tick_passive(b, mgr.player_units, mgr.enemy_units, 0.1)
	_check(absf(float(b.get_meta("mob_aspd_bonus", 0.0)) - 0.30) < 0.001,
		"Fury bonus is %.3f at low HP, description caps at +30 percent"
			% float(b.get_meta("mob_aspd_bonus", 0.0)))
	_check(mgr._fury_vfx.size() == 1, "a raging Bear has no Fury readout")

func _test_shared_keys_unchanged() -> void:
	for pair in [["Gargoyle", EnemyFactory.create_gargoyle()], ["Harpy", EnemyFactory.create_harpy()]]:
		var m = pair[1]; add_child(m)
		_check(str(m.get_meta("mob_skill", "")) == "bear_swipe",
			"%s no longer shares bear_swipe — probe is stale" % pair[0])
		_check(not bool(m.get_meta("bear", false)),
			"%s was wrongly marked as the Bear and would gain claw VFX" % pair[0])
	for pair2 in [["Minotaur", EnemyFactory.create_minotaur()],
			["Crystal Crab", EnemyFactory.create_crystal_crab()],
			["Sky Wyvern", EnemyFactory.create_sky_wyvern()]]:
		var m2 = pair2[1]; add_child(m2)
		_check(str(m2.get_meta("mob_passive", "")) == "bear_fury",
			"%s no longer shares bear_fury — probe is stale" % pair2[0])
		_check(not bool(m2.get_meta("bear", false)),
			"%s was wrongly marked as the Bear and would gain the Fury readout" % pair2[0])
