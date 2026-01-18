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
	gold += amount

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
