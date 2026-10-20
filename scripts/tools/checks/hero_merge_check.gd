extends Node
# Hero merging (2026-09-28). Run in a DISPOSABLE PROFILE — it boots main_game and
# writes a run save:
#   APPDATA=<scratch>/merge_profile godot --headless --path . res://scenes/hero_merge_check.tscn
var failures: Array[String] = []
var _integration_done := false   # a GDScript runtime error aborts a function silently

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	if not OS.get_user_data_dir().contains("merge_profile"):
		print("HERO_MERGE: refusing to run outside a merge_profile APPDATA sandbox")
		get_tree().quit(2)
		return
	seed(4412)
	_check_rules()
	_check_backfill_exact()
	_check_partial_apply()
	_check_shop_weight()
	await _check_toast()
	await _check_partial_toast()
	await _check_integration()
	if not _integration_done:
		check(false, "integration section did not finish (script error?)")
	print("HERO_MERGE: ", "ALL PASS" if failures.is_empty() else str(failures))
	for i in range(3): await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _hero(cls: UnitBase.UnitClass, grade: String = "B") -> UnitBase:
	var u := UnitFactory.create_unit(cls, UnitFactory.element_for_class(cls), true)
	UnitFactory.apply_recruit_rolls(u, UnitFactory.generate_recruit_rolls())
	u.recruit_grade = grade
	add_child(u)
	return u

func _check_rules() -> void:
	check(UnitFactory.next_grade("D") == "C" and UnitFactory.next_grade("S") == "S+", "ladder steps")
	check(UnitFactory.next_grade("S+") == "S+", "S+ is the cap")
	check(UnitFactory.next_grade("") == "A", "legacy blank grade treated as B")
	var a := _hero(UnitBase.UnitClass.RIOT, "B")
	var b := _hero(UnitBase.UnitClass.RIOT, "B")
	var c := _hero(UnitBase.UnitClass.DOC, "B")
	check(UnitFactory.merge_block_reason(a, b) == "", "same class + same grade merges")
	check(UnitFactory.merge_block_reason(a, c) != "", "different class refused")
	check(UnitFactory.merge_block_reason(a, a) != "", "self merge refused")
	# Owner rule 2026-10-07: a LOWER-grade copy still helps, as part of a merge.
	b.recruit_grade = "A"
	check(UnitFactory.merge_survivor(a, b) == b and UnitFactory.merge_survivor(b, a) == b,
		"the higher grade survives, whichever way round")
	check(UnitFactory.merge_block_reason(b, a) == "", "a B can be merged into an A")
	check(UnitFactory.merge_block_reason(a, b) != "", "but the higher grade has to be the one that ranks up")
	b.recruit_grade = "S"; a.recruit_grade = "A"
	check(UnitFactory.merge_block_reason(b, a) == "", "an A can be merged into an S")
	a.recruit_grade = ""   # legacy blank grade counts as B
	b.recruit_grade = "B"
	check(UnitFactory.merge_block_reason(a, b) == "", "blank legacy grade merges with a B")
	a.recruit_grade = "B"
	# Same grade: higher level survives; equal level → the one dropped ON (second argument).
	a.set_level(6); b.set_level(3)
	check(UnitFactory.merge_survivor(a, b) == a and UnitFactory.merge_survivor(b, a) == a, "same grade: higher level survives")
	b.set_level(6)
	check(UnitFactory.merge_survivor(a, b) == b and UnitFactory.merge_survivor(b, a) == a, "level tie → the target survives")
	# Merge arithmetic in D-units (D1 C2 B4 A8 S16 S+32): every grade is worth twice the one below.
	check(UnitFactory.merge_value("D") == 1 and UnitFactory.merge_value("C") == 2 and UnitFactory.merge_value("B") == 4
		and UnitFactory.merge_value("A") == 8 and UnitFactory.merge_value("S") == 16, "grade values double")
	a.recruit_grade = "B"; a.merge_progress = 0; b.recruit_grade = "C"
	var plan := UnitFactory.merge_plan(a, b)
	check(int(plan["steps"]) == 0 and int(plan["progress_after"]) == 2 and int(plan["threshold_before"]) == 4,
		"a C into a B is HALF a merge (2 of 4), no rank-up")
	check(UnitFactory.progress_text(2, 4) == "1/2" and UnitFactory.progress_text(1, 4) == "1/4"
		and UnitFactory.progress_text(3, 4) == "3/4" and UnitFactory.progress_text(0, 4) == "0", "progress shows as a reduced fraction")
	a.merge_progress = 2
	plan = UnitFactory.merge_plan(a, b)
	check(int(plan["steps"]) == 1 and str(plan["grade_after"]) == "A" and int(plan["progress_after"]) == 0,
		"two Cs rank a B up to A")
	b.recruit_grade = "D"; a.merge_progress = 0
	check(int(UnitFactory.merge_plan(a, b)["progress_after"]) == 1, "a D into a B is a quarter")
	b.recruit_grade = "B"; a.merge_progress = 2
	plan = UnitFactory.merge_plan(a, b)
	check(int(plan["steps"]) == 1 and str(plan["grade_after"]) == "A" and int(plan["progress_after"]) == 2
		and int(plan["threshold_after"]) == 8, "a full B on a half-merged B ranks up and KEEPS the half")
	a.recruit_grade = "S"; a.merge_progress = 0; b.recruit_grade = "A"
	plan = UnitFactory.merge_plan(a, b)
	check(int(plan["steps"]) == 0 and int(plan["progress_after"]) == 8 and int(plan["threshold_before"]) == 16,
		"an A into an S is half a merge toward S+")
	a.merge_progress = 8
	plan = UnitFactory.merge_plan(a, b)
	check(int(plan["steps"]) == 1 and str(plan["grade_after"]) == "S+" and int(plan["progress_after"]) == 0,
		"the second A takes the S to S+ (nothing is kept at the top)")
	a.recruit_grade = "S+"; b.recruit_grade = "S+"
	check(UnitFactory.merge_block_reason(a, b) != "", "S+ is the top grade: nothing merges into it")
	b.recruit_grade = "C"
	check(UnitFactory.merge_block_reason(a, b) != "", "not even a lesser copy")
	for u in [a, b, c]: u.queue_free()

