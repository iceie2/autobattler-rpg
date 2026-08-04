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
# Real seconds a unit has gone without managing to take a movement step (see
# move_unit_towards_with_pathfinding). Two large (2×2+) units parked flush
# against each other can mutually block each other's very first step every
# single frame — both keep replanning a path whose first cell the other one
# also wants, so neither ever budges even though open space exists two cells
# away (2026-07-24 user report: Hill Giants frozen solid until one died and
# freed the other). Past STUCK_ESCAPE_SECONDS we widen the sidestep search
# past the immediate ring to break that symmetric deadlock.
var _stuck_timers: Dictionary = {}  # unit -> float
const STUCK_ESCAPE_SECONDS := 1.0
const STUCK_ESCAPE_RADIUS := 3

# ── Real-time pace control ────────────────────────────────────────────────────
# The battle is a live simulation. `time_scale` multiplies every delta so the user
# can slow it to 0.25× for a play-by-play or speed to 4×. `paused` freezes time
# entirely (including movement interpolation).
var paused: bool = false
var time_scale: float = 1.0

# Seconds of battle time elapsed (scaled, so it matches what the fight actually
# experienced rather than wall-clock). Drives the anti-stall enrage below.
var battle_elapsed: float = 0.0
# Per-hero after-action snapshot, instance_id → {name, first, damage, healing}.
# Written every frame so it survives units being freed on death.
var _after_action: Dictionary = {}

# ── Roster-expansion runtime state ────────────────────────────────────────────
# Rush "Afterimage": while active, every unit except the actor is frozen.
var afterimage_actor: UnitBase = null
var afterimage_time: float = 0.0

# Khagan phase-3 possession (timed-survival rework, 2026-07-24). The seized hero
# is a real threat for a bounded window, not an unkillable must-kill wall: you
# win by SURVIVING the timer (or bursting the puppet, which frees it early). See
# start_khagan_possession / end_khagan_possession.
var _khagan_puppet: UnitBase = null
var _khagan_timer: float = 0.0
const KHAGAN_POSSESS_SECONDS: float = 8.0    # survive this long → control breaks, you win
const KHAGAN_PUPPET_DMG_MULT: float = 0.55   # the spirit fights clumsily — capped outgoing damage
const KHAGAN_PUPPET_HP_FRAC: float = 0.7     # seized at reduced HP so bursting it is viable
const KHAGAN_PUPPET_BURST_ACCEL: float = 2.0 # a wounded puppet loses its grip faster (agency)

# Zolt storms — roaming board hazards, ticked here, freed at round end.
var storms: Array = []

# Board-wide field effects that damage enemies as they move.
var thorns_time: float = 0.0          # June "Bloom"
var thorns_dmg: int = 0
var thorns_owner_is_player: bool = true
var grid_field_time: float = 0.0      # Static "Grid"
var grid_field_dmg: int = 0
var grid_field_tick_time: float = 0.0
var grid_owner_is_player: bool = true
var static_grid_channel_time: float = -1.0   # -1 = no channel in progress
var static_grid_channel_caster: UnitBase = null
var fire_trail: Dictionary = {}       # Vector2i -> {dmg,time,source,owner_is_player}  Sear passive

# Re-entrancy guard so Stitch Link / Loose Threads can't recurse forever.
var _propagating: bool = false

# Snapshots of fallen player heroes so Doc can revive one (Field Surgery).
var fallen_allies: Array = []

# Ant Hill swarm — battle-wide rage counter (2026-07-24 rework, see UnitBase.
# attack()'s ANT case): every landed Ant bite on ANY target bumps this by 1,
# UNCAPPED, and it's added as bonus true damage to EVERY Ant's NEXT attack on
# ANY target. Global rather than per-victim so spreading the swarm's bites
# across many units (or healing through single-target damage) can't stall the
# escalation forever — the longer the fight runs, the harder every ant hits,
# full stop, with no ceiling. A capped version defeats the entire point: past
# the cap, stalling becomes free again and the DPS check disappears (2026-07-24
# user correction). Reset at battle start.
var ant_swarm_stacks: int = 0

# ── Freeze watchdog (2026-07-24, diagnosing user report of full mid-battle
# freezes with no console access) — if real time passes with the sim running
# unpaused but no unit ever fires unit_action/action_logged, something is
# silently stuck (not paused, not battle-over). Dumps one full per-unit state
# snapshot to disk so the freeze can be diagnosed from the log instead of
# guessing blind. Self-disarms after one dump per battle (see start_battle).
const FREEZE_WATCHDOG_SECONDS := 4.0
var _watchdog_idle_time: float = 0.0
var _watchdog_fired: bool = false


signal battle_started()
signal battle_ended(player_won: bool)
signal unit_action(unit, action_type: String)
signal action_logged(text: String, is_player: bool)   # event-history feed
signal pace_changed(is_paused: bool, scale: float)
signal unit_summoned(unit: UnitBase)

func _ready():
	unit_action.connect(func(_u, _t): _watchdog_idle_time = 0.0)
	action_logged.connect(func(_t, _p): _watchdog_idle_time = 0.0)

func initialize(grid: BattleGrid, state: GameState) -> void:
	battle_grid = grid
	game_state = state
	
	if game_state:
		game_state.auto_battle_started.connect(_on_auto_battle_started)

func _on_auto_battle_started() -> void:
	start_battle()

# Global pacing knob: the game plays too fast per user feedback (2026-07-02) —
# a first, easily-reversible -10% cut across the whole sim (movement, attacks,
# regen, everything derives dt from time_scale). Tune in balance.gd.
const BASE_TIME_SCALE := Balance.BASE_TIME_SCALE

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
	battle_elapsed = 0.0
	_after_action.clear()
	unit_paths.clear()
	_stuck_timers.clear()
	paused = false
	time_scale = BASE_TIME_SCALE
	_clear_board_effects()
	afterimage_actor = null
	afterimage_time = 0.0
	fallen_allies.clear()
	ant_swarm_stacks = 0
	_watchdog_idle_time = 0.0
	_watchdog_fired = false
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
		unit.ult_active_time = 0.0
		unit.hp_regen_accum = 0.0
		unit.mp_regen_accum = 0.0
		unit.lordee_aura_timer = 0.0
		unit.lordee_chase_timer = 0.0
		unit.current_shield = 0
		# Roster-expansion status fields
		unit.burn_time = 0.0; unit.burn_dps = 0.0; unit.burn_accum = 0.0; unit.burn_source = null
		unit.bleed_time = 0.0; unit.bleed_dps = 0.0; unit.bleed_accum = 0.0; unit.bleed_source = null
		unit.slow_time = 0.0; unit.slow_pct = 0.0
		unit.root_time = 0.0
		unit.taunt_time = 0.0; unit.taunt_source = null
		unit.untargetable_time = 0.0
		unit.melee_untargetable_time = 0.0
		unit.outgoing_dmg_mult = 1.0; unit.outgoing_dmg_time = 0.0
		unit.bonus_aspd_pct = 0.0; unit.bonus_aspd_time = 0.0
		unit.weakened_pct = 0.0; unit.weakened_time = 0.0
		unit.spore_stacks = 0.0; unit.spore_tick_accum = 0.0
		unit.momentum_stacks = 0
		unit.link_partner = null
		unit.puppet_time = 0.0
		unit.stoke_charges = 0
		unit.meltdown_time = 0.0
		unit.combat_healing_done = 0
		unit.first_contribution_time = -1.0   # per-battle; see _sample_first_contribution
		unit.judgment_pool = 0
		unit.revive_used = false
		# Stat Stealer drain — no lingering theft into a fresh battle.
		unit.drain_time = 0.0; unit.drain_stat = ""; unit.drain_per_sec = 0.0
		unit.drain_stolen = 0.0; unit.drain_source = null; unit.drain_accum = 0.0
		unit.drain_snapshot = 0.0
		# Ant Hill's spawn clock gets a short pre-delay before its first ant.
		# ant_swarm_stacks (the actual swarm-rage counter) is now global — reset
		# once in start_battle, not per-unit here.
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
			# Multi-cell units (Hill Giant 2×2, future 3×3 bosses) appear once
			# per occupied cell — without the has() dedup a giant entered the
			# army list 4 times and got ticked 4× per frame: ~4× attack rate,
			# 4× regen/DoT ticks, 4 movement decisions a frame (2026-07-15).
			unit.battle_manager = self
			if unit.is_player_unit:
				if not player_units.has(unit):
					player_units.append(unit)
				if not unit.died.is_connected(_on_ally_died):
					unit.died.connect(_on_ally_died.bind(unit))
			elif not enemy_units.has(unit):
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
	battle_elapsed += dt
	_tick_global_effects(dt)
	_tick_khagan_possession(dt)

	# Tick every living unit's real-time clocks and let it act.
	for unit in player_units + enemy_units:
		if unit and is_instance_valid(unit):
			_tick_unit(unit, dt)
			_sample_first_contribution(unit)

	# Roaming storm hazards.
	for storm in storms:
		if storm and is_instance_valid(storm):
			storm.tick(dt)

	# Smooth movement interpolation (also scaled, so slow-mo slows motion too).
	update_unit_movements(dt)

	check_battle_end()

	# Freeze watchdog — see declaration above. Uses REAL delta (not dt), so it
	# still measures wall-clock even at 0.25x, and never fires while genuinely
	# paused (this whole block is behind the `dt <= 0.0` early-return above).
	if not _watchdog_fired:
		_watchdog_idle_time += delta
		if _watchdog_idle_time >= FREEZE_WATCHDOG_SECONDS:
			_watchdog_fired = true
			_dump_freeze_diagnostic()

# Writes one full state snapshot to user://freeze_diagnostic.log — round, pace
# state, global timers, and every unit's action-gating fields (cooldowns,
# stun/root/taunt, target, is_moving, path cache). Point is to catch WHATEVER
# is silently blocking every unit's action every frame without needing a live
# Godot console (2026-07-24 user report: full mid-battle freeze, exported build).
func _dump_freeze_diagnostic() -> void:
	var lines: Array[String] = []
	lines.append("=== FREEZE DIAGNOSTIC — round %s ===" % (str(game_state.battle_round) if game_state else "?"))
	lines.append("battle_active=%s paused=%s time_scale=%s" % [battle_active, paused, time_scale])
	lines.append("afterimage_time=%s afterimage_actor=%s" % [afterimage_time, afterimage_actor.unit_name if afterimage_actor and is_instance_valid(afterimage_actor) else "null"])
	lines.append("khagan_puppet=%s khagan_timer=%s" % [_khagan_puppet.unit_name if _khagan_puppet and is_instance_valid(_khagan_puppet) else "null", _khagan_timer])
	lines.append("player_units=%d enemy_units=%d" % [player_units.size(), enemy_units.size()])
	for unit in player_units + enemy_units:
		if not (unit and is_instance_valid(unit)):
			lines.append("  <freed unit still in array>")
			continue
		var path_len: int = unit_paths[unit].size() if unit_paths.has(unit) else -1
		lines.append("  %s [%s] pos=%s hp=%d/%d moving=%s stun=%.2f root=%.2f taunt=%.2f puppet_t=%.2f atk_cd=%.2f skill_cd=%.2f ult_ready=%s target=%s path_len=%d" % [
			unit.unit_name, "P" if unit.is_player_unit else "E", unit.grid_position,
			unit.current_hp, unit.max_hp, unit.is_moving, unit.stun_time, unit.root_time,
			unit.taunt_time, unit.puppet_time, unit.attack_cooldown, unit.skill_cd_time,
			unit.ultimate_ready, unit.target_unit.unit_name if unit.target_unit and is_instance_valid(unit.target_unit) else "null",
			path_len])
	var text := "\n".join(lines)
	print(text)
	var f := FileAccess.open("user://freeze_diagnostic.log", FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
		print("[Watchdog] wrote user://freeze_diagnostic.log")

# ── Anti-stall enrage (2026-07-24) ────────────────────────────────────────────
# Multiplier applied to ALL damage from BOTH sides once a fight has dragged past
# Balance.BATTLE_ENRAGE_START, doubling every BATTLE_ENRAGE_DOUBLE_EVERY seconds.
# Read in UnitBase.take_damage. Because it scales both teams identically it never
# decides WHO wins — it just guarantees the battle terminates, which the engine
# otherwise never does (check_battle_end only fires when one side is empty).
# Distinct from the freeze watchdog above: that one is a pure DIAGNOSTIC for
# "no unit acted at all" and resets on any action, so it never fires in the
# stall this fixes (where units attack constantly, just far too slowly).
func enrage_multiplier() -> float:
	var over: float = battle_elapsed - Balance.BATTLE_ENRAGE_START
	if over <= 0.0:
		return 1.0
	return minf(pow(2.0, over / Balance.BATTLE_ENRAGE_DOUBLE_EVERY), Balance.BATTLE_ENRAGE_MAX)

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
		grid_field_tick_time -= dt
		if grid_field_tick_time <= 0.0:
			grid_field_tick_time += 1.0
			var grid_foes: Array = enemy_units if grid_owner_is_player else player_units
			for u in grid_foes.duplicate():
				if u and is_instance_valid(u):
					u.take_damage(grid_field_dmg, UnitBase.Element.LIGHTNING, null, true)
	if static_grid_channel_time > 0.0:
		if not (static_grid_channel_caster and is_instance_valid(static_grid_channel_caster)) \
				or static_grid_channel_caster.stun_time > 0.0:
			# Interrupted (dead/stunned/silenced) — no stun payoff this cast.
			static_grid_channel_time = -1.0
			static_grid_channel_caster = null
		else:
			static_grid_channel_time -= dt
			if static_grid_channel_time <= 0.0:
				var grid_stun_foes: Array = enemy_units if grid_owner_is_player else player_units
				for u in grid_stun_foes.duplicate():
					if u and is_instance_valid(u):
						u.stun_time = maxf(u.stun_time, 2.0)
				_spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, static_grid_channel_caster.global_position, 130.0)
				action_logged.emit("%s's Grid locks the field down!" % static_grid_channel_caster.unit_name, grid_owner_is_player)
				static_grid_channel_time = -1.0
				static_grid_channel_caster = null
	if not fire_trail.is_empty():
		var expired: Array = []
		for cell in fire_trail:
			fire_trail[cell]["time"] -= dt
			if fire_trail[cell]["time"] <= 0.0:
				expired.append(cell)
		for cell in expired:
			fire_trail.erase(cell)

# Khagan possession survival timer. Drains in real time; a WOUNDED puppet loses
# its grip faster (burst is rewarded, never required). When it empties, control
# breaks and the fight is won — see end_khagan_possession. A puppet burst to 0 HP
# instead frees via the die() intercept before this ever reaches 0.
func _tick_khagan_possession(dt: float) -> void:
	if _khagan_puppet == null:
		return
	if not is_instance_valid(_khagan_puppet) or _khagan_puppet not in enemy_units:
		# Puppet freed/removed by another path — stop tracking.
		_khagan_puppet = null
		_khagan_timer = 0.0
		return
	var hp_pct: float = float(_khagan_puppet.current_hp) / maxf(float(_khagan_puppet.max_hp), 1.0)
	_khagan_timer -= dt * (1.0 + KHAGAN_PUPPET_BURST_ACCEL * (1.0 - hp_pct))
	if _khagan_timer <= 0.0:
		end_khagan_possession(_khagan_puppet)

