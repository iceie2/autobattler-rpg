extends Node
# ══════════════════════════════════════════════════════════════════════════════
# RUN RECAP SMOKE (2026-10-07) - the run recorder (RecapFightTap + RunRecap).
#
# Drives the REAL UnitBase.take_damage / heal and AutoBattleManager._grant_shield
# through a real manager, then checks the frozen per-fight data and the run
# record built from it:
#   * caster protection with STACKED shields (FIFO), partial and full shielded
#     hits, unused capacity, self shields, own item-shield/Mana-Shield split,
#     pool wipes, uninstrumented and enemy-sourced grants, summons
#   * enemy defeats by type (summons counted), late kills after the whistle
#   * effective healing incl. self-heal, overheal excluded (BattleRecorder)
#   * exact-once finalisation, replay replacement, immutability, prefix sums,
#     late joins, deaths/revivals, skipped waves, terminal defeat / victory
#   * save/resume parity (var_to_str AND JSON), legacy partial history,
#     report rebuild fidelity, bounded worst-case serialization (measured)
#   * instrumentation parity: the same hits with the tap open or closed leave
#     identical HP / shields
#   * the damage breakdown: auto / skill / ult / DoT / summon / other x
#     physical / magic / true, summing to dealt_hp, persisted, legacy unsplit
#
# Run (it writes one throwaway file under user://, so a disposable profile only):
#   APPDATA=<scratch>/recap/isolated-profile \
#     godot --headless --path . res://scenes/run_recap_smoke.tscn
# Prints RUN_RECAP_SMOKE: ALL PASS. Exit 0 pass, 1 fail, 2 refused.
# ══════════════════════════════════════════════════════════════════════════════

