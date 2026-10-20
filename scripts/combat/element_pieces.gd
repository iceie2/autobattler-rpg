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
# Role pieces (VD-22 roles, owner 2026-09-30) share this class and its hooks.
const PACK_SECS := 2.0           # Pack Hunt: another Fighter's hit counts this long
const RELENTLESS_MAX := 10
const BLOODRUSH_SECS := 3.0
const VOLLEY_EVERY := 5
const FIELD_WINDOW := 3.0        # Killing Field: 3 Ranged heroes within this
const FIELD_SECS := 4.0
const OVERLOAD_EVERY := 4
const DR_CAP := 0.6              # role damage reduction never above 60%
const VIGIL_LOCK := 1.5          # s after its own ult a Healer's heals don't charge
const VIGIL_RATE := 0.10         # Vigil refills at most 10% of an ult per second
var _miracle_used := false
var _ult_count := 0
const ROLE_VERBS := [HeroVerbs.TANK, HeroVerbs.MAGE, HeroVerbs.FIGHTER, HeroVerbs.RANGED, HeroVerbs.HEALER]

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
	for verb in [HeroVerbs.EARTH, HeroVerbs.LIGHTNING, HeroVerbs.WATER, HeroVerbs.AIR] + ROLE_VERBS:
		counts[verb] = mini(3, HeroVerbs.count_types(players, verb))
	_tectonic_t = 0.0
	_deluge_t = 0.0
	_tempest_t = 0.0
	_stun_count = 0
	_thunder_pending = 0
	_miracle_used = false
	_ult_count = 0
	for u in players + enemies:
		if u and is_instance_valid(u):
			u.pack_hits = {}
			u.relentless_target = null
			u.relentless_stacks = 0
			u.bloodrush_time = 0.0
			u.volley_count = 0
			u.field_hits = {}
			u.field_time = 0.0
			u.vigil_lock = 0.0
			u.vigil_bucket = 0.0
			u.role_aspd = val("role_ranged_aspd") * counts.get(HeroVerbs.RANGED, 0) \
				if _is(u, HeroVerbs.RANGED) else 0.0
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
func damage_mult(target: UnitBase, attacker, is_magic: bool = false) -> float:
	if not active or target == null or not is_instance_valid(target):
		return 1.0
	if target.is_player_unit:
		return _role_taken_mult(target)
	var m := _role_dealt_mult(target, attacker, is_magic)
	if val("earth_landslide") > 0.0 and target.earth_stacks >= EARTH_MAX_STACKS \
			and _is(attacker, HeroVerbs.EARTH):
		m *= 1.0 + val("earth_landslide")
	if val("light_conductive") > 0.0 and target.stun_time > 0.0:
		m *= 1.0 + val("light_conductive")
	if val("water_riptide") > 0.0 and target.soak_stacks > 0 and _is(attacker, HeroVerbs.LIGHTNING):
		m *= 1.0 + val("water_riptide")
	return m

# ── Roles: damage in and out ─────────────────────────────────────────────────
# Enemy target: Arcane Circle (Mages' magic damage), Warband (Fighters'
# physical damage), Pack Hunt, Relentless, Longshot, Killing Field.
func _role_dealt_mult(target: UnitBase, attacker, is_magic: bool) -> float:
	var m := 1.0
	if val("role_mage_dmg") > 0.0 and is_magic and _is(attacker, HeroVerbs.MAGE):
		m *= 1.0 + val("role_mage_dmg") * counts.get(HeroVerbs.MAGE, 0)
	if _is(attacker, HeroVerbs.FIGHTER):
		if val("role_fighter_dmg") > 0.0 and not is_magic:
			m *= 1.0 + val("role_fighter_dmg") * counts.get(HeroVerbs.FIGHTER, 0)
		if val("role_fighter_pack") > 0.0:
			for id in target.pack_hits:
				if id != attacker.get_instance_id():
					m *= 1.0 + val("role_fighter_pack")
					break
		if val("role_fighter_relentless") > 0.0 and attacker.relentless_target == target:
			m *= 1.0 + val("role_fighter_relentless") * attacker.relentless_stacks
	if val("role_ranged_longshot") > 0.0 and not is_magic and _is(attacker, HeroVerbs.RANGED):
		m *= 1.0 + val("role_ranged_longshot") * mgr._unit_dist(attacker, target)
	if val("role_ranged_field") > 0.0 and target.field_time > 0.0:
		m *= 1.0 + val("role_ranged_field")
	return m