func _clear_board_effects() -> void:
	for storm in storms:
		if storm and is_instance_valid(storm):
			storm.queue_free()
	storms.clear()
	thorns_time = 0.0
	grid_field_time = 0.0
	static_grid_channel_time = -1.0
	static_grid_channel_caster = null
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
	# Dead units take no actions. check_battle_end() purges them at the end of
	# each frame, but a unit can die mid-frame (another unit's attack earlier in
	# this same loop) — without this it would still get a turn while dead.
	if not _is_alive(unit):
		return
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
	if unit.ult_active_time > 0.0: unit.ult_active_time -= dt

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
	if _unit_dist(unit, target) <= effective_range:
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
			# Basic-mob attack-speed passives (Goblin Pack Courage, Orc Bloodrage,
			# Bear Fury, Windup Overclock) stash their bonus in this meta from
			# _tick_mob_passive; folded into haste so it rides the same cooldown math.
			haste += float(unit.get_meta("mob_aspd_bonus", 0.0))
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
		# Large units go through the same A* as everyone else — find_path is
		# footprint-aware when the mover is passed (2026-07-15 Hill Giant
		# left/right oscillation fix; the old greedy _move_2x2_unit is gone).
		move_unit_towards_with_pathfinding(unit, target.grid_position, dt)

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
			unit.heal(whole, true)   # silent — batched into a single floating number below
			unit.hp_regen_accum -= whole
			unit.regen_text_accum += whole
	# Passive regen (base regen, Equipment Regeneration, Titan's Heart) can tick
	# every physics frame — flush it as one summed floating number every 0.2s
	# instead of spamming "+1 +1 +1" every frame (was making tanks look like
	# they were getting hit with a wall of tiny heal text).
	unit.regen_text_timer += dt
	if unit.regen_text_timer >= 0.2:
		unit.regen_text_timer = 0.0
		if unit.regen_text_accum > 0:
			unit.spawn_heal_text(unit.regen_text_accum)
			unit.regen_text_accum = 0
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
			if not _is_focused(unit, opponents):
				return false
			# Boxed in (surrounded, cornered, wedged against allies) — no legal
			# retreat cell exists. _shauna_kite would still spend the mana, set
			# the cooldown, and consume this whole tick's action for literally
			# no effect (2026-07-24 user report of Shauna "standing there and
			# not fighting"). Gate the trigger on a real escape existing so a
			# boxed-in Shauna falls through to the normal attack/move branch
			# below instead of wasting the turn on a no-op Kite.
			var nearest := find_nearest_enemy(unit, opponents)
			return nearest != null and _best_retreat_cell(unit, nearest) != Vector2i(-1, -1)
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
	# Basic-mob signature passives dispatch on the `mob_passive` meta BEFORE the
	# class match — mobs piggyback hero UnitClass values for stats/sprites, so the
	# class arms below can't tell a Goblin (WARRIOR) from a real Warrior. Mirrors
	# the same-reasoned `mob_skill` dispatch in _use_skill. A mob has no hero
	# passive, so returning here loses nothing. See _tick_mob_passive.
	if unit.has_meta("mob_passive"):
		_tick_mob_passive(unit, opponents, allies, dt)
		return
	match unit.unit_class:
		UnitBase.UnitClass.ANT_HILL:
			_ant_hill_spawn_tick(unit, allies, dt)

		UnitBase.UnitClass.HYDRA:
			_hydra_regrow_tick(unit, dt)

		UnitBase.UnitClass.BLOODHOUND:
			# Blood Frenzy: below 45% HP
			var threshold := unit.max_hp * _abf(unit, AF_PASSIVE, "thresh")
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
				unit.set_meta("presence_bonus", min(nearby * _abf(unit, AF_PASSIVE, "per"),
						_abf(unit, AF_PASSIVE, "cap")))

		UnitBase.UnitClass.LORDEE:
			# Feeding Frenzy: AoE damage pulse every 0.8s to adjacent enemies
			unit.lordee_aura_timer -= dt
			if unit.lordee_aura_timer <= 0.0:
				unit.lordee_aura_timer = _abf(unit, AF_PASSIVE, "every")
				var aura_dmg := _ab(unit, AF_PASSIVE, "dmg")
				for opp in opponents:
					if opp and is_instance_valid(opp):
						if unit.grid_position.distance_to(opp.grid_position) <= 1.5:
							opp.take_damage(aura_dmg, unit.current_element, unit)
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
				unit.hp_regen_accum += float(summon_count) * _abf(unit, AF_PASSIVE, "regen") * dt

		# ── Roster expansion (per-frame passives) ─────────────────────────────
		UnitBase.UnitClass.DOC:
			# Triage: periodically mend the lowest-HP ally; heal scales with missing HP.
			var doc_t: float = float(unit.get_meta("triage_t", 0.0)) - dt
			if doc_t <= 0.0:
				doc_t = _abf(unit, AF_PASSIVE, "every")
				var doc_tar := _lowest_hp_ally(unit, allies, 4.0, true)
				if doc_tar:
					var doc_miss: float = 1.0 - float(doc_tar.current_hp) / float(maxi(doc_tar.max_hp, 1))
					var doc_lo: float = _abf(unit, AF_PASSIVE, "lo")
					var doc_amt: int = int(doc_lo + (_abf(unit, AF_PASSIVE, "hi") - doc_lo) * doc_miss)
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
				var pastor_bonus: float = _abf(unit, AF_PASSIVE, "bonus")
				for ally in allies:
					if ally and is_instance_valid(ally):
						if unit.grid_position.distance_to(ally.grid_position) <= _abf(unit, AF_PASSIVE, "radius"):
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
						if unit.grid_position.distance_to(ally.grid_position) <= _abf(unit, AF_PASSIVE, "radius"):
							ally.hp_regen_accum += _abf(unit, AF_PASSIVE, "regen") * AURA_TICK_INTERVAL

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
							ally.hp_regen_accum += _abf(unit, AF_PASSIVE, "regen") * AURA_TICK_INTERVAL
							var fade: float = AURA_TICK_INTERVAL * _abf(unit, AF_PASSIVE, "cleanse")
							if ally.slow_time > 0.0: ally.slow_time -= fade
							if ally.burn_time > 0.0: ally.burn_time -= fade
							if ally.root_time > 0.0: ally.root_time -= fade

		UnitBase.UnitClass.SHEILDOR:
			# "Guardian Aura" (implemented 2026-07-03 — the factory has shown this
			# passive_name in the UI since creation with NO implementation behind
			# it): every few seconds, grant a small shield to the most-wounded
			# adjacent ally. A mini echo of his skill, aura-throttle pattern.
			var shel_t: float = float(unit.get_meta("bulwark_t", 0.0)) - dt
			if shel_t > 0.0:
				unit.set_meta("bulwark_t", shel_t)
			else:
				unit.set_meta("bulwark_t", _abf(unit, AF_PASSIVE, "every"))
				var shel_tar := _lowest_hp_ally(unit, allies, 1.5, false)
				if shel_tar and shel_tar != unit:
					var shel_amt: int = _ab(unit, AF_PASSIVE, "shield")
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
				var vail_bonus: float = _abf(unit, AF_PASSIVE, "aspd")
				for v_ally in allies:
					if v_ally and is_instance_valid(v_ally) and v_ally != unit:
						if unit.grid_position.distance_to(v_ally.grid_position) <= _abf(unit, AF_PASSIVE, "radius"):
							v_ally.bonus_aspd_pct = maxf(v_ally.bonus_aspd_pct, vail_bonus)
							v_ally.bonus_aspd_time = maxf(v_ally.bonus_aspd_time, 0.35)

		UnitBase.UnitClass.SPORE:
			# Spore Cloud: enemies within 2 cells accrue stacks; burst handled in _tick_statuses.
			var spore_burst_amt: int = _ab(unit, AF_PASSIVE, "burst")
			for opp in opponents:
				if opp and is_instance_valid(opp):
					if unit.grid_position.distance_to(opp.grid_position) <= _abf(unit, AF_PASSIVE, "radius"):
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
			var dmg := _ab(caster, AF_ULT, "dmg")
			target.take_damage(dmg, caster.current_element, caster)
			target.stun_time = _abf(caster, AF_ULT, "stun")
			caster.damage_dealt += dmg
			_spawn_skill_effect(SkillEffect.Type.SHADOW_STRIKE, caster.global_position)

		UnitBase.UnitClass.BOUNCER:
			# Gravity Drop — warning ring + pull all enemies in range + impact
			var dmg := _ab(caster, AF_ULT, "dmg")
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
				if caster.grid_position.distance_to(opp.grid_position) <= _abf(caster, AF_ULT, "radius"):
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
					opp.take_magic_damage(dmg, caster.current_element, caster)
					caster.damage_dealt += dmg

		UnitBase.UnitClass.HEADHUNTER:
			# Snipe — shoot farthest enemy, blocked by any enemy in line
			var target := _farthest_enemy(caster, opponents)
			if not target:
				return
			# Check line of fire for blockers
			var actual_target := _check_line_of_fire(caster, target, opponents)
			var dmg := _ab(caster, AF_ULT, "dmg")
			actual_target.take_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg
			_spawn_skill_effect(SkillEffect.Type.ARROW_RAIN, actual_target.global_position)
		UnitBase.UnitClass.SHEILDOR:
			_sheildor_guardian_leap(caster, allies, opponents)
		UnitBase.UnitClass.LORDEE:
			_lordee_parasite_lunge(caster, opponents)
		UnitBase.UnitClass.SHAUNA:
			# Overdrive: 3 extra attack turns
			caster.overdrive_time = _abf(caster, AF_ULT, "dur")
			caster.ult_active_time = caster.overdrive_time   # no ult-charge while overdrive runs
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
					opp.take_magic_damage(dmg_r, caster.current_element, caster)
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

# Gap between two units measured BODY-to-BODY, not origin-to-origin. grid_position
# on a multi-cell unit is its top-left corner, so a 2×2 Hill Giant standing flush
# west of a 1×1 hero has its right-hand column touching the hero while its origin
# is 2 cells away: _grid_dist said "range 2, out of reach" and the giant walked
# east to close, which put it genuinely out of range, so it walked back — the
# forever-shuffle-never-attack loop the player reported 2026-08-03 (worse on the
# 3×3 Architect, off by 2). Rect-to-rect distance is 0 when the bodies overlap-
# adjacent, 1 when flush, and identical to _grid_dist for two 1×1 units.
func _unit_dist(a: UnitBase, b: UnitBase) -> int:
	return _rect_dist(a.grid_position, a.cell_size, b.grid_position, b.cell_size)

func _rect_dist(a_origin: Vector2i, a_size: int, b_origin: Vector2i, b_size: int) -> int:
	var dx: int = maxi(maxi(a_origin.x - (b_origin.x + b_size - 1), b_origin.x - (a_origin.x + a_size - 1)), 0)
	var dy: int = maxi(maxi(a_origin.y - (b_origin.y + b_size - 1), b_origin.y - (a_origin.y + a_size - 1)), 0)
	return maxi(dx, dy)

# ── After-action tracking (2026-07-27) ────────────────────────────────────────
# Records WHEN each unit first contributed, for the post-battle report. Sampled
# once per unit per frame rather than hooked into the damage paths: damage_dealt
# is incremented from a dozen places (autos, skills, ults, projectiles, DoTs,
# auras) and hooking each would be fragile and easy to miss on the next kit —
# watching the total covers every path that exists or will exist, and is purely
# observational so it cannot alter a fight.
#
# Motive: arena measurement showed the top cause of losses is defeat-in-detail —
# heroes engaging piecemeal while the front line dies alone. That is invisible
# in a damage total (a hero who did nothing for 8s then dealt damage looks fine)
# but obvious in a first-contribution time.
func _sample_first_contribution(unit) -> void:
	if unit.first_contribution_time < 0.0:
		# Healing counts — a healer that has been keeping the line alive is
		# engaged even with zero damage to its name.
		if unit.damage_dealt > 0 or unit.combat_healing_done > 0:
			unit.first_contribution_time = battle_elapsed
	if not unit.is_player_unit:
		return
	# Mirror each hero's numbers into _after_action every frame. Necessary
	# because a defeat FREES the hero units before main_game._on_battle_ended
	# runs — reading them there would report nothing at exactly the moment the
	# report matters most. Keyed by instance id; last values before death stick.
	var taken: int = 0
	for v in unit.damage_taken_from.values():
		taken += int(v)
	_after_action[unit.get_instance_id()] = {
		"name": unit.unit_name,
		"first": unit.first_contribution_time,
		"damage": unit.damage_dealt,
		"healing": unit.combat_healing_done,
		"taken": taken,
	}

# Per-hero after-action rows for the battle just fought. See _sample_first_contribution.
func after_action_rows() -> Array:
	return _after_action.values()

func find_nearest_enemy(unit: UnitBase, enemies: Array) -> UnitBase:
	var nearest: UnitBase = null
	var min_distance: float = INF
	
	for enemy in enemies:
		# _is_alive, not just is_instance_valid: a fallen player hero's node
		# now persists (parked for the round-end revival) instead of being
		# freed, so a validity check alone would happily target a corpse.
		if not _is_alive(enemy):
			continue
		if enemy.untargetable_time > 0.0:   # Vail Updraft etc.
			continue
		# Aloft (Skyrender): out of reach for melee, still fair game for
		# anything with range. Checked against the ATTACKER's reach, so the same
		# target is simultaneously untargetable to a warrior and targetable to an
		# archer — which is the whole point of the wave-20 fight.
		if enemy.melee_untargetable_time > 0.0 and unit.attack_range <= 1:
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

# ── Ability numbers ───────────────────────────────────────────────────────────
# Every hero ability number comes from AbilityFormulas (scripts/units/
# ability_formulas.gd) so the level-up screen can show the player the exact
# figure the fight will deal. Do NOT inline a coefficient here — add a term to
# the registry and read it back through these helpers, or the panel and the
# battle silently disagree (which is the whole reason the registry exists).
const AF_PASSIVE := AbilityFormulas.PASSIVE
const AF_ACTIVE  := AbilityFormulas.ACTIVE
const AF_ULT     := AbilityFormulas.ULTIMATE

func _ab(u: UnitBase, slot: String, id: String) -> int:
	return int(AbilityFormulas.value_of(u, slot, id))

func _abf(u: UnitBase, slot: String, id: String) -> float:
	return AbilityFormulas.value_of(u, slot, id)

# ── New class active skills ───────────────────────────────────────────────────

func _bloodhound_bite(caster: UnitBase, opponents: Array) -> void:
	var target := find_nearest_enemy(caster, opponents)
	if not target:
		return
	var dmg := _ab(caster, AF_ACTIVE, "dmg")
	target.take_damage(dmg, caster.current_element, caster)
	caster.damage_dealt += dmg
	caster.heal(int(float(dmg) * _abf(caster, AF_ACTIVE, "drain")))

func _bouncer_slam(caster: UnitBase, opponents: Array) -> void:
	var target := find_nearest_enemy(caster, opponents)
	if not target:
		return
	var dmg := _ab(caster, AF_ACTIVE, "dmg")
	var bonus: float = caster.get_meta("presence_bonus") if caster.has_meta("presence_bonus") else 0.0
	dmg = int(dmg * (1.0 + bonus))
	target.take_magic_damage(dmg, caster.current_element, caster)
	target.stun_time = _abf(caster, AF_ACTIVE, "stun")
	caster.damage_dealt += dmg
	_spawn_sprite_sheet_effect(
		"res://assets/using/effects_projectiles/bouncer_active.png",
		target.global_position, 64, 60, 12, Vector2(140, 140))

func _nemi_tidal_wave(caster: UnitBase, opponents: Array) -> void:
	var dmg := _ab(caster, AF_ULT, "dmg")
	var cx := caster.grid_position.x
	_spawn_skill_effect_sized(SkillEffect.Type.TIDAL_WAVE, caster.global_position, 100.0)

	# Hit all enemies in a 3-column strip (caster col ±1)
	for opp in opponents:
		if not (opp and is_instance_valid(opp)):
			continue
		if abs(opp.grid_position.x - cx) <= 1:
			opp.take_magic_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.ABSORBED, opp.global_position, 24.0)
			# Pushback: move 2 cells away from Nemi (in y direction)
			var push_y: int = sign(opp.grid_position.y - caster.grid_position.y)
			if push_y == 0: push_y = -1  # if same row, push north
			for _step in range(_ab(caster, AF_ULT, "push")):
				var next: Vector2i = opp.grid_position + Vector2i(0, push_y)
				if battle_grid.is_valid_position(next) and not battle_grid.is_cell_occupied(next):
					battle_grid.remove_unit(opp.grid_position)
					if battle_grid.place_unit(opp, next):
						opp.grid_position = next
						opp.position = _world_pos_for(opp, next)

func _headhunter_rapid_fire(caster: UnitBase) -> void:
	caster.rapid_fire_time = _abf(caster, AF_ACTIVE, "dur")

# ── Shauna active: kite away from nearest enemy, boost next attack ────────────
func _shauna_kite(caster: UnitBase, opponents: Array) -> void:
	var nearest := find_nearest_enemy(caster, opponents)
	if nearest:
		var dest := _best_retreat_cell(caster, nearest)
		if dest != Vector2i(-1, -1):
			start_unit_movement(caster, caster.grid_position, dest)
	caster.next_attack_boosted = true   # next auto hits for +50%

