extends Node2D
class_name StormHazard

# A roaming board hazard (Zolt's Thunderstorm). It is NOT a unit — it never enters
# the player/enemy arrays, can't be targeted or attacked, and doesn't count toward
# win/loss. It picks one direction and drifts that way a cell at a time (only
# re-rolling direction when it would leave the grid), periodically zapping its
# own tile (full damage + brief stun) and its 8 neighbours (half damage, no
# stun). Persists until the round ends (the manager frees it) — storms can and
# do stack up near Zolt if he recasts before old ones wander off; that's
# intentional, it's his power fantasy (2026-07-06, user confirmed).
#
# This is the first of a planned family of board effects (fire patches, poison
# clouds, …). The manager ticks it with scaled dt so pause / slow-mo affect it too.

var battle_grid: BattleGrid = null
var manager = null                 # AutoBattleManager (for the live opponents list)
var caster: UnitBase = null
var owner_is_player: bool = true   # whose enemies this storm zaps
var damage: int = 30
var grid_pos: Vector2i = Vector2i.ZERO

const MOVE_INTERVAL := 1.5         # seconds between hops
const ZAP_DELAY := 0.5             # pause after arriving, then it strikes
const ZAP_RADIUS := 1              # Chebyshev tiles hit around the storm
const CENTER_STUN := 0.5           # stun applied only to the storm's own cell
const RING_DAMAGE_MULT := 0.5      # the 8 surrounding cells take half the center's damage

const DIRS: Array[Vector2i] = [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),
	Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]

var _move_accum: float = 0.0
var _has_zapped: bool = false
var _anim: float = 0.0
# Persistent heading (2026-07-06 user report: re-rolling a fresh random
# direction every hop is a memoryless random walk, which statistically
# wanders back on itself and reads as "hovering near Zolt" instead of
# actually crossing the board. Committing to one direction and only
# re-rolling when it runs off the grid makes the storm travel in a
# straight-ish line instead.
var _drift_dir: Vector2i = Vector2i.ZERO

func setup(p_grid: BattleGrid, p_manager, p_caster: UnitBase, p_damage: int, p_cell: Vector2i) -> void:
	battle_grid = p_grid
	manager = p_manager
	caster = p_caster
	owner_is_player = p_caster.is_player_unit if (p_caster and is_instance_valid(p_caster)) else true
	damage = p_damage
	grid_pos = p_cell
	_drift_dir = DIRS[randi() % DIRS.size()]
	if battle_grid:
		global_position = battle_grid.to_global(battle_grid.grid_to_world(grid_pos))
	z_index = 5
	queue_redraw()

# Driven by the manager's _process so pacing (pause / time-scale) applies.
func tick(dt: float) -> void:
	_anim += dt
	_move_accum += dt
	# After arriving at a tile, strike once ZAP_DELAY into the dwell.
	if not _has_zapped and _move_accum >= ZAP_DELAY:
		_zap()
		_has_zapped = true
	if _move_accum >= MOVE_INTERVAL:
		_move_accum = 0.0
		_has_zapped = false
		_hop()
	queue_redraw()

func _hop() -> void:
	if not battle_grid:
		return
	# Keep drifting the same way; only re-roll direction when it would leave
	# the grid (so the storm crosses the board instead of jittering in place).
	var c: Vector2i = grid_pos + _drift_dir
	if battle_grid.is_valid_position(c):
		grid_pos = c
		global_position = battle_grid.to_global(battle_grid.grid_to_world(grid_pos))
		return
	var order := DIRS.duplicate()
	order.shuffle()
	for d in order:
		var alt: Vector2i = grid_pos + d
		if battle_grid.is_valid_position(alt):
			_drift_dir = d
			grid_pos = alt
			global_position = battle_grid.to_global(battle_grid.grid_to_world(grid_pos))
			return

# Center cell (where the storm currently sits) takes full damage + a brief
# stun; the 8 surrounding cells take half damage and no stun (2026-07-06 user
# request — previously every one of the 9 cells took identical damage).
func _zap() -> void:
	if not (manager and is_instance_valid(manager)):
		return
	var opponents: Array = manager.enemy_units if owner_is_player else manager.player_units
	var ring_damage: int = int(round(float(damage) * RING_DAMAGE_MULT))
	for opp in opponents:
		if not (opp and is_instance_valid(opp)):
			continue
		var dx: int = abs(opp.grid_position.x - grid_pos.x)
		var dy: int = abs(opp.grid_position.y - grid_pos.y)
		if dx == 0 and dy == 0:
			opp.take_damage(damage, UnitBase.Element.LIGHTNING, caster)
			opp.stun_time = maxf(opp.stun_time, CENTER_STUN)
			if caster and is_instance_valid(caster):
				caster.damage_dealt += damage
		elif maxi(dx, dy) <= ZAP_RADIUS:
			opp.take_damage(ring_damage, UnitBase.Element.LIGHTNING, caster)
			if caster and is_instance_valid(caster):
				caster.damage_dealt += ring_damage

func _draw() -> void:
	var cs: float = float(battle_grid.cell_size) if battle_grid else 110.0
	var r: float = cs * 0.55
	# Dark storm cloud body
	var pulse: float = 0.85 + sin(_anim * 6.0) * 0.15
	draw_circle(Vector2.ZERO, r * pulse, Color(0.18, 0.16, 0.28, 0.55))
	draw_circle(Vector2(-r*0.4, -r*0.1), r * 0.55 * pulse, Color(0.22, 0.2, 0.34, 0.5))
	draw_circle(Vector2(r*0.4, r*0.05), r * 0.5 * pulse, Color(0.2, 0.18, 0.3, 0.5))
	# Crackling bolts toward the strike zone, brighter just before a zap
	var charge: float = clampf(_move_accum / ZAP_DELAY, 0.0, 1.0) if not _has_zapped else 0.2
	var bolt_col := Color(1.0, 1.0, 0.5, 0.5 + charge * 0.5)
	for i in range(4):
		var ang: float = _anim * 3.0 + i * (TAU / 4.0)
		var prev := Vector2.ZERO
		for s in range(1, 4):
			var frac: float = float(s) / 3.0
			var jit: float = sin(_anim * 20.0 + i * 3 + s) * r * 0.18
			var perp := Vector2(-sin(ang), cos(ang)) * jit
			var nxt := Vector2(cos(ang), sin(ang)) * (r * frac) + perp
			draw_line(prev, nxt, bolt_col, 2.0)
			prev = nxt
