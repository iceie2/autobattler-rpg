extends Node
# ══════════════════════════════════════════════════════════════════════════════
# EVENT SMOKE (2026-09-19) — end-to-end proof that the event catalog's effects
# actually LAND on real heroes.
#
# `arena --mode=events` validates the catalog itself (every choice × grade
# resolves, no unknown verbs, payouts in range) but it never applies anything:
# it's pure data. This scene closes that gap by instantiating the REAL
# main_game, recruiting heroes, and pushing every catalog choice through
# main_game._apply_event_effects — the same function the panel callback calls.
#
# What it asserts, per verb, is that the effect DID SOMETHING measurable:
# gold moved, HP moved, an item appeared in the bag, a perk raised a stat, a
# flag got set. The 2026-07-16 audit found three events whose choice text
# promised effects the code didn't implement (movement-only "act faster" was a
# no-op for every unit); this is that audit, automated.
#
# Run:  godot --headless res://scenes/event_smoke.tscn
# Exit code 0 = pass, 1 = fail.
# ══════════════════════════════════════════════════════════════════════════════

var _fails: Array = []
var _checked: int = 0

func _ready() -> void:
	var mg_scene := load("res://scenes/main_game.tscn") as PackedScene
	var mg := mg_scene.instantiate()
	add_child(mg)
	for _i in range(30):
		await get_tree().process_frame

	# Two real heroes on the board — several verbs (perks, heals, team buffs)
	# need something to apply TO, and a one-hero team would hide any
	# per-hero-loop bug.
	mg.max_player_units = maxi(mg.max_player_units, 2)
	mg._recruit_hero(UnitBase.UnitClass.BLOODHOUND,
		UnitFactory.element_for_class(UnitBase.UnitClass.BLOODHOUND), {})
	mg._recruit_hero(UnitBase.UnitClass.BOUNCER,
		UnitFactory.element_for_class(UnitBase.UnitClass.BOUNCER), {})
	await get_tree().process_frame

	var heroes: Array = mg.player_units.filter(func(u): return u and is_instance_valid(u))
	if heroes.size() < 2:
		print("EVENT_SMOKE: FAILED -> could not stage two heroes")
		get_tree().quit(1)
		return

	# ── 1. Every catalog choice, applied for real ────────────────────────────
	# Grades C and S: C is the common case, S is the one that produces the
	# biggest numbers (and so the one most likely to trip a clamp or overflow).
	for def: Dictionary in EventCatalog.all_defs():
		var id: String = String(def.get("id", "?"))
		for ci in range(def.get("choices", []).size()):
			for grade in ["C", "S"]:
				_apply_one(mg, def, ci, grade, id)

	# ── 2. Targeted verb assertions ──────────────────────────────────────────
	_check_gold(mg)
	_check_heal(mg)
	_check_perk(mg)
	_check_item(mg)
	_check_scrap_is_worse_than_buying(mg)
	_check_flags_and_debt(mg)
	_check_scar(mg)
	_check_next_wave(mg)

	if _fails.is_empty():
		print("EVENT_SMOKE: PASSED (%d checks, %d events)"
			% [_checked, EventCatalog.all_defs().size()])
		get_tree().quit(0)
	else:
		print("EVENT_SMOKE: FAILED")
		for f in _fails:
			print("  - %s" % f)
		get_tree().quit(1)

# Resolve a choice and push it through the live effect applier. A crash or a
# pushed error here is the failure; the assertions below check for meaning.
func _apply_one(mg: Node, def: Dictionary, ci: int, grade: String, id: String) -> void:
	var ctx: Dictionary = mg._event_context()
	var choice: Dictionary = def["choices"][ci]
	var resolved: Dictionary = EventCatalog.resolve_choice(choice, ctx, grade)
	var effects: Dictionary = resolved.get("effects", {})
	# Keep the run solvent so percentage-of-purse costs have something to bite.
	mg.game_state.gold = maxi(mg.game_state.gold, 60)
	mg._apply_event_effects(effects)
	_checked += 1
	for u in mg.player_units:
		if u and is_instance_valid(u):
			if u.current_hp <= 0:
				_fails.append("%s[%d]/%s left %s on 0 HP outside combat"
					% [id, ci, grade, u.unit_name])
			if u.max_hp <= 0:
				_fails.append("%s[%d]/%s drove %s max HP to 0" % [id, ci, grade, u.unit_name])
	if mg.game_state.gold < 0:
		_fails.append("%s[%d]/%s drove gold negative" % [id, ci, grade])

