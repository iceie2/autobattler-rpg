extends Node
# ══════════════════════════════════════════════════════════════════════════════
# CRYSTAL TREE SMOKE TEST (2026-08-03) — the tree went from ~70 hand-authored
# upgrades to 604 generated ones, and multi-level upgrades were split into
# one-level picks. That split silently breaks every `get_bonus("might")`-style
# read unless the feeder aggregation works, which no other smoke test touches.
#
# This drives the REAL Progression singleton: merge, feeder sums, purchase, the
# level cap, and each of the seven systems wired to a new key.
#
# Run:  godot --headless res://scenes/crystal_smoke.tscn
# Exit code 0 = pass, 1 = fail.
# ══════════════════════════════════════════════════════════════════════════════

var _fails: Array = []
var _saved_levels: Dictionary = {}
var _saved_crystals: int = 0
var _saved_spent: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: %s" % label)
	else:
		_fails.append(label)
		print("  FAIL: %s" % label)

func _eq(got, want, label: String) -> void:
	_check(is_equal_approx(float(got), float(want)),
		"%s (got %s, want %s)" % [label, got, want])

func _ready() -> void:
	# Never clobber a real save: snapshot, mutate in memory, restore at the end.
	# _test_purchase goes through the real buy(), which WRITES the save file, so
	# a memory-only restore is not enough: restore every field buy() touches and
	# write the save back. (2026-09-25: the memory-only restore left a real save
	# at 99,850 crystals holding the test's Pastor unlock - twice, the first time
	# preserved as progression.PRE-BASELINE-2026-08-03.bak.)
	_saved_levels = Progression.upgrade_levels.duplicate(true)
	_saved_crystals = Progression.crystals
	_saved_spent = Progression.crystals_spent

	_test_catalogue()
	_test_feeders()
	_test_purchase()
	_test_level_cap()
	_test_new_systems()

	Progression.upgrade_levels = _saved_levels
	Progression.crystals = _saved_crystals
	Progression.crystals_spent = _saved_spent
	Progression.save_data()

	print("CRYSTAL_SMOKE: %s" % ("ALL PASS" if _fails.is_empty()
		else "%d FAILED -> %s" % [_fails.size(), ", ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)

func _test_catalogue() -> void:
	print("catalogue:")
	var cat := Progression.catalogue()
	_check(cat.size() > 500, "generated entries merged (%d)" % cat.size())
	_check(not Progression._find("web_might_r0_0").is_empty(),
		"a generated web node resolves")
	_check(Progression._find("bench_slots").is_empty(),
		"retired bench_slots is gone")
	_check(Progression._find("loot_quality").is_empty(),
		"retired loot_quality is gone")
	# Generated entries must REPLACE the authored ones, not sit beside them.
	var dupes := {}
	var dupe_count := 0
	for u in cat:
		var k := String(u["key"])
		if dupes.has(k):
			dupe_count += 1
		dupes[k] = true
	_check(dupe_count == 0, "no duplicate keys after merge")
	_check(int(Progression.max_level("max_level")) == 1,
		"generated max_level overrode the authored 5-level version")

func _test_feeders() -> void:
	print("feeder aggregation:")
	Progression.upgrade_levels.clear()
	_eq(Progression.get_bonus("might"), 0, "might starts at 0")
	# `might` is the sector anchor; the other 13 nodes in its sector feed it.
	Progression.upgrade_levels["might"] = 1
	_eq(Progression.get_bonus("might"), 6, "anchor node alone counts once")
	Progression.upgrade_levels["web_might_r0_0"] = 1
	_eq(Progression.get_bonus("might"), 12, "a feeder adds to the base key")
	# A node that feeds must NOT also answer for its own key, or it double-counts.
	_eq(Progression.get_bonus("web_might_r0_0"), 0, "feeder does not answer for itself")
	Progression.upgrade_levels.clear()

func _test_purchase() -> void:
	print("purchase path:")
	Progression.upgrade_levels.clear()
	Progression.crystals = 100000
	# Tree parents are PREREQUISITES: hero_unlock_pastor hangs off "max_level",
	# so buying it from an empty tree is refused by is_locked(). This test
	# predates that gate and was silently failing all five of its checks; grant
	# the parent so it exercises the purchase path it means to (2026-08-07).
	var granted_cost := 0
	for parent: String in Progression._tree_parents.get("hero_unlock_pastor", []):
		granted_cost += Progression.next_cost(parent)
		Progression.upgrade_levels[parent] = 1
	var cost := Progression.next_cost("hero_unlock_pastor")
	_check(cost > 10, "generated cost_mult reached next_cost (%dc)" % cost)
	var before := Progression.crystals
	_check(Progression.buy("hero_unlock_pastor"), "buy succeeds")
	_eq(before - Progression.crystals, cost, "exact cost deducted")
	_check(Progression.next_cost("hero_unlock_pastor") == -1, "maxed at 1 level")
	_check(Progression.is_hero_unlocked(UnitBase.UnitClass.PASTOR),
		"hero unlock takes effect")
	# total_spent replays EVERY owned level, including the prereq granted above.
	_check(Progression.total_spent() == cost + granted_cost,
		"total_spent replays the generated cost")
	_test_hero_price_ladder()

# Hero unlocks share one ladder: all unbought heroes cost the same, and each
# purchase raises every remaining one (2026-09-25).
func _test_hero_price_ladder() -> void:
	print("hero price ladder:")
	Progression.upgrade_levels.clear()
	var keys: Array = Progression.HERO_UNLOCK_KEYS.values()
	var first := Progression.next_cost(keys[0])
	var all_same := true
	for k: String in keys:
		all_same = all_same and Progression.next_cost(k) == first
	_check(all_same, "every unbought hero costs the same (%dc)" % first)
	Progression.upgrade_levels[keys[0]] = 1
	var second := Progression.next_cost(keys[1])
	_check(second > first, "buying one raises the rest (%dc -> %dc)" % [first, second])
	_check(Progression.next_cost(keys[5]) == second, "raise applies to every remaining hero")
	for i in range(11):
		Progression.upgrade_levels[keys[i]] = 1
	print("    12th hero costs %dc" % Progression.next_cost(keys[11]))
	var replay := 0
	for i in range(11):
		replay += Progression._hero_unlock_cost(i)
	_eq(Progression.total_spent(), replay, "total_spent replays the shared ladder")
	Progression.upgrade_levels.clear()
	Progression.upgrade_levels.clear()

func _test_level_cap() -> void:
	print("hero level cap:")
	Progression.upgrade_levels.clear()
	var base := Progression.hero_level_cap()
	_eq(base, Progression.HERO_LEVEL_CAP_BASE, "base cap with nothing bought")
	# Spine node and a web keystone both feed "max_level".
	Progression.upgrade_levels["max_level"] = 1
	Progression.upgrade_levels["max_level_web_0"] = 1
	_eq(Progression.hero_level_cap(), base + 2, "spine + web keystone both raise the cap")
	Progression.upgrade_levels.clear()

func _test_new_systems() -> void:
	print("newly wired systems:")
	Progression.upgrade_levels.clear()
	for k in ["loot_drop_chance_1a", "loot_to_uncommon_1a", "loot_to_rare_1a",
			"interest_cap", "hero_start_level", "catch_up_xp", "item_lock",
			"def_affinity_fire", "synergy_fire_1", "quick_learner", "bonus_xp"]:
		Progression.upgrade_levels[k] = 1
	_eq(Progression.get_bonus("loot_drop_chance"), 3, "equipment spawn chance")
	_eq(Progression.get_bonus("loot_to_uncommon"), 2, "grey->green upconversion")
	_eq(Progression.get_bonus("loot_to_rare"), 1, "green->blue upconversion")
	_eq(Progression.get_bonus("interest_cap"), 1, "interest cap")
	_eq(Progression.get_bonus("hero_start_level"), 1, "hero start level")
	_eq(Progression.get_bonus("catch_up_xp"), 25, "catch-up xp")
	_eq(Progression.get_bonus("item_lock"), 1, "item lock capacity")
	_eq(Progression.get_bonus("def_affinity_fire"), 1, "fire def affinity")
	_eq(Progression.get_bonus("synergy_fire"), 1, "fire synergy (virtual base key)")
	_eq(Progression.get_bonus("quick_learner"), 25, "hero battle xp")
	_eq(Progression.get_bonus("bonus_xp"), 10, "player account xp")

	# The synergy tracker must actually consume that key.
	var tracker := SynergyTracker.new()
	Progression.upgrade_levels["synergy_fire_1"] = 1
	tracker.update_from_team([])
	_check(int(tracker.element_counts.get(UnitBase.Element.FIRE, 0)) == 0,
		"synergy does not invent a count for an element you don't field")
	Progression.upgrade_levels.clear()
