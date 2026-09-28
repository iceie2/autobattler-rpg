extends Node
# ══════════════════════════════════════════════════════════════════════════════
# RELIC RULES SMOKE (VD-21) — the relic rules the audit found broken, on the
# REAL classes, deterministically.
#
# Asserts:
#   1. odds: every relic source rolls the table row at or before its round.
#      Map relic nodes (round 0, played as the biome's first round) and
#      merchants (rounds like 13) used to fall back to wave-1 odds all run.
#   2. on-kill: linear per kill with a fractional carry, through the real
#      apply_relic_on_hit hook (a D relic on a 20-attack hero now pays out).
#
# The main_game halves (bench heroes, the synergy revert, save/resume, the
# relic node's round in the real flow) live in
# scenes/tools/relic_rules_integration.tscn, which needs a disposable profile.
#
# Run:  godot --headless res://scenes/relic_rules_smoke.tscn
# Exit code 0 = pass, 1 = fail. Touches no save file.
# ══════════════════════════════════════════════════════════════════════════════

var _fails: Array = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		_fails.append(label)
		print("  FAIL: %s" % label)

func _near(got: float, want: float, tol: float, label: String) -> void:
	_check(absf(got - want) <= tol, "%s (got %.3f, want %.3f)" % [label, got, want])