func _check_gold(mg: Node) -> void:
	mg.game_state.gold = 50
	mg._apply_event_effects({"gold": 25})
	if mg.game_state.gold != 75:
		_fails.append("gold verb: 50 + 25 gave %d" % mg.game_state.gold)
	mg._apply_event_effects({"gold_pct": -0.2})
	if mg.game_state.gold != 60:
		_fails.append("gold_pct verb: 75 - 20%% gave %d" % mg.game_state.gold)
	_checked += 2

func _check_heal(mg: Node) -> void:
	var u = mg.player_units[0]
	u.current_hp = maxi(1, int(u.max_hp * 0.2))
	var before: int = u.current_hp
	mg._apply_event_effects({"heal_pct": 0.5})
	if u.current_hp <= before:
		_fails.append("heal_pct verb: HP did not rise (%d -> %d)" % [before, u.current_hp])
	if u.current_hp > u.max_hp:
		_fails.append("heal_pct verb: healed past max (%d/%d)" % [u.current_hp, u.max_hp])
	_checked += 1

func _check_perk(mg: Node) -> void:
	# A perk has to change SOMETHING on SOME hero — which hero and which stat
	# are both random ("best" may be either unit; the perk is drawn from the
	# full PERKS table), so the check snapshots every hero and every stat
	# apply_perk_to_unit can touch, and asserts the team line moved.
	var before: Array[String] = []
	for u in mg.player_units:
		before.append(_stat_fingerprint(u))
	mg._apply_event_effects({"hero_perk": {"count": 1, "target": "best", "grade": "S"}})
	var changed: bool = false
	for i in range(mg.player_units.size()):
		if _stat_fingerprint(mg.player_units[i]) != before[i]:
			changed = true
	if not changed:
		_fails.append("hero_perk verb: no hero's stats changed (fingerprint %s)" % str(before))
	_checked += 1

func _check_item(mg: Node) -> void:
	var before: int = mg._equipment_inventory.items.size()
	mg._apply_event_effects({"grant_item": {"count": 1, "max_rarity": EquipmentItem.Rarity.RARE}})
	if mg._equipment_inventory.items.size() <= before:
		_fails.append("grant_item verb: bag did not grow (%d)" % before)
	_checked += 1

# The salvage rate exists to stop a buy-low/scrap-high loop. Assert the
# invariant directly at several rounds rather than trusting the constant.
func _check_scrap_is_worse_than_buying(mg: Node) -> void:
	for r in [1, 25, 75]:
		var item := EquipmentManager.generate_item(r, EquipmentItem.Rarity.RARE)
		var buy: int = ShopGenerator.item_price(item, r)
		var best_salvage: int = int(round(float(buy) * mg.SALVAGE_RATIO * 1.4))
		if best_salvage >= buy:
			_fails.append("salvage at round %d pays %dg for an item that costs %dg"
				% [r, best_salvage, buy])
		_checked += 1

func _check_flags_and_debt(mg: Node) -> void:
	mg._run_flags.clear()
	mg._apply_event_effects({"set_flag": {"refused_duel": true, "_text": "ignored"}})
	if not mg._run_flags.get("refused_duel", false):
		_fails.append("set_flag verb: flag not set")
	if mg._run_flags.has("_text"):
		_fails.append("set_flag verb: authoring key '_text' leaked into run flags")
	# A flag gates its callback event: the rival must be eligible now and not
	# before. This is the whole point of the flag system, so it gets asserted.
	var ctx: Dictionary = mg._event_context()
	ctx["round"] = 20
	var rival: Dictionary = EventCatalog.def_by_id("the_rival_returns")
	if not EventCatalog.is_eligible(rival, ctx):
		_fails.append("the_rival_returns should be eligible once refused_duel is set")
	var clean: Dictionary = ctx.duplicate(true)
	clean["flags"] = {}
	if EventCatalog.is_eligible(rival, clean):
		_fails.append("the_rival_returns fired without the refused_duel flag")

	# ── Debt, underpaid ───────────────────────────────────────────────────────
	# The merchant takes everything you have, the REMAINDER STAYS OWED, and the
	# collector's flag is set.
	#
	# This block previously asserted that the loan was cleared no matter what
	# was paid, which is exactly the exploit it should have caught: spend down
	# to zero before a merchant and the debt evaporated (and the `not_flag`
	# guard reopened, so you could sign another). The test was encoding the bug.
	mg._run_flags.clear()
	mg._apply_event_effects({"debt": 40})
	mg.game_state.gold = 10
	mg._settle_merchant_debt()
	if mg.game_state.gold != 0:
		_fails.append("debt: merchant should have taken all 10g, left %d" % mg.game_state.gold)
	if not mg._run_flags.get("debt_unpaid", false):
		_fails.append("debt: underpayment did not set debt_unpaid")
	if int(mg._run_flags.get("debt", 0)) != 30:
		_fails.append("debt: 30g should still be owed, ledger says %d"
			% int(mg._run_flags.get("debt", 0)))

	# ── Debt, paid in full ────────────────────────────────────────────────────
	mg._run_flags.clear()
	mg._apply_event_effects({"debt": 40})
	mg.game_state.gold = 100
	mg._settle_merchant_debt()
	if mg.game_state.gold != 60:
		_fails.append("debt: paying 40 of 100 left %d" % mg.game_state.gold)
	if mg._run_flags.has("debt"):
		_fails.append("debt: a fully paid loan is still on the ledger")
	if mg._run_flags.get("debt_unpaid", false):
		_fails.append("debt: a fully paid loan still summons the collector")
	_checked += 7

