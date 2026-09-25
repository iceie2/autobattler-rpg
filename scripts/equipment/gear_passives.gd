extends RefCounted
class_name GearPassives

# Combat runtime for the 36 item passives (EQUIPMENT_GREEN_PAIRS.md). Every
# hook is a static call from an existing choke point in UnitBase or
# AutoBattleManager, and every hook returns immediately for a unit with no
# gear_levels, so the legacy equipment path is untouched while the switch is off.
#
# Vocabulary (worksheet): "basic" = a basic attack landing (UnitBase.gear_basic_hit
# is true while it resolves); "skill" = damage inside the caster's skill window
# (opened by an original active-skill cast, closed by an ultimate); "direct" =
# anything but a DoT tick (DoTs arrive as true_damage outside a basic hit).
# Per-fight state lives in unit.gear and is wiped by battle_start.

const SKILL_WINDOW := 1.5        # seconds a cast's delayed hits still count as "skill"
const SUMMON_KILL_CAP := 5       # #27: summoned kills that count per fight (proposed)
const WARD_CAP := 0.24           # #3 pool cap, fraction of max HP
const RHYTHM_CAP := 0.16         # #5 pool cap
const POOL_ORDER := ["bastion", "ward", "rhythm"]

static func lv(u, key: String) -> float:
	return float(u.gear_levels.get(key, 0))

static func _bar(u) -> HealthBar:
	return u.get("health_bar") as HealthBar if u and is_instance_valid(u) else null

static func has(u) -> bool:
	return u != null and is_instance_valid(u) and u is UnitBase and not u.gear_levels.is_empty()

static func _v(u, key: String, field: String) -> float:
	return GearCatalog.value(key, field, lv(u, key))

static func _t(g: Dictionary, key: String) -> float:
	return float(g.get(key, 0.0))

# ── Fight lifecycle ───────────────────────────────────────────────────────────
static func battle_start(u: UnitBase) -> void:
	_revert(u)
	u.gear = {}
	u.gear_shield = 0
	var bar := _bar(u)
	if bar:
		bar.set_gear_shield(0.0)
		bar.set_gear_pips(0, 0, Color.WHITE)
		bar.set_gear_badge("")
	if not has(u):
		return
	# #16 Attunement: a Magic Power multiplier for the fight, on top of every
	# flat bonus. Reverted at the next battle_start / battle_end, never stacked.
	if lv(u, "attunement") > 0.0:
		var add := int(round(u.magic_power * _v(u, "attunement", "mp_pct")))
		u.magic_power += add
		u.gear["mp_added"] = add
	u.gear["pools"] = {"bastion": 0.0, "ward": 0.0, "rhythm": 0.0}
	_refresh_bar(u)

static func battle_end(u: UnitBase) -> void:
	if not (u and is_instance_valid(u)):
		return
	_revert(u)
	u.gear = {}
	u.gear_shield = 0
	var bar := _bar(u)
	if bar:
		bar.set_gear_shield(0.0)
		bar.set_gear_pips(0, 0, Color.WHITE)

static func _revert(u: UnitBase) -> void:
	var add := int(u.gear.get("mp_added", 0))
	if add != 0:
		u.magic_power -= add
		u.gear.erase("mp_added")

# ── Per-frame (called at the top of AutoBattleManager._regen_tick) ─────────────
static func tick(u: UnitBase, dt: float) -> void:
	if u.gear.is_empty():
		return
	var g := u.gear
	for key in ["ward_icd", "bulwark_cd", "wound_t", "tempo_t", "keen", "riposte_t",
			"sustain_t", "counter_t", "vital_t", "recovery_t", "window"]:
		if g.has(key):
			g[key] = maxf(0.0, float(g[key]) - dt)
	# Spellguard stacks expire on their own timers.
	if g.has("guard"):
		var left: Array = []
		for s in g["guard"]:
			s[0] = float(s[0]) - dt
			if float(s[0]) > 0.0:
				left.append(s)
		g["guard"] = left
	if not has(u):
		_refresh_bar(u)
		return
	# #12 Cadence clears on a movement step or 3s without a landed hit.
	g["cadence_t"] = _t(g, "cadence_t") + dt
	if int(g.get("cadence", 0)) > 0 and (u.is_moving or _t(g, "cadence_t") >= 3.0):
		g["cadence"] = 0
	# #5 Iron Rhythm's three-hit count resets after 4s without a landed hit.
	g["rhythm_t"] = _t(g, "rhythm_t") + dt
	if _t(g, "rhythm_t") >= 4.0:
		g["rhythm_hits"] = 0
	# #6 Desperation: pulse when a new 25% step is reached.
	if lv(u, "desperation") > 0.0 and u.max_hp > 0:
		var steps := _despair_steps(u)
		if steps > int(g.get("despair", 0)):
			GearFX.bubble(u, GearFX.BLOOD, 30.0 + 10.0 * steps)
		g["despair"] = steps
	_regen(u, g, dt)
	_refresh_bar(u)

