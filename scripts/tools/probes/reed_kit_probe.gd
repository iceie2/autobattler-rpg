extends Node
# Isolated Reed kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/reed_kit_probe.tscn
#
# Second hero probe (see vail_kit_probe.gd for the two gotchas: heroes need one
# frame before UnitFactory.create_unit works, and the original seven classes
# have no row in CLASS_BASE_STATS). Asserts against the AbilityFormulas
# registry, never literals.

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

func _reed():
	return UnitFactory.create_unit(UnitBase.UnitClass.REED, UnitBase.Element.WATER, true)

func _ally(elem := UnitBase.Element.NORMAL):
	return UnitFactory.create_unit(UnitBase.UnitClass.RUSH, elem, true)

func _ready() -> void:
	await get_tree().process_frame
	_test_identity()
	_test_every_debuff_is_cleansable()
	_test_cleanse_strips_all_and_heals()
	_test_cleanse_spares_buffs()
	_test_wellspring_radius_comes_from_registry()
	_test_wellspring_fade_matches_cleanse_set()
	_test_confluence_scales_with_water_allies()
	if _fail.is_empty():
		print("REED_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("REED_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_identity() -> void:
	var r = _reed(); add_child(r)
	_check(r.current_element == UnitBase.Element.WATER,
		"Reed is not WATER — Confluence's per-Water scaling and his VFX assume it")
	_check(r.attack_range >= 4, "Reed's range dropped to %d" % r.attack_range)
	_check(r.ultimate_damage_mult == 0.0,
		"Confluence gained a damage multiplier — it is a pure heal")

# THE guard on the growing debuff set. The roster gains negative effects per
# element, and the whole point of UnitBase.DEBUFF_TIMERS is that a new one is
# added in ONE place. If someone adds a timer to the list but forgets its
# companion field, or adds a debuff and never lists it, this fails.
func _test_every_debuff_is_cleansable() -> void:
	var v = _ally(); add_child(v)
	for t in UnitBase.DEBUFF_TIMERS:
		v.set(t, 5.0)
	v.burn_dps = 9.0; v.bleed_dps = 9.0; v.slow_pct = 0.5
	v.weakened_pct = 0.5; v.spore_stacks = 7.0
	v.clear_debuffs()
	for t in UnitBase.DEBUFF_TIMERS:
		_check(float(v.get(t)) == 0.0, "clear_debuffs left %s at %.2f" % [t, v.get(t)])
	_check(v.burn_dps == 0.0 and v.bleed_dps == 0.0, "a DOT's dps survived the cleanse")
	_check(v.slow_pct == 0.0, "slow_pct survived; the timer can be re-armed with it still set")
	_check(v.weakened_pct == 0.0, "weakened_pct survived the cleanse")
	_check(v.spore_stacks == 0.0, "spore stacks survived the cleanse")

func _test_cleanse_strips_all_and_heals() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var r = _mk(mgr, s["grid"], _reed(), Vector2i(2, 2), true)
	var hurt = _mk(mgr, s["grid"], _ally(), Vector2i(3, 2), true)
	hurt.current_hp = int(hurt.max_hp * 0.3)
	# The debuff the old inline list missed, and the one a cleanse most implies.
	hurt.stun_time = 4.0
	hurt.burn_time = 4.0
	hurt.puppet_time = 4.0
	mgr.player_units = [r, hurt]; mgr.enemy_units = []
	var hp0: int = hurt.current_hp
	mgr._reed_cleanse(r, mgr.player_units)
	_check(hurt.stun_time == 0.0, "Cleanse did not remove STUN, but promises all debuffs")
	_check(hurt.burn_time == 0.0, "Cleanse did not remove burn")
	_check(hurt.puppet_time == 0.0, "Cleanse did not free a puppeted ally")
	var want: int = int(AbilityFormulas.value_of(r, AbilityFormulas.ACTIVE, "heal"))
	_check(hurt.current_hp - hp0 == want,
		"Cleanse healed %d, registry says %d" % [hurt.current_hp - hp0, want])

# A cleanse that strips Pastor's damage buff would be a trap, not a support.
func _test_cleanse_spares_buffs() -> void:
	var v = _ally(); add_child(v)
	v.outgoing_dmg_mult = 1.4; v.outgoing_dmg_time = 3.0
	v.bonus_aspd_pct = 0.2; v.bonus_aspd_time = 3.0
	v.untargetable_time = 2.0
	v.clear_debuffs()
	_check(is_equal_approx(v.outgoing_dmg_mult, 1.4),
		"cleanse stripped Pastor's damage BUFF (mult now %.2f)" % v.outgoing_dmg_mult)
	_check(v.bonus_aspd_pct > 0.0, "cleanse stripped a haste buff")
	_check(v.untargetable_time > 0.0, "cleanse stripped untargetable, which is protective")
	# ...but a damage PENALTY is a debuff and must go.
	v.outgoing_dmg_mult = 0.6; v.outgoing_dmg_time = 3.0
	v.clear_debuffs()
	_check(is_equal_approx(v.outgoing_dmg_mult, 1.0),
		"cleanse left a damage PENALTY of %.2f in place" % v.outgoing_dmg_mult)

func _test_wellspring_radius_comes_from_registry() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var r = _mk(mgr, s["grid"], _reed(), Vector2i(2, 2), true)
	var rad: float = AbilityFormulas.value_of(r, AbilityFormulas.PASSIVE, "radius")
	_check(rad > 0.0, "Wellspring has no radius term in the registry")
	var near = _mk(mgr, s["grid"], _ally(), Vector2i(3, 2), true)
	var far = _mk(mgr, s["grid"], _ally(), Vector2i(8, 8), true)
	near.current_hp = 10; far.current_hp = 10
	near.hp_regen_accum = 0.0; far.hp_regen_accum = 0.0
	mgr.player_units = [r, near, far]; mgr.enemy_units = []
	r.set_meta("aura_tick_t", 0.0)
	mgr._tick_passive(r, mgr.enemy_units, mgr.player_units, 0.016)
	_check(near.hp_regen_accum > 0.0, "ally inside the radius got no Wellspring regen")
	_check(far.hp_regen_accum == 0.0,
		"ally at 8 tiles got regen; registry radius is %.1f" % rad)

func _test_wellspring_fade_matches_cleanse_set() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var r = _mk(mgr, s["grid"], _reed(), Vector2i(2, 2), true)
	var near = _mk(mgr, s["grid"], _ally(), Vector2i(3, 2), true)
	near.current_hp = 10
	# stun was NOT faded by the old inline version.
	near.stun_time = 5.0; near.slow_time = 5.0
	mgr.player_units = [r, near]; mgr.enemy_units = []
	r.set_meta("aura_tick_t", 0.0)
	mgr._tick_passive(r, mgr.enemy_units, mgr.player_units, 0.016)
	_check(near.slow_time < 5.0, "Wellspring did not fade slow")
	_check(near.stun_time < 5.0,
		"Wellspring faded slow but not STUN — the passive and the active disagree "
		+ "about what a debuff is")

func _test_confluence_scales_with_water_allies() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var r = _mk(mgr, s["grid"], _reed(), Vector2i(2, 2), true)
	var w1 = _mk(mgr, s["grid"], _ally(UnitBase.Element.WATER), Vector2i(3, 2), true)
	var n1 = _mk(mgr, s["grid"], _ally(UnitBase.Element.FIRE), Vector2i(4, 2), true)
	for u in [r, w1, n1]:
		u.current_hp = 1
	mgr.player_units = [r, w1, n1]; mgr.enemy_units = []
	mgr._reed_confluence(r, mgr.player_units)
	var base: float = AbilityFormulas.value_of(r, AbilityFormulas.ULTIMATE, "heal")
	var per: float = AbilityFormulas.value_of(r, AbilityFormulas.ULTIMATE, "per_water")
	# Reed is WATER himself, so two Water units are on the field here.
	var mult: float = 1.0 + 2.0 * per
	var want: int = int(float(n1.max_hp) * base * mult)
	_check(n1.current_hp - 1 == want,
		"Confluence healed the non-Water ally %d, expected %d (x%.2f for 2 Water)"
			% [n1.current_hp - 1, want, mult])
	_check(w1.current_hp > 1, "Confluence skipped a Water ally entirely")
