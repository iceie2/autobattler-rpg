extends RefCounted
class_name ElementPieces

# ══════════════════════════════════════════════════════════════════════════════
# ELEMENT ARCHETYPE PIECES (VD-22, ARCHETYPE_PIECES.md, owner 2026-09-29)
#
# Each element's damage type lives ONLY in its relic pieces: a run that never
# takes the Earth seed never sees armor shred. Relics apply to every hero
# alike, so the team value of a piece is the largest any player unit carries
# (same rule as the Burn pieces). "Per X hero" counts distinct hero types of
# that element fielded at battle start, max 3 (HeroVerbs.count_types).
#
#   Earth     shred    - Earth hits stack armor + magic resist shred (%)
#   Lightning stun     - Lightning heroes' stuns, and payoffs on stunned foes
#   Water     soak     - Water hits Soak: stacking attack/move slow
#   Air       extra    - Air basic attacks can also hit a second enemy
#
# Owned by AutoBattleManager (element_pieces). Hooks: UnitBase.take_damage
# (shred, damage mult, stacking), UnitBase.heal (Tidecall), UnitBase death
# (Aftershock, Arc), UnitBase.speed_modifier (Soak, Slipstream),
# UnitBase._charge_ultimate (Overcharge), AutoBattleManager.apply_stun
# (Static Charge, Thunderhead count) and the generic basic-attack path (Air).
#
# Loop safety (VD-16 rule 5): no piece refunds ult charge from an ult; the
# stuns Arc and Deluge create are sourceless, so they are neither extended nor
# counted toward Thunderhead; Tectonic reads shred and adds shred, so all
# shred is capped at SHRED_CAP.
# ══════════════════════════════════════════════════════════════════════════════

const EARTH_MAX_STACKS := 10
const EARTH_FADE := 4.0          # s after the last Earth hit before stacks fade
const SHRED_CAP := 0.75          # armor/MR can lose at most 75%
const TECTONIC_PERIOD := 10.0
const SOAK_SECS := 3.0
const SOAK_SLOW_CAP := 0.6
const DELUGE_PERIOD := 12.0
const SLIP_SECS := 3.0
const SLIP_MAX := 5
const TEMPEST_PERIOD := 8.0
const THUNDER_EVERY := 5
const AIR_BASE_FRAC := 0.5       # extra hits deal half damage unless Updraft
const TIDECALL_RANGE := 1        # grid tiles: "next to"

var active := false
var v := {}                      # piece type -> team value
var counts := {}                 # element verb -> distinct hero types (max 3)
var mgr                          # AutoBattleManager
var _tectonic_t := 0.0
var _deluge_t := 0.0
var _tempest_t := 0.0
var _stun_count := 0
var _thunder_pending := 0

func val(k: String) -> float:
	return float(v.get(k, 0.0))

func setup(manager, players: Array, enemies: Array) -> void:
	mgr = manager
	v.clear()
	for u in players:
		if u and is_instance_valid(u):
			for k in u.relic_arch:
				v[k] = maxf(val(k), float(u.relic_arch[k]))
	active = not v.is_empty()
	counts.clear()
	for verb in [HeroVerbs.EARTH, HeroVerbs.LIGHTNING, HeroVerbs.WATER, HeroVerbs.AIR]:
		counts[verb] = mini(3, HeroVerbs.count_types(players, verb))
	_tectonic_t = 0.0
	_deluge_t = 0.0
	_tempest_t = 0.0
	_stun_count = 0
	_thunder_pending = 0
	for u in players + enemies:
		if u and is_instance_valid(u):
			u.earth_stacks = 0
			u.earth_hit_age = 0.0
			u.earth_decay_acc = 0.0
			u.earth_perm = 0.0
			u.soak_stacks = 0
			u.soak_time = 0.0
			u.air_slip_stacks = 0
			u.air_slip_time = 0.0
			u.air_tempest_ready = false
			u.stun_haste = 0.0