# Best open adjacent cell to retreat to, away from `threat`. Tries the exact
# "directly away" diagonal first (highest distance gain), but falls back to
# whichever other open neighbor still increases distance if that one is blocked
# or off the grid — e.g. hugging a wall (2026-07-06 user report: Kite would
# silently no-op near a wall, applying the attack-speed buff but never moving,
# because the old code only ever tried that single exact cell).
func _best_retreat_cell(unit: UnitBase, threat: UnitBase) -> Vector2i:
	var cur: Vector2i = unit.grid_position
	var cur_dist: float = cur.distance_to(threat.grid_position)
	var dirs: Array[Vector2i] = [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),
				Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]
	var best := Vector2i(-1, -1)
	var best_gain := 0.0
	for d in dirs:
		var c: Vector2i = cur + d
		if not battle_grid.is_valid_position(c) or battle_grid.is_cell_occupied(c):
			continue
		var gain: float = c.distance_to(threat.grid_position) - cur_dist
		if gain > best_gain:
			best_gain = gain
			best = c
	return best

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
		"windup_punch":
			# Wind-Up Punch: hit + 1s stun, damage scaling with the bot's own
			# elemental affinity (2026-07-07 user request — every mob skill's
			# damage should be tied to affinity, same pattern as bear_swipe/
			# troll_enrage below rather than a flat multiplier like brute_crush).
			if not tar: return
			# (2026-07-17: own-element self-buff removed — take_damage now applies
			# the attacker's off-affinity vs the target centrally, exactly once.)
			var wudm: int = int(float(caster.attack_damage) * caster.skill_damage_multiplier)
			tar.take_damage(wudm, caster.current_element, caster)
			caster.damage_dealt += wudm
			tar.stun_time = maxf(tar.stun_time, 1.0)
			_spawn_skill_effect_sized(SkillEffect.Type.WHIRLWIND, tar.global_position, 26.0)
		"tempest_arc":
			# Chain Discharge (Tempest Conduit, round-55 Lightning elite): hits the
			# nearest hero, then arcs from that hero to the next UNHIT hero within
			# TEMPEST_ARC_RANGE of the previous link, repeating up to
			# TEMPEST_ARC_MAX_JUMPS. Each jump is weaker than the last.
			# The chain walks hero→hero (not outward from the caster), which is what
			# makes it a formation check: what matters is how close the player's
			# units are TO EACH OTHER, not how close they are to the Conduit.
			if not tar: return
			var hit: Array = []
			var link: UnitBase = tar
			var arc_dmg: float = float(caster.magic_power) * caster.skill_damage_multiplier
			for jump in range(TEMPEST_ARC_MAX_JUMPS):
				if not (link and is_instance_valid(link) and link.current_hp > 0):
					break
				link.take_magic_damage(int(arc_dmg), caster.current_element, caster)
				caster.damage_dealt += int(arc_dmg)
				_spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, link.global_position, 26.0)
				hit.append(link)
				arc_dmg *= TEMPEST_ARC_FALLOFF
				# Next link: nearest not-yet-hit hero to the CURRENT link.
				var next_link: UnitBase = null
				var best_d := INF
				for opp in opponents:
					if not (opp and is_instance_valid(opp) and opp.current_hp > 0):
						continue
					if opp in hit:
						continue
					var d: float = link.grid_position.distance_to(opp.grid_position)
					if d <= TEMPEST_ARC_RANGE and d < best_d:
						best_d = d; next_link = opp
				if next_link == null:
					break   # nobody close enough — a spread formation stops the chain here
				link = next_link

		"tide_ward":
			# Tidal Ward (Tidecaller): hard-shields the most-wounded nearby ally —
			# itself included, so focusing it isn't a free kill either. Reuses
			# _lowest_hp_ally + _grant_shield, the same pair Sheildor/Stat Stealer
			# already use; shield is a flat % of the RECIPIENT's max HP so it stays
			# meaningful on a fat escort body and doesn't scale off the caller alone.
			var ward_tar := _lowest_hp_ally(caster, _allies, float(caster.skill_range), true)
			if not ward_tar: return
			_grant_shield(ward_tar, maxi(1, int(float(ward_tar.max_hp) * TIDE_WARD_SHIELD_PCT)))
			_spawn_skill_effect_sized(SkillEffect.Type.TIDE_WAVE, ward_tar.global_position, 30.0)

		"gale_shove":
			# Cyclone Shove (Gale Warden, round-15 Air elite): damage, then physically
			# SHOVE the victim one tile further away — the Air decade's formation
			# check. Displacement copies _rift_tear's remove→place→resync idiom
			# (including its cell_size == 1 guard: 2×2 bodies are never shoved, since
			# place_unit would have to validate a whole block and a half-moved large
			# unit is the one state the grid can't represent).
			if not tar: return
			var gdm: int = int(float(caster.attack_damage) * caster.skill_damage_multiplier)
			tar.take_damage(gdm, caster.current_element, caster)
			caster.damage_dealt += gdm
			_spawn_skill_effect_sized(SkillEffect.Type.WHIRLWIND, tar.global_position, 28.0)
			if tar.cell_size != 1 or not is_instance_valid(tar) or tar.current_hp <= 0:
				return
			# Push direction is derived from the two grid positions rather than
			# hardcoded to a side, so it stays correct whichever way the board is
			# oriented and whoever ends up owning this unit.
			var delta: Vector2i = tar.grid_position - caster.grid_position
			var step := Vector2i(signi(delta.x), signi(delta.y))
			if step == Vector2i.ZERO:
				return
			# Preferred landing tile, then single-axis fallbacks — a shove into a
			# wall or an occupied tile should still nudge sideways if it can, and
			# harmlessly do nothing if it can't (never a silent invalid placement).
			var candidates: Array[Vector2i] = [
				tar.grid_position + step,
				tar.grid_position + Vector2i(0, step.y),
				tar.grid_position + Vector2i(step.x, 0),
			]
			for dest: Vector2i in candidates:
				if dest == tar.grid_position or not battle_grid.is_valid_position(dest):
					continue
				if battle_grid.is_cell_occupied(dest):
					continue
				var from: Vector2i = tar.grid_position
				battle_grid.remove_unit(from)
				if battle_grid.place_unit(tar, dest):
					tar.grid_position = dest
					tar.position = _world_pos_for(tar, dest)
					# Cancel any in-flight step and drop the cached path, or the
					# mover would keep lerping toward a tile it no longer starts from.
					tar.is_moving = false
					tar.move_progress = 0.0
					unit_paths.erase(tar)
				else:
					# Placement refused — put it back exactly where it was.
					battle_grid.place_unit(tar, from)
				break

		"hydra_strike":
			# Serpent Strike: each head bites a DIFFERENT nearby target at once —
			# head count grows over time (see _hydra_regrow_tick), so this hits
			# more targets the longer the fight drags on. Damage scales with the
			# Hydra's own elemental affinity, same convention as every other mob
			# skill (bear_swipe/windup_punch above).
			var heads: int = int(caster.get_meta("hydra_heads", 1))
			# (self-buff removed — central affinity, see above)
			var hy_targets: Array = opponents.filter(func(o): return o and is_instance_valid(o))
			hy_targets.sort_custom(func(a, b): return caster.grid_position.distance_to(a.grid_position) < caster.grid_position.distance_to(b.grid_position))
			var hy_hit_count: int = mini(heads, hy_targets.size())
			for i in range(hy_hit_count):
				var hy_tar: UnitBase = hy_targets[i]
				var hydm: int = int(float(caster.attack_damage) * caster.skill_damage_multiplier)
				hy_tar.take_damage(hydm, caster.current_element, caster)
				caster.damage_dealt += hydm
				_spawn_skill_effect_sized(SkillEffect.Type.WHIRLWIND, hy_tar.global_position, 26.0)
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
			# Infestation passive: while packed with 2+ other rats the disease lingers
			# 50% longer (flag set each tick in _tick_mob_passive).
			var rat_dur: float = 4.5 if bool(caster.get_meta("rat_disease_boost", false)) else 3.0
			apply_burn(tar, float(caster.attack_damage) * 0.35, rat_dur, caster)
			_spawn_skill_effect_sized(SkillEffect.Type.BURN, tar.global_position, 20.0)
		"lizard_snipe":
			# Precision Shot: the lizard barely moves, so this high-multiplier
			# cooldown-gated snipe (not its auto-attack) is its real threat.
			if not tar: return
			var lzdm: int = int(float(caster.attack_damage) * caster.skill_damage_multiplier)
			tar.take_damage(lzdm, caster.current_element, caster)
			caster.damage_dealt += lzdm
			_spawn_skill_effect_sized(SkillEffect.Type.ARROW_RAIN, tar.global_position, 24.0)
		"bear_swipe":
			# Rending Swipe: modest hit (the Bear's whole identity is tanking, not
			# damage) that opens a bleed — the bleed tick rate DOUBLES on any
			# second the target is moving (see _tick_statuses/BLEED_MOVE_MULT), so
			# a bled target that keeps chasing/kiting bleeds out much faster than
			# one that just stands and fights. Both the hit and the bleed scale
			# with the Bear's own offensive affinity in its own element (2026-07-06
			# user request — an Ice Bear's swipe hits harder because it's more
			# affined with ice, not because of any target-element matchup).
			if not tar: return
			# (self-buff removed — central affinity; the bleed loses its element
			# scaling since DoTs are true damage and skip affinity by design.)
			var bswp: int = int(float(caster.attack_damage) * caster.skill_damage_multiplier)
			tar.take_damage(bswp, caster.current_element, caster)
			caster.damage_dealt += bswp
			apply_bleed(tar, float(caster.attack_damage) * 0.3, 4.0, caster)
			_spawn_skill_effect_sized(SkillEffect.Type.WHIRLWIND, tar.global_position, 30.0)
		"troll_enrage":
			# Enrage: picks a RANDOM friendly target in range — itself counts as
			# an eligible pick alongside its allies (2026-07-07 user correction;
			# an earlier version picked the highest-ATK ally, which wasn't
			# specified — targeting choices like this need direction, not
			# invention). The attack-speed RATIO scales with the Troll's own
			# offensive affinity in its own element; the 10s duration itself does
			# not scale, only the magnitude. 10s duration / 5s cooldown (see
			# skill_cooldown_max in EnemyFactory) is intentional: a Troll can keep
			# the buff rolling on 2 targets at once (itself + one other).
			var troll_aff: float = 1.0 + caster.offensive_affinity.get(caster.current_element, 0.0) / 100.0
			var enrage_pct: float = 0.35 * troll_aff
			var enrage_pool: Array = [caster]
			for a in _allies:
				if a and is_instance_valid(a) and a != caster \
						and caster.grid_position.distance_to(a.grid_position) <= float(caster.skill_range):
					enrage_pool.append(a)
			var enrage_tar: UnitBase = enrage_pool[randi() % enrage_pool.size()]
			enrage_tar.bonus_aspd_pct = maxf(enrage_tar.bonus_aspd_pct, enrage_pct)
			enrage_tar.bonus_aspd_time = maxf(enrage_tar.bonus_aspd_time, 10.0)
			_spawn_skill_effect_sized(SkillEffect.Type.CHI_BURST, enrage_tar.global_position, 32.0)

func _nemi_tide(caster: UnitBase, opponents: Array, allies: Array) -> void:
	var first := find_nearest_enemy(caster, opponents)
	if not first:
		return

	var dmg := _ab(caster, AF_ACTIVE, "dmg")
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
			current.take_magic_damage(dmg, caster.current_element, caster)
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
			opp.take_damage(dmg, caster.current_element, caster)

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
			opp.take_damage(dmg, caster.current_element, caster)
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
		target.take_damage(dmg, caster.current_element, caster)
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
			opp.take_magic_damage(dmg, caster.current_element, caster)

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
		caster.spawn_projectile(target, dmg, true)   # hybrid spellblade bolt — magic-typed
		_spawn_skill_effect(SkillEffect.Type.CHAOS_BOLT, target.global_position)

# ── New hero helpers ──────────────────────────────────────────────────────────

func _grant_shield(unit: UnitBase, amount: int) -> void:
	# Khagan puppet: no shielding while possessed (see heal() — same fairness
	# reasoning; a shielded puppet would be another wall route).
	if unit.has_meta("khagan_puppet"):
		return
	unit.current_shield += amount
	unit.shield_changed.emit(unit.current_shield)

# Stat Stealer ultimate: picks one random stat off the target and starts a
# 10-second drain (10% of the cast-time value per second — see _tick_statuses
# for the actual tick). Devastating if it lands on a carry's attack_damage;
# harmless if it lands on a tank's magic_power — the randomness is the point.
const STAT_STEAL_POOL: Array[String] = [
	"attack_damage", "crit_chance", "crit_damage", "attack_speed", "magic_power", "resistance",
]
# Balance 2026-07-24 (user request): a Stat Stealer can never drain more than
# this fraction of the target's cast-time snapshot, no matter how long the
# drain runs uninterrupted — see the floor_val cap in _tick_statuses.
const DRAIN_MAX_STEAL_PCT := 0.8
func _stat_steal_drain(caster: UnitBase, opponents: Array) -> void:
	var target: UnitBase = caster.target_unit if (caster.target_unit and is_instance_valid(caster.target_unit)) else find_nearest_enemy(caster, opponents)
	if not target:
		return
	var stat: String = STAT_STEAL_POOL[randi() % STAT_STEAL_POOL.size()]
	var snapshot: float = float(target.get(stat))
	target.drain_time = 10.0
	target.drain_stat = stat
	# 0.10 → 0.15/sec (2026-07-15 elite rebalance): SS owns round 25 now and a
	# 9-hero level-12 board shrugged off the slower drain.
	target.drain_per_sec = snapshot * 0.15
	target.drain_source = caster
	target.drain_stolen = 0.0
	target.drain_snapshot = snapshot   # caps total theft at DRAIN_MAX_STEAL_PCT of this (see _tick_statuses)
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

# ── Khagan: mind-control finale (timed-survival rework 2026-07-24) ─────────────
# Called from EnemyFactory.advance_khagan_phase() as Khagan's phase-2 body
# "dies". Seizes the player's SECOND-highest damage dealer and moves it into
# enemy_units — but as a FAIR set-piece, not an unkillable must-kill wall (the
# old design felt unfair: a geared carry turned against you at full strength,
# with sustain intact, at the moment you were weakest, could grind out a wipe
# with no counterplay). The rework makes it a bounded threat you WIN by
# outlasting:
#   • sustain stripped   — no self-heal / lifesteal / shields while possessed
#                          (heal() and _grant_shield() gate on the puppet meta),
#                          so a bruiser/healer can't wall you forever
#   • outgoing damage capped (KHAGAN_PUPPET_DMG_MULT) — a threat, not a chain-wipe
#   • seized at reduced HP (KHAGAN_PUPPET_HP_FRAC)     — bursting it is viable
#   • a survival TIMER (KHAGAN_POSSESS_SECONDS) — outlast it and control breaks
#     on its own; damaging the puppet drains the timer faster (see _process),
#     so burst is rewarded but never required.
# Requires >=2 living heroes so seizing your last one can't instantly defeat you;
# if that safety fails, Khagan just dies with no phase 3 this time.
func start_khagan_possession(khagan: UnitBase) -> void:
	var candidates: Array = player_units.filter(func(u): return u and is_instance_valid(u))
	if candidates.size() < 2:
		return
	# Take the SECOND-highest damage dealer this battle (2026-07-18 user spec).
	# Grabbing the #1 carry made runs end anticlimactically; #2 is a real threat
	# you still have your top carry to answer. Deterministic — no RNG.
	candidates.sort_custom(func(a, b): return a.damage_dealt > b.damage_dealt)
	var chosen: UnitBase = candidates[1]
	player_units.erase(chosen)
	enemy_units.append(chosen)
	chosen.is_player_unit = false
	chosen.set_meta("khagan_puppet", true)
	# Snapshot the stats we detune so end_khagan_possession can restore the hero
	# exactly (it survives the fight — this is a loan, not a death).
	chosen.set_meta("khagan_puppet_atk", chosen.attack_damage)
	chosen.set_meta("khagan_puppet_magic", chosen.magic_power)
	chosen.set_meta("khagan_puppet_regen", chosen.hp_regen)
	chosen.attack_damage = maxi(1, int(round(float(chosen.attack_damage) * KHAGAN_PUPPET_DMG_MULT)))
	chosen.magic_power   = int(round(float(chosen.magic_power) * KHAGAN_PUPPET_DMG_MULT))
	chosen.hp_regen      = 0.0
	# Cap HP so bursting is viable — but never HEAL a hero that entered phase 3
	# already wounded (min, not a straight set).
	chosen.current_hp    = maxi(1, mini(chosen.current_hp, int(round(float(chosen.max_hp) * KHAGAN_PUPPET_HP_FRAC))))
	chosen.current_shield = 0
	_khagan_puppet = chosen
	_khagan_timer  = KHAGAN_POSSESS_SECONDS
	if chosen.has_method("show_possession_icon"):
		chosen.show_possession_icon(load("res://assets/using/khagan_phase2.png"))
	action_logged.emit("Khagan's spirit seizes %s! Outlast the possession!" % chosen.unit_name, false)
	_spawn_skill_effect_sized(SkillEffect.Type.SHADOW_STRIKE, chosen.global_position, 56.0)