static func _regen(u: UnitBase, g: Dictionary, dt: float) -> void:
	var hp_rate := 0.0
	var mp_rate := 0.0
	if lv(u, "regeneration") > 0.0:                                     # #8
		hp_rate += u.max_hp * _v(u, "regeneration", "hp_pct_s")
		if u.current_hp < u.max_hp and GearFX.can(u, "regen", 0.8):
			GearFX.motes(u, GearFX.HEAL, 3)
	if lv(u, "rest_cycle") > 0.0 and u.skill_cd_time > 0.0:             # #26
		hp_rate += u.max_hp * _v(u, "rest_cycle", "hp_pct_s")
		mp_rate += _v(u, "rest_cycle", "mana_s")
		if GearFX.can(u, "rest", 0.9):
			GearFX.motes(u, GearFX.HEAL, 2)
			GearFX.motes(u, GearFX.MANA, 2)
	if lv(u, "sustained_assault") > 0.0 and _t(g, "sustain_t") > 0.0:   # #30
		hp_rate += u.max_hp * _v(u, "sustained_assault", "hp_pct_s")
		mp_rate += _v(u, "sustained_assault", "mana_s")
	if lv(u, "recovery") > 0.0 and _t(g, "recovery_t") > 0.0:           # #35
		hp_rate += u.max_hp * _v(u, "recovery", "hp_pct_s")
		mp_rate += _v(u, "recovery", "mana_s")
	# #36 Equilibrium: wasted regen on a full pool feeds the other one.
	if lv(u, "equilibrium") > 0.0:
		var pct := _v(u, "equilibrium", "pct")
		var hp_full := u.current_hp >= u.max_hp
		var mp_full := u.max_mana <= 0 or u.current_mana >= u.max_mana
		if hp_full and not mp_full:
			mp_rate += pct * (u.hp_regen + hp_rate)
		elif mp_full and not hp_full and u.max_mana > 0:
			hp_rate += pct * (u.mana_regen + mp_rate)
		if hp_full != mp_full and GearFX.can(u, "equil", 1.2):
			GearFX.mark(u, "⇅", GearFX.VIOLET)
	if hp_rate > 0.0 and u.current_hp < u.max_hp:
		u.hp_regen_accum += hp_rate * dt
	if mp_rate > 0.0 and u.current_mana < u.max_mana:
		u.mp_regen_accum += mp_rate * dt

static func _despair_steps(u: UnitBase) -> int:
	var missing := 1.0 - float(u.current_hp) / float(maxi(u.max_hp, 1))
	return clampi(int(floor(missing / 0.25)), 0, 3)

# Stack pips under the HP bar (wearer's own stacks; enemies show Sunder) and the
# Battle Haste kill badge.
static func _refresh_bar(u: UnitBase) -> void:
	var bar := _bar(u)
	if not bar:
		return
	var g := u.gear
	var n := 0
	var mx := 0
	var c := Color.WHITE
	if has(u):
		if lv(u, "cadence") > 0.0:
			n = int(g.get("cadence", 0)); mx = 5; c = Color(1.0, 0.78, 0.2)
		elif lv(u, "critical_focus") > 0.0:
			n = int(g.get("focus", 0)); mx = 5; c = GearFX.GOLD
		elif lv(u, "iron_rhythm") > 0.0:
			n = int(g.get("rhythm_hits", 0)); mx = 3; c = GearFX.VIOLET
		elif not g.get("guard", []).is_empty():
			n = mini(5, g["guard"].size()); mx = 5; c = GearFX.VIOLET
	elif int(g.get("sunder", 0)) > 0:
		n = int(g["sunder"]); mx = 5; c = GearFX.STEEL
	bar.set_gear_pips(n, mx, c)
	if has(u) and lv(u, "battle_haste") > 0.0:
		bar.set_gear_badge("⚔%d" % _counter(u, "haste_kills"))