func _ready() -> void:
	_test_odds()
	_test_on_kill()
	print("RELIC_RULES_SMOKE: %s" % ("ALL PASS" if _fails.is_empty()
		else "%d FAILED -> %s" % [_fails.size(), ", ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)

# ── helpers ──────────────────────────────────────────────────────────────────
# Riot: a plain melee hero with no class branch in the relic hooks.
func _hero() -> UnitBase:
	var cls := UnitBase.UnitClass.RIOT
	var u: UnitBase = UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
	add_child(u)
	return u

func _dummy() -> UnitBase:
	var u: UnitBase = EnemyFactory.create_by_type("goblin")
	add_child(u)
	u.max_hp = 1000000
	u.current_hp = 1000000
	u.resistance = 0
	u.magic_resist = 0
	return u

# One inventory for the whole smoke, as in a run: each pick gets its own
# acquisition id. A fresh inventory per pick would hand every relic id 0, and
# the per-unit guard would then skip the second relic on a unit.
var _inv := RelicInventory.new()

func _give(u: UnitBase, relic_id: String) -> void:
	var relic := Relic.by_id(relic_id)
	_check(not relic.is_empty(), "relic %s exists" % relic_id)
	_inv.apply_relic_to_units(_inv.add_relic(relic), [u])

# ── 1. odds ──────────────────────────────────────────────────────────────────
func _test_odds() -> void:
	print("odds:")
	_check(Relic.odds_for_wave(0) == Relic.WAVE_ODDS[1], "round 0 rolls the wave-1 row")
	_check(Relic.odds_for_wave(1) == Relic.WAVE_ODDS[1], "wave 1 rolls the wave-1 row")
	_check(Relic.odds_for_wave(10) == Relic.WAVE_ODDS[1], "wave 10 still rolls the wave-1 row")
	_check(Relic.odds_for_wave(11) == Relic.WAVE_ODDS[11], "wave 11 rolls the wave-11 row")
	_check(Relic.odds_for_wave(13) == Relic.WAVE_ODDS[11], "a round-13 merchant rolls the wave-11 row")
	_check(Relic.odds_for_wave(58) == Relic.WAVE_ODDS[51], "round 58 rolls the wave-51 row")
	_check(Relic.odds_for_wave(100) == Relic.WAVE_ODDS[91], "round 100 rolls the wave-91 row")

	# The real map: each biome opens on a relic node that is a round-0 utility
	# stop, and its biome's first round is biome x 10 + 1 - the two facts the
	# relic branch in main_game resolves the node's round from.
	for b in range(4):
		var map := RunMap.generate(b, 0, true)
		var starts: Array = map.available_next()
		var relic_node: Dictionary = starts[0] if not starts.is_empty() else {}
		_check(int(relic_node.get("type", -1)) == RunMap.NodeType.RELIC,
			"biome %d opens on a relic node" % b)
		_check(int(relic_node.get("round", -1)) == 0, "biome %d relic node carries round 0" % b)
		_check(map.absolute_round(1) == b * 10 + 1, "biome %d first round is %d" % [b, b * 10 + 1])

	# Rolls, seeded so the counts are exact run to run.
	seed(2109)
	var counts := {"D": 0, "C": 0, "B": 0, "A": 0, "S": 0}
	for _i in range(4000):
		counts[Relic.roll_grade(14)] += 1
	_check(counts["S"] == 0, "round 14 never rolls S (wave-11 row has S 0)")
	_near(float(counts["D"]) / 4000.0, 0.45, 0.03, "round 14 D share is the wave-11 row's 45%, not wave 1's 80%")
	var d_at_54 := 0
	var high_at_54 := 0
	for _i in range(2000):
		var g := Relic.roll_grade(54)
		if g == "D":
			d_at_54 += 1
		if g == "A" or g == "S":
			high_at_54 += 1
	_check(d_at_54 == 0, "round 54 never rolls D (wave-51 row has D 0)")
	_check(high_at_54 > 600, "round 54 rolls A/S about 40%% of the time (got %d/2000)" % high_at_54)

	# The real merchant stock on a late-biome round.
	var merchant_grades := {"D": 0, "C": 0, "B": 0, "A": 0, "S": 0}
	for _i in range(150):
		for entry in ShopGenerator.roll_stock(54, []):
			if String(entry.get("kind", "")) == "relic":
				merchant_grades[String(entry["relic"]["grade"])] += 1
	_check(merchant_grades["D"] == 0, "a round-54 merchant never stocks a D relic (%s)" % str(merchant_grades))
	_check(merchant_grades["A"] + merchant_grades["S"] > 0, "a round-54 merchant stocks A/S relics")

# ── 2. on-kill ───────────────────────────────────────────────────────────────
func _test_on_kill() -> void:
	print("on-kill:")
	var dead := _dummy()
	dead.current_hp = 0
	var u := _hero()
	u.attack_damage = 20
	_give(u, "s_soul")   # +2% per kill
	for _k in range(2):
		u.apply_relic_on_hit(dead, 10, true)
	_check(u.attack_damage == 20, "2 kills x 0.4 = 0.8: still 20 (got %d)" % u.attack_damage)
	u.apply_relic_on_hit(dead, 10, true)
	_check(u.attack_damage == 21, "3rd kill carries the fraction to 1.2: 21 (got %d)" % u.attack_damage)
	for _k in range(22):
		u.apply_relic_on_hit(dead, 10, true)
	_check(u.attack_damage == 30, "25 kills = +10, linear (compounding gives 32; got %d)" % u.attack_damage)
	_near(u.relic_kill_atk_gain, 10.0, 0.001, "the running total is kept with its fraction")

	var d := _hero()
	d.attack_damage = 20
	_give(d, "d_onkill")   # +0.4% per kill: round(20 x 1.004) used to stay 20 forever
	for _k in range(12):
		d.apply_relic_on_hit(dead, 10, true)
	_check(d.attack_damage == 20, "D: 12 kills x 0.08 = 0.96, still 20 (got %d)" % d.attack_damage)
	d.apply_relic_on_hit(dead, 10, true)
	_check(d.attack_damage == 21, "D: the 13th kill pays out (got %d)" % d.attack_damage)

	var alive := _dummy()
	var n := _hero()
	n.attack_damage = 20
	_give(n, "s_soul")
	n.apply_relic_on_hit(alive, 10, true)
	n.apply_relic_on_hit(dead, 10, false)
	_check(n.attack_damage == 20 and n.relic_kill_atk_gain == 0.0,
		"a hit that does not kill, or a target already dead, grants nothing")