# Break the possession — from _process when the survival timer runs out, or from
# UnitBase/VisualUnit.die() the instant the puppet is burst to 0 HP. Restores the
# detuned stats, returns the hero to the player's side, and ends the fight in
# victory (freeing the puppet IS defeating Khagan). home_position is never
# touched during possession, so the between-round row heal tops it up like any
# other survivor. Deferred end_battle so the current tick loop finishes cleanly.
func end_khagan_possession(unit: UnitBase) -> void:
	if not unit.has_meta("khagan_puppet"):
		return
	unit.remove_meta("khagan_puppet")
	# Restore the loaned stats.
	if unit.has_meta("khagan_puppet_atk"):
		unit.attack_damage = int(unit.get_meta("khagan_puppet_atk"))
		unit.magic_power   = int(unit.get_meta("khagan_puppet_magic"))
		unit.hp_regen      = float(unit.get_meta("khagan_puppet_regen"))
		unit.remove_meta("khagan_puppet_atk")
		unit.remove_meta("khagan_puppet_magic")
		unit.remove_meta("khagan_puppet_regen")
	unit.current_hp = maxi(1, unit.current_hp)   # never return it dead
	if unit.has_method("hide_possession_icon"):
		unit.hide_possession_icon()
	enemy_units.erase(unit)
	if unit not in player_units:
		player_units.append(unit)
	unit.is_player_unit = true
	_khagan_puppet = null
	_khagan_timer  = 0.0
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
	var shield_amt: int = _ab(caster, AF_ACTIVE, "shield") \
		+ int(float(best_target.max_hp) * _abf(caster, AF_ACTIVE, "bonus"))
	_grant_shield(best_target, shield_amt)
	best_target.heal(int(float(best_target.max_hp) * _abf(caster, AF_ACTIVE, "heal")))
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
	var big_shield: int = _ab(caster, AF_ULT, "shield") \
		+ int(float(target.max_hp) * _abf(caster, AF_ULT, "bonus"))
	_grant_shield(target, big_shield)
	_grant_shield(caster, int(float(big_shield) * _abf(caster, AF_ULT, "self")))
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, target.global_position, 64.0)
	_spawn_skill_effect_sized(SkillEffect.Type.ABSORBED, caster.global_position, 48.0)
	action_logged.emit("%s leaps to protect %s!" % [caster.unit_name, target.unit_name], caster.is_player_unit)

# Lordee skill: Ground Slam — AoE around nearest enemy, 4-hex radius
func _lordee_ground_slam(caster: UnitBase, opponents: Array) -> void:
	var center := find_nearest_enemy(caster, opponents)
	if not center:
		return
	var dmg := _ab(caster, AF_ACTIVE, "dmg")
	_spawn_skill_effect_sized(SkillEffect.Type.WHIRLWIND, center.global_position, 80.0)
	for opp in opponents:
		if not (opp and is_instance_valid(opp)):
			continue
		if center.grid_position.distance_to(opp.grid_position) <= 2.0:
			opp.take_damage(dmg, caster.current_element, caster)
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
	# Damage + permanently steal a slice of the target's attack_damage
	var dmg: int = _ab(caster, AF_ULT, "dmg")
	target.take_damage(dmg, caster.current_element, caster)
	caster.damage_dealt += dmg
	var stolen_atk: int = int(float(target.attack_damage) * _abf(caster, AF_ULT, "steal"))
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
	var dmg := _ab(caster, AF_ULT, "dmg")
	_spawn_skill_effect_sized(SkillEffect.Type.INFERNO, caster.global_position, 72.0)
	for opp in opponents:
		if not (opp and is_instance_valid(opp)):
			continue
		if caster.grid_position.distance_to(opp.grid_position) <= float(caster.ultimate_range):
			opp.take_magic_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg
	for _i in range(_ab(caster, AF_ULT, "bats")):
		_spawn_summon(caster, UnitBase.UnitClass.BAT)

# Zombie/Bat basic claw — extra attack on nearest enemy
func _summon_basic_attack(caster: UnitBase, opponents: Array) -> void:
	var target := find_nearest_enemy(caster, opponents)
	if not target:
		return
	var dmg := int(float(caster.attack_damage) * caster.skill_damage_multiplier)
	target.take_damage(dmg, caster.current_element, caster)
	caster.damage_dealt += dmg

# Spawn a summoned unit in front of the summoner
# Same bottom-4/top-4 team-zone split as VisualUnit._is_valid_placement — the
# neutral middle row(s) belong to neither side, so no summon spawn should ever
# be allowed to resolve there regardless of which "forward offset" search
# found it.
func _in_team_zone(is_player: bool, pos: Vector2i) -> bool:
	var gh: int = battle_grid.grid_height if battle_grid else 9
	return (pos.y >= gh - 4 and pos.y < gh) if is_player else (pos.y >= 0 and pos.y < 4)

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
		# A front-row summoner's "forward" cell can land ON the neutral middle
		# row — is_valid_position only checks grid BOUNDS, not team zones, so
		# that let summons spawn stranded on the dividing line (2026-07-23).
		if battle_grid.is_valid_position(candidate) and not battle_grid.is_cell_occupied(candidate) \
				and _in_team_zone(summoner.is_player_unit, candidate):
			spawn_cell = candidate
			break
	if spawn_cell == Vector2i(-1, -1):
		return  # no room
	var summon: VisualUnit = UnitFactory.create_unit(summon_class, summoner.current_element, summoner.is_player_unit)
	# Summons ride their summoner's level (2026-07-17: zombies/bats spawned at
	# level 1 forever, so Necro fell off a cliff late-game). Ant Hill's ants
	# deliberately stay level 1 — they spawn via _spawn_ant, not here.
	if summoner.level > 1:
		summon.set_level(summoner.level)
	# Necro's minions scale with his MAGIC POWER — the more MP-focused/buffed
	# Necro is, the beefier and harder-hitting his risen dead (2026-07-23 user
	# request). Applied on top of the level scaling above. Scoped to Necro so
	# other summoners keep their own tuning.
	if summoner.unit_class == UnitBase.UnitClass.NECRO:
		var mag: int = summoner.magic_power
		summon.max_hp += mag * 4
		summon.current_hp = summon.max_hp
		summon.attack_damage += int(mag * 0.5)
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

# ── Ant Hill: periodic spawn (DPS check) — tune in balance.gd ─────────────────
# ── Mirrorplate Warden (round-85 elite) knobs ───────────────────────────────
# A single reflected hit can never cost more than this share of the attacker's
# max HP — the bound that keeps a percentage reflect from scaling perfectly with
# player power. See the reasoning in propagate_damage_links.
# NOTE this is a PER-HIT cap, and in an autobattler hits are near-continuous —
# the sustained cost is this number times the attacker's attacks per second, not
# this number. An early 0.04 read as "4% max HP", but at ~2 attacks/sec it was
# really ~8% max HP PER SECOND, which killed a level-55 and a level-65 team at
# exactly the same rate. 0.01 is the honest "small tax per swing" value.
# Final value 0.005: at 0.01 round 85 still lost 2 of 3 while its immediate
# neighbours 84/86 both won 3 of 3 with the same team — i.e. the elite was
# harder than the waves around it for the wrong reason. Halving it again lands
# the encounter alongside its neighbours instead of above them.
const MIRROR_REFLECT_MAX_HP_PCT := 0.005

# ── Aspect Devourer (round-95 capstone elite) knobs ─────────────────────────
# 8s per aspect: long enough that a swap is a readable event the player can plan
# around, short enough that no single element is ever the "right" answer for the
# whole fight. Starts on NORMAL (its spawn element) and steps through the rest.
const ASPECT_CYCLE_INTERVAL := 8.0
# First devour lands early, same reasoning as MAGMA_PULSE_FIRST_DELAY: the
# mechanic should announce itself while the player can still react to it, and it
# keeps the passive inside the probe's 3s verification window.
const ASPECT_FIRST_DELAY := 2.5
const ASPECT_CYCLE: Array[int] = [
	UnitBase.Element.NORMAL, UnitBase.Element.FIRE, UnitBase.Element.WATER,
	UnitBase.Element.EARTH, UnitBase.Element.AIR, UnitBase.Element.LIGHTNING,
]

# ── Tempest Conduit (round-55 Lightning elite) knobs ────────────────────────
# Arc range 2 tiles: adjacent-ish only, so a deliberately spread formation
# genuinely breaks the chain instead of merely shortening it. 25% falloff per
# jump and a 5-jump ceiling keep a fully clumped team punished but not deleted.
const TEMPEST_ARC_RANGE := 2.0
const TEMPEST_ARC_FALLOFF := 0.75
const TEMPEST_ARC_MAX_JUMPS := 5

# ── Magma Heart (round-45 Fire elite) knobs ─────────────────────────────────
# Pulse every 6s, +18% of magic_power in burn DPS per pulse, capped at 8 pulses
# (~48s in). apply_burn takes the MAX of the existing and new dps rather than
# stacking, so the escalating value is what makes later pulses matter at all.
const MAGMA_PULSE_INTERVAL := 6.0
const MAGMA_PULSE_DPS_PCT := 0.18
const MAGMA_PULSE_MAX_STACKS := 8
# The FIRST eruption comes early rather than a full interval in, so the mechanic
# telegraphs itself in the opening seconds instead of ambushing a team that has
# already committed. Also keeps the passive inside the probe's 3s window, so it
# stays a verified ability instead of an EXPECTED_SILENT excuse.
const MAGMA_PULSE_FIRST_DELAY := 2.0

# ── Terracotta Colossus (round-35 Earth elite) knobs ────────────────────────
# +4 armor/sec to a +160 ceiling: reached in 40s, which is deliberately longer
# than the ~50s neighbouring waves take to clear — so a competent team never
# sees the ceiling, and a slow one gets punished progressively rather than
# hitting a cliff. Armor is the diminishing-returns curve (100/(100+armor)), so
# even the capped value is a ~60% reduction, never immunity.
const TERRACOTTA_ARMOR_PER_SEC := 4.0
const TERRACOTTA_ARMOR_CAP := 160.0

# ── Tidecaller (round-25 Water elite) knobs ─────────────────────────────────
# Tuned against the ~9-hero level-12 team the Stat Stealer's round-25 encounter
# was measured with. Kept modest on purpose: a healer stacked into a regen-heavy
# wave is the documented cause of the high-round combat stalls (see the Lightning
# decade notes in wave_data), so the elite escort stays light and this stays a
# pressure source rather than an outright sustain wall.
const TIDE_FONT_RANGE := 4.0            # tiles
const TIDE_FONT_PCT_PER_SEC := 0.015    # 1.5% of each nearby ally's max HP per second
const TIDE_WARD_SHIELD_PCT := 0.20      # shield = 20% of the recipient's max HP

const ANT_HILL_SPAWN_INTERVAL := Balance.ANT_HILL_SPAWN_INTERVAL
const ANT_HILL_MAX_ANTS := Balance.ANT_HILL_MAX_ANTS

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

# ── Hydra: time-based head regrowth (the wave-30 boss's whole identity) ──────
# Every HYDRA_REGROW_INTERVAL seconds survived, the Hydra grows another head,
# up to HYDRA_MAX_HEADS — its "Serpent Strike" skill (see the "hydra_strike"
# case in _use_mob_skill above) then bites that many DIFFERENT targets at once,
# and its own attack_damage rises a bit too. A slow fight snowballs into being
# hit from several sides simultaneously — the pressure is time, not HP.
const HYDRA_REGROW_INTERVAL := 20.0
const HYDRA_MAX_HEADS := 4

# Skyrender (wave-20 Air boss) — Cyclone Ascent cycle. Fixed windows, not
# HP thresholds, so the boss can never become unreachable at the worst possible
# moment. Grounded is deliberately the LONGER half: a melee-only team is slowed
# by the fight, not locked out of it.
const SKYRENDER_GROUND_TIME := 8.0
const SKYRENDER_ALOFT_TIME := 4.0

# Drowned Maw (wave-30 Water boss) — Riptide. A board-wide aura that scales all
# healing the player's units RECEIVE. Board-wide rather than a radius on purpose:
# the fight asks "does your comp fall apart without sustain", which is a DRAFT
# question the player answers before the battle, and a radius would turn it into
# an in-battle positioning puzzle they have no lever for. Refreshed every tick
# and decayed in _tick_status, so it lifts the moment the boss dies.
const DROWNED_HEAL_MULT := 0.35     # healing received while Riptide holds
const DROWNED_AURA_REFRESH := 1.0   # seconds of debuff written per tick

# Emberhollow (wave-50 Fire boss) — returns ONCE at this fraction of max HP if
# either Ember Heart is still alive when the body drops. Bounded to one revival
# on purpose: an unbounded "kill the adds or it never dies" loop is the kind of
# unwinnable wall the boss-fairness rule exists to prevent.
const EMBERHOLLOW_REVIVE_HP := 0.5

# Arcfang (wave-60 Lightning boss) — Thunder Run. Every interval it teleports to
# whoever is doing the most damage on the other side, ignoring the frontline in
# between. The question: is your carry protected, or is it standing alone?
#
# Fair per the boss-fairness rule: it takes nothing away from the player and
# removes no control. It is a THREAT you build around before the fight — bodyguard
# the carry, spread out, make the carry tanky — and it is bounded (a fixed
# interval, never an HP trigger, so it can't ambush you at your weakest moment).
const ARCFANG_BLINK_INTERVAL := 10.0

# Gravekeeper (wave-90 mixed boss) — Grave Call. A hero that falls gets back up
# on the Gravekeeper's side as a detuned shade. The question: can you avoid
# losses at all, when every loss compounds?
#
# This is the one mechanic in the game that turns the player's own units against
# them, so it is deliberately built to avoid the Khagan possession trap (see the
# boss-fairness rule): it only ever uses heroes who are ALREADY DEAD — it never
# seizes a living unit, never removes control of anything the player still has,
# and takes nothing away that wasn't already lost. On top of that the shade is
# detuned hard, gets no sustain, and the count is capped so a bad opening can't
# snowball into an unwinnable wall.
const GRAVE_SHADE_HP := 0.5      # of the fallen hero's max HP
const GRAVE_SHADE_DMG := 0.6     # of its attack
const GRAVE_SHADE_MAX := 3       # simultaneous shades — the anti-snowball cap

# Is a living Gravekeeper fighting against `side`? Drives the raise check in
# VisualUnit.die().
func gravekeeper_active(for_player_unit: bool) -> bool:
	var foes: Array = enemy_units if for_player_unit else player_units
	for u in foes:
		if u and is_instance_valid(u) and u.has_meta("gravekeeper") \
				and u.current_hp > 0 and not u._is_dying:
			return true
	return false

