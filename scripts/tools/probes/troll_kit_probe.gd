extends Node
# Isolated Troll kit probe, driving the REAL AutoBattleManager.
# Run: godot --headless --fixed-fps 30 res://scenes/tools/troll_kit_probe.tscn

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
	_test_enrage_targets_and_duration()
	_test_enrage_magnitude_vs_description()
	_test_enraged_visual()
	_test_regen_and_smother()
	_test_shared_keys_unchanged()
	if _fail.is_empty():
		print("TROLL_KIT_PROBE: ALL PASS"); get_tree().quit(0); return
	for f in _fail: print("FAIL: ", f)
	print("TROLL_KIT_PROBE: %d FAILURE(S)" % _fail.size()); get_tree().quit(1)

func _test_ultimate() -> void:
	var t := EnemyFactory.create_by_type("troll_normal"); add_child(t)
	_check(t.ultimate_charge_max == 0,
		"Troll still inherits an ultimate pool (%d)" % t.ultimate_charge_max)
	_check(bool(t.get_meta("troll", false)), "troll marker meta missing")

func _test_enrage_targets_and_duration() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var t = _mk(mgr, s["grid"], EnemyFactory.create_by_type("troll_normal"), Vector2i(2, 2), false)
	var ally = _mk(mgr, s["grid"], EnemyFactory.create_by_type("goblin"), Vector2i(3, 2), false)
	mgr.enemy_units = [t, ally]; mgr.player_units = []
	mgr._use_skill(t, mgr.player_units, mgr.enemy_units)
	# It picks randomly between itself and in-range allies; one of them must be buffed.
	var buffed: bool = (t.bonus_aspd_time > 0.0) or (ally.bonus_aspd_time > 0.0)
	_check(buffed, "Enrage buffed nobody — it must always have at least itself as a target")
	var who = t if t.bonus_aspd_time > 0.0 else ally
	_check(absf(who.bonus_aspd_time - 10.0) < 0.01,
		"Enrage lasts %.2fs, description promises 10s" % who.bonus_aspd_time)
	_check(str(who.aspd_flavor) == "troll_enrage",
		"Enrage did not tag its haste flavour ('%s')" % str(who.aspd_flavor))
	# It must actually raise the haste multiplier, not just set a timer.
	_check(who.bonus_aspd_pct > 0.0,
		"Enrage set a duration but no attack-speed magnitude")

# The code multiplies by (1 + own_affinity/100).
#
# CRITICAL: build probe units with EnemyFactory.create_by_type(), NOT the bare
# create_<name>() function. set_affinity_profile(100,100) is applied inside
# create_by_type, so a directly-constructed unit has NO own-element affinity
# (100 instead of 150) and is simply a different unit from the one waves spawn.
# Measured directly the buff looks like +70%; as the game actually spawns it,
# it is +87.5%.
# RESOLVED 2026-09-18 (user): the NUMBERS stay, the DESCRIPTION was the bug. It
# now prints 87.5% — the value a player actually receives. This probe still PINS
# the behaviour so neither the number nor the text can drift away from the other.
func _test_enrage_magnitude_vs_description() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var t = _mk(mgr, s["grid"], EnemyFactory.create_by_type("troll_normal"), Vector2i(2, 2), false)
	mgr.enemy_units = [t]; mgr.player_units = []
	var aff: float = t.offensive_affinity.get(t.current_element, 0.0)
	_check(absf(aff - 150.0) < 0.01,
		"own-element offensive affinity is %.0f, expected 150 (100 base + 50) — the magnitude note below is stale" % aff)
	mgr._use_skill(t, mgr.player_units, mgr.enemy_units)
	var actual: float = t.bonus_aspd_pct
	var expected_as_coded: float = 0.35 * (1.0 + aff / 100.0)
	_check(absf(actual - expected_as_coded) < 0.001,
		"Enrage magnitude drifted: %.3f, expected %.3f from 0.35*(1+aff/100)" % [actual, expected_as_coded])
	# The description must print what the player actually receives. This is the
	# half that was wrong; the number itself is deliberate and stays.
	var printed := "%.1f" % (actual * 100.0)
	_check(printed in t.skill_description,
		"Enrage grants +%s%% but its description reads \"%s\" — the two have drifted apart again"
			% [printed, t.skill_description])

