extends Node
class_name AutoBattleManager

# References
var battle_grid: BattleGrid
var game_state: GameState
var projectile_container: Node2D
var skill_effect_container: Node2D
var background_layer: BackgroundLayer   # set by main_game; used for drag-zone indicator

# Battle state
var player_units: Array = []
var enemy_units: Array = []
var battle_active: bool = false

# Movement speed multiplier (higher = faster base movement)
var base_movement_speed: float = 0.5

# Unit movement paths
var unit_paths: Dictionary = {}  # unit -> Array[Vector2i]

# ── Real-time pace control ────────────────────────────────────────────────────
# The battle is a live simulation. `time_scale` multiplies every delta so the user
# can slow it to 0.25× for a play-by-play or speed to 4×. `paused` freezes time
# entirely (including movement interpolation).
var paused: bool = false
var time_scale: float = 1.0

# ── Roster-expansion runtime state ────────────────────────────────────────────
# Rush "Afterimage": while active, every unit except the actor is frozen.
var afterimage_actor: UnitBase = null
var afterimage_time: float = 0.0

# Zolt storms — roaming board hazards, ticked here, freed at round end.
var storms: Array = []

# Board-wide field effects that damage enemies as they move.
var thorns_time: float = 0.0          # June "Bloom"
var thorns_dmg: int = 0
var thorns_owner_is_player: bool = true
var grid_field_time: float = 0.0      # Static "Grid"
var grid_field_dmg: int = 0
var grid_owner_is_player: bool = true
var fire_trail: Dictionary = {}       # Vector2i -> {dmg,time,source,owner_is_player}  Sear passive

# Re-entrancy guard so Stitch Link / Loose Threads can't recurse forever.
var _propagating: bool = false

# Snapshots of fallen player heroes so Doc can revive one (Field Surgery).
var fallen_allies: Array = []


signal battle_started()
signal battle_ended(player_won: bool)
signal unit_action(unit, action_type: String)
signal action_logged(text: String, is_player: bool)   # event-history feed
signal pace_changed(is_paused: bool, scale: float)
signal unit_summoned(unit: UnitBase)

func _ready():
	pass

func initialize(grid: BattleGrid, state: GameState) -> void:
	battle_grid = grid
	game_state = state
	
	if game_state:
		game_state.auto_battle_started.connect(_on_auto_battle_started)

func _on_auto_battle_started() -> void:
	start_battle()

# Global pacing knob: the game plays too fast per user feedback (2026-07-02) —
# a first, easily-reversible -10% cut across the whole sim (movement, attacks,
# regen, everything derives dt from time_scale). Revisit if -20% ends up wanted.
const BASE_TIME_SCALE := 0.9

# Perf pass (2026-07-03): several per-unit passives (NEMI/BOUNCER/PASTOR/JUNE/REED)
# used to re-scan the full ally+enemy roster every single frame purely to check
# proximity — O(N) distance checks x every unit with that class x 60fps. These
# are slow-moving auras, not instant reactions, so they're now throttled to this
# interval instead (~4 refreshes/sec) via a per-unit "aura_tick_t" meta countdown.
const AURA_TICK_INTERVAL := 0.25

# Gate for per-frame pathfinding debug prints (see move_unit_towards_with_
# pathfinding). NEVER ship true — printing every frame per stuck unit was a
# measurable part of the 15+ unit lag (2026-07-04 perf pass).
const PATH_DEBUG := false

func start_battle() -> void:
	battle_active = true
	unit_paths.clear()
	paused = false
	time_scale = BASE_TIME_SCALE
	_clear_board_effects()
	afterimage_actor = null
	afterimage_time = 0.0
	fallen_allies.clear()
	collect_units()
	_init_unit_timers()
	print("[Battle] Started — players: %d, enemies: %d" % [player_units.size(), enemy_units.size()])
	battle_started.emit()
	pace_changed.emit(paused, time_scale)

# Reset every unit's real-time clocks at the start of a battle. Skills begin on
# cooldown (skill_cooldown_max is now read as SECONDS), basic attacks start ready.
func _init_unit_timers() -> void:
	for unit in player_units + enemy_units:
		if not (unit and is_instance_valid(unit)):
			continue
		unit.attack_cooldown = 0.0
		unit.skill_cd_time = float(unit.skill_cooldown_max)
		unit.stun_time = 0.0
		unit.rapid_fire_time = 0.0
		unit.overdrive_time = 0.0
		unit.hp_regen_accum = 0.0
		unit.mp_regen_accum = 0.0
		unit.lordee_aura_timer = 0.0
		unit.lordee_chase_timer = 0.0
		unit.current_shield = 0
		# Roster-expansion status fields
		unit.burn_time = 0.0; unit.burn_dps = 0.0; unit.burn_accum = 0.0; unit.burn_source = null
		unit.slow_time = 0.0; unit.slow_pct = 0.0
		unit.root_time = 0.0
		unit.taunt_time = 0.0; unit.taunt_source = null
		unit.untargetable_time = 0.0
		unit.outgoing_dmg_mult = 1.0; unit.outgoing_dmg_time = 0.0
		unit.bonus_aspd_pct = 0.0; unit.bonus_aspd_time = 0.0
		unit.weakened_pct = 0.0; unit.weakened_time = 0.0
		unit.spore_stacks = 0.0; unit.spore_tick_accum = 0.0
		unit.shock_cd = 0.0
		unit.momentum_stacks = 0
		unit.link_partner = null
		unit.puppet_time = 0.0
		unit.stoke_charges = 0
		unit.meltdown_time = 0.0
		unit.combat_healing_done = 0
		unit.revive_used = false
		# Stat Stealer drain — no lingering theft into a fresh battle.
		unit.drain_time = 0.0; unit.drain_stat = ""; unit.drain_per_sec = 0.0
		unit.drain_stolen = 0.0; unit.drain_source = null; unit.drain_accum = 0.0
		# Ant Hill swarm — no lingering bite-vulnerability into a fresh battle;
		# the hill's spawn clock gets a short pre-delay before its first ant.
		unit.ant_bite_stacks = 0
		unit.summon_spawn_timer = 2.5
		# ── Relic battle-start effects ──
		unit.relic_revive_used = false
		if unit.relic_start_shield_pct > 0.0:
			unit.current_shield += int(round(unit.max_hp * unit.relic_start_shield_pct))
		if unit.relic_free_first_ult and unit.ultimate_charge_max > 0:
			unit.ultimate_charge = unit.ultimate_charge_max
			unit.ultimate_ready = true

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
				if not unit.died.is_connected(_on_ally_died):
					unit.died.connect(_on_ally_died.bind(unit))
			else:
				enemy_units.append(unit)
		else:
			print("[Battle] Cell %s has non-unit or null: %s" % [grid_pos, unit])

func _process(delta: float) -> void:
	if not battle_active:
		return

	# Scale real time by the user's pace setting. Paused → frozen.
	var dt: float = 0.0 if paused else delta * time_scale
	if dt <= 0.0:
		return

	# Global timers (Rush freeze, board fields) tick once per frame, not per unit.
	_tick_global_effects(dt)

	# Tick every living unit's real-time clocks and let it act.
	for unit in player_units + enemy_units:
		if unit and is_instance_valid(unit):
			_tick_unit(unit, dt)

	# Roaming storm hazards.
	for storm in storms:
		if storm and is_instance_valid(storm):
			storm.tick(dt)

	# Smooth movement interpolation (also scaled, so slow-mo slows motion too).
	update_unit_movements(dt)

	check_battle_end()

# Frame-level decay for effects that aren't owned by a single unit.
func _tick_global_effects(dt: float) -> void:
	if afterimage_time > 0.0:
		afterimage_time -= dt
		# If the actor died mid-cast, end the freeze immediately so nobody stalls.
		if afterimage_time <= 0.0 or not (afterimage_actor and is_instance_valid(afterimage_actor)):
			afterimage_time = 0.0
			afterimage_actor = null
	if thorns_time > 0.0:
		thorns_time -= dt
	if grid_field_time > 0.0:
		grid_field_time -= dt
	if not fire_trail.is_empty():
		var expired: Array = []
		for cell in fire_trail:
			fire_trail[cell]["time"] -= dt
			if fire_trail[cell]["time"] <= 0.0:
				expired.append(cell)
		for cell in expired:
			fire_trail.erase(cell)

func _clear_board_effects() -> void:
	for storm in storms:
		if storm and is_instance_valid(storm):
			storm.queue_free()
	storms.clear()
	thorns_time = 0.0
	grid_field_time = 0.0
	fire_trail.clear()

# ── Pace control ──────────────────────────────────────────────────────────────
func set_paused(p: bool) -> void:
	paused = p
	pace_changed.emit(paused, time_scale)

func set_time_scale(scale: float) -> void:
	time_scale = scale
	paused = false
	pace_changed.emit(paused, time_scale)

# ── Per-unit real-time update ─────────────────────────────────────────────────
# Runs every frame for every living unit. Counts its timers down, applies regen,
# then takes at most one meaningful action this frame following priority:
#   ultimate (when charged) > active skill (cooldown + mana) > attack (in range) > move.
func _tick_unit(unit: UnitBase, dt: float) -> void:
	# Rush "Afterimage": every other unit is frozen while the actor moves freely.
	if afterimage_time > 0.0 and unit != afterimage_actor:
		return

	# Stitch "Puppet": a controlled enemy treats its own team as the enemy.
	var own_is_player: bool = unit.is_player_unit
	if unit.puppet_time > 0.0:
		own_is_player = not own_is_player
	var opponents: Array = enemy_units if own_is_player else player_units
	var allies: Array    = player_units if own_is_player else enemy_units

	_regen_tick(unit, dt)
	_tick_statuses(unit, dt)
	if not (unit and is_instance_valid(unit)):
		return   # a damage-over-time tick may have killed it
	_tick_passive(unit, opponents, allies, dt)

	# Count down all real-time timers.
	if unit.stun_time > 0.0:      unit.stun_time -= dt
	if unit.skill_cd_time > 0.0:  unit.skill_cd_time -= dt
	if unit.attack_cooldown > 0.0: unit.attack_cooldown -= dt
	if unit.rapid_fire_time > 0.0: unit.rapid_fire_time -= dt
	if unit.overdrive_time > 0.0:  unit.overdrive_time -= dt

	# Stunned or rooted-into-stun: no actions until it wears off.
	if unit.stun_time > 0.0:
		return

	unit.target_unit = _choose_target(unit, opponents)

	# ── Ultimate (fires the moment it is charged) ──────────────────────────────
	if unit.ultimate_ready:
		var ult_before: int = unit.damage_dealt
		_use_ultimate(unit, opponents, allies)
		if unit.has_method("cast_particles"): unit.cast_particles()
		unit.ultimate_ready = false
		unit.ultimate_charge = 0
		unit_action.emit(unit, "ultimate")
		var ult_name: String = unit.ultimate_name if unit.ultimate_name != "" else "their ultimate"
		var ult_dmg: int = unit.damage_dealt - ult_before
		if ult_dmg > 0:
			action_logged.emit("%s unleashes %s! (%d dmg)" % [unit.unit_name, ult_name, ult_dmg], unit.is_player_unit)
		else:
			action_logged.emit("%s unleashes %s!" % [unit.unit_name, ult_name], unit.is_player_unit)
		return

	# ── Active skill (needs cooldown elapsed AND enough mana) ──────────────────
	if unit.skill_cd_time <= 0.0 and unit.skill_name != "" \
			and unit.current_mana >= unit.skill_mana_cost \
			and _skill_trigger_ready(unit, opponents):
		if unit.skill_mana_cost > 0:
			unit.spend_mana(unit.skill_mana_cost)
		var skill_before: int = unit.damage_dealt
		_use_skill(unit, opponents, allies)
		if unit.has_method("cast_particles"): unit.cast_particles()
		unit.skill_cd_time = float(unit.skill_cooldown_max)   # cooldown in seconds
		unit_action.emit(unit, "skill")
		var skill_dmg: int = unit.damage_dealt - skill_before
		if skill_dmg > 0:
			action_logged.emit("%s casts %s (%d dmg)" % [unit.unit_name, unit.skill_name, skill_dmg], unit.is_player_unit)
		else:
			action_logged.emit("%s casts %s" % [unit.unit_name, unit.skill_name], unit.is_player_unit)
		return

	# ── Basic attack / move toward target ──────────────────────────────────────
	var target: UnitBase = unit.target_unit
	if not (target and is_instance_valid(target)):
		return

	var effective_range: int = unit.attack_range + (2 if unit.rapid_fire_time > 0.0 else 0)
	# Use Chebyshev (grid) distance to match 8-directional movement. Euclidean here
	# left diagonally-adjacent melee units (dist 1.41 > range 1) permanently stuck:
	# "out of range" yet unable to step orthogonally closer past a blocking ally.
	if _grid_dist(unit.grid_position, target.grid_position) <= effective_range:
		# In range: attack only when this unit's attack timer is ready.
		if unit.attack_cooldown <= 0.0:
			unit.pending_attack_log_damage = 0
			if unit.rapid_fire_time > 0.0 and opponents.size() > 1:
				var second := _second_nearest(unit, target, opponents)
				if second:
					unit.attack(second)
			unit.attack(target)
			_apply_on_hit_passives(unit, target, opponents)
			# Twin Fang relic: chance for the attack to strike a second time.
			if unit.relic_double_atk_chance > 0.0 and randf() < unit.relic_double_atk_chance and is_instance_valid(target) and target.current_hp > 0:
				unit.attack(target)
				_apply_on_hit_passives(unit, target, opponents)
			# Shauna Overdrive: an extra swing per attack while active.
			if unit.overdrive_time > 0.0:
				unit.attack(target)
				_spawn_skill_effect_sized(SkillEffect.Type.OVERDRIVE, unit.global_position, 32.0)
			var haste: float = unit.equipment_passives.get("Haste", 0.0)
			unit.attack_cooldown = 1.0 / (unit.attacks_per_second * (1.0 + haste))
			unit_action.emit(unit, "attack")
			unit_paths.erase(unit)
			var atk_dmg: int = unit.pending_attack_log_damage
			if unit.attack_range > 1:
				action_logged.emit("%s shoots %s for %d damage" % [unit.unit_name, target.unit_name, atk_dmg], unit.is_player_unit)
			else:
				action_logged.emit("%s attacks %s for %d damage" % [unit.unit_name, target.unit_name, atk_dmg], unit.is_player_unit)
	elif not unit.is_moving and unit.movement_speed > 0 and unit.root_time <= 0.0:
		# Out of range: keep closing the distance (rooted units can't move).
		if unit.cell_size > 1:
			_move_2x2_unit(unit, target.grid_position)
		else:
			move_unit_towards_with_pathfinding(unit, target.grid_position)