# Raise `dead` as a shade on the Gravekeeper's side, standing where it fell.
# Called from VisualUnit.die() while the corpse still holds its cell, so the
# shade takes a free NEIGHBOURING cell rather than the corpse's own.
#
# Team zones are deliberately NOT enforced here (unlike spawn_slime_split): a
# shade rises where the body dropped, which is in the player's half. Zones only
# constrain opening placement — units cross freely once fighting starts.
func gravekeeper_raise_shade(dead: UnitBase) -> void:
	if battle_grid == null or dead == null:
		return
	if dead.has_meta("grave_shade"):
		return                       # a shade falling again raises nothing
	var army: Array = enemy_units if dead.is_player_unit else player_units
	var alive_shades := 0
	for u in army:
		if u and is_instance_valid(u) and u.has_meta("grave_shade") and u.current_hp > 0:
			alive_shades += 1
	if alive_shades >= GRAVE_SHADE_MAX:
		return
	var cell := Vector2i(-1, -1)
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var c: Vector2i = dead.grid_position + offset
		if battle_grid.is_valid_position(c) and not battle_grid.is_cell_occupied(c):
			cell = c
			break
	if cell == Vector2i(-1, -1):
		return
	# Rebuilt from the class rather than deep-copied: a copy would drag along
	# equipment, relic hooks, synergy buffs and status — exactly the gear-scaled
	# threat that made Khagan's possession feel unfair.
	var shade: VisualUnit = UnitFactory.create_unit(dead.unit_class, dead.current_element, false)
	if shade == null:
		return
	if dead.level > 1:
		shade.set_level(dead.level)
	shade.unit_name = "Shade of %s" % dead.unit_name
	shade.is_player_unit = not dead.is_player_unit
	shade.is_summoned = true
	shade.gold_reward = 0
	shade.crystal_reward = 0
	shade.xp_reward = 0
	shade.max_hp = maxi(1, int(shade.max_hp * GRAVE_SHADE_HP))
	shade.current_hp = shade.max_hp
	shade.attack_damage = maxi(1, int(shade.attack_damage * GRAVE_SHADE_DMG))
	shade.magic_power = int(shade.magic_power * GRAVE_SHADE_DMG)
	shade.hp_regen = 0.0             # no sustain, same as the Khagan puppet
	shade.set_meta("grave_shade", true)
	shade.grid_position = cell
	if not battle_grid.place_unit(shade, cell):
		shade.queue_free()
		return
	shade.battle_manager = self
	if shade.is_player_unit:
		player_units.append(shade)
	else:
		enemy_units.append(shade)
	unit_summoned.emit(shade)
	shade.position = _world_pos_for(shade, cell)
	action_logged.emit("%s rises again — bound to the Gravekeeper!" % dead.unit_name,
			shade.is_player_unit)

# Is at least one Ember Heart still fighting on Emberhollow's side? Drives the
# revive check in VisualUnit.die(). Deliberately scans the live army rather than
# tracking spawn-time references — Hearts can die in any order, and a freed unit
# must not keep the boss alive.
# Teleport Arcfang beside whoever is hurting it most. Unlike _rift_tear's
# displacement (which bails on cell_size != 1), this has to move a 2×2 body, so
# it asks Pathfinding for the nearest ORIGIN whose whole footprint fits rather
# than a single free cell.
#
# Ordered remove → place → restore-on-failure: computing the destination while
# still on the grid would let Arcfang's own cells block a spot next to the
# target, and a failed place() after an unguarded remove() would leave the boss
# off-grid entirely (invisible to movement and occupancy for the rest of the fight).
func _arcfang_blink(unit: UnitBase, opponents: Array) -> void:
	if battle_grid == null:
		return
	# The "carry": most damage dealt so far, falling back to raw attack at the
	# opening blink when nobody has dealt damage yet.
	var best: UnitBase = null
	var best_dmg: int = -1
	for opp in opponents:
		if not (opp and is_instance_valid(opp) and opp.current_hp > 0):
			continue
		var score: int = opp.damage_dealt if opp.damage_dealt > 0 else opp.attack_damage
		if score > best_dmg:
			best_dmg = score
			best = opp
	if best == null:
		return
	var origin: Vector2i = unit.grid_position
	battle_grid.remove_unit(origin)
	var dest: Vector2i = Pathfinding.find_nearest_free_origin(best.grid_position, battle_grid, unit)
	if dest == Vector2i(-1, -1) or not battle_grid.place_unit(unit, dest):
		battle_grid.place_unit(unit, origin)   # put it back exactly where it was
		return
	unit.grid_position = dest
	unit.position = _world_pos_for(unit, dest)
	unit.is_moving = false
	unit_paths.erase(unit)                     # stale path would drag it back
	_spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, unit.global_position, 42.0)
	action_logged.emit("%s flashes across the field onto %s!" % [unit.unit_name, best.unit_name],
			unit.is_player_unit)

func emberhollow_hearts_alive(boss: UnitBase) -> bool:
	var army: Array = player_units if boss.is_player_unit else enemy_units
	for u in army:
		if u and is_instance_valid(u) and u.has_meta("ember_heart") \
				and u.current_hp > 0 and not u._is_dying:
			return true
	return false
const HYDRA_ATK_PER_HEAD := 0.10   # +10% attack_damage per extra head beyond the first

func _hydra_regrow_tick(unit: UnitBase, dt: float) -> void:
	var heads: int = int(unit.get_meta("hydra_heads", 1))
	if heads >= HYDRA_MAX_HEADS:
		return
	var accum: float = float(unit.get_meta("hydra_regrow_accum", 0.0)) + dt
	if accum < HYDRA_REGROW_INTERVAL:
		unit.set_meta("hydra_regrow_accum", accum)
		return
	heads += 1
	unit.set_meta("hydra_heads", heads)
	unit.set_meta("hydra_regrow_accum", 0.0)
	unit.attack_damage = int(round(float(unit.attack_damage) * (1.0 + HYDRA_ATK_PER_HEAD)))
	var elem_name: String = EnemyFactory.HYDRA_ELEMENT_NAMES.get(unit.current_element, "")
	unit.unit_name = "%s Hydra (%d Heads)" % [elem_name, heads]
	action_logged.emit("Another head grows from the Hydra! (%d heads now)" % heads, false)
	_spawn_skill_effect_sized(SkillEffect.Type.WHIRLWIND, unit.global_position, 40.0)

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
		if battle_grid.is_valid_position(candidate) and not battle_grid.is_cell_occupied(candidate) \
				and _in_team_zone(hill.is_player_unit, candidate):
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

# Slime "Split" passive: when a slime dies, spawn up to two smaller slimes on
# free cells around it. Children are marked so they never split again (one
# generation) and are summoned (no gold/crystal/xp rewards, so splitting can't be
# farmed). Called from VisualUnit.die() while the corpse is still on the grid.
func spawn_slime_split(parent: UnitBase) -> void:
	if not (parent and is_instance_valid(parent) and battle_grid):
		return
	if parent.has_meta("slime_split_child"):
		return   # already a child — do not split further
	var search_offsets: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	var spawned := 0
	for offset in search_offsets:
		if spawned >= 2:
			break
		var cell: Vector2i = parent.grid_position + offset
		if not (battle_grid.is_valid_position(cell) and not battle_grid.is_cell_occupied(cell) \
				and _in_team_zone(parent.is_player_unit, cell)):
			continue
		var child: VisualUnit = EnemyFactory._create_slime(parent.current_element, parent.level)
		child.remove_meta("mob_passive")          # children never re-split
		child.set_meta("slime_split_child", true)
		child.is_summoned = true
		child.summon_owner = parent
		child.is_player_unit = parent.is_player_unit
		child.gold_reward = 0
		child.crystal_reward = 0
		child.xp_reward = 0
		child.max_hp = maxi(1, int(parent.max_hp * 0.4))
		child.current_hp = child.max_hp
		child.attack_damage = maxi(1, int(parent.attack_damage * 0.6))
		child.magic_power = int(parent.magic_power * 0.6)
		child.grid_position = cell
		if battle_grid.place_unit(child, cell):
			if child.is_player_unit:
				player_units.append(child)
			else:
				enemy_units.append(child)
			unit_summoned.emit(child)
			child.position = battle_grid.grid_to_world(cell)
			spawned += 1
		else:
			child.queue_free()
	if spawned > 0:
		action_logged.emit("%s splits apart!" % parent.unit_name, parent.is_player_unit)

# Cloven Titan (wave-40 Earth boss): its death splits it into two 1×1 halves.
# Called from VisualUnit.die() while the corpse is still on the grid, exactly
# like spawn_slime_split — but a 2×2 parent occupies (x..x+1, y..y+1), so the
# slime's immediate-neighbour ring would try to place children INSIDE the
# parent's own still-registered footprint. This searches the ring OUTSIDE that
# block instead.
#
# The halves carry no rewards and can never split again, so the fight can't be
# farmed and can't cascade — the boss's own death already paid out normally.
const CLOVEN_HALF_HP := 0.45      # of the parent's max, each
const CLOVEN_HALF_ATK := 0.7      # of the parent's attack, each
func spawn_cloven_halves(parent: UnitBase) -> void:
	if not (parent and is_instance_valid(parent) and battle_grid):
		return
	if parent.has_meta("cloven_half"):
		return   # already a half — one generation only
	var anchor: Vector2i = parent.grid_position
	# Ring immediately outside the parent's 2×2 block, nearest cells first.
	var ring: Array[Vector2i] = [
		anchor + Vector2i(-1, 0), anchor + Vector2i(2, 0),
		anchor + Vector2i(-1, 1), anchor + Vector2i(2, 1),
		anchor + Vector2i(0, -1), anchor + Vector2i(1, -1),
		anchor + Vector2i(0, 2),  anchor + Vector2i(1, 2),
		anchor + Vector2i(-1, -1), anchor + Vector2i(2, 2),
	]
	var spawned := 0
	for cell in ring:
		if spawned >= 2:
			break
		if not (battle_grid.is_valid_position(cell) and not battle_grid.is_cell_occupied(cell) \
				and _in_team_zone(parent.is_player_unit, cell)):
			continue
		var half: VisualUnit = EnemyFactory.create_cloven_titan(parent.level)
		half.unit_name = "Cloven Half"
		half.cell_size = 1                      # a half is not a colossus
		half.remove_meta("cloven_split")         # never splits again
		half.set_meta("cloven_half", true)
		half.is_summoned = true
		half.summon_owner = parent
		half.is_player_unit = parent.is_player_unit
		half.is_boss = false
		half.gold_reward = 0
		half.crystal_reward = 0
		half.xp_reward = 0
		half.max_hp = maxi(1, int(parent.max_hp * CLOVEN_HALF_HP))
		half.current_hp = half.max_hp
		half.attack_damage = maxi(1, int(parent.attack_damage * CLOVEN_HALF_ATK))
		half.magic_power = int(parent.magic_power * CLOVEN_HALF_ATK)
		half.grid_position = cell
		if battle_grid.place_unit(half, cell):
			if half.is_player_unit:
				player_units.append(half)
			else:
				enemy_units.append(half)
			unit_summoned.emit(half)
			half.position = battle_grid.grid_to_world(cell)
			spawned += 1
		else:
			half.queue_free()
	if spawned > 0:
		action_logged.emit("%s cracks apart — the halves keep coming!" % parent.unit_name,
				parent.is_player_unit)

# A unit still in the fight. current_hp <= 0 is the reliable "dead" signal for
# BOTH UnitBase and VisualUnit: every cheat-death path (Phoenix Pact, Undying,
# Khagan possession, phase transforms) restores HP to >= 1 before returning, so
# nothing legitimately sits at 0 while alive.
func _is_alive(u) -> bool:
	return u != null and is_instance_valid(u) and u.current_hp > 0

func check_battle_end() -> void:
	# Drop the dead. This used to filter on is_instance_valid ALONE, which
	# silently depended on VisualUnit.die() calling queue_free(): player heroes
	# are now parked instead of freed (round-end revival, 2026-07-24), so a
	# fallen hero stayed "valid" forever and never left these arrays — it kept
	# getting ticked, attacked, and targeted as an invisible ghost, and
	# player_units could never empty so a team wipe never registered as a loss.
	player_units = player_units.filter(_is_alive)
	enemy_units = enemy_units.filter(_is_alive)

	if enemy_units.is_empty():
		end_battle(true)
	elif player_units.is_empty():
		end_battle(false)

func end_battle(player_won: bool) -> void:
	# Idempotent: the Khagan possession-break path removes the puppet from
	# enemy_units AND call_deferred("end_battle") — so check_battle_end can fire
	# end_battle synchronously the same frame, then the deferred call fires again
	# on idle. Guard so battle_ended emits exactly once (double-emit would double
	# the round-advance / reward flow in main_game._on_battle_ended).
	if not battle_active:
		return
	battle_active = false
	_clear_board_effects()
	afterimage_actor = null
	afterimage_time = 0.0
	battle_ended.emit(player_won)
	# State transition is handled by _on_battle_ended in main_game.gd

func move_unit_towards_with_pathfinding(unit: UnitBase, target_pos: Vector2i, dt: float = 0.0) -> void:
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
		var new_path = Pathfinding.find_path(current_pos, target_pos, battle_grid, 500, unit)
		if new_path.is_empty():
			# PERF (2026-07-04): these [Path] prints fired EVERY FRAME for every
			# blocked/boxed-in unit on a crowded board — console I/O + string
			# formatting was a real chunk of the 15+ unit frame time. Debug-only.
			if PATH_DEBUG: print("[Path] NO PATH from %s to %s" % [current_pos, target_pos])
			_note_stuck(unit, current_pos, target_pos, dt)
			return
		if new_path.size() > 0 and new_path[0] == current_pos:
			new_path.remove_at(0)
		unit_paths[unit] = new_path
		if PATH_DEBUG: print("[Path] found len=%d first=%s" % [new_path.size(), new_path[0] if new_path.size() > 0 else "EMPTY"])

	var path = unit_paths[unit]
	if path.is_empty():
		if PATH_DEBUG: print("[Path] path empty after cache")
		_note_stuck(unit, current_pos, target_pos, dt)
		return

	var next_pos = path[0]
	if not Pathfinding.is_origin_free(next_pos, battle_grid, unit):
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
		var sidestep := _find_sidestep(unit, current_pos, target_pos)
		if sidestep != Vector2i(-1, -1):
			unit_paths.erase(unit)   # cached route no longer matches from here — replan clean next tick
			_stuck_timers.erase(unit)
			if not unit.is_moving:
				start_unit_movement(unit, current_pos, sidestep)
			return
		if PATH_DEBUG: print("[Path] next_pos %s blocked" % [next_pos])
		unit_paths.erase(unit)
		_note_stuck(unit, current_pos, target_pos, dt)
		return

	_stuck_timers.erase(unit)
	if not unit.is_moving:
		start_unit_movement(unit, current_pos, next_pos)

# Tracks how long `unit` has failed to take a step. Past STUCK_ESCAPE_SECONDS,
# tries a wider sidestep search that ignores the "must be an improvement"
# rule — the escape hatch for two footprint>1 units parked flush against each
# other, where EVERY immediate-ring origin overlaps the other unit's cells on
# BOTH sides every single frame, so normal sidestep and normal A* replanning
# both keep failing in lockstep forever (2026-07-24 user report: two Hill
# Giants frozen solid until one died and freed the other).
func _note_stuck(unit: UnitBase, current_pos: Vector2i, target_pos: Vector2i, dt: float) -> void:
	var t: float = float(_stuck_timers.get(unit, 0.0)) + dt
	if t < STUCK_ESCAPE_SECONDS:
		_stuck_timers[unit] = t
		return
	var escape := _find_sidestep_wide(unit, current_pos, target_pos, STUCK_ESCAPE_RADIUS)
	if escape != Vector2i(-1, -1):
		_stuck_timers.erase(unit)
		unit_paths.erase(unit)
		if not unit.is_moving:
			start_unit_movement(unit, current_pos, escape)
	else:
		_stuck_timers[unit] = t   # still nothing even at wide radius — keep counting, try again next tick

# BFS outward from `current_pos` (ring by ring, up to `radius`) for the first
# origin the unit's whole footprint fits on — unlike _find_sidestep this does
# NOT require the cell to be closer to target_pos, since the whole point is
# escaping a knot no 1-ring, improvement-only search can break.
func _find_sidestep_wide(unit: UnitBase, current_pos: Vector2i, target_pos: Vector2i, radius: int) -> Vector2i:
	var visited: Dictionary = {current_pos: true}
	var frontier: Array[Vector2i] = [current_pos]
	for _ring in range(radius):
		var next_frontier: Array[Vector2i] = []
		for pos in frontier:
			for neighbor in Pathfinding.get_all_neighbors(pos):
				if visited.has(neighbor) or not battle_grid.is_valid_position(neighbor):
					continue
				visited[neighbor] = true
				next_frontier.append(neighbor)
				if Pathfinding.is_origin_free(neighbor, battle_grid, unit):
					return neighbor
		frontier = next_frontier
	return Vector2i(-1, -1)

# Picks the free neighbor of `current_pos` that gets closest to `target_pos`
# (Chebyshev distance), but only if it's an actual improvement over staying
# put — returns Vector2i(-1,-1) if every free neighbor is equal or farther
# (better to wait one tick than wander away from the goal). Footprint-aware:
# a 2×2 unit only sidesteps to origins its whole body fits on.
func _find_sidestep(unit: UnitBase, current_pos: Vector2i, target_pos: Vector2i) -> Vector2i:
	# Body-to-body, same as the range check: origin distance would tell a 2×2 unit
	# that shuffling sideways is an "improvement" when its body is already flush.
	var best_dist: int = _rect_dist(current_pos, unit.cell_size, target_pos, 1)
	var best: Vector2i = Vector2i(-1, -1)
	for neighbor in Pathfinding.get_neighbors(current_pos, battle_grid):
		if not Pathfinding.is_origin_free(neighbor, battle_grid, unit):
			continue
		var d: int = _rect_dist(neighbor, unit.cell_size, target_pos, 1)
		if d < best_dist:
			best_dist = d
			best = neighbor
	return best