func _test_enraged_visual() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var t = _mk(mgr, s["grid"], EnemyFactory.create_by_type("troll_normal"), Vector2i(2, 2), false)
	mgr.enemy_units = [t]; mgr.player_units = []
	mgr._sync_enraged_vfx()
	_check(mgr._enraged_vfx.is_empty(), "an unbuffed unit already shows the Enrage readout")
	mgr._use_skill(t, mgr.player_units, mgr.enemy_units)
	mgr._sync_enraged_vfx()
	_check(mgr._enraged_vfx.size() == 1,
		"a 10s attack-speed buff has no persistent visual (%d)" % mgr._enraged_vfx.size())
	t.bonus_aspd_time = 0.0
	mgr._sync_enraged_vfx()
	_check(mgr._enraged_vfx.is_empty(), "Enrage readout outlived the buff")

	# A hero riding the SAME timer from another source must show nothing.
	var s2 := _fresh(); var mgr2 = s2["mgr"]
	var hero = _mk(mgr2, s2["grid"], UnitFactory.create_unit(UnitBase.UnitClass.PASTOR), Vector2i(2, 6), true)
	mgr2.player_units = [hero]; mgr2.enemy_units = []
	hero.bonus_aspd_pct = 0.2; hero.bonus_aspd_time = 5.0   # no flavour tag
	mgr2._sync_enraged_vfx()
	_check(mgr2._enraged_vfx.is_empty(),
		"a hero's own haste rendered as Troll sinew — the aspd flavour gate is not working")

func _test_regen_and_smother() -> void:
	var s := _fresh(); var mgr = s["mgr"]
	var t = _mk(mgr, s["grid"], EnemyFactory.create_by_type("troll_normal"), Vector2i(2, 2), false)
	mgr.enemy_units = [t]; mgr.player_units = []
	t.current_hp = 200
	mgr._tick_passive(t, mgr.player_units, mgr.enemy_units, 0.1)
	_check(t.hp_regen_accum > 0.0, "Regeneration did not regenerate while unblocked")
	_check(mgr._troll_regen_vfx.size() == 1,
		"Regeneration is running with no readout — its fire/lightning counterplay is never communicated")
	# A FIRE hit must smother it.
	t.take_damage(10, UnitBase.Element.FIRE, null)
	_check(float(t.get_meta("troll_regen_block_t", 0.0)) > 0.0,
		"a Fire hit did not set the regen block — passive plumbing changed")
	mgr._tick_passive(t, mgr.player_units, mgr.enemy_units, 0.1)
	_check(mgr._troll_regen_vfx.is_empty(),
		"Regeneration readout survived the smother — it must clear the moment regen stops")
	# Per-element counters (ELEMENT_COUNTERS.md): own element never counters;
	# each element counts equally across the 6 Trolls; each Troll really obeys it.
	var tally := {}
	for el in UnitBase.REGEN_COUNTERS:
		var pair: Array = UnitBase.REGEN_COUNTERS[el]
		_check(pair.size() == 2 and not (el in pair), "Troll %s counters its own element" % el)
		for c in pair: tally[c] = int(tally.get(c, 0)) + 1
	for el in UnitBase.Element.values():
		_check(int(tally.get(el, 0)) == 2, "element %d counters %d Trolls, want 2" % [el, int(tally.get(el, 0))])
	for code in ["troll_normal", "troll_fire", "troll_water", "troll_earth", "troll_air", "troll_lightning"]:
		var tv = _mk(mgr, s["grid"], EnemyFactory.create_by_type(code), Vector2i(4, 2), false)
		for el in UnitBase.Element.values():
			tv.set_meta("troll_regen_block_t", 0.0)
			tv.take_damage(1, el, null)
			var blocked: bool = float(tv.get_meta("troll_regen_block_t", 0.0)) > 0.0
			_check(blocked == (el in UnitBase.REGEN_COUNTERS[tv.current_element]),
				"%s: element %d block=%s disagrees with REGEN_COUNTERS" % [code, el, blocked])
		s["grid"].remove_unit(Vector2i(4, 2)); tv.queue_free()

func _test_shared_keys_unchanged() -> void:
	for pair in [["Gargoyle", EnemyFactory.create_by_type("gargoyle")],
			["Ember Phoenix", EnemyFactory.create_by_type("ember_phoenix")]]:
		var m = pair[1]; add_child(m)
		_check(str(m.get_meta("mob_passive", "")) != "troll_regen",
			"%s is back on troll_regen — it has its own passive since 2026-09-24" % pair[0])
		_check(not bool(m.get_meta("troll", false)),
			"%s was wrongly marked as the Troll and would gain sinew VFX" % pair[0])
