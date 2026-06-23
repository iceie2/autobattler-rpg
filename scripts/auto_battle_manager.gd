extends Node
class_name AutoBattleManager

# References
var battle_grid: BattleGrid
var game_state: GameState
var projectile_container: Node2D
var skill_effect_container: Node2D

# Battle state
var player_units: Array = []
var enemy_units: Array = []
var battle_active: bool = false
var battle_timer: float = 0.0
var action_delay: float = 0.5  # Time between actions (faster updates)

# Movement speed multiplier (higher = faster base movement)
var base_movement_speed: float = 0.5

# Unit movement paths
var unit_paths: Dictionary = {}  # unit -> Array[Vector2i]

signal battle_started()
signal battle_ended(player_won: bool)
signal unit_action(unit, action_type: String)

func _ready():
	pass

func initialize(grid: BattleGrid, state: GameState) -> void:
	battle_grid = grid
	game_state = state
	
	if game_state:
		game_state.auto_battle_started.connect(_on_auto_battle_started)

func _on_auto_battle_started() -> void:
	start_battle()

func start_battle() -> void:
	battle_active = true
	battle_timer = 0.0
	unit_paths.clear()
	collect_units()
	print("[Battle] Started — players: %d, enemies: %d" % [player_units.size(), enemy_units.size()])
	battle_started.emit()

func collect_units() -> void:
	player_units.clear()
	enemy_units.clear()

	if not battle_grid:
		print("[Battle] ERROR: battle_grid is null!")
		return

	print("[Battle] occupied_cells count: %d" % battle_grid.occupied_cells.size())
	for grid_pos in battle_grid.occupied_cells:
		var unit = battle_grid.get_unit_at(grid_pos)
		if unit and unit is UnitBase:
			unit.battle_manager = self
			if unit.is_player_unit:
				player_units.append(unit)
			else:
				enemy_units.append(unit)
		else:
			print("[Battle] Cell %s has non-unit or null: %s" % [grid_pos, unit])

func _process(delta: float) -> void:
	if not battle_active:
		return
	
	# Update all moving units
	update_unit_movements(delta)
	
	battle_timer += delta
	
	if battle_timer >= action_delay:
		battle_timer = 0.0
		execute_battle_turn()

func execute_battle_turn() -> void:
	_run_side(player_units, enemy_units)
	_run_side(enemy_units, player_units)
	check_battle_end()

func _run_side(units: Array, opponents: Array) -> void:
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue

		# ── Passives evaluated each turn ──────────────────────────────────────
		_tick_passive(unit, opponents, units)

		# Skip turn if stunned
		if unit.stun_turns > 0:
			unit.stun_turns -= 1
			continue

		# Tick active skill cooldown
		if unit.skill_cooldown > 0:
			unit.skill_cooldown -= 1

		# Tick Headhunter rapid-fire duration
		if unit.rapid_fire_turns > 0:
			unit.rapid_fire_turns -= 1

		# ── Ultimate (fires when ready, before normal turn) ───────────────────
		if unit.ultimate_ready:
			_use_ultimate(unit, opponents, units)
			unit.ultimate_ready = false
			unit.ultimate_charge = 0
			unit_action.emit(unit, "ultimate")
			continue

		# ── Active skill ──────────────────────────────────────────────────────
		var can_afford_mana: bool = unit.current_mana >= unit.skill_mana_cost
		if unit.skill_cooldown == 0 and unit.skill_name != "" and can_afford_mana:
			if unit.skill_mana_cost > 0:
				unit.current_mana -= unit.skill_mana_cost
			_use_skill(unit, opponents)
			unit.skill_cooldown = unit.skill_cooldown_max
			unit_action.emit(unit, "skill")
			continue

		# ── Normal attack / move ──────────────────────────────────────────────
		var target := _choose_target(unit, opponents)
		if not target:
			continue

		var effective_range: int = unit.attack_range + (2 if unit.rapid_fire_turns > 0 else 0)
		if unit.grid_position.distance_to(target.grid_position) <= effective_range:
			# Extra target for Headhunter Rapid Fire
			if unit.rapid_fire_turns > 0 and opponents.size() > 1:
				var second := _second_nearest(unit, target, opponents)
				if second:
					unit.attack(second)
			unit.attack(target)
			unit_action.emit(unit, "attack")
			unit_paths.erase(unit)
		elif not unit.is_moving and unit.movement_speed > 0:
			move_unit_towards_with_pathfinding(unit, target.grid_position)
			unit_action.emit(unit, "move")

