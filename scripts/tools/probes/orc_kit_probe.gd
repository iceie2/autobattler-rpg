extends Node
# Isolated Orc kit probe, driving the REAL AutoBattleManager.
# Units built via create_by_type so they carry the affinity profile waves spawn.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/orc_kit_probe.tscn

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
	_test_crush_committed()
	_test_crush_interrupt()
	_test_bloodrage_threshold()
	_test_shared_keys_unchanged()
	if _fail.is_empty():
		print("ORC_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("ORC_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ultimate() -> void:
	var o := EnemyFactory.create_by_type("orc_normal"); add_child(o)
	_check(o.ultimate_charge_max == 0,
		"Orc still inherits an ultimate pool (%d) — ~2.5 free Crushing Blows at 750 HP" % o.ultimate_charge_max)
	_check(o.get_meta("crush_vfx_reach", 0.0) > 0.0, "Orc slam-VFX reach missing")

func _test_range_gate() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var o = _mk(mgr, s["grid"], EnemyFactory.create_by_type("orc_normal"), Vector2i(2, 2), false)
	var far = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(8, 2), true)
	mgr.enemy_units = [o]; mgr.player_units = [far]
	_check(not mgr._skill_trigger_ready(o, mgr.player_units),
		"Crushing Blow triggered on a target 6 tiles away")
	var near = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(3, 2), true)
	mgr.player_units = [near, far]
	_check(mgr._skill_trigger_ready(o, mgr.player_units), "Crushing Blow did not fire on an adjacent target")

func _test_crush_committed() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var o = _mk(mgr, s["grid"], EnemyFactory.create_by_type("orc_normal"), Vector2i(2, 2), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(3, 2), true)
	v.max_hp = 9999; v.current_hp = 9999
	mgr.enemy_units = [o]; mgr.player_units = [v]
	var hp0: int = v.current_hp
	mgr._use_skill(o, mgr.player_units, mgr.enemy_units)
	_check(v.current_hp == hp0, "Crushing Blow dealt damage before its contact frame")
	_check(v.stun_time == 0.0, "Crushing Blow stunned before contact")
	_check(o.get_meta("hill_giant_committed", false), "Orc not flagged committed while winding up")
	mgr._tick_orc_crushes(AutoBattleManager.ORC_CRUSH_CONTACT + 0.01)
	var removed: int = hp0 - v.current_hp
	_check(removed > 0, "Crushing Blow never dealt damage at contact")
	_check(o.damage_dealt == removed,
		"damage meter recorded %d but %d HP was removed" % [o.damage_dealt, removed])
	_check(absf(v.stun_time - v.tenacity_scaled(1.0)) < 0.001,
		"Crushing Blow stun is %.3fs, description promises 1s scaled by tenacity" % v.stun_time)
	_check(not o.get_meta("hill_giant_committed", false), "committed flag never released")

func _test_crush_interrupt() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var o = _mk(mgr, s["grid"], EnemyFactory.create_by_type("orc_normal"), Vector2i(2, 2), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(3, 2), true)
	mgr.enemy_units = [o]; mgr.player_units = [v]
	var hp0: int = v.current_hp
	mgr._use_skill(o, mgr.player_units, mgr.enemy_units)
	o.stun_time = 2.0
	mgr._tick_orc_crushes(AutoBattleManager.ORC_CRUSH_CONTACT + 0.01)
	_check(v.current_hp == hp0, "a stunned Orc still landed its Crushing Blow")
	_check(v.stun_time == 0.0, "an interrupted Crushing Blow still stunned")
	_check(not o.get_meta("hill_giant_committed", false),
		"interrupted crush left the Orc committed forever")