# ── Item counters (#23 Clockwork casts, #27 Battle Haste kills) ────────────────
static func _counter(u: UnitBase, name: String) -> int:
	var best := 0
	for item in u.gear_items:
		if item.passive_levels.has(ComponentEquipmentItem.COUNTERS[name]):
			best = maxi(best, int(item.counters.get(name, 0)))
	return best

static func _bump_counter(u: UnitBase, name: String, delta: int) -> void:
	for item in u.gear_items:
		if item.passive_levels.has(ComponentEquipmentItem.COUNTERS[name]):
			item.counters[name] = maxi(0, int(item.counters.get(name, 0)) + delta)

# ── Item shields (#1 / #3 / #5): one violet pool, tracked per source ──────────
static func _add_shield(u: UnitBase, pool: String, amount: float, cap_frac: float = -1.0) -> bool:
	var pools: Dictionary = u.gear.get("pools", {})
	var add := amount
	if cap_frac > 0.0:
		add = minf(amount, u.max_hp * cap_frac - float(pools.get(pool, 0.0)))
	if add < 1.0:
		return false
	pools[pool] = float(pools.get(pool, 0.0)) + add
	u.gear["pools"] = pools
	u.gear_shield += int(round(add))
	var bar := _bar(u)
	if bar:
		bar.set_gear_shield(float(u.gear_shield))
	return true

# ── Cooldowns and attack timing ───────────────────────────────────────────────
# Ability Haste: base x 100 / (100 + haste), floor 1s (or the base if it is
# already under 1s). Identical to the old value when haste is 0.
static func skill_cooldown(u: UnitBase) -> float:
	var base := float(u.skill_cooldown_max)
	if u.ability_haste <= 0:
		return base
	return maxf(minf(base, 1.0), base * 100.0 / (100.0 + float(u.ability_haste)))

# Multiplier on the wait before the next basic attack. Enemies read it too:
# a Riposte slow is stored on the attacker's own gear state.
static func attack_wait_mult(u: UnitBase) -> float:
	if u.gear.is_empty():
		return 1.0
	var g := u.gear
	var bonus := 0.0
	if has(u):
		bonus += int(g.get("cadence", 0)) * _v(u, "cadence", "aspd_stack")          # #12
		if _t(g, "tempo_t") > 0.0:
			bonus += _v(u, "spell_tempo", "aspd")                                   # #18
		if lv(u, "battle_haste") > 0.0:
			bonus += _v(u, "battle_haste", "rate") * log(1.0 + _counter(u, "haste_kills"))  # #27
	var slow := float(g.get("riposte_slow", 0.0)) if _t(g, "riposte_t") > 0.0 else 0.0  # #29
	var mult := 1.0 / ((1.0 + bonus) * (1.0 - clampf(slow, 0.0, 0.9)))
	if _t(g, "keen") > 0.0:                                                       # #28
		mult *= 1.0 - float(g.get("keen_pct", 0.0))
		g["keen"] = 0.0
		GearFX.spark(u, GearFX.WHITE)
	return mult

# ── Crits (read inside UnitBase.attack's crit roll) ───────────────────────────
static func crit_bonus(u: UnitBase) -> float:
	if not has(u):
		return 0.0
	var g := u.gear
	var bonus := 0.0
	if lv(u, "desperation") > 0.0:
		bonus += _despair_steps(u) * _v(u, "desperation", "crit_step")               # #6
	bonus += int(g.get("focus", 0)) * _v(u, "critical_focus", "crit_stack")          # #31
	if _t(g, "counter_t") > 0.0:
		bonus += _v(u, "counterstrike", "crit")                                     # #32
	return bonus

