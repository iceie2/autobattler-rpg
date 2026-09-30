extends Node
# ══════════════════════════════════════════════════════════════════════════════
# ELEMENT PIECES SMOKE (VD-22, ARCHETYPE_PIECES.md) — drives the REAL
# ElementPieces hooks on real units through UnitBase.take_damage / heal /
# speed_modifier / _charge_ultimate and AutoBattleManager.apply_stun.
#
# Asserts, per element: the seed's damage type, each piece's effect, that the
# effect needs the element (non-element heroes don't trigger it), and that a
# team owning no pieces fights exactly as before. Plus the relic side: all 20
# pieces resolve at every grade, RelicInventory writes each one, the first
# screen offers at most 3 distinct seeds, a later screen reserves a piece for
# an element on the team, and HeroVerbs counts element heroes.
#
# Run:  godot --headless res://scenes/element_pieces_smoke.tscn
# Exit code 0 = pass, 1 = fail. Touches no save file.
# ══════════════════════════════════════════════════════════════════════════════

var _fails: Array = []
var mgr: AutoBattleManager
var ep: ElementPieces
var _inv := RelicInventory.new()

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		_fails.append(label)
		print("  FAIL: %s" % label)

func _near(got: float, want: float, tol: float, label: String) -> void:
	_check(absf(got - want) <= tol, "%s (got %.3f, want %.3f)" % [label, got, want])