# Bloodrage is BINARY at 50% HP — the flip is the interesting moment and it must
# both apply the numbers and announce itself.
func _test_bloodrage_threshold() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var o = _mk(mgr, s["grid"], EnemyFactory.create_by_type("orc_normal"), Vector2i(2, 2), false)
	mgr.enemy_units = [o]; mgr.player_units = []
	mgr._tick_passive(o, mgr.player_units, mgr.enemy_units, 0.1)
	_check(float(o.get_meta("mob_dmg_bonus", -1.0)) == 0.0, "Bloodrage applied above 50% HP")
	_check(mgr._orc_rage_vfx.is_empty(), "a healthy Orc already shows Bloodrage")
	# Cross the threshold.
	o.current_hp = int(o.max_hp * 0.4)
	mgr._tick_passive(o, mgr.player_units, mgr.enemy_units, 0.1)
	_check(absf(float(o.get_meta("mob_dmg_bonus", 0.0)) - 0.20) < 0.001,
		"Bloodrage damage bonus is %.3f, description promises +20 percent"
			% float(o.get_meta("mob_dmg_bonus", 0.0)))
	_check(absf(float(o.get_meta("mob_aspd_bonus", 0.0)) - 0.15) < 0.001,
		"Bloodrage attack-speed bonus is %.3f, description promises +15 percent"
			% float(o.get_meta("mob_aspd_bonus", 0.0)))
	_check(mgr._orc_rage_vfx.size() == 1,
		"an enraged Orc has no readout — it silently became 20 percent stronger")
	# And the buff must actually reach outgoing damage.
	_check(o.outgoing_damage_multiplier() > 1.0,
		"Bloodrage set a meta but did not raise outgoing damage (mult %.3f)"
			% o.outgoing_damage_multiplier())
	# Healing back above the line must clear both the numbers and the readout.
	o.current_hp = o.max_hp
	mgr._tick_passive(o, mgr.player_units, mgr.enemy_units, 0.1)
	_check(float(o.get_meta("mob_dmg_bonus", -1.0)) == 0.0, "Bloodrage persisted after healing above 50%")
	_check(mgr._orc_rage_vfx.is_empty(), "Bloodrage readout survived healing above the threshold")

# brute_crush is shared with the Ogre, Fire Giant and Tidepool Horror;
# orc_rage with the Ogre and Fire Giant. None may gain the Orc's identity.
func _test_shared_keys_unchanged() -> void:
	for code in ["ogre", "fire_giant", "tidepool_horror"]:
		var u := EnemyFactory.create_by_type(code); add_child(u)
		_check(str(u.get_meta("mob_skill", "")) == "brute_crush",
			"%s no longer shares brute_crush — probe is stale" % code)
	# The Ogre's ability is named identically ("Crushing Blow"/"Bloodrage"), so it
	# SHARES the visual language at its own scale — showing it something different
	# would misrepresent an identical ability. The Fire Giant and Tidepool Horror
	# name their abilities differently, so they stay opted out until their passes.
	var ogre_u := EnemyFactory.create_by_type("ogre"); add_child(ogre_u)
	_check(ogre_u.get_meta("crush_vfx_reach", 0.0) > 0.0,
		"the Ogre shares Crushing Blow by name but gets no slam VFX")
	for code2 in ["fire_giant", "tidepool_horror"]:
		var u2 := EnemyFactory.create_by_type(code2); add_child(u2)
		_check(u2.get_meta("crush_vfx_reach", 0.0) == 0.0,
			"%s opted into the Orc slam VFX but its ability has its own name" % code2)
	# The shared BUG FIXES should still reach them: a non-Orc user must also be
	# committed rather than resolving instantly.
	var s := _fresh(); var mgr = s["mgr"]
	var ogre = _mk(mgr, s["grid"], EnemyFactory.create_by_type("ogre"), Vector2i(2, 2), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(3, 2), true)
	v.max_hp = 9999; v.current_hp = 9999
	mgr.enemy_units = [ogre]; mgr.player_units = [v]
	var hp0: int = v.current_hp
	mgr._use_skill(ogre, mgr.player_units, mgr.enemy_units)
	_check(v.current_hp == hp0, "the Ogre's Crushing Blow still resolves instantly")
	mgr._tick_orc_crushes(AutoBattleManager.ORC_CRUSH_CONTACT + 0.01)
	_check(v.current_hp < hp0, "the Ogre's Crushing Blow never landed at contact")
	_check(ogre.damage_dealt == hp0 - v.current_hp,
		"the Ogre's damage credit is not post-mitigation")
