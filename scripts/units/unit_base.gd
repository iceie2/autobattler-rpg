extends Node2D
class_name UnitBase

# Element types
enum Element {
	NORMAL,
	FIRE,
	WATER,
	EARTH,
	AIR,
	LIGHTNING
}

# Class types
enum UnitClass {
	WARRIOR,
	RANGER,
	MONK,
	THIEF,
	BLACK_MAGE,
	WHITE_MAGE,
	RED_MAGE,
	BLOODHOUND,
	BOUNCER,
	HEADHUNTER,
	SHAUNA,
	NEMI,
	# ── New heroes ──
	SHEILDOR,
	LORDEE,
	NECRO,
	# ── Roster expansion (2026 design pass) ──
	DOC,
	RIOT,
	PASTOR,
	SABLE,
	RUSH,
	STITCH,
	COAL,
	JUNE,
	CROSS,
	SEAR,
	EMBER,
	RIFT,
	ZOLT,
	LUMEN,
	STATIC,
	REED,
	VAIL,
	SPORE,
	# ── Summons (not recruitable) ──
	ZOMBIE,
	BAT,
	ANT,
	# ── Elites (enemy-only, not recruitable) ──
	STAT_STEALER,
	ANT_HILL,
	# ── Bosses (enemy-only, not recruitable) ──
	HYDRA
}

# Trait classes for synergies (Tank, Mage, Fighter, Ranged, Healer, Summoner)
enum TraitClass {
	TANK,
	MAGE,
	FIGHTER,
	RANGED,
	HEALER,
	SUMMONER
}

# Unit identity
@export var unit_name: String = "Unit"
@export var unit_class: UnitClass = UnitClass.WARRIOR
@export var trait_class: TraitClass = TraitClass.FIGHTER
@export var current_element: Element = Element.NORMAL
@export var level: int = 1

# Core stats
@export var max_hp: int = 100
@export var current_hp: int = 100
@export var max_mana: int = 50
@export var current_mana: int = 50

# Combat stats — each fully independent (TFT-style), set by class base + one-time
# recruit roll + flat level-up perk picks. Nothing here is derived from anything else.
@export var attack_damage: int = 15
@export var magic_power: int = 10
@export var resistance: int = 10     # flat armor — mitigates all incoming damage
@export var attack_speed: float = 0.7   # base attacks per second (before speed_modifier())
@export var hp_regen: float = 0.5    # HP restored per second
@export var mana_regen: float = 1.0  # mana restored per second
# Crit is a real combat stat (not the Headhunter/Shauna hit-counter tricks below,
# which are separate flavor mechanics) but baseline is 0% chance for everyone —
# nothing grants crit_chance yet (future gear/relics will). crit_damage still
# carries a real default so the multiplier is correct the moment something does.
@export var crit_chance: float = Balance.CRIT_CHANCE_BASE   # 0.0–1.0 chance to crit on a basic attack
@export var crit_damage: float = Balance.CRIT_DAMAGE_BASE   # damage multiplier on a crit (2.0 = double)

# Movement and Combat
@export var movement_speed: int = 3
@export var attack_range: int = 1

# Movement interpolation
var is_moving: bool = false
var move_start_pos: Vector2 = Vector2.ZERO
var move_target_pos: Vector2 = Vector2.ZERO
var move_progress: float = 0.0
var target_grid_pos: Vector2i = Vector2i.ZERO

# Elemental Affinity - per element dictionaries
var offensive_affinity: Dictionary = {
	Element.NORMAL: 0.0,
	Element.FIRE: 0.0,
	Element.WATER: 0.0,
	Element.EARTH: 0.0,
	Element.AIR: 0.0,
	Element.LIGHTNING: 0.0
}

var defensive_affinity: Dictionary = {
	Element.NORMAL: 0.0,
	Element.FIRE: 0.0,
	Element.WATER: 0.0,
	Element.EARTH: 0.0,
	Element.AIR: 0.0,
	Element.LIGHTNING: 0.0
}

# Equipment slots
var equipped_weapon = null
var equipped_armor = null
var equipped_accessory = null

# Items an enemy spawned wielding (stat bonuses already baked directly into this
# unit's stats at spawn time — see main_game.gd's _roll_held_item). Dropped as-is
# on death so what you see mid-fight is exactly what you loot. Player heroes use
# EquipmentInventory as the source of truth instead of this array.
var held_items: Array = []

