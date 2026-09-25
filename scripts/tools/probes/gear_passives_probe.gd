extends Node
# Component-equipment probe: the 36 item passives, merge rules, save round-trip,
# auto-merge and Ability Haste, driven through the REAL AutoBattleManager /
# UnitBase hooks. Verification gate for EQUIPMENT_GREEN_PAIRS.md.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/gear_passives_probe.tscn
# Prints GEAR_PASSIVES_PROBE: ALL PASS, or every failed check.

var _fail: Array = []
var _passed := 0
var _mgr: AutoBattleManager
var _grid: BattleGrid
var _next_cell := 0

func _check(c: bool, m: String) -> void:
	if c:
		_passed += 1
	else:
		_fail.append(m)

func _ready() -> void:
	_grid = BattleGrid.new()
	_mgr = AutoBattleManager.new()
	var fx := Node2D.new()
	add_child(_grid); add_child(_mgr); add_child(fx)
	_mgr.initialize(_grid, null)
	_mgr.skill_effect_container = fx
	_rules()
	_inventory()
	_passives()
	if _fail.is_empty():
		print("GEAR_PASSIVES_PROBE: ALL PASS (%d checks)" % _passed)
	else:
		for f in _fail:
			print("  FAIL: ", f)
		print("GEAR_PASSIVES_PROBE: %d FAILED / %d passed" % [_fail.size(), _passed])
	get_tree().quit()

# A bare unit on the board with round numbers and no mitigation.
func _unit(player: bool, levels: Dictionary = {}) -> UnitBase:
	var u := UnitBase.new()
	add_child(u)
	u.battle_manager = _mgr
	u.is_player_unit = player
	u.max_hp = 1000
	u.current_hp = 1000
	u.max_mana = 100
	u.current_mana = 50
	u.attack_damage = 100
	u.magic_power = 100
	u.resistance = 0
	u.magic_resist = 0
	u.crit_chance = 0.0
	u.attack_range = 1
	u.hp_regen = 0.0
	u.mana_regen = 0.0
	var cell := Vector2i(_next_cell % 6, 2 + _next_cell / 6)
	_next_cell += 1
	u.grid_position = cell
	u.gear_levels = levels.duplicate()
	var fighters: Array = _mgr.player_units if player else _mgr.enemy_units
	fighters.append(u)
	GearPassives.battle_start(u)
	return u

func _pair(levels: Dictionary) -> Array:
	var a := _unit(true, levels)
	var b := _unit(false)
	b.grid_position = a.grid_position + Vector2i(0, 1)
	return [a, b]

func _basic(a: UnitBase, b: UnitBase, dmg: int, crit: bool = false) -> void:
	a.gear_basic_hit = true
	b.take_damage(dmg, UnitBase.Element.NORMAL, a, false, 0, false, crit)
	a.gear_basic_hit = false

# ── Merge rules ───────────────────────────────────────────────────────────────
func _green(x: String, y: String) -> ComponentEquipmentItem:
	return ComponentEquipmentRules.combine(ComponentEquipmentRules.create_common(x, {x: 5}),
		ComponentEquipmentRules.create_common(y, {y: 5}))