# Player target: Bulwark Oath (Tanks), Last Wall (heroes behind a living
# Tank), Covered (Ranged heroes with an ally in front). Capped at DR_CAP.
func _role_taken_mult(u: UnitBase) -> float:
	var cut := 0.0
	var tank := _is(u, HeroVerbs.TANK)
	if tank and val("role_tank_dr") > 0.0:
		cut += val("role_tank_dr") * counts.get(HeroVerbs.TANK, 0)
	if not tank and val("role_tank_wall") > 0.0 and _tank_in_front(u):
		cut += val("role_tank_wall")
	if val("role_ranged_covered") > 0.0 and _is(u, HeroVerbs.RANGED) and _ally_in_front(u):
		cut += val("role_ranged_covered")
	return 1.0 - minf(cut, DR_CAP)

# Player rows: a smaller y is nearer the front (UnitBase.is_front_row).
func _tank_in_front(u: UnitBase) -> bool:
	for t in mgr.player_units:
		if t != u and mgr._is_alive(t) and _is(t, HeroVerbs.TANK) \
				and t.home_position.y < u.home_position.y:
			return true
	return false

func _ally_in_front(u: UnitBase) -> bool:
	for a in mgr.player_units:
		if a != u and mgr._is_alive(a) and a.grid_position.x == u.grid_position.x \
				and a.grid_position.y < u.grid_position.y:
			return true
	return false

# Shared Burden: part of a non-Tank hero's damage moves to the nearest Tank,
# as true damage (already mitigated; Tanks never redirect, so no loop).
func redirect(target: UnitBase, dmg: int, attacker) -> int:
	if not active or val("role_tank_share") <= 0.0 or not target.is_player_unit \
			or _is(target, HeroVerbs.TANK) or dmg <= 1:
		return dmg
	var tank: UnitBase = null
	var best := 999999
	for t in mgr.player_units:
		if t != target and mgr._is_alive(t) and _is(t, HeroVerbs.TANK):
			var d: int = mgr._unit_dist(target, t)
			if d < best:
				best = d
				tank = t
	if tank == null:
		return dmg
	var moved := int(dmg * val("role_tank_share"))
	if moved <= 0:
		return dmg
	tank.take_damage(moved, UnitBase.Element.NORMAL, attacker, true)
	return dmg - moved

# Iron Will: Tanks' ult charge from damage taken.
func taken_charge_mult(u: UnitBase) -> float:
	if active and val("role_tank_charge") > 0.0 and _is(u, HeroVerbs.TANK):
		return 1.0 + val("role_tank_charge")
	return 1.0

# Miracle: once per fight, while a Healer lives, the first hero who would die
# is healed instead. Returns true when it saved the unit.
func try_miracle(u: UnitBase) -> bool:
	if not active or _miracle_used or val("role_healer_miracle") <= 0.0 \
			or not u.is_player_unit or u.is_summoned:
		return false
	var healer_alive := false
	for h in mgr.player_units:
		if h != u and mgr._is_alive(h) and _is(h, HeroVerbs.HEALER):
			healer_alive = true
			break
	if not healer_alive:
		return false
	_miracle_used = true
	u.current_hp = maxi(1, int(round(u.max_hp * val("role_healer_miracle"))))
	GearFX.pop(u, "MIRACLE", GearFX.GOLD, true)
	mgr._spawn_skill_effect_sized(SkillEffect.Type.HOLY_LIGHT, u.global_position, 50.0)
	return true

# ── Roles: casts (AutoBattleManager) ─────────────────────────────────────────
func skill_cost(u: UnitBase) -> int:
	var cost := u.skill_mana_cost_before_modifiers()
	if active and val("role_mage_mana") > 0.0 and _is(u, HeroVerbs.MAGE):
		return int(round(cost * (1.0 - val("role_mage_mana"))))
	return cost