func add_projectile(projectile: Projectile) -> void:
	if projectile_container:
		projectile_container.add_child(projectile)

# World position for a unit anchored at grid_pos. 2×2 units are centred on the
# middle of their 2×2 block (half-cell offset) so they don't snap to a single cell.
func _world_pos_for(unit: UnitBase, grid_pos: Vector2i) -> Vector2:
	var w: Vector2 = battle_grid.grid_to_world(grid_pos)
	# Centre any multi-cell body on its own block. Generalised from "== 2" to an
	# N×N formula 2026-07-29 for the 3×3 Architect; identical result at size 2.
	if unit.cell_size > 1:
		var off: float = battle_grid.cell_size * (unit.cell_size - 1) * 0.5
		w += Vector2(off, off)
	return w

func start_unit_movement(unit: UnitBase, from_pos: Vector2i, to_pos: Vector2i) -> void:
	unit.is_moving = true
	unit.move_start_pos = _world_pos_for(unit, from_pos)
	unit.move_target_pos = _world_pos_for(unit, to_pos)
	unit.move_progress = 0.0
	unit.target_grid_pos = to_pos
	# Drives the walk_south/north/east/west pick in VisualUnit._update_animation().
	unit.last_move_direction = unit.move_target_pos - unit.move_start_pos

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

	# Bleed damage-over-time — Bear's Rending Swipe. Moving while bled reopens
	# the wound: the tick rate doubles for any tick where the unit is_moving,
	# so standing still to fight is the way to mitigate it (2026-07-06 user request).
	if unit.bleed_time > 0.0:
		unit.bleed_time -= dt
		var bleed_rate: float = unit.bleed_dps * (BLEED_MOVE_MULT if unit.is_moving else 1.0)
		unit.bleed_accum += bleed_rate * dt
		if unit.bleed_accum >= 1.0:
			var bwhole: int = int(unit.bleed_accum)
			unit.bleed_accum -= float(bwhole)
			var blsrc = unit.bleed_source
			unit.take_damage(bwhole, UnitBase.Element.NORMAL, blsrc, true)
			if blsrc and is_instance_valid(blsrc):
				blsrc.damage_dealt += bwhole
		if unit.bleed_time <= 0.0:
			unit.bleed_dps = 0.0
			unit.bleed_accum = 0.0
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
			var hard_floor: float = 1.0 if stat == "crit_damage" else (0.05 if stat == "attack_speed" else 0.0)
			# Balance 2026-07-24 (user request): drain_time*drain_per_sec adds up
			# to 150% of the snapshot over the full 10s, so an uninterrupted
			# drain could otherwise fully zero the stat well before it expires.
			# Cap total theft at DRAIN_MAX_STEAL_PCT of the cast-time snapshot —
			# whichever floor is HIGHER (snapshot-based or the existing hard
			# floor) wins, so this never lowers the pre-existing safety floors.
			var floor_val: float = maxf(hard_floor, unit.drain_snapshot * (1.0 - DRAIN_MAX_STEAL_PCT))
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
	if unit.heal_cut_time > 0.0: unit.heal_cut_time -= dt   # Riptide (Drowned Maw)
	if unit.bonus_aspd_time > 0.0:
		unit.bonus_aspd_time -= dt
		if unit.bonus_aspd_time <= 0.0: unit.bonus_aspd_pct = 0.0
	if unit.weakened_time > 0.0:
		unit.weakened_time -= dt
		if unit.weakened_time <= 0.0: unit.weakened_pct = 0.0
	if unit.outgoing_dmg_time > 0.0:
		unit.outgoing_dmg_time -= dt
		if unit.outgoing_dmg_time <= 0.0: unit.outgoing_dmg_mult = 1.0
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

const BLEED_MOVE_MULT := 2.0   # bleed tick rate while is_moving — see _tick_statuses
func apply_bleed(target: UnitBase, dps: float, dur: float, source) -> void:
	if not (target and is_instance_valid(target)): return
	target.bleed_dps = maxf(target.bleed_dps, dps)
	target.bleed_time = maxf(target.bleed_time, dur)
	target.bleed_source = source

func apply_slow(target: UnitBase, pct: float, dur: float) -> void:
	if not (target and is_instance_valid(target)): return
	target.slow_pct = maxf(target.slow_pct, pct)
	target.slow_time = maxf(target.slow_time, dur)

func _lowest_hp_ally(unit: UnitBase, allies: Array, rng: float, include_self: bool) -> UnitBase:
	var best: UnitBase = null
	var best_pct := INF
	for a in allies:
		# _is_alive: a corpse sits at 0 HP, so a validity-only check would make
		# it permanently the "most wounded ally" and soak every heal cast.
		if not _is_alive(a): continue
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

# By HP PERCENT (not raw current_hp) so a nearly-dead boss reads as a better
# target than a full-hp trash mob with a smaller max_hp pool. Used by Cross
# Judgment (2026-07-24, second pass — see that function's comment).
func _lowest_hp_enemy(opponents: Array) -> UnitBase:
	var best: UnitBase = null
	var best_pct := INF
	for opp in opponents:
		if not (opp and is_instance_valid(opp)): continue
		var pct := float(opp.current_hp) / float(maxi(opp.max_hp, 1))
		if pct < best_pct:
			best_pct = pct; best = opp
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
			opp.take_magic_damage(dmg, UnitBase.Element.LIGHTNING, caster)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, opp.global_position, 22.0)

# Per-frame signature passives for basic mobs. Dispatches on the `mob_passive`
# meta (set in EnemyFactory). Attack-speed and outgoing-damage bonuses are stashed
# in the `mob_aspd_bonus` / `mob_dmg_bonus` metas, read at the cooldown-reset site
# and in UnitBase.outgoing_damage_multiplier respectively — recomputed every tick
# so threshold/aura effects fall off automatically when their condition ends.
func _tick_mob_passive(unit: UnitBase, opponents: Array, allies: Array, dt: float) -> void:
	var key: String = str(unit.get_meta("mob_passive"))
	match key:
		"goblin_pack":
			# Pack Courage: +6% aspd per OTHER goblin within 3 tiles, cap +30%.
			var pack := _count_passive_allies(unit, allies, "goblin_pack", 3.0)
			unit.set_meta("mob_aspd_bonus", minf(pack * 0.06, 0.30))

		"architect_phases":
			# The Architect (wave 100, the finale). Reprises the run's three trials
			# by HP band — see create_the_architect. Each band delegates to the same
			# code the original boss used, so the finale can never drift from what
			# the player was taught.
			var frac: float = float(unit.current_hp) / maxf(float(unit.max_hp), 1.0)
			var phase: int = 0 if frac > 0.66 else (1 if frac > 0.33 else 2)
			if int(unit.get_meta("architect_phase", 0)) != phase:
				unit.set_meta("architect_phase", phase)
				unit.set_meta("arcfang_timer", 0.0)   # each band starts its clock fresh
				action_logged.emit("The Architect shifts its design — %s!" % [
					["it rises out of reach", "the tide smothers your healing",
					 "it hunts your strongest"][phase]], false)
			match phase:
				0:
					unit.melee_untargetable_time = SKYRENDER_ALOFT_TIME
				1:
					unit.melee_untargetable_time = 0.0
					for opp in opponents:
						if opp and is_instance_valid(opp):
							opp.heal_cut_time = maxf(opp.heal_cut_time, DROWNED_AURA_REFRESH)
				_:
					unit.melee_untargetable_time = 0.0
					var at: float = float(unit.get_meta("arcfang_timer", 0.0)) + dt
					if at < ARCFANG_BLINK_INTERVAL:
						unit.set_meta("arcfang_timer", at)
					else:
						unit.set_meta("arcfang_timer", 0.0)
						_arcfang_blink(unit, opponents)

		"arcfang_blink":
			# Thunder Run (Arcfang, wave-60 Lightning boss). See ARCFANG_BLINK_INTERVAL.
			var t: float = float(unit.get_meta("arcfang_timer", 0.0)) + dt
			if t < ARCFANG_BLINK_INTERVAL:
				unit.set_meta("arcfang_timer", t)
			else:
				unit.set_meta("arcfang_timer", 0.0)
				_arcfang_blink(unit, opponents)

		"drowned_riptide":
			# Riptide (Drowned Maw, the wave-30 Water boss). Every opponent has its
			# healing-received scaled for as long as the Maw is alive; the debuff is
			# rewritten each tick rather than applied once, so nothing can strip it
			# and it expires on its own when the boss dies (see the heal_cut_time
			# decay in _tick_status and the gate in UnitBase.heal).
			#
			# The fight this makes: an attrition grind where your healer is running
			# at a third power. Answered in the DRAFT — bring more damage, more
			# bodies, or burst it down — not by anything mid-battle, which is the
			# only kind of question this game can actually ask (see the placement
			# /targeting findings; the player has no in-combat lever).
			var announced: bool = bool(unit.get_meta("riptide_announced", false))
			for opp in opponents:
				if opp and is_instance_valid(opp):
					opp.heal_cut_time = maxf(opp.heal_cut_time, DROWNED_AURA_REFRESH)
			if not announced:
				unit.set_meta("riptide_announced", true)
				action_logged.emit(
					"%s drags the tide in — your healing is smothered!" % unit.unit_name, false)

		"skyrender_ascent":
			# Cyclone Ascent (Skyrender, the wave-20 Air boss). Cycles
			# GROUNDED → ALOFT forever. While aloft it can't be reached by melee
			# (see the melee_untargetable_time check in find_nearest_enemy) but
			# keeps attacking — so a team with no reach spends that window taking
			# hits it cannot answer. The question the fight asks is "did you bring
			# ranged damage", which the round-15 Gale Warden (a formation check)
			# deliberately does not ask.
			#
			# Fair by construction, per the boss-fairness rule: the windows are
			# FIXED and bounded (never HP-gated, so it can't "go invulnerable at
			# the worst moment"), it always comes back down, and a pure-melee team
			# still gets SKYRENDER_GROUND_TIME of every cycle to hit back — slower,
			# never impossible.
			var aloft: bool = bool(unit.get_meta("skyrender_aloft", false))
			var t: float = float(unit.get_meta("skyrender_timer", 0.0)) + dt
			var window: float = SKYRENDER_ALOFT_TIME if aloft else SKYRENDER_GROUND_TIME
			if t >= window:
				t = 0.0
				aloft = not aloft
				unit.set_meta("skyrender_aloft", aloft)
				action_logged.emit(
					"%s %s!" % [unit.unit_name, "sweeps into the sky" if aloft else "slams back down"],
					false)
			unit.set_meta("skyrender_timer", t)
			# Refreshed every tick rather than set once, so the normal status
			# decay in _tick_status can't quietly expire it mid-window.
			unit.melee_untargetable_time = SKYRENDER_ALOFT_TIME if aloft else 0.0

		"aspect_devour":
			# Devour Aspect (Aspect Devourer, round-95 capstone elite): every
			# ASPECT_CYCLE_INTERVAL seconds it swallows a new element and becomes it.
			# set_affinity_profile re-derives the whole offensive/defensive table
			# from current_element (it applies the own-element bonuses against
			# whatever current_element now is), so the swap has to happen BEFORE
			# that call or the profile would still describe the previous aspect.
			var asp_t: float = float(unit.get_meta("aspect_t", ASPECT_FIRST_DELAY)) - dt
			if asp_t > 0.0:
				unit.set_meta("aspect_t", asp_t)
			else:
				unit.set_meta("aspect_t", ASPECT_CYCLE_INTERVAL)
				var idx: int = int(unit.get_meta("aspect_idx", 0)) + 1
				unit.set_meta("aspect_idx", idx)
				unit.current_element = ASPECT_CYCLE[idx % ASPECT_CYCLE.size()]
				unit.set_affinity_profile(100.0, 100.0)
				# Announced so the swap always reads as telegraphed, never random.
				action_logged.emit("%s devours a new aspect — now %s!" % [
					unit.unit_name, EnemyFactory.HYDRA_ELEMENT_NAMES.get(unit.current_element, "?"),
				], unit.is_player_unit)

		"magma_pulse":
			# Eruption (Magma Heart, round-45 Fire elite): every MAGMA_PULSE_INTERVAL
			# seconds, burn EVERY living opponent at once, each pulse hotter than the
			# last. Unavoidable by design — there is no position that escapes it, so
			# the only answer is killing the Heart. Escalation is capped at
			# MAGMA_PULSE_MAX_STACKS so a slow fight is punishing, not unsurvivable.
			var pulse_t: float = float(unit.get_meta("magma_pulse_t", MAGMA_PULSE_FIRST_DELAY)) - dt
			if pulse_t > 0.0:
				unit.set_meta("magma_pulse_t", pulse_t)
			else:
				unit.set_meta("magma_pulse_t", MAGMA_PULSE_INTERVAL)
				var pulses: int = mini(int(unit.get_meta("magma_pulses", 0)) + 1, MAGMA_PULSE_MAX_STACKS)
				unit.set_meta("magma_pulses", pulses)
				var dps: float = float(unit.magic_power) * MAGMA_PULSE_DPS_PCT * float(pulses)
				for opp in opponents:
					if opp and is_instance_valid(opp) and opp.current_hp > 0:
						# Duration outlasts the interval so the burn is continuous
						# once it starts — the pressure ramps, it doesn't flicker.
						apply_burn(opp, dps, MAGMA_PULSE_INTERVAL + 1.0, unit)

		"terracotta_harden":
			# Set in Stone (Terracotta Colossus, round-35 Earth elite): armor climbs
			# every second, capped at +TERRACOTTA_ARMOR_CAP over the statline it
			# spawned with. Banked through a float accumulator meta because
			# resistance/magic_resist are INT fields — adding a sub-1 amount per
			# frame directly would be truncated away every tick and the ramp would
			# silently never happen. This is the exact int-truncation bug the
			# drain_accum/burn_accum accumulators elsewhere in this file exist for.
			var base_res: int = int(unit.get_meta("terracotta_base_res", unit.resistance))
			if not unit.has_meta("terracotta_base_res"):
				unit.set_meta("terracotta_base_res", base_res)
			var gained: float = float(unit.get_meta("terracotta_armor", 0.0))
			if gained < TERRACOTTA_ARMOR_CAP:
				gained = minf(gained + TERRACOTTA_ARMOR_PER_SEC * dt, TERRACOTTA_ARMOR_CAP)
				unit.set_meta("terracotta_armor", gained)
				# Both defenses harden together — a purely physical wall would just
				# hand the fight to any magic carry and stop being a burst check.
				unit.resistance   = base_res + int(gained)
				unit.magic_resist = base_res + int(gained)

		"tide_font":
			# Tide Font (Tidecaller, round-25 Water elite): regenerates every nearby
			# ally, the Tidecaller included. This is what makes it a target-priority
			# check — the escort keeps standing back up until the caller dies.
			# Throttled to AURA_TICK_INTERVAL like every other aura (see the NEMI
			# comment in _tick_passive); the regen is banked through hp_regen_accum
			# so the int-truncation problem the drain/burn accumulators exist to
			# solve can't reappear here.
			var tide_t: float = float(unit.get_meta("aura_tick_t", 0.0)) - dt
			if tide_t > 0.0:
				unit.set_meta("aura_tick_t", tide_t)
			else:
				unit.set_meta("aura_tick_t", AURA_TICK_INTERVAL)
				for ally in allies:
					if not (ally and is_instance_valid(ally)):
						continue
					if unit.grid_position.distance_to(ally.grid_position) > TIDE_FONT_RANGE:
						continue
					ally.hp_regen_accum += float(ally.max_hp) * TIDE_FONT_PCT_PER_SEC * AURA_TICK_INTERVAL

		"orc_rage":
			# Bloodrage: below 50% HP, +20% dmg / +15% aspd.
			var enraged: bool = unit.current_hp < unit.max_hp * 0.5
			unit.set_meta("mob_dmg_bonus", 0.20 if enraged else 0.0)
			unit.set_meta("mob_aspd_bonus", 0.15 if enraged else 0.0)

		"bear_fury":
			# Fury: aspd ramps with missing HP, up to +30%.
			var missing: float = 1.0 - float(unit.current_hp) / float(maxi(unit.max_hp, 1))
			unit.set_meta("mob_aspd_bonus", minf(missing * 0.40, 0.30))

		"windup_overclock":
			# Overclock: +5%/3s aspd, cap +50% — accumulates smoothly.
			var oc: float = float(unit.get_meta("oc_bonus", 0.0)) + (0.05 / 3.0) * dt
			oc = minf(oc, 0.50)
			unit.set_meta("oc_bonus", oc)
			unit.set_meta("mob_aspd_bonus", oc)

		"troll_regen":
			# Regeneration: +2% max HP/s, unless a recent Fire/Lightning hit blocked it
			# (block flag set in UnitBase.take_damage, counted down here).
			var block_t: float = float(unit.get_meta("troll_regen_block_t", 0.0))
			if block_t > 0.0:
				unit.set_meta("troll_regen_block_t", block_t - dt)
			else:
				unit.hp_regen_accum += float(unit.max_hp) * 0.02 * dt

		"lizard_coldblood":
			# Cold Blood: 3% max HP/s regen while un-hit for 3s. Detect hits by watching
			# cumulative damage-taken rise (element/attacker-agnostic, cheap dict sum).
			var total: int = 0
			for v in unit.damage_taken_from.values():
				total += int(v)
			var seen: int = int(unit.get_meta("cb_dmg_seen", 0))
			if total > seen:
				unit.set_meta("cb_dmg_seen", total)
				unit.set_meta("cb_calm_t", 3.0)
			var calm: float = float(unit.get_meta("cb_calm_t", 0.0)) - dt
			unit.set_meta("cb_calm_t", calm)
			if calm <= 0.0:
				unit.hp_regen_accum += float(unit.max_hp) * 0.03 * dt

		"shaman_link":
			# Spirit Link: nearby allies regen +0.5 HP/s. Throttled full-roster scan
			# (perf: same reasoning as the NEMI/BOUNCER auras above).
			var link_t: float = float(unit.get_meta("aura_tick_t", 0.0)) - dt
			if link_t > 0.0:
				unit.set_meta("aura_tick_t", link_t)
			else:
				unit.set_meta("aura_tick_t", AURA_TICK_INTERVAL)
				for ally in allies:
					if ally and is_instance_valid(ally) and ally != unit:
						if unit.grid_position.distance_to(ally.grid_position) <= 3:
							ally.hp_regen_accum += 0.5 * AURA_TICK_INTERVAL

		"rat_infest":
			# Infestation: with 2+ other rats within 2 tiles, +15% dmg and the bite's
			# disease DoT lasts 50% longer (read in the "rat_bite" mob skill).
			var swarm := _count_passive_allies(unit, allies, "rat_infest", 2.0)
			var infesting: bool = swarm >= 2
			unit.set_meta("mob_dmg_bonus", 0.15 if infesting else 0.0)
			unit.set_meta("rat_disease_boost", infesting)

		# "archer_focus" (Focus Fire) is on-hit, handled in _apply_on_hit_passives.
		# "slime_split" / "skeleton_undying" are on-death, handled in VisualUnit.die().
		_:
			pass

