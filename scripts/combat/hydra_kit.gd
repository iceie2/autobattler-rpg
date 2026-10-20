extends RefCounted
class_name HydraKit

# First-cut tuning. The six variants retain the same base stats and affinities.
const FIRST := 3.0
const COOLDOWN := 10.0
const WINDUP := 0.9
const RECOVERY := 0.5
const FIRE_LIFE := 3.0
const FIRE_TICK := 0.5
const FIRE_DPS := 0.20
const HEADS := 3
const HIT_SCALE := [1.8, 1.2, 1.4, 1.25, 1.2, 1.5]
const MOVE_NAMES := ["Crushing Jaws", "Scorched Ground", "Undertow", "Stonefangs", "Gale Sweep", "Forked Discharge"]
const CLIPS := ["crushing_jaws", "scorched_ground", "undertow", "stonefangs", "gale_sweep", "forked_discharge"]
const SUMMARIES := [
	"Heads converge on one hero for a heavy bite and brief stun.",
	"Breathes along a marked strip, leaving burning ground for 3s.",
	"Pulls nearby heroes toward its mouth, then releases a close-range blast.",
	"Marks hero tiles, then erupts damaging spikes that briefly root.",
	"Sweeps a marked cone, damaging heroes and pushing them away.",
	"Marks a hero, then lightning chains through nearby allies.",
]

var casts: Array[Dictionary] = []
var hazards: Array[Dictionary] = []

static func reset(u: UnitBase) -> void:
	u.set_meta("hydra_heads", HEADS)
	u.set_meta("hydra_lost_heads", 0)
	u.set_meta("hydra_head_pool_active", true)
	u.set_meta("hydra_signature_t", FIRST)
	u.set_meta("hydra_busy", false)
	u.unit_name = "%s Hydra" % EnemyFactory.HYDRA_ELEMENT_NAMES[u.current_element]
	sync_heads(u)

static func heads_for_hp(hp: int, maximum: int) -> int:
	if hp <= 0: return 0
	if hp <= ceili(float(maximum) / HEADS): return 1
	if hp <= ceili(float(maximum) * 2 / HEADS): return 2
	return HEADS

static func health_cap(u: UnitBase) -> int:
	return ceili(float(u.max_hp) * int(u.get_meta("hydra_heads", HEADS)) / HEADS)

static func sync_heads(u: UnitBase) -> void:
	var old: int = int(u.get_meta("hydra_heads", HEADS))
	var heads := mini(old, heads_for_hp(u.current_hp, u.max_hp))
	u.set_meta("hydra_heads", heads)
	u.set_meta("hydra_lost_heads", HEADS - heads)
	u.unit_name = "%s Hydra (%d Heads)" % [EnemyFactory.HYDRA_ELEMENT_NAMES[u.current_element], heads]
	if u is VisualUnit:
		if u.model3d: u.model3d.set_hydra_heads(heads)
		if u.health_bar: u.health_bar.set_hydra_heads(heads, HEADS, SynergyData.element_color(u.current_element))
	if heads < old and is_instance_valid(u.battle_manager):
		u.battle_manager.action_logged.emit("%s head%s severed — %d remaining!" % [old - heads, "s" if old - heads > 1 else "", heads], u.is_player_unit)
		if heads == 0 and u.is_boss and not u.is_player_unit and u.battle_manager.battle_active:
			u.battle_manager.hydra_defeated = true

static func signature_damage(u: UnitBase) -> int:
	var scale: float = HIT_SCALE[u.current_element]
	if u.current_element == UnitBase.Element.NORMAL:
		scale += 0.25 * (int(u.get_meta("hydra_heads", 1)) - 1)
	return maxi(1, int(u.attack_damage * scale))