# Twincast: a Mage skill's damage lands again at half on its target.
func on_skill_cast(u: UnitBase, target, skill_dmg: int) -> void:
	if not active or val("role_mage_twincast") <= 0.0 or skill_dmg <= 0 \
			or not _is(u, HeroVerbs.MAGE) or randf() >= val("role_mage_twincast"):
		return
	var tgt: UnitBase = target if mgr._is_alive(target) and _enemy(target) else _nearest(u, [])
	if tgt == null:
		return
	var pre: int = tgt.current_hp
	tgt.take_magic_damage(int(skill_dmg * 0.5), u.current_element, u)
	u.damage_dealt += maxi(0, pre - tgt.current_hp)
	GearFX.pop(u, "TWINCAST", GearFX.VIOLET)

# Resonance, Overload, and the Vigil lock. Resonance never charges the caster,
# so a cast can only speed the OTHER Mages (bounded: 3 Mages x 15% < 1 ult).
func on_ult_cast(caster: UnitBase) -> void:
	if not active or not caster.is_player_unit:
		return
	caster.vigil_lock = VIGIL_LOCK
	if val("role_mage_resonance") > 0.0 and _is(caster, HeroVerbs.MAGE):
		for m in mgr.player_units:
			if m != caster and mgr._is_alive(m) and _is(m, HeroVerbs.MAGE) \
					and not m.ultimate_ready and m.ultimate_charge_max > 0:
				m.ultimate_charge = mini(m.ultimate_charge_max,
					m.ultimate_charge + int(round(m.ultimate_charge_max * val("role_mage_resonance"))))
				if m.ultimate_charge >= m.ultimate_charge_max:
					m.ultimate_ready = true
	if val("role_mage_overload") > 0.0:
		_ult_count += 1
		if _ult_count % OVERLOAD_EVERY == 0:
			_overload()

func _overload() -> void:
	var total := 0
	var source: UnitBase = null
	for m in mgr.player_units:
		if mgr._is_alive(m) and _is(m, HeroVerbs.MAGE):
			total += m.magic_power
			if source == null or m.magic_power > source.magic_power:
				source = m
	var dmg := int(total * val("role_mage_overload"))
	if source == null or dmg <= 0:
		return
	for e in mgr.enemy_units.duplicate():
		if mgr._is_alive(e):
			var pre: int = e.current_hp
			e.take_magic_damage(dmg, source.current_element, source)
			source.damage_dealt += maxi(0, pre - e.current_hp)
			mgr._spawn_skill_effect_sized(SkillEffect.Type.CHAOS_BOLT, e.global_position, 44.0)

# ── Roles + Water: healing (UnitBase.heal) ───────────────────────────────────
# `healer` is the hero who healed, when the heal site knows it.
func after_heal(u: UnitBase, healer, healed: int, excess: int) -> void:
	if not active or not u.is_player_unit:
		return
	if val("role_healer_overflow") > 0.0 and excess > 0:
		var cap := int(u.max_hp * val("role_healer_overflow"))
		var add := mini(excess, cap - u.current_shield)
		if add > 0:
			u.current_shield += add
	if healed <= 0 or not _is(healer, HeroVerbs.HEALER):
		return
	if val("role_healer_radiance") > 0.0:
		var e := _nearest(u, [])
		var dmg := int(healed * val("role_healer_radiance"))
		if e and dmg > 0:
			var pre: int = e.current_hp
			e.take_magic_damage(dmg, healer.current_element, healer)
			healer.damage_dealt += maxi(0, pre - e.current_hp)
	# Vigil: rate-capped, and never from the Healer's own ult (VIGIL_LOCK).
	if val("role_healer_vigil") > 0.0 and healer.vigil_lock <= 0.0 and healer.ultimate_charge_max > 0:
		var want := int(healed * val("role_healer_vigil"))
		var give := mini(want, int(healer.vigil_bucket))
		if give > 0:
			healer.vigil_bucket -= give
			healer._charge_ultimate(give)