# Pick target: Bloodhound in frenzy locks on most-damage-dealer, else nearest
func _choose_target(unit: UnitBase, opponents: Array) -> UnitBase:
	if unit.frenzy_active and is_instance_valid(unit.most_damage_dealer):
		return unit.most_damage_dealer as UnitBase
	return find_nearest_enemy(unit, opponents)

func _second_nearest(unit: UnitBase, first: UnitBase, opponents: Array) -> UnitBase:
	var best: UnitBase = null
	var best_d := INF
	for opp in opponents:
		if not (opp and is_instance_valid(opp)) or opp == first:
			continue
		var d := unit.grid_position.distance_to(opp.grid_position)
		if d < best_d:
			best_d = d; best = opp
	return best

# ── Passive evaluations ───────────────────────────────────────────────────────
func _tick_passive(unit: UnitBase, opponents: Array, allies: Array) -> void:
	match unit.unit_class:
		UnitBase.UnitClass.BLOODHOUND:
			# Blood Frenzy: below 45% HP
			var threshold := unit.max_hp * 0.45
			unit.frenzy_active = unit.current_hp < threshold
			if unit.frenzy_active:
				# Find which opponent dealt the most damage to this unit
				var top_dealer: UnitBase = null
				var top_dmg := 0
				for opp in opponents:
					if not (opp and is_instance_valid(opp)):
						continue
					var dmg: int = unit.damage_taken_from.get(opp, 0)
					if dmg > top_dmg:
						top_dmg = dmg; top_dealer = opp
				unit.most_damage_dealer = top_dealer

		UnitBase.UnitClass.BOUNCER:
			# Presence: count units within 2 tiles (recalculated, stored in offensive affinity)
			var nearby := 0
			for opp in opponents:
				if opp and is_instance_valid(opp):
					if unit.grid_position.distance_to(opp.grid_position) <= 2:
						nearby += 1
			for ally in allies:
				if ally and is_instance_valid(ally) and ally != unit:
					if unit.grid_position.distance_to(ally.grid_position) <= 2:
						nearby += 1
			# Store presence bonus as a temp modifier (applied in damage calc)
			unit.set_meta("presence_bonus", min(nearby * 0.05, 0.3))