# A partial merge changes NO stats: only merge_progress moves; the second half
# ranks up exactly like a full merge.
func _check_partial_apply() -> void:
	var s := _hero(UnitBase.UnitClass.RIOT, "B")
	var c1 := _hero(UnitBase.UnitClass.RIOT, "C")
	var c2 := _hero(UnitBase.UnitClass.RIOT, "C")
	s.set_level(5)
	c1.current_xp = 10.0
	var hp0 := s.max_hp
	var atk0 := s.attack_damage
	var gb0: Dictionary = s.growth_bonus.duplicate()
	UnitFactory.merge_heroes(s, c1)
	check(s.recruit_grade == "B" and s.merge_progress == 2, "after one C: still B, half a merge banked")
	check(s.max_hp == hp0 and s.attack_damage == atk0 and s.growth_bonus == gb0, "a partial merge changes no stats or growth")
	UnitFactory.merge_heroes(s, c2)
	check(s.recruit_grade == "A" and s.merge_progress == 0, "the second C ranks it up to A")
	check(s.max_hp > hp0 and s.attack_damage > atk0, "the rank-up applies the usual stat backfill")
	# The same backfill as a straight same-grade merge would give.
	var ref := _hero(UnitBase.UnitClass.RIOT, "B")
	var ref2 := _hero(UnitBase.UnitClass.RIOT, "B")
	ref.growth_bonus = gb0.duplicate()
	ref.set_level(5)
	ref.max_hp = hp0
	ref.attack_damage = atk0
	UnitFactory.merge_heroes(ref, ref2)
	check(ref.max_hp == s.max_hp and ref.attack_damage == s.attack_damage, "two halves = the same result as one full merge")
	for u in [s, c1, c2, ref, ref2]: u.queue_free()