# XP / levelling
var current_xp: float = 0.0
var xp_to_level: float = 100.0
var perk_points: int = 0   # queued bonus stat choices shown in level-up screen between rounds

# Economy (set on enemy units; ignored for player units)
var gold_reward: int = 0
var crystal_reward: int = 0
var xp_reward: int = 0
var equipment_passives: Dictionary = {}  # {"PassiveName": effect_value} — built by EquipmentInventory

# Multi-cell size (1 = normal 1×1, 2 = 2×2 boss)
var cell_size: int = 1

# Gacha rolls applied at recruit time
var recruit_rolls: Dictionary = {}   # {stat_key: {flat, growth}}
var recruit_grade: String     = ""   # "S" "A" "B" "C" "D"

# ── Per-level stat growth (additive, not %) ───────────────────────────────────
# Every level, each stat gains growth_base[stat] + growth_bonus[stat]:
#   growth_base  — fixed per class (see UnitFactory.CLASS_GROWTH_PER_LEVEL), same
#                  for every unit of that class, set once in UnitFactory.create_unit.
#   growth_bonus — personalized, rolled once at recruit time (see
#                  UnitFactory.apply_recruit_rolls). Enemies/summons never roll
#                  one, so it's just an empty dict (0 bonus) for them.
# Example: base attack 18, growth_base 3, growth_bonus 4 → level up: 18 → 25.
var growth_base: Dictionary  = {}    # {stat_key: flat amount per level}
var growth_bonus: Dictionary = {}    # {stat_key: flat amount per level}

func stat_growth(stat_key: String) -> float:
	return growth_base.get(stat_key, 0.0) + growth_bonus.get(stat_key, 0.0)

# ── Shield system ─────────────────────────────────────────────────────────────
var current_shield: int = 0   # absorbs damage before HP; resets at round end

# ── Summon system (Necro) ─────────────────────────────────────────────────────
var is_summoned: bool     = false   # true for Zombie / Bat summons AND Doc's revived hero
var summon_owner: UnitBase = null   # Necro reference (for passive heal)
# Doc's Field Surgery revives a real fallen hero, not a conjured summon — it's
# still flagged is_summoned (needed so _on_ally_died's "don't let a summon get
# re-snapshotted as revivable" guard applies to it too), but if it SURVIVES the
# round it should graduate into a normal permanent roster member instead of
# being deleted by main_game._despawn_summons() like a real summon would be.
# See _despawn_summons()'s survivor check.
var is_doc_revival: bool = false

# ── Lordee mechanics ──────────────────────────────────────────────────────────
var lordee_aura_timer:      float   = 0.0
var lordee_chase_target:    UnitBase = null
var lordee_chase_timer:     float   = 0.0   # >0 = hunting stolen target

# ── Skill system (passive / active / ultimate) ────────────────────────────────
# Passive (always-on, evaluated each turn in AutoBattleManager)
var passive_name: String = ""

# Active (replaces old skill_ fields for new classes; old fields kept for legacy)
var skill_name: String = ""
var skill_damage_multiplier: float = 1.5
var skill_range: int = 2
var skill_cooldown_max: int = 4   # seconds between casts (see skill_cd_time)
var skill_mana_cost: int = 0      # 0 = free (legacy classes); >0 = costs mana
var skill_description: String = ""

# Ultimate (charged by dealing and taking damage)
var ultimate_name: String = ""
var ultimate_damage_mult: float = 2.0
var ultimate_range: int = 3
var ultimate_charge: int = 0
var ultimate_charge_max: int = 300
var ultimate_ready: bool = false

# ── Combat state (per-unit tracking) ─────────────────────────────────────────
var damage_dealt: int = 0          # cumulative for damage meter
var pending_attack_log_damage: int = 0   # reset each attack; damage of this swing
var hit_counter: int = 0           # Headhunter: every-7th-crit / Shauna: every-3rd-true-dmg
var next_attack_boosted: bool = false  # Shauna active: next hit +50% DMG
var frenzy_active: bool = false    # Bloodhound passive
var most_damage_dealer = null      # ref to unit that dealt most dmg to self
var damage_taken_from: Dictionary = {}   # unit → total damage dealt to self