# ── Ultimate implementations ──────────────────────────────────────────────────
func _use_ultimate(caster: UnitBase, opponents: Array, allies: Array) -> void:
	match caster.unit_class:
		UnitBase.UnitClass.BLOODHOUND:
			# Pounce — leap to most-damage-dealer, stun + 250% ATK
			var target: UnitBase = caster.most_damage_dealer
			if not (target and is_instance_valid(target)):
				target = find_nearest_enemy(caster, opponents)
			if not target:
				return
			var dmg := int(caster.attack_damage * caster.ultimate_damage_mult)
			target.take_damage(dmg, caster.current_element)
			target.stun_turns = 1
			caster.damage_dealt += dmg
			_spawn_skill_effect(SkillEffect.Type.SHADOW_STRIKE, caster.global_position)

		UnitBase.UnitClass.BOUNCER:
			# Gravity Drop — warning ring + pull all enemies in range + impact
			var dmg := int(caster.magic_power * caster.ultimate_damage_mult)
			var bonus: float = caster.get_meta("presence_bonus") if caster.has_meta("presence_bypass") else 0.0
			if caster.has_meta("presence_bonus"):
				bonus = float(caster.get_meta("presence_bonus"))
			dmg = int(dmg * (1.0 + bonus))

			# Large gravity drop effect centred on Bouncer (covers the pull area)
			_spawn_skill_effect_sized(SkillEffect.Type.GRAVITY_DROP,
				caster.global_position, 80.0)

			for opp in opponents:
				if not (opp and is_instance_valid(opp)):
					continue
				if caster.grid_position.distance_to(opp.grid_position) <= 4:
					var prev_pos: Vector2 = opp.global_position
					# Small absorbed burst on the enemy before pulling
					_spawn_skill_effect_sized(SkillEffect.Type.ABSORBED, prev_pos, 28.0)
					# Pull to nearest open cell next to Bouncer
					var open_cell := _nearest_open_adjacent(caster.grid_position)
					if open_cell != Vector2i(-1, -1) and open_cell != opp.grid_position:
						battle_grid.remove_unit(opp.grid_position)
						if battle_grid.place_unit(opp, open_cell):
							opp.grid_position = open_cell
							opp.position = battle_grid.grid_to_world(open_cell)
					opp.take_damage(dmg, caster.current_element)
					caster.damage_dealt += dmg

		UnitBase.UnitClass.HEADHUNTER:
			# Snipe — shoot farthest enemy, blocked by any enemy in line
			var target := _farthest_enemy(caster, opponents)
			if not target:
				return
			# Check line of fire for blockers
			var actual_target := _check_line_of_fire(caster, target, opponents)
			var dmg := int(caster.attack_damage * caster.ultimate_damage_mult)
			actual_target.take_damage(dmg, caster.current_element)
			caster.damage_dealt += dmg
			_spawn_skill_effect(SkillEffect.Type.ARROW_RAIN, actual_target.global_position)
		_:
			# Legacy classes fire their normal skill as "ultimate"
			_use_skill(caster, opponents)

func _nearest_open_adjacent(center: Vector2i) -> Vector2i:
	var dirs: Array[Vector2i] = [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),
				 Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]
	for d in dirs:
		var c: Vector2i = center + d
		if battle_grid.is_valid_position(c) and not battle_grid.is_cell_occupied(c):
			return c
	return Vector2i(-1, -1)

func _farthest_enemy(unit: UnitBase, opponents: Array) -> UnitBase:
	var farthest: UnitBase = null
	var max_d := -1.0
	for opp in opponents:
		if not (opp and is_instance_valid(opp)):
			continue
		var d := unit.grid_position.distance_to(opp.grid_position)
		if d > max_d:
			max_d = d; farthest = opp
	return farthest

func _check_line_of_fire(shooter: UnitBase, target: UnitBase, opponents: Array) -> UnitBase:
	# Return first opponent on the path between shooter and target (or target itself)
	var sx := shooter.grid_position.x; var sy := shooter.grid_position.y
	var tx := target.grid_position.x;  var ty := target.grid_position.y
	var best := target
	var best_d := shooter.grid_position.distance_to(target.grid_position)
	for opp in opponents:
		if not (opp and is_instance_valid(opp)) or opp == target:
			continue
		# Simple: is this unit roughly on the line?
		var ox: int = opp.grid_position.x; var oy: int = opp.grid_position.y
		var cross: int = abs((tx - sx) * (sy - oy) - (sx - ox) * (ty - sy))
		if cross <= 1:  # within 1 unit of the line
			var d := shooter.grid_position.distance_to(opp.grid_position)
			if d < best_d:
				best_d = d; best = opp
	return best

func find_nearest_enemy(unit: UnitBase, enemies: Array) -> UnitBase:
	var nearest: UnitBase = null
	var min_distance: float = INF
	
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		
		var distance = unit.grid_position.distance_to(enemy.grid_position)
		if distance < min_distance:
			min_distance = distance
			nearest = enemy
	
	return nearest

func assign_preferred_target(unit: UnitBase, target: UnitBase) -> void:
	unit.target_unit = target

# ── Skill execution ───────────────────────────────────────────────────────────

