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
# Every coin now spawns EXACTLY at `world_pos` and travels out along its own
# arc (see GoldCoin._ready). The old random offset scattered coins with no path
# connecting them to the body, which read as "discs appeared" rather than
# "the corpse dropped gold" (2026-09-16 report).
func spawn_coins(world_pos: Vector2, count: int, coin_value: int = 1,
		power: float = 1.0) -> void:
	for i in range(count):
		var c := GoldCoin.new()
		c.value = coin_value
		c.position = world_pos
		c.toss_index = i
		c.toss_total = count
		c.toss_power = power
		c.collected.connect(func(v: int): coin_collected.emit(v))
		add_child(c)

# Round-reward gold. It used to rain onto random cells across the enemy half,
# which put lone coins in the far corners with nothing tying them to anything.
# Now it bursts from `origin` (main_game hands us the last enemy to fall) with
# a wider toss so a big payout still spreads instead of stacking on one point.
# Without an origin it falls back to the centre of the enemy half.
func spawn_burst(count: int, origin = null) -> void:
	if count <= 0:
		return
	var from: Vector2
	if origin is Vector2:
		from = origin
	elif battle_grid:
		from = battle_grid.grid_to_world(Vector2i(battle_grid.grid_width / 2, 1))
	else:
		return
	# Big payouts get a wider fan so 10+ coins still read as separate drops.
	var power: float = clampf(1.0 + float(count) * 0.06, 1.0, 2.2)
	spawn_coins(from, count, 1, power)

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
