extends Node
# Skipped-wave payout (2026-09-29): an event/merchant/camp node replaces its
# stage's fight, so entering one must pay that stage's Normal-clear XP and the
# early crystal floor (main_game._grant_skipped_wave_rewards). Also prints the
# per-stage amounts for waves 1-9 so a retune can read them without a run.
# Run with APPDATA pointed at a scratch folder whose path contains
# "skipwave-check" — main_game touches the save.
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _hero_xp_total(h) -> Array:
	return [h.level, h.current_xp]

func _enter_event_at(mg, round_no: int) -> Dictionary:
	var before := {
		"player_xp": mg.game_state.player_xp, "player_level": mg.game_state.player_level,
		"crystals": mg.game_state.crystals, "round": mg.game_state.battle_round,
		"heroes": mg.player_units.map(_hero_xp_total),
	}
	mg._grant_skipped_wave_rewards(round_no)
	return before

func _ready() -> void:
	if not "skipwave-check" in OS.get_environment("APPDATA"):
		push_error("SKIPWAVE_CHECK requires an isolated APPDATA folder containing skipwave-check.")
		get_tree().quit(2)
		return
	seed(482)
	var mg = load("res://scenes/main_game.tscn").instantiate()
	add_child(mg)
	for i in range(30): await get_tree().process_frame
	mg._relic_screen.hide()
	mg._hero_shop.hide()
	mg._call_to_arms_pending = false
	mg.game_state.battle_round = 2
	mg._recruit_hero(UnitBase.UnitClass.RIOT, UnitBase.Element.NORMAL, {})
	mg._recruit_hero(UnitBase.UnitClass.RIOT, UnitBase.Element.NORMAL, {})

	# Wave 3 (inside the crystal-floor window).
	var b: Dictionary = _enter_event_at(mg, 3)
	var gained_account: bool = mg.game_state.player_level > b["player_level"] \
		or mg.game_state.player_xp > b["player_xp"]
	check(gained_account, "event at wave 3 paid no account XP")
	var after_heroes: Array = mg.player_units.map(_hero_xp_total)
	for i in range(after_heroes.size()):
		check(after_heroes[i] != b["heroes"][i], "hero %d gained no XP from the event" % i)
	check(mg.game_state.crystals == b["crystals"] + Balance.EARLY_WAVE_CRYSTAL_BONUS,
		"event at wave 3 paid %d crystals, expected %d" % [
			mg.game_state.crystals - b["crystals"], Balance.EARLY_WAVE_CRYSTAL_BONUS])
	check(mg.game_state.battle_round == b["round"], "the payout moved battle_round")

	# Wave 12 (past the window): XP yes, crystal no.
	var b2: Dictionary = _enter_event_at(mg, 12)
	check(mg.game_state.crystals == b2["crystals"], "event at wave 12 paid the early crystal floor")

	# Informational: what each stage pays (the same math the function uses).
	var dir := WaveDirector.new()
	for r in range(1, 10):
		var hp := 0.0
		var xp := 0.0
		for e in dir.generate_wave_spec(r, WaveScaler.Difficulty.NORMAL, mg.battle_grid.grid_width, -1, 0):
			var u = dir.create_enemy_for_entry(e, r)
			if u:
				hp += u.max_hp
				xp += u.xp_reward
				u.free()
		print("SKIPWAVE wave %d: enemy hp %d, kill xp %d -> team hero xp ~%d, account xp %d" % [
			r, hp, xp, (hp / float(mg.ROW_XP_PER_DMG) + xp) * mg.SKIPPED_WAVE_ROW_MULT,
			xp * mg.PLAYER_XP_SHARE])

	print("SKIPWAVE_CHECK: ", "ALL PASS" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
