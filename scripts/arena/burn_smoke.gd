extends Node
# ══════════════════════════════════════════════════════════════════════════════
# BURN ARCHETYPE SMOKE (VD-16, BUILD_ARCHETYPES.md) — drives the REAL
# AutoBattleManager burn functions on real units, deterministically.
#
# Asserts:
#   1. classic rule untouched without relics (strongest burn wins, longer time,
#      last applier credited) — the "no Burn relics = today's game" promise
#   2. Kindling scales burns a player hero LIGHTS, never copies or enemy burns
#   3. Kindred Flames: one part per hero type, others add their share, 2x cap
#   4. loop rule 2: ten real Sear Conflagrations never grow the burn
#   5. parts expire one by one and the total follows
#   6. Ashfall moves each part at its share, onto the nearest living enemy,
#      without re-applying Kindling
#   7. Tinder Heart is a flat multiplier on ult charge, only while flagged
#   8. Inferno Crown deals burn x seconds and adds no burn
#   9. relic offers: pieces never in a generic draw, one seed on the wave-1
#      screen, one reserved piece later (never an owned piece), all 25 resolve
#  10. RelicInventory writes each piece's field
#
# Run:  godot --headless res://scenes/burn_smoke.tscn
# Exit code 0 = pass, 1 = fail. Touches no save file.
# ══════════════════════════════════════════════════════════════════════════════

var _fails: Array = []
var mgr: AutoBattleManager

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		_fails.append(label)
		print("  FAIL: %s" % label)

func _near(got: float, want: float, label: String) -> void:
	_check(absf(got - want) < 0.01, "%s (got %.2f, want %.2f)" % [label, got, want])

