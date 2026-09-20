extends Node
# Isolated Storm Giant kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/storm_giant_kit_probe.tscn

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
	_test_inherits_clap_fixes()
	_test_clap_uses_own_numbers()
	_test_gathering_storm()
	_test_neighbours_unchanged()
	if _fail.is_empty():
		print("STORM_GIANT_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("STORM_GIANT_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ultimate_and_identity() -> void:
	var g := EnemyFactory.create_by_type("storm_giant"); add_child(g)
	_check(g.ultimate_charge_max == 0,
		"Storm Giant still inherits an ultimate pool (%d) — ~7.2 free Thunderclaps at 2150 HP"
			% g.ultimate_charge_max)
	_check(bool(g.get_meta("storm_giant", false)), "storm_giant marker meta missing")
	_check(g.cell_size == 2, "Storm Giant is no longer 2x2 — the VFX reach assumes it")
	# Its abilities are named differently from the Wind-Up Bot's, so it must NOT
	# be wearing the Bot's identity.
	_check(not bool(g.get_meta("windup_bot", false)),
		"Storm Giant was marked as a Wind-Up Bot — it would gain the knock-up and clockwork VFX")

func _test_inherits_clap_fixes() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var g = _mk(mgr, s["grid"], EnemyFactory.create_by_type("storm_giant"), Vector2i(2, 2), false)
	var far = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(8, 6), true)
	mgr.enemy_units = [g]; mgr.player_units = [far]
	_check(not mgr._skill_trigger_ready(g, mgr.player_units),
		"Thunderclap triggered on a distant target — it should inherit the melee gate")
	# A 2x2 body occupies (2,2)-(3,3), so (4,3) is adjacent to its edge.
	var near = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(4, 3), true)
	mgr.player_units = [near, far]
	_check(mgr._skill_trigger_ready(g, mgr.player_units),
		"Thunderclap did not fire on a target flush with its 2x2 body")

func _test_clap_uses_own_numbers() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var g = _mk(mgr, s["grid"], EnemyFactory.create_by_type("storm_giant"), Vector2i(2, 2), false)
	var v = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(4, 3), true)
	v.max_hp = 99999; v.current_hp = 99999
	mgr.enemy_units = [g]; mgr.player_units = [v]
	_check(absf(g.skill_damage_multiplier - 1.6) < 0.001,
		"Storm Giant multiplier is %.2f, description promises 160 percent" % g.skill_damage_multiplier)
	_check(g.skill_cooldown_max == 7, "cooldown is %d, description promises 7s" % g.skill_cooldown_max)
	var hp0: int = v.current_hp
	mgr._use_skill(g, mgr.player_units, mgr.enemy_units)
	_check(v.current_hp == hp0, "Thunderclap dealt damage before its contact frame")
	mgr._tick_windup_punches(AutoBattleManager.WINDUP_PUNCH_CONTACT + 0.01)
	var removed: int = hp0 - v.current_hp
	_check(removed > 0, "Thunderclap never landed at contact")
	_check(g.damage_dealt == removed,
		"damage meter recorded %d but %d HP was removed" % [g.damage_dealt, removed])
	# Shared key, but it keeps the 1.0s stun — the Bot's 1.5s + knock-up is the
	# Bot's alone.
	_check(absf(v.stun_time - v.tenacity_scaled(1.0)) < 0.001,
		"Thunderclap stun is %.3fs, expected the unchanged 1.0s scaled" % v.stun_time)
	_check(absf(v._toss_offset.y) < 0.01,
		"Thunderclap knocked the target airborne — that is the Wind-Up Bot's alone")

# Same +5%/3s ramp as the Bot's Overclock, but its own fiction and its own
# visual. Previously the ramp was completely invisible on this unit.
func _test_gathering_storm() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var g = _mk(mgr, s["grid"], EnemyFactory.create_by_type("storm_giant"), Vector2i(2, 2), false)
	mgr.enemy_units = [g]; mgr.player_units = []
	g.set_meta("oc_time", 0.0)
	mgr._tick_passive(g, mgr.player_units, mgr.enemy_units, 0.0)
	_check(mgr._gathering_vfx.is_empty(), "a fresh Storm Giant already shows a gathered storm")
	# 15s in => 5 steps => +25%.
	g.set_meta("oc_time", 15.0)
	mgr._tick_passive(g, mgr.player_units, mgr.enemy_units, 0.0)
	_check(absf(float(g.get_meta("oc_bonus", 0.0)) - 0.25) < 0.001,
		"at 15s the ramp is %.3f, description promises +5%% every 3s (=+25%%)"
			% float(g.get_meta("oc_bonus", 0.0)))
	_check(mgr._gathering_vfx.size() == 1, "a gathering storm has no readout")
	var mid: float = mgr._gathering_vfx.values()[0].storm
	# 30s in => capped at +50%.
	g.set_meta("oc_time", 30.0)
	mgr._tick_passive(g, mgr.player_units, mgr.enemy_units, 0.0)
	_check(absf(float(g.get_meta("oc_bonus", 0.0)) - 0.50) < 0.001,
		"the ramp did not cap at the stated +50%% (%.3f)" % float(g.get_meta("oc_bonus", 0.0)))
	_check(mgr._gathering_vfx.values()[0].storm > mid,
		"the storm visual did not thicken as the ramp climbed (%.2f then %.2f)"
			% [mid, mgr._gathering_vfx.values()[0].storm])
	# It must use ITS readout, not the Wind-Up Bot's clockwork one.
	_check(mgr._windup_oc_vfx.is_empty(),
		"the Storm Giant borrowed the Wind-Up Bot's clockwork Overclock badge")

func _test_neighbours_unchanged() -> void:
	var bot := EnemyFactory.create_by_type("windup_bot_normal"); add_child(bot)
	_check(not bool(bot.get_meta("storm_giant", false)),
		"the Wind-Up Bot was wrongly marked as a Storm Giant")
	_check(bool(bot.get_meta("windup_bot", false)), "the Wind-Up Bot lost its own marker")
	var husk := EnemyFactory.create_by_type("coral_husk"); add_child(husk)
	_check(str(husk.get_meta("mob_passive", "")) == "windup_overclock",
		"the Coral Husk no longer shares windup_overclock — probe is stale")
	_check(not bool(husk.get_meta("storm_giant", false)),
		"the Coral Husk was wrongly marked as a Storm Giant and would gain a thunderhead")