func _use_skill(caster: UnitBase, opponents: Array) -> void:
	var effect_type: SkillEffect.Type
	match caster.unit_class:
		UnitBase.UnitClass.WARRIOR:
			effect_type = SkillEffect.Type.WHIRLWIND
			_whirlwind(caster, opponents)
		UnitBase.UnitClass.RANGER:
			effect_type = SkillEffect.Type.ARROW_RAIN
			_arrow_rain(caster, opponents)
		UnitBase.UnitClass.MONK:
			effect_type = SkillEffect.Type.CHI_BURST
			_chi_burst(caster, opponents)
		UnitBase.UnitClass.THIEF:
			effect_type = SkillEffect.Type.SHADOW_STRIKE
			_shadow_strike(caster, opponents)
		UnitBase.UnitClass.BLACK_MAGE:
			effect_type = SkillEffect.Type.INFERNO
			_inferno(caster, opponents)
		UnitBase.UnitClass.WHITE_MAGE:
			effect_type = SkillEffect.Type.HOLY_LIGHT
			_holy_light(caster)
		UnitBase.UnitClass.RED_MAGE:
			effect_type = SkillEffect.Type.CHAOS_BOLT
			_chaos_bolt(caster, opponents)
		UnitBase.UnitClass.BLOODHOUND:
			effect_type = SkillEffect.Type.SHADOW_STRIKE
			_bloodhound_bite(caster, opponents)
		UnitBase.UnitClass.BOUNCER:
			effect_type = SkillEffect.Type.WHIRLWIND
			_bouncer_slam(caster, opponents)
		UnitBase.UnitClass.HEADHUNTER:
			effect_type = SkillEffect.Type.ARROW_RAIN
			_headhunter_rapid_fire(caster)
		_:
			return
	_spawn_skill_effect(effect_type, caster.global_position)

# ── New class active skills ───────────────────────────────────────────────────

func _bloodhound_bite(caster: UnitBase, opponents: Array) -> void:
	var target := find_nearest_enemy(caster, opponents)
	if not target:
		return
	var dmg := int(caster.attack_damage * caster.skill_damage_multiplier)
	target.take_damage(dmg, caster.current_element)
	caster.damage_dealt += dmg
	# Heal for 30% of damage dealt
	caster.heal(int(dmg * 0.3))

func _bouncer_slam(caster: UnitBase, opponents: Array) -> void:
	var target := find_nearest_enemy(caster, opponents)
	if not target:
		return
	var dmg := int(caster.magic_power * caster.skill_damage_multiplier)
	var bonus: float = caster.get_meta("presence_bonus") if caster.has_meta("presence_bonus") else 0.0
	dmg = int(dmg * (1.0 + bonus))
	target.take_damage(dmg, caster.current_element)
	target.stun_turns = 1
	caster.damage_dealt += dmg

func _headhunter_rapid_fire(caster: UnitBase) -> void:
	caster.rapid_fire_turns = 3  # lasts 3 battle turns

func _spawn_skill_effect(type: SkillEffect.Type, world_pos: Vector2) -> void:
	_spawn_skill_effect_sized(type, world_pos, 56.0)

func _spawn_skill_effect_sized(type: SkillEffect.Type, world_pos: Vector2, r: float) -> void:
	if not skill_effect_container:
		return
	var fx := SkillEffect.new()
	skill_effect_container.add_child(fx)
	fx.setup(type, world_pos, r)

# Warrior: hits all adjacent enemies
func _whirlwind(caster: UnitBase, opponents: Array) -> void:
	for opp in opponents:
		if opp == null or not is_instance_valid(opp):
			continue
		if caster.grid_position.distance_to(opp.grid_position) <= 1.5:
			var dmg := int(caster.attack_damage * caster.skill_damage_multiplier)
			opp.take_damage(dmg, caster.current_element)