# ── Real-time combat timers (seconds) ────────────────────────────────────────
# The battle runs in real time: each unit acts on its own clocks rather than in a
# shared turn queue. These count DOWN by (delta * time_scale) each frame.
var attack_cooldown: float = 0.0   # time until this unit's next basic attack
var skill_cd_time: float = 0.0     # time until the active skill can fire again
var stun_time: float = 0.0         # >0 = stunned, no actions
var rapid_fire_time: float = 0.0   # Headhunter active: +range & double-shot while >0
var overdrive_time: float = 0.0    # Shauna ultimate: extra attack per swing while >0
var hp_regen_accum: float = 0.0    # fractional HP regen carried between frames
var mp_regen_accum: float = 0.0    # fractional MP regen carried between frames

# ── Status effects (roster expansion) ─────────────────────────────────────────
# All counted down in AutoBattleManager._tick_statuses(). Generic so every hero's
# CC/DoT/buff shares one pipeline instead of bespoke fields per kit.
var burn_time: float = 0.0         # >0 = burning; deals burn_dps per second
var burn_dps: float = 0.0
var burn_accum: float = 0.0        # fractional burn carried between frames
var burn_source = null             # who lit the burn (for damage credit)

var bleed_time: float = 0.0        # >0 = bleeding; deals bleed_dps per second,
var bleed_dps: float = 0.0         # doubled (BLEED_MOVE_MULT in auto_battle_manager)
var bleed_accum: float = 0.0       # for any tick where the unit is_moving — Bear's
var bleed_source = null            # Rending Swipe (2026-07-06): reopens the wound.

var slow_time: float = 0.0         # >0 = slowed; slow_pct cuts attack & move speed
var slow_pct: float = 0.0

var root_time: float = 0.0         # >0 = can attack but cannot move
var taunt_time: float = 0.0        # >0 = forced to target taunt_source
var taunt_source = null
var untargetable_time: float = 0.0 # >0 = cannot be selected as a target

var outgoing_dmg_mult: float = 1.0 # multiplies damage this unit deals (Pastor buff/Damnation)
var outgoing_dmg_time: float = 0.0 # 0 with mult!=1 = lasts rest of round; >0 = timed

var bonus_aspd_pct: float = 0.0    # Vail Tailwind / Pastor sermon — attack & move haste
var bonus_aspd_time: float = 0.0

var weakened_pct: float = 0.0      # Coal post-Meltdown self-debuff
var weakened_time: float = 0.0

var spore_stacks: float = 0.0      # Spore passive accumulation
var spore_tick_accum: float = 0.0

var shock_cd: float = 0.0          # Static: debounce so adjacency shock can't every-frame

var momentum_stacks: int = 0       # Sable: each shot empowers the next

var link_partner = null            # Stitch Link: shares damage with this unit
var puppet_time: float = 0.0       # Stitch Puppet: temporarily fights its own team

var stoke_charges: int = 0         # Coal Stoke: next N hits apply double burn
var meltdown_time: float = 0.0     # Coal Meltdown: punches explode

var combat_healing_done: int = 0   # Cross Judgment: tracks total healing this battle
var revive_used: bool = false      # Doc Field Surgery: once per battle

# ── Relic modifiers (set by RelicInventory when relics are applied; read by the
# combat code below and by AutoBattleManager). Defaults are all neutral so a unit
# with no relics behaves exactly as before. Persist across the run except the
# per-battle flags, which AutoBattleManager._init_unit_timers resets. ──
var relic_lifesteal: float = 0.0         # heal this fraction of damage dealt
var relic_outgoing_mult: float = 1.0     # multiply all outgoing damage
var relic_dmg_taken_mult: float = 1.0    # multiply all incoming damage
var relic_vs_boss_mult: float = 1.0      # extra outgoing multiplier vs bosses
var relic_ult_charge_mult: float = 1.0   # multiply ultimate charge gained
var relic_double_atk_chance: float = 0.0 # chance (0–1) to strike twice per attack
var relic_start_shield_pct: float = 0.0  # battle-start shield = frac of max HP
var relic_regen_pct: float = 0.0         # regen frac of max HP per second
var relic_free_first_ult: bool = false   # start each battle with ult charged
var relic_revive_pct: float = 0.0        # cheat death once/battle, revive at this frac
var relic_revive_used: bool = false      # per-battle guard for relic_revive_pct
var relic_on_kill_atk: float = 0.0       # each kill permanently grants +frac attack dmg