# Stats are stored as final numbers with relic/scar/gear bonuses baked in. The
# merge must add ONLY growth-step × level and leave those extras intact.
func _check_backfill_exact() -> void:
	var s := _hero(UnitBase.UnitClass.RIOT, "B")
	var k := _hero(UnitBase.UnitClass.RIOT, "B")
	s.set_level(8)
	# Simulated baked-in extras (relic atk, scar hp) that a recompute would wipe.
	s.attack_damage += 37
	s.max_hp += 120; s.current_hp = s.max_hp
	k.current_xp = 0.0
	var before := {"hp": s.max_hp, "mana": s.max_mana, "atk": s.attack_damage,
		"magic": s.magic_power, "res": s.resistance, "mres": s.magic_resist,
		"aspd": s.attack_speed, "hpregen": s.hp_regen, "manaregen": s.mana_regen}
	var gb: Dictionary = s.growth_bonus.duplicate()
	UnitFactory.merge_heroes(s, k)
	var lv := s.level
	check(lv == 8, "no XP carried → level unchanged")
	check(s.recruit_grade == "A", "B → A")
	var step := func(key: String) -> float:
		var d: float = float(s.growth_base.get(key, 0.0)) * UnitFactory.MERGE_GROWTH_STEP
		return float(round(d)) if key == "res" else snappedf(d, 0.01)
	for key in ["hp", "mana", "atk", "magic", "res", "aspd", "hpregen", "manaregen"]:
		check(is_equal_approx(float(s.growth_bonus.get(key, 0.0)), float(gb.get(key, 0.0)) + step.call(key)),
			"growth bonus +step for %s" % key)
	check(s.max_hp == before.hp + int(round(step.call("hp") * lv)), "hp backfill exact (scar kept)")
	check(s.attack_damage == before.atk + int(round(step.call("atk") * lv)), "atk backfill exact (relic kept)")
	check(s.magic_power == before.magic + int(round(step.call("magic") * lv)), "magic backfill")
	check(s.max_mana == before.mana + int(round(step.call("mana") * lv)), "mana backfill")
	check(s.resistance == before.res + int(step.call("res") * lv), "res backfill")
	check(s.magic_resist == before.mres + int(step.call("res") * lv), "mres backfill")
	check(is_equal_approx(s.attack_speed, before.aspd + step.call("aspd") * lv), "aspd backfill")
	check(s.current_hp <= s.max_hp, "hp not over max")
	# Future levels use the new growth.
	var atk_pre := s.attack_damage
	var hp_pre := s.max_hp
	s.level_up()
	check(s.attack_damage - atk_pre >= int(floor(s.stat_growth("atk"))), "next level uses raised atk growth")
	check(s.max_hp - hp_pre >= int(floor(s.stat_growth("hp"))), "next level uses raised hp growth")
	# XP carry: half the consumed copy's XP.
	var k2 := _hero(UnitBase.UnitClass.RIOT)
	k2.current_xp = 10.0
	var xp_before := s.current_xp
	var lv_before := s.level
	UnitFactory.merge_heroes(s, k2)
	check(s.level > lv_before or is_equal_approx(s.current_xp, xp_before + 5.0), "half XP carried")
	for u in [s, k, k2]: u.queue_free()

func _fmt_stat(v: float, fmt: String) -> String:
	return ("%.2f" % v) if fmt == "f2" else str(int(round(v)))

