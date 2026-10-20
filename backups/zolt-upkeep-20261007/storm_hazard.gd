extends Node2D
class_name StormHazard

# A roaming board hazard (Zolt's Thunderstorm). It is NOT a unit — it never enters
# the player/enemy arrays, can't be targeted or attacked, and doesn't count toward
# win/loss. It drifts one cell at a time toward enemy-dense areas without
# occupying an enemy's exact cell, periodically zapping its
# own tile (full damage + brief stun) and its 8 neighbours (half damage, no
# stun). Persists until the round ends or its caster reaches 0 mana. Storms still
# gather near Zolt, but never share a cell (owner 2026-09-30: stacked storms
# on one tile were "super op") — see cell_taken().
#
# This is the first of a planned family of board effects (fire patches, poison
# clouds, …). The manager ticks it with scaled dt so pause / slow-mo affect it too.
#
# Visuals v2 (2026-09-30, owner-approved audit): v1 was a flat navy disc with a
# spinning spoke wheel sitting ON the ground over the unit — it read as a black
# hole, and the strike was a flash + ring with no bolt. Now, in Zolt's lightning
# grammar (jagged hard strokes, CORE/BLUE/GOLD from ZoltVFX):
#   air (this node, z 20, over units): a bumpy storm cloud HOVERING above its
#     cell, rain, belly flicker, a lean into each hop, and a real jagged bolt
#     cloud -> centre cell on the strike, with forked arcs toward the 8 ring cells.
#   ground (_GroundLayer, z 1, under units): the cloud's shadow, the 3x3 strike
#     area as perspective-correct board tiles that light up during the charge,
#     and a scorch + gold spark burst where the bolt lands.
# Gameplay timing is unchanged: hop every MOVE_INTERVAL, strike at ZAP_DELAY.

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

const CORE := Color(0.92, 0.98, 1.0)       # == ZoltVFX palette
const BLUE := Color(0.16, 0.48, 1.0)
const GOLD := Color(1.0, 0.76, 0.22)
const CLOUD_DARK := Color(0.09, 0.10, 0.17)
const CLOUD_MID := Color(0.20, 0.22, 0.32)
const CLOUD_LIT := Color(0.42, 0.47, 0.62)
const OUTLINE := Color(0.03, 0.03, 0.06)
const BOLT_LIFE := 0.30
const SCORCH_LIFE := 1.2
const CLOUD_A := 0.90       # slightly see-through: units behind stay readable
const CLOUD_SIZE := 0.85    # cloud scale relative to a cell (v2.0 hid neighbours)
const PUFFS := [[-0.42, 0.06, 0.30], [0.0, 0.10, 0.34], [0.42, 0.06, 0.30],
	[-0.22, -0.14, 0.30], [0.20, -0.16, 0.33], [0.0, -0.30, 0.24]]

var _ground: Node2D = null
var _scale_from := 1.0
var _scale_to := 1.0
var _bolt: PackedVector2Array = PackedVector2Array()   # local, cloud belly -> ground
var _forks: Array = []                                  # [PackedVector2Array] ground arcs
var _bolt_t := 0.0
var _scorch_t := 0.0
var _scorch_at := Vector2.ZERO                          # global
var _seed := 0.0

class _GroundLayer extends Node2D:
	var storm = null
	func _draw() -> void:
		if storm: storm._draw_ground(self)

func setup(p_grid: BattleGrid, p_manager, p_caster: UnitBase, p_damage: int, p_cell: Vector2i) -> void:
	battle_grid = p_grid
	manager = p_manager
	caster = p_caster
	if caster and is_instance_valid(caster):
		caster.mana_changed.connect(_on_caster_mana_changed)
	owner_is_player = p_caster.is_player_unit if (p_caster and is_instance_valid(p_caster)) else true
	damage = p_damage
	grid_pos = p_cell
	_drift_dir = DIRS[randi() % DIRS.size()]
	if battle_grid:
		global_position = battle_grid.to_global(battle_grid.grid_to_world(grid_pos))
		_scale_from = battle_grid.row_scale(grid_pos.y)
		_scale_to = _scale_from
	z_as_relative = false
	z_index = 20
	_seed = randf() * 100.0
	_ground = _GroundLayer.new()
	_ground.storm = self
	_ground.top_level = true
	_ground.z_as_relative = false
	_ground.z_index = 1
	add_child(_ground)
	queue_redraw()