# Smoothly accrue HP/MP over time. Fractional amounts carry between frames so even
# slow regen ticks up correctly at any time scale.
func _regen_tick(unit: UnitBase, dt: float) -> void:
	if unit.current_hp < unit.max_hp:
		unit.hp_regen_accum += unit.hp_regen * dt
		# Equipment Regeneration: effect_value * 30 HP/sec (0.15–0.30 → 4.5–9 HP/sec)
		var regen_passive: float = unit.equipment_passives.get("Regeneration", 0.0)
		if regen_passive > 0.0:
			unit.hp_regen_accum += regen_passive * 30.0 * dt
		# Titan's Heart relic: regenerate a fraction of MAX HP per second.
		if unit.relic_regen_pct > 0.0:
			unit.hp_regen_accum += unit.max_hp * unit.relic_regen_pct * dt
		if unit.hp_regen_accum >= 1.0:
			var whole: int = int(unit.hp_regen_accum)
			unit.heal(whole)
			unit.hp_regen_accum -= whole
	if unit.current_mana < unit.max_mana:
		unit.mp_regen_accum += unit.mana_regen * dt
		if unit.mp_regen_accum >= 1.0:
			var whole: int = int(unit.mp_regen_accum)
			unit.restore_mana(whole)
			unit.mp_regen_accum -= whole

# Pick target: Bloodhound in frenzy locks on most-damage-dealer; Lordee chases steal target; else nearest
func _choose_target(unit: UnitBase, opponents: Array) -> UnitBase:
	# Taunt overrides everything (Riot Shield Bash / Kettle).
	if unit.taunt_time > 0.0 and unit.taunt_source != null and is_instance_valid(unit.taunt_source) \
			and unit.taunt_source in opponents and unit.taunt_source.untargetable_time <= 0.0:
		return unit.taunt_source as UnitBase
	if unit.frenzy_active and unit.most_damage_dealer != null and is_instance_valid(unit.most_damage_dealer):
		return unit.most_damage_dealer as UnitBase
	if unit.unit_class == UnitBase.UnitClass.LORDEE and unit.lordee_chase_timer > 0.0 \
			and unit.lordee_chase_target != null and is_instance_valid(unit.lordee_chase_target):
		return unit.lordee_chase_target as UnitBase
	return find_nearest_enemy(unit, opponents)

# ── Focus system ──────────────────────────────────────────────────────────────
# How many of `potential_focusers` are currently targeting `unit`.
# Relies on each unit's target_unit being recorded every frame in _tick_unit().
func _count_focusers(unit: UnitBase, potential_focusers: Array) -> int:
	var count := 0
	for f in potential_focusers:
		if f and is_instance_valid(f) and f.target_unit == unit:
			count += 1
	return count

func _is_focused(unit: UnitBase, potential_focusers: Array) -> bool:
	return _count_focusers(unit, potential_focusers) > 0

# Per-class condition gating whether an active skill may fire this turn.
# Default: always ready. Shauna's Kite only fires while an enemy focuses her.
func _skill_trigger_ready(unit: UnitBase, opponents: Array) -> bool:
	match unit.unit_class:
		UnitBase.UnitClass.SHAUNA:
			return _is_focused(unit, opponents)
		_:
			return true

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
func _tick_passive(unit: UnitBase, opponents: Array, allies: Array, dt: float) -> void:
	match unit.unit_class:
		UnitBase.UnitClass.ANT_HILL:
			_ant_hill_spawn_tick(unit, allies, dt)

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

		UnitBase.UnitClass.NEMI:
			# Resonance: allies near Nemi get +1 move speed this turn; nearest enemy gets -1.
			# Full-roster distance scan — throttled to every AURA_TICK_INTERVAL (perf: was
			# every frame, i.e. O(N) roster scans x 60/sec per Nemi on the field).
			var nemi_t: float = float(unit.get_meta("aura_tick_t", 0.0)) - dt
			if nemi_t > 0.0:
				unit.set_meta("aura_tick_t", nemi_t)
			else:
				unit.set_meta("aura_tick_t", AURA_TICK_INTERVAL)
				for ally in allies:
					if ally and is_instance_valid(ally) and ally != unit:
						if unit.grid_position.distance_to(ally.grid_position) <= 3:
							# Temporary buff via metadata reset each turn
							if not ally.has_meta("resonance_buffed"):
								ally.movement_speed = min(ally.movement_speed + 1, 8)
								ally.set_meta("resonance_buffed", true)
						else:
							if ally.has_meta("resonance_buffed"):
								ally.movement_speed = max(ally.movement_speed - 1, 1)
								ally.remove_meta("resonance_buffed")
				var debuff_target := find_nearest_enemy(unit, opponents)
				if debuff_target and not debuff_target.has_meta("resonance_debuffed"):
					# Floor of 1 (not 0) — a debuff should never fully immobilize a
					# unit. Ant Hill is the sole deliberately-stationary exception
					# (movement_speed=0 by design, see enemy_factory.gd) so it's
					# excluded here rather than getting bumped to 1 by a debuff.
					var move_floor: int = 0 if debuff_target.unit_class == UnitBase.UnitClass.ANT_HILL else 1
					debuff_target.movement_speed = max(debuff_target.movement_speed - 1, move_floor)
					debuff_target.set_meta("resonance_debuffed", true)

		UnitBase.UnitClass.BOUNCER:
			# Presence: count units within 2 tiles (recalculated, stored in offensive affinity).
			# Throttled to AURA_TICK_INTERVAL — see NEMI comment above, same perf reasoning.
			var bouncer_t: float = float(unit.get_meta("aura_tick_t", 0.0)) - dt
			if bouncer_t > 0.0:
				unit.set_meta("aura_tick_t", bouncer_t)
			else:
				unit.set_meta("aura_tick_t", AURA_TICK_INTERVAL)
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

		UnitBase.UnitClass.LORDEE:
			# Feeding Frenzy: AoE damage pulse every 0.8s to adjacent enemies
			unit.lordee_aura_timer -= dt
			if unit.lordee_aura_timer <= 0.0:
				unit.lordee_aura_timer = 0.8
				var aura_dmg := int(unit.attack_damage * 0.12)
				for opp in opponents:
					if opp and is_instance_valid(opp):
						if unit.grid_position.distance_to(opp.grid_position) <= 1.5:
							opp.take_damage(aura_dmg, unit.current_element)
							unit.damage_dealt += aura_dmg
			# Chase timer — if target dies while chasing, lock in a small permanent bonus
			if unit.lordee_chase_timer > 0.0:
				unit.lordee_chase_timer -= dt
				var ct: UnitBase = unit.lordee_chase_target
				if ct != null and not is_instance_valid(ct):
					# Target died — permanent steal (already applied, just clear temp)
					unit.lordee_chase_target = null
					unit.lordee_chase_timer = 0.0

		UnitBase.UnitClass.NECRO:
			# Soul Harvest: heal Necro for a trickle based on active summoned units nearby
			var summon_count := 0
			for ally in allies:
				if ally and is_instance_valid(ally) and ally.is_summoned and ally.summon_owner == unit:
					summon_count += 1
			if summon_count > 0:
				unit.hp_regen_accum += float(summon_count) * 0.5 * dt

		# ── Roster expansion (per-frame passives) ─────────────────────────────
		UnitBase.UnitClass.DOC:
			# Triage: periodically mend the lowest-HP ally; heal scales with missing HP.
			var doc_t: float = float(unit.get_meta("triage_t", 0.0)) - dt
			if doc_t <= 0.0:
				doc_t = 1.4
				var doc_tar := _lowest_hp_ally(unit, allies, 4.0, true)
				if doc_tar:
					var doc_miss: float = 1.0 - float(doc_tar.current_hp) / float(maxi(doc_tar.max_hp, 1))
					var doc_amt: int = int(float(unit.magic_power) * (0.35 + doc_miss * 1.1) * UnitFactory.natural_aspect(unit))
					doc_tar.heal(doc_amt)
					unit.combat_healing_done += doc_amt
					_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, doc_tar.global_position, 26.0)
			unit.set_meta("triage_t", doc_t)

		UnitBase.UnitClass.PASTOR:
			# Righteous Fury: nearby allies deal bonus damage.
			# Throttled to AURA_TICK_INTERVAL — see NEMI comment above, same perf reasoning
			# (the buff duration below outlasts the tick gap, so no per-frame precision lost).
			var pastor_t: float = float(unit.get_meta("aura_tick_t", 0.0)) - dt
			if pastor_t > 0.0:
				unit.set_meta("aura_tick_t", pastor_t)
			else:
				unit.set_meta("aura_tick_t", AURA_TICK_INTERVAL)
				var pastor_bonus: float = 0.12 * UnitFactory.natural_aspect(unit)
				for ally in allies:
					if ally and is_instance_valid(ally):
						if unit.grid_position.distance_to(ally.grid_position) <= 3.0:
							ally.outgoing_dmg_mult = maxf(ally.outgoing_dmg_mult, 1.0 + pastor_bonus)
							ally.outgoing_dmg_time = maxf(ally.outgoing_dmg_time, 0.35)

		UnitBase.UnitClass.JUNE:
			# Verdant Aura: nearby allies slowly regenerate HP.
			# Throttled to AURA_TICK_INTERVAL — regen amount uses the fixed interval (not dt)
			# so the total HP/sec granted is unchanged, just delivered in bigger, less frequent chunks.
			var june_t: float = float(unit.get_meta("aura_tick_t", 0.0)) - dt
			if june_t > 0.0:
				unit.set_meta("aura_tick_t", june_t)
			else:
				unit.set_meta("aura_tick_t", AURA_TICK_INTERVAL)
				for ally in allies:
					if ally and is_instance_valid(ally) and ally != unit:
						if unit.grid_position.distance_to(ally.grid_position) <= 3.0:
							ally.hp_regen_accum += (float(unit.magic_power) * 0.10 * UnitFactory.natural_aspect(unit)) * AURA_TICK_INTERVAL

		UnitBase.UnitClass.REED:
			# Wellspring: stronger nearby regen + debuffs fade 30% faster.
			# Throttled to AURA_TICK_INTERVAL — same reasoning as JUNE above.
			var reed_t: float = float(unit.get_meta("aura_tick_t", 0.0)) - dt
			if reed_t > 0.0:
				unit.set_meta("aura_tick_t", reed_t)
			else:
				unit.set_meta("aura_tick_t", AURA_TICK_INTERVAL)
				for ally in allies:
					if ally and is_instance_valid(ally) and ally != unit:
						if unit.grid_position.distance_to(ally.grid_position) <= 3.0:
							ally.hp_regen_accum += (float(unit.magic_power) * 0.12 * UnitFactory.natural_aspect(unit)) * AURA_TICK_INTERVAL
							if ally.slow_time > 0.0: ally.slow_time -= AURA_TICK_INTERVAL * 0.3
							if ally.burn_time > 0.0: ally.burn_time -= AURA_TICK_INTERVAL * 0.3
							if ally.root_time > 0.0: ally.root_time -= AURA_TICK_INTERVAL * 0.3

		UnitBase.UnitClass.SHEILDOR:
			# "Guardian Aura" (implemented 2026-07-03 — the factory has shown this
			# passive_name in the UI since creation with NO implementation behind
			# it): every few seconds, grant a small shield to the most-wounded
			# adjacent ally. A mini echo of his skill, aura-throttle pattern.
			var shel_t: float = float(unit.get_meta("bulwark_t", 0.0)) - dt
			if shel_t > 0.0:
				unit.set_meta("bulwark_t", shel_t)
			else:
				unit.set_meta("bulwark_t", 4.0)
				var shel_tar := _lowest_hp_ally(unit, allies, 1.5, false)
				if shel_tar and shel_tar != unit:
					var shel_amt: int = int(float(unit.magic_power) * 0.35 * UnitFactory.natural_aspect(unit))
					shel_tar.current_shield += shel_amt
					if shel_tar.health_bar:
						shel_tar.health_bar.update_shield(shel_tar.current_shield, shel_tar.max_hp)
					_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, shel_tar.global_position, 22.0)

		UnitBase.UnitClass.VAIL:
			# "Far Winds" (implemented 2026-07-03 — passive_name existed in the UI
			# with NO implementation): allies near Vail attack slightly faster.
			# Mirrors PASTOR's refresh-a-short-buff aura shape — never stacks/leaks.
			var vail_t: float = float(unit.get_meta("aura_tick_t", 0.0)) - dt
			if vail_t > 0.0:
				unit.set_meta("aura_tick_t", vail_t)
			else:
				unit.set_meta("aura_tick_t", AURA_TICK_INTERVAL)
				var vail_bonus: float = 0.10 * UnitFactory.natural_aspect(unit)
				for v_ally in allies:
					if v_ally and is_instance_valid(v_ally) and v_ally != unit:
						if unit.grid_position.distance_to(v_ally.grid_position) <= 3.0:
							v_ally.bonus_aspd_pct = maxf(v_ally.bonus_aspd_pct, vail_bonus)
							v_ally.bonus_aspd_time = maxf(v_ally.bonus_aspd_time, 0.35)

		UnitBase.UnitClass.SPORE:
			# Spore Cloud: enemies within 2 cells accrue stacks; burst handled in _tick_statuses.
			var spore_burst_amt: int = int(float(unit.magic_power) * 1.6 * UnitFactory.natural_aspect(unit))
			for opp in opponents:
				if opp and is_instance_valid(opp):
					if unit.grid_position.distance_to(opp.grid_position) <= 2.0:
						opp.spore_stacks += dt
						opp.set_meta("spore_source", unit)
						opp.set_meta("spore_burst", spore_burst_amt)