func _rules() -> void:
	var R := ComponentEquipmentRules
	# Every one of the 55 grey pairs makes a green with exactly one passive.
	var seen: Dictionary = {}
	for i in range(R.COMPONENTS.size()):
		for j in range(i, R.COMPONENTS.size()):
			var g := _green(R.COMPONENTS[i], R.COMPONENTS[j])
			_check(g != null and g.passive_level_count() == 1, "green %s+%s" % [R.COMPONENTS[i], R.COMPONENTS[j]])
			if g:
				seen[g.passive_levels.keys()[0]] = true
	_check(seen.size() == 36, "55 recipes reach all 36 passives (got %d)" % seen.size())
	_check(_green("armor_typo", "hp") == null, "unknown component refused")
	# HP + Mana Regen shares Regeneration with HP + HP Regen.
	_check(_green("hp", "manaregen").passive_levels.has("regeneration"), "hp+manaregen = regeneration")
	# green + green -> blue: no removal; blue + blue -> purple: remove 1.
	var ls := _green("hp", "atk")
	var th := _green("res", "magic_resist")
	var blue_a := R.combine(ls, th)
	_check(blue_a != null and blue_a.passive_levels == {"lifesteal": 1, "thorns": 1}, "blue keeps both")
	var blue_b := R.combine(_green("atk", "hp"), _green("atk", "res"))
	_check(R.levels_to_remove(blue_a, blue_b) == 1, "blue+blue must remove 1")
	_check(R.combine(blue_a, blue_b) == null, "merge refused without the removal")
	_check(R.combine(blue_a, blue_b, 1.0, {"lifesteal": 1, "thorns": 1}) == null, "removing 2 of 1 refused")
	var purple := R.combine(blue_a, blue_b, 1.0, {"thorns": 1})
	_check(purple != null and purple.passive_levels == {"lifesteal": 2, "sunder": 1}, "purple = lifesteal 2 + sunder 1")
	_check(purple != null and purple.name == "Lifesteal", "centre = highest level")
	_check(purple != null and purple.component_count() == 8, "purple has 8 components")
	# Ties go to the first input.
	_check(R.dominant_passive({"thorns": 1, "lifesteal": 1}) == "thorns", "tie -> first merged")
	# purple + purple -> gold removes 2.
	var purple2 := R.combine(R.combine(_green("hp", "atk"), _green("hp", "atk")),
		R.combine(_green("hp", "atk"), _green("hp", "atk")), 1.0, {"lifesteal": 1})
	_check(purple2 != null and purple2.passive_levels == {"lifesteal": 3}, "focused purple")
	var gold := R.combine(purple, purple2, 1.0, {"sunder": 1, "lifesteal": 1})
	_check(gold != null and gold.passive_levels == {"lifesteal": 4}, "focused gold lifesteal 4")
	# Counters: add when both carry, vanish when the passive is removed.
	var cw_a := _green("cdr", "aspd")
	var cw_b := _green("aspd", "cdr")
	cw_a.counters["clockwork_casts"] = 40
	cw_b.counters["clockwork_casts"] = 12
	var cw := R.combine(cw_a, cw_b)
	_check(cw != null and int(cw.counters.get("clockwork_casts", 0)) == 52, "clockwork counts add (40+12)")
	var cw_one := R.combine(_green("cdr", "aspd"), _green("hp", "hp"))   # clockwork 1 + bastion 1
	cw_one.counters["clockwork_casts"] = 30
	var cw2 := R.combine(cw_one, R.combine(_green("hp", "hp"), _green("hp", "hp")), 1.0, {"clockwork": 1})
	_check(cw2 != null and cw2.passive_levels == {"last_bastion": 3} and not cw2.counters.has("clockwork_casts"),
		"removed clockwork drops its count")
	# Direct drops obey the same budgets, and survive a save round-trip.
	for rarity in range(5):
		var drop := R.generate_item(10, rarity)
		_check(drop != null and drop.rarity == rarity, "drop rarity %d" % rarity)
		if drop:
			_check(drop.component_count() == R.COMPONENTS_BY_RARITY[rarity], "drop components %d" % rarity)
			_check(drop.passive_level_count() == R.PASSIVE_BUDGET[rarity], "drop budget %d" % rarity)
			var back := R.from_dict(R.to_dict(drop))
			_check(back != null and back.passive_levels == drop.passive_levels \
				and back.passive_levels.keys() == drop.passive_levels.keys() \
				and back.composition == drop.composition and back.stat_bonus == drop.stat_bonus,
				"save round-trip %d" % rarity)
	_check(ls.passives.is_empty(), "item.passives stays empty (no legacy double-fire)")