static func crit_damage_bonus(u: UnitBase) -> float:
	return _v(u, "critical_focus", "critdmg") if has(u) else 0.0

# The swing has rolled: Counterstrike's charge is spent crit or not (#32).
static func on_attack_roll(u: UnitBase) -> void:
	if has(u) and _t(u.gear, "counter_t") > 0.0:
		u.gear["counter_t"] = 0.0

# ── Skill casts (AutoBattleManager active-skill branch) ───────────────────────
static func before_cast(u: UnitBase) -> void:
	if not has(u):
		return
	# #21 Empty Reservoir snapshots mana BEFORE the cost is paid.
	u.gear["reservoir"] = 1.0 - float(u.current_mana) / float(u.max_mana) if u.max_mana > 0 else -1.0
	u.gear["window"] = SKILL_WINDOW
	u.gear["cast_id"] = int(u.gear.get("cast_id", 0)) + 1
	# #17 only echoes skills that hit an enemy: remember the target's HP so
	# after_cast can tell a damaging cast from a heal / self-buff / ground AoE.
	var t: UnitBase = u.target_unit
	u.gear["echo_hp"] = t.current_hp if t and is_instance_valid(t) else -1

static func on_ultimate(u: UnitBase) -> void:
	if not u.gear.is_empty():
		u.gear["window"] = 0.0

static func after_cast(u: UnitBase, target: UnitBase, opponents: Array, allies: Array, mgr) -> void:
	if not has(u) or bool(u.gear.get("echo", false)):
		return
	var g := u.gear
	# Measured before Clockwork adds its own hit to the same target.
	var hit_enemy: bool = target != null and is_instance_valid(target) \
		and target.current_hp < int(g.get("echo_hp", -1))
	if lv(u, "aftercast_ward") > 0.0 and _t(g, "ward_icd") <= 0.0:                 # #3
		if _add_shield(u, "ward", u.max_hp * _v(u, "aftercast_ward", "shield"), WARD_CAP):
			g["ward_icd"] = 6.0
			GearFX.bubble(u, GearFX.VIOLET, 36.0)
	if lv(u, "second_wind") > 0.0:                                               # #4
		u.heal(int(round(u.max_hp * _v(u, "second_wind", "heal"))))
		GearFX.swirl(u, GearFX.HEAL)
	if lv(u, "spell_tempo") > 0.0:                                               # #18
		g["tempo_t"] = 4.0
		GearFX.speed(u)
	if lv(u, "battle_charge") > 0.0 and u.ultimate_charge_max > 0 and not u.ultimate_ready:  # #22
		u._charge_ultimate(int(round(_v(u, "battle_charge", "charge"))))
		GearFX.spark(u, GearFX.GOLD)
	if lv(u, "spellguard") > 0.0:                                                # #25
		var guard: Array = g.get("guard", [])
		guard.append([5.0 + 15.0 * GearCatalog.curve(lv(u, "spellguard")), _v(u, "spellguard", "def")])
		g["guard"] = guard
		GearFX.rings(u, mini(guard.size(), 5))
	if lv(u, "clockwork") > 0.0:                                                 # #23
		_bump_counter(u, "clockwork_casts", 1)
		var n := _counter(u, "clockwork_casts")
		var hit_target := _cast_target(u, target, opponents)
		if hit_target:
			var dmg := int(round(_v(u, "clockwork", "dmg") * log(1.0 + n)))
			if dmg > 0:
				g["proc"] = true
				var pre := hit_target.current_hp
				hit_target.take_damage(dmg, UnitBase.Element.NORMAL, u, false, 0, true)
				g["proc"] = false
				u.damage_dealt += maxi(0, pre - hit_target.current_hp)
				GearFX.pop(hit_target, "⚙×%d" % n, GearFX.BRASS)
	if lv(u, "spell_echo") > 0.0 and hit_enemy and target.current_hp > 0 \
			and randf() < _v(u, "spell_echo", "chance"):  # #17
		_echo(u, target, allies, mgr)