# Runs the toast to completion, sampling every frame. Fills `out`:
#   finished / badge / rows_ok (at `done`), and over the whole run:
#   sum_ok  — an int row's main + remaining gain ALWAYS equals its final value
#             (so "2059 → 2059"-style states can't occur),
#   saw_mid — some int row showed a value strictly between old and new,
#   fmt_ok  — decimal rows only ever show exactly two decimals.
func _await_toast(toast: MergeResultScreen, out: Dictionary) -> void:
	out["sum_ok"] = true
	out["saw_mid"] = false
	out["fmt_ok"] = true
	toast.done.connect(func() -> void:
		var rows_ok := true
		for r in toast._rows:
			rows_ok = rows_ok and r["main"].text == _fmt_stat(r["b"], r["fmt"]) and r["gain"].text == ""
		out["finished"] = true
		out["badge"] = toast._badge.text
		out["rows_ok"] = rows_ok)
	var waited := 0.0
	while not out.get("finished", false) and waited < 20.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if out.get("finished", false) or not is_instance_valid(toast):
			break
		for r in toast._rows:
			var main: Label = r["main"]
			var g: String = (r["gain"] as Label).text
			if r["fmt"] == "int":
				var ia := int(round(float(r["a"])))
				var ib := int(round(float(r["b"])))
				var v := int(main.text)
				if g != "" and v + int(g.substr(1)) != ib:
					out["sum_ok"] = false
				if v > mini(ia, ib) and v < maxi(ia, ib):
					out["saw_mid"] = true
			else:
				if main.text.split(".").size() != 2 or main.text.split(".")[1].length() != 2:
					out["fmt_ok"] = false

# The literal spec case: a stat at 2047 gaining 12 must start "2047 +12" and
# end "2059" with the gain gone; whole stats step as integers, decimals stay
# clean two-place values; no buttons, click-swallowing root, self-dismissing.
func _check_toast() -> void:
	var u := _hero(UnitBase.UnitClass.RIOT, "B")
	u.max_hp = 2047
	u.attack_speed = 1.00
	var before := MergeResultScreen.snapshot(u)
	u.max_hp = 2059
	u.attack_speed = 1.06
	u.recruit_grade = "A"
	var t := MergeResultScreen.new()
	add_child(t)
	t.present(u, before)
	check(t._badge.text == "B", "toast begins on the old grade badge")
	check(t._grade_chip.text == "GRADE B", "toast begins with the old grade chip")
	check(t._rows.size() == 2, "only the changed stats get rows")
	var hp: Dictionary = t._rows[0]
	check(hp["main"].text == "2047" and hp["gain"].text == "+12", "row starts as '2047 +12'")
	var asp: Dictionary = t._rows[1]
	check(asp["main"].text == "1.00" and asp["gain"].text == "+0.06", "decimal row starts '1.00 +0.06'")
	check(t._root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "overlay never blocks input")
	check(t.find_children("*", "BaseButton", true, false).is_empty(), "overlay has no buttons")
	var out := {}
	await _await_toast(t, out)   # no input of any kind is sent
	check(out.get("finished", false), "toast dismisses itself with no input")
	check(out.get("badge", "") == "A", "transform reaches the new grade (A)")
	check(out.get("sum_ok", false), "main + remaining gain always equals the final value")
	check(out.get("saw_mid", false), "the main value actually climbs through the steps")
	check(out.get("fmt_ok", false), "decimal stats never show float noise")
	check(out.get("rows_ok", false), "rows end at 2059 / 1.06 with the gain gone")
	await get_tree().process_frame
	check(not is_instance_valid(t), "toast frees itself")
	u.queue_free()