# True on boss enemies (Orc Brute / The Triarch / future bosses) — read by the
# Executioner relic's vs-boss damage bonus.
var is_boss: bool = false
# True on elite enemies (Hill Giant, Stat Stealer, …) — a lesser tier than a
# full boss; spawns periodically in rounds 5/15/25 (see WaveScaler). Does NOT
# grant the Executioner relic's vs-boss bonus — that's boss-only.
var is_elite: bool = false

# ── Stat-drain DOT (Stat Stealer's ultimate) ──────────────────────────────────
# While drain_time > 0, _tick_statuses (AutoBattleManager) drains drain_per_sec
# from `drain_stat` every second, transferring it live onto drain_source's
# matching stat. The theft is NOT reverted when the timer runs out — per design
# it stays stolen for the rest of the fight unless drain_source dies, at which
# point AutoBattleManager.restore_stat_theft() returns exactly drain_stolen.
var drain_time: float = 0.0
var drain_stat: String = ""        # which stat key is being stolen (e.g. "attack_damage")
var drain_per_sec: float = 0.0     # absolute amount drained per second (10% of the cast-time snapshot)
var drain_stolen: float = 0.0      # running total taken from this unit so far (for restoration)
var drain_source = null            # the Stat Stealer who cast this drain
var drain_accum: float = 0.0       # fractional carry-over for int-typed stats (mirrors burn_accum)

# ── Ant Hill elite ─────────────────────────────────────────────────────────────
# Each Ant bite stacks +1 permanent vulnerability on its victim (no decay this
# battle) — the Nth bite from any Ant deals +[stacks BEFORE that hit] bonus
# damage, so ignoring the swarm makes every subsequent bite hurt more. Reset at
# battle start.
var ant_bite_stacks: int = 0
# Ant Hill's periodic-spawn clock (generic name so any future "summons over
# time" unit could reuse it). Counts down in _tick_passive; reset at battle start.
var summon_spawn_timer: float = 0.0

# Battle state
var grid_position: Vector2i = Vector2i.ZERO
var home_position: Vector2i = Vector2i.ZERO   # row at battle start — drives heal/XP bonuses
var kill_count:    int       = 0              # kills this battle (display / stat tracking)
var kill_xp:       int       = 0              # XP earned from kills this battle (summed from enemy xp_reward)
var target_unit = null
var is_player_unit: bool = true
var battle_manager = null
var damage_text_container: Node2D = null
var skill_effect_container: Node2D = null

# Effective attacks per second — attack_speed with slow/haste modifiers applied.
# The battle manager resets attack_cooldown to 1.0 / attacks_per_second after each swing.
var attacks_per_second: float:
	get:
		return clampf(attack_speed * speed_modifier(), 0.1, 6.0)

# Combined slow / haste / weakness multiplier shared by attack speed and movement.
func speed_modifier() -> float:
	var m: float = 1.0
	if slow_time > 0.0:
		m *= (1.0 - clampf(slow_pct, 0.0, 0.9))
	if bonus_aspd_time > 0.0:
		m *= (1.0 + bonus_aspd_pct)
	return m

# Multiplier applied to damage this unit deals (buffs, debuffs, Sable momentum).
func outgoing_damage_multiplier() -> float:
	var m: float = outgoing_dmg_mult
	if weakened_time > 0.0:
		m *= (1.0 - clampf(weakened_pct, 0.0, 0.9))
	if unit_class == UnitClass.SABLE:
		# Balance 2026-07-03: 0.06 → 0.05/stack (12-stack cap: max +72% → +60%).
		# Sable topped the arena solo-damage board; user playtests flag her strong.
		m *= (1.0 + momentum_stacks * 0.05)
	return m

func get_defense_multiplier(attacking_element: Element = Element.NORMAL) -> float:
	# damage_taken = base_damage * (1.0 - (defense_value / (defense_value + 100)))
	var def_value = defensive_affinity.get(attacking_element, 0.0)
	return 1.0 - (def_value / (def_value + 100.0))