# ── Ultimate implementations ──────────────────────────────────────────────────
func _use_ultimate(caster: UnitBase, opponents: Array, allies: Array) -> void:
	match caster.unit_class:
		UnitBase.UnitClass.STAT_STEALER:
			_stat_steal_drain(caster, opponents)

		UnitBase.UnitClass.BLOODHOUND:
			# Pounce — leap to most-damage-dealer, stun + 250% ATK
			var _mdl = caster.most_damage_dealer
			var target: UnitBase = _mdl if (is_instance_valid(_mdl) and _mdl != null) else null
			if not (target and is_instance_valid(target)):
				target = find_nearest_enemy(caster, opponents)
			if not target:
				return
			var dmg := int(caster.attack_damage * caster.ultimate_damage_mult)
			target.take_damage(dmg, caster.current_element)
			target.stun_time = 1.5
			caster.damage_dealt += dmg
			_spawn_skill_effect(SkillEffect.Type.SHADOW_STRIKE, caster.global_position)

		UnitBase.UnitClass.BOUNCER:
			# Gravity Drop — warning ring + pull all enemies in range + impact
			var dmg := int(caster.magic_power * caster.ultimate_damage_mult)
			var bonus: float = caster.get_meta("presence_bonus") if caster.has_meta("presence_bonus") else 0.0
			if caster.has_meta("presence_bonus"):
				bonus = float(caster.get_meta("presence_bonus"))
			dmg = int(dmg * (1.0 + bonus))

			# Large gravity drop effect centred on Bouncer, sized to cover the 4x4 pull area
			# (grid cell_size is 110px, so 4 cells ≈ 440px across)
			_spawn_sprite_sheet_effect(
				"res://assets/using/effects_projectiles/bouncer_ult.png",
				caster.global_position, 64, 60, 14, Vector2(480, 480))

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
							opp.position = _world_pos_for(opp, open_cell)
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
		UnitBase.UnitClass.SHEILDOR:
			_sheildor_guardian_leap(caster, allies, opponents)
		UnitBase.UnitClass.LORDEE:
			_lordee_parasite_lunge(caster, opponents)
		UnitBase.UnitClass.SHAUNA:
			# Overdrive: 3 extra attack turns
			caster.overdrive_time = 4.0
			_spawn_skill_effect(SkillEffect.Type.OVERDRIVE, caster.global_position)

		UnitBase.UnitClass.NECRO:
			_necro_bat_swarm(caster, opponents)
		UnitBase.UnitClass.NEMI:
			# Tidal Wave: 3-wide column sweep with pushback
			_nemi_tidal_wave(caster, opponents)

		UnitBase.UnitClass.WHITE_MAGE:
			# Mass Rejuvenation — heal all allies for 30% of their max HP
			for ally in allies:
				if not (ally and is_instance_valid(ally)):
					continue
				var heal_amt := int(ally.max_hp * 0.30)
				ally.heal(heal_amt)
				_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, ally.global_position, 40.0)

		UnitBase.UnitClass.RED_MAGE:
			# Arcane Overload — 220% MAG to all enemies within range 4
			var dmg_r := int(caster.magic_power * 2.2)
			for opp in opponents:
				if not (opp and is_instance_valid(opp)):
					continue
				if caster.grid_position.distance_to(opp.grid_position) <= 4:
					opp.take_damage(dmg_r, caster.current_element)
					caster.damage_dealt += dmg_r
					_spawn_skill_effect_sized(SkillEffect.Type.CHAOS_BOLT, opp.global_position, 36.0)

		# ── Roster expansion ───────────────────────────────────────────────────
		UnitBase.UnitClass.DOC:        _doc_field_surgery(caster, allies)
		UnitBase.UnitClass.RIOT:       _riot_kettle(caster, opponents)
		UnitBase.UnitClass.PASTOR:     _pastor_damnation(caster, opponents)
		UnitBase.UnitClass.SABLE:      _sable_headshot(caster, opponents)
		UnitBase.UnitClass.RUSH:       _rush_afterimage(caster, opponents)
		UnitBase.UnitClass.STITCH:     _stitch_puppet(caster, opponents)
		UnitBase.UnitClass.COAL:       _coal_meltdown(caster)
		UnitBase.UnitClass.JUNE:       _june_bloom(caster)
		UnitBase.UnitClass.CROSS:      _cross_judgment(caster, opponents)
		UnitBase.UnitClass.SEAR:      _sear_conflagration(caster, opponents)
		UnitBase.UnitClass.EMBER:      _ember_wildfire(caster, opponents)
		UnitBase.UnitClass.RIFT:       _rift_collapse(caster, opponents)
		UnitBase.UnitClass.ZOLT:       _zolt_thunderhammer(caster, opponents)
		UnitBase.UnitClass.LUMEN:      _lumen_prism(caster, opponents)
		UnitBase.UnitClass.STATIC:     _static_grid(caster)
		UnitBase.UnitClass.REED:       _reed_confluence(caster, allies)
		UnitBase.UnitClass.VAIL:       _vail_tailwind(caster, allies)
		UnitBase.UnitClass.SPORE:      _spore_release(caster, opponents)

		_:
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

# Chebyshev distance — the true step count on an 8-directional grid.
func _grid_dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func find_nearest_enemy(unit: UnitBase, enemies: Array) -> UnitBase:
	var nearest: UnitBase = null
	var min_distance: float = INF
	
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.untargetable_time > 0.0:   # Vail Updraft etc.
			continue

		var distance = unit.grid_position.distance_to(enemy.grid_position)
		if distance < min_distance:
			min_distance = distance
			nearest = enemy

	return nearest

func assign_preferred_target(unit: UnitBase, target: UnitBase) -> void:
	unit.target_unit = target

# ── Skill execution ───────────────────────────────────────────────────────────

func _use_skill(caster: UnitBase, opponents: Array, allies: Array = []) -> void:
	# Basic-mob signature moves dispatch on `mob_skill` meta BEFORE the class
	# match — mobs piggyback hero classes for stats/sprites, so class arms
	# can't tell a Goblin from the Triarch's warrior phase. See _use_mob_skill.
	var mob_skill: String = str(caster.get_meta("mob_skill", ""))
	if mob_skill != "":
		_use_mob_skill(caster, mob_skill, opponents, allies)
		return
	var effect_type: SkillEffect.Type
	match caster.unit_class:
		UnitBase.UnitClass.STAT_STEALER:
			effect_type = SkillEffect.Type.CHI_BURST
			_grant_shield(caster, int(float(caster.max_hp) * 0.25))

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
		UnitBase.UnitClass.SHAUNA:
			effect_type = SkillEffect.Type.OVERDRIVE
			_shauna_kite(caster, opponents)
		UnitBase.UnitClass.NEMI:
			effect_type = SkillEffect.Type.TIDE_WAVE
			_nemi_tide(caster, opponents, allies)
		UnitBase.UnitClass.SHEILDOR:
			effect_type = SkillEffect.Type.HOLY_LIGHT
			_sheildor_shield_ally(caster, allies)
		UnitBase.UnitClass.LORDEE:
			effect_type = SkillEffect.Type.WHIRLWIND
			_lordee_ground_slam(caster, opponents)
		UnitBase.UnitClass.NECRO:
			effect_type = SkillEffect.Type.ABSORBED
			_necro_raise_zombie(caster)
		# ── Roster expansion ───────────────────────────────────────────────────
		UnitBase.UnitClass.DOC:
			effect_type = SkillEffect.Type.HOLY_LIGHT
			_doc_inject(caster, allies)
		UnitBase.UnitClass.RIOT:
			effect_type = SkillEffect.Type.WHIRLWIND
			_riot_shield_bash(caster, opponents)
		UnitBase.UnitClass.PASTOR:
			effect_type = SkillEffect.Type.HOLY_LIGHT
			_pastor_sermon(caster, allies)
		UnitBase.UnitClass.SABLE:
			effect_type = SkillEffect.Type.ARROW_RAIN
			_sable_bolt(caster, opponents)
		UnitBase.UnitClass.RUSH:
			effect_type = SkillEffect.Type.SHADOW_STRIKE
			_rush_blitz(caster, opponents)
		UnitBase.UnitClass.STITCH:
			effect_type = SkillEffect.Type.ABSORBED
			_stitch_link(caster, opponents)
		UnitBase.UnitClass.COAL:
			effect_type = SkillEffect.Type.BURN
			_coal_stoke(caster)
		UnitBase.UnitClass.JUNE:
			effect_type = SkillEffect.Type.NATURE
			_june_root(caster, opponents)
		UnitBase.UnitClass.CROSS:
			effect_type = SkillEffect.Type.HOLY_LIGHT
			_cross_absolution(caster, allies)
		UnitBase.UnitClass.SEAR:
			effect_type = SkillEffect.Type.BURN
			_sear_ignite(caster, opponents)
		UnitBase.UnitClass.EMBER:
			effect_type = SkillEffect.Type.BURN
			_ember_cinder(caster, opponents)
		UnitBase.UnitClass.RIFT:
			effect_type = SkillEffect.Type.SHADOW_STRIKE
			_rift_tear(caster, opponents)
		UnitBase.UnitClass.ZOLT:
			effect_type = SkillEffect.Type.LIGHTNING
			_zolt_summon_storm(caster)
		UnitBase.UnitClass.LUMEN:
			effect_type = SkillEffect.Type.CHAOS_BOLT
			_lumen_refract(caster, opponents)
		UnitBase.UnitClass.STATIC:
			effect_type = SkillEffect.Type.LIGHTNING
			_static_tripwire(caster, opponents)
		UnitBase.UnitClass.REED:
			effect_type = SkillEffect.Type.HOLY_LIGHT
			_reed_cleanse(caster, allies)
		UnitBase.UnitClass.VAIL:
			effect_type = SkillEffect.Type.HOLY_LIGHT
			_vail_updraft(caster, allies)
		UnitBase.UnitClass.SPORE:
			effect_type = SkillEffect.Type.NATURE
			_spore_bloom(caster, opponents)
		UnitBase.UnitClass.ZOMBIE, UnitBase.UnitClass.BAT:
			effect_type = SkillEffect.Type.SHADOW_STRIKE
			_summon_basic_attack(caster, opponents)
		# Enemy special skills re-use existing implementations
		_:
			return
	# Bouncer spawns its own sprite-based effect (see _bouncer_slam) — skip the generic one.
	if caster.unit_class != UnitBase.UnitClass.BOUNCER:
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
	target.stun_time = 1.5
	caster.damage_dealt += dmg
	_spawn_sprite_sheet_effect(
		"res://assets/using/effects_projectiles/bouncer_active.png",
		target.global_position, 64, 60, 12, Vector2(140, 140))

func _nemi_tidal_wave(caster: UnitBase, opponents: Array) -> void:
	var dmg := int(caster.magic_power * caster.ultimate_damage_mult * UnitFactory.natural_aspect(caster))
	var cx := caster.grid_position.x
	_spawn_skill_effect_sized(SkillEffect.Type.TIDAL_WAVE, caster.global_position, 100.0)

	# Hit all enemies in a 3-column strip (caster col ±1)
	for opp in opponents:
		if not (opp and is_instance_valid(opp)):
			continue
		if abs(opp.grid_position.x - cx) <= 1:
			opp.take_damage(dmg, caster.current_element)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.ABSORBED, opp.global_position, 24.0)
			# Pushback: move 2 cells away from Nemi (in y direction)
			var push_y: int = sign(opp.grid_position.y - caster.grid_position.y)
			if push_y == 0: push_y = -1  # if same row, push north
			for _step in range(2):
				var next: Vector2i = opp.grid_position + Vector2i(0, push_y)
				if battle_grid.is_valid_position(next) and not battle_grid.is_cell_occupied(next):
					battle_grid.remove_unit(opp.grid_position)
					if battle_grid.place_unit(opp, next):
						opp.grid_position = next
						opp.position = _world_pos_for(opp, next)