var _fails: Array = []
var mgr: AutoBattleManager

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		_fails.append(label)
		print("  FAIL: %s" % label)

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("isolated-profile"):
		push_error("run_recap_smoke: refusing to run outside a disposable isolated-profile")
		get_tree().quit(2)
		return
	mgr = AutoBattleManager.new()
	add_child(mgr)
	mgr.skill_effect_container = Node2D.new()
	add_child(mgr.skill_effect_container)

	_test_stacked_shields()
	_test_self_items_and_unattributed()
	_test_pool_wipe_and_enemy_grant()
	_test_summons()
	_test_defeats()
	_test_instrumentation_parity()
	_test_damage_split()
	_test_fight_finalisation()
	_test_cumulative_and_history()
	_test_terminal_and_persistence()
	_test_legacy_partial()
	_test_bounded_serialization()

	print("RUN_RECAP_SMOKE: %s" % ("ALL PASS" if _fails.is_empty()
		else "%d FAILED -> %s" % [_fails.size(), ", ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)

# ── helpers ──────────────────────────────────────────────────────────────────
func _hero(cls: int, hp := 1000) -> UnitBase:
	var u: UnitBase = UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
	add_child(u)
	u.battle_manager = mgr
	u.max_hp = hp
	u.current_hp = hp
	u.resistance = 0
	u.magic_resist = 0
	u.died.connect(mgr._on_ally_died.bind(u))
	return u

func _foe(hp := 100000, type := "goblin") -> UnitBase:
	var u: UnitBase = EnemyFactory.create_by_type(type)
	add_child(u)
	u.battle_manager = mgr
	u.is_player_unit = false
	u.max_hp = hp
	u.current_hp = hp
	u.resistance = 0
	u.magic_resist = 0
	return u

func _begin(players: Array, enemies: Array) -> void:
	mgr.player_units = players
	mgr.enemy_units = enemies
	mgr.battle_elapsed = 0.0
	mgr.recorder.begin(players, enemies)
	mgr.recap_tap.begin(players, enemies)

func _hit(victim: UnitBase, attacker: UnitBase, amount: int) -> void:
	victim.take_damage(amount, UnitBase.Element.NORMAL, attacker, true)

func _prot(snap: Dictionary, u: UnitBase) -> Dictionary:
	return snap["heroes"].get(u.get_instance_id(), {"protect_out": -1, "protect_self": -1})

func _free(units: Array) -> void:
	for u in units:
		if is_instance_valid(u):
			u.queue_free()

# ── protection ───────────────────────────────────────────────────────────────
func _test_stacked_shields() -> void:
	print("[stacked shields, caster credit, unused capacity]")
	var a := _hero(UnitBase.UnitClass.SHEILDOR)
	var b := _hero(UnitBase.UnitClass.NEMI)
	var c := _hero(UnitBase.UnitClass.SHAUNA)
	var foe := _foe()
	_begin([a, b, c], [foe])
	mgr._grant_shield(c, 100, a)
	mgr._grant_shield(c, 50, b)
	_check(c.current_shield == 150, "two casters stack one pool (150)")
	_hit(c, foe, 120)
	_check(c.current_hp == 1000 and c.current_shield == 30, "fully shielded hit: no HP lost, 30 left")
	_hit(c, foe, 50)
	_check(c.current_hp == 980 and c.current_shield == 0, "partial shielded hit: 30 soaked, 20 HP lost")
	mgr._grant_shield(c, 70, b)          # never hit: unused capacity
	var rep := mgr.recorder.snapshot(true, [])
	var snap := mgr.recap_tap.snapshot()
	_check(_prot(snap, a)["protect_out"] == 100, "oldest grant spent first: Sheildor credited 100")
	_check(_prot(snap, b)["protect_out"] == 50, "Nemi credited 20 + 30 = 50; her unused 70 counts for nobody")
	_check(_prot(snap, c)["protect_out"] == 0 and _prot(snap, c)["protect_self"] == 0,
		"the holder supplied nothing, so it is credited nothing")
	var c_row: Dictionary = {}
	for h in rep["heroes"]:
		if int(h["id"]) == c.get_instance_id():
			c_row = h
	_check(int(c_row.get("taken_shield", -1)) == 150 and int(c_row.get("taken_hp", -1)) == 20,
		"recipient side kept separately: Shauna's shields absorbed 150, HP lost 20")
	_check(int(snap["protect_unattributed"]) == 0, "nothing unattributed")
	_free([a, b, c, foe])

func _test_self_items_and_unattributed() -> void:
	print("[self shields, own item layers, uninstrumented grants]")
	var a := _hero(UnitBase.UnitClass.SHEILDOR)
	var foe := _foe()
	_begin([a], [foe])
	mgr._grant_shield(a, 40, a)
	_hit(a, foe, 25)
	# Item shields + Mana Shield are always the holder's own items: the tap is
	# handed the split directly (GearPassives layers need real gear to exist).
	mgr.recap_tap.on_shield_hit(a, 30, 0)
	a.current_shield += 60                 # a grant with no source hook at all
	_hit(a, foe, 70)
	var snap := mgr.recap_tap.snapshot()
	_check(_prot(snap, a)["protect_self"] == 25 + 30 + 15, "self: 25 own pool + 30 own items + 15 left of its pool shield")
	_check(int(snap["protect_unattributed"]) == 55, "the unhooked 60: 55 absorbed, credited to nobody")
	_check(a.current_hp == 1000 and a.current_shield == 5, "combat itself untouched (5 shield left)")
	_free([a, foe])

func _test_pool_wipe_and_enemy_grant() -> void:
	print("[pool wiped outside a hit, enemy-sourced grant]")
	var a := _hero(UnitBase.UnitClass.SHEILDOR)
	var b := _hero(UnitBase.UnitClass.NEMI)
	var c := _hero(UnitBase.UnitClass.SHAUNA)
	var foe := _foe()
	_begin([a, b, c], [foe])
	mgr._grant_shield(c, 80, a)
	c.current_shield = 0                   # e.g. Khagan possession / a phase change
	mgr._grant_shield(c, 30, b)
	_hit(c, foe, 30)
	mgr._grant_shield(c, 40, foe)          # an enemy's shield on a hero
	_hit(c, foe, 40)
	var snap := mgr.recap_tap.snapshot()
	_check(_prot(snap, a)["protect_out"] == 0, "a wiped shield earns its caster nothing")
	_check(_prot(snap, b)["protect_out"] == 30, "the grant after the wipe is credited (30)")
	_check(int(snap["protect_unattributed"]) == 40, "an enemy-supplied shield is unattributed, not a hero's")
	_free([a, b, c, foe])

func _test_summons() -> void:
	print("[summons roll into their owner once]")
	var owner := _hero(UnitBase.UnitClass.NEMI)
	var c := _hero(UnitBase.UnitClass.SHAUNA)
	var s := _hero(UnitBase.UnitClass.RIOT)
	s.is_summoned = true
	s.summon_owner = owner
	var foe := _foe()
	_begin([owner, c, s], [foe])
	mgr._grant_shield(c, 50, s)            # the summon shields an ally
	_hit(c, foe, 50)
	mgr._grant_shield(s, 20, owner)        # the owner shields its own summon
	_hit(s, foe, 20)
	var snap := mgr.recap_tap.snapshot()
	_check(_prot(snap, owner)["protect_out"] == 50, "summon's shield on an ally credits the owner (50)")
	_check(_prot(snap, owner)["protect_self"] == 20, "owner's shield on its own summon is self-protection (20)")
	_check(not snap["heroes"].has(s.get_instance_id()), "a summon never gets a row of its own")
	_free([owner, c, s, foe])

# ── defeats ──────────────────────────────────────────────────────────────────
func _test_defeats() -> void:
	print("[enemy defeats by type]")
	var h := _hero(UnitBase.UnitClass.SHAUNA)
	var g1 := _foe(10)
	var g2 := _foe(10)
	var g3 := _foe(10)
	g3.is_summoned = true
	var boss := _foe(10, "goblin")
	boss.is_boss = true
	boss.set_meta("sprite_folder", "khagan_phase1")
	_begin([h], [g1, g2, g3, boss])
	for g in [g1, g2, g3, boss]:
		mgr.recap_tap.on_enemy_defeat(g)
	var snap := mgr.recap_tap.snapshot()
	mgr.recap_tap.on_enemy_defeat(g1)       # after the whistle
	var gob: Dictionary = {}
	var kh: Dictionary = {}
	for d in snap["defeats"]:
		if d["key"] == RecapFightTap.enemy_type_key(g1): gob = d
		if d["key"] == "khagan_phase1": kh = d
	_check(int(gob.get("n", 0)) == 3 and int(gob.get("summoned", 0)) == 1, "3 goblins, 1 of them summoned")
	_check(bool(kh.get("boss", false)) and int(kh.get("n", 0)) == 1, "boss tallied under its own type")
	_check(int(snap["defeat_total"]) == 4 and int(snap["summoned_total"]) == 1, "total 4 (1 summoned)")
	_check(not mgr.recap_tap.is_open(), "a closed fight ignores a late kill")
	var gk := RecapFightTap.enemy_type_key(g1)
	_check(snap["order"] == [gk, gk, gk, "khagan_phase1"], "the kill order is recorded as it happened")
	# The order is bounded; counts stay exact past the cap.
	_begin([h], [])
	var many: Array = []
	for _i in range(RecapFightTap.MAX_ORDER + 25):
		var g := _foe(10)
		many.append(g)
		mgr.recap_tap.on_enemy_defeat(g)
	var big := mgr.recap_tap.snapshot()
	_check((big["order"] as Array).size() == RecapFightTap.MAX_ORDER and int(big["defeat_total"]) == RecapFightTap.MAX_ORDER + 25,
		"kill order capped at %d, defeat count still exact (%d)" % [RecapFightTap.MAX_ORDER, int(big["defeat_total"])])
	var capped := RunRecap.create("cap")
	capped.finalise_fight({"node_id": "x", "round": 1, "won": true}, {}, big, {}, [])
	_check(capped.kill_order(0).size() == RecapFightTap.MAX_ORDER + 25, "the parade still gets one sprite per defeat")
	_free(many)
	_free([h, g1, g2, g3, boss])

# ── combat parity ────────────────────────────────────────────────────────────
func _test_instrumentation_parity() -> void:
	print("[instrumentation does not change combat]")
	var results: Array = []
	for open in [true, false]:
		var a := _hero(UnitBase.UnitClass.SHEILDOR)
		var c := _hero(UnitBase.UnitClass.SHAUNA)
		var foe := _foe()
		_begin([a, c], [foe])
		if not open:
			mgr.recap_tap.snapshot()          # closes it: hooks become no-ops
		mgr._grant_shield(c, 90, a)
		_hit(c, foe, 60)
		c.heal(500, true, null, a)
		_hit(c, foe, 75)
		mgr._grant_shield(c, 10, c)
		_hit(c, foe, 5)
		results.append([c.current_hp, c.current_shield, a.current_hp, foe.current_hp,
			c.effective_armor(), c.effective_magic_resist()])
		mgr.recap_tap.snapshot()
		_free([a, c, foe])
	_check(results[0] == results[1], "HP / shields / effective stats identical with the tap open or closed %s" % str(results[0]))

# ── damage breakdown ─────────────────────────────────────────────────────────
# Every source x type cell through the REAL take_damage, tagged the way the
# manager tags it. Expected values are the foe's actual HP loss per hit, so the
# test does not depend on damage formulas.
func _dealt(foe: UnitBase, fn: Callable) -> int:
	var before := foe.current_hp
	fn.call()
	return before - foe.current_hp

func _test_damage_split() -> void:
	print("[damage breakdown: auto / skill / ult / DoT / summon / passive / other x physical / magic / true]")
	var a := _hero(UnitBase.UnitClass.SHAUNA)
	var s := _hero(UnitBase.UnitClass.RIOT)
	s.is_summoned = true
	s.summon_owner = a
	var foe := _foe()
	_begin([a, s], [foe])
	var T := RecapFightTap.TYPES
	var want: Array = []
	want.resize(RecapFightTap.SOURCES * T)
	want.fill(0)
	a.gear_basic_hit = true
	want[RecapFightTap.SRC_AUTO * T + RecapFightTap.TYPE_PHYS] += _dealt(foe, func(): foe.take_damage(120, UnitBase.Element.NORMAL, a))
	want[RecapFightTap.SRC_AUTO * T + RecapFightTap.TYPE_MAGIC] += _dealt(foe, func(): foe.take_damage(30, UnitBase.Element.NORMAL, a, false, 0, true))
	a.gear_basic_hit = false
	a.recap_action = 1
	want[RecapFightTap.SRC_SKILL * T + RecapFightTap.TYPE_MAGIC] += _dealt(foe, func(): foe.take_damage(200, UnitBase.Element.NORMAL, a, false, 0, true))
	a.recap_action = 2
	want[RecapFightTap.SRC_ULT * T + RecapFightTap.TYPE_TRUE] += _dealt(foe, func(): foe.take_damage(300, UnitBase.Element.NORMAL, a, true))
	want[RecapFightTap.SRC_ULT * T + RecapFightTap.TYPE_PHYS] += _dealt(foe, func(): foe.take_damage(70, UnitBase.Element.NORMAL, a))
	a.recap_action = 0
	mgr.recap_tap.in_dot = true
	want[RecapFightTap.SRC_DOT * T + RecapFightTap.TYPE_TRUE] += _dealt(foe, func(): foe.take_damage(15, UnitBase.Element.NORMAL, a, true))
	mgr.recap_tap.in_dot = false
	s.gear_basic_hit = true
	want[RecapFightTap.SRC_SUMMON * T + RecapFightTap.TYPE_PHYS] += _dealt(foe, func(): foe.take_damage(40, UnitBase.Element.NORMAL, s))
	s.gear_basic_hit = false
	want[RecapFightTap.SRC_OTHER * T + RecapFightTap.TYPE_PHYS] += _dealt(foe, func(): foe.take_damage(25, UnitBase.Element.NORMAL, a))
	# A passive's damage; a skill hit that triggers it stays the skill's.
	mgr.recap_tap.in_passive = true
	want[RecapFightTap.SRC_PASSIVE * T + RecapFightTap.TYPE_MAGIC] += _dealt(foe, func(): foe.take_damage(45, UnitBase.Element.NORMAL, a, false, 0, true))
	a.recap_action = 1
	want[RecapFightTap.SRC_SKILL * T + RecapFightTap.TYPE_MAGIC] += _dealt(foe, func(): foe.take_damage(20, UnitBase.Element.NORMAL, a, false, 0, true))
	a.recap_action = 0
	mgr.recap_tap.in_passive = false
	# A delayed-hit queue named for this hero's class files under that ability;
	# one named for another class does not.
	mgr.recap_tap.set_ambient(a.unit_class, 2)
	want[RecapFightTap.SRC_ULT * T + RecapFightTap.TYPE_MAGIC] += _dealt(foe, func(): foe.take_damage(55, UnitBase.Element.NORMAL, a, false, 0, true))
	mgr.recap_tap.set_ambient(UnitBase.UnitClass.NEMI if a.unit_class != UnitBase.UnitClass.NEMI else UnitBase.UnitClass.RIOT, 1)
	want[RecapFightTap.SRC_OTHER * T + RecapFightTap.TYPE_PHYS] += _dealt(foe, func(): foe.take_damage(12, UnitBase.Element.NORMAL, a))
	mgr.recap_tap.clear_ambient()
	_hit(a, foe, 10)                          # damage TAKEN is never in anyone's breakdown
	var nonzero := 0
	for v in want:
		nonzero += 1 if int(v) > 0 else 0
	_check(nonzero == 10, "the fixture lands damage in 10 distinct cells (%d)" % nonzero)
	var rep := mgr.recorder.snapshot(true, [])
	var snap := mgr.recap_tap.snapshot()
	var got: Array = snap["split"].get(a.get_instance_id(), [])
	_check(got == want, "every hit filed under its source and type %s" % str(got))
	_check(not snap["split"].has(s.get_instance_id()), "a summon's damage is its owner's, in the Summons row")
	var sum := 0
	for v in got:
		sum += int(v)
	var dealt := -1
	for h in rep["heroes"]:
		if int(h["id"]) == a.get_instance_id():
			dealt = int(h["dealt_hp"])
	_check(sum == dealt, "the breakdown sums to the report's Damage dealt (%d = %d)" % [sum, dealt])
	# Into the run record, and back out of a save.
	var recap := RunRecap.create("smoke-split")
	var ids := _uids(recap, [a])
	var uid: int = ids[a.get_instance_id()]
	recap.finalise_fight({"node_id": "b0r1c0", "round": 1, "type": RunMap.NodeType.BATTLE, "won": true}, rep, snap, ids, [uid])
	var ds := recap.damage_split(uid, 0)
	_check(ds["cells"] == want and int(ds["unsplit"]) == 0, "RunRecap.damage_split returns the stored cells")
	_check(String(recap.hero(uid).get("skill", "")) == String(a.skill_name) and String(recap.hero(uid).get("ult", "")) == String(a.ultimate_name),
		"the hero's skill / ultimate names are kept for the breakdown's row labels")
	var back := RunRecap.from_dict(str_to_var(var_to_str(recap.to_dict())))
	_check(back != null and back.damage_split(uid, 0)["cells"] == want, "the breakdown survives a save round trip")
	# A fight recorded before the breakdown existed is reported apart, never spread.
	var old: Dictionary = back.fights[0].duplicate(true)
	old.erase("dmg_split")
	back.fights.append(old)
	old["key"] = "legacy"
	old["round"] = 2
	var d := RunRecap.from_dict(str_to_var(var_to_str(back.to_dict())))
	var ds2 := d.damage_split(uid, 1)
	_check(ds2["cells"] == want and int(ds2["unsplit"]) == dealt and ds2["unsplit_rounds"] == [2],
		"an older fight without a breakdown is 'not broken down', not guessed (%d)" % int(ds2["unsplit"]))
	var d2 := RunRecap.from_dict(str_to_var(var_to_str(d.to_dict())))
	_check(d2 != null and d2.fights[1]["dmg_split"] == null and d2.damage_split(uid, 1)["unsplit"] == dealt,
		"...and stays that way through a second save / resume")
	# A record written with the original 6 sources (before Passive) still reads.
	var short_row: Array = [uid]
	for i in range(6 * RecapFightTap.TYPES):
		short_row.append(int(want[i]))
	d2.fights[0]["dmg_split"] = [short_row]
	var ds3 := d2.damage_split(uid, 0)
	_check((ds3["cells"] as Array).slice(0, 6 * RecapFightTap.TYPES) == want.slice(0, 6 * RecapFightTap.TYPES)
		and int(ds3["cells"][RecapFightTap.SRC_PASSIVE * RecapFightTap.TYPES]) == 0,
		"a row written before the Passive source existed still reads (Passive 0)")
	_free([a, s, foe])

# ── run record ───────────────────────────────────────────────────────────────
# A real fight through the real recorder and tap, frozen for RunRecap.
func _real_fight(heroes: Array, foe: UnitBase, won: bool) -> Array:
	_begin(heroes, [foe])
	mgr._grant_shield(heroes[0], 30, heroes[0])
	_hit(heroes[0], foe, 50)                      # 30 shield + 20 HP
	heroes[0].heal(500, false)                    # self-sustain: 20 lands, 480 overheal
	_hit(heroes[0], foe, 40)
	if heroes.size() > 1:
		heroes[0].heal(100, false, null, heroes[1])   # ally heal: 40 lands, 60 overheal
	_hit(foe, heroes[0], 300)
	mgr.recorder.now = 12.5
	return [mgr.recorder.snapshot(won, [foe] if not won else []), mgr.recap_tap.snapshot()]

func _uids(recap: RunRecap, units: Array) -> Dictionary:
	var out := {}
	for u in units:
		out[u.get_instance_id()] = recap.ensure_uid(u)
	return out

func _test_fight_finalisation() -> void:
	print("[exact-once finalisation, replay, immutability, healing metric]")
	var recap := RunRecap.create("smoke-run")
	var a := _hero(UnitBase.UnitClass.SHAUNA)
	var b := _hero(UnitBase.UnitClass.NEMI)
	var foe := _foe()
	var ids := _uids(recap, [a, b])
	var fz := _real_fight([a, b], foe, true)
	var ctx := {"node_id": "b0r1c0", "round": 1, "biome": 0, "type": RunMap.NodeType.BATTLE, "tier": 0, "won": true}
	_check(recap.finalise_fight(ctx, fz[0], fz[1], ids, ids.values()), "first finalise records the fight")
	_check(not recap.finalise_fight(ctx, fz[0], fz[1], ids, ids.values()), "the same battle is refused a second time")
	_check(recap.fights.size() == 1, "exactly one entry")
	var row_a: Array = recap.fights[0]["rows"][0]
	var rep_a: Dictionary = fz[0]["heroes"][0]
	_check(row_a[RunRecap.M_DAMAGE + 1] == int(rep_a["dealt_hp"]) and row_a[1] == 300, "damage = the recorder's dealt_hp (300)")
	_check(row_a[RunRecap.M_HEALING + 1] == int(rep_a["heal_out"]) + int(rep_a["heal_self"]),
		"healing = ally + self effective healing (%d)" % row_a[2])
	_check(int(rep_a["overheal"]) == 480 and row_a[2] == 20, "self-heal counts, overheal excluded (20 of 500)")
	var row_b: Array = recap.fights[0]["rows"][1]
	_check(row_b[2] == 40, "ally heal credits the healer: 40 of 100 landed")
	_check(row_a[RunRecap.M_PROTECTION + 1] == 30, "protection = own shield absorbed (30)")
	# Immutability: scribbling over the source snapshot changes nothing stored.
	fz[0]["heroes"][0]["dealt_hp"] = 999999
	fz[1]["heroes"].clear()
	_check(recap.fights[0]["rows"][0][1] == 300, "stored entry is a copy, not a reference")
	# Replay of the same encounter after a resume replaces it.
	var fz2 := _real_fight([a, b], foe, true)
	_check(recap.finalise_fight(ctx, fz2[0], fz2[1], ids, ids.values()) and recap.fights.size() == 1,
		"a replay of the same encounter replaces, never duplicates")
	_free([a, b, foe])

func _mk_report(rows: Array, won: bool, dur: float, deaths := {}) -> Dictionary:
	# Minimal BattleRecorder-shaped snapshot for arithmetic tests (labelled synthetic).
	var heroes: Array = []
	for r in rows:
		var d: Array = deaths.get(r[0], [0, true])
		heroes.append({"id": r[0], "name": "SYNTHETIC-%d" % r[0], "cls": 0, "level": 1,
			"dealt_hp": r[1], "dealt_shield": 0, "dealt_by_summons": 0, "taken_hp": 0, "taken_shield": 0,
			"heal_out": r[2], "heal_self": 0, "overheal": 0, "deaths": d[0], "revives": 0, "ults": 0,
			"hp_end": 10, "max_hp_end": 10, "survived": d[1], "alive_time": dur, "intervals": [[0.0, dur]]})
	return {"won": won, "duration": dur, "heroes": heroes, "events": [], "team": {},
		"enemies": {"seen": 3, "remaining": 0 if won else 1, "hp": 0, "max_hp": 0, "survivors": []}}

func _mk_tap(token: String, prot: Dictionary, defeats: Array = [], order: Array = []) -> Dictionary:
	var hs := {}
	for k in prot.keys():
		hs[k] = {"uid": 0, "protect_out": prot[k], "protect_self": 0}
	var total := 0
	for d in defeats:
		total += int(d["n"])
	return {"token": token, "heroes": hs, "protect_unattributed": 0, "defeats": defeats,
		"defeat_total": total, "summoned_total": 0, "order": order}

func _test_cumulative_and_history() -> void:
	print("[prefix totals, late joins, deaths/revivals, skipped waves]")
	var recap := RunRecap.create("smoke-run-2")
	# instance ids 9001.. stand in for heroes; uid_by_id maps them.
	var ids := {9001: 1, 9002: 2, 9003: 3}
	for k in ids.keys():
		recap._touch_hero(ids[k], "SYNTHETIC-%d" % ids[k], 0, 0)
	recap.next_uid = 4
	var gob := {"key": "goblin", "name": "Goblin", "portrait": "", "n": 4, "summoned": 1, "boss": false, "elite": false}
	recap.note_node({"node_id": "b0r1c0", "round": 1, "biome": 0, "type": RunMap.NodeType.BATTLE}, true)
	recap.finalise_fight({"node_id": "b0r1c0", "round": 1, "type": RunMap.NodeType.BATTLE, "won": true},
		_mk_report([[9001, 100, 10], [9002, 50, 0]], true, 20.0), _mk_tap("t1", {9001: 5}, [gob]), ids, [1, 2])
	recap.note_node({"node_id": "b0r2c3", "round": 2, "biome": 0, "type": RunMap.NodeType.EVENT}, false)
	recap.finalise_fight({"node_id": "b0r3c1", "round": 3, "type": RunMap.NodeType.BATTLE, "won": true},
		_mk_report([[9001, 7, 0], [9002, 3, 2], [9003, 40, 0]], true, 15.0, {9002: [1, true]}),
		_mk_tap("t2", {9003: 9}), ids, [1, 2, 3])
	var rat := {"key": "rat", "name": "Rat", "portrait": "", "n": 1, "summoned": 0, "boss": false, "elite": false}
	recap.finalise_fight({"node_id": "b0r4c0", "round": 4, "type": RunMap.NodeType.ELITE, "won": false},
		_mk_report([[9001, 1, 1], [9003, 2, 0]], false, 30.0, {9001: [1, false], 9003: [1, false]}),
		_mk_tap("t3", {}, [gob, rat], ["goblin", "rat", "goblin", "goblin", "goblin"]), ids, [1, 2, 3], [2])
	var p := recap.prefix_totals()
	_check(p.size() == 3, "one prefix vector per fight")
	_check(p[0][1] == [100, 10, 5] and p[1][1] == [107, 10, 5] and p[2][1] == [108, 11, 5], "hero 1 cumulative exact")
	_check(not p[0].has(3) and p[1][3] == [40, 0, 9] and p[2][3] == [42, 0, 9], "late joiner starts at its first fight")
	_check(recap.hero(3)["first_round"] == 3 and recap.hero(3)["first_fight"] == 3, "late joiner: joined wave 3")
	_check(recap.hero(2)["last_round"] == 4 and recap.hero(2)["first_fight"] == 1,
		"a benched hero stays on the roster (last seen wave 4)")
	_check(recap.fights[1]["revived"] == [2] and recap.fights[2]["fallen"] == [1, 3], "revived vs fallen per fight")
	var order := recap.fight_route_order()
	_check(order.size() == 3 and recap.route.size() == 4 and recap.route[1]["kind"] == "node"
		and recap.route[1]["round"] == 2, "event at wave 2 kept as a route stop; fights keep real waves 1/3/4")
	_check(recap.defeat_total() == 9 and recap.defeat_tally()[0]["n"] == 8 and recap.defeat_tally()[0]["summoned"] == 2,
		"defeat tally sums the fights (9 = 8 goblins, 2 summoned, + 1 rat)")
	_check(recap.fighting_heroes().map(func(h): return h["uid"]) == [1, 2, 3], "stable roster order")
	_check(recap.kill_order(2) == ["goblin", "rat", "goblin", "goblin", "goblin"], "kill order kept per fight")
	_check(recap.kill_order(0) == ["goblin", "goblin", "goblin", "goblin"], "no recorded order: grouped by type, count-exact")
	var h2: Dictionary = recap.hero(2)
	_check(RecapHeroChart.life_state(h2, recap.fights[2])["kind"] == "bench", "a benched hero reads Bench, from the record")
	var f_old: Dictionary = recap.fights[2].duplicate(true)
	f_old.erase("bench")
	_check(RecapHeroChart.life_state(h2, f_old)["kind"] == "out",
		"an older record without the bench says 'Not fielded', never a guessed Bench")
	_check(RecapHeroChart.life_state(recap.hero(1), recap.fights[2])["kind"] == "fell", "a hero who fell reads Fell")

func _test_terminal_and_persistence() -> void:
	print("[terminal result, save/resume parity, rebuild fidelity]")
	var recap := RunRecap.create("smoke-run-3")
	var a := _hero(UnitBase.UnitClass.SHAUNA)
	var b := _hero(UnitBase.UnitClass.DOC)
	var foe := _foe()
	var ids := _uids(recap, [a, b])
	# fight 1: won; fight 2: lost with a death
	var f1 := _real_fight([a, b], foe, true)
	recap.finalise_fight({"node_id": "b0r1c1", "round": 1, "type": RunMap.NodeType.BATTLE, "tier": 1, "won": true},
		f1[0], f1[1], ids, ids.values())
	_begin([a, b], [foe])
	mgr.recorder.now = 3.0
	_hit(a, foe, 5000)
	mgr.recorder.now = 7.25
	var f2 := [mgr.recorder.snapshot(false, [foe]), mgr.recap_tap.snapshot()]
	var key2 := RunRecap.encounter_key("b0r2c0", 2)
	recap.finalise_fight({"node_id": "b0r2c0", "round": 2, "type": RunMap.NodeType.BOSS, "tier": 2, "won": false},
		f2[0], f2[1], ids, ids.values())
	recap.finalise_run("defeat", 2, 7, 3)
	_check(recap.is_final() and recap.outcome == "defeat", "terminal defeat recorded")
	_check(not recap.finalise_fight({"node_id": "x", "round": 3, "won": true}, f1[0], {"token": "late"}, ids, []),
		"nothing is added after the run is final")
	var rebuilt := recap.report_for(key2)
	_check(not rebuilt.is_empty() and rebuilt["takeaway"] == f2[0]["takeaway"],
		"rebuilt report says the same takeaway: \"%s\"" % rebuilt.get("takeaway", ""))
	_check(rebuilt["heroes"].size() == f2[0]["heroes"].size()
		and int(rebuilt["heroes"][0]["taken_hp"]) == int(f2[0]["heroes"][0]["taken_hp"])
		and int(rebuilt["heroes"][0]["id"]) == ids[a.get_instance_id()], "rebuilt hero rows match, keyed by uid")
	var deaths: Array = rebuilt["events"].filter(func(e): return e["kind"] == "death")
	_check(deaths.size() == 1 and int(deaths[0]["hero"]) == int(rebuilt["heroes"][0]["id"]),
		"death marker lines up with its hero lane")
	_check(recap.report_for("no-such-fight").is_empty(), "an unknown fight opens nothing")

	# var_to_str (run save) round trip
	var s1 := var_to_str(recap.to_dict())
	var back := RunRecap.from_dict(str_to_var(s1))
	_check(back != null and var_to_str(back.to_dict()) == s1, "run-save round trip is exact")
	# JSON (terminal file) round trip, through the real atomic writer
	var path := "user://_run_recap_smoke_terminal.json"
	_check(RunRecap.save_terminal(recap, path), "terminal file written atomically")
	_check(not FileAccess.file_exists(path + ".tmp"), "no temp file left behind")
	var loaded := RunRecap.load_terminal(path)
	_check(loaded != null and loaded.outcome == "defeat" and loaded.final_round == 2, "terminal file loads")
	if loaded != null:
		_check(loaded.prefix_totals() == recap.prefix_totals(), "prefix totals survive JSON")
		_check(JSON.stringify(loaded.report_for(key2)) == JSON.stringify(recap.report_for(key2)),
			"historical report survives JSON unchanged")
		_check(JSON.stringify(loaded.defeat_tally()) == JSON.stringify(recap.defeat_tally()), "defeat tally survives JSON")
	RunRecap.clear_terminal(path)
	_check(not FileAccess.file_exists(path), "terminal file cleared")
	_check(RunRecap.from_dict({"version": 99}) == null and RunRecap.from_dict("junk") == null,
		"unknown versions / junk are rejected, not misread")
	var won := RunRecap.create("smoke-win")
	won.finalise_run("victory", 100, 1, 1)
	_check(won.outcome == "victory" and won.fights.is_empty(), "victory with zero recorded fights is representable")
	_free([a, b, foe])

func _test_legacy_partial() -> void:
	print("[legacy save: partial history]")
	var r := RunRecap.from_legacy("legacy-run", 12)
	_check(r.is_partial() and r.history_before_unavailable and r.coverage_from_round == 12,
		"pre-recorder history is UNAVAILABLE from wave 12, not zero")
	_check(r.prefix_totals().is_empty() and r.defeat_total() == 0 and r.fights.is_empty(),
		"no invented fights before coverage")
	var fresh := RunRecap.create("fresh-run")
	_check(not fresh.is_partial(), "a run recorded from wave 1 is complete")

# ── bounds ───────────────────────────────────────────────────────────────────
func _test_bounded_serialization() -> void:
	print("[bounded worst case: 100 fights x 20 heroes, live-recorder caps]")
	var recap := RunRecap.create("SYNTHETIC-worst-case")
	var ids := {}
	for i in range(20):
		ids[50000 + i] = i + 1
		recap._touch_hero(i + 1, "SYNTHETIC hero %02d" % i, i % 26, 0)
	recap.next_uid = 21
	for f in range(100):
		var rep := _mk_report([], f % 7 != 6, 180.0)
		for i in range(20):
			rep["heroes"].append({"id": 50000 + i, "name": "SYNTHETIC hero %02d" % i, "cls": i % 26, "level": 30,
				"dealt_hp": 123456, "dealt_shield": 4567, "dealt_by_summons": 890, "taken_hp": 98765,
				"taken_shield": 6543, "heal_out": 54321, "heal_self": 4321, "overheal": 7654,
				"deaths": 2, "revives": 1, "ults": 4, "hp_end": 1234, "max_hp_end": 5678, "survived": true,
				"alive_time": 170.25, "intervals": [[0.0, 61.37], [92.11, 180.0]]})
		var evs: Array = []
		for i in range(160):
			evs.append({"t": 1.11 * i, "kind": ["death", "revive", "ultimate", "heal"][i % 4], "hero": 50000 + i % 20,
				"name": "x", "by": "SYNTHETIC Very Long Enemy Name", "ability": "SYNTHETIC Ultimate Name",
				"target": "SYNTHETIC hero", "amount": 1000 + i})
		rep["events"] = evs
		var surv: Array = []
		for i in range(60):
			surv.append({"name": "SYNTHETIC enemy %d" % i, "portrait": "res://assets/using/enemies/normal/goblin.png",
				"hp": 500, "max_hp": 900, "start_max_hp": 900, "summoned": i % 5 == 0})
		rep["enemies"] = {"seen": 70, "remaining": 60, "hp": 30000, "max_hp": 54000, "survivors": surv}
		var defeats: Array = []
		# 43 x 12 = 516 defeats per fight: past the tap's 512-entry kill-order cap,
		# so the measured size includes a saturated kill order for every fight.
		var order: Array = []
		for t in range(12):
			defeats.append({"key": "type_%d" % (t + f % 40), "name": "SYNTHETIC type", "portrait": "", "n": 43,
				"summoned": 1, "boss": t == 0, "elite": false})
		for i in range(RecapFightTap.MAX_ORDER):
			order.append("type_%d" % (i % 12 + f % 40))
		recap.note_node({"node_id": "b%dr%dc0" % [f / 10, f % 10], "round": f + 1, "type": RunMap.NodeType.EVENT}, false)
		recap.finalise_fight({"node_id": "b%dr%dc1" % [f / 10, f % 10], "round": f + 1, "biome": f / 10,
				"type": RunMap.NodeType.BOSS if f % 10 == 9 else RunMap.NodeType.BATTLE, "tier": f % 3, "won": true},
			rep, _mk_tap("w%d" % f, {50000: 777, 50001: 333}, defeats, order), ids, ids.values())
	_check(recap.fights.size() == 100 and recap.route.size() == 200, "all 100 fights and 200 stops kept")
	var t0 := Time.get_ticks_usec()
	var vs := var_to_str(recap.to_dict())
	var t_var := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var js := JSON.stringify(recap.to_dict())
	var t_json := (Time.get_ticks_usec() - t0) / 1000.0
	print("  MEASURED worst case: run-save block %d bytes (var_to_str %.1f ms), terminal JSON %d bytes (%.1f ms)"
		% [vs.length(), t_var, js.length(), t_json])
	_check(vs.length() < 3_000_000 and js.length() < 3_000_000, "worst case stays under the 3 MB budget")
	var key := RunRecap.encounter_key("b0r0c1", 1)
	var rb := recap.report_for(key)
	var notes: Array = rb.get("reduced_detail", [])
	_check(notes.size() >= 2, "reduced marker detail is disclosed (%d notes)" % notes.size())
	_check(rb["enemies"]["remaining"] == 60 and rb["enemies"]["survivors"].size() == RunRecap.MAX_STORED_SURVIVORS,
		"survivor count stays exact while pictures are capped")
	var deaths := 0
	for h in rb["heroes"]:
		deaths += int(h["deaths"])
	_check(deaths == 40, "per-hero death counts stay exact (40) even with markers capped")
	_check(recap.defeat_total() == 51600, "every defeat counted (100 x 516)")
	_check(recap.kill_order(50).size() == 516, "the parade gets every defeat even past the order cap")
	_check(recap.final_totals()[1] == [12345600, 5864200, 77700], "aggregates exact at the end of the run")
