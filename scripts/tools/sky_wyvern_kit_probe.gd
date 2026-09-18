extends Node
# Isolated Sky Wyvern kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/sky_wyvern_kit_probe.tscn

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
	_test_sting_committed_and_venom_flavour()
	_test_three_dot_fictions()
	_test_wounded_dive()
	if _fail.is_empty():
		print("SKY_WYVERN_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("SKY_WYVERN_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ultimate() -> void:
	var w := EnemyFactory.create_by_type("sky_wyvern"); add_child(w)
	_check(w.ultimate_charge_max == 0,
		"Sky Wyvern still inherits an ultimate pool (%d) — ~7 free Venom Stingers at 2120 HP"
			% w.ultimate_charge_max)
	_check(bool(w.get_meta("sky_wyvern", false)), "sky_wyvern marker meta missing")
	_check(w.cell_size == 2, "Sky Wyvern is no longer 2x2 — the VFX reach assumes it")

func _test_sting_committed_and_venom_flavour() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var w = _mk(mgr, s["grid"], EnemyFactory.create_by_type("sky_wyvern"), Vector2i(2, 2), false)
	# 2x2 occupies (2,2)-(3,3), so (4,3) is flush with its edge.
	var v = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(4, 3), true)
	v.max_hp = 9999; v.current_hp = 9999
	mgr.enemy_units = [w]; mgr.player_units = [v]
	var hp0: int = v.current_hp
	mgr._use_skill(w, mgr.player_units, mgr.enemy_units)
	_check(v.current_hp == hp0, "Venom Stinger dealt damage before its contact frame")
	mgr._tick_rat_bites(AutoBattleManager.RAT_BITE_CONTACT + 0.01)
	var removed: int = hp0 - v.current_hp
	_check(removed > 0, "Venom Stinger never landed at contact")
	_check(w.damage_dealt == removed,
		"damage meter recorded %d but %d HP was removed" % [w.damage_dealt, removed])
	# THE fix: its poison must not be flavoured as fire.
	_check(str(v.burn_flavor) == "venom",
		"the Wyvern's DoT flavour is '%s' — its description promises poison, not fire"
			% str(v.burn_flavor))
	_check(absf(v.burn_time - 3.0) < 0.01,
		"venom lasts %.2fs, description promises 3s" % v.burn_time)
	_check(absf(v.burn_dps - float(w.attack_damage) * 0.35) < 0.01,
		"venom dps is %.2f, description promises 35 percent of ATK" % v.burn_dps)
	mgr._sync_disease_vfx()
	_check(mgr._disease_vfx.size() == 1, "envenomed target has no persistent visual")
	v.burn_time = 0.0
	mgr._sync_disease_vfx()
	_check(mgr._disease_vfx.is_empty(), "venom visual outlived the DoT")

# THREE mobs ride rat_bite with three fictions: Rat disease, Hellhound fire
# (correct default, keeps the generic burn), Sky Wyvern venom.
func _test_three_dot_fictions() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var rat = _mk(mgr, s["grid"], EnemyFactory.create_by_type("rat"), Vector2i(1, 1), false)
	var hound = _mk(mgr, s["grid"], EnemyFactory.create_by_type("hellhound"), Vector2i(3, 1), false)
	var wyv = _mk(mgr, s["grid"], EnemyFactory.create_by_type("sky_wyvern"), Vector2i(5, 1), false)
	var a = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(1, 2), true)
	var b = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(3, 2), true)
	var c = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(5, 3), true)
	for u in [a, b, c]:
		u.max_hp = 9999; u.current_hp = 9999
	mgr.enemy_units = [rat, hound, wyv]; mgr.player_units = [a, b, c]
	for caster in [rat, hound, wyv]:
		mgr._use_skill(caster, mgr.player_units, mgr.enemy_units)
	mgr._tick_rat_bites(AutoBattleManager.RAT_BITE_CONTACT + 0.01)
	var flavours: Array = []
	for u in [a, b, c]:
		if u.burn_time > 0.0:
			flavours.append(str(u.burn_flavor))
	_check("disease" in flavours, "no target ended up with the Rat's disease (%s)" % str(flavours))
	_check("venom" in flavours, "no target ended up with the Wyvern's venom (%s)" % str(flavours))
	_check("fire" in flavours, "the Hellhound's bite is no longer fire (%s)" % str(flavours))
	# Only disease and venom get a bespoke persistent visual; fire keeps the
	# generic burn it always had.
	mgr._sync_disease_vfx()
	_check(mgr._disease_vfx.size() == 2,
		"expected 2 bespoke DoT visuals (disease + venom), found %d" % mgr._disease_vfx.size())

func _test_wounded_dive() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var w = _mk(mgr, s["grid"], EnemyFactory.create_by_type("sky_wyvern"), Vector2i(2, 2), false)
	mgr.enemy_units = [w]; mgr.player_units = []
	mgr._tick_passive(w, mgr.player_units, mgr.enemy_units, 0.1)
	_check(mgr._wounded_dive_vfx.is_empty(), "a full-HP Wyvern already shows Wounded Dive")
	w.current_hp = int(w.max_hp * 0.25)
	mgr._tick_passive(w, mgr.player_units, mgr.enemy_units, 0.1)
	_check(absf(float(w.get_meta("mob_aspd_bonus", 0.0)) - 0.30) < 0.001,
		"Wounded Dive is %.3f at low HP, description caps at +30 percent"
			% float(w.get_meta("mob_aspd_bonus", 0.0)))
	_check(mgr._wounded_dive_vfx.size() == 1, "a wounded Wyvern has no readout")
	# Its own readout, not the Bear's or the Minotaur's.
	_check(mgr._fury_vfx.is_empty(), "the Wyvern borrowed the Bear's Fury readout")
	_check(mgr._savage_vfx.is_empty(), "the Wyvern borrowed the Minotaur's Savage Charge readout")