func _headhunter_rapid_fire(caster: UnitBase) -> void:
	caster.rapid_fire_time = 4.0

# ── Shauna active: kite away from nearest enemy, boost next attack ────────────
func _shauna_kite(caster: UnitBase, opponents: Array) -> void:
	var nearest := find_nearest_enemy(caster, opponents)
	if nearest:
		var dx: int = sign(caster.grid_position.x - nearest.grid_position.x)
		var dy: int = sign(caster.grid_position.y - nearest.grid_position.y)
		if dx == 0 and dy == 0:
			dy = 1  # fallback: move south if same cell
		var dest := caster.grid_position + Vector2i(dx, dy)
		if battle_grid.is_valid_position(dest) and not battle_grid.is_cell_occupied(dest):
			start_unit_movement(caster, caster.grid_position, dest)
	caster.next_attack_boosted = true   # next auto hits for +50%

# ── Nemi active: Tide — a chain that bounces between the two teams ─────────────
# Rules:
#   • Cast on the nearest enemy (damage). Then bounce to a unit within TIDE_RANGE
#     of the LAST unit hit, on the OPPOSITE team from the last hit.
#   • Must alternate enemy → ally → enemy → …  (never the same team twice in a row).
#   • Hitting an enemy damages it; hitting an ally heals it.
#   • On an ally bounce, prefer Nemi (the caster) if she is in range.
#   • If the next required team has no valid target in range, the chain ends —
#     it will NOT bounce to the wrong team just because someone is nearby.
#   • A unit is never hit twice (guarantees the chain terminates).
const TIDE_RANGE := 2.0
const TIDE_MAX_BOUNCES := 8

# ── Basic-monster signature moves (2026-07-03) ────────────────────────────────
# Basic mobs piggyback hero UnitClass values for stats/sprites, so their skills
# can't dispatch on unit_class without polluting hero arms. Instead the enemy
# factory sets `mob_skill` meta + the normal skill_name/cd fields, and _use_skill
# routes here FIRST. One readable signature move per mob; each has a name so it
# can get an ability icon later (planned asset pass — always leave an icon slot).
func _use_mob_skill(caster: UnitBase, key: String, opponents: Array, _allies: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	match key:
		"goblin_shank":
			# Quick lunge for bonus damage — goblins get scarier in numbers.
			if not tar: return
			var dmg: int = int(float(caster.attack_damage) * caster.skill_damage_multiplier)
			tar.take_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.SHADOW_STRIKE, tar.global_position, 22.0)
		"archer_cripple":
			# Crippling Arrow: modest damage + slow.
			if not tar: return
			var adm: int = int(float(caster.attack_damage) * caster.skill_damage_multiplier)
			tar.take_damage(adm, caster.current_element, caster)
			caster.damage_dealt += adm
			apply_slow(tar, 0.30, 2.0)
			_spawn_skill_effect_sized(SkillEffect.Type.ARROW_RAIN, tar.global_position, 24.0)
		"shaman_mend":
			# Mend: heal the most-wounded ally (the reason to focus shamans first).
			var heal_tar := _lowest_hp_ally(caster, _allies, 6.0, true)
			if not heal_tar: return
			var amt: int = int(float(caster.magic_power) * 1.5)
			heal_tar.heal(amt)
			caster.combat_healing_done += amt
			_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, heal_tar.global_position, 26.0)
		"brute_crush":
			# Crushing Blow: big hit + short stun. Long cooldown — telegraphed bully.
			if not tar: return
			var bdm: int = int(float(caster.attack_damage) * caster.skill_damage_multiplier)
			tar.take_damage(bdm, caster.current_element, caster)
			caster.damage_dealt += bdm
			tar.stun_time = maxf(tar.stun_time, 1.0)
			_spawn_skill_effect_sized(SkillEffect.Type.WHIRLWIND, tar.global_position, 30.0)
		"slime_goo":
			# Corrosive Goo: weaken the target's outgoing damage.
			if not tar: return
			tar.weakened_pct = maxf(tar.weakened_pct, 0.25)
			tar.weakened_time = maxf(tar.weakened_time, 3.0)
			_spawn_skill_effect_sized(SkillEffect.Type.ABSORBED, tar.global_position, 24.0)
		"skeleton_boneshield":
			# Bone Shield: rattle up a shield — skeletons hold the line.
			var sh: int = int(float(caster.max_hp) * 0.25)
			caster.current_shield += sh
			if caster.health_bar:
				caster.health_bar.update_shield(caster.current_shield, caster.max_hp)
			_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, caster.global_position, 24.0)
		"rat_bite":
			# Infected Bite: small hit + disease DoT (burn plumbing, flavored).
			if not tar: return
			var rdm: int = int(float(caster.attack_damage) * caster.skill_damage_multiplier)
			tar.take_damage(rdm, caster.current_element, caster)
			caster.damage_dealt += rdm
			apply_burn(tar, float(caster.attack_damage) * 0.35, 3.0, caster)
			_spawn_skill_effect_sized(SkillEffect.Type.BURN, tar.global_position, 20.0)

func _nemi_tide(caster: UnitBase, opponents: Array, allies: Array) -> void:
	var first := find_nearest_enemy(caster, opponents)
	if not first:
		return

	var dmg := int(caster.magic_power * caster.skill_damage_multiplier * UnitFactory.natural_aspect(caster))
	var heal_amt := dmg

	var visited: Dictionary = {}
	var current: UnitBase = first
	var current_is_enemy := true   # the first hit is always an enemy

	for _bounce in range(TIDE_MAX_BOUNCES):
		if not (current and is_instance_valid(current)):
			break
		visited[current] = true

		# Apply the effect for whichever team `current` belongs to.
		if current_is_enemy:
			current.take_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.TIDE_WAVE, current.global_position, 32.0)
		else:
			current.heal(heal_amt)
			_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, current.global_position, 32.0)

		# Pick the next bounce on the OPPOSITE team, within range of `current`.
		var want_enemy := not current_is_enemy
		var pool: Array = opponents if want_enemy else allies
		var next := _tide_next_target(current, pool, want_enemy, caster, visited)
		if not next:
			break
		current = next
		current_is_enemy = want_enemy

# Nearest unvisited unit in `pool` within TIDE_RANGE of `from`. When looking for an
# ally bounce, Nemi (the caster) is preferred over any other ally in range.
func _tide_next_target(from: UnitBase, pool: Array, want_enemy: bool,
		caster: UnitBase, visited: Dictionary) -> UnitBase:
	# Ally bounce: prioritise Nemi if she is a valid, in-range, unvisited target.
	if not want_enemy and is_instance_valid(caster) and not visited.has(caster):
		if from.grid_position.distance_to(caster.grid_position) <= TIDE_RANGE:
			return caster

	var best: UnitBase = null
	var best_d := INF
	for u in pool:
		if not (u and is_instance_valid(u)) or visited.has(u):
			continue
		var d := from.grid_position.distance_to(u.grid_position)
		if d <= TIDE_RANGE and d < best_d:
			best_d = d; best = u
	return best

func _spawn_skill_effect(type: SkillEffect.Type, world_pos: Vector2) -> void:
	_spawn_skill_effect_sized(type, world_pos, 56.0)

func _spawn_skill_effect_sized(type: SkillEffect.Type, world_pos: Vector2, r: float) -> void:
	if not skill_effect_container:
		return
	var fx := SkillEffect.new()
	skill_effect_container.add_child(fx)
	fx.setup(type, world_pos, r)

# Sprite-sheet skill effect (used for heroes with dedicated frame-by-frame art,
# e.g. Bouncer's active/ultimate). `size` is the max on-screen bounding box in
# pixels (aspect ratio of the source frame is preserved).
func _spawn_sprite_sheet_effect(texture_path: String, world_pos: Vector2,
		frame_width: int, frame_height: int, frame_count: int, size: Vector2,
		fps: float = 18.0) -> void:
	if not skill_effect_container:
		return
	var tex: Texture2D = load(texture_path) as Texture2D
	if not tex:
		return
	var fx := TexturedSkillEffect.new()
	skill_effect_container.add_child(fx)
	fx.setup(tex, world_pos, frame_width, frame_height, frame_count, size, fps)

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

# ── New hero helpers ──────────────────────────────────────────────────────────

func _grant_shield(unit: UnitBase, amount: int) -> void:
	unit.current_shield += amount
	unit.shield_changed.emit(unit.current_shield)

# Stat Stealer ultimate: picks one random stat off the target and starts a
# 10-second drain (10% of the cast-time value per second — see _tick_statuses
# for the actual tick). Devastating if it lands on a carry's attack_damage;
# harmless if it lands on a tank's magic_power — the randomness is the point.
const STAT_STEAL_POOL: Array[String] = [
	"attack_damage", "crit_chance", "crit_damage", "attack_speed", "magic_power", "resistance",
]
func _stat_steal_drain(caster: UnitBase, opponents: Array) -> void:
	var target: UnitBase = caster.target_unit if (caster.target_unit and is_instance_valid(caster.target_unit)) else find_nearest_enemy(caster, opponents)
	if not target:
		return
	var stat: String = STAT_STEAL_POOL[randi() % STAT_STEAL_POOL.size()]
	var snapshot: float = float(target.get(stat))
	target.drain_time = 10.0
	target.drain_stat = stat
	target.drain_per_sec = snapshot * 0.10
	target.drain_source = caster
	target.drain_stolen = 0.0
	_spawn_skill_effect(SkillEffect.Type.CHAOS_BOLT, target.global_position)

# Called from VisualUnit.die() when a Stat Stealer actually dies (real death
# only — not a Triarch-style phase-transform or a relic revive). Returns every
# stat it currently has stolen to whichever player unit it stole from — "you
# only get it back when you kill him."
func restore_stat_theft(dying_stealer: UnitBase) -> void:
	for u in player_units:
		if not (u and is_instance_valid(u)):
			continue
		if u.drain_source == dying_stealer:
			if u.drain_stolen > 0.0 and u.drain_stat != "":
				u.set(u.drain_stat, float(u.get(u.drain_stat)) + u.drain_stolen)
			u.drain_time = 0.0
			u.drain_stat = ""
			u.drain_per_sec = 0.0
			u.drain_stolen = 0.0
			u.drain_source = null

# ── Khagan: mind-control finale ────────────────────────────────────────────────
# Called from EnemyFactory.advance_khagan_phase() as Khagan's phase-2 body
# "dies". Picks the player's highest attack_damage hero (turns your best carry
# against you) and moves it from player_units into enemy_units for the rest of
# the fight — no stat buff, its own full kit turned against its former allies
# is the threat. Requires >=2 living heroes so possessing your last one can't
# leave the player instantly defeated; if that safety fails, Khagan just dies
# with no phase 3 this time.
func start_khagan_possession(khagan: UnitBase) -> void:
	var candidates: Array = player_units.filter(func(u): return u and is_instance_valid(u))
	if candidates.size() < 2:
		return
	var chosen: UnitBase = candidates[0]
	for u in candidates:
		if u.attack_damage > chosen.attack_damage:
			chosen = u
	player_units.erase(chosen)
	enemy_units.append(chosen)
	chosen.is_player_unit = false
	chosen.set_meta("khagan_puppet", true)
	action_logged.emit("Khagan's spirit seizes control of %s!" % chosen.unit_name, false)
	_spawn_skill_effect_sized(SkillEffect.Type.SHADOW_STRIKE, chosen.global_position, 56.0)

# Called from UnitBase/VisualUnit.die() the instant the possessed hero's HP
# would hit 0 — breaks the control, returns it to the player's side, and ends
# the fight in victory (defeating the puppet IS defeating Khagan; nothing else
# on the field needs to die too). Deferred so the current per-unit tick loop
# finishes cleanly before the battle-end signal cascade runs.
func end_khagan_possession(unit: UnitBase) -> void:
	if not unit.has_meta("khagan_puppet"):
		return
	unit.remove_meta("khagan_puppet")
	enemy_units.erase(unit)
	if unit not in player_units:
		player_units.append(unit)
	unit.is_player_unit = true
	unit.current_hp = maxi(unit.current_hp, int(unit.max_hp * 0.15))
	action_logged.emit("%s breaks free of Khagan's control!" % unit.unit_name, true)
	call_deferred("end_battle", true)

# Sheildor skill: shield + small heal to the most-damaged nearby ally (or self)
func _sheildor_shield_ally(caster: UnitBase, allies: Array) -> void:
	var best_target: UnitBase = caster
	var lowest_hp_pct: float = float(caster.current_hp) / float(max(caster.max_hp, 1))
	for ally in allies:
		if not (ally and is_instance_valid(ally)) or ally == caster:
			continue
		if caster.grid_position.distance_to(ally.grid_position) > float(caster.skill_range):
			continue
		var pct: float = float(ally.current_hp) / float(max(ally.max_hp, 1))
		if pct < lowest_hp_pct:
			lowest_hp_pct = pct
			best_target = ally
	var shield_amt: int = int(float(caster.magic_power) * 8.0 + float(best_target.max_hp) * 0.06)
	_grant_shield(best_target, shield_amt)
	best_target.heal(int(float(best_target.max_hp) * 0.05))
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, best_target.global_position, 44.0)
	action_logged.emit("%s shields %s!" % [caster.unit_name, best_target.unit_name], caster.is_player_unit)