# Ranger: hits up to 3 nearest enemies with ranged shots
func _arrow_rain(caster: UnitBase, opponents: Array) -> void:
	var sorted := opponents.filter(func(u): return u != null and is_instance_valid(u))
	sorted.sort_custom(func(a, b):
		return caster.grid_position.distance_to(a.grid_position) < \
			   caster.grid_position.distance_to(b.grid_position))
	var count := mini(3, sorted.size())
	for i in range(count):
		var target: UnitBase = sorted[i]
		if caster.grid_position.distance_to(target.grid_position) <= caster.skill_range:
			var dmg := int(caster.attack_damage * caster.skill_damage_multiplier)
			caster.spawn_projectile(target, dmg)
			_spawn_skill_effect(SkillEffect.Type.ARROW_RAIN, target.global_position)

# Monk: damages nearby enemies AND heals adjacent allies
func _chi_burst(caster: UnitBase, opponents: Array) -> void:
	for opp in opponents:
		if opp == null or not is_instance_valid(opp):
			continue
		if caster.grid_position.distance_to(opp.grid_position) <= caster.skill_range:
			var dmg := int(caster.attack_damage * caster.skill_damage_multiplier)
			opp.take_damage(dmg, caster.current_element)
	# Heal allies adjacent to caster
	var allies := player_units if caster.is_player_unit else enemy_units
	for ally in allies:
		if ally == null or not is_instance_valid(ally) or ally == caster:
			continue
		if caster.grid_position.distance_to(ally.grid_position) <= 2.0:
			ally.heal(int(caster.magic_power * 0.8))

# Thief: high-damage critical strike on nearest enemy
func _shadow_strike(caster: UnitBase, opponents: Array) -> void:
	var target := find_nearest_enemy(caster, opponents)
	if target and is_instance_valid(target):
		var dmg := int(caster.attack_damage * caster.skill_damage_multiplier)
		target.take_damage(dmg, caster.current_element)
		_spawn_skill_effect(SkillEffect.Type.SHADOW_STRIKE, target.global_position)

# Black Mage: large AOE explosion around nearest enemy
func _inferno(caster: UnitBase, opponents: Array) -> void:
	var center := find_nearest_enemy(caster, opponents)
	if not center or not is_instance_valid(center):
		return
	_spawn_skill_effect(SkillEffect.Type.INFERNO, center.global_position)
	for opp in opponents:
		if opp == null or not is_instance_valid(opp):
			continue
		if center.grid_position.distance_to(opp.grid_position) <= 2.0:
			var dmg := int(caster.magic_power * caster.skill_damage_multiplier)
			opp.take_damage(dmg, caster.current_element)

# White Mage: heals all allies
func _holy_light(caster: UnitBase) -> void:
	var allies := player_units if caster.is_player_unit else enemy_units
	for ally in allies:
		if ally == null or not is_instance_valid(ally):
			continue
		var heal_amount := int(caster.magic_power * 1.2)
		ally.heal(heal_amount)
		_spawn_skill_effect(SkillEffect.Type.HOLY_LIGHT, ally.global_position)

# Red Mage: random-element bolt at the nearest 2 enemies
func _chaos_bolt(caster: UnitBase, opponents: Array) -> void:
	var sorted := opponents.filter(func(u): return u != null and is_instance_valid(u))
	sorted.sort_custom(func(a, b):
		return caster.grid_position.distance_to(a.grid_position) < \
			   caster.grid_position.distance_to(b.grid_position))
	var _random_elem: UnitBase.Element = UnitBase.Element.values()[randi() % UnitBase.Element.values().size()]
	var count := mini(2, sorted.size())
	for i in range(count):
		var target: UnitBase = sorted[i]
		var dmg := int((caster.attack_damage + caster.magic_power) * 0.5 * caster.skill_damage_multiplier)
		caster.spawn_projectile(target, dmg)
		_spawn_skill_effect(SkillEffect.Type.CHAOS_BOLT, target.global_position)

func check_battle_end() -> void:
	# Remove dead units
	player_units = player_units.filter(func(u): return u != null and is_instance_valid(u))
	enemy_units = enemy_units.filter(func(u): return u != null and is_instance_valid(u))
	
	if enemy_units.is_empty():
		end_battle(true)
	elif player_units.is_empty():
		end_battle(false)

