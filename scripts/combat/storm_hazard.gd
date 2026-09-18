extends Node2D
class_name StormHazard

# A roaming board hazard (Zolt's Thunderstorm). It is NOT a unit — it never enters
# the player/enemy arrays, can't be targeted or attacked, and doesn't count toward
# win/loss. It drifts one cell at a time toward enemy-dense areas without
# occupying an enemy's exact cell, periodically zapping its
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

const MOVE_INTERVAL := 1.0         # seconds between hops
const ZAP_DELAY := 0.5             # pause after arriving, then it strikes
const ZAP_RADIUS := 1              # Chebyshev tiles hit around the storm
const CENTER_STUN := 0.5           # stun applied only to the storm's own cell
const RING_DAMAGE_MULT := 0.5      # the 8 surrounding cells take half the center's damage

const DIRS: Array[Vector2i] = [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),
	Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]

var _move_accum: float = 0.0
var _has_zapped: bool = false
var _anim: float = 0.0
var _zap_flash: float = 0.0
var _hop_t: float = 1.0
var _hop_from := Vector2.ZERO
var _hop_to := Vector2.ZERO
# Heading supplies momentum to the density steering below. It prevents the
# storm from jittering between equally attractive cells around one formation.
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
	_zap_flash = maxf(0.0, _zap_flash - dt * 2.8)
	if _hop_t < 1.0:
		_hop_t = minf(1.0, _hop_t + dt / 0.34)
		var eased := 1.0 - pow(1.0 - _hop_t, 3.0)
		global_position = _hop_from.lerp(_hop_to, eased)
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
	var opponents: Array = []
	if manager and is_instance_valid(manager):
		opponents = manager.enemy_units if owner_is_player else manager.player_units
	var living: Array = []
	for opp in opponents:
		if opp and is_instance_valid(opp) and opp.current_hp > 0:
			living.append(opp)

	var candidates: Array = []
	for d in DIRS:
		var cell: Vector2i = grid_pos + d
		if not battle_grid.is_valid_position(cell):
			continue
		var on_enemy := false
		for opp in living:
			if opp.grid_position == cell:
				on_enemy = true
				break
		# Storms hunt the formation around units, not the unit-occupied cell.
		if not on_enemy:
			candidates.append({"dir": d, "cell": cell})

	# A completely surrounded storm may cross a unit cell rather than freeze,
	# though normal formations always leave at least one valid adjacent choice.
	if candidates.is_empty():
		for d in DIRS:
			var cell: Vector2i = grid_pos + d
			if battle_grid.is_valid_position(cell):
				candidates.append({"dir": d, "cell": cell})
	if candidates.is_empty():
		return

	var best: Dictionary = candidates[0]
	var best_score := -INF
	for candidate in candidates:
		var d: Vector2i = candidate["dir"]
		var cell: Vector2i = candidate["cell"]
		# Small momentum plus tiny noise keeps the cloud organic. Enemy density is
		# intentionally the dominant term: several nearby units pull harder than
		# one isolated target, while distance falloff makes it converge on combat.
		var score := (0.55 if d == _drift_dir else 0.0)
		if d == -_drift_dir:
			score -= 0.2
		for opp in living:
			var dx: int = abs(opp.grid_position.x - cell.x)
			var dy: int = abs(opp.grid_position.y - cell.y)
			var dist: float = float(maxi(dx, dy))
			score += 2.4 / (dist + 0.5)
		score += randf_range(-0.08, 0.08)
		if score > best_score:
			best_score = score
			best = candidate

	_drift_dir = best["dir"]
	grid_pos = best["cell"]
	_begin_drift_to(battle_grid.to_global(battle_grid.grid_to_world(grid_pos)))

func _begin_drift_to(destination: Vector2) -> void:
	_hop_from = global_position
	_hop_to = destination
	_hop_t = 0.0