func get_attack_multiplier(target_element: Element = Element.NORMAL) -> float:
	# Returns multiplier based on offensive affinity against target element
	var off_value = offensive_affinity.get(target_element, 0.0)
	return 1.0 + (off_value / 100.0)

# Signals
signal health_changed(current: int, maximum: int)
signal died()
signal element_changed(new_element: Element)
signal leveled_up(new_level: int)
signal attacked(target)
signal mana_changed(current: int, maximum: int)
signal took_damage(amount: int, attacker)   # fires only on damage (not heals) → hit reaction
signal shield_changed(current: int)        # shield value changed (absorbed damage or granted)

func _ready():
	update_visuals()

func take_damage(amount: int, element: Element = Element.NORMAL, attacker = null, true_damage: bool = false, bonus_true_damage: int = 0) -> void:
	# Evasion: chance to dodge the hit entirely (only applies to direct hits, not DoT/true damage)
	if not true_damage and amount > 0:
		var ev: float = equipment_passives.get("Evasion", 0.0)
		if ev > 0.0 and randf() < ev:
			return

	var modified_damage := calculate_damage_with_element(amount, element)
	if not true_damage:
		# League-style diminishing-returns curve (2026-07-10, replaces flat
		# subtraction): 100 resistance = 50% reduction, 200 = 66.7%, asymptotic —
		# never reaches 100%. Flat subtraction let any resistance value fully
		# negate small/incremental hits (DoTs, stacking bite mechanics) once it
		# exceeded their damage, flooring them at 1 dmg forever regardless of how
		# much they scaled — see the Ant Hill bite-stack bug fixed just above.
		modified_damage = int(modified_damage * (100.0 / (100.0 + float(resistance))))
		modified_damage = int(modified_damage * get_defense_multiplier(element))
	# Relic: fragile-but-deadly picks (e.g. Glass Cannon) raise incoming damage.
	if relic_dmg_taken_mult != 1.0:
		modified_damage = int(round(modified_damage * relic_dmg_taken_mult))
	modified_damage = max(1, modified_damage)
	# Ant Hill swarm bite stacks: added AFTER the flat resistance subtraction and
	# max(1,...) floor above, as true damage. Bite stacks are a snowballing DPS
	# check (each bite makes every future ant bite hit harder) — computed as a
	# pre-mitigation bonus, they got fully eaten by resistance's flat subtraction
	# and every ant hit floored to 1 dmg forever, no matter how many stacks piled
	# up (2026-07-10 bug report: fights stalling out with neither side progressing).
	modified_damage += bonus_true_damage

	# Shield absorbs damage before HP
	if current_shield > 0:
		var absorbed: int = mini(current_shield, modified_damage)
		current_shield -= absorbed
		modified_damage -= absorbed
		shield_changed.emit(current_shield)
		if modified_damage <= 0:
			spawn_damage_text(absorbed, element)
			return   # fully blocked — no HP lost, no signals

	spawn_damage_text(modified_damage, element)

	current_hp = max(0, current_hp - modified_damage)
	health_changed.emit(current_hp, max_hp)
	took_damage.emit(modified_damage, attacker)   # drives the hit reaction (flash + recoil)
	_charge_ultimate(modified_damage)
	# Track who dealt damage to us (for Bloodhound ultimate)
	if attacker != null:
		var prev: int = damage_taken_from.get(attacker, 0)
		damage_taken_from[attacker] = prev + modified_damage

	# Stitch mechanics: Link (share with bound partner) + Loose Threads (team bleed).
	if battle_manager and modified_damage > 0 and battle_manager.has_method("propagate_damage_links"):
		battle_manager.propagate_damage_links(self, modified_damage, attacker)

	if current_hp <= 0:
		die()

func calculate_damage_with_element(base_damage: int, attacker_element: Element) -> int:
	# Elemental damage modifiers (simplified)
	var modifier = 1.0
	
	# Example: Fire beats Earth, Water beats Fire, etc.
	if attacker_element == Element.FIRE and current_element == Element.EARTH:
		modifier = 1.5
	elif attacker_element == Element.WATER and current_element == Element.FIRE:
		modifier = 1.5
	elif attacker_element == Element.EARTH and current_element == Element.LIGHTNING:
		modifier = 1.5
	elif attacker_element == Element.LIGHTNING and current_element == Element.WATER:
		modifier = 1.5
	
	return int(base_damage * modifier)