func _inventory() -> void:
	var inv := ComponentEquipmentInventory.new()
	add_child(inv)
	# Auto-merge never pairs greys, does pair greens, and stops before a menu.
	inv.add_item(ComponentEquipmentRules.create_common("hp"))
	inv.add_item(ComponentEquipmentRules.create_common("atk"))
	inv.set_auto_combine(true)
	_check(inv.items.size() == 2, "auto never pairs greys")
	inv.items.clear()
	inv.add_item(_green("hp", "atk"))
	inv.add_item(_green("res", "res"))
	_check(inv.items.size() == 1 and inv.items[0].rarity == EquipmentItem.Rarity.RARE, "auto green->blue")
	inv.add_item(ComponentEquipmentRules.combine(_green("atk", "atk"), _green("crit", "crit")))
	_check(inv.items.size() == 2, "auto stops where the menu is needed")
	# Levels sum across a hero's items; haste applies and reverts.
	var hero := _unit(true)
	var uid := hero.unit_name + "_" + str(hero.get_instance_id())
	var a := _green("hp", "atk")
	var b := _green("cdr", "atk")   # hunters_reset, +haste
	b.stat_bonus["cdr"] = 100
	inv.items.append(a)
	inv.items.append(b)
	inv.apply_to_hero(a, hero)
	inv.apply_to_hero(b, hero)
	_check(hero.gear_levels.get("lifesteal", 0) == 1 and hero.gear_levels.get("hunters_reset", 0) == 1,
		"gear_levels summed on equip (%s)" % str(hero.gear_levels))
	_check(hero.ability_haste == 100, "haste from cdr stat")
	hero.skill_cooldown_max = 4
	_check(is_equal_approx(GearPassives.skill_cooldown(hero), 2.0), "100 haste halves a 4s cooldown")
	hero.skill_cooldown_max = 1
	_check(is_equal_approx(GearPassives.skill_cooldown(hero), 1.0), "cooldown floor 1s")
	inv.remove_from_hero(b, hero)
	_check(hero.ability_haste == 0 and not hero.gear_levels.has("hunters_reset"), "unequip reverts haste + levels")
	_check(hero.equipment_passives.is_empty(), "legacy equipment_passives untouched")