# Sheildor ultimate: Guardian Leap — teleport to lowest-HP ally, grant big shield to both
func _sheildor_guardian_leap(caster: UnitBase, allies: Array, opponents: Array) -> void:
	var target: UnitBase = null
	var lowest: float = INF
	for ally in allies:
		if not (ally and is_instance_valid(ally)) or ally == caster:
			continue
		var pct: float = float(ally.current_hp) / float(max(ally.max_hp, 1))
		if pct < lowest:
			lowest = pct; target = ally
	if not target:
		return
	# Teleport to open cell adjacent to target
	var dest := _nearest_open_adjacent(target.grid_position)
	if dest != Vector2i(-1, -1):
		battle_grid.remove_unit(caster.grid_position)
		if battle_grid.place_unit(caster, dest):
			caster.grid_position = dest
			caster.position = _world_pos_for(caster, dest)
	# Massive shield for both
	var big_shield: int = int(float(caster.magic_power) * 15.0 + float(target.max_hp) * 0.20)
	_grant_shield(target, big_shield)
	_grant_shield(caster, big_shield / 2)
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, target.global_position, 64.0)
	_spawn_skill_effect_sized(SkillEffect.Type.ABSORBED, caster.global_position, 48.0)
	action_logged.emit("%s leaps to protect %s!" % [caster.unit_name, target.unit_name], caster.is_player_unit)

# Lordee skill: Ground Slam — AoE around nearest enemy, 4-hex radius
func _lordee_ground_slam(caster: UnitBase, opponents: Array) -> void:
	var center := find_nearest_enemy(caster, opponents)
	if not center:
		return
	var dmg := int(caster.attack_damage * caster.skill_damage_multiplier)
	_spawn_skill_effect_sized(SkillEffect.Type.WHIRLWIND, center.global_position, 80.0)
	for opp in opponents:
		if not (opp and is_instance_valid(opp)):
			continue
		if center.grid_position.distance_to(opp.grid_position) <= 2.0:
			opp.take_damage(dmg, caster.current_element)
			caster.damage_dealt += dmg

# Lordee ultimate: Parasite Lunge — blink to target, steal ATK, set chase
func _lordee_parasite_lunge(caster: UnitBase, opponents: Array) -> void:
	# Filter to targets not yet permanently stolen from
	var stolen_set: Array = caster.get_meta("lordee_stolen_set", []) as Array
	var pool := opponents.filter(func(u: UnitBase) -> bool:
		return u != null and is_instance_valid(u) and not (u in stolen_set))
	if pool.is_empty():
		pool = opponents.filter(func(u: UnitBase) -> bool: return u != null and is_instance_valid(u))
	if pool.is_empty():
		return
	pool.sort_custom(func(a: UnitBase, b: UnitBase) -> bool:
		return caster.grid_position.distance_to(a.grid_position) < caster.grid_position.distance_to(b.grid_position))
	var target: UnitBase = pool[0]
	# Blink to adjacent open cell
	var dest := _nearest_open_adjacent(target.grid_position)
	if dest != Vector2i(-1, -1):
		battle_grid.remove_unit(caster.grid_position)
		if battle_grid.place_unit(caster, dest):
			caster.grid_position = dest
			caster.position = _world_pos_for(caster, dest)
	# Damage + steal 7% of target's attack_damage
	var dmg: int = int(float(caster.attack_damage) * 1.5)
	target.take_damage(dmg, caster.current_element)
	caster.damage_dealt += dmg
	var stolen_atk: int = int(float(target.attack_damage) * 0.07)
	caster.attack_damage += stolen_atk
	stolen_set.append(target)
	caster.set_meta("lordee_stolen_set", stolen_set)
	# Chase this target for 20s — if they die, perm bonus sticks
	caster.lordee_chase_target = target
	caster.lordee_chase_timer = 20.0
	_spawn_skill_effect_sized(SkillEffect.Type.SHADOW_STRIKE, target.global_position, 40.0)
	action_logged.emit("%s leeches from %s! (+%d ATK)" % [caster.unit_name, target.unit_name, stolen_atk], caster.is_player_unit)

# Necro skill: Raise Zombie — summon a zombie in front of Necro
func _necro_raise_zombie(caster: UnitBase) -> void:
	_spawn_summon(caster, UnitBase.UnitClass.ZOMBIE)

# Necro ultimate: Bat Swarm — summon 3 bats around Necro, deal AoE dark damage
func _necro_bat_swarm(caster: UnitBase, opponents: Array) -> void:
	var dmg := int(float(caster.magic_power) * caster.ultimate_damage_mult)
	_spawn_skill_effect_sized(SkillEffect.Type.INFERNO, caster.global_position, 72.0)
	for opp in opponents:
		if not (opp and is_instance_valid(opp)):
			continue
		if caster.grid_position.distance_to(opp.grid_position) <= float(caster.ultimate_range):
			opp.take_damage(dmg, caster.current_element)
			caster.damage_dealt += dmg
	for _i in range(3):
		_spawn_summon(caster, UnitBase.UnitClass.BAT)

# Zombie/Bat basic claw — extra attack on nearest enemy
func _summon_basic_attack(caster: UnitBase, opponents: Array) -> void:
	var target := find_nearest_enemy(caster, opponents)
	if not target:
		return
	var dmg := int(float(caster.attack_damage) * caster.skill_damage_multiplier)
	target.take_damage(dmg, caster.current_element)
	caster.damage_dealt += dmg

# Spawn a summoned unit in front of the summoner
func _spawn_summon(summoner: UnitBase, summon_class: UnitBase.UnitClass) -> void:
	# Find an open cell close to summoner (towards enemies)
	var forward_y: int = -1 if summoner.is_player_unit else 1
	var search_offsets: Array[Vector2i] = [
		Vector2i(0, forward_y), Vector2i(1, forward_y), Vector2i(-1, forward_y),
		Vector2i(0, forward_y * 2), Vector2i(1, 0), Vector2i(-1, 0)
	]
	var spawn_cell := Vector2i(-1, -1)
	for offset in search_offsets:
		var candidate: Vector2i = summoner.grid_position + offset
		if battle_grid.is_valid_position(candidate) and not battle_grid.is_cell_occupied(candidate):
			spawn_cell = candidate
			break
	if spawn_cell == Vector2i(-1, -1):
		return  # no room
	var summon: VisualUnit = UnitFactory.create_unit(summon_class, summoner.current_element, summoner.is_player_unit)
	summon.is_summoned = true
	summon.summon_owner = summoner
	summon.is_player_unit = summoner.is_player_unit
	summon.grid_position = spawn_cell
	if battle_grid.place_unit(summon, spawn_cell):
		if summon.is_player_unit:
			player_units.append(summon)
		else:
			enemy_units.append(summon)
		unit_summoned.emit(summon)  # main_game.gd adds to scene tree here (signal is synchronous)
		summon.position = battle_grid.grid_to_world(spawn_cell)
		action_logged.emit("%s raises a %s!" % [summoner.unit_name, summon.get_class_name_string()], summoner.is_player_unit)

# ── Ant Hill: periodic spawn (DPS check) ──────────────────────────────────────
const ANT_HILL_SPAWN_INTERVAL := 4.5
const ANT_HILL_MAX_ANTS := 20

func _ant_hill_spawn_tick(hill: UnitBase, allies: Array, dt: float) -> void:
	hill.summon_spawn_timer -= dt
	if hill.summon_spawn_timer > 0.0:
		return
	hill.summon_spawn_timer = ANT_HILL_SPAWN_INTERVAL
	var alive_ants := 0
	for a in allies:
		if a and is_instance_valid(a) and a.summon_owner == hill and a.is_summoned:
			alive_ants += 1
	if alive_ants >= ANT_HILL_MAX_ANTS:
		return   # swarm is already at its cap — try again next interval
	_spawn_ant(hill)

