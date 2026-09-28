extends Node
# VD-21 main_game checks, the halves scenes/relic_rules_smoke.tscn cannot reach:
#   - a picked relic reaches benched heroes, not only the board
#   - a later biome's relic node rolls, titles and paints as its first round,
#     and offers a follow-up piece instead of the run-start seed
#   - on-kill growth survives the battle-end synergy revert, the next fight,
#     and a save/resume
# It drives the real main_game, which writes the run and progression saves and
# telemetry, so it runs ONLY in a disposable profile - point APPDATA at a
# scratch folder whose path contains /vd21-relic-rules/isolated-profile/:
#   APPDATA=<scratch>/vd21-relic-rules/isolated-profile \
#     godot --headless --path . res://scenes/tools/relic_rules_integration.tscn
# Prints RELIC_RULES_INTEGRATION: ALL PASS. Exit 0 pass, 1 fail, 2 refused.

var failures: Array = []

func check(ok: bool, label: String) -> void:
	print("  %s: %s" % ["ok" if ok else "FAIL", label])
	if not ok:
		failures.append(label)

func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("/vd21-relic-rules/isolated-profile/"):
		push_error("Refusing the VD-21 integration test outside its disposable profile")
		get_tree().quit(2)
		return
	RunSave.resume_on_start = false
	var mg = load("res://scenes/main_game.tscn").instantiate()
	add_child(mg)
	await _frames(30)
	if not mg.MAP_MODE:
		check(false, "MAP_MODE is on (the relic node checks need the run map)")

	# Opening beat: a relic with no stat effect, then the free starting hero.
	mg._on_relic_chosen(Relic.by_id("d_gold"))
	await _frames(5)
	if not mg._hero_shop._card_btns.is_empty():
		mg._hero_shop._card_btns[0].emit_signal("pressed")
	await _frames(5)
	check(mg.player_units.size() == 1, "a starting hero is on the board")
	if mg.player_units.is_empty():
		_finish()
		return
	var board_hero = mg.player_units[0]

	# ── bench heroes get a picked relic ──────────────────────────────────────
	var cls := UnitBase.UnitClass.RIOT
	check(mg._recruit_hero(cls, UnitFactory.element_for_class(cls), {}), "a second hero is recruited")
	var second = null
	for u in mg.player_units + mg.bench_units:
		if u != board_hero:
			second = u
	if second in mg.player_units:
		mg._bench_unit(second)
	check(second != null and second in mg.bench_units, "the second hero is on the bench")
	var atk_board: int = board_hero.attack_damage
	var atk_bench: int = second.attack_damage
	mg._on_relic_chosen(Relic.by_id("b_atk"))   # +30% team attack damage
	await _frames(3)
	check(board_hero.attack_damage == int(round(atk_board * 1.30)),
		"the board hero gets the picked relic (%d -> %d)" % [atk_board, board_hero.attack_damage])
	check(second.attack_damage == int(round(atk_bench * 1.30)),
		"the benched hero gets it too (%d -> %d)" % [atk_bench, second.attack_damage])

	# ── a later biome's relic node ───────────────────────────────────────────
	mg._relic_screen.visible = false
	mg._run_map = RunMap.generate(1, 0, true)
	var starts: Array = mg._run_map.available_next()
	var opening_ok: bool = not starts.is_empty() and int(starts[0]["type"]) == RunMap.NodeType.RELIC
	check(opening_ok, "biome 1 opens on a relic node")
	if opening_ok:
		mg._on_map_node_chosen(starts[0])
		await _frames(3)
		check(mg._relic_screen_wave == 11, "biome 1's relic node rolls as round 11 (got %d)" % mg._relic_screen_wave)
		check(mg.background_layer.current_biome == 1,
			"it paints biome 1, not biome 0 (got %d)" % mg.background_layer.current_biome)
		check(mg._relic_screen.visible, "its relic screen opens")
		var sub = mg._relic_screen.get("_sub_lbl")
		if sub:
			check(String(sub.text).begins_with("Wave 11"), "the screen is titled Wave 11 (%s)" % sub.text)
		check(mg._relic_offer_ctx(mg._relic_screen_wave).has("team_verbs"),
			"it offers a piece for the team's verbs, not the run-start seed")
		mg._relic_screen.visible = false

	# ── on-kill growth across fights and a resume ─────────────────────────────
	mg._on_relic_chosen(Relic.by_id("s_soul"))   # +2% attack per kill
	await _frames(3)
	var dead_foe: UnitBase = EnemyFactory.create_by_type("goblin")
	add_child(dead_foe)
	dead_foe.current_hp = 0
	var atk0: int = board_hero.attack_damage
	mg._apply_team_synergies()
	var boosted: int = board_hero.attack_damage
	for _k in range(25):
		board_hero.apply_relic_on_hit(dead_foe, 10, true)
	# The base stays the fight's (synergy-boosted) attack without kill growth.
	var earned := int(floor(25.0 * 0.02 * float(boosted) + 0.000001))
	mg._revert_team_synergies()
	check(earned > 0 and board_hero.attack_damage == atk0 + earned,
		"25 kills survive the battle-end revert (%d + %d, got %d)" % [atk0, earned, board_hero.attack_damage])
	mg._apply_team_synergies()
	mg._revert_team_synergies()
	check(board_hero.attack_damage == atk0 + earned, "the growth is still there after the next fight")

	var d: Dictionary = mg._hero_to_dict(board_hero, false)
	check(is_equal_approx(float(d.get("r_kill_atk", -1.0)), board_hero.relic_kill_atk_gain),
		"the hero's save record carries the kill total")
	d["bench"] = true   # restore onto the bench: the board cell is taken
	mg._restore_hero(d)
	var restored = mg.bench_units[-1]
	check(restored != second and restored.attack_damage == board_hero.attack_damage \
			and is_equal_approx(restored.relic_kill_atk_gain, board_hero.relic_kill_atk_gain),
		"a resumed hero keeps its attack and kill total (%d, %.2f)" % [restored.attack_damage, restored.relic_kill_atk_gain])
	var gain_before: float = restored.relic_kill_atk_gain
	var base: float = float(restored.attack_damage - restored.kill_atk_whole())
	restored.apply_relic_on_hit(dead_foe, 10, true)
	check(is_equal_approx(restored.relic_kill_atk_gain - gain_before, base * 0.02),
		"after a resume a kill still adds 2% of the attack without kill growth")
	mg.game_state.battle_round = 1   # save_run writes nothing before round 1
	mg.save_run()
	var found := false
	for h in RunSave.read_data().get("heroes", []):
		if float(h.get("r_kill_atk", 0.0)) > 0.0:
			found = true
	check(found, "the run checkpoint writes the kill total")
	_finish()

func _finish() -> void:
	print("RELIC_RULES_INTEGRATION: " + ("ALL PASS" if failures.is_empty()
		else "%d FAILED -> %s" % [failures.size(), ", ".join(failures)]))
	get_tree().quit(0 if failures.is_empty() else 1)