func _on_caster_mana_changed(current: int, _maximum: int) -> void:
	if current > 0 or is_queued_for_deletion():
		return
	if manager and is_instance_valid(manager):
		manager.storms.erase(self)
	caster.set_meta("storm_upkeep_acc", 0.0)
	hide()
	if _ground and is_instance_valid(_ground):
		_ground.hide()
	queue_free()

# Driven by the manager's _process so pacing (pause / time-scale) applies.
func tick(dt: float) -> void:
	_anim += dt
	_zap_flash = maxf(0.0, _zap_flash - dt * 2.8)
	_bolt_t = maxf(0.0, _bolt_t - dt)
	_scorch_t = maxf(0.0, _scorch_t - dt)
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
	if _ground:
		_ground.queue_redraw()

## True when another live storm already sits on `cell`. A storm's grid_pos is
## updated the moment its hop starts, and storms tick one after another, so two
## can never claim the same cell in the same frame.
static func cell_taken(storms: Array, cell: Vector2i, except: Node = null) -> bool:
	for s in storms:
		if s != except and s and is_instance_valid(s) and s.grid_pos == cell:
			return true
	return false

func _hop() -> void:
	if not battle_grid:
		return
	var others: Array = manager.storms if manager and is_instance_valid(manager) else []
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
		if not battle_grid.is_valid_position(cell) or cell_taken(others, cell, self):
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
			if battle_grid.is_valid_position(cell) and not cell_taken(others, cell, self):
				candidates.append({"dir": d, "cell": cell})
	if candidates.is_empty():
		return   # boxed in by other storms: hold this cell for a beat

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
	_scale_from = _depth()
	_scale_to = battle_grid.row_scale(grid_pos.y) if battle_grid else 1.0
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
	_make_bolt()
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

# ── visuals ─────────────────────────────────────────────────────────────────

func _cs() -> float:
	return float(battle_grid.cell_size) if battle_grid else 110.0

## perspective scale right now (eases between rows during a hop)
func _depth() -> float:
	var e := 1.0 - pow(1.0 - _hop_t, 3.0)
	return lerpf(_scale_from, _scale_to, e)

func _charge() -> float:
	if _has_zapped:
		return 0.0
	return clampf(_move_accum / ZAP_DELAY, 0.0, 1.0)

## cloud centre, local to this node: hovering above the ground point, with a
## lean into the hop and a slow bob
func _cloud_centre() -> Vector2:
	var cs := _cs() * _depth()
	var c := Vector2(0, -cs * 1.25 + sin(_anim * 1.7 + _seed) * cs * 0.04)
	if _hop_t < 1.0 and _hop_to != _hop_from:
		c += (_hop_to - _hop_from).normalized() * sin(PI * _hop_t) * cs * 0.10
	return c

func _make_bolt() -> void:
	var cs := _cs() * _depth()
	var top := _cloud_centre() + Vector2(0, cs * 0.22)
	var steps := 7
	_bolt = PackedVector2Array()
	for i in steps + 1:
		var u := float(i) / steps
		var p := top.lerp(Vector2.ZERO, u)
		if i > 0 and i < steps:
			p.x += randf_range(-1.0, 1.0) * cs * 0.16
		_bolt.append(p)
	# forked arcs from the impact toward the 8 ring cells (flattened by the
	# board's perspective), so the half-damage ring visibly takes the hit
	_forks.clear()
	for d in DIRS:
		var end := Vector2(d.x * cs * 0.85, d.y * cs * 0.55)
		var pts := PackedVector2Array([Vector2.ZERO])
		for j in range(1, 4):
			var q := Vector2.ZERO.lerp(end, j / 3.0)
			if j < 3:
				q += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * cs * 0.07
			pts.append(q)
		_forks.append(pts)
	_bolt_t = BOLT_LIFE
	_scorch_t = SCORCH_LIFE
	_scorch_at = global_position