# The toast for a partial merge: no flash, no stat rows, a narrow card, and the
# merge-progress bar fills; a rank-up that keeps leftover progress shows the bar too.
func _check_partial_toast() -> void:
	var u := _hero(UnitBase.UnitClass.RIOT, "B")
	var before := MergeResultScreen.snapshot(u)
	u.merge_progress = 2   # absorbed a C: half a merge
	var t := MergeResultScreen.new()
	add_child(t)
	t.present(u, before)
	check(t._partial and t._show_bar and t._rows.is_empty(), "partial toast: progress bar, no stat rows")
	check(t._card.size.x == MergeResultScreen.CARD_W, "no stat rows, so the card is just the hero")
	check(t._badge.text == "B" and t._bar_fill.size.x == 0.0 and t._bar_lbl.text.ends_with("0"), "it starts on an empty bar")
	var cap := {"done": false}
	t.done.connect(func() -> void:
		cap["done"] = true
		cap["w"] = t._bar_fill.size.x
		cap["bar_w"] = t._bar_w
		cap["lbl"] = t._bar_lbl.text
		cap["badge"] = t._badge.text)
	var waited := 0.0
	while not cap["done"] and waited < 25.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(cap["done"], "partial toast dismisses itself")
	check(is_equal_approx(float(cap.get("w", -1.0)), float(cap.get("bar_w", 0.0)) * 0.5), "the bar fills to half")
	check(str(cap.get("lbl", "")).ends_with("1/2") and cap.get("badge", "") == "B", "it ends on 1/2 and the grade is unchanged")
	await get_tree().process_frame
	# Rank-up that keeps leftover progress: B at half + a full B → A with 1/4 toward S.
	var u2 := _hero(UnitBase.UnitClass.RIOT, "B")
	u2.merge_progress = 2
	var before2 := MergeResultScreen.snapshot(u2)
	u2.recruit_grade = "A"
	u2.merge_progress = 2
	var t2 := MergeResultScreen.new()
	add_child(t2)
	t2.present(u2, before2)
	check(not t2._partial and t2._show_bar, "a rank-up that keeps leftover progress still shows the bar")
	check(is_equal_approx(t2._bar_fill.size.x, t2._bar_w * 0.5), "the bar starts at the old half")
	var cap2 := {"done": false}
	t2.done.connect(func() -> void:
		cap2["done"] = true
		cap2["w"] = t2._bar_fill.size.x
		cap2["bar_w"] = t2._bar_w
		cap2["lbl"] = t2._bar_lbl.text
		cap2["badge"] = t2._badge.text)
	waited = 0.0
	while not cap2["done"] and waited < 25.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check(cap2.get("badge", "") == "A" and is_equal_approx(float(cap2.get("w", -1.0)), float(cap2.get("bar_w", 0.0)) * 0.25)
		and str(cap2.get("lbl", "")).ends_with("1/4"), "it ends as A with a quarter (2 of 8) banked")
	await get_tree().process_frame
	u.queue_free()
	u2.queue_free()

func _check_shop_weight() -> void:
	var shop := HeroShop.new()
	var classes: Array = UnitFactory.get_all_classes()
	var owned: int = classes[0]
	shop.owned_classes = [owned]
	var hits := 0
	var n := 40000
	for i in range(n):
		if shop._pick_class(classes) == owned:
			hits += 1
	var expect: float = HeroShop.OWNED_WEIGHT / (float(classes.size()) - 1.0 + HeroShop.OWNED_WEIGHT)
	var got := float(hits) / n
	print("HERO_MERGE: owned pick rate %.4f expected %.4f (uniform %.4f)" % [got, expect, 1.0 / classes.size()])
	check(absf(got - expect) < 0.006, "owned weight ≈ 1.5×")
	shop.owned_classes = []
	shop.free()

