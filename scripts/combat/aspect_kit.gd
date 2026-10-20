extends RefCounted
class_name AspectKit

# First-cut damage coefficients; base stats remain owned by EnemyFactory.
const POUNCE_SCALE := 0.45
const BREATH_SCALE := 1.25
const TELL := 0.65
const TRAVEL := 0.45
const BREATH_TELL := 0.8
const RANGE := 5.0
const HALF_ANGLE := PI / 6.0

static func reset(u: UnitBase) -> void:
	u.current_element = UnitBase.Element.NORMAL
	u.set_meta("aspect_t", 6.0)
	u.set_meta("aspect_idx", 0)
	u.set_meta("aspect_pounced", false)
	u.set_meta("aspect_action", {})
	u.set_meta("aspect_busy", false)
	u.set_affinity_profile(100.0, 100.0)
	if u.has_method("set_pounce_height"): u.set_pounce_height(0.0)

static func description(u: UnitBase) -> String:
	var name: String = EnemyFactory.HYDRA_ELEMENT_NAMES.get(u.current_element, "Normal")
	var next: int = (AutoBattleManager.ASPECT_CYCLE.find(u.current_element) + 1) % 6
	return "%s Aspect — only takes %s damage, including true damage and damage over time. Other elements cannot damage HP or shields. Next: %s in %.1fs.\n\nAspect Pounce: halfway through each 6s phase, marks the farthest hero's tile for %.2fs, then leaps to the nearest clear 2×2 space and hits within 1.5 tiles of the marked tile for %d elemental magic damage.\n\nAspect Breath: after landing, warns for %.1fs, then hits a fixed 60° cone reaching 5 tiles for %d elemental magic damage. Damage shown is before defenses and outgoing modifiers. Basic attacks continue between these moves." % [name, name, EnemyFactory.HYDRA_ELEMENT_NAMES.get(AutoBattleManager.ASPECT_CYCLE[next], "Normal"), float(u.get_meta("aspect_t", 6.0)), TELL, int(u.magic_power * POUNCE_SCALE), BREATH_TELL, int(u.magic_power * BREATH_SCALE)]

static func tick(m, u: UnitBase, opponents: Array, dt: float) -> void:
	var a: Dictionary = u.get_meta("aspect_action", {})
	if a.is_empty():
		if float(u.get_meta("aspect_t", 6.0)) > 3.0 or u.get_meta("aspect_pounced", false) or u.stun_time > 0.0: return
		var far: UnitBase = null
		var distance := -1.0
		for v in opponents:
			if not m._is_alive(v): continue
			var d: float = u.global_position.distance_squared_to(v.global_position)
			if d > distance: distance = d; far = v
		if far == null: return
		u.set_meta("aspect_pounced", true)
		u.set_meta("aspect_busy", true)
		u.is_moving = false
		u.move_progress = 0.0
		m.unit_paths.erase(u)
		a = {"state": "tell", "left": TELL, "mark": far.grid_position, "point": far.global_position, "element": u.current_element}
		u.set_meta("aspect_action", a)
		show(m, a.point, u.current_element, TELL, false, Vector2.DOWN, m.battle_grid.cell_size * 1.5)
		m.action_logged.emit("Aspect Devourer marks %s for Aspect Pounce!" % far.unit_name, false)
		return
	a.left = float(a.left) - dt
	if a.state == "travel":
		var k := clampf(1.0 - float(a.left) / TRAVEL, 0.0, 1.0)
		u.position = (a.from as Vector2).lerp(a.to, k)
		if u.has_method("set_pounce_height"): u.set_pounce_height(sin(k * PI) * 65.0)
	if float(a.left) > 0.0: return
	match a.state:
		"tell":
			var old := u.grid_position
			var dest := old
			var best := INF
			for y in m.battle_grid.grid_height:
				for x in m.battle_grid.grid_width:
					var p := Vector2i(x, y)
					var valid := true
					for cell in u.footprint_at(p):
						if not m.battle_grid.is_valid_position(cell) or (m.battle_grid.is_cell_occupied(cell) and m.battle_grid.get_unit_at(cell) != u): valid = false; break
					var d := Vector2(p).distance_squared_to(Vector2(a.mark))
					if valid and d < best: best = d; dest = p
			m.battle_grid.purge_unit(u)
			if not m.battle_grid.place_unit(u, dest):
				m.battle_grid.place_unit(u, old)
				dest = old
			u.grid_position = dest
			a.from = u.position
			a.to = m._world_pos_for(u, dest)
			a.state = "travel"; a.left = TRAVEL
		"travel":
			u.position = a.to
			if u.has_method("set_pounce_height"): u.set_pounce_height(0.0)
			for v in opponents:
				if m._is_alive(v) and Vector2(v.grid_position).distance_to(Vector2(a.mark)) <= 1.5:
					v.take_magic_damage(int(u.magic_power * POUNCE_SCALE * u.outgoing_damage_multiplier()), a.element, u)
			show(m, a.point, a.element, 0.3, false, Vector2.DOWN, m.battle_grid.cell_size * 1.5)
			var target = m._choose_target(u, opponents)
			var direction := Vector2.DOWN
			if m._is_alive(target): direction = (target.global_position - u.global_position).normalized()
			a.direction = direction; a.origin = u.global_position
			if u is VisualUnit and u.model3d:
				u.model3d.face_direction(direction)
				u.model3d.play_oneshot_timed("skill", BREATH_TELL, "idle")
			a.state = "breath"; a.left = BREATH_TELL
			show(m, a.origin, a.element, BREATH_TELL, true, direction, m.battle_grid.cell_size * RANGE)
		"breath":
			for v in opponents:
				if not m._is_alive(v): continue
				var delta: Vector2 = v.global_position - a.origin
				if delta.length() <= m.battle_grid.cell_size * RANGE and (delta.length() < 1.0 or delta.normalized().dot(a.direction) >= cos(HALF_ANGLE)):
					v.take_magic_damage(int(u.magic_power * BREATH_SCALE * u.outgoing_damage_multiplier()), a.element, u)
			show(m, a.origin, a.element, 0.35, true, a.direction, m.battle_grid.cell_size * RANGE)
			m.action_logged.emit("Aspect Devourer unleashes Aspect Breath!", false)
			u.set_meta("aspect_action", {})
			u.set_meta("aspect_busy", false)

static func show(m, point: Vector2, element: int, life: float, cone: bool, direction := Vector2.DOWN, reach := 70.0) -> void:
	if not m.skill_effect_container: return
	var fx := AspectAttackVFX.new()
	m.skill_effect_container.add_child(fx)
	fx.setup(point, element, life, cone, direction, reach)
	fx.manager = m