func _is(u, verb: String) -> bool:
	return u != null and is_instance_valid(u) and u is UnitBase and u.is_player_unit \
		and HeroVerbs.unit_has_verb(u, verb)

func _enemy(u) -> bool:
	return u != null and is_instance_valid(u) and not u.is_player_unit

func _nearest(from: UnitBase, exclude: Array) -> UnitBase:
	var best: UnitBase = null
	var best_d := 999999
	for e in mgr.enemy_units:
		if not mgr._is_alive(e) or e in exclude:
			continue
		var d: int = mgr._unit_dist(from, e)
		if d < best_d:
			best_d = d
			best = e
	return best

# ── Earth ────────────────────────────────────────────────────────────────────
func earth_per_stack() -> float:
	return val("earth_shred_pct") * counts.get(HeroVerbs.EARTH, 0)

# Stack shred alone, as a fraction (for Tectonic and tests).
func stack_shred(target: UnitBase) -> float:
	return target.earth_stacks * earth_per_stack()

# Armor/MR fraction removed for this hit. Stacks count for Earth heroes' hits,
# or for everyone's with Rubble; Tectonic's permanent shred counts for all.
func shred_for(target: UnitBase, attacker) -> float:
	if not active or not _enemy(target):
		return 0.0
	var s: float = target.earth_perm
	if target.earth_stacks > 0 and (val("earth_rubble") > 0.0 or _is(attacker, HeroVerbs.EARTH)):
		s += stack_shred(target)
	return clampf(s, 0.0, SHRED_CAP)

# ── Hit hooks (UnitBase.take_damage) ─────────────────────────────────────────
func damage_mult(target: UnitBase, attacker) -> float:
	if not active or not _enemy(target):
		return 1.0
	var m := 1.0
	if val("earth_landslide") > 0.0 and target.earth_stacks >= EARTH_MAX_STACKS \
			and _is(attacker, HeroVerbs.EARTH):
		m *= 1.0 + val("earth_landslide")
	if val("light_conductive") > 0.0 and target.stun_time > 0.0:
		m *= 1.0 + val("light_conductive")
	if val("water_riptide") > 0.0 and target.soak_stacks > 0 and _is(attacker, HeroVerbs.LIGHTNING):
		m *= 1.0 + val("water_riptide")
	return m

# After a direct (non-true) hit lands: Earth and Water hits add their stacks.
func on_hit(target: UnitBase, attacker, true_damage: bool) -> void:
	if not active or true_damage or not _enemy(target):
		return
	if val("earth_shred_pct") > 0.0 and _is(attacker, HeroVerbs.EARTH):
		var was := target.earth_stacks
		target.earth_stacks = mini(EARTH_MAX_STACKS, target.earth_stacks + 1)
		target.earth_hit_age = 0.0
		target.earth_decay_acc = 0.0
		if was < EARTH_MAX_STACKS and target.earth_stacks == EARTH_MAX_STACKS:
			GearFX.pop(target, "SHATTERED", GearFX.BRASS)
	if val("water_soak") > 0.0 and _is(attacker, HeroVerbs.WATER):
		var max_stacks: int = maxi(1, int(round(val("water_saturate"))))
		if target.soak_stacks == 0:
			GearFX.pop(target, "SOAKED", GearFX.MANA)
		target.soak_stacks = mini(max_stacks, target.soak_stacks + 1)
		target.soak_time = SOAK_SECS
		target.soak_slow = val("water_soak") * counts.get(HeroVerbs.WATER, 0)