# Like _spawn_summon, but for the Ant Hill specifically: uses the real ant.png
# art (via sprite_folder meta) instead of the generic Zombie/Bat shape-fallback,
# and searches a wider ring since the hill is 2×2 (no single "in front" cell).
func _spawn_ant(hill: UnitBase) -> void:
	var search_offsets: Array[Vector2i] = [
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(-1, 2), Vector2i(2, 0), Vector2i(2, 1),
		Vector2i(-2, 0), Vector2i(-2, 1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	var spawn_cell := Vector2i(-1, -1)
	for offset in search_offsets:
		var candidate: Vector2i = hill.grid_position + offset
		if battle_grid.is_valid_position(candidate) and not battle_grid.is_cell_occupied(candidate):
			spawn_cell = candidate
			break
	if spawn_cell == Vector2i(-1, -1):
		return  # no room this tick — try again next interval
	var ant: VisualUnit = UnitFactory.create_unit(UnitBase.UnitClass.ANT, hill.current_element, hill.is_player_unit)
	ant.is_summoned = true
	ant.summon_owner = hill
	ant.is_player_unit = hill.is_player_unit
	ant.set_meta("sprite_folder", "ant")
	ant.grid_position = spawn_cell
	if battle_grid.place_unit(ant, spawn_cell):
		if ant.is_player_unit:
			player_units.append(ant)
		else:
			enemy_units.append(ant)
		unit_summoned.emit(ant)
		ant.position = battle_grid.grid_to_world(spawn_cell)
		action_logged.emit("The Ant Hill spawns another ant!", hill.is_player_unit)
	else:
		ant.queue_free()

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
	_clear_board_effects()
	afterimage_actor = null
	afterimage_time = 0.0
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
			# PERF (2026-07-04): these [Path] prints fired EVERY FRAME for every
			# blocked/boxed-in unit on a crowded board — console I/O + string
			# formatting was a real chunk of the 15+ unit frame time. Debug-only.
			if PATH_DEBUG: print("[Path] NO PATH from %s to %s" % [current_pos, target_pos])
			return
		if new_path.size() > 0 and new_path[0] == current_pos:
			new_path.remove_at(0)
		unit_paths[unit] = new_path
		if PATH_DEBUG: print("[Path] found len=%d first=%s" % [new_path.size(), new_path[0] if new_path.size() > 0 else "EMPTY"])

	var path = unit_paths[unit]
	if path.is_empty():
		if PATH_DEBUG: print("[Path] path empty after cache")
		return

	var next_pos = path[0]
	var occupied = battle_grid.is_cell_occupied(next_pos)
	if not battle_grid.is_valid_position(next_pos) or occupied:
		# Local collision avoidance (2026-07-04 user report — Ant Hill swarm
		# units "got stuck" and zig-zagged): previously a blocked next step
		# just dropped the whole cached path and did nothing this tick, then
		# replanned a fresh (often very different) full A* route next tick.
		# In a dense crowd that thrashes every frame — freeze, replan, freeze,
		# replan, each recompute finding a different detour around whichever
		# neighbors currently happen to be occupied. Try a one-cell sidestep
		# first: any free neighbor that's at least as close to the real target
		# as staying put. Real forward progress instead of a frame of nothing,
		# and far fewer full recomputes since the unit isn't perpetually stuck.
		var sidestep := _find_sidestep(current_pos, target_pos)
		if sidestep != Vector2i(-1, -1):
			unit_paths.erase(unit)   # cached route no longer matches from here — replan clean next tick
			if not unit.is_moving:
				start_unit_movement(unit, current_pos, sidestep)
			return
		if PATH_DEBUG: print("[Path] next_pos %s blocked (occupied=%s)" % [next_pos, occupied])
		unit_paths.erase(unit)
		return

	if not unit.is_moving:
		start_unit_movement(unit, current_pos, next_pos)

# Picks the free neighbor of `current_pos` that gets closest to `target_pos`
# (Chebyshev distance), but only if it's an actual improvement over staying
# put — returns Vector2i(-1,-1) if every free neighbor is equal or farther
# (better to wait one tick than wander away from the goal).
func _find_sidestep(current_pos: Vector2i, target_pos: Vector2i) -> Vector2i:
	var best_dist: int = _grid_dist(current_pos, target_pos)
	var best: Vector2i = Vector2i(-1, -1)
	for neighbor in Pathfinding.get_neighbors(current_pos, battle_grid):
		if battle_grid.is_cell_occupied(neighbor):
			continue
		var d: int = _grid_dist(neighbor, target_pos)
		if d < best_dist:
			best_dist = d
			best = neighbor
	return best

func _move_2x2_unit(unit: UnitBase, target_pos: Vector2i) -> void:
	# Simple cardinal + diagonal movement for large units.
	# Picks the direction that gets closest to target and checks all 4 cells.
	var pos := unit.grid_position
	var dx: int = sign(target_pos.x - pos.x)
	var dy: int = sign(target_pos.y - pos.y)

	# Build candidate next positions in preference order
	var candidates: Array[Vector2i] = []
	if dx != 0 and dy != 0:
		candidates = [pos + Vector2i(dx, dy), pos + Vector2i(dx, 0), pos + Vector2i(0, dy)]
	elif dx != 0:
		candidates = [pos + Vector2i(dx, 0), pos + Vector2i(0, 1), pos + Vector2i(0, -1)]
	else:
		candidates = [pos + Vector2i(0, dy), pos + Vector2i(1, 0), pos + Vector2i(-1, 0)]

	for next_pos in candidates:
		if _can_place_2x2(next_pos, unit):
			start_unit_movement(unit, pos, next_pos)
			return

func _can_place_2x2(origin: Vector2i, exclude_unit: UnitBase) -> bool:
	for dy in range(2):
		for dx in range(2):
			var p := origin + Vector2i(dx, dy)
			if not battle_grid.is_valid_position(p):
				return false
			if battle_grid.is_cell_occupied(p) and battle_grid.get_unit_at(p) != exclude_unit:
				return false
	return true

func add_projectile(projectile: Projectile) -> void:
	if projectile_container:
		projectile_container.add_child(projectile)

# World position for a unit anchored at grid_pos. 2×2 units are centred on the
# middle of their 2×2 block (half-cell offset) so they don't snap to a single cell.
func _world_pos_for(unit: UnitBase, grid_pos: Vector2i) -> Vector2:
	var w: Vector2 = battle_grid.grid_to_world(grid_pos)
	if unit.cell_size == 2:
		w += Vector2(battle_grid.cell_size * 0.5, battle_grid.cell_size * 0.5)
	return w

func start_unit_movement(unit: UnitBase, from_pos: Vector2i, to_pos: Vector2i) -> void:
	unit.is_moving = true
	unit.move_start_pos = _world_pos_for(unit, from_pos)
	unit.move_target_pos = _world_pos_for(unit, to_pos)
	unit.move_progress = 0.0
	unit.target_grid_pos = to_pos

	battle_grid.remove_unit(from_pos)
	battle_grid.place_unit(unit, to_pos)
	unit.grid_position = to_pos

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
	var speed_multiplier = unit.movement_speed * base_movement_speed * unit.speed_modifier()
	unit.move_progress += delta * speed_multiplier

	if unit.move_progress >= 1.0:
		# Movement complete
		unit.position = unit.move_target_pos
		unit.is_moving = false
		unit.move_progress = 0.0
		_on_unit_finished_step(unit)

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


# ══════════════════════════════════════════════════════════════════════════════
# ROSTER EXPANSION — status pipeline, reactive hooks, and per-hero ability bodies
# ══════════════════════════════════════════════════════════════════════════════

# ── Per-unit status decay (burn, slow, root, taunt, buffs, spore burst, …) ────
func _tick_statuses(unit: UnitBase, dt: float) -> void:
	# Burn damage-over-time.
	if unit.burn_time > 0.0:
		unit.burn_time -= dt
		unit.burn_accum += unit.burn_dps * dt
		if unit.burn_accum >= 1.0:
			var whole: int = int(unit.burn_accum)
			unit.burn_accum -= float(whole)
			var bsrc = unit.burn_source
			unit.take_damage(whole, UnitBase.Element.FIRE, bsrc, true)
			if bsrc and is_instance_valid(bsrc):
				bsrc.damage_dealt += whole
		if unit.burn_time <= 0.0:
			unit.burn_dps = 0.0
			unit.burn_accum = 0.0
	if not is_instance_valid(unit):
		return

	# Stat Stealer drain-over-time: 10%/sec of the cast-time snapshot, transferred
	# live onto drain_source's matching stat. Once drain_time runs out the theft
	# is NOT reverted here — it stays stolen until drain_source dies (see
	# restore_stat_theft), or forever if it's never killed this fight.
	if unit.drain_time > 0.0:
		unit.drain_time -= dt
		var stat: String = unit.drain_stat
		if stat != "":
			# crit_damage is a multiplier (2.0 = double dmg) — its natural "no
			# bonus" floor is 1.0, not 0. attack_speed floors just above zero to
			# avoid a divide-by-zero elsewhere (1.0 / attacks_per_second).
			var floor_val: float = 1.0 if stat == "crit_damage" else (0.05 if stat == "attack_speed" else 0.0)
			# attack_speed/crit_chance/crit_damage are float fields, so fractional
			# amounts apply directly. attack_damage/magic_power/resistance are
			# INT fields — repeatedly setting a truncating int property would
			# silently discard the sub-1 remainder every single tick, so those
			# bank the fraction in drain_accum first (mirrors burn_accum above).
			var is_float_stat: bool = stat in ["attack_speed", "crit_chance", "crit_damage"]
			var cur: float = float(unit.get(stat))
			var raw: float = unit.drain_per_sec * dt
			if is_float_stat:
				var amount: float = minf(raw, maxf(0.0, cur - floor_val))
				if amount > 0.0:
					unit.set(stat, cur - amount)
					unit.drain_stolen += amount
					var src = unit.drain_source
					if src and is_instance_valid(src):
						src.set(stat, float(src.get(stat)) + amount)
			else:
				unit.drain_accum += raw
				if unit.drain_accum >= 1.0:
					var whole: int = int(unit.drain_accum)
					var actual: int = mini(whole, maxi(0, int(cur) - int(floor_val)))
					unit.drain_accum -= float(whole)
					if actual > 0:
						unit.set(stat, int(cur) - actual)
						unit.drain_stolen += float(actual)
						var src2 = unit.drain_source
						if src2 and is_instance_valid(src2):
							src2.set(stat, int(src2.get(stat)) + actual)

	# Spore stacks burst at 10.
	if unit.spore_stacks >= 10.0:
		unit.spore_stacks = 0.0
		var burst: int = int(unit.get_meta("spore_burst", 40))
		var ssrc = unit.get_meta("spore_source", null)
		_spawn_skill_effect_sized(SkillEffect.Type.NATURE, unit.global_position, 40.0)
		unit.take_damage(burst, UnitBase.Element.EARTH, ssrc, true)
		if ssrc and is_instance_valid(ssrc):
			ssrc.damage_dealt += burst
	if not is_instance_valid(unit):
		return

	# Simple count-downs.
	if unit.slow_time > 0.0: unit.slow_time -= dt
	if unit.root_time > 0.0: unit.root_time -= dt
	if unit.taunt_time > 0.0:
		unit.taunt_time -= dt
		if unit.taunt_time <= 0.0: unit.taunt_source = null
	if unit.untargetable_time > 0.0: unit.untargetable_time -= dt
	if unit.bonus_aspd_time > 0.0:
		unit.bonus_aspd_time -= dt
		if unit.bonus_aspd_time <= 0.0: unit.bonus_aspd_pct = 0.0
	if unit.weakened_time > 0.0:
		unit.weakened_time -= dt
		if unit.weakened_time <= 0.0: unit.weakened_pct = 0.0
	if unit.outgoing_dmg_time > 0.0:
		unit.outgoing_dmg_time -= dt
		if unit.outgoing_dmg_time <= 0.0: unit.outgoing_dmg_mult = 1.0
	if unit.shock_cd > 0.0: unit.shock_cd -= dt
	if unit.puppet_time > 0.0: unit.puppet_time -= dt
	if unit.meltdown_time > 0.0:
		unit.meltdown_time -= dt
		if unit.meltdown_time <= 0.0:
			# Coal cools down: brief weakness after Meltdown.
			unit.weakened_pct = 0.4
			unit.weakened_time = 3.0
	if unit.link_partner != null and not is_instance_valid(unit.link_partner):
		unit.link_partner = null

	# Equipment Spell Echo: persistent outgoing damage bonus (never expires)
	var echo: float = unit.equipment_passives.get("Spell Echo", 0.0)
	if echo > 0.0:
		unit.outgoing_dmg_mult = maxf(unit.outgoing_dmg_mult, 1.0 + echo)
		unit.outgoing_dmg_time = 0.1  # keep refreshed so the normal expiry path never fires

# ── Status application helpers (refresh = take stronger value / longer time) ───
func apply_burn(target: UnitBase, dps: float, dur: float, source) -> void:
	if not (target and is_instance_valid(target)): return
	target.burn_dps = maxf(target.burn_dps, dps)
	target.burn_time = maxf(target.burn_time, dur)
	target.burn_source = source

func apply_slow(target: UnitBase, pct: float, dur: float) -> void:
	if not (target and is_instance_valid(target)): return
	target.slow_pct = maxf(target.slow_pct, pct)
	target.slow_time = maxf(target.slow_time, dur)

func _lowest_hp_ally(unit: UnitBase, allies: Array, rng: float, include_self: bool) -> UnitBase:
	var best: UnitBase = null
	var best_pct := INF
	for a in allies:
		if not (a and is_instance_valid(a)): continue
		if a == unit and not include_self: continue
		if unit.grid_position.distance_to(a.grid_position) > rng: continue
		var pct := float(a.current_hp) / float(maxi(a.max_hp, 1))
		if pct < best_pct:
			best_pct = pct; best = a
	return best

func _highest_hp_enemy(_unit: UnitBase, opponents: Array) -> UnitBase:
	var best: UnitBase = null
	var hi := -1
	for opp in opponents:
		if opp and is_instance_valid(opp) and opp.current_hp > hi:
			hi = opp.current_hp; best = opp
	return best

func _team_has_stitch(team: Array) -> bool:
	for u in team:
		if u and is_instance_valid(u) and u.unit_class == UnitBase.UnitClass.STITCH:
			return true
	return false

func _find_open_in_row(row: int) -> Vector2i:
	for x in range(battle_grid.grid_width):
		var c := Vector2i(x, row)
		if battle_grid.is_valid_position(c) and not battle_grid.is_cell_occupied(c):
			return c
	return Vector2i(-1, -1)

func _nearest_open_cell_to(center: Vector2i) -> Vector2i:
	if battle_grid.is_valid_position(center) and not battle_grid.is_cell_occupied(center):
		return center
	for r in range(1, maxi(battle_grid.grid_width, battle_grid.grid_height)):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := center + Vector2i(dx, dy)
				if battle_grid.is_valid_position(c) and not battle_grid.is_cell_occupied(c):
					return c
	return Vector2i(-1, -1)

func _explosion(caster: UnitBase, center_cell: Vector2i, dmg: int, opponents: Array, radius: float) -> void:
	_spawn_skill_effect_sized(SkillEffect.Type.INFERNO, battle_grid.grid_to_world(center_cell), 48.0)
	for opp in opponents:
		if opp and is_instance_valid(opp):
			if Vector2(center_cell).distance_to(Vector2(opp.grid_position)) <= radius:
				opp.take_damage(dmg, UnitBase.Element.FIRE, caster, true)
				if caster and is_instance_valid(caster):
					caster.damage_dealt += dmg

func _chain_lightning(caster: UnitBase, first: UnitBase, opponents: Array, radius: float, dmg: int) -> void:
	for opp in opponents:
		if opp and is_instance_valid(opp) and first.grid_position.distance_to(opp.grid_position) <= radius:
			opp.take_damage(dmg, UnitBase.Element.LIGHTNING, caster)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, opp.global_position, 22.0)

# ── Reactive: runs on the attacker's basic attack ─────────────────────────────
func _apply_on_hit_passives(attacker: UnitBase, target: UnitBase, opponents: Array) -> void:
	if not (attacker and is_instance_valid(attacker) and target and is_instance_valid(target)):
		return
	var aspect: float = UnitFactory.natural_aspect(attacker)
	match attacker.unit_class:
		UnitBase.UnitClass.ANT:
			# Bite lands (damage already dealt in UnitBase.attack, which read the
			# PRE-increment stack count) — now bump the stack for the NEXT bite.
			target.ant_bite_stacks = mini(target.ant_bite_stacks + 1, 20)
		UnitBase.UnitClass.COAL:
			var stacks: int = 2 if attacker.stoke_charges > 0 else 1
			if attacker.stoke_charges > 0: attacker.stoke_charges -= 1
			apply_burn(target, float(attacker.attack_damage) * 0.12 * float(stacks) * aspect, 3.0, attacker)
			if attacker.meltdown_time > 0.0:
				_explosion(attacker, target.grid_position, int(float(attacker.attack_damage) * 0.6 * aspect), opponents, 1.5)
		UnitBase.UnitClass.EMBER:
			apply_burn(target, float(attacker.attack_damage) * 0.12 * aspect, 3.0, attacker)
		UnitBase.UnitClass.SABLE:
			attacker.momentum_stacks = mini(attacker.momentum_stacks + 1, 12)
		UnitBase.UnitClass.ZOLT:
			var zc: int = int(attacker.get_meta("zolt_auto", 0)) + 1
			if zc >= 6:
				zc = 0
				_chain_lightning(attacker, target, opponents, 3.0, int(float(attacker.magic_power) * 0.6 * aspect))
			attacker.set_meta("zolt_auto", zc)
		UnitBase.UnitClass.LUMEN:
			var second := _second_nearest(attacker, target, opponents)
			if second:
				var d: int = int(float(attacker.attack_damage) * 0.5 * aspect)
				second.take_damage(d, attacker.current_element, attacker)
				attacker.damage_dealt += d
				_spawn_skill_effect_sized(SkillEffect.Type.CHAOS_BOLT, second.global_position, 20.0)

	# Equipment Lifesteal: heal for a fraction of melee damage dealt this swing
	var lifesteal: float = attacker.equipment_passives.get("Lifesteal", 0.0)
	if lifesteal > 0.0 and attacker.pending_attack_log_damage > 0 and attacker.current_hp < attacker.max_hp:
		var heal_amt: int = int(float(attacker.pending_attack_log_damage) * lifesteal)
		if heal_amt > 0:
			attacker.heal(heal_amt)
			_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, attacker.global_position, 16.0)

