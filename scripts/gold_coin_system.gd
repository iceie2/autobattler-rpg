class_name GoldCoinSystem
extends Node2D
# ══════════════════════════════════════════════════════════════════════════════
# Owns the physical gold drops (economy v3) — extracted from main_game.gd in
# the 2026-07-04 refactor. Coins spawn where enemies die (or rain onto the
# enemy half for round rewards), idle on the field, then the round-end vacuum
# spirals every coin into the gold counter. Gold is only credited when a coin
# ARRIVES — main_game listens to `coin_collected` and adds to game_state.
# ══════════════════════════════════════════════════════════════════════════════

signal coin_collected(value: int)

# Set by main_game after construction — used to pick rain cells for bursts.
var battle_grid: BattleGrid = null

func spawn_coins(world_pos: Vector2, count: int) -> void:
	for i in range(count):
		var c := GoldCoin.new()
		c.position = world_pos + Vector2(randf_range(-16.0, 16.0), randf_range(-10.0, 8.0))
		c.collected.connect(func(v: int): coin_collected.emit(v))
		add_child(c)

# Reward gold rains across the enemy half of the board (visibly "comes down").
func spawn_burst(count: int) -> void:
	if not battle_grid:
		return
	for i in range(count):
		var cell := Vector2i(randi() % battle_grid.grid_width, randi() % 4)
		spawn_coins(battle_grid.grid_to_world(cell), 1)

# THE vacuum: every coin on the field spirals into `target` (the gold counter),
# staggered so it reads as a wave.
func vacuum_all(target: Vector2) -> void:
	var i := 0
	for c in get_children():
		if c is GoldCoin:
			c.start_vacuum(target, float(i) * 0.05)
			i += 1