# No enemy target (self-buff, heal, ground AoE): the current attack target,
# else the nearest living enemy (#23 targeting decision).
static func _cast_target(u: UnitBase, target: UnitBase, opponents: Array) -> UnitBase:
	for cand in [target, u.target_unit]:
		if cand and is_instance_valid(cand) and cand.current_hp > 0 and cand.is_player_unit != u.is_player_unit:
			return cand
	var best: UnitBase = null
	var best_d := INF
	for o in opponents:
		if o and is_instance_valid(o) and o.current_hp > 0:
			var d: float = u.global_position.distance_squared_to(o.global_position)
			if d < best_d:
				best_d = d
				best = o
	return best

# #17: a free copy on the same enemy. No mana, no cooldown, no crit, no echo of
# the echo, and no cast-triggered passives (echo flag).
static func _echo(u: UnitBase, target: UnitBase, allies: Array, mgr) -> void:
	if mgr == null or not mgr.has_method("_use_skill"):
		return
	var saved_target: UnitBase = u.target_unit
	var saved_crit: float = u.crit_chance
	u.gear["echo"] = true
	u.target_unit = target
	u.crit_chance = 0.0
	mgr._use_skill(u, [target], allies)
	u.crit_chance = saved_crit
	u.target_unit = saved_target
	u.gear["echo"] = false
	GearFX.pop(u, "ECHO", GearFX.VIOLET, true)
	GearFX.bubble(u, Color(GearFX.VIOLET, 0.6), 52.0)

# ── Damage pipeline (UnitBase.take_damage) ────────────────────────────────────
# Pre-mitigation multiplier on the attacker's SKILL damage (#19, #21).
static func skill_damage_mult(attacker, victim: UnitBase, amount: int, true_damage: bool) -> int:
	if not has(attacker) or attacker.gear_basic_hit or true_damage:
		return amount
	var g: Dictionary = attacker.gear
	if _t(g, "window") <= 0.0 or bool(g.get("proc", false)):
		return amount
	var out := float(amount)
	var echo := bool(g.get("echo", false))
	if lv(attacker, "empty_reservoir") > 0.0 and not echo and float(g.get("reservoir", -1.0)) > 0.0:  # #21
		var bonus := _v(attacker, "empty_reservoir", "bonus") * float(g["reservoir"])
		out *= 1.0 + bonus
		if GearFX.can(victim, "reservoir"):
			GearFX.spark(victim, Color(GearFX.VIOLET, 0.4 + bonus * 2.0))
	if lv(attacker, "arcane_precision") > 0.0 and not echo \
			and randf() < _v(attacker, "arcane_precision", "chance"):                # #19
		out *= 1.5
		GearFX.pop(victim, "1.5×", GearFX.VIOLET, true)
	if lv(attacker, "attunement") > 0.0 and GearFX.can(victim, "attune"):          # #16 cue
		GearFX.spark(victim, GearFX.VIOLET)
	return int(round(out))

# Effective armor/MR: Spellguard stacks add, Sunder stacks shred (#25, #14).
static func effective_armor(u: UnitBase, armor: int) -> int:
	if u.gear.is_empty():
		return armor
	var a := float(armor)
	for s in u.gear.get("guard", []):
		a += float(s[1])
	var shred := int(u.gear.get("sunder", 0)) * float(u.gear.get("sunder_pct", 0.0))
	return int(round(a * (1.0 - clampf(shred, 0.0, 1.0))))