func _check_integration() -> void:
	var mg = load("res://scenes/main_game.tscn").instantiate()
	add_child(mg)
	for i in range(12): await get_tree().process_frame
	mg.game_state.current_state = GameState.State.PLAYER_TURN
	for u in mg.player_units.duplicate(): mg.player_units.erase(u); mg.battle_grid.purge_unit(u); u.queue_free()
	mg.max_player_units = 10   # round-1 field cap would bench copy 2
	mg.game_state.battle_round = 3   # save_run() skips round 0
	var cls := UnitBase.UnitClass.RIOT
	var el := UnitFactory.element_for_class(cls)
	check(mg._recruit_hero(cls, el, UnitFactory.generate_recruit_rolls()), "recruit copy 1")
	check(mg._recruit_hero(cls, el, UnitFactory.generate_recruit_rolls()), "recruit copy 2")
	if mg.player_units.size() < 2:
		check(false, "both copies must be fielded (got %d)" % mg.player_units.size())
		mg.queue_free()
		return
	var a: VisualUnit = mg.player_units[-2]
	var b: VisualUnit = mg.player_units[-1]
	a.recruit_grade = "B"; b.recruit_grade = "B"   # same grade, or they cannot merge
	a.set_level(4)   # a is higher level → a survives even though b is the one dragged
	var item := ComponentEquipmentRules.generate_item(5, 1)
	mg._equipment_inventory.add_item(item)
	check(mg._equipment_inventory.apply_to_hero(item, b), "gear on consumed copy")
	var count: int = mg.player_units.size()
	# Refused outside prep.
	mg.game_state.current_state = GameState.State.AUTO_BATTLE
	mg._merge_fielded_heroes(b, a)
	check(mg.player_units.size() == count, "no merge mid-battle")
	mg.game_state.current_state = GameState.State.PLAYER_TURN
	mg._merge_fielded_heroes(b, a)   # drag b onto a
	check(mg.player_units.size() == count - 1, "one copy consumed")
	check(a in mg.player_units and is_instance_valid(a), "higher level survives")
	check(a.recruit_grade == "A", "survivor B → A")
	check(item in mg._equipment_inventory.items, "consumed gear back in bag")
	check(mg.battle_grid.get_unit_at(a.grid_position) == a, "survivor still on its cell")
	check(b not in mg.player_units and b not in mg.bench_units, "consumed copy off the roster at once")
	# Field+field merge flies the consumed copy into the survivor first.
	await get_tree().create_timer(MergeVFX.PULL_TIME + 0.2).timeout
	check(not is_instance_valid(b), "consumed node freed after the pull")
	var burst_seen := false
	for ch in mg.battle_grid_node.get_children():
		burst_seen = burst_seen or ch is MergeVFX
	check(burst_seen, "merge burst spawned on the board")
	# The transformation toast spawns itself once the beat lands. Catch it the
	# frame it appears: it must START on the old grade / old stats.
	var waited := 0.0
	while not mg._merge_toasts.is_busy() and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var toast: MergeResultScreen = mg._merge_toasts.active as MergeResultScreen
	check(toast != null and is_instance_valid(toast), "transformation toast appears after the merge beat")
	if toast != null:
		check(toast._badge.text == "B", "toast starts on the OLD grade (B)")
		check(mg._any_modal_open(), "toast counts as a modal (no tooltip bleed-through)")
		var hp0: Dictionary = toast._rows[0] if not toast._rows.is_empty() else {}
		check(not hp0.is_empty() and hp0["main"].text == _fmt_stat(hp0["a"], hp0["fmt"])
			and hp0["gain"].text.begins_with("+"), "first row starts as old value + full gain")
		var end := {}
		await _await_toast(toast, end)
		check(end.get("finished", false), "toast dismisses itself, no input sent")
		check(end.get("badge", "") == "A", "toast ends on the NEW grade (A)")
		check(end.get("rows_ok", false), "every changed row ends exactly on the live stat, gain gone")
		await get_tree().process_frame
		check(not is_instance_valid(toast) and not mg._merge_toasts.is_busy(), "toast freed and the queue is idle")
	var saved: Dictionary = {}
	for h in RunSave.read_data().get("heroes", []):
		if int(h.get("class", -1)) == int(cls):
			saved = h
	check(str(saved.get("grade", "")) == "A", "grade persisted to save")
	var sg: Dictionary = saved.get("growth_bonus", {})
	var growth_ok := sg.size() == a.growth_bonus.size()
	for key in a.growth_bonus:
		growth_ok = growth_ok and is_equal_approx(float(sg.get(key, -999.0)), float(a.growth_bonus[key]))
	check(growth_ok, "growth persisted to save")
	# Downed copies can't merge.
	check(mg._recruit_hero(cls, el, UnitFactory.generate_recruit_rolls()), "recruit copy 3")
	var c: VisualUnit = mg.player_units[-1]
	c.recruit_grade = "A"   # same grade as a (now A) so only the downed state blocks it
	mg._downed_heroes.append(c)
	var cnt2: int = mg.player_units.size()
	mg._merge_fielded_heroes(c, a)
	check(mg.player_units.size() == cnt2 and a.recruit_grade == "A", "downed copy refused")
	mg._downed_heroes.erase(c)

	# ── Bench copy merges with a fielded copy (drag-from-bench path) ──
	mg._bench_unit(c)
	check(c in mg.bench_units, "copy 3 benched")
	var fielded_before: int = mg.player_units.size()
	check(mg._try_merge_heroes(c, a), "bench → field merge accepted")
	check(a.recruit_grade == "S" and c not in mg.bench_units, "bench copy consumed, A → S")
	check(mg.player_units.size() == fielded_before, "field count unchanged by a bench merge")
	await get_tree().process_frame
	check(not is_instance_valid(c), "benched copy freed immediately")
	# Drop-target lookup finds the fielded copy under its cell.
	check(mg._recruit_hero(cls, el, UnitFactory.generate_recruit_rolls()), "recruit copy 4")
	var d: VisualUnit = mg.player_units[-1]
	d.recruit_grade = "S"   # matches a (S after the bench merge) for the panel merge below
	mg._bench_unit(d)
	var cell_pos: Vector2 = mg.get_viewport().get_canvas_transform() \
		* mg.battle_grid.to_global(mg.battle_grid.grid_to_world(a.grid_position))
	check(mg._merge_target_at(cell_pos, d) == a, "drop target = fielded copy under the cursor")
	check(mg._merge_target_at(cell_pos + Vector2(9999, 0), d) == null, "no target off the board")

	# ── Merge panel ──
	check(mg._merge_btn != null and mg._merge_btn.get_parent() == mg.use_items_btn.get_parent(),
		"Merge Heroes button sits with Equipment")
	mg._on_merge_pressed()
	var panel: HeroMergePanel = mg._merge_panel
	check(panel.visible, "panel opens")
	check(panel._groups().has(cls) and panel._groups()[cls].size() == 2, "panel lists the duplicate pair")
	check(panel._picked.size() == 2 and not panel._merge_btn.disabled, "two copies pre-picked, MERGE enabled")
	check(mg._any_modal_open(), "panel counts as a modal")
	panel._on_merge_pressed()
	check(a.recruit_grade == "S+" and d not in mg.bench_units, "panel MERGE runs the shared merge (S → S+)")
	check(panel._groups().is_empty() and panel._empty_lbl.visible, "panel refreshed to empty state")
	# S+ is the cap: another copy can't merge into it.
	check(mg._recruit_hero(cls, el, UnitFactory.generate_recruit_rolls()), "recruit copy 5")
	var e: VisualUnit = mg.player_units[-1]
	e.recruit_grade = "S+"   # same grade, so the ONLY blocker is the S+ cap
	panel.refresh(mg.player_units, mg.bench_units)
	check(panel._merge_btn.disabled, "MERGE disabled when survivor is S+")
	check(not mg._try_merge_heroes(e, a), "S+ merge refused")
	panel.visible = false

	# ── Lesser copies are partial merges (drag AND panel) ──
	var dcls := UnitBase.UnitClass.DOC
	var del := UnitFactory.element_for_class(dcls)
	check(mg._recruit_hero(dcls, del, UnitFactory.generate_recruit_rolls()), "recruit doc 1")
	check(mg._recruit_hero(dcls, del, UnitFactory.generate_recruit_rolls()), "recruit doc 2")
	check(mg._recruit_hero(dcls, del, UnitFactory.generate_recruit_rolls()), "recruit doc 3")
	var d_hi: VisualUnit = mg.player_units[-3]
	var a1: VisualUnit = mg.player_units[-2]
	var a2: VisualUnit = mg.player_units[-1]
	d_hi.recruit_grade = "S"; d_hi.set_level(6); d_hi.merge_progress = 0
	a1.recruit_grade = "A"; a1.set_level(3)
	a2.recruit_grade = "A"; a2.set_level(2)
	var n_before: int = mg.player_units.size()
	# Through the panel: preview says it is part of a merge.
	mg._on_merge_pressed()
	panel._selected_class = dcls
	panel._picked = [d_hi, a1]
	panel.refresh(mg.player_units, mg.bench_units)
	check(not panel._merge_btn.disabled and panel._preview.text.contains("of a merge") and panel._preview.text.contains("1/2"),
		"the panel previews an A into an S as +1/2 of a merge")
	panel._on_merge_pressed()
	check(d_hi in mg.player_units and d_hi.recruit_grade == "S" and d_hi.merge_progress == 8 and d_hi.level == 6,
		"the S stays S and banks half a merge (8 of 16)")
	check(a1 not in mg.player_units and mg.player_units.size() == n_before - 1, "the A copy was used up")
	check(mg.info_label.text.contains("progress") and mg.info_label.text.contains("1/2"), "the player is told the progress")
	var progress_saved := false
	var saved_hero: Dictionary = {}
	for h in RunSave.read_data().get("heroes", []):
		if int(h.get("class", -1)) == int(dcls) and int(h.get("merge_progress", 0)) == 8 and str(h.get("grade", "")) == "S":
			progress_saved = true
			saved_hero = h
	check(progress_saved, "merge progress is saved with the hero")
	# ...and restored on resume (a copy of the saved hero must come back with its progress).
	mg._restore_hero(saved_hero)
	var restored_ok := false
	for u in (mg.player_units + mg.bench_units).duplicate():
		if is_instance_valid(u) and u != d_hi and u.unit_class == dcls and u.recruit_grade == "S" and u.merge_progress == 8:
			restored_ok = true
			# Remove the test copy again so it can't change later group checks.
			mg.battle_grid.purge_unit(u)
			mg.player_units.erase(u)
			mg.bench_units.erase(u)
			u.queue_free()
	check(restored_ok, "merge progress comes back when the run is resumed")
	# The second A (dragged) completes it.
	check(mg._try_merge_heroes(a2, d_hi), "the second A is accepted")
	check(d_hi.recruit_grade == "S+" and d_hi.merge_progress == 0 and d_hi.level == 6, "two As take an S to S+")
	check(a2 not in mg.player_units, "the second A was used up")
	# The higher grade always survives, even when it is the one being dragged ONTO a lesser hero.
	check(mg._recruit_hero(dcls, del, UnitFactory.generate_recruit_rolls()), "recruit doc 4")
	check(mg._recruit_hero(dcls, del, UnitFactory.generate_recruit_rolls()), "recruit doc 5")
	var hi2: VisualUnit = mg.player_units[-2]
	var lo2: VisualUnit = mg.player_units[-1]
	hi2.recruit_grade = "A"; hi2.set_level(2); hi2.merge_progress = 0
	lo2.recruit_grade = "C"; lo2.set_level(9); lo2.merge_progress = 0
	check(mg._try_merge_heroes(hi2, lo2), "dragging the A onto a higher-LEVEL C works")
	check(hi2 in mg.player_units and lo2 not in mg.player_units and hi2.recruit_grade == "A" and hi2.merge_progress == 2
		and hi2.level == 2, "the A survives at its own level and banks 2 of 8")
	# Auto-pick prefers a legal same-grade pair over the two highest levels.
	check(mg._recruit_hero(dcls, del, UnitFactory.generate_recruit_rolls()), "recruit doc 3")
	check(mg._recruit_hero(dcls, del, UnitFactory.generate_recruit_rolls()), "recruit doc 4")
	var x1: VisualUnit = mg.player_units[-2]
	var x2: VisualUnit = mg.player_units[-1]
	x1.recruit_grade = "A"; x1.set_level(2)
	x2.recruit_grade = "A"; x2.set_level(2)
	panel._selected_class = dcls
	panel._picked.clear()
	panel.refresh(mg.player_units, mg.bench_units)
	check(panel._picked.size() == 2 and d_hi not in panel._picked
		and UnitFactory.grade_of(panel._picked[0]) == "A" and UnitFactory.grade_of(panel._picked[1]) == "A",
		"auto-pick chose a legal A + A pair (a rank-up), not the S+ that nothing can merge into")
	# Nothing, not even a lesser copy, merges into an S+.
	var cnt_s: int = mg.player_units.size()
	check(not mg._try_merge_heroes(x1, d_hi) and mg.player_units.size() == cnt_s and x1 in mg.player_units,
		"a lesser copy cannot be merged into an S+")
	panel.visible = false
	_integration_done = true
	mg.queue_free()
	for i in range(3): await get_tree().process_frame