# Counts allies (excluding `unit`) carrying `passive_key` within `radius` tiles.
func _count_passive_allies(unit: UnitBase, allies: Array, passive_key: String, radius: float) -> int:
	var n := 0
	for a in allies:
		if a and is_instance_valid(a) and a != unit and a.has_meta("mob_passive") \
				and str(a.get_meta("mob_passive")) == passive_key \
				and unit.grid_position.distance_to(a.grid_position) <= radius:
			n += 1
	return n

# ── Reactive: runs on the attacker's basic attack ─────────────────────────────
func _apply_on_hit_passives(attacker: UnitBase, target: UnitBase, opponents: Array) -> void:
	if not (attacker and is_instance_valid(attacker) and target and is_instance_valid(target)):
		return
	# Goblin Archer "Focus Fire": +8% dmg per consecutive hit on the SAME target
	# (cap +40%), resets on switching. Tracked by target instance id in meta; the
	# bonus is stashed in mob_dmg_bonus (read in outgoing_damage_multiplier), so it
	# applies from the NEXT hit onward — same one-hit-lag as the Ant bite stacks.
	if attacker.has_meta("mob_passive") and str(attacker.get_meta("mob_passive")) == "archer_focus":
		var tid: int = target.get_instance_id()
		var stacks: int = int(attacker.get_meta("ff_stacks", 0))
		if int(attacker.get_meta("ff_target", 0)) == tid:
			stacks = mini(stacks + 1, 5)
		else:
			stacks = 0
			attacker.set_meta("ff_target", tid)
		attacker.set_meta("ff_stacks", stacks)
		attacker.set_meta("mob_dmg_bonus", stacks * 0.08)
		return
	match attacker.unit_class:
		UnitBase.UnitClass.ANT:
			# Bite lands (damage already dealt in UnitBase.attack, which read the
			# PRE-increment stack) — now bump the GLOBAL swarm-rage counter for
			# every Ant's NEXT bite, on any target (see ant_swarm_stacks above).
			# No cap — that's the point.
			ant_swarm_stacks += 1
		UnitBase.UnitClass.COAL:
			var stacks: float = _abf(attacker, AF_ACTIVE, "mult") if attacker.stoke_charges > 0 else 1.0
			if attacker.stoke_charges > 0: attacker.stoke_charges -= 1
			apply_burn(target, _abf(attacker, AF_PASSIVE, "burn") * stacks,
					_abf(attacker, AF_PASSIVE, "dur"), attacker)
			if attacker.meltdown_time > 0.0:
				_explosion(attacker, target.grid_position, _ab(attacker, AF_ULT, "blast"), opponents, 1.5)
		UnitBase.UnitClass.EMBER:
			apply_burn(target, _abf(attacker, AF_PASSIVE, "burn"),
					_abf(attacker, AF_PASSIVE, "dur"), attacker)
		UnitBase.UnitClass.SABLE:
			attacker.momentum_stacks = mini(attacker.momentum_stacks + 1,
					_ab(attacker, AF_PASSIVE, "cap"))
		UnitBase.UnitClass.ZOLT:
			var zc: int = int(attacker.get_meta("zolt_auto", 0)) + 1
			if zc >= _ab(attacker, AF_PASSIVE, "every"):
				zc = 0
				_chain_lightning(attacker, target, opponents, 3.0, _ab(attacker, AF_PASSIVE, "dmg"))
			attacker.set_meta("zolt_auto", zc)
		UnitBase.UnitClass.LUMEN:
			var second := _second_nearest(attacker, target, opponents)
			if second:
				var d: int = _ab(attacker, AF_PASSIVE, "dmg")
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

	# Mirrorplate (round-85 elite): throw a share of the hit back at whoever
	# landed it. Lives here rather than in take_damage because this function is
	# already the on-being-hit hook, already gated on dmg > 0, and — importantly —
	# already re-entrancy guarded by _propagating above, so the reflected hit
	# can't bounce back and forth.
	# NEVER LETHAL: the reflect is clamped to leave the attacker at 1 HP. Killing
	# a player's carry with their own attack, with no counterplay visible before
	# it happens, is the agency-removing pattern this project has ruled out.
	if victim.has_meta("mob_reflect") and attacker and is_instance_valid(attacker) \
			and attacker is UnitBase and attacker != victim and attacker.current_hp > 0:
		var pct: float = float(victim.get_meta("mob_reflect"))
		# Per-hit ceiling as a share of the ATTACKER's own max HP. Without this a
		# pure percentage reflect is unbeatable by design: the reflected damage
		# scales off the player's damage, so team power and reflect power grow in
		# lockstep and the ratio never improves. Measured directly — a level-55 and
		# a level-65 team both lost round 85 three times out of three, identically,
		# while the strictly-stronger round-95 elite was a comfortable win.
		# Capping against max HP breaks that loop: a stronger team still takes the
		# tax, but a bounded one that healing and levels can actually answer.
		var back: int = int(float(dmg) * pct)
		back = mini(back, int(float(attacker.max_hp) * MIRROR_REFLECT_MAX_HP_PCT))
		back = mini(back, attacker.current_hp - 1)
		if back > 0:
			# True damage: the reflect is the victim's own armor throwing the blow
			# back, so it shouldn't be re-mitigated by the attacker's defenses.
			attacker.take_damage(back, victim.current_element, victim, true)
			victim.damage_dealt += back

	# Static Live Wire: anyone who damages him is hit by their own current, taking
	# back a slice of the damage they just dealt. Scales off Static's own level
	# and magic power — 10% at level 1 / low magic power, up to 20% at level 50 / 100+.
	if victim.unit_class == UnitBase.UnitClass.STATIC and attacker and is_instance_valid(attacker) \
			and attacker is UnitBase and attacker != victim:
		var reflect_pct: float = _abf(victim, AF_PASSIVE, "reflect")
		var reflect_back: int = int(float(dmg) * reflect_pct)
		if reflect_back > 0:
			attacker.take_damage(reflect_back, UnitBase.Element.LIGHTNING, victim, true)
			victim.damage_dealt += reflect_back
			_spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, attacker.global_position, 22.0)

	# Riot Crowd Control: slow whoever damaged him.
	if victim.unit_class == UnitBase.UnitClass.RIOT and attacker and is_instance_valid(attacker) and attacker != victim:
		apply_slow(attacker, _abf(victim, AF_PASSIVE, "slow"), _abf(victim, AF_PASSIVE, "dur"))

	# Cross Penance: heal a share of damage taken (counts toward Judgment).
	# Balance 2026-07-03: 0.35 → 0.20 — at 35% Cross out-sustained an entire
	# 11-unit wave solo in arena sweeps (3119 self-healing, 100% solo win rate,
	# highest damage in the roster). Still the tankiest sustain in the game at 20%.
	# Balance 2026-07-24: 0.20 → 0.15 — 20% Penance STILL let a lone Cross solo
	# full waves. Root cause was actually _cross_judgment reading lifetime
	# combat_healing_done (never reset), so every ult cast scaled off ALL
	# healing ever done in the fight — see that function's comment.
	if victim.unit_class == UnitBase.UnitClass.CROSS:
		var ch: int = int(float(dmg) * _abf(victim, AF_PASSIVE, "share"))
		if ch > 0:
			victim.heal(ch)
			victim.combat_healing_done += ch
			victim.judgment_pool += ch

	# Rift Backlash: redirect 30% of damage to a random enemy.
	if victim.unit_class == UnitBase.UnitClass.RIFT:
		var rift_opps: Array = enemy_units if victim.is_player_unit else player_units
		var pool: Array = rift_opps.filter(func(u): return u != null and is_instance_valid(u))
		if not pool.is_empty():
			var pick: UnitBase = pool[randi() % pool.size()]
			var rdmg: int = int(float(dmg) * _abf(victim, AF_PASSIVE, "redirect"))
			if rdmg > 0:
				pick.take_damage(rdmg, UnitBase.Element.NORMAL, victim, true)
				victim.damage_dealt += rdmg

	# Stitch Link: bound partner shares the hit.
	if victim.link_partner != null and is_instance_valid(victim.link_partner):
		# Class-level lookup: the Stitch that cast this may already be dead.
		var share: int = int(float(dmg) * AbilityFormulas.flat(
				UnitBase.UnitClass.STITCH, AF_ACTIVE, "share"))
		if share > 0:
			victim.link_partner.take_damage(share, UnitBase.Element.NORMAL, attacker, true)

	# Stitch Loose Threads: if the victim's foes field a Stitch, bleed to its teammates.
	var team: Array = player_units if victim.is_player_unit else enemy_units
	var foes: Array = enemy_units if victim.is_player_unit else player_units
	if _team_has_stitch(foes):
		var bleed: int = int(float(dmg) * AbilityFormulas.flat(
				UnitBase.UnitClass.STITCH, AF_PASSIVE, "bleed"))
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
			"dmg": _abf(unit, AF_PASSIVE, "trail"),
			"time": _abf(unit, AF_PASSIVE, "dur"),
			"source": unit, "owner_is_player": unit.is_player_unit,
		}

	# Field hazards burn the mover if it belongs to the opposing side.
	if thorns_time > 0.0 and unit.is_player_unit != thorns_owner_is_player:
		unit.take_damage(thorns_dmg, UnitBase.Element.EARTH, null, true)
	if is_instance_valid(unit) and fire_trail.has(cell):
		var ft = fire_trail[cell]
		if unit.is_player_unit != ft["owner_is_player"]:
			apply_burn(unit, ft["dmg"], 2.0, ft["source"])

# ── Track fallen heroes so Doc can revive one ─────────────────────────────────
# Stores the ACTUAL downed node, not a stat snapshot (2026-07-24): hero nodes
# are no longer freed on death (VisualUnit.die parks them for the end-of-round
# revival), so Doc can now put the real hero back — with its true level, XP and
# equipment — instead of rebuilding an approximate copy.
func _on_ally_died(unit: UnitBase) -> void:
	if not (unit and is_instance_valid(unit)):
		return
	if unit.is_summoned:
		return
	fallen_allies.append(unit)

# ══════════════════════════════════════════════════════════════════════════════
# Hero skills
# ══════════════════════════════════════════════════════════════════════════════

func _doc_inject(caster: UnitBase, allies: Array) -> void:
	var tar := _lowest_hp_ally(caster, allies, float(caster.skill_range), true)
	if not tar: return
	var miss: float = 1.0 - float(tar.current_hp) / float(maxi(tar.max_hp, 1))
	# Registry stores the band ends; the target's missing HP picks a point on it.
	var lo: float = _abf(caster, AF_ACTIVE, "lo")
	var amt: int = int(lo + (_abf(caster, AF_ACTIVE, "hi") - lo) * miss)
	tar.heal(amt)
	caster.combat_healing_done += amt
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, tar.global_position, 48.0)

func _riot_shield_bash(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	var dmg: int = _ab(caster, AF_ACTIVE, "dmg")
	tar.take_damage(dmg, caster.current_element, caster)
	caster.damage_dealt += dmg
	tar.stun_time = maxf(tar.stun_time, _abf(caster, AF_ACTIVE, "stun"))
	tar.taunt_source = caster
	tar.taunt_time = maxf(tar.taunt_time, _abf(caster, AF_ACTIVE, "taunt"))
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
	best.bonus_aspd_pct = maxf(best.bonus_aspd_pct, _abf(caster, AF_ACTIVE, "aspd"))
	best.bonus_aspd_time = maxf(best.bonus_aspd_time, _abf(caster, AF_ACTIVE, "dur"))
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, best.global_position, 40.0)

func _sable_bolt(caster: UnitBase, opponents: Array) -> void:
	var cx: int = caster.grid_position.x
	var dmg: int = _ab(caster, AF_ACTIVE, "dmg")
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
	var dmg: int = _ab(caster, AF_ACTIVE, "dmg")
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
	caster.stoke_charges = _ab(caster, AF_ACTIVE, "charges")
	_spawn_skill_effect_sized(SkillEffect.Type.BURN, caster.global_position, 40.0)

func _june_root(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	tar.root_time = maxf(tar.root_time, _abf(caster, AF_ACTIVE, "root"))
	var dmg: int = _ab(caster, AF_ACTIVE, "dmg")
	if dmg > 0:
		tar.take_magic_damage(dmg, caster.current_element, caster)
		caster.damage_dealt += dmg
	_spawn_skill_effect_sized(SkillEffect.Type.NATURE, tar.global_position, 38.0)

func _cross_absolution(caster: UnitBase, allies: Array) -> void:
	var tar := _lowest_hp_ally(caster, allies, float(caster.skill_range), true)
	if not tar: return
	tar.slow_time = 0.0; tar.burn_time = 0.0; tar.bleed_time = 0.0; tar.root_time = 0.0
	tar.taunt_time = 0.0; tar.taunt_source = null
	var h: int = _ab(caster, AF_ACTIVE, "hp") + _ab(caster, AF_ACTIVE, "res")
	tar.heal(h)
	caster.combat_healing_done += h
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, tar.global_position, 44.0)