# Before ordinary shields: Bulwark block (#7), then the item-shield pool.
# Returns the damage left for ordinary shields/HP (0 = fully stopped).
static func pre_shield(u: UnitBase, dmg: int, attacker, true_damage: bool) -> int:
	if u.gear.is_empty() or dmg <= 0:
		return dmg
	var basic: bool = attacker is UnitBase and is_instance_valid(attacker) and attacker.gear_basic_hit
	var direct := not true_damage or basic
	if direct and lv(u, "bulwark") > 0.0 and _t(u.gear, "bulwark_cd") <= 0.0:
		u.gear["bulwark_cd"] = GearCatalog.shrink(24.0, 6.0, lv(u, "bulwark"))
		GearFX.flare(u, GearFX.STEEL)
		GearFX.pop(u, "BLOCKED", GearFX.STEEL, true)
		return 0
	if u.gear_shield <= 0:
		return dmg
	var absorbed := mini(u.gear_shield, dmg)
	u.gear_shield -= absorbed
	var left := float(absorbed)
	var pools: Dictionary = u.gear.get("pools", {})
	for key in POOL_ORDER:
		var take := minf(left, float(pools.get(key, 0.0)))
		pools[key] = float(pools.get(key, 0.0)) - take
		left -= take
	var bar := _bar(u)
	if bar:
		bar.set_gear_shield(float(u.gear_shield))
	if absorbed >= dmg:
		u.spawn_damage_text(absorbed, UnitBase.Element.NORMAL)
	return dmg - absorbed

# After ordinary shields: #20 Mana Shield pays part of a direct hit with mana.
static func post_shield(u: UnitBase, dmg: int, attacker, true_damage: bool) -> int:
	if not has(u) or dmg <= 0 or lv(u, "mana_shield") <= 0.0 or u.current_mana <= 0:
		return dmg
	var basic: bool = attacker is UnitBase and is_instance_valid(attacker) and attacker.gear_basic_hit
	if true_damage and not basic:
		return dmg
	var redirect := int(floor(dmg * _v(u, "mana_shield", "pct")))
	redirect = mini(redirect, u.current_mana * 2)
	if redirect <= 0:
		return dmg
	var cost := int(ceil(redirect / 2.0))
	u.current_mana -= cost
	if GearFX.can(u, "manashield"):
		GearFX.bubble(u, GearFX.MANA, 40.0)
		GearFX.pop(u, "-%d mana" % cost, GearFX.MANA)
	return dmg - redirect

# Heal received after Deep Wound (#13).
static func heal_received(u: UnitBase, amount: int) -> int:
	if u.gear.is_empty() or _t(u.gear, "wound_t") <= 0.0:
		return amount
	return int(round(amount * (1.0 - float(u.gear.get("wound_cut", 0.0)))))