# ── The 36 passives ───────────────────────────────────────────────────────────
func _passives() -> void:
	var L := 4   # one gold
	var f := GearCatalog.curve(L)
	var p: Array
	var a: UnitBase
	var b: UnitBase

	# No gear: every hook is inert.
	var plain := _unit(true)
	_check(GearPassives.crit_bonus(plain) == 0.0 and GearPassives.attack_wait_mult(plain) == 1.0,
		"no-gear unit unchanged")

	# 1 Last Bastion
	a = _unit(true, {"last_bastion": L}); a.current_hp = 600
	b = _unit(false)
	b.take_damage(0, UnitBase.Element.NORMAL, null)   # noop
	a.take_damage(200, UnitBase.Element.NORMAL, b)
	_check(a.gear_shield == roundi(1000 * 0.30 * f), "#1 bastion shield %d" % a.gear_shield)
	a.current_hp = 900; a.gear_shield = 0
	a.take_damage(500, UnitBase.Element.NORMAL, b)
	_check(a.gear_shield == 0, "#1 once per fight")

	# 2 Lifesteal (basic only)
	p = _pair({"lifesteal": L}); a = p[0]; b = p[1]; a.current_hp = 500
	_basic(a, b, 100)
	_check(a.current_hp == 500 + roundi(100 * 0.40 * f), "#2 lifesteal heal (%d)" % a.current_hp)
	a.current_hp = 500
	b.take_damage(100, UnitBase.Element.NORMAL, a)   # not basic
	_check(a.current_hp == 500, "#2 skills do not lifesteal")

	# 3 Aftercast Ward (6s gate, 24% pool cap)
	a = _unit(true, {"aftercast_ward": L})
	GearPassives.after_cast(a, null, [], [], _mgr)
	var ward := a.gear_shield
	_check(ward == roundi(1000 * 0.12 * f), "#3 ward shield %d" % ward)
	GearPassives.after_cast(a, null, [], [], _mgr)
	_check(a.gear_shield == ward, "#3 6s internal cooldown")
	a.gear["echo"] = true; a.gear["ward_icd"] = 0.0
	GearPassives.after_cast(a, null, [], [], _mgr)
	_check(a.gear_shield == ward, "#3 echo copies grant nothing")
	a.gear["echo"] = false
	for i in range(10):
		a.gear["ward_icd"] = 0.0
		GearPassives.after_cast(a, null, [], [], _mgr)
	_check(a.gear_shield <= 240 and a.gear_shield >= 230, "#3 pool capped at 24%% (%d)" % a.gear_shield)

	# 4 Second Wind
	a = _unit(true, {"second_wind": L}); a.current_hp = 500
	GearPassives.after_cast(a, null, [], [], _mgr)
	_check(a.current_hp == 500 + roundi(1000 * 0.06 * f), "#4 heal on cast")

	# 5 Iron Rhythm
	p = _pair({"iron_rhythm": L}); a = p[0]; b = p[1]
	_basic(a, b, 10); _basic(a, b, 10)
	_check(a.gear_shield == 0, "#5 no shield before the 3rd hit")
	_basic(a, b, 10)
	_check(a.gear_shield == roundi(1000 * 0.06 * f), "#5 shield on 3rd hit")
	_basic(a, b, 10); GearPassives.tick(a, 4.1); _basic(a, b, 10); _basic(a, b, 10)
	_check(a.gear_shield == roundi(1000 * 0.06 * f), "#5 count resets after 4s idle")

	# 6 Desperation
	a = _unit(true, {"desperation": L}); a.current_hp = 400   # 60% missing -> 2 steps
	_check(is_equal_approx(GearPassives.crit_bonus(a), 2 * 0.08 * f), "#6 two steps")

	# 7 Bulwark
	a = _unit(true, {"bulwark": L})
	a.take_damage(300, UnitBase.Element.NORMAL, null)
	_check(a.current_hp == 1000, "#7 first hit blocked")
	a.take_damage(300, UnitBase.Element.NORMAL, null)
	_check(a.current_hp == 700, "#7 cooldown after a block")
	GearPassives.tick(a, GearCatalog.shrink(24.0, 6.0, L) + 0.1)
	a.take_damage(300, UnitBase.Element.NORMAL, null)
	_check(a.current_hp == 700, "#7 ready again after %.1fs" % GearCatalog.shrink(24.0, 6.0, L))
	a.take_damage(50, UnitBase.Element.NORMAL, null, true)   # DoT-style true damage
	_check(a.current_hp == 650, "#7 DoT cannot trigger the block")

	# 8 Regeneration
	a = _unit(true, {"regeneration": L}); a.current_hp = 500
	GearPassives.tick(a, 1.0)
	_check(is_equal_approx(a.hp_regen_accum, 1000 * 0.01 * f), "#8 regen accum %.2f" % a.hp_regen_accum)

	# 9 Overkill
	_mgr.enemy_units.clear()   # stray probe units all sit at the same screen position
	p = _pair({"overkill": L}); a = p[0]; b = p[1]; b.current_hp = 50
	var c := _unit(false); c.grid_position = a.grid_position + Vector2i(1, 0)
	_basic(a, b, 250)
	_check(c.current_hp == 1000 - roundi(200 * 0.50 * f), "#9 overkill spill (%d)" % c.current_hp)

	# 10 Arcane Conduit: once per target per cast
	p = _pair({"arcane_conduit": L}); a = p[0]; b = p[1]
	GearPassives.before_cast(a)
	b.take_damage(100, UnitBase.Element.NORMAL, a, false, 0, true)
	var after_one := b.current_hp
	_check(after_one == 1000 - 100 - roundi(100 * 0.50 * f), "#10 conduit extra hit (%d)" % after_one)
	b.take_damage(100, UnitBase.Element.NORMAL, a, false, 0, true)
	_check(b.current_hp == after_one - 100, "#10 once per target per cast")

	# 11 Hunter's Reset
	p = _pair({"hunters_reset": L}); a = p[0]; b = p[1]; b.current_hp = 10; a.skill_cd_time = 3.0
	_basic(a, b, 100)
	_check(is_equal_approx(a.skill_cd_time, 3.0 - 1.5 * f), "#11 cooldown cut on basic kill")

	# 12 Cadence
	p = _pair({"cadence": L}); a = p[0]; b = p[1]
	for i in range(7):
		_basic(a, b, 1)
	_check(int(a.gear.get("cadence", 0)) == 5, "#12 five stacks max")
	_check(is_equal_approx(GearPassives.attack_wait_mult(a), 1.0 / (1.0 + 5 * 0.06 * f)), "#12 attack speed")
	a.is_moving = true; GearPassives.tick(a, 0.01); a.is_moving = false
	_check(int(a.gear.get("cadence", 0)) == 0, "#12 movement clears")

	# 13 Deep Wound
	p = _pair({"deep_wound": L}); a = p[0]; b = p[1]
	_basic(a, b, 100, true)
	b.current_hp = 500; b.heal(100)
	_check(b.current_hp == 500 + roundi(100 * (1.0 - 0.40 * f)), "#13 healing cut (%d)" % b.current_hp)

	# 14 Sunder
	p = _pair({"sunder": L}); a = p[0]; b = p[1]; b.resistance = 100
	for i in range(6):
		_basic(a, b, 1)
	_check(int(b.gear.get("sunder", 0)) == 5, "#14 five stacks")
	_check(GearPassives.effective_armor(b, 100) == roundi(100 * (1.0 - 5 * 0.08 * f)), "#14 armor shred")

	# 15 Blood Price
	p = _pair({"blood_price": L}); a = p[0]; b = p[1]; b.current_hp = 10; a.current_hp = 500; a.current_mana = 0
	_basic(a, b, 100)
	_check(a.current_hp == 500 + roundi(1000 * 0.04 * f) and a.current_mana == roundi(8 * f), "#15 kill heal + mana")

	# 16 Attunement: battle-start multiplier, reverted, never stacked
	a = _unit(true, {"attunement": L})
	_check(a.magic_power == 100 + roundi(100 * 0.60 * f), "#16 magic power")
	GearPassives.battle_start(a)
	_check(a.magic_power == 100 + roundi(100 * 0.60 * f), "#16 does not stack across fights")
	GearPassives.battle_end(a)
	_check(a.magic_power == 100, "#16 reverted at fight end")

	# 17 Spell Echo: the copy is free, targeted and does not re-trigger
	p = _pair({"spell_echo": L, "second_wind": L}); a = p[0]; b = p[1]
	a.current_hp = 500
	GearPassives._echo(a, b, [], _mgr)
	_check(a.current_hp == 500, "#17 echo triggers no cast passives")
	_check(not bool(a.gear.get("echo", false)), "#17 echo flag cleared")
	# Only a cast that damaged its enemy target may echo (heals/buffs never do).
	var stub := EchoStub.new(); add_child(stub)
	p = _pair({"spell_echo": 24}); a = p[0]; b = p[1]; a.target_unit = b
	for i in range(300):
		GearPassives.before_cast(a)          # target untouched by the "cast"
		GearPassives.after_cast(a, b, [b], [], stub)
	_check(stub.copies == 0, "#17 no echo for a non-damaging cast (%d)" % stub.copies)
	for i in range(1000):
		GearPassives.before_cast(a)
		b.current_hp -= 1                    # the cast hit its target
		GearPassives.after_cast(a, b, [b], [], stub)
		b.current_hp = 1000
	var echo_rate := stub.copies / 1000.0
	_check(absf(echo_rate - 0.30 * GearCatalog.curve(24)) < 0.05, "#17 echo rate %.3f" % echo_rate)

	# 18 Spell Tempo
	a = _unit(true, {"spell_tempo": L})
	GearPassives.after_cast(a, null, [], [], _mgr)
	_check(is_equal_approx(GearPassives.attack_wait_mult(a), 1.0 / (1.0 + 0.25 * f)), "#18 tempo")
	GearPassives.tick(a, 4.1)
	_check(is_equal_approx(GearPassives.attack_wait_mult(a), 1.0), "#18 lasts 4s")

	# 19 Arcane Precision (statistical)
	p = _pair({"arcane_precision": L}); a = p[0]; b = p[1]
	GearPassives.before_cast(a)
	var hits := 0
	for i in range(2000):
		if GearPassives.skill_damage_mult(a, b, 100, false) == 150:
			hits += 1
	var want := 0.25 * f
	_check(absf(hits / 2000.0 - want) < 0.03, "#19 precision rate %.3f vs %.3f" % [hits / 2000.0, want])

	# 20 Mana Shield
	a = _unit(true, {"mana_shield": L}); a.current_mana = 100
	a.take_damage(200, UnitBase.Element.NORMAL, null)
	var redirect := int(floor(200 * 0.30 * f))
	_check(a.current_hp == 1000 - (200 - redirect) and a.current_mana == 100 - int(ceil(redirect / 2.0)),
		"#20 mana shield (hp %d mana %d)" % [a.current_hp, a.current_mana])

	# 21 Empty Reservoir
	p = _pair({"empty_reservoir": L}); a = p[0]; b = p[1]; a.current_mana = 0
	GearPassives.before_cast(a)
	_check(GearPassives.skill_damage_mult(a, b, 100, false) == roundi(100 * (1.0 + 0.40 * f)), "#21 empty bonus")
	a.current_mana = 100
	GearPassives.before_cast(a)
	_check(GearPassives.skill_damage_mult(a, b, 100, false) == 100, "#21 full mana = no bonus")

	# 22 Battle Charge
	a = _unit(true, {"battle_charge": L}); a.ultimate_charge_max = 300; a.ultimate_charge = 0
	GearPassives.after_cast(a, null, [], [], _mgr)
	_check(a.ultimate_charge == roundi(45 * f), "#22 ult charge %d" % a.ultimate_charge)

	# 23 Clockwork: item counter, ln growth, untargeted -> nearest
	p = _pair({"clockwork": L}); a = p[0]; b = p[1]
	var cw := _green("cdr", "aspd"); cw.counters["clockwork_casts"] = 9
	a.gear_items = [cw]
	GearPassives.after_cast(a, null, [b], [], _mgr)
	_check(int(cw.counters["clockwork_casts"]) == 10, "#23 count persists on the item")
	_check(b.current_hp == 1000 - roundi(36 * f * log(11.0)), "#23 ln(1+N) magic hit (%d)" % b.current_hp)

	# 24 Precision Reset (no per-second limit)
	p = _pair({"precision_reset": L}); a = p[0]; b = p[1]; a.skill_cd_time = 2.0
	_basic(a, b, 1, true); _basic(a, b, 1, true)
	_check(is_equal_approx(a.skill_cd_time, 2.0 - 2 * 0.6 * f), "#24 two crits, two cuts")

	# 25 Spellguard stacks + expiry
	a = _unit(true, {"spellguard": L})
	GearPassives.after_cast(a, null, [], [], _mgr)
	GearPassives.after_cast(a, null, [], [], _mgr)
	_check(GearPassives.effective_armor(a, 10) == roundi(10 + 2 * 20 * f), "#25 two stacks")
	GearPassives.tick(a, 5.0 + 15.0 * f + 0.1)
	_check(GearPassives.effective_armor(a, 10) == 10, "#25 stacks expire")

	# 26 Rest Cycle: only while the skill recharges
	a = _unit(true, {"rest_cycle": L}); a.current_hp = 500; a.current_mana = 0; a.skill_cd_time = 0.0
	GearPassives.tick(a, 1.0)
	_check(a.hp_regen_accum == 0.0, "#26 idle when skill ready")
	a.skill_cd_time = 5.0
	GearPassives.tick(a, 1.0)
	_check(is_equal_approx(a.mp_regen_accum, 3.0 * f), "#26 mana while recharging")

	# 27 Battle Haste: kills persist on the item, half lost on death, summon cap
	p = _pair({"battle_haste": L}); a = p[0]
	var bh := _green("aspd", "aspd"); a.gear_items = [bh]
	for i in range(7):
		var foe := _unit(false); foe.is_summoned = true; foe.current_hp = 1
		_basic(a, foe, 10)
	_check(int(bh.counters.get("haste_kills", 0)) == 5, "#27 summon kills capped at 5")
	var foe2 := _unit(false); foe2.current_hp = 1
	_basic(a, foe2, 10)
	_check(int(bh.counters["haste_kills"]) == 6, "#27 real kills uncapped")
	_check(is_equal_approx(GearPassives.attack_wait_mult(a), 1.0 / (1.0 + 0.127 * f * log(7.0))), "#27 ln(1+K)")
	GearPassives.on_death(a)
	_check(int(bh.counters["haste_kills"]) == 3, "#27 death halves (6 -> 3)")

	# 28 Keen Rhythm
	p = _pair({"keen_rhythm": L}); a = p[0]; b = p[1]
	_basic(a, b, 1, true)
	_check(is_equal_approx(GearPassives.attack_wait_mult(a), 1.0 - 0.30 * f), "#28 next wait shorter")
	_check(is_equal_approx(GearPassives.attack_wait_mult(a), 1.0), "#28 consumed by one attack")

	# 29 Riposte: slows the attacker
	p = _pair({"riposte": L}); a = p[0]; b = p[1]
	_basic(b, a, 10)
	_check(is_equal_approx(GearPassives.attack_wait_mult(b), 1.0 / (1.0 - 0.25 * f)), "#29 attacker slowed")
	GearPassives.tick(b, 3.1)
	_check(is_equal_approx(GearPassives.attack_wait_mult(b), 1.0), "#29 lasts 3s")

	# 30 Sustained Assault
	p = _pair({"sustained_assault": L}); a = p[0]; b = p[1]; a.current_mana = 0
	_basic(a, b, 1)
	GearPassives.tick(a, 1.0)
	_check(is_equal_approx(a.mp_regen_accum, 3.0 * f), "#30 mana after a hit")
	GearPassives.tick(a, 1.5)
	var acc := a.mp_regen_accum
	GearPassives.tick(a, 1.0)
	_check(is_equal_approx(a.mp_regen_accum, acc), "#30 ends 2s after the hit")

	# 31 Critical Focus
	p = _pair({"critical_focus": L}); a = p[0]; b = p[1]
	for i in range(6):
		_basic(a, b, 1)
	_check(is_equal_approx(GearPassives.crit_bonus(a), 5 * 0.06 * f), "#31 five stacks")
	_basic(a, b, 1, true)
	_check(GearPassives.crit_bonus(a) == 0.0, "#31 crit consumes stacks")
	_check(is_equal_approx(GearPassives.crit_damage_bonus(a), 0.5 * f), "#31 crit damage")

	# 32 Counterstrike
	p = _pair({"counterstrike": L}); a = p[0]; b = p[1]
	_basic(b, a, 10)
	_check(is_equal_approx(GearPassives.crit_bonus(a), 0.40 * f), "#32 charged by a basic hit")
	GearPassives.on_attack_roll(a)
	_check(GearPassives.crit_bonus(a) == 0.0, "#32 spent by the next swing")

	# 33 Vital Precision (1/s)
	p = _pair({"vital_precision": L}); a = p[0]; b = p[1]; a.current_hp = 500; a.current_mana = 0
	_basic(a, b, 1, true); _basic(a, b, 1, true)
	_check(a.current_hp == 500 + roundi(1000 * 0.02 * f), "#33 heal once per second")

	# 34 Thorns
	p = _pair({"thorns": L}); a = p[0]; b = p[1]
	_basic(b, a, 100)
	_check(b.current_hp == 1000 - roundi(100 * 0.35 * f), "#34 reflect (%d)" % b.current_hp)

	# 35 Recovery
	a = _unit(true, {"recovery": L}); a.current_mana = 0
	a.take_damage(50, UnitBase.Element.NORMAL, null)
	GearPassives.tick(a, 1.0)
	_check(is_equal_approx(a.mp_regen_accum, 5.0 * f), "#35 regen after being hit")

	# 36 Equilibrium
	a = _unit(true, {"equilibrium": L}); a.hp_regen = 2.0; a.current_mana = 0
	GearPassives.tick(a, 1.0)
	_check(is_equal_approx(a.mp_regen_accum, 0.80 * f * 2.0), "#36 wasted hp regen -> mana")

class EchoStub extends Node:
	var copies := 0
	func _use_skill(_caster, _opponents, _allies = []) -> void:
		copies += 1