func _stroke(ci: CanvasItem, pts: PackedVector2Array, w: float, a: float) -> void:
	if pts.size() < 2 or a <= 0.01:
		return
	ci.draw_polyline(pts, Color(BLUE, 0.35 * a), w * 3.2, true)
	ci.draw_polyline(pts, Color(BLUE, 0.85 * a), w * 1.6, true)
	ci.draw_polyline(pts, Color(CORE, a), maxf(1.0, w * 0.6), true)

func _draw() -> void:
	var k := _depth()
	var cs := _cs() * k * CLOUD_SIZE
	var cc := _cloud_centre()
	var charge := _charge()
	# rain: short slanted streaks from the belly toward the ground
	var rw := cs * 0.62
	for i in 12:
		var h := fposmod(float(i) * 0.618 + _seed, 1.0)
		var x := (h - 0.5) * 2.0 * rw * 0.8
		var ph := fposmod(_anim * 2.4 + h * 3.1, 1.0)
		var y0 := cc.y + cs * 0.25 + ph * (-cc.y - cs * 0.25)
		var p0 := Vector2(cc.x + x + ph * cs * 0.12, y0)
		draw_line(p0, p0 + Vector2(cs * 0.05, cs * 0.14), Color(0.70, 0.80, 1.0, 0.45 * (1.0 - ph * 0.6)), maxf(1.0, 1.6 * k), true)
	# flicker: the belly lights up blue at irregular moments, steadily during charge
	var flick := maxf(0.0, sin(_anim * 7.3 + _seed) * sin(_anim * 3.1 + _seed * 2.0)) * 0.7
	var glow := clampf(flick * 0.6 + charge * 0.9 + _zap_flash, 0.0, 1.4)
	# cloud body: bumpy puffs, outline -> dark -> mid -> lit top edge
	var breathe := 1.0 + 0.03 * sin(_anim * 2.3 + _seed)
	for P in PUFFS:
		draw_circle(cc + Vector2(P[0], P[1]) * cs, (float(P[2]) * cs + 2.5) * breathe, Color(OUTLINE, 0.75 * CLOUD_A))
	for P in PUFFS:
		draw_circle(cc + Vector2(P[0], float(P[1]) + 0.03) * cs, float(P[2]) * cs * breathe, Color(CLOUD_DARK, CLOUD_A))
	# lit rim: a thin crescent along each top puff (lit circle, then the mid body
	# drawn over it slightly lower). Round highlight DOTS read as eyes/ears — the
	# first capture looked like a paw print / face.
	for P in PUFFS.slice(3):
		draw_circle(cc + Vector2(float(P[0]) - 0.03, float(P[1]) - 0.05) * cs, float(P[2]) * cs * 0.80 * breathe, Color(CLOUD_LIT, CLOUD_A))
	for P in PUFFS:
		draw_circle(cc + Vector2(float(P[0]) - 0.02, float(P[1]) + 0.0) * cs, float(P[2]) * cs * 0.80 * breathe, Color(CLOUD_MID, CLOUD_A))
	# belly glow (inside the cloud)
	if glow > 0.02:
		for i in range(4, 0, -1):
			var f := float(i) / 4.0
			draw_circle(cc + Vector2(0, cs * 0.08), cs * 0.42 * f, Color(BLUE, 0.22 * glow * (1.0 - f) + 0.05 * glow))
		# a jagged crackle in the cloud's belly while it charges. Hard zigzag, low
		# and off-centre: a smooth centred wave read as a SMILE on the cloud.
		if charge > 0.3 or flick > 0.5:
			var a0 := Vector2(-cs * 0.30, cs * 0.16) + cc
			var pts := PackedVector2Array([a0])
			for j in range(1, 6):
				var zig := (1.0 if j % 2 == 0 else -1.0) * cs * (0.03 + 0.03 * fposmod(sin(_anim * 23.0 + j * 5.7) * 43.1, 1.0))
				pts.append(a0 + Vector2(cs * 0.55 * j / 5.0, zig))
			_stroke(self, pts, maxf(1.0, 1.2 * k), clampf(glow, 0.0, 1.0) * 0.8)
	# the strike: a jagged bolt, cloud -> centre cell
	if _bolt_t > 0.0:
		var a := clampf(_bolt_t / BOLT_LIFE * 1.4, 0.0, 1.0)
		_stroke(self, _bolt, 3.2 * k, a)
		for fk in _forks:
			_stroke(self, fk, 1.4 * k, a * 0.85)
		for i in range(5, 0, -1):
			var f := float(i) / 5.0
			draw_circle(cc + Vector2(0, cs * 0.1), cs * 0.6 * f, Color(CORE, 0.18 * a * (1.0 - f)))