func _ready() -> void:
	mgr = AutoBattleManager.new()
	add_child(mgr)
	mgr.skill_effect_container = Node2D.new()
	add_child(mgr.skill_effect_container)
	ep = mgr.element_pieces

	_test_inert()
	_test_earth()
	_test_lightning()
	_test_water()
	_test_air()
	_test_tank()
	_test_mage()
	_test_fighter()
	_test_ranged()
	_test_healer()
	_test_relics()

	print("ELEMENT_PIECES_SMOKE: %s" % ("ALL PASS" if _fails.is_empty()
		else "%d FAILED -> %s" % [_fails.size(), ", ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)

# ── helpers ──────────────────────────────────────────────────────────────────
func _hero(cls: int, pos := Vector2i(0, 6)) -> UnitBase:
	var u: UnitBase = UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
	add_child(u)
	u.battle_manager = mgr
	u.grid_position = pos
	return u

func _foe(pos: Vector2i, armor := 100) -> UnitBase:
	var u: UnitBase = EnemyFactory.create_by_type("goblin")
	add_child(u)
	u.battle_manager = mgr
	u.is_player_unit = false
	u.max_hp = 1000000
	u.current_hp = 1000000
	u.resistance = armor
	u.magic_resist = armor
	u.tenacity = 0
	u.grid_position = pos
	return u

func _give(units: Array, relic_id: String) -> void:
	var relic := Relic.by_id(relic_id)
	_check(not relic.is_empty(), "relic %s exists" % relic_id)
	_inv.apply_relic_to_units(_inv.add_relic(relic), units)

# Start a "battle": the manager's lists and ElementPieces.setup, as start_battle.
func _begin(players: Array, enemies: Array) -> void:
	mgr.player_units = players
	mgr.enemy_units = enemies
	ep.setup(mgr, players, enemies)

func _hit(target: UnitBase, attacker: UnitBase, amount := 1000) -> int:
	var before := target.current_hp
	target.take_damage(amount, attacker.current_element, attacker)
	return before - target.current_hp

func _tick(secs: float) -> void:
	var t := 0.0
	while t < secs - 0.0001:
		ep.tick(0.1)
		t += 0.1

# ── inert ────────────────────────────────────────────────────────────────────
func _test_inert() -> void:
	print("no pieces:")
	var bh := _hero(UnitBase.UnitClass.BLOODHOUND)
	var foe := _foe(Vector2i(0, 0))
	_begin([bh], [foe])
	_check(not ep.active, "no pieces owned -> inactive")
	var a := _hit(foe, bh)
	var b := _hit(foe, bh)
	_check(a == b and foe.earth_stacks == 0, "hits unchanged, no stacks (%d, %d)" % [a, b])

# ── Earth ────────────────────────────────────────────────────────────────────
func _test_earth() -> void:
	print("earth:")
	var bh := _hero(UnitBase.UnitClass.BLOODHOUND)
	var june := _hero(UnitBase.UnitClass.JUNE)
	var lord := _hero(UnitBase.UnitClass.LORDEE)   # Normal element
	var team := [bh, june, lord]
	_give(team, "b_faultline")   # 2% per stack per Earth hero
	var foe := _foe(Vector2i(0, 0))
	var near := _foe(Vector2i(1, 0))
	var far := _foe(Vector2i(6, 0))
	_begin(team, [foe, near, far])
	_check(ep.counts[HeroVerbs.EARTH] == 2, "2 Earth hero types counted")
	_near(ep.earth_per_stack(), 0.04, 0.0001, "per stack = 2% x 2 Earth heroes")
	var first := _hit(foe, bh)
	_check(foe.earth_stacks == 1, "an Earth hit adds a stack")
	_hit(foe, lord)
	_check(foe.earth_stacks == 1, "a Normal hero's hit adds none")
	for _i in range(12):
		_hit(foe, bh)
	_check(foe.earth_stacks == 10, "stacks cap at 10")
	_near(ep.shred_for(foe, bh), 0.40, 0.0001, "Earth hits see 40% shred")
	_near(ep.shred_for(foe, lord), 0.0, 0.0001, "other heroes see none without Rubble")
	var shredded := _hit(foe, bh)
	# 100 armor -> 60: damage x (160/200)... ratio = (100/160)/(100/200) = 1.25
	_near(float(shredded) / float(first), 1.25, 0.02, "40% shred on 100 armor = 1.25x damage")
	_tick(4.1)
	_check(foe.earth_stacks == 0, "stacks fade 4 s after the last Earth hit")

	_give(team, "c_rubble")      # one stack per 0.8 s, shred for everyone
	_begin(team, [foe, near, far])
	for _i in range(10):
		_hit(foe, bh)
	_near(ep.shred_for(foe, lord), 0.40, 0.0001, "Rubble: other heroes' hits see the shred")
	_tick(4.0 + 0.8 * 3 + 0.05)
	_check(foe.earth_stacks == 7, "Rubble: stacks fade one at a time (got %d)" % foe.earth_stacks)

	_give(team, "a_landslide")   # +19% from Earth heroes at 10 stacks
	_begin(team, [foe, near, far])
	for _i in range(10):
		_hit(foe, bh)
	_near(ep.damage_mult(foe, bh), 1.19, 0.0001, "Landslide: +19% for Earth heroes at 10 stacks")
	_near(ep.damage_mult(foe, lord), 1.0, 0.0001, "Landslide: nothing for other heroes")

	_give(team, "b_aftershock")  # half the stacks jump
	_begin(team, [foe, near, far])
	for _i in range(10):
		_hit(foe, bh)
	foe.current_hp = 1
	_hit(foe, bh)
	_check(near.earth_stacks == 5 and far.earth_stacks == 0,
		"Aftershock: 5 of 10 stacks jump to the NEAREST enemy (near %d, far %d)" % [near.earth_stacks, far.earth_stacks])

	_give(team, "b_tectonic")    # 20% of the deepest shred, permanent
	var t1 := _foe(Vector2i(0, 1))
	var t2 := _foe(Vector2i(3, 1))
	_begin(team, [t1, t2])
	# Rubble is owned, so stacks fade from 4 s on; re-hit just before the pulse
	# so the deepest shred at 10 s is the full 40%.
	_tick(9.9)
	for _i in range(10):
		_hit(t1, bh)
	_tick(0.2)
	_near(t2.earth_perm, 0.08, 0.0001, "Tectonic: every enemy keeps 20% of the 40% deepest shred")
	_near(ep.shred_for(t2, lord), 0.08, 0.0001, "permanent shred counts for every hit")

# ── Lightning ────────────────────────────────────────────────────────────────
func _test_lightning() -> void:
	print("lightning:")
	var static_h := _hero(UnitBase.UnitClass.STATIC)
	var riot := _hero(UnitBase.UnitClass.RIOT)
	var lord := _hero(UnitBase.UnitClass.LORDEE)
	var team := [static_h, riot, lord]
	_give(team, "b_staticcharge")   # +10% per Lightning hero
	var foe := _foe(Vector2i(0, 0))
	var near := _foe(Vector2i(1, 0))
	_begin(team, [foe, near])
	mgr.apply_stun(foe, 1.0, static_h)
	_near(foe.stun_time, 1.2, 0.001, "Static Charge: a Lightning hero's 1 s stun lasts 1.2 s")
	foe.stun_time = 0.0
	mgr.apply_stun(foe, 1.0, lord)
	_near(foe.stun_time, 1.0, 0.001, "a Normal hero's stun is not lengthened")
	foe.stun_time = 0.0
	mgr.apply_stun(foe, 1.0)
	_near(foe.stun_time, 1.0, 0.001, "a sourceless stun is not lengthened")

	_give(team, "b_conductive")
	_begin(team, [foe, near])
	foe.stun_time = 0.0
	var plain := _hit(foe, lord)
	foe.stun_time = 2.0
	var stunned := _hit(foe, lord)
	_near(float(stunned) / float(plain), 1.15, 0.02, "Conductive: stunned enemies take +15%")

	_give(team, "b_arc")
	_begin(team, [foe, near])
	near.stun_time = 0.0
	foe.stun_time = 2.0
	foe.current_hp = 1
	_hit(foe, lord)
	_near(near.stun_time, 1.0, 0.001, "Arc: a stunned enemy's death stuns the nearest for 1 s")

	_give(team, "b_overcharge")
	var f2 := _foe(Vector2i(0, 2))
	_begin(team, [f2])
	f2.stun_time = 3.0
	_tick(0.1)
	_near(static_h.stun_haste, 0.25, 0.0001, "Overcharge: Lightning heroes charge +25% while a foe is stunned")
	_near(lord.stun_haste, 0.0, 0.0001, "Overcharge: not for other heroes")
	static_h.ultimate_charge = 0
	static_h.ultimate_ready = false
	static_h._charge_ultimate(100)
	_check(static_h.ultimate_charge == 125, "Overcharge applies in _charge_ultimate (got %d)" % static_h.ultimate_charge)
	f2.stun_time = 0.0
	_tick(0.1)
	_near(static_h.stun_haste, 0.0, 0.0001, "Overcharge ends when nothing is stunned")

	_give(team, "b_thunderhead")    # 1.8x magic power on every 5th hero stun
	var f3 := _foe(Vector2i(0, 3))
	var f4 := _foe(Vector2i(2, 3))
	_begin(team, [f3, f4])
	var hp3 := f3.current_hp
	for _i in range(4):
		mgr.apply_stun(f3, 1.0, static_h)
	_tick(0.1)
	_check(f3.current_hp == hp3, "Thunderhead: nothing on stuns 1-4")
	mgr.apply_stun(f3, 1.0, static_h)
	_tick(0.1)
	_check(f3.current_hp < hp3 and f4.current_hp == 1000000,
		"Thunderhead: the 5th stun strikes stunned enemies only")
	var hp_before := f3.current_hp
	for _i in range(5):
		mgr.apply_stun(f3, 1.0)       # sourceless: Arc / Deluge / hazards
	_tick(0.1)
	_check(f3.current_hp == hp_before, "Thunderhead: sourceless stuns are not counted")

# ── Water ────────────────────────────────────────────────────────────────────
func _test_water() -> void:
	print("water:")
	var nemi := _hero(UnitBase.UnitClass.NEMI, Vector2i(0, 1))
	var reed := _hero(UnitBase.UnitClass.REED, Vector2i(5, 5))
	var static_h := _hero(UnitBase.UnitClass.STATIC)
	var lord := _hero(UnitBase.UnitClass.LORDEE)
	var team := [nemi, reed, static_h, lord]
	_give(team, "b_undertow")   # 8% per stack per Water hero
	var foe := _foe(Vector2i(0, 0))
	_begin(team, [foe])
	_check(ep.counts[HeroVerbs.WATER] == 2, "2 Water hero types counted")
	var speed0 := foe.speed_modifier()
	_hit(foe, lord)
	_check(foe.soak_stacks == 0, "a Normal hero's hit does not Soak")
	_hit(foe, nemi)
	_check(foe.soak_stacks == 1, "a Water hit Soaks")
	_near(foe.speed_modifier() / speed0, 0.84, 0.001, "Soak: 16% slower (8% x 2 Water heroes)")
	_hit(foe, nemi)
	_check(foe.soak_stacks == 1, "without Saturate, Soak does not stack")
	_tick(3.05)
	_check(foe.soak_stacks == 0, "Soak ends after 3 s")

	_give(team, "b_saturate")   # up to 4 stacks
	_begin(team, [foe])
	for _i in range(6):
		_hit(foe, nemi)
	_check(foe.soak_stacks == 4, "Saturate: up to 4 stacks (got %d)" % foe.soak_stacks)
	_near(foe.speed_modifier() / speed0, 0.40, 0.001, "slow caps at 60% (4 x 16% = 64%)")

	_give(team, "b_riptide")
	var dry := _foe(Vector2i(4, 0))
	_begin(team, [foe, dry])
	_hit(foe, nemi)            # Soak it (setup cleared the old Soak)
	var on_dry := _hit(dry, static_h)
	var on_wet := _hit(foe, static_h)
	_near(float(on_wet) / float(on_dry), 1.15, 0.02, "Riptide: Soaked enemies take +15% from Lightning heroes")
	_near(ep.damage_mult(foe, lord), 1.0, 0.0001, "Riptide: not from other heroes")

	_give(team, "b_tidecall")   # +20% healing next to a Soaked enemy
	_begin(team, [foe])
	_hit(foe, nemi)
	nemi.max_hp = 100000
	nemi.current_hp = 1000
	nemi.heal(100, true)
	_check(nemi.current_hp == 1120, "Tidecall: +20% healing next to a Soaked enemy (got %d)" % (nemi.current_hp - 1000))
	reed.max_hp = 100000
	reed.current_hp = 1000
	reed.heal(100, true)
	_check(reed.current_hp == 1100, "Tidecall: normal healing away from it")

	_give(team, "b_deluge")     # freeze Soaked enemies 1 s every 12 s
	var wet := _foe(Vector2i(0, 4))
	var dry2 := _foe(Vector2i(4, 4))
	_begin(team, [wet, dry2])
	_hit(wet, nemi)
	wet.soak_time = 99.0       # keep it Soaked through the wait
	_tick(12.05)
	_check(wet.stun_time > 0.8 and dry2.stun_time == 0.0, "Deluge: Soaked enemies freeze, dry ones don't")

# ── Air ──────────────────────────────────────────────────────────────────────
func _test_air() -> void:
	print("air:")
	var hh := _hero(UnitBase.UnitClass.HEADHUNTER)
	var sable := _hero(UnitBase.UnitClass.SABLE)
	var lord := _hero(UnitBase.UnitClass.LORDEE)
	var team := [hh, sable, lord]
	_give(team, "b_crosswind")  # 8% per Air hero
	var t := _foe(Vector2i(0, 0))
	var second := _foe(Vector2i(1, 0))
	var third := _foe(Vector2i(2, 0))
	_begin(team, [t, second, third])
	_near(ep.val("air_extra_chance") * ep.counts[HeroVerbs.AIR], 0.16, 0.0001, "Crosswind: 8% x 2 Air heroes")
	ep.v["air_extra_chance"] = 1.0   # force the roll for the checks below
	hh.attack_damage = 1000
	ep.on_basic_attack(hh, t)
	_check(second.current_hp < 1000000 and third.current_hp == 1000000,
		"Crosswind: the extra hit lands on the nearest other enemy")
	lord.attack_damage = 1000
	var hp2 := second.current_hp
	ep.on_basic_attack(lord, t)
	_check(second.current_hp == hp2, "Crosswind: not for a Normal hero")

	_give(team, "b_gustchain")
	_begin(team, [t, second, third])
	ep.v["air_extra_chance"] = 1.0
	ep.on_basic_attack(hh, t)
	_check(third.current_hp < 1000000, "Gust Chain: the extra hit carries on to a third enemy")

	_give(team, "b_slipstream")
	_begin(team, [t, second, third])
	ep.v["air_extra_chance"] = 1.0
	var s0 := hh.speed_modifier()
	for _i in range(7):
		ep.on_basic_attack(hh, t)
	_check(hh.air_slip_stacks == 5, "Slipstream: stacks cap at 5 (got %d)" % hh.air_slip_stacks)
	_near(hh.speed_modifier() / s0, 1.20, 0.001, "Slipstream: +4% x 5 attack speed")
	_tick(3.05)
	_check(hh.air_slip_stacks == 0, "Slipstream ends 3 s after the last extra hit")

	var solo := _foe(Vector2i(0, 5))
	var side := _foe(Vector2i(1, 5))
	_begin(team, [solo, side])
	ep.v["air_extra_chance"] = 1.0
	ep.v.erase("air_chain")
	var hp_half := side.current_hp
	ep.on_basic_attack(hh, solo)
	var half_hit := hp_half - side.current_hp
	_give(team, "s_updraft")   # full damage
	_begin(team, [solo, side])
	ep.v["air_extra_chance"] = 1.0
	ep.v.erase("air_chain")
	var hp_full := side.current_hp
	ep.on_basic_attack(hh, solo)
	var full_hit := hp_full - side.current_hp
	_near(float(full_hit) / float(half_hit), 2.0, 0.05, "Updraft S: extra hits deal full damage, not half")

	_give(team, "b_tempest")   # 50% to all in range every 8 s
	var main := _foe(Vector2i(0, 7))
	var in_range := _foe(Vector2i(2, 7))
	var out_range := _foe(Vector2i(30, 7))
	hh.grid_position = Vector2i(0, 9)
	_begin(team, [main, in_range, out_range])
	ep.v.erase("air_extra_chance")
	ep.on_basic_attack(hh, main)
	_check(in_range.current_hp == 1000000, "Tempest: nothing before 8 s")
	_tick(8.05)
	_check(hh.air_tempest_ready and not lord.air_tempest_ready, "Tempest arms Air heroes only")
	ep.on_basic_attack(hh, main)
	_check(in_range.current_hp < 1000000 and out_range.current_hp == 1000000 and not hh.air_tempest_ready,
		"Tempest: the next attack hits enemies in range, once")

# ── Roles (VD-22, 2026-09-30) ────────────────────────────────────────────────
func _placed(cls: int, pos: Vector2i) -> UnitBase:
	var u := _hero(cls, pos)
	u.home_position = pos
	return u

func _test_tank() -> void:
	print("tank:")
	var riot := _placed(UnitBase.UnitClass.RIOT, Vector2i(2, 5))
	var bouncer := _placed(UnitBase.UnitClass.BOUNCER, Vector2i(4, 5))
	var doc := _placed(UnitBase.UnitClass.DOC, Vector2i(2, 8))
	var team := [riot, bouncer, doc]
	var foe := _foe(Vector2i(2, 2))
	_give(team, "b_bulwark")        # 6% per Tank
	_begin(team, [foe])
	_near(ep.damage_mult(riot, foe), 0.88, 0.0001, "Bulwark Oath: 2 Tanks -> Tanks take 12% less")
	_near(ep.damage_mult(doc, foe), 1.0, 0.0001, "Bulwark Oath: not for non-Tanks")
	_give(team, "b_lastwall")       # 12% behind a Tank
	_begin(team, [foe])
	_near(ep.damage_mult(doc, foe), 0.88, 0.0001, "Last Wall: a hero behind a living Tank takes 12% less")
	_give(team, "b_sharedburden")   # 20% moves to the nearest Tank
	_begin(team, [foe])
	var riot_hp := riot.current_hp
	var kept := ep.redirect(doc, 1000, foe)
	_check(kept == 800 and riot_hp - riot.current_hp == 200,
		"Shared Burden: 200 of 1000 moves to the nearest Tank (kept %d, Tank took %d)" % [kept, riot_hp - riot.current_hp])
	_check(ep.redirect(riot, 1000, foe) == 1000, "Shared Burden: Tanks never redirect")
	_give(team, "b_retribution")    # 15% back
	_begin(team, [foe])
	riot.max_hp = 1000000
	riot.current_hp = 1000000
	var r_before := riot.current_hp
	var f_before := foe.current_hp
	riot.take_damage(1000, UnitBase.Element.NORMAL, foe)
	var taken := r_before - riot.current_hp
	_check(f_before - foe.current_hp == int(taken * 0.15),
		"Retribution: the attacker takes 15%% of %d back (got %d)" % [taken, f_before - foe.current_hp])
	_give(team, "b_ironwill")
	_begin(team, [foe])
	_near(ep.taken_charge_mult(riot), 1.30, 0.0001, "Iron Will: Tanks charge +30% from damage taken")
	_near(ep.taken_charge_mult(doc), 1.0, 0.0001, "Iron Will: not for non-Tanks")

func _test_mage() -> void:
	print("mage:")
	var static_h := _placed(UnitBase.UnitClass.STATIC, Vector2i(1, 7))
	var zolt := _placed(UnitBase.UnitClass.ZOLT, Vector2i(3, 7))
	var lord := _placed(UnitBase.UnitClass.LORDEE, Vector2i(5, 5))
	var team := [static_h, zolt, lord]
	var foe := _foe(Vector2i(2, 2))
	_give(team, "b_arcanecircle")   # 10% per Mage
	_begin(team, [foe])
	_near(ep.damage_mult(foe, static_h, true), 1.20, 0.0001, "Arcane Circle: 2 Mages -> +20% magic damage")
	_near(ep.damage_mult(foe, static_h, false), 1.0, 0.0001, "Arcane Circle: physical hits unchanged")
	_give(team, "b_resonance")      # others +10%
	_begin(team, [foe])
	zolt.ultimate_ready = false
	zolt.ultimate_charge = 0
	static_h.ultimate_ready = false
	static_h.ultimate_charge = 0
	ep.on_ult_cast(static_h)
	_check(zolt.ultimate_charge == int(round(zolt.ultimate_charge_max * 0.10)) and static_h.ultimate_charge == 0,
		"Resonance: other Mages +10% ult charge, never the caster")
	_give(team, "b_manatide")       # -25% mana
	_begin(team, [foe])
	_check(ep.skill_cost(static_h) == int(round(static_h.skill_mana_cost * 0.75)) \
		and ep.skill_cost(lord) == lord.skill_mana_cost, "Mana Tide: Mage skills cost 25% less")
	_give(team, "b_twincast")
	_begin(team, [foe])
	ep.v["role_mage_twincast"] = 1.0   # force the roll
	var hp := foe.current_hp
	ep.on_skill_cast(static_h, foe, 400)
	_check(foe.current_hp < hp, "Twincast: the skill's target is hit again")
	_give(team, "b_overload")
	_begin(team, [foe])
	hp = foe.current_hp
	for _i in range(3):
		ep.on_ult_cast(lord)
	_check(foe.current_hp == hp, "Overload: nothing on ults 1-3")
	ep.on_ult_cast(lord)
	_check(foe.current_hp < hp, "Overload: the 4th ult (any hero) blasts every enemy")

func _test_fighter() -> void:
	print("fighter:")
	var lord := _placed(UnitBase.UnitClass.LORDEE, Vector2i(1, 5))
	var rush := _placed(UnitBase.UnitClass.RUSH, Vector2i(3, 5))
	var static_h := _placed(UnitBase.UnitClass.STATIC, Vector2i(2, 7))
	var team := [lord, rush, static_h]
	var foe := _foe(Vector2i(2, 2))
	_give(team, "b_warband")        # 8% per Fighter
	_begin(team, [foe])
	_near(ep.damage_mult(foe, lord, false), 1.16, 0.0001, "Warband: 2 Fighters -> +16% physical damage")
	_near(ep.damage_mult(foe, static_h, false), 1.0, 0.0001, "Warband: not for a Mage")
	_give(team, "b_packhunt")
	_begin(team, [foe])
	ep.on_hit(foe, lord, false, 10)
	_near(ep.damage_mult(foe, lord, false), 1.16, 0.0001, "Pack Hunt: a Fighter's own hit does not mark for itself")
	ep.on_hit(foe, rush, false, 10)
	_near(ep.damage_mult(foe, lord, false), 1.16 * 1.15, 0.0001, "Pack Hunt: +15% after another Fighter's hit")
	_tick(2.1)
	_near(ep.damage_mult(foe, lord, false), 1.16, 0.0001, "Pack Hunt: the mark lasts 2 s")
	_give(team, "b_relentless")     # 3% per hit on the same target
	var foe2 := _foe(Vector2i(4, 2))
	_begin(team, [foe, foe2])
	for _i in range(3):
		ep.on_hit(foe, lord, false, 10)
	_near(ep.damage_mult(foe, lord, false), 1.16 * 1.09, 0.0001, "Relentless: 3 hits -> +9%")
	ep.on_hit(foe2, lord, false, 10)
	_check(lord.relentless_stacks == 1, "Relentless: a new target resets the stacks")
	_give(team, "b_bloodrush")      # +30% attack speed 3 s
	_give(team, "s_onslaught")      # 100% reset
	_begin(team, [foe, foe2])
	var s0 := lord.speed_modifier()
	lord.attack_cooldown = 5.0
	ep.on_enemy_death(foe, lord)
	_near(lord.speed_modifier() / s0, 1.30, 0.001, "Bloodrush: a kill gives +30% attack speed")
	_check(lord.attack_cooldown == 0.0, "Onslaught S: a kill resets the attack timer")
	_tick(3.1)
	_near(lord.speed_modifier() / s0, 1.0, 0.001, "Bloodrush ends after 3 s")

func _test_ranged() -> void:
	print("ranged:")
	var hh := _placed(UnitBase.UnitClass.HEADHUNTER, Vector2i(2, 8))
	var sable := _placed(UnitBase.UnitClass.SABLE, Vector2i(4, 8))
	var ember := _placed(UnitBase.UnitClass.EMBER, Vector2i(6, 8))
	var riot := _placed(UnitBase.UnitClass.RIOT, Vector2i(2, 5))
	var team := [hh, sable, ember, riot]
	var foe := _foe(Vector2i(2, 5 - 3))
	var foe2 := _foe(Vector2i(3, 2))
	var s0 := hh.speed_modifier()
	_give(team, "b_deadeye")        # 8% per Ranged hero
	_begin(team, [foe, foe2])
	_near(hh.speed_modifier() / s0, 1.24, 0.001, "Deadeye: 3 Ranged -> +24% attack speed")
	_near(riot.role_aspd, 0.0, 0.0001, "Deadeye: not for a Tank")
	_give(team, "b_longshot")       # 4% per tile
	_begin(team, [foe, foe2])
	var d: int = mgr._unit_dist(hh, foe)
	_near(ep.damage_mult(foe, hh, false), 1.0 + 0.04 * d, 0.0001, "Longshot: +4%% per tile (%d tiles)" % d)
	_give(team, "b_covered")        # 25% with an ally in front
	_begin(team, [foe, foe2])
	_near(ep.damage_mult(hh, foe), 0.75, 0.0001, "Covered: Riot in front -> 25% less")
	_near(ep.damage_mult(sable, foe), 1.0, 0.0001, "Covered: nobody in front -> no cut")
	_give(team, "b_volley")         # every 5th attack, 75%
	_begin(team, [foe, foe2])
	hh.attack_damage = 1000
	var hp2 := foe2.current_hp
	for _i in range(4):
		ep.on_basic_attack(hh, foe)
	_check(foe2.current_hp == hp2, "Volley: nothing on attacks 1-4")
	ep.on_basic_attack(hh, foe)
	_check(foe2.current_hp < hp2, "Volley: the 5th attack also hits a second enemy")
	_give(team, "b_killingfield")   # +25% for 4 s
	_begin(team, [foe, foe2])
	ep.on_hit(foe, hh, false, 10)
	ep.on_hit(foe, sable, false, 10)
	_check(foe.field_time <= 0.0, "Killing Field: 2 Ranged heroes are not enough")
	ep.on_hit(foe, ember, false, 10)
	_near(ep.damage_mult(foe, riot, false), 1.25, 0.0001, "Killing Field: 3 Ranged heroes -> +25% from anyone")
	_tick(4.1)
	_near(ep.damage_mult(foe, riot, false), 1.0, 0.0001, "Killing Field ends after 4 s")

func _test_healer() -> void:
	print("healer:")
	var doc := _placed(UnitBase.UnitClass.DOC, Vector2i(2, 8))
	var reed := _placed(UnitBase.UnitClass.REED, Vector2i(4, 8))
	var riot := _placed(UnitBase.UnitClass.RIOT, Vector2i(2, 5))
	var team := [doc, reed, riot]
	var foe := _foe(Vector2i(2, 3))
	_give(team, "b_mendingcircle")  # 10% per Healer
	_begin(team, [foe])
	riot.max_hp = 100000
	riot.current_hp = 1000
	riot.heal(100, true, doc)
	_check(riot.current_hp == 1120, "Mending Circle: 2 Healers -> heals from Healers +20%% (got %d)" % (riot.current_hp - 1000))
	riot.current_hp = 1000
	riot.heal(100, true)
	_check(riot.current_hp == 1100, "Mending Circle: a heal with no Healer source is unchanged")
	_give(team, "b_overflow")       # up to 20% max HP shield
	_begin(team, [foe])
	riot.current_shield = 0
	riot.current_hp = riot.max_hp - 100
	riot.heal(50000, true)
	_check(riot.current_shield == int(riot.max_hp * 0.20), "Overflow: overheal becomes a shield capped at 20%% (%d)" % riot.current_shield)
	_give(team, "b_radiance")       # 15% of the heal
	_begin(team, [foe])
	riot.current_hp = 1000
	var fh := foe.current_hp
	riot.heal(1000, true, doc)
	_check(foe.current_hp < fh, "Radiance: a Healer's heal also hits the nearest enemy")
	_give(team, "b_vigil")          # 5% of each heal, 10% of an ult per s
	_begin(team, [foe])
	doc.ultimate_ready = false
	doc.ultimate_charge = 0
	riot.current_hp = 1000
	riot.heal(1000, true, doc)
	_check(doc.ultimate_charge == 0, "Vigil: nothing before the rate bucket fills")
	_tick(1.0)
	riot.current_hp = 1000
	riot.heal(20000, true, doc)
	var cap := int(doc.ultimate_charge_max * 0.10)
	_check(doc.ultimate_charge > 0 and doc.ultimate_charge <= cap + 1,
		"Vigil: charges from healing, at most 10%% of an ult per second (%d / %d)" % [doc.ultimate_charge, cap])
	ep.on_ult_cast(doc)
	var after_cast := doc.ultimate_charge
	_tick(1.0)
	riot.current_hp = 1000
	riot.heal(20000, true, doc)
	_check(doc.ultimate_charge == after_cast, "Vigil: no charge from heals right after its own ult")
	_give(team, "b_miracle")        # 30% HP, once
	_begin(team, [foe])
	riot.current_shield = 0        # Overflow above left Riot a shield
	reed.current_shield = 0
	riot.current_hp = 10
	riot.take_damage(5000, UnitBase.Element.NORMAL, foe, true)
	_check(riot.current_hp == int(round(riot.max_hp * 0.30)), "Miracle: the first lethal hit heals to 30%% instead (%d)" % riot.current_hp)
	var reed_saved := false
	reed.current_hp = 10
	reed.take_damage(5000, UnitBase.Element.NORMAL, foe, true)
	reed_saved = reed.current_hp > 0
	_check(not reed_saved, "Miracle: only once per fight")

# ── relic side ───────────────────────────────────────────────────────────────
func _test_relics() -> void:
	print("relics:")
	var pieces := ["faultline", "rubble", "landslide", "aftershock", "tectonic",
		"staticcharge", "conductive", "arc", "overcharge", "thunderhead",
		"undertow", "saturate", "riptide", "tidecall", "deluge",
		"crosswind", "gustchain", "slipstream", "updraft", "tempest"]
	var role_pieces := ["bulwark", "sharedburden", "retribution", "ironwill", "lastwall",
		"arcanecircle", "resonance", "manatide", "twincast", "overload",
		"warband", "packhunt", "bloodrush", "relentless", "onslaught",
		"deadeye", "longshot", "volley", "covered", "killingfield",
		"mendingcircle", "overflow", "radiance", "vigil", "miracle"]
	var bad_roles := 0
	for p in role_pieces:
		for g in ["d", "c", "b", "a", "s"]:
			var r := Relic.by_id("%s_%s" % [g, p])
			if r.is_empty() or r.get("category", "") != "archetype" or "{" in String(r.get("desc", "")):
				bad_roles += 1
	_check(bad_roles == 0, "all 25 role pieces resolve at every grade with filled text (%d bad)" % bad_roles)
	var ur := _hero(UnitBase.UnitClass.RIOT)
	for p in role_pieces:
		_give([ur], "c_" + p)
	_check(ur.relic_arch.size() == 25, "RelicInventory writes all 25 role piece types (%d)" % ur.relic_arch.size())
	_check(HeroVerbs.has_verb(UnitBase.UnitClass.RIOT, HeroVerbs.TANK) \
		and HeroVerbs.has_verb(UnitBase.UnitClass.RIOT, HeroVerbs.LIGHTNING) \
		and not HeroVerbs.has_verb(UnitBase.UnitClass.NECRO, HeroVerbs.MAGE), "HeroVerbs: role verbs by trait class")
	var missing := 0
	for p in pieces:
		for g in ["d", "c", "b", "a", "s"]:
			var r := Relic.by_id("%s_%s" % [g, p])
			if r.is_empty() or r.get("category", "") != "archetype" or "{" in String(r.get("desc", "")):
				missing += 1
	_check(missing == 0, "all 20 pieces resolve at every grade with filled text (%d bad)" % missing)
	var u := _hero(UnitBase.UnitClass.SPORE)
	for p in pieces:
		_give([u], "c_" + p)
	_check(u.relic_arch.size() == 20, "RelicInventory writes all 20 piece types (%d)" % u.relic_arch.size())
	var b_txt: String = Relic.by_id("b_faultline")["desc"]
	var c_txt: String = Relic.by_id("c_faultline")["desc"]
	_check(b_txt.contains("by 2%") and c_txt.contains("by 1.5%"),
		"percent text keeps its decimal ('%s' / '%s')" % [b_txt.substr(40, 40), c_txt.substr(40, 40)])
	_check("Bloodhound" in HeroVerbs.hero_names(HeroVerbs.EARTH) \
		and "Spore" in HeroVerbs.hero_names(HeroVerbs.EARTH) \
		and not "Coal" in HeroVerbs.hero_names(HeroVerbs.EARTH), "HeroVerbs: Earth heroes by element")
	_check(HeroVerbs.has_verb(UnitBase.UnitClass.COAL, HeroVerbs.BURN) \
		and not HeroVerbs.has_verb(UnitBase.UnitClass.COAL, HeroVerbs.EARTH), "Coal stays Burn only")
	var all_verbs := [HeroVerbs.BURN, HeroVerbs.EARTH, HeroVerbs.LIGHTNING, HeroVerbs.WATER, HeroVerbs.AIR]
	var ok_seeds := true
	for _i in range(40):
		var offers: Array = Relic.roll_offers(1, [], 3, {"seed_verbs": all_verbs})
		var verbs := {}
		for r in offers:
			if not r.get("seed", false):
				ok_seeds = false
			verbs[r.get("verb", "")] = true
		if offers.size() != 3 or verbs.size() != 3:
			ok_seeds = false
	_check(ok_seeds, "five buildable seeds -> three distinct seed cards")
	var got_earth := true
	for _i in range(20):
		var offers: Array = Relic.roll_offers(11, [], 3, {"team_verbs": [HeroVerbs.EARTH]})
		var n := 0
		for r in offers:
			if r.get("verb", "") == HeroVerbs.EARTH:
				n += 1
		if n != 1:
			got_earth = false
	_check(got_earth, "a later screen reserves exactly one Earth piece for an Earth team")