func heal(amount: int) -> void:
	var before: int = current_hp
	current_hp = min(max_hp, current_hp + amount)
	health_changed.emit(current_hp, max_hp)
	var healed: int = current_hp - before
	if healed > 0:
		spawn_heal_text(healed)

func restore_mana(amount: int) -> void:
	current_mana = min(max_mana, current_mana + amount)
	mana_changed.emit(current_mana, max_mana)

func spend_mana(amount: int) -> bool:
	if current_mana >= amount:
		current_mana -= amount
		mana_changed.emit(current_mana, max_mana)
		return true
	return false

func change_element(new_element: Element) -> void:
	current_element = new_element
	element_changed.emit(new_element)
	update_visuals()

# Applies one tick of this unit's personalized per-level growth to every stat.
# Shared by level_up() (level 2+, in combat) AND the recruit flow (level 1
# already "counts" as having received its level's growth the moment you buy the
# hero — see UnitFactory.apply_recruit_rolls). Two recruits of the same class
# will diverge over time since their growth rolls differ.
func apply_stat_growth() -> void:
	max_hp         = maxi(1, max_hp         + int(stat_growth("hp")))
	max_mana       = maxi(0, max_mana       + int(stat_growth("mana")))
	attack_damage  = maxi(1, attack_damage  + int(stat_growth("atk")))
	magic_power    = maxi(0, magic_power    + int(stat_growth("magic")))
	resistance     = maxi(0, resistance     + int(stat_growth("res")))
	attack_speed   = maxf(0.05, attack_speed + stat_growth("aspd"))
	hp_regen       = maxf(0.0,  hp_regen     + stat_growth("hpregen"))
	mana_regen     = maxf(0.0,  mana_regen   + stat_growth("manaregen"))

func level_up() -> void:
	level += 1
	apply_stat_growth()
	current_hp = max_hp
	current_mana = max_mana
	leveled_up.emit(level)


func equip_weapon(weapon) -> void:
	equipped_weapon = weapon

func equip_armor(armor) -> void:
	equipped_armor = armor

func equip_accessory(accessory) -> void:
	equipped_accessory = accessory

func attack(target) -> void:
	if not (target and target.has_method("take_damage")):
		return

	var target_element: Element = target.current_element if target is UnitBase else Element.NORMAL
	var damage := int(attack_damage * get_attack_multiplier(target_element))
	damage = int(damage * outgoing_damage_multiplier())
	# Relic outgoing multipliers (Glass Cannon, element relics, Executioner vs bosses).
	if relic_outgoing_mult != 1.0:
		damage = int(damage * relic_outgoing_mult)
	if relic_vs_boss_mult != 1.0 and target is UnitBase and target.is_boss:
		damage = int(damage * relic_vs_boss_mult)
	# Ant Hill swarm: every bite adds the victim's CURRENT stack count as bonus
	# damage (read before this hit's stack increment in _apply_on_hit_passives),
	# so the 1st bite is normal, the 2nd is +1, the 3rd is +2, etc. Passed to
	# take_damage() as unmitigated bonus_true_damage (2026-07-10 fix) — added to
	# `damage` here it was flat-resistance'd away and floored to 1 dmg forever,
	# since resistance is a flat subtraction, not a percentage.
	var ant_bonus_dmg: int = 0
	if unit_class == UnitClass.ANT and target is UnitBase:
		ant_bonus_dmg = target.ant_bite_stacks

	hit_counter += 1
	# Generic crit roll (separate from the Headhunter/Shauna hit-counter flavor
	# mechanics below — those are class-specific tricks, this is the real crit
	# stat that gear/relics/the Stat Stealer's drain read and write).
	if crit_chance > 0.0 and randf() < crit_chance:
		damage = int(damage * crit_damage)
	# Headhunter: every 7th hit = 3× crit
	if unit_class == UnitClass.HEADHUNTER and hit_counter % 7 == 0:
		damage = int(damage * 3.0)
	# Shauna: next attack boosted (+50%) from Kite active
	var is_boosted := next_attack_boosted
	if is_boosted:
		damage = int(damage * 1.5)
		next_attack_boosted = false
	# Shauna: every 3rd hit = true damage (bypass defence)
	var is_true_dmg := (unit_class == UnitClass.SHAUNA and hit_counter % 3 == 0)

	# Headhunter active bonus range already applied by battle manager

	# Bouncer is a melee brawler despite having range 2 (grab/pull reach) — no projectile.
	if attack_range > 1 and unit_class != UnitClass.BOUNCER:
		spawn_projectile(target, damage)
		pending_attack_log_damage += damage   # intended damage (mitigated on hit)
	else:
		var pre_hp: int = target.current_hp
		var was_alive: bool = pre_hp > 0
		target.take_damage(damage, current_element, self, is_true_dmg, ant_bonus_dmg)
		var actual: int = max(0, pre_hp - target.current_hp)
		damage_dealt += actual
		pending_attack_log_damage += actual
		_charge_ultimate(actual / 2)
		apply_relic_on_hit(target, actual, was_alive)

	attacked.emit(target)