static func description(u: UnitBase) -> String:
	var e: int = u.current_element
	var heads: int = int(u.get_meta("hydra_heads", 1))
	var extra: String
	match e:
		UnitBase.Element.NORMAL: extra = "Bites one hero for %d physical damage and stuns for 0.8s. More surviving heads strengthen the bite." % signature_damage(u)
		UnitBase.Element.FIRE: extra = "A fixed strip reaches 5 tiles; more surviving heads widen it. Initial hit: %d physical Fire damage. Burning ground: %d true Fire damage every 0.5s for 3s." % [signature_damage(u), maxi(1, int(u.attack_damage * FIRE_DPS * FIRE_TICK))]
		UnitBase.Element.WATER: extra = "Pulls heroes within %.2f tiles one tile toward its mouth, then warns for another 0.5s before a 2-tile blast for %d physical Water damage. More surviving heads widen the pull." % [3.0 + 0.25 * (heads - 1), signature_damage(u)]
		UnitBase.Element.EARTH: extra = "Marks up to %d hero tiles. After the warning, spikes hit occupants of those tiles for %d physical Earth damage and root for 1.2s. Move off the marked tiles to evade." % [heads + 1, signature_damage(u)]
		UnitBase.Element.AIR: extra = "A fixed 70° cone reaches %.1f tiles; more surviving heads extend it. Hits for %d physical Air damage and pushes one tile away." % [4.0 + 0.5 * (heads - 1), signature_damage(u)]
		_: extra = "Marks one hero. Hits for %d physical Lightning damage, then chains through up to %d nearby allies within 2 tiles per jump. Each jump retains 80%% damage; each hero is hit once." % [signature_damage(u), heads]
	var lower: int = ceili(float(u.max_hp) * maxi(0, heads - 1) / HEADS)
	return "Head Health: %d/%d heads remain. Current head: %d/%d HP. Each head owns one third of total HP. Severed heads stay dead; healing cannot regrow them. Kill the last head to win.\n\nSerpent Strike: each surviving head bites a different nearby hero for %d physical damage. 5s cooldown.\n\n%s: %s First cast at 3s, then 10s cooldown; %.1fs warning. Damage shown is before defenses and outgoing modifiers. Control durations are reduced by target tenacity." % [heads, HEADS, maxi(0, u.current_hp - lower), maxi(1, health_cap(u) - lower), int(u.attack_damage * u.skill_damage_multiplier), MOVE_NAMES[e], extra, WINDUP]

func passive(m, u: UnitBase, opponents: Array, dt: float) -> void:
	sync_heads(u)
	if u.health_bar:
		u.health_bar.set_ability_timers([[1.0 - float(u.get_meta("hydra_signature_t", FIRST)) / COOLDOWN, SynergyData.element_color(u.current_element)], [1.0 - u.skill_cd_time / maxf(1.0, u.skill_cooldown_max), Color(0.8, 0.7, 0.5)]])
	var left := float(u.get_meta("hydra_signature_t", FIRST)) - dt
	u.set_meta("hydra_signature_t", maxf(0, left))
	if left <= 0 and not u.get_meta("hydra_busy", false) and u.stun_time <= 0 and u.action_time <= 0:
		begin(m, u, opponents)

func begin(m, u: UnitBase, opponents: Array) -> void:
	var living: Array = opponents.filter(func(v): return m._is_alive(v))
	if living.is_empty() or u.get_meta("hydra_busy", false): return
	living.sort_custom(func(a, b): return u.combat_distance_to(a) < u.combat_distance_to(b))
	var target: UnitBase = living[0]
	if u.current_element == UnitBase.Element.LIGHTNING: target = living[-1]
	var direction: Vector2 = (target.global_position - u.global_position).normalized()
	if direction == Vector2.ZERO: direction = Vector2.DOWN
	var heads: int = int(u.get_meta("hydra_heads", 1))
	var marks: Array[Vector2i] = []
	for v in living.slice(0, mini(heads + 1, living.size())): marks.append(v.grid_position)
	u.set_meta("hydra_busy", true)
	u.set_meta("hydra_signature_t", COOLDOWN)
	u.is_moving = false; u.move_progress = 0.0
	m.unit_paths.erase(u)
	var c := {"caster": u, "target": target, "opponents": opponents, "element": u.current_element,
		"heads": heads, "origin": u.global_position, "direction": direction, "marks": marks,
		"state": "warning", "left": WINDUP, "fx": null}
	casts.append(c)
	c.fx = effect(m, c, true)
	if u is VisualUnit and u.model3d:
		u.model3d.face_direction(direction)
		u.model3d.play_oneshot_timed(CLIPS[u.current_element], WINDUP + RECOVERY, "idle")
	m.action_logged.emit("%s prepares %s!" % [u.unit_name, MOVE_NAMES[u.current_element]], u.is_player_unit)