# After a direct (non-true) hit lands: Earth and Water hits add their stacks.
func on_hit(target: UnitBase, attacker, true_damage: bool, dmg: int = 0) -> void:
	if not active or true_damage or target == null:
		return
	if target.is_player_unit:
		# Retribution: Tanks hit back, as true damage (true hits never reflect).
		if val("role_tank_thorns") > 0.0 and dmg > 0 and _is(target, HeroVerbs.TANK) \
				and _enemy(attacker) and attacker.current_hp > 0:
			var r := int(dmg * val("role_tank_thorns"))
			if r > 0:
				var pre: int = attacker.current_hp
				attacker.take_damage(r, UnitBase.Element.NORMAL, target, true)
				target.damage_dealt += maxi(0, pre - attacker.current_hp)
		return
	if _is(attacker, HeroVerbs.FIGHTER):
		if val("role_fighter_pack") > 0.0:
			target.pack_hits[attacker.get_instance_id()] = PACK_SECS
		if val("role_fighter_relentless") > 0.0:
			if attacker.relentless_target != target:
				attacker.relentless_target = target
				attacker.relentless_stacks = 0
			attacker.relentless_stacks = mini(RELENTLESS_MAX, attacker.relentless_stacks + 1)
	if val("role_ranged_field") > 0.0 and _is(attacker, HeroVerbs.RANGED):
		target.field_hits[attacker.unit_class] = FIELD_WINDOW
		if target.field_hits.size() >= 3 and target.field_time <= 0.0:
			GearFX.pop(target, "MARKED", GearFX.BLOOD)
		if target.field_hits.size() >= 3:
			target.field_time = FIELD_SECS
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
func on_enemy_death(dead: UnitBase, killer = null) -> void:
	if not active or not _enemy(dead):
		return
	# Bloodrush / Onslaught: a Fighter's kill.
	if _is(killer, HeroVerbs.FIGHTER):
		if val("role_fighter_bloodrush") > 0.0:
			killer.bloodrush_time = BLOODRUSH_SECS
			killer.bloodrush_pct = val("role_fighter_bloodrush")
		if val("role_fighter_onslaught") > 0.0 and randf() < val("role_fighter_onslaught"):
			killer.attack_cooldown = 0.0
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
func heal_mult(unit: UnitBase, healer = null) -> float:
	if not active or not unit.is_player_unit:
		return 1.0
	var m := 1.0
	# Mending Circle: heals FROM Healers.
	if val("role_healer_heal") > 0.0 and _is(healer, HeroVerbs.HEALER):
		m *= 1.0 + val("role_healer_heal") * counts.get(HeroVerbs.HEALER, 0)
	if val("water_tidecall") > 0.0:
		for e in mgr.enemy_units:
			if mgr._is_alive(e) and e.soak_stacks > 0 and mgr._unit_dist(unit, e) <= TIDECALL_RANGE:
				m *= 1.0 + val("water_tidecall")
				break
	return m

# ── Air + Ranged (generic basic-attack path) ─────────────────────────────────
func on_basic_attack(unit: UnitBase, target: UnitBase) -> void:
	if not active or not mgr._is_alive(target):
		return
	var base := float(unit.attack_damage) * unit.outgoing_damage_multiplier()   # relics: take_damage applies them
	# Volley: every 5th Ranged attack also fires at a second enemy.
	if val("role_ranged_volley") > 0.0 and _is(unit, HeroVerbs.RANGED):
		unit.volley_count += 1
		if unit.volley_count % VOLLEY_EVERY == 0:
			var v2 := _nearest(target, [target])
			if v2:
				_air_hit(unit, v2, int(base * val("role_ranged_volley")), false)
	if not _is(unit, HeroVerbs.AIR):
		return
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
		# Role marks: Pack Hunt hits and Killing Field hits age out.
		for id in e.pack_hits.keys():
			e.pack_hits[id] = float(e.pack_hits[id]) - dt
			if e.pack_hits[id] <= 0.0:
				e.pack_hits.erase(id)
		for c in e.field_hits.keys():
			e.field_hits[c] = float(e.field_hits[c]) - dt
			if e.field_hits[c] <= 0.0:
				e.field_hits.erase(c)
		if e.field_time > 0.0:
			e.field_time -= dt
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
			if u.bloodrush_time > 0.0:
				u.bloodrush_time -= dt
			if u.vigil_lock > 0.0:
				u.vigil_lock -= dt
			if u.ultimate_charge_max > 0:
				u.vigil_bucket = minf(u.ultimate_charge_max * VIGIL_RATE,
					u.vigil_bucket + u.ultimate_charge_max * VIGIL_RATE * dt)
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