# Lifesteal + Soul-Harvest on-kill, shared by melee (here) and ranged (projectile
# on-reach). `was_alive` guards the kill bonus so it only fires on the killing blow.
func apply_relic_on_hit(target, actual: int, was_alive: bool) -> void:
	if actual <= 0:
		return
	if relic_lifesteal > 0.0:
		heal(int(round(actual * relic_lifesteal)))
	if relic_on_kill_atk > 0.0 and was_alive and target is UnitBase and target.current_hp <= 0:
		attack_damage = maxi(1, int(round(attack_damage * (1.0 + relic_on_kill_atk))))

func _charge_ultimate(amount: int) -> void:
	if ultimate_charge_max <= 0 or ultimate_ready:
		return
	if relic_ult_charge_mult != 1.0:
		amount = int(round(amount * relic_ult_charge_mult))
	ultimate_charge = min(ultimate_charge + amount, ultimate_charge_max)
	if ultimate_charge >= ultimate_charge_max:
		ultimate_ready = true

func grant_xp(amount: float) -> void:
	current_xp += amount
	while current_xp >= xp_to_level:
		current_xp -= xp_to_level
		xp_to_level *= 1.5
		level_up()
		perk_points += 1

func set_level(target_level: int) -> void:
	while level < target_level:
		level_up()

func spawn_projectile(target, damage: int) -> void:
	if not battle_manager:
		return

	var projectile := Projectile.new()
	var start_pos: Vector2 = global_position
	var end_pos:   Vector2 = target.global_position if target else global_position

	projectile.setup(start_pos, end_pos, damage, current_element, target)
	projectile.caster = self   # so on_reach_target can credit damage_dealt

	if battle_manager.has_method("add_projectile"):
		battle_manager.add_projectile(projectile)

func die() -> void:
	# Khagan's mind-controlled puppet: a lethal hit clamps to 1 HP and STAYS
	# there (no partial-heal floor — 2026-07-08 user spec) instead of really
	# dying — the player fights their own hero down to exactly 1 HP to end the
	# encounter. The normal between-round row heal
	# (main_game._grant_between_round_bonuses) tops it up afterward same as any
	# other survivor, since home_position was never touched (mirrors the
	# VisualUnit.die() override).
	if has_meta("khagan_puppet") and current_hp <= 0:
		current_hp = 1
		current_shield = 0
		health_changed.emit(current_hp, max_hp)
		if battle_manager and battle_manager.has_method("end_khagan_possession"):
			battle_manager.end_khagan_possession(self)
		return
	# Phoenix Pact: cheat death once per battle, reviving at a fraction of max HP.
	# Guards on current_hp <= 0 so it only intercepts an actual death (all death
	# paths funnel through here, including DoT ticks).
	if relic_revive_pct > 0.0 and not relic_revive_used and current_hp <= 0:
		relic_revive_used = true
		current_hp = maxi(1, int(round(max_hp * relic_revive_pct)))
		current_shield = 0
		health_changed.emit(current_hp, max_hp)
		return
	# Stat Stealer: return any stats it's currently holding stolen (mirrors the
	# VisualUnit.die() override, which is what real game units actually use).
	if battle_manager and battle_manager.has_method("restore_stat_theft"):
		battle_manager.restore_stat_theft(self)
	died.emit()
	queue_free()

func update_visuals() -> void:
	# Override in derived classes to update sprite/shape based on element
	pass