# ── Reactive: runs whenever ANY unit takes damage (called from UnitBase) ──────
func propagate_damage_links(victim: UnitBase, dmg: int, attacker) -> void:
	if _propagating:
		return
	if not (victim and is_instance_valid(victim)):
		return
	_propagating = true

	# Riot Crowd Control: slow whoever damaged him.
	if victim.unit_class == UnitBase.UnitClass.RIOT and attacker and is_instance_valid(attacker) and attacker != victim:
		apply_slow(attacker, 0.3, 1.5)

	# Cross Penance: heal a share of damage taken (counts toward Judgment).
	# Balance 2026-07-03: 0.35 → 0.20 — at 35% Cross out-sustained an entire
	# 11-unit wave solo in arena sweeps (3119 self-healing, 100% solo win rate,
	# highest damage in the roster). Still the tankiest sustain in the game at 20%.
	if victim.unit_class == UnitBase.UnitClass.CROSS:
		var ch: int = int(float(dmg) * 0.20)
		if ch > 0:
			victim.heal(ch)
			victim.combat_healing_done += ch

	# Rift Backlash: redirect 30% of damage to a random enemy.
	if victim.unit_class == UnitBase.UnitClass.RIFT:
		var rift_opps: Array = enemy_units if victim.is_player_unit else player_units
		var pool: Array = rift_opps.filter(func(u): return u != null and is_instance_valid(u))
		if not pool.is_empty():
			var pick: UnitBase = pool[randi() % pool.size()]
			var rdmg: int = int(float(dmg) * 0.30)
			if rdmg > 0:
				pick.take_damage(rdmg, UnitBase.Element.NORMAL, victim, true)
				victim.damage_dealt += rdmg

	# Stitch Link: bound partner shares the hit.
	if victim.link_partner != null and is_instance_valid(victim.link_partner):
		var share: int = int(float(dmg) * 0.5)
		if share > 0:
			victim.link_partner.take_damage(share, UnitBase.Element.NORMAL, attacker, true)

	# Stitch Loose Threads: if the victim's foes field a Stitch, bleed to its teammates.
	var team: Array = player_units if victim.is_player_unit else enemy_units
	var foes: Array = enemy_units if victim.is_player_unit else player_units
	if _team_has_stitch(foes):
		var bleed: int = int(float(dmg) * 0.08)
		if bleed > 0:
			for mate in team.duplicate():
				if mate and is_instance_valid(mate) and mate != victim:
					mate.take_damage(bleed, UnitBase.Element.NORMAL, null, true)

	# Equipment Thorns: reflect a fraction of incoming damage back to the attacker
	var thorns_eq: float = victim.equipment_passives.get("Thorns", 0.0)
	if thorns_eq > 0.0 and attacker and is_instance_valid(attacker) and attacker != victim:
		var reflect: int = int(float(dmg) * thorns_eq)
		if reflect > 0:
			attacker.take_damage(reflect, UnitBase.Element.NORMAL, null, true)

	_propagating = false

# ── Reactive: runs when a unit finishes a movement step ───────────────────────
func _on_unit_finished_step(unit: UnitBase) -> void:
	if not (unit and is_instance_valid(unit)):
		return
	var cell: Vector2i = unit.grid_position

	# Brand lays a burning trail on the tile it now stands on.
	if unit.unit_class == UnitBase.UnitClass.SEAR:
		fire_trail[cell] = {
			"dmg": float(unit.magic_power) * 0.5 * UnitFactory.natural_aspect(unit),
			"time": 5.0, "source": unit, "owner_is_player": unit.is_player_unit,
		}

	# Field hazards burn the mover if it belongs to the opposing side.
	if thorns_time > 0.0 and unit.is_player_unit != thorns_owner_is_player:
		unit.take_damage(thorns_dmg, UnitBase.Element.EARTH, null, true)
	if is_instance_valid(unit) and grid_field_time > 0.0 and unit.is_player_unit != grid_owner_is_player:
		unit.take_damage(grid_field_dmg, UnitBase.Element.LIGHTNING, null, true)
	if is_instance_valid(unit) and fire_trail.has(cell):
		var ft = fire_trail[cell]
		if unit.is_player_unit != ft["owner_is_player"]:
			apply_burn(unit, ft["dmg"], 2.0, ft["source"])

	# Static Live Wire: an enemy ending its step next to a Static gets shocked.
	if is_instance_valid(unit) and unit.shock_cd <= 0.0:
		var foes: Array = player_units if not unit.is_player_unit else enemy_units
		for s in foes:
			if s and is_instance_valid(s) and s.unit_class == UnitBase.UnitClass.STATIC:
				if s.grid_position.distance_to(unit.grid_position) <= 1.5:
					var sd: int = int(float(s.magic_power) * 0.5 * UnitFactory.natural_aspect(s))
					unit.take_damage(sd, UnitBase.Element.LIGHTNING, s, true)
					s.damage_dealt += sd
					apply_slow(unit, 0.3, 1.0)
					unit.shock_cd = 1.0
					_spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, unit.global_position, 26.0)
					break

# ── Snapshot fallen heroes so Doc can revive one ──────────────────────────────
func _on_ally_died(unit: UnitBase) -> void:
	if not (unit and is_instance_valid(unit)):
		return
	if unit.is_summoned:
		return
	fallen_allies.append({
		"class": unit.unit_class,
		"element": unit.current_element,
		"level": unit.level,
		"pos": unit.grid_position,
	})

# ══════════════════════════════════════════════════════════════════════════════
# Hero skills
# ══════════════════════════════════════════════════════════════════════════════

func _doc_inject(caster: UnitBase, allies: Array) -> void:
	var tar := _lowest_hp_ally(caster, allies, float(caster.skill_range), true)
	if not tar: return
	var miss: float = 1.0 - float(tar.current_hp) / float(maxi(tar.max_hp, 1))
	var amt: int = int(float(caster.magic_power) * (1.2 + miss * 1.8) * UnitFactory.natural_aspect(caster))
	tar.heal(amt)
	caster.combat_healing_done += amt
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, tar.global_position, 48.0)

func _riot_shield_bash(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	var dmg: int = int(float(caster.attack_damage) * caster.skill_damage_multiplier)
	tar.take_damage(dmg, caster.current_element, caster)
	caster.damage_dealt += dmg
	tar.stun_time = maxf(tar.stun_time, 1.2)
	tar.taunt_source = caster
	tar.taunt_time = maxf(tar.taunt_time, 3.0)
	_spawn_skill_effect_sized(SkillEffect.Type.WHIRLWIND, tar.global_position, 36.0)

func _pastor_sermon(caster: UnitBase, allies: Array) -> void:
	var best: UnitBase = null
	var best_atk := -1
	for a in allies:
		if a and is_instance_valid(a) and a != caster:
			if caster.grid_position.distance_to(a.grid_position) <= float(caster.skill_range):
				if a.attack_damage > best_atk:
					best_atk = a.attack_damage; best = a
	if not best: best = caster
	best.bonus_aspd_pct = maxf(best.bonus_aspd_pct, 0.4)
	best.bonus_aspd_time = maxf(best.bonus_aspd_time, 5.0)
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, best.global_position, 40.0)

func _sable_bolt(caster: UnitBase, opponents: Array) -> void:
	var cx: int = caster.grid_position.x
	var dmg: int = int(float(caster.attack_damage) * caster.skill_damage_multiplier)
	var hit := false
	for opp in opponents:
		if opp and is_instance_valid(opp) and opp.grid_position.x == cx:
			opp.take_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.ARROW_RAIN, opp.global_position, 28.0)
			hit = true
	if not hit:
		var t := find_nearest_enemy(caster, opponents)
		if t:
			t.take_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg

func _rush_blitz(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	var row: int = tar.grid_position.y
	var dmg: int = int(float(caster.attack_damage) * caster.skill_damage_multiplier)
	for opp in opponents:
		if opp and is_instance_valid(opp) and opp.grid_position.y == row:
			opp.take_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.SHADOW_STRIKE, opp.global_position, 26.0)
	var dest := _nearest_open_adjacent(tar.grid_position)
	if dest != Vector2i(-1, -1):
		battle_grid.remove_unit(caster.grid_position)
		if battle_grid.place_unit(caster, dest):
			caster.grid_position = dest
			caster.position = _world_pos_for(caster, dest)
			caster.is_moving = false

func _stitch_link(caster: UnitBase, opponents: Array) -> void:
	var pool: Array = opponents.filter(func(u): return u != null and is_instance_valid(u))
	pool.sort_custom(func(a, b): return caster.grid_position.distance_to(a.grid_position) < caster.grid_position.distance_to(b.grid_position))
	if pool.size() < 2:
		return
	var a: UnitBase = pool[0]
	var b: UnitBase = pool[1]
	a.link_partner = b
	b.link_partner = a
	_spawn_skill_effect_sized(SkillEffect.Type.ABSORBED, a.global_position, 30.0)
	_spawn_skill_effect_sized(SkillEffect.Type.ABSORBED, b.global_position, 30.0)
	action_logged.emit("%s links two enemies!" % caster.unit_name, caster.is_player_unit)

func _coal_stoke(caster: UnitBase) -> void:
	caster.stoke_charges = 3
	_spawn_skill_effect_sized(SkillEffect.Type.BURN, caster.global_position, 40.0)

func _june_root(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	tar.root_time = maxf(tar.root_time, 3.0)
	var dmg: int = int(float(caster.magic_power) * caster.skill_damage_multiplier)
	if dmg > 0:
		tar.take_damage(dmg, caster.current_element, caster)
		caster.damage_dealt += dmg
	_spawn_skill_effect_sized(SkillEffect.Type.NATURE, tar.global_position, 38.0)

func _cross_absolution(caster: UnitBase, allies: Array) -> void:
	var tar := _lowest_hp_ally(caster, allies, float(caster.skill_range), true)
	if not tar: return
	tar.slow_time = 0.0; tar.burn_time = 0.0; tar.root_time = 0.0
	tar.taunt_time = 0.0; tar.taunt_source = null
	var h: int = int(float(caster.max_hp) * 0.12 + float(caster.resistance) * 6.0)
	tar.heal(h)
	caster.combat_healing_done += h
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, tar.global_position, 44.0)

func _sear_ignite(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	var dmg: int = int(float(caster.magic_power) * caster.skill_damage_multiplier)
	tar.take_damage(dmg, caster.current_element, caster)
	caster.damage_dealt += dmg
	apply_burn(tar, float(caster.magic_power) * 0.25 * UnitFactory.natural_aspect(caster), 5.0, caster)
	_spawn_skill_effect_sized(SkillEffect.Type.BURN, tar.global_position, 40.0)

func _ember_cinder(caster: UnitBase, opponents: Array) -> void:
	var center := find_nearest_enemy(caster, opponents)
	if not center: return
	var dmg: int = int(float(caster.attack_damage) * caster.skill_damage_multiplier)
	for opp in opponents:
		if opp and is_instance_valid(opp) and center.grid_position.distance_to(opp.grid_position) <= 2.0:
			opp.take_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg
			apply_burn(opp, float(caster.attack_damage) * 0.12 * UnitFactory.natural_aspect(caster), 3.0, caster)
			_spawn_skill_effect_sized(SkillEffect.Type.BURN, opp.global_position, 30.0)

func _rift_tear(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	var dmg: int = int(float(caster.magic_power) * caster.skill_damage_multiplier)
	tar.take_damage(dmg, caster.current_element, caster)
	caster.damage_dealt += dmg
	# Banish to the far edge away from the caster.
	var far_y: int = 0 if caster.is_player_unit else battle_grid.grid_height - 1
	var dest := _find_open_in_row(far_y)
	if dest != Vector2i(-1, -1) and tar.cell_size == 1:
		battle_grid.remove_unit(tar.grid_position)
		if battle_grid.place_unit(tar, dest):
			tar.grid_position = dest
			tar.position = _world_pos_for(tar, dest)
			tar.is_moving = false
	_spawn_skill_effect_sized(SkillEffect.Type.SHADOW_STRIKE, tar.global_position, 36.0)

func _zolt_summon_storm(caster: UnitBase) -> void:
	var step := Vector2i(0, -1) if caster.is_player_unit else Vector2i(0, 1)
	var cell: Vector2i = caster.grid_position + step
	if not battle_grid.is_valid_position(cell):
		cell = caster.grid_position
	var storm := StormHazard.new()
	if skill_effect_container:
		skill_effect_container.add_child(storm)
	else:
		add_child(storm)
	var dmg: int = int(float(caster.magic_power) * 0.5 * UnitFactory.natural_aspect(caster))
	storm.setup(battle_grid, self, caster, dmg, cell)
	storms.append(storm)
	action_logged.emit("%s conjures a thunderstorm!" % caster.unit_name, caster.is_player_unit)

func _lumen_refract(caster: UnitBase, opponents: Array) -> void:
	var visited: Dictionary = {}
	var current := find_nearest_enemy(caster, opponents)
	var dmg: int = int(float(caster.magic_power) * caster.skill_damage_multiplier)
	for i in range(5):
		if not (current and is_instance_valid(current)): break
		visited[current] = true
		current.take_damage(dmg, caster.current_element, caster)
		caster.damage_dealt += dmg
		_spawn_skill_effect_sized(SkillEffect.Type.CHAOS_BOLT, current.global_position, 24.0)
		var nxt: UnitBase = null
		var nd := INF
		for opp in opponents:
			if opp and is_instance_valid(opp) and not visited.has(opp):
				var d := current.grid_position.distance_to(opp.grid_position)
				if d < nd:
					nd = d; nxt = opp
		current = nxt
		dmg = int(float(dmg) * 0.85)

func _static_tripwire(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	tar.stun_time = maxf(tar.stun_time, 3.0)
	var dmg: int = int(float(caster.magic_power) * 0.6)
	tar.take_damage(dmg, UnitBase.Element.LIGHTNING, caster)
	caster.damage_dealt += dmg
	_spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, tar.global_position, 34.0)

func _reed_cleanse(caster: UnitBase, allies: Array) -> void:
	var tar := _lowest_hp_ally(caster, allies, float(caster.skill_range), true)
	if not tar: return
	tar.slow_time = 0.0; tar.burn_time = 0.0; tar.root_time = 0.0
	tar.taunt_time = 0.0; tar.taunt_source = null
	var h: int = int(float(caster.magic_power) * 1.4 * UnitFactory.natural_aspect(caster))
	tar.heal(h)
	caster.combat_healing_done += h
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, tar.global_position, 40.0)

func _vail_updraft(caster: UnitBase, allies: Array) -> void:
	var tar := _lowest_hp_ally(caster, allies, 99.0, false)
	if not tar: tar = caster
	tar.untargetable_time = maxf(tar.untargetable_time, 2.0)
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, tar.global_position, 40.0)