# Center cell (where the storm currently sits) takes full damage + a brief
# stun; the 8 surrounding cells take half damage and no stun (2026-07-06 user
# request — previously every one of the 9 cells took identical damage).
func _zap() -> void:
	if not (manager and is_instance_valid(manager)):
		return
	_zap_flash = 1.0
	var opponents: Array = manager.enemy_units if owner_is_player else manager.player_units
	var ring_damage: int = int(round(float(damage) * RING_DAMAGE_MULT))
	for opp in opponents:
		if not (opp and is_instance_valid(opp)):
			continue
		var dx: int = abs(opp.grid_position.x - grid_pos.x)
		var dy: int = abs(opp.grid_position.y - grid_pos.y)
		if dx == 0 and dy == 0:
			var source := caster if caster and is_instance_valid(caster) else null
			opp.take_magic_damage(damage, UnitBase.Element.LIGHTNING, source)
			manager.apply_stun(opp, CENTER_STUN)
			if manager.has_method("_spawn_zolt_point"):
				manager._spawn_zolt_point(ZoltVFX.Mode.AUTO_IMPACT, opp.global_position, 0.42, opp)
				manager._spawn_zolt_point(ZoltVFX.Mode.STUN_RESIDUE, opp.global_position, CENTER_STUN, opp)
			if caster and is_instance_valid(caster):
				caster.damage_dealt += damage
		elif maxi(dx, dy) <= ZAP_RADIUS:
			var source := caster if caster and is_instance_valid(caster) else null
			opp.take_magic_damage(ring_damage, UnitBase.Element.LIGHTNING, source)
			if manager.has_method("_spawn_zolt_point"):
				manager._spawn_zolt_point(ZoltVFX.Mode.AUTO_IMPACT, opp.global_position, 0.28, opp)
			if caster and is_instance_valid(caster):
				caster.damage_dealt += ring_damage

func _draw() -> void:
	var cs: float = float(battle_grid.cell_size) if battle_grid else 110.0
	var r: float = cs * 0.48
	var pulse: float = 0.92 + sin(_anim * 5.0) * 0.08
	# The nine gameplay cells are visible during the pre-strike dwell.
	var charge: float = clampf(_move_accum / ZAP_DELAY, 0.0, 1.0) if not _has_zapped else 0.2
	for y in range(-1, 2):
		for x in range(-1, 2):
			var rect := Rect2(Vector2(x, y) * cs - Vector2.ONE * cs * 0.46, Vector2.ONE * cs * 0.92)
			var col := Color(0.16, 0.48, 1.0, (0.06 + charge * 0.12) * (1.0 if x == 0 and y == 0 else 0.62))
			draw_rect(rect, col, false, 2.5 if x != 0 or y != 0 else 4.0)
	# Layered charcoal cloud with blue-white internal illumination.
	draw_circle(Vector2(0, -24), r * 1.05 * pulse, Color(0.05, 0.065, 0.13, 0.82))
	draw_circle(Vector2(-r * 0.48, -22), r * 0.63 * pulse, Color(0.08, 0.11, 0.22, 0.85))
	draw_circle(Vector2(r * 0.46, -18), r * 0.58 * pulse, Color(0.10, 0.14, 0.28, 0.82))
	draw_circle(Vector2(0, -14), r * 0.42, Color(0.16, 0.48, 1.0, 0.12 + charge * 0.25))
	var bolt_col := Color(0.92, 0.98, 1.0, 0.5 + charge * 0.5)
	for i in range(6):
		var ang: float = _anim * 3.0 + i * (TAU / 6.0)
		var prev := Vector2.ZERO
		for s in range(1, 4):
			var frac: float = float(s) / 3.0
			var jit: float = sin(_anim * 20.0 + i * 3 + s) * r * 0.18
			var perp := Vector2(-sin(ang), cos(ang)) * jit
			var nxt := Vector2(cos(ang), sin(ang)) * (r * frac) + perp
			draw_line(prev, nxt, Color(0.16, 0.48, 1.0, bolt_col.a), 6.0)
			draw_line(prev, nxt, bolt_col, 2.2)
			prev = nxt
	if _zap_flash > 0.0:
		draw_circle(Vector2.ZERO, 75.0 * _zap_flash, Color(0.92, 0.98, 1.0, 0.42 * _zap_flash))
		draw_arc(Vector2.ZERO, 42.0 + 95.0 * (1.0 - _zap_flash), 0.0, TAU, 36,
			Color(1.0, 0.76, 0.22, _zap_flash), 7.0 * _zap_flash)