# End of take_damage. hp_dmg = HP actually lost; raw = post-mitigation damage
# that reached HP before the clamp (for Overkill's excess).
static func after_hit(victim: UnitBase, attacker, hp_dmg: int, raw: int, pre_hp: int,
		is_crit: bool, true_damage: bool) -> void:
	var att: UnitBase = attacker if attacker is UnitBase and is_instance_valid(attacker) else null
	var basic := att != null and att.gear_basic_hit
	var direct := not true_damage or basic
	var killed := victim.current_hp <= 0
	if att == null and not has(victim):
		return
	# Victim side.
	if has(victim) and direct and hp_dmg > 0:
		var g := victim.gear
		if not killed and lv(victim, "last_bastion") > 0.0 and not bool(g.get("bastion_used", false)) \
				and pre_hp * 2 > victim.max_hp and victim.current_hp * 2 <= victim.max_hp:   # #1
			g["bastion_used"] = true
			_add_shield(victim, "bastion", victim.max_hp * _v(victim, "last_bastion", "shield"))
			GearFX.bubble(victim, GearFX.VIOLET, 54.0)
			GearFX.pop(victim, "Last Bastion", GearFX.VIOLET, true)
		if lv(victim, "recovery") > 0.0:                                             # #35
			g["recovery_t"] = 3.0
			if GearFX.can(victim, "recovery", 0.5):
				GearFX.swirl(victim, GearFX.HEAL)
		if lv(victim, "thorns") > 0.0 and att and att != victim and att.current_hp > 0:  # #34
			var reflect := int(round(hp_dmg * _v(victim, "thorns", "pct")))
			if reflect > 0:
				att.take_damage(reflect, UnitBase.Element.NORMAL, null, true)
				if GearFX.can(victim, "thorns"):
					GearFX.burst(victim, GearFX.STEEL, 10)
		if basic and att:
			if lv(victim, "counterstrike") > 0.0:                                    # #32
				g["counter_t"] = 4.0
				if GearFX.can(victim, "counter", 0.5):
					GearFX.spark(victim, GearFX.GOLD)
			if lv(victim, "riposte") > 0.0 and att.current_hp > 0:                  # #29
				var slow := _v(victim, "riposte", "slow")
				var ag := att.gear
				if _t(ag, "riposte_t") <= 0.0 or float(ag.get("riposte_slow", 0.0)) < slow:
					ag["riposte_slow"] = slow
				ag["riposte_t"] = 3.0
				if GearFX.can(att, "riposte", 0.5):
					GearFX.swirl(att, Color(0.6, 0.6, 0.65))
	if att == null or not has(att):
		return
	var ag := att.gear
	var original := not bool(ag.get("echo", false)) and not bool(ag.get("proc", false))
	# Attacker side: landed basic attack.
	if basic:
		if hp_dmg > 0 and lv(att, "lifesteal") > 0.0 and att.current_hp < att.max_hp:  # #2
			att.heal(int(round(hp_dmg * _v(att, "lifesteal", "pct"))))
			if GearFX.can(att, "lifesteal"):
				GearFX.wisp(victim, att, GearFX.BLOOD)
		if lv(att, "iron_rhythm") > 0.0:                                             # #5
			ag["rhythm_t"] = 0.0
			ag["rhythm_hits"] = int(ag.get("rhythm_hits", 0)) + 1
			if int(ag["rhythm_hits"]) >= 3:
				ag["rhythm_hits"] = 0
				if _add_shield(att, "rhythm", att.max_hp * _v(att, "iron_rhythm", "shield"), RHYTHM_CAP):
					GearFX.bubble(att, GearFX.VIOLET, 40.0)
		if lv(att, "cadence") > 0.0 and not att.is_moving:                           # #12
			ag["cadence_t"] = 0.0
			ag["cadence"] = mini(5, int(ag.get("cadence", 0)) + 1)
			if int(ag["cadence"]) == 5 and GearFX.can(att, "cadence", 1.0):
				GearFX.speed(att)
		if lv(att, "sustained_assault") > 0.0:                                        # #30
			ag["sustain_t"] = 2.0
			if GearFX.can(att, "sustain", 0.8):
				GearFX.motes(att, GearFX.HEAL, 2)
				GearFX.motes(att, GearFX.MANA, 2)
		if lv(att, "critical_focus") > 0.0:                                           # #31
			if is_crit:
				if int(ag.get("focus", 0)) > 0:
					GearFX.burst(att, GearFX.GOLD, 5)
				ag["focus"] = 0
			else:
				ag["focus"] = mini(5, int(ag.get("focus", 0)) + 1)
		if is_crit:
			if lv(att, "deep_wound") > 0.0 and not killed:                            # #13
				var vg := victim.gear
				var cut := _v(att, "deep_wound", "cut")
				if _t(vg, "wound_t") <= 0.0 or float(vg.get("wound_cut", 0.0)) < cut:
					vg["wound_cut"] = cut
				vg["wound_t"] = 4.0
				GearFX.mark(victim, "✚", GearFX.BLOOD)
			if lv(att, "vital_precision") > 0.0 and _t(ag, "vital_t") <= 0.0:         # #33
				ag["vital_t"] = 1.0
				att.heal(int(round(att.max_hp * _v(att, "vital_precision", "hp_pct"))))
				att.restore_mana(int(round(_v(att, "vital_precision", "mana"))))
			if lv(att, "precision_reset") > 0.0 and att.skill_cd_time > 0.0:          # #24
				att.skill_cd_time = maxf(0.0, att.skill_cd_time - _v(att, "precision_reset", "sec"))
				if GearFX.can(att, "preset", 0.4):
					GearFX.mark(att, "⟲", Color(0.3, 0.85, 0.8))
			if lv(att, "keen_rhythm") > 0.0:                                          # #28
				ag["keen"] = 3.0
				ag["keen_pct"] = _v(att, "keen_rhythm", "pct")
		if lv(att, "sunder") > 0.0 and not killed:                                     # #14
			var vg2 := victim.gear
			vg2["sunder"] = mini(5, int(vg2.get("sunder", 0)) + 1)
			vg2["sunder_pct"] = maxf(float(vg2.get("sunder_pct", 0.0)), _v(att, "sunder", "shred_stack"))
			_refresh_bar(victim)
	# Attacker side: original skill damage.
	elif direct and original and _t(ag, "window") > 0.0 and not killed:
		if lv(att, "arcane_conduit") > 0.0:                                            # #10
			var hit: Dictionary = ag.get("conduit", {})
			var vid := victim.get_instance_id()
			if int(hit.get(vid, -1)) != int(ag.get("cast_id", 0)):
				hit[vid] = int(ag.get("cast_id", 0))
				ag["conduit"] = hit
				var extra := int(round(att.attack_damage * _v(att, "arcane_conduit", "atk_pct")))
				if extra > 0:
					ag["proc"] = true
					victim.take_damage(extra, UnitBase.Element.NORMAL, att, false, 0, true)
					ag["proc"] = false
					GearFX.spark(victim, GearFX.VIOLET)
	if killed:
		_on_kill(att, victim, basic, original and (basic or _t(ag, "window") > 0.0), raw - pre_hp)

