extends Node
class_name GameState

# Game states
enum State {
	PLAYER_TURN,
	AUTO_BATTLE,
	ENEMY_TURN,
	GAME_OVER
}

# Player turn actions
enum PlayerAction {
	CHANGE_ELEMENT,
	CHANGE_EQUIPMENT,
	USE_ITEMS,
	READY_FOR_BATTLE
}

# Current game state
var current_state: State = State.PLAYER_TURN
var battle_round: int = 0

# Resources
var gold: int = 0
var crystals: int = 0

# ── Player/account level (2026-07-04, TFT-style idea from the balance journal) ──
# Per-RUN progression (resets with the run, unlike Progression's permanent
# meta-upgrades) fed by TOTAL TEAM XP — every hero kill's XP also feeds this
# pool at a flat rate, "raised" vs TFT since this game paces much faster.
# main_game.gd derives max_player_units from player_level (see _team_size_for_level),
# replacing the old flat cap — team size now grows WITH you instead of being
# available in full from turn one.
#
# Curve re-tuned 2026-08-07 (user spec) and now MEASURED, not hand-derived —
# see Balance.PLAYER_XP_GROWTH for the fitted numbers and the
# `--mode=xpcurve` harness that produced them. The 2026-07-09 hand-derived
# pass assumed growth past level 3 would come from "other systems" that never
# arrived, so ×3.2 compounding left the whole upper ladder unreachable.
#
# This curve IS the team-size gate: there is no player-level cap upgrade. A
# fresh account tops out around level 8 because it runs out of XP, not because
# a constant stops it. The crystal tree sells XP RATE (bonus_xp) and SLOTS
# (hero_slots) — never a ceiling.
var player_level: int = 1
var player_xp: float = 0.0
var player_xp_to_level: float = Balance.PLAYER_XP_BASE

signal player_leveled_up(new_level: int)

# Signals
signal state_changed(new_state: State)
signal battle_round_started(round_number: int)
signal player_turn_started()
signal enemy_turn_started()
signal auto_battle_started()

func _ready():
	pass

func change_state(new_state: State) -> void:
	current_state = new_state
	state_changed.emit(new_state)
	
	match new_state:
		State.PLAYER_TURN:
			player_turn_started.emit()
		State.ENEMY_TURN:
			enemy_turn_started.emit()
		State.AUTO_BATTLE:
			auto_battle_started.emit()
		State.GAME_OVER:
			pass

func start_battle_round() -> void:
	battle_round += 1
	battle_round_started.emit(battle_round)
	change_state(State.PLAYER_TURN)

func player_ready_for_battle() -> void:
	change_state(State.AUTO_BATTLE)

func end_auto_battle() -> void:
	change_state(State.ENEMY_TURN)

func end_enemy_turn() -> void:
	# Loop back to auto battle, then player turn
	change_state(State.AUTO_BATTLE)
	await get_tree().create_timer(1.0).timeout
	start_battle_round()

func add_gold(amount: int) -> void:
	gold = max(0, gold + amount)

func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		return true
	return false

func add_crystals(amount: int) -> void:
	crystals += amount

func spend_crystals(amount: int) -> bool:
	if crystals >= amount:
		crystals -= amount
		return true
	return false

func reset_player_level() -> void:
	player_level = 1
	player_xp = 0.0
	player_xp_to_level = Balance.PLAYER_XP_BASE

# Called with a SHARE of each kill's hero XP (see main_game._on_unit_died) —
# a single account-wide pool, not divided per-hero like combat XP is.
func add_player_xp(amount: float) -> void:
	player_xp += amount
	# Player level is UNCAPPED (2026-08-07 user spec: "make it so the player can
	# go higher level but there is a hard cap of team size of 20"). The ladder
	# keeps paying out — it just stops buying board slots once the clamp is hit,
	# so a monster run still shows progress instead of a dead XP bar.
	#
	# The loop terminates without a cap because player_xp_to_level grows by
	# PLAYER_XP_GROWTH (>1) every level, so each level costs strictly more than
	# the last against a finite XP grant.
	while player_xp >= player_xp_to_level:
		player_xp -= player_xp_to_level
		player_level += 1
		player_xp_to_level *= Balance.PLAYER_XP_GROWTH
		player_leveled_up.emit(player_level)