func _sear_ignite(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	var dmg: int = _ab(caster, AF_ACTIVE, "dmg")
	tar.take_magic_damage(dmg, caster.current_element, caster)
	caster.damage_dealt += dmg
	apply_burn(tar, _abf(caster, AF_ACTIVE, "burn"), _abf(caster, AF_ACTIVE, "dur"), caster)
	_spawn_skill_effect_sized(SkillEffect.Type.BURN, tar.global_position, 40.0)

func _ember_cinder(caster: UnitBase, opponents: Array) -> void:
	var center := find_nearest_enemy(caster, opponents)
	if not center: return
	var dmg: int = _ab(caster, AF_ACTIVE, "dmg")
	for opp in opponents:
		if opp and is_instance_valid(opp) and center.grid_position.distance_to(opp.grid_position) <= 2.0:
			opp.take_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg
			apply_burn(opp, _abf(caster, AF_PASSIVE, "burn"), _abf(caster, AF_PASSIVE, "dur"), caster)
			_spawn_skill_effect_sized(SkillEffect.Type.BURN, opp.global_position, 30.0)

func _rift_tear(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	var dmg: int = _ab(caster, AF_ACTIVE, "dmg")
	tar.take_magic_damage(dmg, caster.current_element, caster)
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
	var dmg: int = _ab(caster, AF_ACTIVE, "dmg")
	storm.setup(battle_grid, self, caster, dmg, cell)
	storms.append(storm)
	action_logged.emit("%s conjures a thunderstorm!" % caster.unit_name, caster.is_player_unit)

func _lumen_refract(caster: UnitBase, opponents: Array) -> void:
	var visited: Dictionary = {}
	var current := find_nearest_enemy(caster, opponents)
	var dmg: int = _ab(caster, AF_ACTIVE, "dmg")
	var decay: float = 1.0 - _abf(caster, AF_ACTIVE, "decay")
	for i in range(_ab(caster, AF_ACTIVE, "bounces")):
		if not (current and is_instance_valid(current)): break
		visited[current] = true
		current.take_magic_damage(dmg, caster.current_element, caster)
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
		dmg = int(float(dmg) * decay)

# Static's shared level+magic-power curve now lives in AbilityFormulas as the
# "static:LO:HI" term curve — it was always exactly the level+stat scaling the
# registry standardises, so it moved wholesale rather than being flattened.
# See AbilityFormulas._apply_curve.

func _static_tripwire(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	tar.stun_time = maxf(tar.stun_time, _abf(caster, AF_ACTIVE, "stun"))
	var dmg: int = _ab(caster, AF_ACTIVE, "dmg")
	tar.take_magic_damage(dmg, UnitBase.Element.LIGHTNING, caster)
	caster.damage_dealt += dmg
	_spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, tar.global_position, 34.0)

func _reed_cleanse(caster: UnitBase, allies: Array) -> void:
	var tar := _lowest_hp_ally(caster, allies, float(caster.skill_range), true)
	if not tar: return
	tar.slow_time = 0.0; tar.burn_time = 0.0; tar.bleed_time = 0.0; tar.root_time = 0.0
	tar.taunt_time = 0.0; tar.taunt_source = null
	var h: int = _ab(caster, AF_ACTIVE, "heal")
	tar.heal(h)
	caster.combat_healing_done += h
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, tar.global_position, 40.0)

func _vail_updraft(caster: UnitBase, allies: Array) -> void:
	var tar := _lowest_hp_ally(caster, allies, 99.0, false)
	if not tar: tar = caster
	tar.untargetable_time = maxf(tar.untargetable_time, _abf(caster, AF_ACTIVE, "dur"))
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, tar.global_position, 40.0)

func _spore_bloom(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	tar.spore_stacks = 10.0   # instant max → bursts on its next status tick
	tar.set_meta("spore_source", caster)
	tar.set_meta("spore_burst", _ab(caster, AF_ACTIVE, "burst"))
	_spawn_skill_effect_sized(SkillEffect.Type.NATURE, tar.global_position, 38.0)

# ══════════════════════════════════════════════════════════════════════════════
# Hero ultimates
# ══════════════════════════════════════════════════════════════════════════════

func _doc_field_surgery(caster: UnitBase, allies: Array) -> void:
	# Once per battle: pull a downed ally back into THIS fight at 30% HP, rather
	# than making the team wait for the end-of-round 10% revival everyone now
	# gets. Revives the REAL downed hero node (parked by VisualUnit.die), so it
	# returns with its actual level/XP/equipment. It used to build a fresh copy
	# from a stat snapshot and mark it a summon that "graduated" if it survived
	# — under round-end revival that copy would have duplicated the hero
	# (original revives at round end, copy graduates → two of them), so the copy
	# is gone entirely (2026-07-24).
	var downed: UnitBase = null
	if not caster.revive_used:
		while not fallen_allies.is_empty():
			var cand = fallen_allies.pop_back()
			if cand and is_instance_valid(cand) and cand.current_hp <= 0:
				downed = cand
				break
	if downed == null:
		# Nothing revivable (already used, nobody down) — emergency team heal.
		for a in allies:
			if a and is_instance_valid(a):
				var h: int = int(float(a.max_hp) * _abf(caster, AF_ULT, "fallback"))
				a.heal(h)
				caster.combat_healing_done += h
				_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, a.global_position, 36.0)
		return
	var cell := _nearest_open_adjacent(caster.grid_position)
	if cell == Vector2i(-1, -1):
		cell = _nearest_open_cell_to(caster.grid_position)
	if cell == Vector2i(-1, -1):
		# No room right now — leave them down; the round-end revival still gets them.
		fallen_allies.append(downed)
		return
	caster.revive_used = true
	downed.revive(_abf(caster, AF_ULT, "revive"))
	downed.grid_position = cell
	downed.home_position = cell   # slots back in here next round
	if battle_grid.place_unit(downed, cell):
		# The node was never removed from the scene tree and its `died` signal is
		# still wired from its original recruit, so this only has to put it back
		# in the roster — emitting unit_summoned would re-add and re-connect it.
		if downed.is_player_unit:
			if downed not in player_units: player_units.append(downed)
		elif downed not in enemy_units:
			enemy_units.append(downed)
		downed.position = _world_pos_for(downed, cell)
		_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, downed.global_position, 60.0)
		action_logged.emit("%s revives %s!" % [caster.unit_name, downed.unit_name], caster.is_player_unit)
	else:
		caster.revive_used = false
		fallen_allies.append(downed)

func _riot_kettle(caster: UnitBase, opponents: Array) -> void:
	for opp in opponents:
		if opp and is_instance_valid(opp):
			opp.taunt_source = caster
			opp.taunt_time = maxf(opp.taunt_time, _abf(caster, AF_ULT, "taunt"))
	_spawn_skill_effect_sized(SkillEffect.Type.GRAVITY_DROP, caster.global_position, 90.0)
	action_logged.emit("%s kettles the enemy!" % caster.unit_name, caster.is_player_unit)

func _pastor_damnation(caster: UnitBase, opponents: Array) -> void:
	for opp in opponents:
		if opp and is_instance_valid(opp):
			opp.outgoing_dmg_mult = minf(opp.outgoing_dmg_mult, 1.0 - _abf(caster, AF_ULT, "weaken"))
			opp.outgoing_dmg_time = 0.0   # lasts the rest of the round
	_spawn_skill_effect_sized(SkillEffect.Type.INFERNO, caster.global_position, 90.0)
	action_logged.emit("%s damns the enemy host!" % caster.unit_name, caster.is_player_unit)

func _sable_headshot(caster: UnitBase, opponents: Array) -> void:
	var tar := find_nearest_enemy(caster, opponents)
	if not tar: return
	var mom: int = caster.momentum_stacks
	var dmg: int = int(_abf(caster, AF_ULT, "dmg") * (1.0 + float(mom) * _abf(caster, AF_PASSIVE, "per")))
	tar.take_damage(dmg, caster.current_element, caster)
	caster.damage_dealt += dmg
	caster.momentum_stacks = 0
	_spawn_skill_effect_sized(SkillEffect.Type.ARROW_RAIN, tar.global_position, 50.0)
	action_logged.emit("%s lands a headshot! (%d dmg)" % [caster.unit_name, dmg], caster.is_player_unit)

func _rush_afterimage(caster: UnitBase, opponents: Array) -> void:
	afterimage_actor = caster
	afterimage_time = _abf(caster, AF_ULT, "dur")
	caster.ult_active_time = afterimage_time   # no ult-charge (or re-ult) while afterimage runs
	var dmg: int = _ab(caster, AF_ULT, "dmg")
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
	tar.puppet_time = _abf(caster, AF_ULT, "dur")
	_spawn_skill_effect_sized(SkillEffect.Type.SHADOW_STRIKE, tar.global_position, 44.0)
	action_logged.emit("%s seizes control of %s!" % [caster.unit_name, tar.unit_name], caster.is_player_unit)

func _coal_meltdown(caster: UnitBase) -> void:
	caster.meltdown_time = _abf(caster, AF_ULT, "dur")
	_spawn_skill_effect_sized(SkillEffect.Type.BURN, caster.global_position, 60.0)
	action_logged.emit("%s overheats — Meltdown!" % caster.unit_name, caster.is_player_unit)

func _june_bloom(caster: UnitBase) -> void:
	thorns_time = _abf(caster, AF_ULT, "dur")
	thorns_dmg = _ab(caster, AF_ULT, "thorns")
	thorns_owner_is_player = caster.is_player_unit
	_spawn_skill_effect_sized(SkillEffect.Type.NATURE, caster.global_position, 100.0)
	action_logged.emit("%s blankets the field in thorns!" % caster.unit_name, caster.is_player_unit)

func _cross_judgment(caster: UnitBase, opponents: Array) -> void:
	# Balance 2026-07-24, first pass: this used to read lifetime
	# combat_healing_done (only ever reset at battle start), so every cast
	# scaled off ALL healing done in the entire fight — a solo Cross tanking
	# a full wave charged this ult fast (take_damage charges ultimates at
	# full rate) and each successive AoE cast hit EVERY enemy for a number
	# that only ever grew, never shrank. Fixed by reading judgment_pool (a
	# dedicated resource banking Penance healing since the last cast, spent
	# to zero here) instead — but that alone didn't stop him soloing full
	# waves, because AoE-hit-everyone was ITSELF the multiplier: tanking a
	# bigger crowd meant hitting a bigger crowd back, so total output still
	# scaled with wave size for free (verified: solo Cross beat a wave his
	# exact stat-twin Riot couldn't touch — see arena sweep 2026-07-24).
	# Balance 2026-07-24, second pass: single-target instead of AoE. Judgment
	# is now a finishing blow on the lowest-HP%% enemy — tanking more enemies
	# no longer multiplies his damage output, it just fills the resource
	# faster. Multiplier restored 0.45->0.5 since a single-target hit no
	# longer carries the AoE's implicit "free extra hits" value.
	var dmg: int = int(float(caster.judgment_pool) * _abf(caster, AF_ULT, "pool"))
	var floor_dmg: int = _ab(caster, AF_ULT, "floor")
	if dmg < floor_dmg:
		dmg = floor_dmg
	caster.judgment_pool = 0
	var tar: UnitBase = _lowest_hp_enemy(opponents)
	if tar and is_instance_valid(tar):
		tar.take_damage(dmg, caster.current_element, caster)
		caster.damage_dealt += dmg
		_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, tar.global_position, 30.0)
	action_logged.emit("%s passes judgment! (%d dmg)" % [caster.unit_name, dmg], caster.is_player_unit)

func _sear_conflagration(caster: UnitBase, opponents: Array) -> void:
	var maxdps: float = _abf(caster, AF_ULT, "floor")
	for opp in opponents:
		if opp and is_instance_valid(opp) and opp.burn_dps > maxdps:
			maxdps = opp.burn_dps
	for opp in opponents:
		if opp and is_instance_valid(opp):
			apply_burn(opp, maxdps, _abf(caster, AF_ACTIVE, "dur"), caster)
			var burst: int = int(opp.burn_dps * _abf(caster, AF_ULT, "burst"))
			if burst > 0:
				opp.take_damage(burst, UnitBase.Element.FIRE, caster, true)
				caster.damage_dealt += burst
			_spawn_skill_effect_sized(SkillEffect.Type.BURN, opp.global_position, 36.0)
	action_logged.emit("%s ignites the battlefield!" % caster.unit_name, caster.is_player_unit)

func _ember_wildfire(caster: UnitBase, opponents: Array) -> void:
	for opp in opponents.duplicate():
		if opp and is_instance_valid(opp) and opp.burn_time > 0.0:
			var burst: int = int(opp.burn_dps * _abf(caster, AF_ULT, "burn_mult")) \
				+ _ab(caster, AF_ULT, "blast")
			_explosion(caster, opp.grid_position, burst, opponents, 1.5)
	action_logged.emit("%s detonates the flames!" % caster.unit_name, caster.is_player_unit)

func _rift_collapse(caster: UnitBase, opponents: Array) -> void:
	var center := Vector2i(battle_grid.grid_width / 2, battle_grid.grid_height / 2)
	var dmg: int = _ab(caster, AF_ULT, "dmg")
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
	var dmg: int = _ab(caster, AF_ULT, "dmg")
	tar.take_damage(dmg, UnitBase.Element.LIGHTNING, caster)
	caster.damage_dealt += dmg
	tar.stun_time = maxf(tar.stun_time, _abf(caster, AF_ULT, "stun"))
	_spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, tar.global_position, 72.0)
	action_logged.emit("%s calls down the thunderhammer!" % caster.unit_name, caster.is_player_unit)

func _lumen_prism(caster: UnitBase, opponents: Array) -> void:
	var dmg: int = _ab(caster, AF_ULT, "dmg")
	for opp in opponents:
		if opp and is_instance_valid(opp):
			opp.take_damage(dmg, caster.current_element, caster)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.CHAOS_BOLT, opp.global_position, 28.0)
	_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, caster.global_position, 60.0)
	action_logged.emit("%s splits into a prism!" % caster.unit_name, caster.is_player_unit)

func _static_grid(caster: UnitBase) -> void:
	grid_field_time = _abf(caster, AF_ULT, "dur")
	grid_field_tick_time = 1.0
	grid_field_dmg = _ab(caster, AF_ULT, "dmg")
	grid_owner_is_player = caster.is_player_unit
	static_grid_channel_time = _abf(caster, AF_ULT, "lock")
	static_grid_channel_caster = caster
	_spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, caster.global_position, 100.0)
	action_logged.emit("%s electrifies the entire field!" % caster.unit_name, caster.is_player_unit)

func _reed_confluence(caster: UnitBase, allies: Array) -> void:
	var water := 0
	for a in allies:
		if a and is_instance_valid(a) and a.current_element == UnitBase.Element.WATER:
			water += 1
	var mult: float = 1.0 + float(water) * _abf(caster, AF_ULT, "per_water")
	for a in allies:
		if a and is_instance_valid(a):
			var h: int = int(float(a.max_hp) * _abf(caster, AF_ULT, "heal") * mult)
			a.heal(h)
			caster.combat_healing_done += h
			_spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, a.global_position, 34.0)
	action_logged.emit("%s channels the confluence! (x%.1f)" % [caster.unit_name, mult], caster.is_player_unit)

func _vail_tailwind(caster: UnitBase, allies: Array) -> void:
	for a in allies:
		if a and is_instance_valid(a):
			a.bonus_aspd_pct = maxf(a.bonus_aspd_pct, _abf(caster, AF_ULT, "aspd"))
			a.bonus_aspd_time = maxf(a.bonus_aspd_time, _abf(caster, AF_ULT, "dur"))
			_spawn_skill_effect_sized(SkillEffect.Type.OVERDRIVE, a.global_position, 26.0)
	action_logged.emit("%s summons a tailwind!" % caster.unit_name, caster.is_player_unit)

func _spore_release(caster: UnitBase, opponents: Array) -> void:
	# Registry stores the band ends (0.2 and 1.5 stack multipliers folded in); the
	# target's own stack count picks a point on it.
	var lo: float = _abf(caster, AF_ULT, "lo")
	var hi: float = _abf(caster, AF_ULT, "hi")
	for opp in opponents:
		if opp and is_instance_valid(opp):
			var mult: float = clampf(opp.spore_stacks / 10.0, 0.2, 1.5)
			var dmg: int = int(lerpf(lo, hi, (mult - 0.2) / 1.3))
			opp.spore_stacks = 0.0
			opp.take_damage(dmg, UnitBase.Element.EARTH, caster, true)
			caster.damage_dealt += dmg
			_spawn_skill_effect_sized(SkillEffect.Type.NATURE, opp.global_position, 32.0)
	action_logged.emit("%s releases the spores!" % caster.unit_name, caster.is_player_unit)