func tick(m, dt: float) -> void:
	for c in casts.duplicate():
		var u = c.caster
		if not m._is_alive(u): finish(c); continue
		# Stuns interrupt anticipation; hazards already on the ground persist.
		if u.stun_time > 0 and c.state == "warning": finish(c); continue
		c.left = float(c.left) - dt
		if c.left > 0: continue
		if c.state == "recovery": finish(c); continue
		if is_instance_valid(c.fx): c.fx.queue_free()
		var prior_tag: int = u.recap_action
		u.recap_action = 1
		if c.state == "water_blast": water_blast(m, c)
		else: resolve(m, c)
		u.recap_action = prior_tag
		if c.state != "water_blast":
			c.state = "recovery"; c.left = RECOVERY
			c.fx = null if c.element == UnitBase.Element.FIRE else effect(m, c, false)
	for h in hazards.duplicate():
		var active_dt := minf(dt, maxf(0, float(h.left)))
		h.left = float(h.left) - dt
		h.tick = float(h.tick) - active_dt
		while float(h.tick) <= 0:
			h.tick = float(h.tick) + FIRE_TICK
			var was_dot: bool = m.recap_tap.in_dot
			m.recap_tap.in_dot = true
			for v in h.opponents:
				if m._is_alive(v) and in_strip(v.global_position, h.origin, h.direction, h.length, h.width):
					var source = h.caster if is_instance_valid(h.caster) else null
					var before: int = v.current_hp
					v.take_damage(h.damage, UnitBase.Element.FIRE, source, true)
					if source: source.damage_dealt += maxi(0, before - v.current_hp)
			m.recap_tap.in_dot = was_dot
		if float(h.left) <= 0:
			if is_instance_valid(h.fx): h.fx.queue_free()
			hazards.erase(h)

func finish(c: Dictionary) -> void:
	if is_instance_valid(c.fx): c.fx.queue_free()
	if is_instance_valid(c.caster):
		c.caster.set_meta("hydra_busy", false)
		if c.caster is VisualUnit and c.caster.model3d and c.caster.model3d._current in CLIPS:
			c.caster.model3d.cancel_oneshot()
			c.caster.model3d.play("idle")
	casts.erase(c)

func clear() -> void:
	for c in casts.duplicate(): finish(c)
	for h in hazards:
		if is_instance_valid(h.fx): h.fx.queue_free()
	hazards.clear()

func hit(u: UnitBase, v: UnitBase, scale := 1.0) -> void:
	var before := v.current_hp
	v.take_damage(maxi(1, int(signature_damage(u) * u.outgoing_damage_multiplier() * scale)), u.current_element, u)
	u.damage_dealt += maxi(0, before - v.current_hp)