# UnitBase death branch, before die().
func on_enemy_death(dead: UnitBase) -> void:
	if not active or not _enemy(dead):
		return
	if val("earth_aftershock") > 0.0 and dead.earth_stacks >= EARTH_MAX_STACKS:
		var n := _nearest(dead, [dead])
		if n:
			n.earth_stacks = mini(EARTH_MAX_STACKS,
				n.earth_stacks + int(round(dead.earth_stacks * val("earth_aftershock"))))
			n.earth_hit_age = 0.0
			mgr._spawn_skill_effect_sized(SkillEffect.Type.NATURE, n.global_position, 40.0)
	if val("light_arc") > 0.0 and dead.stun_time > 0.0:
		var n2 := _nearest(dead, [dead])
		if n2:
			mgr.apply_stun(n2, val("light_arc"))   # sourceless: not extended, not counted
			mgr._spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, n2.global_position, 36.0)

# ── Lightning (AutoBattleManager.apply_stun) ─────────────────────────────────
# Returns the stun duration to apply. Only stuns with a player hero source are
# extended (Lightning heroes) or counted (Thunderhead).
func on_stun(target: UnitBase, dur: float, source) -> float:
	if not active or not _enemy(target) or source == null or not is_instance_valid(source) \
			or not (source is UnitBase) or not source.is_player_unit:
		return dur
	if val("light_stun_ext") > 0.0 and _is(source, HeroVerbs.LIGHTNING):
		dur *= 1.0 + val("light_stun_ext") * counts.get(HeroVerbs.LIGHTNING, 0)
	if val("light_thunder") > 0.0:
		_stun_count += 1
		if _stun_count % THUNDER_EVERY == 0:
			_thunder_pending += 1
	return dur

func _thunder() -> void:
	var caster: UnitBase = null
	for u in mgr.player_units:
		if mgr._is_alive(u) and _is(u, HeroVerbs.LIGHTNING) \
				and (caster == null or u.magic_power > caster.magic_power):
			caster = u
	if caster == null:
		return
	var dmg := int(val("light_thunder") * caster.magic_power)
	for e in mgr.enemy_units.duplicate():
		if mgr._is_alive(e) and e.stun_time > 0.0 and dmg > 0:
			var pre: int = e.current_hp
			e.take_magic_damage(dmg, UnitBase.Element.LIGHTNING, caster)
			caster.damage_dealt += maxi(0, pre - e.current_hp)
			mgr._spawn_skill_effect_sized(SkillEffect.Type.LIGHTNING, e.global_position, 48.0)

# ── Water: Tidecall (UnitBase.heal) ──────────────────────────────────────────
func heal_mult(unit: UnitBase) -> float:
	if not active or val("water_tidecall") <= 0.0 or not unit.is_player_unit:
		return 1.0
	for e in mgr.enemy_units:
		if mgr._is_alive(e) and e.soak_stacks > 0 and mgr._unit_dist(unit, e) <= TIDECALL_RANGE:
			return 1.0 + val("water_tidecall")
	return 1.0

# ── Air (generic basic-attack path) ──────────────────────────────────────────
func on_basic_attack(unit: UnitBase, target: UnitBase) -> void:
	if not active or not _is(unit, HeroVerbs.AIR) or not mgr._is_alive(target):
		return
	var base := float(unit.attack_damage) * unit.outgoing_damage_multiplier() * unit.relic_outgoing_mult
	var frac: float = val("air_updraft") if val("air_updraft") > 0.0 else AIR_BASE_FRAC
	var chance: float = val("air_extra_chance") * counts.get(HeroVerbs.AIR, 0)
	if chance > 0.0 and randf() < chance:
		var second := _nearest(target, [target])
		if second:
			_air_hit(unit, second, int(base * frac))
			if val("air_chain") > 0.0 and randf() < chance * val("air_chain"):
				var third := _nearest(second, [target, second])
				if third:
					_air_hit(unit, third, int(base * frac))
	if unit.air_tempest_ready and val("air_tempest") > 0.0:
		unit.air_tempest_ready = false
		mgr._spawn_skill_effect_sized(SkillEffect.Type.TORNADO, unit.global_position, 60.0)
		for e in mgr.enemy_units.duplicate():
			if e != target and mgr._is_alive(e) and mgr._unit_dist(unit, e) <= unit.attack_range:
				_air_hit(unit, e, int(base * val("air_tempest")), false)

