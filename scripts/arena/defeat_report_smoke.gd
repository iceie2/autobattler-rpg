extends Node
# ══════════════════════════════════════════════════════════════════════════════
# DEFEAT REPORT SMOKE (2026-10-07) - the final-battle recorder + the infographic.
#
# Drives the REAL UnitBase.take_damage / heal / die through a real
# AutoBattleManager, then checks the frozen report and the screen built from it:
#   * shielded hits (partial + full), overkill, unattributed damage, summons
#   * effective healing vs overheal, self-heal vs ally heal, credit param
#   * early death, revival => several alive intervals
#   * simulation time: pause freezes it, time_scale scales it, recorder follows
#   * next-battle reset (nothing from fight 1 leaks into fight 2)
#   * run totals and final-battle numbers stay separate on the screen
#   * synthetic solo / zero-damage / crowded reports build without error and
#     same-timestamp timeline markers stay apart
#
# Run:  godot --headless res://scenes/defeat_report_smoke.tscn
# Exit 0 = pass. Touches no save file (no Progression / RunHistory involved).
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
	mgr = AutoBattleManager.new()
	add_child(mgr)
	mgr.skill_effect_container = Node2D.new()
	add_child(mgr.skill_effect_container)

	_test_damage_and_shields()
	_test_healing()
	_test_deaths_and_intervals()
	_test_simulation_time()
	_test_reset_between_battles()
	await _test_screen_separation()
	await _test_synthetic_layouts()

	print("DEFEAT_REPORT_SMOKE: %s" % ("ALL PASS" if _fails.is_empty()
		else "%d FAILED -> %s" % [_fails.size(), ", ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)

# ── helpers ──────────────────────────────────────────────────────────────────
func _hero(cls: int) -> UnitBase:
	var u: UnitBase = UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
	add_child(u)
	u.battle_manager = mgr
	u.max_hp = 1000
	u.current_hp = 1000
	u.resistance = 0
	u.magic_resist = 0
	u.died.connect(mgr._on_ally_died.bind(u))   # the wiring collect_units does
	return u

func _foe(hp := 100000) -> UnitBase:
	var u: UnitBase = EnemyFactory.create_by_type("goblin")
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
	mgr.recorder.begin(players, enemies)

func _row(report: Dictionary, unit: UnitBase) -> Dictionary:
	for h in report["heroes"]:
		if h["id"] == unit.get_instance_id():
			return h
	return {}

# True damage skips armour/element maths, so recorded numbers can be compared
# with exact inputs.
func _true_hit(victim: UnitBase, attacker, amount: int) -> void:
	victim.take_damage(amount, UnitBase.Element.NORMAL, attacker, true)

# ── damage + shields ─────────────────────────────────────────────────────────
func _test_damage_and_shields() -> void:
	print("damage + shields:")
	var tank := _hero(UnitBase.UnitClass.SHEILDOR)
	var dps := _hero(UnitBase.UnitClass.BLOODHOUND)
	var foe := _foe()
	_begin([tank, dps], [foe])

	# Partial shield: 120 true damage into a 50 shield -> 50 soaked, 70 HP lost.
	tank.current_shield = 50
	_true_hit(tank, foe, 120)
	var snap := mgr.recorder.snapshot(false, [foe])
	var t := _row(snap, tank)
	_check(t["taken_shield"] == 50 and t["taken_hp"] == 70,
		"partial shield: 50 absorbed + 70 HP (got %d / %d)" % [t["taken_shield"], t["taken_hp"]])
	_check(tank.current_hp == 930, "report HP matches the unit's real HP loss")

	# Fully absorbed hit: no HP lost, all soaked.
	_begin([tank, dps], [foe])
	tank.current_shield = 500
	_true_hit(tank, foe, 100)
	t = _row(mgr.recorder.snapshot(false, [foe]), tank)
	_check(t["taken_shield"] == 100 and t["taken_hp"] == 0, "fully shielded hit: 0 HP, 100 soaked")

	# Overkill: only the HP that existed counts.
	_begin([tank, dps], [foe])
	tank.current_shield = 0
	tank.current_hp = 30
	_true_hit(tank, foe, 100)
	t = _row(mgr.recorder.snapshot(false, [foe]), tank)
	_check(t["taken_hp"] == 30, "overkill excluded: lost 30, not 100 (got %d)" % t["taken_hp"])

	# Dealt: a hero hitting an enemy is credited HP only; enemy shield is separate.
	var foe2 := _foe(5000)
	_begin([tank, dps], [foe2])
	foe2.current_shield = 40
	_true_hit(foe2, dps, 100)
	var snap2 := mgr.recorder.snapshot(false, [foe2])
	var d := _row(snap2, dps)
	_check(d["dealt_hp"] == 60 and d["dealt_shield"] == 40,
		"dealt: 60 to HP, 40 into enemy shield (got %d / %d)" % [d["dealt_hp"], d["dealt_shield"]])
	_check(snap2["team"]["dealt_hp"] == 60, "team total is the sum of the rows")

	# No hero owner: DoT with a null source still counts as TAKEN, never as dealt.
	var dummy := _hero(UnitBase.UnitClass.NEMI)
	_begin([dummy], [foe2])
	dummy.take_damage(25, UnitBase.Element.NORMAL, null, true)
	var snap3 := mgr.recorder.snapshot(false, [foe2])
	_check(_row(snap3, dummy)["taken_hp"] == 25 and snap3["unattributed_taken"] == 25,
		"sourceless damage: taken by the hero, tallied as unattributed")

	_begin([dummy], [foe2])
	_true_hit(dummy, foe2, 10)
	var snap3b := mgr.recorder.snapshot(false, [foe2])
	_check(_row(snap3b, dummy)["taken_hp"] == 10 and snap3b["unattributed_taken"] == 0,
		"damage from a living enemy is attributed, not 'unattributed'")

	# Friendly fire never counts as dealt.
	var ally := _hero(UnitBase.UnitClass.JUNE)
	_begin([dummy, ally], [foe2])
	_true_hit(ally, dummy, 40)
	var snap4 := mgr.recorder.snapshot(false, [foe2])
	_check(_row(snap4, dummy)["dealt_hp"] == 0 and _row(snap4, ally)["taken_hp"] == 40,
		"friendly damage: taken by the victim, not dealt by the attacker")

	# Summons credit their owner.
	var owner := _hero(UnitBase.UnitClass.NECRO)
	var minion := _hero(UnitBase.UnitClass.NECRO)
	minion.is_summoned = true
	minion.summon_owner = owner
	_begin([owner], [foe2])
	_true_hit(foe2, minion, 33)
	var snap5 := mgr.recorder.snapshot(false, [foe2])
	var o := _row(snap5, owner)
	_check(o["dealt_hp"] == 33 and o["dealt_by_summons"] == 33, "summon damage credited to its owner")

# ── healing ──────────────────────────────────────────────────────────────────
func _test_healing() -> void:
	print("healing:")
	var healer := _hero(UnitBase.UnitClass.DOC)
	var patient := _hero(UnitBase.UnitClass.BLOODHOUND)
	var foe := _foe()
	_begin([healer, patient], [foe])
	patient.current_hp = 600

	# 150 offered, 400 missing -> all 150 lands, 0 wasted.
	patient.heal(150, true, null, healer)
	# 500 offered, 250 missing -> 250 lands, 250 wasted.
	patient.heal(500, true, null, healer)
	var snap := mgr.recorder.snapshot(false, [foe])
	var h := _row(snap, healer)
	_check(h["heal_out"] == 400, "effective healing = HP that landed (got %d)" % h["heal_out"])
	_check(h["overheal"] == 250, "overheal reported separately, not added to healing (got %d)" % h["overheal"])
	_check(_row(snap, patient)["healed_in"] == 400, "recipient's healed_in agrees")
	_check(snap["team"]["heal_out"] == 400, "team healing total is effective healing")

	# Self-heal (regen / lifesteal call heal() with no credit) is its own bucket.
	_begin([healer, patient], [foe])
	patient.current_hp = 500
	patient.heal(100, true)
	snap = mgr.recorder.snapshot(false, [foe])
	var p := _row(snap, patient)
	_check(p["heal_self"] == 100 and p["heal_out"] == 0, "self-heal separated from ally healing")

	# The `healer` argument (balance hook) is credited when `credit` is not given.
	_begin([healer, patient], [foe])
	patient.current_hp = 500
	patient.heal(60, true, healer)
	h = _row(mgr.recorder.snapshot(false, [foe]), healer)
	_check(h["heal_out"] == 60, "healer arg used as the credit fallback")

	# Healing a full-HP ally is all overheal and no healing.
	_begin([healer, patient], [foe])
	patient.current_hp = patient.max_hp
	patient.heal(80, true, null, healer)
	h = _row(mgr.recorder.snapshot(false, [foe]), healer)
	_check(h["heal_out"] == 0 and h["overheal"] == 80, "full-HP heal: 0 healing, all overheal")

# ── deaths, revivals, intervals ──────────────────────────────────────────────
func _test_deaths_and_intervals() -> void:
	print("deaths + intervals:")
	var early := _hero(UnitBase.UnitClass.NEMI)
	var steady := _hero(UnitBase.UnitClass.SHAUNA)
	var revived := _hero(UnitBase.UnitClass.RIOT)
	var foe := _foe()
	_begin([early, steady, revived], [foe])

	mgr.recorder.now = 0.4
	early.current_hp = 5
	_true_hit(early, foe, 50)       # dies at 0.4s
	mgr.recorder.now = 6.0
	revived.current_hp = 5
	_true_hit(revived, foe, 50)     # dies at 6.0
	mgr.recorder.now = 14.0
	revived.revive(0.5)
	mgr.recorder.on_revive(revived)   # back at 14.0
	mgr.recorder.now = 25.0
	revived.current_hp = 5
	_true_hit(revived, foe, 50)     # dies again at 25.0
	mgr.recorder.now = 40.0
	var snap := mgr.recorder.snapshot(false, [foe])

	var e := _row(snap, early)
	_check(is_equal_approx(e["alive_time"], 0.4) and e["deaths"] == 1,
		"early death: alive 0.4s (got %.2f)" % e["alive_time"])
	var s := _row(snap, steady)
	_check(is_equal_approx(s["alive_time"], 40.0) and s["survived"] and s["deaths"] == 0,
		"never-dead hero: alive the whole 40s")
	var r := _row(snap, revived)
	_check(r["intervals"].size() == 2, "revival => two alive intervals (got %d)" % r["intervals"].size())
	_check(is_equal_approx(r["alive_time"], 6.0 + 11.0) and r["deaths"] == 2 and r["revives"] == 1,
		"alive = 6 + 11 = 17s, not the first-death time (got %.2f)" % r["alive_time"])
	_check(not r["survived"], "hero down at the end is not 'survived'")
	var kinds: Array = []
	for ev in snap["events"]:
		kinds.append(ev["kind"])
	_check(kinds == ["death", "death", "revive", "death"], "events time-ordered: %s" % str(kinds))
	var tk: String = snap["takeaway"]
	_check(tk.contains("fell first at 0.4s"), "takeaway names the first fall: \"%s\"" % tk)

# ── simulation time ──────────────────────────────────────────────────────────
func _test_simulation_time() -> void:
	print("simulation time:")
	mgr.battle_active = true
	mgr.player_units = []
	mgr.enemy_units = []
	mgr.battle_elapsed = 0.0
	mgr.recorder.now = 0.0
	mgr.paused = true
	mgr.time_scale = 1.0
	mgr._process(1.0)
	_check(mgr.battle_elapsed == 0.0 and mgr.recorder.now == 0.0, "paused: simulation clock does not move")
	mgr.paused = false
	mgr.time_scale = 4.0
	mgr.battle_active = true     # an empty board ends the fight after each tick
	mgr._process(0.5)
	_check(is_equal_approx(mgr.battle_elapsed, 2.0) and is_equal_approx(mgr.recorder.now, 2.0),
		"4x: 0.5s of wall time = 2.0 simulation seconds")
	mgr.time_scale = 0.25
	mgr.battle_active = true
	mgr._process(1.0)
	_check(is_equal_approx(mgr.recorder.now, 2.25), "0.25x: 1s of wall time adds 0.25 simulation seconds")
	mgr.battle_active = false

# ── reset between battles ────────────────────────────────────────────────────
func _test_reset_between_battles() -> void:
	print("next-battle reset:")
	var hero := _hero(UnitBase.UnitClass.LORDEE)
	var foe := _foe()
	_begin([hero], [foe])
	mgr.recorder.now = 9.0
	_true_hit(foe, hero, 777)
	_true_hit(hero, foe, 111)
	var first := mgr.recorder.snapshot(false, [foe])
	_check(_row(first, hero)["dealt_hp"] == 777 and _row(first, hero)["taken_hp"] == 111, "fight 1 recorded")

	# Fight 2 on the SAME unit objects (heroes persist across rounds).
	_begin([hero], [foe])
	mgr.recorder.now = 3.0
	var second := mgr.recorder.snapshot(true, [])
	var h2 := _row(second, hero)
	_check(h2["dealt_hp"] == 0 and h2["taken_hp"] == 0 and second["events"].is_empty(),
		"fight 2 starts from zero (nothing carried over)")
	_check(is_equal_approx(second["duration"], 3.0) and second["won"], "fight 2 has its own duration/outcome")
	_check(first["duration"] == 9.0 and _row(first, hero)["dealt_hp"] == 777,
		"fight 1's frozen report is unaffected by fight 2")
	_check(second["takeaway"].begins_with("No damage"), "zero-damage fight: honest takeaway")
	# Not recording outside a fight.
	_true_hit(foe, hero, 5)
	var after := mgr.recorder.snapshot(true, [])
	_check(after["team"]["dealt_hp"] == 0, "a finished (inactive) recorder ignores late hits")

# ── the screen: run totals vs final battle ───────────────────────────────────
func _test_screen_separation() -> void:
	print("screen:")
	var hero := _hero(UnitBase.UnitClass.SHAUNA)
	var foe := _foe(4000)
	_begin([hero], [foe])
	mgr.recorder.now = 12.0
	_true_hit(foe, hero, 500)
	_true_hit(hero, foe, 200)
	mgr.recorder.now = 20.0
	hero.current_hp = 1
	_true_hit(hero, foe, 10)
	var report := mgr.recorder.snapshot(false, [foe])
	var summary := {"crystals": 9, "rounds_cleared": 12, "fell_on": 13, "enemies_defeated": 248,
		"biome": "Skyreach", "encounter": "Boss", "difficulty": "Brutal"}

	var go := GameOverScreen.new()
	add_child(go)
	go.show_defeat_report(summary, report)
	await get_tree().process_frame
	await get_tree().process_frame
	var labels: Array = []
	_collect_labels(go, labels)
	_check("Rounds cleared" in labels and "12" in labels, "run total: rounds cleared = 12")
	_check("Fell on round" in labels and "13" in labels, "the losing round is shown as 'fell on', not cleared")
	_check("248" in labels, "run total: enemies defeated (whole run)")
	_check(not ("Rounds survived" in labels), "no 'Rounds survived' wording")
	_check("500" in labels, "final-battle damage (500) appears on the hero card")
	var heading_idx := labels.find("RUN TOTALS")
	var battle_idx := labels.find("FINAL BATTLE")
	_check(heading_idx >= 0 and battle_idx > heading_idx, "RUN TOTALS and FINAL BATTLE are separate sections")
	# 248 (run) must not appear between FINAL BATTLE and the end as a fight stat.
	_check(labels.find("248") < battle_idx, "run kills sit in the run strip, before the final-battle section")
	go.queue_free()

# Visible labels only: the compact victory panel stays built (hidden) behind it.
func _collect_labels(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_collect_labels(c, out)

# ── synthetic layouts (never real results) ───────────────────────────────────
func _synthetic(heroes: int, enemies: int, zero: bool) -> Dictionary:
	var hs: Array = []
	var events: Array = []
	var dur := 90.0
	for i in range(heroes):
		var fell := 8.0 + i * 3.0 if i % 2 == 0 else -1.0
		var iv := [[0.0, fell if fell > 0.0 else dur]]
		var deaths := 1 if fell > 0.0 else 0
		if i == 1 and heroes > 2:
			iv = [[0.0, 20.0], [31.0, dur]]
			deaths = 1
			events.append({"t": 20.0, "kind": "death", "hero": 1000 + i, "name": "Hero %d" % i, "by": "Orc"})
			events.append({"t": 31.0, "kind": "revive", "hero": 1000 + i, "name": "Hero %d" % i})
		if fell > 0.0:
			events.append({"t": fell, "kind": "death", "hero": 1000 + i, "name": "Hero %d" % i, "by": ""})
		hs.append({"id": 1000 + i, "name": "Hero %d" % i, "cls": UnitBase.UnitClass.SHAUNA, "portrait": "",
			"level": 5 + i, "dealt_hp": 0 if zero else 1200 * (i + 1), "dealt_shield": 0, "dealt_by_summons": 0,
			"taken_hp": 0 if zero else 800 + 90 * i, "taken_shield": 0 if zero or i % 3 else 120,
			"heal_out": 0 if zero or i % 4 else 300, "heal_self": 0, "overheal": 0, "healed_in": 0,
			"intervals": iv, "deaths": deaths, "revives": 1 if (i == 1 and heroes > 2) else 0, "ults": 0,
			"alive_time": 0.0, "survived": fell < 0.0, "hp_end": 0, "max_hp_end": 1500})
		var at := 0.0
		for pair in iv:
			at += float(pair[1]) - float(pair[0])
		hs[i]["alive_time"] = at
	# Same-timestamp stack on one hero: three markers at exactly 15.0s.
	if heroes > 0:
		for kind in ["ultimate", "heal", "revive"]:
			events.append({"t": 15.0, "kind": kind, "hero": 1000, "name": "Hero 0", "ability": "Test Ult",
				"target": "Hero 1", "amount": 99})
	events.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var surv: Array = []
	for j in range(enemies):
		surv.append({"name": "Enemy %d" % j, "portrait": "", "hp": 100 + j, "max_hp": 400,
			"start_max_hp": 300 if j == 0 else 400, "summoned": j % 5 == 4})
	var rep := {"version": 1, "won": false, "duration": dur if not zero else 4.0, "heroes": hs, "events": events,
		"enemies": {"seen": enemies + 3, "remaining": enemies, "hp": 100 * enemies, "max_hp": 400 * enemies,
			"survivors": surv},
		"team": {"dealt_hp": 0 if zero else 5000, "dealt_shield": 0, "taken_hp": 0 if zero else 3000,
			"taken_shield": 240 if not zero else 0, "heal_out": 0 if zero else 600, "heal_self": 0},
		"unattributed_taken": 0, "notes": []}
	rep["takeaway"] = BattleRecorder.build_takeaway(rep)
	return rep

func _test_synthetic_layouts() -> void:
	print("synthetic layouts:")
	var summary := {"crystals": 3, "rounds_cleared": 4, "fell_on": 5, "enemies_defeated": 40,
		"biome": "Grassland", "encounter": "Elite", "difficulty": "Veteran"}
	for case in [["solo", 1, 2, false], ["four", 4, 5, false], ["crowded", 20, 40, false], ["zero", 3, 2, true],
			["no enemies", 4, 0, false]]:
		var go := GameOverScreen.new()
		add_child(go)
		go.show_defeat_report(summary, _synthetic(case[1], case[2], case[3]))
		await get_tree().process_frame
		await get_tree().process_frame
		var view := go.report_view()
		_check(view != null and view.size.x > 100.0, "%s report builds and lays out" % case[0])
		go.queue_free()
	# Simultaneous markers stay apart on the timeline.
	var tl := BattleTimeline.new()
	tl.size = Vector2(900, 200)
	add_child(tl)
	tl.setup(_synthetic(3, 1, false))
	tl.size = Vector2(900, 200)
	var xs: Array = []
	for kind in ["ultimate", "heal", "revive"]:
		for m in tl.marker_positions(1000, kind):
			if is_equal_approx(m["t"], 15.0):
				xs.append(m["x"])
	xs.sort()
	_check(xs.size() == 3 and xs[1] - xs[0] >= BattleTimeline.MARK_STEP - 0.01 and xs[2] - xs[1] >= BattleTimeline.MARK_STEP - 0.01,
		"3 events at one timestamp are fanned out (x = %s)" % str(xs))
	tl.queue_free()