func end_battle(player_won: bool) -> void:
	battle_active = false
	battle_ended.emit(player_won)
	# State transition is handled by _on_battle_ended in main_game.gd

func move_unit_towards_with_pathfinding(unit: UnitBase, target_pos: Vector2i) -> void:
	if not battle_grid:
		return
	
	var current_pos = unit.grid_position
	
	# Check if we need a new path or if target moved
	var needs_new_path = false
	if not unit_paths.has(unit):
		needs_new_path = true
	else:
		var cached_path = unit_paths[unit]
		# If path is empty or target moved significantly, recalculate
		if cached_path.is_empty():
			needs_new_path = true
		elif cached_path.size() > 0:
			var path_goal = cached_path[cached_path.size() - 1]
			# Recalculate if target moved more than 2 cells from path goal
			if path_goal.distance_to(target_pos) > 2:
				needs_new_path = true
	
	if needs_new_path:
		var new_path = Pathfinding.find_path(current_pos, target_pos, battle_grid)
		if new_path.is_empty():
			print("[Path] NO PATH from %s to %s" % [current_pos, target_pos])
			return
		if new_path.size() > 0 and new_path[0] == current_pos:
			new_path.remove_at(0)
		unit_paths[unit] = new_path
		print("[Path] found len=%d first=%s" % [new_path.size(), new_path[0] if new_path.size() > 0 else "EMPTY"])

	var path = unit_paths[unit]
	if path.is_empty():
		print("[Path] path empty after cache")
		return

	var next_pos = path[0]
	var occupied = battle_grid.is_cell_occupied(next_pos)
	if not battle_grid.is_valid_position(next_pos) or occupied:
		print("[Path] next_pos %s blocked (occupied=%s)" % [next_pos, occupied])
		unit_paths.erase(unit)
		return

	if not unit.is_moving:
		start_unit_movement(unit, current_pos, next_pos)

func add_projectile(projectile: Projectile) -> void:
	if projectile_container:
		projectile_container.add_child(projectile)

func start_unit_movement(unit: UnitBase, from_pos: Vector2i, to_pos: Vector2i) -> void:
	print("[Move] START %s → %s" % [from_pos, to_pos])
	unit.is_moving = true
	unit.move_start_pos = battle_grid.grid_to_world(from_pos)
	unit.move_target_pos = battle_grid.grid_to_world(to_pos)
	unit.move_progress = 0.0
	unit.target_grid_pos = to_pos

	battle_grid.remove_unit(from_pos)
	var placed = battle_grid.place_unit(unit, to_pos)
	unit.grid_position = to_pos
	print("[Move] placed=%s gpos_after=%s is_moving=%s" % [placed, unit.grid_position, unit.is_moving])

func update_unit_movements(delta: float) -> void:
	# Update all player units
	for unit in player_units:
		if unit and is_instance_valid(unit) and unit.is_moving:
			update_single_unit_movement(unit, delta)
	
	# Update all enemy units
	for unit in enemy_units:
		if unit and is_instance_valid(unit) and unit.is_moving:
			update_single_unit_movement(unit, delta)

func update_single_unit_movement(unit: UnitBase, delta: float) -> void:
	# Calculate movement speed based on unit's movement_speed stat
	# Higher movement_speed = faster interpolation
	var speed_multiplier = unit.movement_speed * base_movement_speed
	unit.move_progress += delta * speed_multiplier
	
	if unit.move_progress >= 1.0:
		# Movement complete
		unit.position = unit.move_target_pos
		unit.is_moving = false
		unit.move_progress = 0.0
		
		# Remove completed step from path
		if unit_paths.has(unit):
			var path = unit_paths[unit]
			if path.size() > 0:
				path.remove_at(0)
				if path.is_empty():
					unit_paths.erase(unit)
	else:
		# Interpolate position
		unit.position = unit.move_start_pos.lerp(unit.move_target_pos, unit.move_progress)