static func _on_kill(att: UnitBase, victim: UnitBase, basic: bool, counts: bool, excess: int) -> void:
	var ag := att.gear
	if lv(att, "battle_haste") > 0.0:                                                 # #27
		var summon := bool(victim.get("is_summoned"))
		if not summon or int(ag.get("summon_kills", 0)) < SUMMON_KILL_CAP:
			if summon:
				ag["summon_kills"] = int(ag.get("summon_kills", 0)) + 1
			_bump_counter(att, "haste_kills", 1)
			GearFX.pop(att, "+1", Color(1.0, 0.78, 0.2))
	if counts and lv(att, "blood_price") > 0.0:                                       # #15
		att.heal(int(round(att.max_hp * _v(att, "blood_price", "hp_pct"))))
		att.restore_mana(int(round(_v(att, "blood_price", "mana"))))
		GearFX.wisp(victim, att, GearFX.BLOOD)
	if not basic:
		return
	if lv(att, "hunters_reset") > 0.0 and att.skill_cd_time > 0.0:                    # #11
		att.skill_cd_time = maxf(0.0, att.skill_cd_time - _v(att, "hunters_reset", "sec"))
		GearFX.mark(att, "⟲", Color(0.3, 0.85, 0.8))
	if lv(att, "overkill") > 0.0 and excess > 0:                                       # #9
		var spill := int(round(excess * _v(att, "overkill", "pct")))
		var next := _nearest_other(att, victim)
		if spill > 0 and next:
			# attacker null: true, noncrit, and cannot chain Overkill or on-hits.
			next.take_damage(spill, UnitBase.Element.NORMAL, null, true)
			att.damage_dealt += spill
			GearFX.streak(victim, next, GearFX.WHITE)

static func _nearest_other(att: UnitBase, victim: UnitBase) -> UnitBase:
	var mgr = att.battle_manager
	if mgr == null:
		return null
	var foes: Array = mgr.enemy_units if att.is_player_unit else mgr.player_units
	var best: UnitBase = null
	var best_d := INF
	for o in foes:
		if o == victim or not (o and is_instance_valid(o)) or o.current_hp <= 0:
			continue
		var cheb: int = maxi(absi(o.grid_position.x - att.grid_position.x),
			absi(o.grid_position.y - att.grid_position.y))
		if cheb > att.attack_range:
			continue
		var d: float = victim.global_position.distance_squared_to(o.global_position)
		if d < best_d:
			best_d = d
			best = o
	return best

# The wearer died (not a Phoenix Pact save): #27 loses half its kills.
static func on_death(u: UnitBase) -> void:
	if not has(u) or lv(u, "battle_haste") <= 0.0:
		return
	if u.relic_revive_pct > 0.0 and not u.relic_revive_used:
		return
	for item in u.gear_items:
		if item.passive_levels.has("battle_haste"):
			item.counters["haste_kills"] = int(item.counters.get("haste_kills", 0)) / 2
	GearFX.pop(u, "½", Color(1.0, 0.78, 0.2), true)
