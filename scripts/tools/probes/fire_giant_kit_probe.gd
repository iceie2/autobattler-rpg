extends Node
# Isolated Fire Giant kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/fire_giant_kit_probe.tscn

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
	_test_molten_smash_inherits_fixes()
	_test_forge_fury()
	_test_three_crush_users_stay_separate()
	if _fail.is_empty():
		print("FIRE_GIANT_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("FIRE_GIANT_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ultimate() -> void:
	var g := EnemyFactory.create_by_type("fire_giant"); add_child(g)
	_check(g.ultimate_charge_max == 0,
		"Fire Giant still inherits an ultimate pool (%d) — ~7.7 free Molten Smashes at 2300 HP"
			% g.ultimate_charge_max)
	_check(bool(g.get_meta("fire_giant", false)), "fire_giant marker meta missing")
	_check(g.cell_size == 2, "Fire Giant is no longer 2x2 — FIRE_GIANT_REACH assumes it")
	# Name-match rule, inverted: its names DIFFER from the Orc's, so it must NOT
	# opt into the shared slam visual.
	var orc := EnemyFactory.create_by_type("orc_normal"); add_child(orc)
	_check(g.skill_name != orc.skill_name,
		"Fire Giant's skill is now named the same as the Orc's — it should then SHARE the slam, not have its own")
	_check(float(g.get_meta("crush_vfx_reach", 0.0)) == 0.0,
		"Fire Giant opted into the ORC's slam visual despite having its own ability names")

func _test_molten_smash_inherits_fixes() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var g = _mk(mgr, s["grid"], EnemyFactory.create_by_type("fire_giant"), Vector2i(2, 2), false)
	# 2x2 occupies (2,2)-(3,3); (8,2) is well out of its melee reach.
	var far = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(8, 2), true)
	mgr.enemy_units = [g]; mgr.player_units = [far]
	_check(not mgr._skill_trigger_ready(g, mgr.player_units),
		"Molten Smash triggered on a distant target — it should inherit brute_crush's melee gate")
	var v = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(4, 3), true)
	v.max_hp = 9999; v.current_hp = 9999
	mgr.player_units = [v, far]
	var hp0: int = v.current_hp
	mgr._use_skill(g, mgr.player_units, mgr.enemy_units)
	_check(v.current_hp == hp0, "Molten Smash dealt damage before its contact frame")
	mgr._tick_orc_crushes(AutoBattleManager.ORC_CRUSH_CONTACT + 0.01)
	var removed: int = hp0 - v.current_hp
	_check(removed > 0, "Molten Smash never landed at contact")
	_check(g.damage_dealt == removed,
		"damage meter recorded %d but %d HP was removed" % [g.damage_dealt, removed])
	_check(v.stun_time > 0.0, "Molten Smash did not apply the 1s stun its description promises")

func _test_forge_fury() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var g = _mk(mgr, s["grid"], EnemyFactory.create_by_type("fire_giant"), Vector2i(2, 2), false)
	mgr.enemy_units = [g]; mgr.player_units = []
	mgr._tick_passive(g, mgr.player_units, mgr.enemy_units, 0.1)
	_check(mgr._forge_fury_vfx.is_empty(), "a full-HP Fire Giant already shows Forge Fury")
	_check(absf(float(g.get_meta("mob_dmg_bonus", 0.0))) < 0.001,
		"Forge Fury paid out above 50% HP")
	# Cross the threshold.
	g.current_hp = int(g.max_hp * 0.4)
	mgr._tick_passive(g, mgr.player_units, mgr.enemy_units, 0.1)
	_check(absf(float(g.get_meta("mob_dmg_bonus", 0.0)) - 0.20) < 0.001,
		"Forge Fury damage bonus is %.3f, description promises +20 percent"
			% float(g.get_meta("mob_dmg_bonus", 0.0)))
	_check(absf(float(g.get_meta("mob_aspd_bonus", 0.0)) - 0.15) < 0.001,
		"Forge Fury attack-speed bonus is %.3f, description promises +15 percent"
			% float(g.get_meta("mob_aspd_bonus", 0.0)))
	_check(mgr._forge_fury_vfx.size() == 1,
		"Forge Fury is running with no readout — the moment it got 20 percent stronger stays silent")
	# Its own readout, not the Orc's.
	_check(mgr._orc_rage_vfx.is_empty(), "the Fire Giant borrowed the Orc's Bloodrage readout")
	# Healing back above the line must clear it.
	g.current_hp = g.max_hp
	mgr._tick_passive(g, mgr.player_units, mgr.enemy_units, 0.1)
	_check(mgr._forge_fury_vfx.is_empty(), "Forge Fury readout survived healing back above 50%")

# THREE mobs ride brute_crush/orc_rage. The Orc and Ogre share a name so they
# share a visual; the Fire Giant's names are its own so it must not.
func _test_three_crush_users_stay_separate() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var orc = _mk(mgr, s["grid"], EnemyFactory.create_by_type("orc_normal"), Vector2i(1, 1), false)
	var ogre = _mk(mgr, s["grid"], EnemyFactory.create_by_type("ogre"), Vector2i(3, 1), false)
	var fg = _mk(mgr, s["grid"], EnemyFactory.create_by_type("fire_giant"), Vector2i(6, 1), false)
	mgr.enemy_units = [orc, ogre, fg]; mgr.player_units = []
	for u in [orc, ogre, fg]:
		u.current_hp = int(u.max_hp * 0.3)
		mgr._tick_passive(u, mgr.player_units, mgr.enemy_units, 0.1)
	_check(mgr._orc_rage_vfx.size() == 2,
		"expected 2 Bloodrage readouts (Orc + Ogre, same ability name), found %d" % mgr._orc_rage_vfx.size())
	_check(mgr._forge_fury_vfx.size() == 1,
		"expected exactly 1 Forge Fury readout, found %d" % mgr._forge_fury_vfx.size())
	_check(not bool(orc.get_meta("fire_giant", false)), "the Orc was marked as a Fire Giant")
	_check(not bool(ogre.get_meta("fire_giant", false)), "the Ogre was marked as a Fire Giant")
