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

# Screen-space hover radius (canvas-transformed) — same technique main_game
# already uses for the held-item badge tooltip (2026-07-21 hover-collect).
const HOVER_RADIUS := 24.0

# coin_value lets meta-progression bonuses (Bounty: +gold per kill) drop ONE
# richer coin instead of flooding the field with extra coin nodes.
func spawn_coins(world_pos: Vector2, count: int, coin_value: int = 1) -> void:
	for i in range(count):
		var c := GoldCoin.new()
		c.value = coin_value
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
# staggered so it reads as a wave. `target` is a GLOBAL screen position (the
# gold counter's UI rect center) — convert it to local space before handing it
# to GoldCoin, since coins live under this node (itself offset from the true
# origin by the battlefield's centering transform). Passing the raw global
# value double-counted that offset and sent every coin arcing toward a point
# well past the actual counter (2026-07-04 user report).
func vacuum_all(target: Vector2) -> void:
	var local_target := to_local(target)
	var i := 0
	for c in get_children():
		if c is GoldCoin:
			c.start_vacuum(local_target, float(i) * 0.05)
			i += 1

# Hand-collect: any IDLE coin under the mouse starts vacuuming toward `target`
# immediately, individually (2026-07-21 user request — no need to wait for
# round end). Call every frame with the current mouse position; repeated
# calls while still hovering are harmless (start_vacuum no-ops once vacuuming).
func check_hover(mouse_screen: Vector2, target: Vector2) -> void:
	var local_target := to_local(target)
	for c in get_children():
		if c is GoldCoin and c.state == GoldCoin.State.IDLE:
			var screen_pos: Vector2 = c.get_global_transform_with_canvas().origin
			if screen_pos.distance_to(mouse_screen) <= HOVER_RADIUS:
				c.start_vacuum(local_target, 0.0)