func _air_hit(unit: UnitBase, e: UnitBase, dmg: int, slip: bool = true) -> void:
	if dmg <= 0:
		return
	var pre: int = e.current_hp
	e.take_damage(dmg, unit.current_element, unit)
	unit.damage_dealt += maxi(0, pre - e.current_hp)
	mgr._spawn_skill_effect_sized(SkillEffect.Type.WIND_GLIMMER, e.global_position, 30.0, 0.5)
	if slip and val("air_slip") > 0.0:
		unit.air_slip_stacks = mini(SLIP_MAX, unit.air_slip_stacks + 1)
		unit.air_slip_time = SLIP_SECS
		unit.air_slip_pct = val("air_slip")

# ── Per-frame (AutoBattleManager._process) ───────────────────────────────────
func tick(dt: float) -> void:
	if not active:
		return
	var deepest := 0.0
	var any_stunned := false
	for e in mgr.enemy_units:
		if not mgr._is_alive(e):
			continue
		if e.stun_time > 0.0:
			any_stunned = true
		# Earth fade: all at once 4 s after the last hit, or one per Rubble step.
		if e.earth_stacks > 0:
			e.earth_hit_age += dt
			if e.earth_hit_age >= EARTH_FADE:
				var step := val("earth_rubble")
				if step > 0.0:
					e.earth_decay_acc += dt
					while e.earth_decay_acc >= step and e.earth_stacks > 0:
						e.earth_decay_acc -= step
						e.earth_stacks -= 1
				else:
					e.earth_stacks = 0
			deepest = maxf(deepest, stack_shred(e))
		if e.soak_time > 0.0:
			e.soak_time -= dt
			if e.soak_time <= 0.0:
				e.soak_stacks = 0
	# Tectonic: every enemy keeps a share of the deepest shred, for this fight.
	if val("earth_tectonic") > 0.0:
		_tectonic_t += dt
		if _tectonic_t >= TECTONIC_PERIOD:
			_tectonic_t -= TECTONIC_PERIOD
			if deepest > 0.0:
				for e in mgr.enemy_units:
					if mgr._is_alive(e):
						e.earth_perm = minf(SHRED_CAP, e.earth_perm + deepest * val("earth_tectonic"))
	# Deluge: freeze every Soaked enemy.
	if val("water_deluge") > 0.0:
		_deluge_t += dt
		if _deluge_t >= DELUGE_PERIOD:
			_deluge_t -= DELUGE_PERIOD
			for e in mgr.enemy_units.duplicate():
				if mgr._is_alive(e) and e.soak_stacks > 0:
					mgr.apply_stun(e, val("water_deluge"))   # sourceless
					mgr._spawn_skill_effect_sized(SkillEffect.Type.WAVE_WAKE, e.global_position, 40.0)
	# Overcharge: Lightning heroes' ult haste while anything is stunned.
	for u in mgr.player_units:
		if u and is_instance_valid(u):
			u.stun_haste = val("light_ult_haste") \
				if any_stunned and _is(u, HeroVerbs.LIGHTNING) else 0.0
			if u.air_slip_time > 0.0:
				u.air_slip_time -= dt
				if u.air_slip_time <= 0.0:
					u.air_slip_stacks = 0
	while _thunder_pending > 0:
		_thunder_pending -= 1
		_thunder()
	# Tempest: arm each Air hero's next attack.
	if val("air_tempest") > 0.0:
		_tempest_t += dt
		if _tempest_t >= TEMPEST_PERIOD:
			_tempest_t -= TEMPEST_PERIOD
			for u in mgr.player_units:
				if mgr._is_alive(u) and _is(u, HeroVerbs.AIR):
					u.air_tempest_ready = true