func _draw_ground(ci: CanvasItem) -> void:
	if not battle_grid:
		return
	var k := _depth()
	var cs := _cs() * k
	var charge := _charge()
	# strike area: the 3x3 as real (perspective) board tiles
	var area_a := 0.10 + 0.55 * charge * charge
	if _bolt_t > 0.0:
		area_a = maxf(area_a, 0.7 * _bolt_t / BOLT_LIFE)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := grid_pos + Vector2i(dx, dy)
			if not battle_grid.is_valid_position(c):
				continue
			var q := BoardPerspective.cell_quad(c.x, c.y, battle_grid.grid_width, battle_grid.grid_height, float(battle_grid.cell_size))
			var g := PackedVector2Array()
			var mid := (q[0] + q[1] + q[2] + q[3]) / 4.0
			for v in q:
				g.append(battle_grid.to_global(v.lerp(mid, 0.06)))
			var centre := dx == 0 and dy == 0
			ci.draw_colored_polygon(g, Color(BLUE, area_a * (0.30 if centre else 0.16)))
			var loop := g.duplicate()
			loop.append(g[0])
			ci.draw_polyline(loop, Color(CORE if centre else BLUE, area_a * (0.9 if centre else 0.6)), 3.0 if centre else 2.0, true)
	# the cloud's shadow, following the cloud (not the cell) during a hop
	var sp := global_position + Vector2(_cloud_centre().x, 0)
	var sh := PackedVector2Array()
	for i in 24:
		var t := TAU * i / 24.0
		sh.append(sp + Vector2(cos(t) * cs * 0.55, sin(t) * cs * 0.20))
	ci.draw_colored_polygon(sh, Color(0.02, 0.02, 0.06, 0.28 + 0.12 * charge))
	# scorch + gold sparks where the bolt landed
	if _scorch_t > 0.0:
		var a := _scorch_t / SCORCH_LIFE
		var sc := PackedVector2Array()
		for i in 20:
			var t := TAU * i / 20.0
			var r := 1.0 + 0.18 * sin(t * 5.0 + _seed)
			sc.append(_scorch_at + Vector2(cos(t) * cs * 0.28 * r, sin(t) * cs * 0.11 * r))
		ci.draw_colored_polygon(sc, Color(0.05, 0.04, 0.03, 0.45 * a))
		var e := 1.0 - a
		if e < 0.35:
			var qq := e / 0.35
			for i in 10:
				var t := TAU * i / 10.0 + _seed
				var d := Vector2(cos(t), sin(t) * 0.45)
				ci.draw_line(_scorch_at + d * cs * (0.10 + 0.30 * qq), _scorch_at + d * cs * (0.22 + 0.42 * qq), Color(GOLD, 1.0 - qq), maxf(1.0, 2.2 * k), true)
			ci.draw_circle(_scorch_at, cs * 0.18 * (1.0 - qq), Color(CORE, 0.8 * (1.0 - qq)))