func get_element_color() -> Color:
	match current_element:
		Element.FIRE:
			return Color(1.0, 0.2, 0.0)  # Bright red-orange
		Element.WATER:
			return Color(0.0, 0.7, 1.0)  # Cyan/ice blue
		Element.EARTH:
			return Color(0.55, 0.35, 0.2)  # Brown
		Element.AIR:
			return Color(0.8, 1.0, 1.0)  # Light cyan/white
		Element.LIGHTNING:
			return Color(1.0, 1.0, 0.0)  # Yellow
		Element.NORMAL:
			return Color(0.6, 0.6, 0.6)  # Grey
		_:
			return Color(0.6, 0.6, 0.6)  # Grey default

func get_class_name_string() -> String:
	match unit_class:
		UnitClass.WARRIOR:
			return "Warrior"
		UnitClass.RANGER:
			return "Ranger"
		UnitClass.MONK:
			return "Monk"
		UnitClass.THIEF:
			return "Thief"
		UnitClass.BLACK_MAGE:
			return "Black Mage"
		UnitClass.WHITE_MAGE:
			return "White Mage"
		UnitClass.RED_MAGE:
			return "Red Mage"
		UnitClass.BLOODHOUND:
			return "Bloodhound"
		UnitClass.BOUNCER:
			return "Bouncer"
		UnitClass.HEADHUNTER:
			return "Headhunter"
		UnitClass.SHAUNA:
			return "Shauna"
		UnitClass.NEMI:
			return "Nemi"
		UnitClass.SHEILDOR:
			return "Sheildor"
		UnitClass.LORDEE:
			return "Lordee"
		UnitClass.NECRO:
			return "Necro"
		UnitClass.DOC:
			return "Doc"
		UnitClass.RIOT:
			return "Riot"
		UnitClass.PASTOR:
			return "Pastor"
		UnitClass.SABLE:
			return "Sable"
		UnitClass.RUSH:
			return "Rush"
		UnitClass.STITCH:
			return "Stitch"
		UnitClass.COAL:
			return "Coal"
		UnitClass.JUNE:
			return "June"
		UnitClass.CROSS:
			return "Cross"
		UnitClass.SEAR:
			return "Sear"
		UnitClass.EMBER:
			return "Ember"
		UnitClass.RIFT:
			return "Rift"
		UnitClass.ZOLT:
			return "Zolt"
		UnitClass.LUMEN:
			return "Lumen"
		UnitClass.STATIC:
			return "Static"
		UnitClass.REED:
			return "Reed"
		UnitClass.VAIL:
			return "Vail"
		UnitClass.SPORE:
			return "Spore"
		UnitClass.ZOMBIE:
			return "Zombie"
		UnitClass.BAT:
			return "Bat"
		UnitClass.HYDRA:
			return "Hydra"
		_:
			return "Unknown"

func get_element_name_string() -> String:
	match current_element:
		Element.FIRE:
			return "Fire"
		Element.WATER:
			return "Water"
		Element.EARTH:
			return "Earth"
		Element.AIR:
			return "Air"
		Element.LIGHTNING:
			return "Lightning"
		Element.NORMAL:
			return "Normal"
		_:
			return "Unknown"

func is_in_attack_range(target_pos: Vector2i) -> bool:
	var distance = grid_position.distance_to(target_pos)
	return distance <= attack_range

func get_distance_to(target_pos: Vector2i) -> float:
	return grid_position.distance_to(target_pos)

func spawn_damage_text(damage: int, element: Element) -> void:
	if not damage_text_container:
		return

	var damage_text = DamageText.new()
	# Spawn slightly above the unit
	var spawn_pos = global_position + Vector2(0, -20)
	damage_text.setup(damage, element, spawn_pos)
	damage_text_container.add_child(damage_text)

# Green "+N" floating text — fires whenever heal() actually restores any HP,
# regardless of source (skills, lifesteal, auras, relics — anything routed
# through heal()), matching spawn_damage_text's shape above.
func spawn_heal_text(amount: int) -> void:
	if not damage_text_container:
		return

	var heal_text = DamageText.new()
	var spawn_pos = global_position + Vector2(0, -20)
	heal_text.setup_heal(amount, spawn_pos)
	damage_text_container.add_child(heal_text)