func _spore_bloom(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	tar.spore_stacks = 10.0   # instant max → bursts on its next status tick
	tar.set_meta("spore_source", caster)
	tar.set_meta("spore_burst", int(float(caster.magic_power) * 1.6 * UnitFactory.natural_aspect(caster)))
	_spawn_skill_effect_sized(SkillEffect.Type.NATURE, tar.global_position, 38.0)

# ══════════════════════════════════════════════════════════════════════════════
# Hero ultimates
# ══════════════════════════════════════════════════════════════════════════════

func _doc_field_surgery(caster: UnitBase, allies: Array) -> void:
	# Once per battle: revive a fallen ally as a battle-duration unit at 30% HP.
	if caster.revive_used or fallen_allies.is_empty():
		# Fallback: emergency team heal.
		for a in allies:
			if a and is_instance_valid(a):
				var h: int = int(float(a.max_hp) * 0.25)
				a.heal(h)
				caster.combat_healing_done += h
				_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, a.global_position, 36.0)
		return
	caster.revive_used = true
	var snap: Dictionary = fallen_allies.pop_back()
	var cell := _nearest_open_adjacent(caster.grid_position)
	if cell == Vector2i(-1, -1):
		cell = _nearest_open_cell_to(caster.grid_position)
	if cell == Vector2i(-1, -1):
		return
	var revived: VisualUnit = UnitFactory.create_unit(snap["class"], snap["element"], caster.is_player_unit)
	if int(snap["level"]) > 1:
		revived.set_level(int(snap["level"]))
	revived.is_summoned = true
	revived.summon_owner = caster
	revived.is_player_unit = caster.is_player_unit
	revived.grid_position = cell
	revived.current_hp = int(float(revived.max_hp) * 0.30)
	if battle_grid.place_unit(revived, cell):
		if revived.is_player_unit: player_units.append(revived)
		else: enemy_units.append(revived)
		unit_summoned.emit(revived)   # main_game adds to tree + wires signals
		revived.position = _world_pos_for(revived, cell)
		_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, revived.global_position, 60.0)
		action_logged.emit("%s revives %s!" % [caster.unit_name, revived.unit_name], caster.is_player_unit)
	else:
		revived.queue_free()

func _riot_kettle(caster: UnitBase, opponents: Array) -> void:
	for opp in opponents:
		if opp and is_instance_valid(opp):
			opp.taunt_source = caster
			opp.taunt_time = maxf(opp.taunt_time, 4.0)
	_spawn_skill_effect_sized(SkillEffect.Type.GRAVITY_DROP, caster.global_position, 90.0)
	action_logged.emit("%s kettles the enemy!" % caster.unit_name, caster.is_player_unit)

func _pastor_damnation(caster: UnitBase, opponents: Array) -> void:
	for opp in opponents:
		if opp and is_instance_valid(opp):
			opp.outgoing_dmg_mult = minf(opp.outgoing_dmg_mult, 0.6)
			opp.outgoing_dmg_time = 0.0   # lasts the rest of the round
	_spawn_skill_effect_sized(SkillEffect.Type.INFERNO, caster.global_position, 90.0)
	action_logged.emit("%s damns the enemy host!" % caster.unit_name, caster.is_player_unit)

func _sable_headshot(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	var mom: int = caster.momentum_stacks
	var dmg: int = int(float(caster.attack_damage) * caster.ultimate_damage_mult * (1.0 + float(mom) * 0.12))
	tar.take_damage(dmg, caster.current_element, caster)
	caster.damage_dealt += dmg
	caster.momentum_stacks = 0
	_spawn_skill_effect_sized(SkillEffect.Type.ARROW_RAIN, tar.global_position, 50.0)
	action_logged.emit("%s lands a headshot! (%d dmg)" % [caster.unit_name, dmg], caster.is_player_unit)

func _rush_afterimage(caster: UnitBase, opponents: Array) -> void:
	afterimage_actor = caster
	afterimage_time = 3.0
	var dmg: int = int(float(caster.attack_damage) * caster.ultimate_damage_mult)
	for opp in opponents:
		if opp and is_instance_valid(opp):
			opp.take_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.SHADOW_STRIKE, opp.global_position, 30.0)
	_spawn_skill_effect_sized(SkillEffect.Type.OVERDRIVE, caster.global_position, 60.0)
	action_logged.emit("%s blurs into afterimages!" % caster.unit_name, caster.is_player_unit)

func _stitch_puppet(caster: UnitBase, opponents: Array) -> void:
	var tar := _highest_hp_enemy(caster, opponents)
	if not tar: tar = find_nearest_enemy(caster, opponents)
	if not tar: return
	tar.puppet_time = 4.0
	_spawn_skill_effect_sized(SkillEffect.Type.SHADOW_STRIKE, tar.global_position, 44.0)
	action_logged.emit("%s seizes control of %s!" % [caster.unit_name, tar.unit_name], caster.is_player_unit)

func _coal_meltdown(caster: UnitBase) -> void:
	caster.meltdown_time = 5.0
	_spawn_skill_effect_sized(SkillEffect.Type.BURN, caster.global_position, 60.0)
	action_logged.emit("%s overheats — Meltdown!" % caster.unit_name, caster.is_player_unit)

func _june_bloom(caster: UnitBase) -> void:
	thorns_time = 8.0
	thorns_dmg = int(float(caster.magic_power) * 0.5 * UnitFactory.natural_aspect(caster))
	thorns_owner_is_player = caster.is_player_unit
	_spawn_skill_effect_sized(SkillEffect.Type.NATURE, caster.global_position, 100.0)
	action_logged.emit("%s blankets the field in thorns!" % caster.unit_name, caster.is_player_unit)

func _cross_judgment(caster: UnitBase, opponents: Array) -> void:
	var dmg: int = int(float(caster.combat_healing_done) * 0.6)
	if dmg < caster.attack_damage:
		dmg = caster.attack_damage
	for opp in opponents:
		if opp and is_instance_valid(opp):
			opp.take_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, opp.global_position, 30.0)
	action_logged.emit("%s passes judgment! (%d dmg)" % [caster.unit_name, dmg], caster.is_player_unit)

func _sear_conflagration(caster: UnitBase, opponents: Array) -> void:
	var maxdps: float = float(caster.magic_power) * 0.2 * UnitFactory.natural_aspect(caster)
	for opp in opponents:
		if opp and is_instance_valid(opp) and opp.burn_dps > maxdps:
			maxdps = opp.burn_dps
	for opp in opponents:
		if opp and is_instance_valid(opp):
			apply_burn(opp, maxdps, 5.0, caster)
			var burst: int = int(opp.burn_dps * 2.0)
			if burst > 0:
				opp.take_damage(burst, UnitBase.Element.FIRE, caster, true)
				caster.damage_dealt += burst
			_spawn_skill_effect_sized(SkillEffect.Type.BURN, opp.global_position, 36.0)
	action_logged.emit("%s ignites the battlefield!" % caster.unit_name, caster.is_player_unit)

func _ember_wildfire(caster: UnitBase, opponents: Array) -> void:
	for opp in opponents.duplicate():
		if opp and is_instance_valid(opp) and opp.burn_time > 0.0:
			var burst: int = int(opp.burn_dps * 4.0 + float(caster.attack_damage) * 0.5)
			_explosion(caster, opp.grid_position, burst, opponents, 1.5)
	action_logged.emit("%s detonates the flames!" % caster.unit_name, caster.is_player_unit)

func _rift_collapse(caster: UnitBase, opponents: Array) -> void:
	var center := Vector2i(battle_grid.grid_width / 2, battle_grid.grid_height / 2)
	var dmg: int = int(float(caster.magic_power) * caster.ultimate_damage_mult)
	_spawn_skill_effect_sized(SkillEffect.Type.GRAVITY_DROP, battle_grid.grid_to_world(center), 110.0)
	for opp in opponents:
		if not (opp and is_instance_valid(opp)): continue
		if opp.cell_size == 1:
			var dest := _nearest_open_cell_to(center)
			if dest != Vector2i(-1, -1):
				battle_grid.remove_unit(opp.grid_position)
				if battle_grid.place_unit(opp, dest):
					opp.grid_position = dest
					opp.position = _world_pos_for(opp, dest)
					opp.is_moving = false
		opp.take_damage(dmg, caster.current_element, caster)
		caster.damage_dealt += dmg
		_spawn_skill_effect_sized(SkillEffect.Type.SHADOW_STRIKE, opp.global_position, 30.0)
	action_logged.emit("%s collapses space!" % caster.unit_name, caster.is_player_unit)

func _zolt_thunderhammer(caster: UnitBase, opponents: Array) -> void:
	var tar := _highest_hp_enemy(caster, opponents)
	if not tar: tar = find_nearest_enemy(caster, opponents)
	if not tar: return
	var dmg: int = int(float(caster.magic_power) * caster.ultimate_damage_mult * UnitFactory.natural_aspect(caster))
	tar.take_damage(dmg, UnitBase.Element.LIGHTNING, caster)
	caster.damage_dealt += dmg
	tar.stun_time = maxf(tar.stun_time, 5.0)
	_spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, tar.global_position, 72.0)
	action_logged.emit("%s calls down the thunderhammer!" % caster.unit_name, caster.is_player_unit)

func _lumen_prism(caster: UnitBase, opponents: Array) -> void:
	var dmg: int = int(float(caster.magic_power) * caster.ultimate_damage_mult)
	for opp in opponents:
		if opp and is_instance_valid(opp):
			opp.take_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.CHAOS_BOLT, opp.global_position, 28.0)
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, caster.global_position, 60.0)
	action_logged.emit("%s splits into a prism!" % caster.unit_name, caster.is_player_unit)

func _static_grid(caster: UnitBase) -> void:
	grid_field_time = 4.0
	grid_field_dmg = int(float(caster.magic_power) * 0.35 * UnitFactory.natural_aspect(caster))
	grid_owner_is_player = caster.is_player_unit
	_spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, caster.global_position, 100.0)
	action_logged.emit("%s electrifies the floor!" % caster.unit_name, caster.is_player_unit)

func _reed_confluence(caster: UnitBase, allies: Array) -> void:
	var water := 0
	for a in allies:
		if a and is_instance_valid(a) and a.current_element == UnitBase.Element.WATER:
			water += 1
	var mult: float = 1.0 + float(water) * 0.4
	for a in allies:
		if a and is_instance_valid(a):
			var h: int = int(float(a.max_hp) * 0.18 * mult)
			a.heal(h)
			caster.combat_healing_done += h
			_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, a.global_position, 34.0)
	action_logged.emit("%s channels the confluence! (x%.1f)" % [caster.unit_name, mult], caster.is_player_unit)

func _vail_tailwind(caster: UnitBase, allies: Array) -> void:
	for a in allies:
		if a and is_instance_valid(a):
			a.bonus_aspd_pct = maxf(a.bonus_aspd_pct, 0.5)
			a.bonus_aspd_time = maxf(a.bonus_aspd_time, 6.0)
			_spawn_skill_effect_sized(SkillEffect.Type.OVERDRIVE, a.global_position, 26.0)
	action_logged.emit("%s summons a tailwind!" % caster.unit_name, caster.is_player_unit)

func _spore_release(caster: UnitBase, opponents: Array) -> void:
	var burst: int = int(float(caster.magic_power) * 1.4 * UnitFactory.natural_aspect(caster))
	for opp in opponents:
		if opp and is_instance_valid(opp):
			var mult: float = clampf(opp.spore_stacks / 10.0, 0.2, 1.5)
			var dmg: int = int(float(burst) * (0.6 + mult))
			opp.spore_stacks = 0.0
			opp.take_damage(dmg, UnitBase.Element.EARTH, caster, true)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.NATURE, opp.global_position, 32.0)
	action_logged.emit("%s releases the spores!" % caster.unit_name, caster.is_player_unit)
