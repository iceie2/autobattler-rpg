extends Node
# ══════════════════════════════════════════════════════════════════════════════
# ROUND-START CEREMONY SMOKE (2026-08-02) — row bonuses (heal + XP) and revives
# no longer resolve instantly at round end; they're measured there and paid out
# by main_game._play_round_start_ceremony at the start of the next round. That
# payout is an await chain driven by process frames, which the plain boot smoke
# never reaches (it stops at round 1). This scene instantiates the REAL
# main_game, stages a pending payout by hand, awaits the ceremony, and asserts
# the numbers actually landed.
#
# Run:  godot --headless res://scenes/ceremony_smoke.tscn
# Exit code 0 = pass, 1 = fail.
# ══════════════════════════════════════════════════════════════════════════════

var _fails: Array = []

func _ready() -> void:
	var mg_scene := load("res://scenes/main_game.tscn") as PackedScene
	var mg := mg_scene.instantiate()
	add_child(mg)
	for i in range(30):
		await get_tree().process_frame

	# The player starts with an empty field (heroes are recruited in prep), so
	# stage two through the same recruit path the hero shop uses. The level-1
	# field cap can be 1, which would bench the second hero.
	mg.max_player_units = maxi(mg.max_player_units, 2)
	# Recruit real roster heroes, not WARRIOR: the legacy base classes were dropped
	# from UnitFactory.CLASS_BASE_STATS, so create_unit(WARRIOR) has been failing
	# on the table lookup and this smoke test could never get past "no starting
	# heroes" (found 2026-08-02). Starter heroes are always unlocked, so these two
	# recruit on any save.
	mg._recruit_hero(UnitBase.UnitClass.BLOODHOUND, UnitFactory.element_for_class(UnitBase.UnitClass.BLOODHOUND), {})
	mg._recruit_hero(UnitBase.UnitClass.BOUNCER, UnitFactory.element_for_class(UnitBase.UnitClass.BOUNCER), {})
	await get_tree().process_frame

	var heroes: Array = mg.player_units.filter(func(u): return u and is_instance_valid(u))
	if heroes.size() < 1:
		print("CEREMONY_SMOKE: FAILED -> no starting heroes to test with")
		get_tree().quit(1)
		return

	# ── Survivor: takes a row heal + XP ───────────────────────────────────────
	var alive = heroes[0]
	alive.current_hp = maxi(1, int(alive.max_hp * 0.4))
	var hp_before: int = alive.current_hp
	var xp_before: float = alive.current_xp
	var heal_amt: int = int(alive.max_hp * 0.25)

	# ── Casualty: down at 0 HP, revived by the ceremony, earns XP but no heal ─
	var downed = heroes[1] if heroes.size() > 1 else null
	if downed:
		mg.player_units.erase(downed)
		downed.current_hp = 0
		mg._downed_heroes.append(downed)

	mg._pending_row_bonuses = [{
		"unit": alive, "heal": heal_amt, "xp": 5.0, "front_t": 1.0, "revive": false,
	}]
	if downed:
		mg._pending_row_bonuses.append({
			"unit": downed, "heal": 0, "xp": 5.0, "front_t": 0.0, "revive": true,
		})

	await mg._play_round_start_ceremony()

	_check(alive.current_hp == mini(alive.max_hp, hp_before + heal_amt),
			"row heal applied (%d → %d, wanted +%d)" % [hp_before, alive.current_hp, heal_amt])
	_check(alive.current_xp > xp_before or alive.level > 1,
			"row XP granted (%.1f → %.1f)" % [xp_before, alive.current_xp])
	if downed:
		_check(downed.current_hp > 0, "downed hero revived (%d HP)" % downed.current_hp)
		_check(downed.current_hp <= int(downed.max_hp * 0.15),
				"revive lands at ~10%% HP, not 10%% + a row heal (%d/%d)" % [
					downed.current_hp, downed.max_hp])
		_check(downed in mg.player_units, "revived hero rejoined the roster")
		_check(mg._downed_heroes.is_empty(), "downed list drained")

	await get_tree().process_frame   # let the queue_free'd XP bars actually go

	_check(mg._pending_row_bonuses.is_empty(), "pending payouts consumed")
	_check(not mg._ceremony_active, "ceremony released the board")
	# The temporary XP bars are children of the heroes — they must not survive.
	var leftover := 0
	for h in mg.player_units:
		if h and is_instance_valid(h):
			for c in h.get_children():
				if c is XPGainBar:
					leftover += 1
	_check(leftover == 0, "temporary XP bars cleaned up (%d left)" % leftover)

	# Round 1 (nothing pending) must be a no-op, not a hang or a locked board.
	await mg._play_round_start_ceremony()
	_check(not mg._ceremony_active, "empty ceremony is a no-op")

	# ── VD-18: Quick Learner multiplies the DAMAGE share of battle XP too ────
	# Damage XP is ~96% of hero XP; the node used to reach only the kill share.
	# A known Quick Learner level is set in memory only - nothing between here
	# and the restore saves - so the check means the same on every save.
	var saved_levels: Dictionary = Progression.upgrade_levels.duplicate(true)
	Progression.upgrade_levels["quick_learner"] = 4
	var ql_mult: float = 1.0 + float(Progression.get_bonus("quick_learner")) / 100.0
	# The highest-level hero, so Tutelage (catch-up) can't join the multiplier.
	var probe = null
	for u in mg.player_units:
		if u and is_instance_valid(u) and (probe == null or u.level > probe.level):
			probe = u
	for u in mg.player_units:
		if u and is_instance_valid(u):
			u.damage_dealt = 0
			u.kill_xp = 0
	probe.damage_dealt = 800                 # 100 XP before any multiplier
	mg._snapshot_between_round_bonuses()
	var paid: Dictionary = {}
	for b: Dictionary in mg._pending_row_bonuses:
		if b["unit"] == probe:
			paid = b
	var row_mult: float = lerpf(1.10, 1.40, float(paid.get("front_t", 0.0)))
	Progression.upgrade_levels = saved_levels
	mg._pending_row_bonuses.clear()
	_check(ql_mult > 1.5, "Quick Learner staged in memory (x%.2f)" % ql_mult)
	_check(absf(float(paid.get("xp", 0.0)) - 100.0 * ql_mult * row_mult) < 0.01,
		"damage XP carries Quick Learner (%.1f, want %.1f)" % [float(paid.get("xp", 0.0)), 100.0 * ql_mult * row_mult])

	# ── MAP MODE: level-ups are settled BEFORE the map opens ─────────────────
	# Owner call (2026-09-22): "if we level up we should do our level up screen
	# before we go to the map screen." The claim is about ORDER, so this drives
	# the REAL post-battle path — _on_battle_ended(true) — and records which of
	# the two modals comes up first. That path re-measures the row bonuses
	# itself, so the hero is handed a fight's worth of damage rather than a
	# hand-staged payout: the XP has to travel the same road it does in a run.
	if mg.MAP_MODE:
		mg._ensure_map_for_biome(0)
		var starts: Array = mg._run_map.available_next()
		if not starts.is_empty():
			mg._map_node = mg._run_map.advance_to(String(starts[0]["id"]))
		var fighter = mg.player_units.filter(
			func(u): return u and is_instance_valid(u))[0]
		fighter.damage_dealt = 100000     # far past one level's worth of XP
		mg._run_map_screen.visible = false
		mg._level_up_screen.visible = false
		var lu_seen := false
		var map_before_lu := false
		var overlap := false
		# Not awaited: stepped frame by frame so both modals can be watched.
		mg._on_battle_ended(true)
		for _f in range(900):
			await get_tree().process_frame
			var lu_up: bool = mg._level_up_screen.visible
			var map_up: bool = mg._run_map_screen.visible
			if lu_up and map_up:
				overlap = true
			if lu_up:
				lu_seen = true
				mg._level_up_screen._apply_perk(LevelUpScreen.PERKS[0])
			if map_up:
				map_before_lu = not lu_seen
				break
		_check(lu_seen, "the levelled hero's perk screen came up after the fight")
		_check(not map_before_lu, "the map did NOT open before the level-up screen")
		_check(not overlap, "the level-up screen and the map were never up together")
		_check(mg._run_map_screen.visible, "the map opened once the perk was picked")
		_check(mg._pending_row_bonuses.is_empty(), "the fight was paid out before the map")
		# The next round's own ceremony now has nothing left to pay.
		await mg._play_round_start_ceremony()
		_check(not mg._ceremony_active, "round-start ceremony is a no-op after a map payout")

	# ── VD-19: round rewards are a pick 1 of 3 ───────────────────────────────
	# The map promises only a kind; the real grant path must roll three, show
	# them, and hand over exactly the one picked — for items straight into the
	# bag, for stats on to the "which hero" screen with that perk.
	var specific: int = 0
	for _r in range(60):
		var rolled: Dictionary = RoundReward.roll(WaveScaler.Difficulty.BRUTAL, 3)
		if rolled.has("item") or rolled.has("perk"):
			specific += 1
	_check(specific == 0, "roll() promises only a kind, never a specific item/perk (%d did)" % specific)
	var item_reward := {"type": RoundReward.Type.ITEM, "choice": true, "difficulty": 2, "round": 3}
	var bag_before: int = mg._equipment_inventory.items.size()
	mg._pending_round_reward = item_reward
	mg._grant_round_reward()                   # not awaited: it waits on the pick
	await get_tree().process_frame
	var pick_screen: RewardChoiceScreen = mg._reward_choice_screen
	_check(pick_screen != null and pick_screen.visible, "item reward opened the pick screen")
	if pick_screen:
		_check(pick_screen._card_row.get_child_count() == RoundReward.OPTIONS,
			"pick screen shows %d items" % RoundReward.OPTIONS)
		pick_screen._on_pick(1)
		await get_tree().process_frame
	_check(mg._equipment_inventory.items.size() == bag_before + 1,
		"exactly one item went into the bag (%d -> %d)"
			% [bag_before, mg._equipment_inventory.items.size()])

	mg._pending_round_reward = {"type": RoundReward.Type.STAT_BONUS, "choice": true,
		"difficulty": 1, "round": 3}
	mg._grant_round_reward()
	await get_tree().process_frame
	_check(pick_screen and pick_screen.visible, "stat reward opened the pick screen")
	if pick_screen:
		pick_screen._on_pick(0)
		await get_tree().process_frame
	_check(mg._round_reward_screen.visible, "the picked stat went on to the hero screen")
	_check(not mg._round_reward_screen._chosen_perk.is_empty(),
		"the hero screen was handed the picked perk")
	mg._round_reward_screen.visible = false
	mg._round_reward_screen.done.emit()
	await get_tree().process_frame

	if _fails.is_empty():
		print("CEREMONY_SMOKE: ALL PASS")
		get_tree().quit(0)
	else:
		print("CEREMONY_SMOKE: FAILED -> %s" % str(_fails))
		get_tree().quit(1)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  — %s" % label)
	else:
		_fails.append(label)
		print("  FAIL — %s" % label)