# Every stat LevelUpScreen.apply_perk_to_unit can move. Anything missing here
# makes the perk check silently pass on a no-op — the first version omitted
# regen/movement/crit-damage and reported a false failure for exactly that
# reason.
# A scar must move one stat UP and the other DOWN. This is the check that the
# whole verb exists for: the shared perk path floors every value positive, so a
# scar routed through it would quietly become two buffs.
func _check_scar(mg: Node) -> void:
	var u = mg.player_units[0]
	# "best" targets the highest level; make this unit unambiguously that.
	u.level = maxi(u.level, mg.player_units[1].level + 1)
	var atk_before: int = u.attack_damage
	var hp_before: int = u.max_hp
	mg._apply_event_effects({"hero_scar": {
		"target": "best", "gain_stat": "attack_damage", "gain_pct": 0.5,
		"cost_stat": "max_hp", "cost_pct": 0.2}})
	if u.attack_damage <= atk_before:
		_fails.append("scar: attack did not rise (%d -> %d)" % [atk_before, u.attack_damage])
	if u.max_hp >= hp_before:
		_fails.append("scar: max HP did not FALL (%d -> %d) — the cost was floored away"
			% [hp_before, u.max_hp])
	if u.current_hp > u.max_hp:
		_fails.append("scar: current HP %d left above the new max %d" % [u.current_hp, u.max_hp])
	if u.current_hp < 1:
		_fails.append("scar: the cost killed the hero outright")
	if u.get_meta("scars", []).is_empty():
		_fails.append("scar: nothing recorded on the hero, so the details panel can't show it")
	# A scar must never be able to zero a stat out, however big the cost.
	mg._apply_event_effects({"hero_scar": {
		"target": "best", "gain_stat": "attack_damage", "gain_pct": 0.1,
		"cost_stat": "max_hp", "cost_pct": 5.0}})
	if u.max_hp < 1:
		_fails.append("scar: a huge cost drove max HP to %d" % u.max_hp)
	_checked += 6

# The wave-modifier verb is the plumbing the whole Combat archetype needs, so
# check it lands in the held dict AND survives into a generated wave spec.
func _check_next_wave(mg: Node) -> void:
	mg._next_wave_mods.clear()
	mg._apply_event_effects({"next_wave": {"extra_enemies": 2, "reward_tier": 2}})
	if int(mg._next_wave_mods.get("extra_enemies", 0)) != 2:
		_fails.append("next_wave: extra_enemies not held (%s)" % str(mg._next_wave_mods))
	if int(mg._next_wave_mods.get("reward_tier", -1)) != 2:
		_fails.append("next_wave: reward_tier not held (%s)" % str(mg._next_wave_mods))
	var with_mod: int = mg._generate_wave_spec(WaveScaler.Difficulty.NORMAL).size()
	mg._next_wave_mods.clear()
	var without: int = mg._generate_wave_spec(WaveScaler.Difficulty.NORMAL).size()
	if with_mod != without + 2:
		_fails.append("next_wave: spec had %d bodies with the modifier and %d without (expected +2)"
			% [with_mod, without])
	_checked += 3

func _stat_fingerprint(u) -> String:
	return "%d/%d/%.3f/%d/%d/%d/%.3f/%.3f/%d/%.3f/%.3f" % [
		u.attack_damage, u.magic_power, u.attack_speed, u.max_hp,
		u.resistance, u.magic_resist, u.hp_regen, u.mana_regen,
		u.movement_speed, u.crit_chance, u.crit_damage]