func resolve(m, c: Dictionary) -> void:
	var u: UnitBase = c.caster
	c.heads = int(u.get_meta("hydra_heads", HEADS))
	c.marks = c.marks.slice(0, mini(c.marks.size(), c.heads + 1))
	var cell: float = m.battle_grid.cell_size
	match int(c.element):
		UnitBase.Element.NORMAL:
			if m._is_alive(c.target):
				hit(u, c.target); m.apply_stun(c.target, 0.8, u)
		UnitBase.Element.FIRE:
			var width: float = cell * (0.7 + 0.2 * (int(c.heads) - 1))
			for v in c.opponents:
				if m._is_alive(v) and in_strip(v.global_position, c.origin, c.direction, cell * 5, width): hit(u, v)
			var fx = effect(m, c, false, FIRE_LIFE)
			hazards.append({"caster": u, "opponents": c.opponents, "origin": c.origin, "direction": c.direction,
				"length": cell * 5, "width": width, "left": FIRE_LIFE, "tick": FIRE_TICK,
				"damage": maxi(1, int(u.attack_damage * FIRE_DPS * FIRE_TICK * u.outgoing_damage_multiplier())), "fx": fx})
		UnitBase.Element.WATER:
			for v in c.opponents:
				if m._is_alive(v) and v.global_position.distance_to(c.origin) <= cell * (3.0 + 0.25 * (int(c.heads) - 1)):
					shift(m, v, u, true)
			c.state = "water_blast"; c.left = 0.5
			c.fx = effect(m, c, true)
		UnitBase.Element.EARTH:
			for v in c.opponents:
				if not m._is_alive(v): continue
				for mark in c.marks:
					if v.footprint_at(v.grid_position).has(mark):
						hit(u, v); m.apply_root(v, 1.2); break
		UnitBase.Element.AIR:
			for v in c.opponents:
				if m._is_alive(v) and in_cone(v.global_position, c.origin, c.direction, cell * (4.0 + 0.5 * (int(c.heads) - 1))):
					hit(u, v); shift(m, v, u, false)
		UnitBase.Element.LIGHTNING:
			var target = c.target
			var struck: Array = []
			var points := PackedVector2Array([c.origin])
			for jump in range(int(c.heads) + 1):
				if not m._is_alive(target): break
				points.append(target.global_position)
				struck.append(target)
				hit(u, target, pow(0.8, jump))
				var near = null
				var best: float = cell * 2.0
				for v in c.opponents:
					if not m._is_alive(v) or struck.has(v): continue
					var distance: float = target.global_position.distance_to(v.global_position)
					if distance <= best: best = distance; near = v
				target = near
			c.lightning = points

func water_blast(m, c: Dictionary) -> void:
	for v in c.opponents:
		if m._is_alive(v) and v.global_position.distance_to(c.origin) <= m.battle_grid.cell_size * 2.0:
			hit(c.caster, v)
	c.state = "recovery"

static func in_strip(point: Vector2, origin: Vector2, direction: Vector2, length: float, width: float) -> bool:
	var delta := point - origin
	return delta.dot(direction) >= 0 and delta.dot(direction) <= length and absf(delta.cross(direction)) <= width

static func in_cone(point: Vector2, origin: Vector2, direction: Vector2, length: float) -> bool:
	var delta := point - origin
	return delta.length() <= length and (delta.length() < 1.0 or delta.normalized().dot(direction) >= cos(deg_to_rad(35)))

static func shift(m, v: UnitBase, u: UnitBase, pull: bool) -> void:
	var delta := Vector2(v.grid_position - u.grid_position)
	if pull: delta = -delta
	var step := Vector2i(signi(roundi(delta.x)), signi(roundi(delta.y)))
	if absf(delta.x) > absf(delta.y): step.y = 0
	else: step.x = 0
	if step == Vector2i.ZERO: return
	var dest := v.grid_position + step
	for p in v.footprint_at(dest):
		if not m.battle_grid.is_valid_position(p) or (m.battle_grid.is_cell_occupied(p) and m.battle_grid.get_unit_at(p) != v): return
	var old := v.grid_position
	var from := v.global_position
	m.battle_grid.purge_unit(v)
	if not m.battle_grid.place_unit(v, dest):
		m.battle_grid.place_unit(v, old); return
	v.grid_position = dest
	v.position = m._world_pos_for(v, dest)
	v.is_moving = false; v.move_progress = 0.0
	m.unit_paths.erase(v)
	if v.has_method("play_shove_slide"): v.play_shove_slide(from)

func effect(m, c: Dictionary, warning: bool, life := 0.5):
	if not m.skill_effect_container: return null
	var fx := HydraVFX.new()
	m.skill_effect_container.add_child(fx)
	fx.setup(m, c, warning, WINDUP if warning else life)
	return fx