func _ready() -> void:
	mgr = AutoBattleManager.new()
	add_child(mgr)
	mgr.skill_effect_container = Node2D.new()
	add_child(mgr.skill_effect_container)

	_test_classic_rule()
	_test_kindling()
	_test_kindred()
	_test_sear_no_ratchet()
	_test_part_decay()
	_test_ashfall()
	_test_tinder()
	_test_inferno()
	_test_offers()
	_test_inventory_fields()

	print("BURN_SMOKE: %s" % ("ALL PASS" if _fails.is_empty()
		else "%d FAILED -> %s" % [_fails.size(), ", ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)

# ── helpers ──────────────────────────────────────────────────────────────────
func _hero(cls: int) -> UnitBase:
	var u: UnitBase = UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
	add_child(u)
	return u

func _foe() -> UnitBase:
	var u: UnitBase = EnemyFactory.create_by_type("goblin")
	add_child(u)
	u.max_hp = 100000
	u.current_hp = 100000
	return u

func _reset_mgr() -> void:
	mgr._kindling_mult = 1.0
	mgr._ashfall_frac = 0.0
	mgr._flare_secs = 0.0
	mgr._flare_timer = 0.0

func _give(u: UnitBase, share: float) -> void:
	u.relic_burn_stack_share = share

# ── 1 ────────────────────────────────────────────────────────────────────────
func _test_classic_rule() -> void:
	print("classic rule (no relics):")
	_reset_mgr()
	var coal := _hero(UnitBase.UnitClass.COAL)
	var ember := _hero(UnitBase.UnitClass.EMBER)
	var e := _foe()
	mgr.apply_burn(e, 10.0, 3.0, coal)
	mgr.apply_burn(e, 6.0, 5.0, ember)
	_near(e.burn_dps, 10.0, "strongest burn wins, no sum")
	_near(e.burn_time, 5.0, "longer duration wins")
	_check(e.burn_source == ember, "last applier is credited (unchanged quirk)")
	_check(e.burn_parts.is_empty(), "no parts without Kindred Flames")
	_near(e.burn_strongest_single(), 10.0, "strongest single == burn_dps")

# ── 2 ────────────────────────────────────────────────────────────────────────
func _test_kindling() -> void:
	print("Kindling:")
	_reset_mgr()
	mgr._kindling_mult = 1.3
	var coal := _hero(UnitBase.UnitClass.COAL)
	var e1 := _foe()
	var e2 := _foe()
	mgr.apply_burn(e1, 10.0, 3.0, coal)
	_near(e1.burn_dps, 13.0, "a burn a hero lights is scaled")
	mgr._set_burn(e2, 10.0, 3.0, coal)
	_near(e2.burn_dps, 10.0, "a copy (_set_burn) is not re-scaled")
	var goblin := _foe()
	var hero_target := _hero(UnitBase.UnitClass.SEAR)
	mgr.apply_burn(hero_target, 10.0, 3.0, goblin)
	_near(hero_target.burn_dps, 10.0, "an enemy's burn is not scaled")
	var team := [coal, _hero(UnitBase.UnitClass.COAL), _hero(UnitBase.UnitClass.EMBER),
		_hero(UnitBase.UnitClass.SHAUNA)]
	_check(HeroVerbs.count_types(team, HeroVerbs.BURN) == 2,
		"two Coals count once; Shauna is Fire but not a burner")

# ── 3 ────────────────────────────────────────────────────────────────────────
func _test_kindred() -> void:
	print("Kindred Flames:")
	_reset_mgr()
	var coal := _hero(UnitBase.UnitClass.COAL)
	var ember := _hero(UnitBase.UnitClass.EMBER)
	var sear := _hero(UnitBase.UnitClass.SEAR)
	for u in [coal, ember, sear]:
		_give(u, 0.5)
	var e := _foe()
	mgr.apply_burn(e, 10.0, 4.0, coal)
	mgr.apply_burn(e, 8.0, 4.0, ember)
	_near(e.burn_dps, 14.0, "strongest in full + half of the other")
	_near(e.burn_strongest_single(), 10.0, "strongest single stays the biggest part")
	mgr.apply_burn(e, 6.0, 4.0, sear)
	_near(e.burn_dps, 17.0, "a third hero adds half of its own")
	var coal2 := _hero(UnitBase.UnitClass.COAL)
	_give(coal2, 0.5)
	mgr.apply_burn(e, 9.0, 4.0, coal2)
	_near(e.burn_dps, 17.0, "a second Coal shares Coal's part")
	for u in [coal, ember, sear]:
		_give(u, 1.0)
	var e2 := _foe()
	mgr.apply_burn(e2, 10.0, 4.0, coal)
	mgr.apply_burn(e2, 9.0, 4.0, ember)
	mgr.apply_burn(e2, 9.0, 4.0, sear)
	_near(e2.burn_dps, 20.0, "total capped at 2x the strongest single")

# ── 4 ────────────────────────────────────────────────────────────────────────
func _test_sear_no_ratchet() -> void:
	print("loop rule 2 - Sear's spread never ratchets:")
	_reset_mgr()
	mgr._kindling_mult = 1.45   # worst case: a Kindling that could re-apply
	var coal := _hero(UnitBase.UnitClass.COAL)
	var ember := _hero(UnitBase.UnitClass.EMBER)
	var sear := _hero(UnitBase.UnitClass.SEAR)
	for u in [coal, ember, sear]:
		_give(u, 0.5)
	var a := _foe()
	var b := _foe()
	mgr.enemy_units = [a, b]
	mgr.apply_burn(a, 10.0, 60.0, coal)
	mgr.apply_burn(a, 8.0, 60.0, ember)
	mgr._sear_conflagration(sear, [a, b])
	var after_one := [a.burn_dps, b.burn_dps]
	for i in range(9):
		mgr._sear_conflagration(sear, [a, b])
	_near(a.burn_dps, after_one[0], "enemy A's total after 10 casts == after 1")
	_near(b.burn_dps, after_one[1], "enemy B's total after 10 casts == after 1")
	_check(a.burn_dps <= 2.0 * a.burn_strongest_single() + 0.001, "A under the 2x cap")
	mgr.enemy_units = []

# ── 5 ────────────────────────────────────────────────────────────────────────
func _test_part_decay() -> void:
	print("parts expire one by one:")
	_reset_mgr()
	var coal := _hero(UnitBase.UnitClass.COAL)
	var ember := _hero(UnitBase.UnitClass.EMBER)
	_give(coal, 0.5)
	_give(ember, 0.5)
	var e := _foe()
	mgr.apply_burn(e, 10.0, 2.0, coal)
	mgr.apply_burn(e, 8.0, 5.0, ember)
	for i in range(30):
		mgr._tick_statuses(e, 0.1)   # 3 s
	_check(not e.burn_parts.has(UnitBase.UnitClass.COAL), "Coal's 2 s part is gone")
	_near(e.burn_dps, 8.0, "total falls to Ember's part alone")
	for i in range(30):
		mgr._tick_statuses(e, 0.1)
	_check(e.burn_time <= 0.0 and e.burn_parts.is_empty() and e.burn_dps == 0.0,
		"everything clears when the last part ends")

# ── 6 ────────────────────────────────────────────────────────────────────────
func _test_ashfall() -> void:
	print("Ashfall:")
	_reset_mgr()
	mgr._ashfall_frac = 0.65
	mgr._kindling_mult = 1.5
	mgr.battle_active = true
	var coal := _hero(UnitBase.UnitClass.COAL)
	var ember := _hero(UnitBase.UnitClass.EMBER)
	_give(coal, 0.5)
	_give(ember, 0.5)
	var dying := _foe()
	var near := _foe()
	var far := _foe()
	dying.grid_position = Vector2i(5, 2)
	near.grid_position = Vector2i(6, 2)
	far.grid_position = Vector2i(0, 0)
	mgr.enemy_units = [dying, near, far]
	mgr._set_burn(dying, 10.0, 4.0, coal)
	mgr._set_burn(dying, 8.0, 4.0, ember)
	mgr.burn_ashfall(dying)
	_near(float(near.burn_parts.get(UnitBase.UnitClass.COAL, [0.0])[0]), 6.5,
		"Coal's part jumps at 65%, no second Kindling")
	_near(float(near.burn_parts.get(UnitBase.UnitClass.EMBER, [0.0])[0]), 5.2,
		"Ember's part jumps separately")
	_check(far.burn_time <= 0.0, "only the NEAREST enemy catches it")
	mgr._ashfall_frac = 0.0
	var other := _foe()
	other.grid_position = Vector2i(5, 3)
	mgr.enemy_units = [dying, other]
	mgr.burn_ashfall(dying)
	_check(other.burn_time <= 0.0, "no Ashfall owned -> nothing jumps")
	mgr.enemy_units = []
	mgr.battle_active = false

# ── 7 ────────────────────────────────────────────────────────────────────────
func _test_tinder() -> void:
	print("Tinder Heart:")
	var sear := _hero(UnitBase.UnitClass.SEAR)
	sear.relic_burn_ult_haste = 0.25
	sear.ultimate_charge = 0
	sear.burn_haste_active = false
	sear._charge_ultimate(100)
	_check(sear.ultimate_charge == 100, "no bonus while no foe burns (%d)" % sear.ultimate_charge)
	sear.ultimate_charge = 0
	sear.burn_haste_active = true
	sear._charge_ultimate(100)
	_check(sear.ultimate_charge == 125, "+25%% while flagged (%d)" % sear.ultimate_charge)
	_reset_mgr()
	var shauna := _hero(UnitBase.UnitClass.SHAUNA)
	shauna.relic_burn_ult_haste = 0.25
	var e := _foe()
	mgr.player_units = [sear, shauna]
	mgr.enemy_units = [e]
	mgr._set_burn(e, 5.0, 3.0, sear)
	mgr._tick_burn_pieces(0.1)
	_check(sear.burn_haste_active and not shauna.burn_haste_active,
		"the flag lands on Burn heroes only")
	mgr.player_units = []
	mgr.enemy_units = []

# ── 8 ────────────────────────────────────────────────────────────────────────
func _test_inferno() -> void:
	print("Inferno Crown:")
	_reset_mgr()
	mgr._flare_secs = 2.0
	var ember := _hero(UnitBase.UnitClass.EMBER)
	var e := _foe()
	mgr.enemy_units = [e]
	mgr._set_burn(e, 10.0, 30.0, ember)
	var hp := e.current_hp
	mgr._tick_burn_pieces(7.9)
	_check(e.current_hp == hp, "nothing before 8 s")
	mgr._tick_burn_pieces(0.2)
	_check(hp - e.current_hp == 20, "flare deals burn x 2 s (%d)" % (hp - e.current_hp))
	_near(e.burn_dps, 10.0, "and adds no burn")
	mgr.enemy_units = []

# ── 9 ────────────────────────────────────────────────────────────────────────
func _test_offers() -> void:
	print("relic offers:")
	var leaked := 0
	for i in range(300):
		for r in Relic.roll_offers([1, 11, 21, 41][i % 4], []):
			if r.get("category", "") == "archetype":
				leaked += 1
	_check(leaked == 0, "no piece in 300 generic screens (%d leaked)" % leaked)
	var seeds_ok := true
	for i in range(50):
		var offers: Array = Relic.roll_offers(1, [], 3, {"seed_verbs": ["burn"]})
		var n_seed := offers.filter(func(r): return r.get("piece", "") == "kindling").size()
		var n_arch := offers.filter(func(r): return r.get("category", "") == "archetype").size()
		seeds_ok = seeds_ok and offers.size() == 3 and n_seed == 1 and n_arch == 1
	_check(seeds_ok, "wave 1 with a buildable Burn: 3 cards, exactly one Kindling")
	var reserved_ok := true
	for i in range(80):
		var offers: Array = Relic.roll_offers(11, ["c_kindling"], 3, {"team_verbs": ["burn"]})
		var arch := offers.filter(func(r): return r.get("category", "") == "archetype")
		reserved_ok = reserved_ok and offers.size() == 3 and arch.size() == 1 \
			and arch[0]["piece"] != "kindling"
	_check(reserved_ok, "later screen: one reserved piece, never an owned one")
	var all_owned := ["c_kindling", "c_kindred", "c_ashfall", "c_tinder", "c_inferno"]
	var full: Array = Relic.roll_offers(11, all_owned, 3, {"team_verbs": ["burn"]})
	_check(full.size() == 3 and full.all(func(r): return r.get("category", "") != "archetype"),
		"every piece owned -> the reserved card falls back to a generic relic")
	var ok_desc := true
	for r in Relic.archetype_relics():
		ok_desc = ok_desc and not Relic.by_id(r["id"]).is_empty() and not "{" in String(r["desc"])
	# 25 Burn relics (5 pieces x 5 grades); VD-22's element pieces are checked
	# in element_pieces_smoke.
	var burn_n: int = Relic.archetype_relics().filter(func(r): return r["verb"] == "burn").size()
	_check(burn_n == 25 and ok_desc,
		"25 Burn pieces, every piece resolves by id, no unfilled {placeholders}")
	print("    e.g. %s: %s" % [Relic.by_id("c_kindling")["name"], Relic.by_id("c_kindling")["desc"]])

# ── 10 ───────────────────────────────────────────────────────────────────────
func _test_inventory_fields() -> void:
	print("RelicInventory fields:")
	var inv := RelicInventory.new()
	for rid in ["b_kindling", "c_kindred", "a_ashfall", "d_tinder", "s_inferno"]:
		inv.add_relic(Relic.by_id(rid))
	var u := _hero(UnitBase.UnitClass.EMBER)
	inv.apply_all_to_unit(u)
	_near(u.relic_burn_per_burner, 0.20, "Kindling B")
	_near(u.relic_burn_stack_share, 0.50, "Kindred Flames C")
	_near(u.relic_burn_leap, 0.90, "Ashfall A")
	_near(u.relic_burn_ult_haste, 0.18, "Tinder Heart D")
	_near(u.relic_burn_flare_secs, 4.4, "Inferno Crown S")
	_check(inv.seed_verbs() == ["burn"], "the Kindling seed favours Burn heroes in the shop")
	_test_shop_weighting()

# ── 11 ───────────────────────────────────────────────────────────────────────
func _test_shop_weighting() -> void:
	print("hero shop weighting:")
	var shop := HeroShop.new()   # never added to the tree: only the draw is exercised
	var classes: Array = UnitFactory.get_all_classes()
	var burners := func(n_draws: int) -> float:
		var hits := 0
		for i in range(n_draws):
			if HeroVerbs.has_verb(shop._pick_class(classes), HeroVerbs.BURN):
				hits += 1
		return float(hits) / n_draws
	seed(99)
	var plain: float = burners.call(6000)
	shop.favored_verbs = ["burn"]
	var seeded: float = burners.call(6000)
	# 3 of 26 heroes burn: uniform ~11.5%; at SEED_WEIGHT 3 -> 9/32 ~28%.
	_check(absf(plain - 3.0 / 26.0) < 0.02, "no seed: uniform (%.1f%% burners)" % (plain * 100.0))
	_check(absf(seeded - 9.0 / 32.0) < 0.025, "Kindling owned: ~28%% burners (%.1f%%)" % (seeded * 100.0))
	shop.free()
