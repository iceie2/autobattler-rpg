extends Node
# Isolated Ogre kit probe, driving the REAL AutoBattleManager.
# The Ogre shares `brute_crush` and `orc_rage` with the Orc, so it inherits
# those fixes; this asserts the inheritance actually holds AND that its own
# numbers (180% ATK / 8s CD / 900 HP) are the ones being used, not the Orc's.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/ogre_kit_probe.tscn

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
	_test_ultimate_and_identity()
	_test_inherits_crush_fixes()
	_test_uses_its_own_numbers()
	_test_bloodrage()
	if _fail.is_empty():
		print("OGRE_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("OGRE_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ultimate_and_identity() -> void:
	var o := EnemyFactory.create_by_type("ogre"); add_child(o)
	_check(o.ultimate_charge_max == 0,
		"Ogre still inherits an ultimate pool (%d) — ~3 free Crushing Blows at 900 HP" % o.ultimate_charge_max)
	# Identically-named ability => same visual language, scaled to a bigger body.
	var reach: float = o.get_meta("crush_vfx_reach", 0.0)
	_check(reach > 0.0, "Ogre has no slam VFX despite sharing the Crushing Blow name")
	var orc := EnemyFactory.create_by_type("orc_normal"); add_child(orc)
	_check(reach > orc.get_meta("crush_vfx_reach", 0.0),
		"Ogre's slam is not scaled larger than the Orc's (%.0f vs %.0f) despite a bigger body"
			% [reach, orc.get_meta("crush_vfx_reach", 0.0)])
	_check(o.skill_name == orc.skill_name,
		"Ogre and Orc skill names diverged — the shared-visual rationale no longer holds")

func _test_inherits_crush_fixes() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var o = _mk(mgr, s["grid"], EnemyFactory.create_by_type("ogre"), Vector2i(2, 2), false)
	var far = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(8, 2), true)
	mgr.enemy_units = [o]; mgr.player_units = [far]
	_check(not mgr._skill_trigger_ready(o, mgr.player_units),
		"Ogre's Crushing Blow triggered on a target 6 tiles away — it should inherit the melee gate")
	var near = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(3, 2), true)
	mgr.player_units = [near, far]
	_check(mgr._skill_trigger_ready(o, mgr.player_units), "Ogre did not fire on an adjacent target")

func _test_uses_its_own_numbers() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var o = _mk(mgr, s["grid"], EnemyFactory.create_by_type("ogre"), Vector2i(2, 2), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(3, 2), true)
	v.max_hp = 99999; v.current_hp = 99999
	v.resistance = 0; v.magic_resist = 0          # isolate the raw multiplier
	mgr.enemy_units = [o]; mgr.player_units = [v]
	_check(absf(o.skill_damage_multiplier - 1.8) < 0.001,
		"Ogre skill multiplier is %.2f, description promises 180 percent" % o.skill_damage_multiplier)
	_check(o.skill_cooldown_max == 8, "Ogre cooldown is %d, description promises 8s" % o.skill_cooldown_max)
	var hp0: int = v.current_hp
	mgr._use_skill(o, mgr.player_units, mgr.enemy_units)
	_check(v.current_hp == hp0, "Ogre's Crushing Blow resolved instantly")
	mgr._tick_orc_crushes(AutoBattleManager.ORC_CRUSH_CONTACT + 0.01)
	var removed: int = hp0 - v.current_hp
	_check(removed > 0, "Ogre's Crushing Blow never landed")
	_check(o.damage_dealt == removed,
		"damage meter recorded %d but %d HP was removed" % [o.damage_dealt, removed])
	# It must be using ITS 180%, not the Orc's 160%.
	var expect: int = int(float(o.attack_damage) * 1.8)
	_check(absf(float(removed) - float(expect)) <= float(expect) * 0.5 + 2.0,
		"Ogre removed %d HP; 180%% of its %d ATK is ~%d — it may be using the wrong multiplier"
			% [removed, o.attack_damage, expect])
	_check(absf(v.stun_time - v.tenacity_scaled(1.0)) < 0.001,
		"Ogre stun is %.3fs, description promises 1s scaled by tenacity" % v.stun_time)

func _test_bloodrage() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var o = _mk(mgr, s["grid"], EnemyFactory.create_by_type("ogre"), Vector2i(2, 2), false)
	mgr.enemy_units = [o]; mgr.player_units = []
	mgr._tick_passive(o, mgr.player_units, mgr.enemy_units, 0.1)
	_check(float(o.get_meta("mob_dmg_bonus", -1.0)) == 0.0, "Bloodrage applied above 50% HP")
	_check(mgr._orc_rage_vfx.is_empty(), "a healthy Ogre already shows Bloodrage")
	o.current_hp = int(o.max_hp * 0.4)
	mgr._tick_passive(o, mgr.player_units, mgr.enemy_units, 0.1)
	_check(absf(float(o.get_meta("mob_dmg_bonus", 0.0)) - 0.20) < 0.001,
		"Bloodrage damage bonus is %.3f, description promises +20 percent"
			% float(o.get_meta("mob_dmg_bonus", 0.0)))
	_check(mgr._orc_rage_vfx.size() == 1,
		"an enraged Ogre has no readout — same passive name as the Orc, so it must announce itself too")
	o.current_hp = o.max_hp
	mgr._tick_passive(o, mgr.player_units, mgr.enemy_units, 0.1)
	_check(mgr._orc_rage_vfx.is_empty(), "Bloodrage readout survived healing above the threshold")
