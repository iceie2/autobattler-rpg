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
