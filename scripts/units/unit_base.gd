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

# Core stats — HP and mana emit their changed-signal from property setters, so
# EVERY write path (round-end heal, level-up growth, event effects, synergy
# apply/revert, progression bonuses) updates the overhead bar and any open UI.
# Before 2026-07-15 only take_damage()/heal() emitted manually, so direct
# assignments left the in-world bar stale until the next round's first hit.
@export var max_hp: int = 100:
	set(value):
		if value == max_hp:
			return
		max_hp = value
		health_changed.emit(current_hp, max_hp)
@export var current_hp: int = 100:
	set(value):
		if value == current_hp:
			return
		current_hp = value
		health_changed.emit(current_hp, max_hp)
@export var max_mana: int = 50:
	set(value):
		if value == max_mana:
			return
		max_mana = value
		mana_changed.emit(current_mana, max_mana)
@export var current_mana: int = 50:
	set(value):
		if value == current_mana:
			return
		current_mana = value
		mana_changed.emit(current_mana, max_mana)

# Combat stats — each fully independent (TFT-style), set by class base + one-time
# recruit roll + flat level-up perk picks. Nothing here is derived from anything else.
@export var attack_damage: int = 15
@export var magic_power: int = 10
# Defense split (2026-07-16 rework): `resistance` is now ARMOR (physical
# mitigation only); magic_resist mitigates magic-typed damage. Damage is
# typed by the stat it scales from — attack_damage sources are physical,
# magic_power sources go through take_magic_damage(). DoTs stay true damage.
# Both start equal everywhere (copied at the factory choke points) so the
# split itself is balance-neutral until an archetype tuning pass.
@export var resistance: int = 10     # flat ARMOR — mitigates physical damage
@export var magic_resist: int = 10   # flat MAGIC ARMOR — mitigates magic damage
# Flat TENACITY — the third defensive stat (2026-08-07). Shortens incoming
# crowd control (stun / root / taunt / slow) exactly the way armor blunts
# damage, on the same diminishing-returns family so a player who reads "armor"
# reads this for free: duration_mult = 100 / (100 + tenacity).
#   0 → 1.00x    20 → 0.83x    60 → 0.63x    150 → 0.40x    200 → 0.33x
# The curve is asymptotic to zero and NEVER reaches it: tenacity can never make
# a unit CC-immune, which is the explicit design constraint. Applied ONCE at the
# moment a status is applied (see AutoBattleManager.apply_stun/root/taunt/slow),
# never on the per-frame decay — decay-side scaling would make the remaining-
# duration UI lie and would double-dip when two sources refresh one status.
# Heroes are 0 by default; enemies get tier values in EnemyFactory.
@export var tenacity: int = 0
@export var attack_speed: float = 0.7   # base attacks per second (before speed_modifier())
@export var hp_regen: float = 0.5    # HP restored per second
@export var mana_regen: float = 1.0  # mana restored per second
# Crit is a real combat stat (not the Headhunter/Shauna hit-counter tricks below,
# which are separate flavor mechanics). Everyone — heroes AND enemies — crits at
# a 10% baseline (Balance.CRIT_CHANCE_BASE, 2026-07-24); gear/perks/relics/shop
# and the crystal-shop Lethality/Killing Blow nodes stack on top.
@export var crit_chance: float = Balance.CRIT_CHANCE_BASE   # 0.0–1.0 chance to crit on a basic attack
@export var crit_damage: float = Balance.CRIT_DAMAGE_BASE   # damage multiplier on a crit (2.0 = double)

# Movement and Combat
@export var movement_speed: int = 3
@export var attack_range: int = 1

# Movement interpolation
var is_moving: bool = false
# One-shot movement_speed override for the current step only (e.g. Shauna's
# Kite reposition, which reads as an instant dodge-step regardless of her
# actual speed stat). 0 = unused, falls back to movement_speed as normal.
var move_speed_override: int = 0
var move_start_pos: Vector2 = Vector2.ZERO
var move_target_pos: Vector2 = Vector2.ZERO
var move_progress: float = 0.0
var target_grid_pos: Vector2i = Vector2i.ZERO
# World-space direction of the current/last step (set in AutoBattleManager.start_unit_movement).
# VisualUnit._update_animation() reads this to pick walk_south/north/east/west.
var last_move_direction: Vector2 = Vector2.ZERO

# Elemental Affinity RATINGS (2026-07-16 rework): 100 = neutral.
# - Offensive rating R vs a target element multiplies damage by R/100.
# - Defensive rating D vs an incoming element: below 100 the shortfall is
#   ADDED to damage taken (75 → ×1.25); at or above 100 damage HALVES per
#   +100 (200 → ×0.5, 300 → ×0.25) — user-specified curve.
# Populated by set_affinity_profile(): every element gets the base rating,
# then the unit's OWN element gets +50 offense / +25 defense and every OTHER
# element's defense takes −15 (Balance.AFFINITY_* knobs).
var offensive_affinity: Dictionary = {
	Element.NORMAL: 100.0,
	Element.FIRE: 100.0,
	Element.WATER: 100.0,
	Element.EARTH: 100.0,
	Element.AIR: 100.0,
	Element.LIGHTNING: 100.0
}

var defensive_affinity: Dictionary = {
	Element.NORMAL: 100.0,
	Element.FIRE: 100.0,
	Element.WATER: 100.0,
	Element.EARTH: 100.0,
	Element.AIR: 100.0,
	Element.LIGHTNING: 100.0
}

# Class-base ratings, kept so the element deltas can be reapplied cleanly
# whenever the unit's element changes mid-run (see change_element()).
var base_off_affinity: float = 100.0
var base_def_affinity: float = 100.0

func set_affinity_profile(off_base: float, def_base: float) -> void:
	base_off_affinity = off_base
	base_def_affinity = def_base
	for e in Element.values():
		offensive_affinity[e] = off_base
		defensive_affinity[e] = def_base - Balance.AFFINITY_OFFELEM_DEF_PENALTY
	offensive_affinity[current_element] = off_base + Balance.AFFINITY_OWN_OFF_BONUS
	defensive_affinity[current_element] = def_base + Balance.AFFINITY_OWN_DEF_BONUS

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
# Component equipment (EQUIPMENT_GREEN_PAIRS.md). Only ever non-empty in a
# ComponentEquipmentGateway run; every GearPassives hook bails on empty levels.
var gear_levels: Dictionary = {}   # passive key -> summed level L (1..24)
var gear_items: Array = []         # equipped ComponentEquipmentItems (persistent counters)
var gear: Dictionary = {}          # per-fight passive state, reset by GearPassives.battle_start
var gear_shield: int = 0           # item shields (#1/#3/#5): violet, absorbed before current_shield
var gear_basic_hit: bool = false   # true only while this unit's basic attack resolves
var ability_haste: int = 0         # League-style haste: skill cooldown x 100/(100+haste)
# Shared channel system (VD-15): the ability this unit is channelling, if any.
# Owned by AutoBattleManager.start_channel / _tick_channel / cancel_channel.
var channel: Channel = null

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

# 2026-08-01: crystal-shop "Growth" upgrades (Might/Spellpower/Fleetfoot/
# Vitality Flow/Mana Flow Growth) add a small extra amount to EVERY hero's
# per-level growth for that stat — a global multiplier-ish bonus on top of
# growth_base/growth_bonus above, read live so a mid-run purchase applies to
# the next level-up. Player heroes only (enemies/summons have is_player_unit
# false and never see these).
const PROGRESSION_GROWTH_KEYS: Dictionary = {
	"atk": "attack_per_level",
	"magic": "spellpower_per_level",
	"aspd": "attack_speed_per_level",
	"hpregen": "hp_regen_per_level",
	"manaregen": "mana regen per level",
	"hp": "health_per_level",
	"mana": "mana_per_level",
	# crit/critdmg have no innate per-class growth (see
	# UnitFactory.CLASS_GROWTH_PER_LEVEL) — these upgrades are their only
	# source of per-level-up growth (2026-08-02).
	"crit": "crit_per_level",
	"critdmg": "crit_dmg_per_lvl",
	# Physical-armor-only growth bucket — deliberately separate from "res" so
	# it doesn't also buff magic_resist, which still rides "res" alone below.
	"armor": "armor_per_lvl",
}

# ── Tenacity ──────────────────────────────────────────────────────────────────
# Multiplier applied to the duration of any incoming crowd control. Same shape
# as the armor curve; asymptotic to zero so it can never fully block a status.
func status_duration_mult() -> float:
	return 100.0 / (100.0 + maxf(0.0, float(tenacity)))

# Convenience: the duration `dur` as this unit actually experiences it.
func tenacity_scaled(dur: float) -> float:
	return dur * status_duration_mult()

func stat_growth(stat_key: String) -> float:
	var total: float = growth_base.get(stat_key, 0.0) + growth_bonus.get(stat_key, 0.0)
	if is_player_unit and PROGRESSION_GROWTH_KEYS.has(stat_key):
		total += Progression.get_bonus_float(PROGRESSION_GROWTH_KEYS[stat_key])
	return total

# Fractional carry for int-typed stats (atk, magic) whose growth can now
# include sub-1 amounts (Growth upgrades above) — apply_stat_growth() below
# would otherwise truncate that fraction to 0 EVERY level via int(), silently
# discarding it forever instead of it accumulating into a real point over
# several level-ups (e.g. +0.1/level should become +1 extra attack every 10
# hero levels, not never).
var _int_growth_carry: Dictionary = {}   # {stat_key: float remainder}

func _grow_int_stat(current: int, stat_key: String, min_value: int) -> int:
	var carry: float = _int_growth_carry.get(stat_key, 0.0) + stat_growth(stat_key)
	var whole := int(floor(carry))
	_int_growth_carry[stat_key] = carry - float(whole)
	return maxi(min_value, current + whole)

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
# Seconds into the battle this unit first dealt damage or healed; -1 = never
# contributed. Written only by AutoBattleManager._sample_first_contribution and
# read only by the post-battle report — it drives the "your back row spent 6s
# out of range" diagnosis that a raw damage total can't express.
var first_contribution_time: float = -1.0
# >0 = MELEE attackers (attack_range <= 1) can't target this unit; ranged and
# magic still can. Distinct from untargetable_time, which hides a unit from
# everything. Drives the Skyrender's aloft windows — see
# AutoBattleManager.find_nearest_enemy and the "skyrender_ascent" mob passive.
var melee_untargetable_time: float = 0.0
# >0 = all healing this unit RECEIVES is scaled by Balance-side
# AutoBattleManager.DROWNED_HEAL_MULT. Refreshed every tick by the Drowned Maw's
# Riptide aura (wave-30 boss) and decayed in _tick_status, so it lifts on its
# own once the boss dies. Gates inside heal(), which every sustain route in the
# game funnels through — regen, lifesteal, drain-heals, skill and ult heals.
var heal_cut_time: float = 0.0
var pending_attack_log_damage: int = 0   # reset each attack; damage of this swing
var hit_counter: int = 0           # Headhunter: every-7th-crit / Shauna: every-3rd-true-dmg
var next_attack_boosted: bool = false  # Shauna active: next hit +50% DMG
var frenzy_active: bool = false    # Bloodhound passive
var most_damage_dealer = null      # ref to unit that dealt most dmg to self
var damage_taken_from: Dictionary = {}   # unit → total damage dealt to self
# Count of hits this unit has TAKEN, from any source. damage_taken_from only
# records hits that carry an attacker, so several real sources never appear in
# it — Static's Grid field, reflect damage, and any DoT whose source has since
# died all pass null. Anything asking "has this unit been hit recently?" must
# read this instead (see the Lizard's Cold Blood), or it silently ignores them.
var times_hit: int = 0

# ── Real-time combat timers (seconds) ────────────────────────────────────────
# The battle runs in real time: each unit acts on its own clocks rather than in a
# shared turn queue. These count DOWN by (delta * time_scale) each frame.
var attack_cooldown: float = 0.0   # time until this unit's next basic attack
var skill_cd_time: float = 0.0     # time until the active skill can fire again
var action_time: float = 0.0       # remaining time in the current attack/skill/ultimate animation
var stun_time: float = 0.0         # >0 = stunned, no actions
var rapid_fire_time: float = 0.0   # Headhunter active: +range & double-shot while >0
var overdrive_time: float = 0.0    # Shauna ultimate: extra attack per swing while >0
# Duration-based active ultimates (Rush afterimage, Shauna overdrive) set this
# to their effect length. While it's >0 the unit can't gain ult charge, so it
# can't re-ult mid-ult — Rush was ult-into-ult-into-ult chaining (2026-07-17).
var ult_active_time: float = 0.0
var hp_regen_accum: float = 0.0    # fractional HP regen carried between frames
var mp_regen_accum: float = 0.0    # fractional MP regen carried between frames
var regen_text_accum: int = 0      # passive-regen HP healed since the last floating-text flush
var regen_text_timer: float = 0.0  # time since the last floating-text flush

# ── Status effects (roster expansion) ─────────────────────────────────────────
# All counted down in AutoBattleManager._tick_statuses(). Generic so every hero's
# CC/DoT/buff shares one pipeline instead of bespoke fields per kit.
var burn_time: float = 0.0         # >0 = burning; deals burn_dps per second
var burn_dps: float = 0.0
var burn_accum: float = 0.0        # fractional burn carried between frames
var burn_source = null             # who lit the burn (for damage credit)
# What the burn LOOKS like. The burn timer is shared plumbing reused for several
# different fictions (the Rat's disease, the Sky Wyvern's venom, real fire), and
# every one of them used to render as the same orange puff. Purely presentational
# — it never touches damage, duration or stacking. "fire" keeps the original look,
# so anything that does not pass a flavour is unchanged.
var burn_flavor: String = "fire"
# Kindred Flames (VD-16) only: one burn per hero TYPE, summed by
# recompute_burn_total(). Empty under the classic rule (strongest burn wins).
var burn_parts: Dictionary = {}          # unit_class -> [dps, time_left, source]
var burn_stack_share: float = 0.0        # share in force on this unit; 0 = classic rule

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

var bonus_aspd_pct: float = 0.0    # Pastor sermon / Zolt enrage — attack & move haste
# What the haste LOOKS like. Third instance of the same pattern as burn_flavor /
# weaken_flavor: this timer is shared plumbing (Pastor's sermon, Vail's gust and
# the Troll's Enrage all ride it), so a visual keyed on the timer alone would
# paint troll sinew on a hero. "" = no dedicated visual (existing behaviour).
var aspd_flavor: String = ""
var bonus_aspd_time: float = 0.0

var bonus_regen_amt: float = 0.0   # Vail Updraft — flat HP/sec while active
var bonus_regen_time: float = 0.0

var weakened_pct: float = 0.0      # Coal post-Meltdown self-debuff
var weakened_time: float = 0.0
# What the weaken LOOKS like. Same reasoning as burn_flavor: this timer is shared
# plumbing — Coal's own post-Meltdown burnout AND the Slime's Corrosive Goo both
# live on it. Purely presentational, never touches the multiplier or duration.
# "" = no dedicated visual (Coal's existing behaviour, unchanged).
var weaken_flavor: String = ""

var spore_stacks: float = 0.0      # Spore passive accumulation
var spore_tick_accum: float = 0.0

var momentum_stacks: int = 0       # Sable: each shot empowers the next

var link_partner = null            # Legacy Stitch Link field; retained for compatibility
var link_group: Array = []         # Stitch Link network, snapshotted when cast
var link_share: float = 0.0        # MAG-scaled share for this network
var link_owner: UnitBase = null     # Stitch who receives Threadguard shielding
var puppet_time: float = 0.0       # Stitch Puppet: temporarily fights its own team

var stoke_charges: int = 0         # Coal Stoke: next N hits apply double burn
var meltdown_time: float = 0.0     # Coal Meltdown: punches explode

var combat_healing_done: int = 0   # lifetime healing-done stat this battle (arena/stat-sheet reporting)
# Cross Judgment resource (2026-07-24 split from combat_healing_done): banks
# Penance healing since the last Judgment cast, then Judgment spends it to
# zero. Kept separate so Judgment scales off RECENT healing, not the
# lifetime combat_healing_done total (which must stay untouched — it's the
# stat sheet's "healing done" number for every healer class, not just Cross).
var judgment_pool: int = 0
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
var relic_kill_atk_gain: float = 0.0     # attack earned from kills so far, fraction kept (VD-21)
var relic_execute_threshold: float = 0.0 # target hp% (0-1) below which execute_pct kicks in
var relic_execute_bonus: float = 0.0     # bonus outgoing dmg mult while target is below threshold
var relic_first_strike_crit: bool = false # first attack each fight is a guaranteed crit
var relic_first_strike_used: bool = false # per-battle guard for relic_first_strike_crit
var relic_first_strike_crit_mult: float = 2.0 # damage mult applied on that guaranteed first crit (own magnitude, independent of crit_damage)
var relic_row_front_mult: float = 1.0    # outgoing dmg mult while in the front row
var relic_row_back_mult: float = 1.0     # outgoing dmg mult while in the back row
var relic_opening_burst_pct: float = 0.0 # bonus outgoing dmg mult for the opening window
var relic_opening_burst_window: float = 0.0 # seconds the opening window lasts
var relic_opening_burst_remaining: float = 0.0 # per-battle countdown for the window above
var relic_ult_refund_kill: float = 0.0   # killing blow refunds this frac of max ult charge
var relic_gold_scaling_dmg: float = 0.0  # bonus outgoing dmg mult per gold currently held
var relic_momentum_pct_per_sec: float = 0.0 # attack speed ramp per second survived in a fight
var relic_momentum_time: float = 0.0     # per-battle seconds-survived accumulator
var relic_underdog_dmg_per_dead: float = 0.0 # bonus outgoing dmg mult per dead ally
var relic_underdog_res_per_dead: float = 0.0 # incoming dmg reduction per dead ally
# ── Burn archetype pieces (VD-16) - set by RelicInventory, read by combat ──
var relic_burn_per_burner: float = 0.0   # Kindling: +burn dps per Burn hero type fielded (max 3)
var relic_burn_stack_share: float = 0.0  # Kindred Flames: share each other hero's burn adds
var relic_burn_leap: float = 0.0         # Ashfall: share of a dying enemy's burn that jumps
var relic_burn_ult_haste: float = 0.0    # Tinder Heart: ult charge bonus while any foe burns
var relic_burn_flare_secs: float = 0.0   # Inferno Crown: seconds of burn dealt at once every 8 s
var burn_haste_active: bool = false      # set each frame by the battle manager for Tinder Heart

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
# The stat's value at the moment of the cast — lets _tick_statuses cap total
# theft at DRAIN_MAX_STEAL_PCT of this original value (2026-07-24 balance:
# unbounded drain_time*drain_per_sec could otherwise fully zero a stat).
var drain_snapshot: float = 0.0

# Ant Hill's periodic-spawn clock (generic name so any future "summons over
# time" unit could reuse it). Counts down in _tick_passive; reset at battle start.
var summon_spawn_timer: float = 0.0

# Battle state
var grid_position: Vector2i = Vector2i.ZERO
var home_position: Vector2i = Vector2i.ZERO   # row at battle start — drives heal/XP bonuses
var milestone_ult_casts: int = 0
var milestone_double_attacks: int = 0
var milestone_shield_absorbed: int = 0

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
	if unit_class == UnitClass.BLOODHOUND and frenzy_active:
		m *= (1.0 + AbilityFormulas.flat(UnitClass.BLOODHOUND,
				AbilityFormulas.PASSIVE, "aspd"))
	# Relic "Momentum": attack speed ramps up the longer this fight has gone.
	if relic_momentum_pct_per_sec > 0.0:
		m *= (1.0 + minf(relic_momentum_time * relic_momentum_pct_per_sec, 1.0))
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
	# Basic-mob signature passives (Orc Bloodrage, Archer Focus Fire, Rat
	# Infestation) stash their outgoing bonus in this meta each tick/hit — read
	# here so every damage source scales the same way. Defaults to 0 for anything
	# without a mob passive. See AutoBattleManager._tick_mob_passive.
	var mob_dmg_bonus: float = get_meta("mob_dmg_bonus", 0.0)
	if mob_dmg_bonus != 0.0:
		m *= (1.0 + mob_dmg_bonus)
	# Relic "Opening Burst": bonus damage for a short window at the start of each fight.
	if relic_opening_burst_remaining > 0.0:
		m *= (1.0 + relic_opening_burst_pct)
	# Relic "Underdog": bonus damage scaling with dead teammates this fight.
	if relic_underdog_dmg_per_dead > 0.0 and battle_manager:
		m *= (1.0 + relic_underdog_dmg_per_dead * battle_manager.fallen_allies.size())
	return m

# Row position at battle start (home_position.y), used by row_stat_mult relics.
# PLAYER_Y_FRONT/BACK live in main_game.gd (5..8); the midpoint below avoids a
# cross-file const dependency for this one read.
func is_front_row() -> bool:
	return home_position.y <= 6

func get_defense_multiplier(attacking_element: Element = Element.NORMAL) -> float:
	# Rating-based (2026-07-16): below 100 the shortfall is added to damage
	# taken linearly (75 → ×1.25); at/above 100 damage halves per +100
	# (200 → ×0.5, 300 → ×0.25). Clamped so nothing becomes fully immune or
	# takes more than 2.5×.
	var d: float = defensive_affinity.get(attacking_element, 100.0)
	if d >= 100.0:
		return maxf(pow(0.5, (d - 100.0) / 100.0), 0.1)
	return clampf(2.0 - d / 100.0, 1.0, 2.5)

func get_attack_multiplier(target_element: Element = Element.NORMAL) -> float:
	# Offensive rating / 100 (140 rating = ×1.4, matching the displayed %).
	return offensive_affinity.get(target_element, 100.0) / 100.0

# Name of whatever landed this unit's killing blow, for the run export's death
# cause. Set in take_damage() right before die(); "" if never damaged fatally
# by a tracked attacker (e.g. a DoT tick with no attacker ref).
var last_killed_by: String = ""

# Signals
signal health_changed(current: int, maximum: int)
signal died()
signal element_changed(new_element: Element)
signal leveled_up(new_level: int)
signal attacked(target)
signal mana_changed(current: int, maximum: int)
signal took_damage(amount: int, attacker)   # fires only on damage (not heals) → hit reaction
signal shield_changed(current: int)        # shield value changed (absorbed damage or granted)
signal ward_changed(hits: int, maximum: int)  # hit-count ward changed (Gargoyle Stone Ward)

# Hit-count ward: each hit is fully blocked and spends one charge, whatever its
# damage. Separate from current_shield (an HP pool) on purpose.
const STONE_WARD_HITS := 4
# Element counters (ELEMENT_COUNTERS.md): which hit elements block a troll_regen
# user's regen, keyed by ITS element. Never its own element; across the 6 Trolls
# every element appears exactly twice. Update the doc's tally when editing.
const REGEN_COUNTERS := {
	Element.NORMAL:    [Element.FIRE, Element.LIGHTNING],
	Element.AIR:       [Element.EARTH, Element.WATER],
	Element.WATER:     [Element.LIGHTNING, Element.EARTH],
	Element.EARTH:     [Element.WATER, Element.AIR],
	Element.FIRE:      [Element.AIR, Element.NORMAL],
	Element.LIGHTNING: [Element.NORMAL, Element.FIRE],
}
var ward_hits: int = 0
var ward_max: int = 0
# Phoenix Rebirth: >0 while rebuilding from the ashes — immune, can't act.
var rebirth_time: float = 0.0

func _ready():
	update_visuals()

# ── Negative effects: ONE canonical definition ───────────────────────────────
#
# THE CONTRACT: when a new negative effect is added to this class, add its timer
# here and reset its companion fields in `clear_debuffs()`. Nothing else needs
# to change — every cleanse in the game reads this list.
#
# WHY. Before this existed the same partial list was copy-pasted in three
# places (Reed's Cleanse, Cross's Absolution, the round reset) and they had
# already drifted apart: Reed's passive faded slow/burn/root, his active also
# cleared bleed, and neither touched stun — which is the debuff a player most
# expects a cleanse to answer. Both abilities claim to remove "all debuffs".
# The roster is still growing per element, so a hand-maintained list in each
# ability would drift again by the next hero.
#
# NOT IN THIS LIST, deliberately:
#   • outgoing_dmg_mult / outgoing_dmg_time — Pastor GRANTS this as a damage
#     BUFF. Only a value below 1.0 is a penalty, handled explicitly below.
#   • untargetable_time / melee_untargetable_time / bonus_* — beneficial.
#   • drain_stolen — the theft persists by design and is restored only when the
#     Stat Stealer dies (see restore_stat_theft). Cleansing the TIMER stops
#     further loss, which is the correct scope for a cleanse.
const DEBUFF_TIMERS: Array[String] = [
	"stun_time", "burn_time", "bleed_time", "slow_time", "root_time",
	"taunt_time", "weakened_time", "heal_cut_time", "drain_time", "puppet_time",
]

## Remove every negative effect. Used by any "cleanse" ability.
func clear_debuffs() -> void:
	for t in DEBUFF_TIMERS:
		set(t, 0.0)
	# Companion fields. A timer at 0 with a live dps/pct behind it is a bug
	# waiting for the next thing that re-arms the timer without resetting them.
	burn_dps = 0.0;  burn_accum = 0.0;  burn_source = null
	burn_parts.clear(); burn_stack_share = 0.0
	bleed_dps = 0.0; bleed_accum = 0.0; bleed_source = null
	slow_pct = 0.0
	taunt_source = null
	weakened_pct = 0.0; weaken_flavor = ""
	drain_stat = ""; drain_per_sec = 0.0; drain_accum = 0.0
	spore_stacks = 0.0; spore_tick_accum = 0.0
	# Only when it is actually a penalty — see the note above.
	if outgoing_dmg_mult < 1.0:
		outgoing_dmg_mult = 1.0
		outgoing_dmg_time = 0.0

## Shorten every negative effect by `seconds`, without removing it outright.
## Reed's Wellspring uses this so "debuffs fade faster" covers the same set his
## Cleanse strips, instead of the two disagreeing about what a debuff is.
func fade_debuffs(seconds: float) -> void:
	if seconds <= 0.0:
		return
	for t in DEBUFF_TIMERS:
		var v: float = get(t)
		if v > 0.0:
			set(t, maxf(v - seconds, 0.0))

# Strongest single burn on this unit. Equals burn_dps under the classic rule;
# under Kindred Flames it is the biggest one hero's part. This is what Sear's
# spread and Ashfall copy: a copy never reads a stacked total (VD-16 loop rule 2).
func burn_strongest_single() -> float:
	if burn_parts.is_empty():
		return burn_dps
	var best := 0.0
	for k in burn_parts:
		best = maxf(best, float(burn_parts[k][0]))
	return best

# Kindred Flames total: the strongest part in full, every other hero type adds
# burn_stack_share of its own, capped at 2x the strongest (VD-16 loop rule 4).
# Credit goes to the hero holding the strongest part.
func recompute_burn_total() -> void:
	var best := 0.0
	var best_src = null
	var total := 0.0
	var longest := 0.0
	for k in burn_parts:
		var p: Array = burn_parts[k]
		total += float(p[0])
		longest = maxf(longest, float(p[1]))
		if float(p[0]) > best:
			best = float(p[0])
			best_src = p[2]
	burn_dps = minf(best + burn_stack_share * (total - best), 2.0 * best)
	burn_time = longest
	if best_src != null and is_instance_valid(best_src):
		burn_source = best_src

# Magic-typed damage: identical pipeline, mitigated by magic_resist instead of
# armor. Use this for any hit whose amount scales off the caster's magic_power.
func take_magic_damage(amount: int, element: Element = Element.NORMAL, attacker = null) -> void:
	take_damage(amount, element, attacker, false, 0, true)

func take_damage(amount: int, element: Element = Element.NORMAL, attacker = null, true_damage: bool = false, bonus_true_damage: int = 0, is_magic: bool = false, is_crit: bool = false) -> void:
	# Already dead (e.g. a projectile/skill landed after a prior hit killed this
	# unit) — skip entirely so we don't re-run die(), on-hit passives, etc. on a corpse.
	if current_hp <= 0:
		return
	# Phoenix Rebirth: nothing lands while it is rebuilding.
	if rebirth_time > 0.0:
		return
	# Evasion: chance to dodge the hit entirely (only applies to direct hits, not DoT/true damage)
	if not true_damage and amount > 0:
		var ev: float = equipment_passives.get("Evasion", 0.0)
		if ev > 0.0 and randf() < ev:
			# Announce it. This used to be a bare `return`: no damage number, no
			# flash, nothing — so a dodged hit was indistinguishable from a bug.
			if battle_manager and battle_manager.has_method("spawn_evade"):
				battle_manager.spawn_evade(self)
			return

	var modified_damage := amount
	# Component equipment: Empty Reservoir / Arcane Precision on skill damage.
	# is_instance_valid FIRST: a projectile or DoT can outlive its attacker, and
	# `is` on a freed instance is a hard script error (crashed round ends 2026-09-26).
	if is_instance_valid(attacker) and attacker is UnitBase and not attacker.gear_levels.is_empty():
		modified_damage = GearPassives.skill_damage_mult(attacker, self, modified_damage, true_damage)
	# Attacker's offensive affinity vs THIS unit's element — applied centrally
	# (2026-07-17) so every non-true damage source scales the same way.
	if not true_damage and attacker != null and attacker is UnitBase:
		modified_damage = int(modified_damage * attacker.get_attack_multiplier(current_element))
	if not true_damage:
		# League-style diminishing-returns curve (2026-07-10, replaces flat
		# subtraction): 100 armor = 50% reduction, 200 = 66.7%, asymptotic —
		# never reaches 100%. Armor vs magic armor picked by the damage type
		# (2026-07-16 defense split).
		var armor: int = magic_resist if is_magic else resistance
		armor = GearPassives.effective_armor(self, armor)   # Spellguard / Sunder
		modified_damage = int(modified_damage * (100.0 / (100.0 + float(armor))))
		modified_damage = int(modified_damage * get_defense_multiplier(element))
	# Relic: fragile-but-deadly picks (e.g. Glass Cannon) raise incoming damage.
	if relic_dmg_taken_mult != 1.0:
		modified_damage = int(round(modified_damage * relic_dmg_taken_mult))
	# Relic "Underdog": takes less damage the more teammates have fallen this fight.
	if relic_underdog_res_per_dead > 0.0 and battle_manager:
		var underdog_cut: float = minf(0.8, relic_underdog_res_per_dead * battle_manager.fallen_allies.size())
		modified_damage = int(round(modified_damage * (1.0 - underdog_cut)))
	modified_damage = max(1, modified_damage)
	# Ant Hill swarm bite stacks: added AFTER the flat resistance subtraction and
	# max(1,...) floor above, as true damage. Bite stacks are a snowballing DPS
	# check (each bite makes every future ant bite hit harder) — computed as a
	# pre-mitigation bonus, they got fully eaten by resistance's flat subtraction
	# and every ant hit floored to 1 dmg forever, no matter how many stacks piled
	# up (2026-07-10 bug report: fights stalling out with neither side progressing).
	modified_damage += bonus_true_damage

	# Anti-stall enrage: once a fight drags past Balance.BATTLE_ENRAGE_START,
	# every damage source on BOTH sides is scaled up (doubling every
	# BATTLE_ENRAGE_DOUBLE_EVERY seconds) so the battle actually terminates —
	# the engine has no other timeout. Applied HERE rather than in
	# outgoing_damage_multiplier() because that one is only consulted by basic
	# attacks; skills, ultimates, projectiles and DoTs all converge on
	# take_damage, so this is the single point that catches everything.
	# See AutoBattleManager.enrage_multiplier for the full rationale.
	if battle_manager and battle_manager.has_method("enrage_multiplier"):
		var enrage: float = battle_manager.enrage_multiplier()
		if enrage > 1.0:
			modified_damage = int(modified_damage * enrage)

	# Stone Ward: a whole hit is blocked and spends one charge, big or small.
	if ward_hits > 0 and modified_damage > 0:
		ward_hits -= 1
		ward_changed.emit(ward_hits, ward_max)
		spawn_damage_text(0, element)
		times_hit += 1
		if ward_hits == 0 and battle_manager and battle_manager.has_method("spawn_stone_ward_break"):
			battle_manager.spawn_stone_ward_break(self)
		return

	# Component equipment: Bulwark block, then the violet item-shield pool.
	if not gear.is_empty():
		var shield_before := gear_shield
		modified_damage = GearPassives.pre_shield(self, modified_damage, attacker, true_damage)
		milestone_shield_absorbed += maxi(0, shield_before - gear_shield)
		if modified_damage <= 0:
			return
	# Shield absorbs damage before HP
	if current_shield > 0:
		var absorbed: int = mini(current_shield, modified_damage)
		milestone_shield_absorbed += absorbed
		current_shield -= absorbed
		modified_damage -= absorbed
		shield_changed.emit(current_shield)
		if modified_damage <= 0:
			spawn_damage_text(absorbed, element)
			return   # fully blocked — no HP lost, no signals

	if not gear_levels.is_empty():
		var before_mana_shield := modified_damage
		modified_damage = GearPassives.post_shield(self, modified_damage, attacker, true_damage)
		milestone_shield_absorbed += maxi(0, before_mana_shield - modified_damage)
		if modified_damage <= 0:
			return
	spawn_damage_text(modified_damage, element, is_crit)

	var gear_pre_hp: int = current_hp
	current_hp = max(0, current_hp - modified_damage)   # setter emits health_changed
	# Troll "Regeneration" counterplay: a hit of one of its two REGEN_COUNTERS
	# elements (per Troll element) shuts its passive
	# regen off for a couple seconds (ticked down in AutoBattleManager). Element is
	# only known here, so the flag is set at the damage site rather than in the tick.
	if not true_damage and has_meta("mob_passive") and str(get_meta("mob_passive")) == "troll_regen" \
			and element in REGEN_COUNTERS.get(current_element, []):
		set_meta("troll_regen_block_t", 2.0)
	# Stone Ward trigger: the hit that crosses 50% still lands in full; the ward
	# covers the NEXT hits. A hit that kills outright never raises it.
	if current_hp > 0 and current_hp * 2 <= max_hp and not has_meta("ward_used") \
			and has_meta("mob_passive") and str(get_meta("mob_passive")) == "gargoyle_ward":
		set_meta("ward_used", true)
		ward_max = STONE_WARD_HITS
		ward_hits = STONE_WARD_HITS
		ward_changed.emit(ward_hits, ward_max)
		if battle_manager and battle_manager.has_method("spawn_stone_ward"):
			battle_manager.spawn_stone_ward(self)
	times_hit += 1
	took_damage.emit(modified_damage, attacker)   # drives the hit reaction (flash + recoil)
	_charge_ultimate(modified_damage)
	# Track who dealt damage to us (for Bloodhound ultimate)
	if attacker != null:
		var prev: int = damage_taken_from.get(attacker, 0)
		damage_taken_from[attacker] = prev + modified_damage

	# Stitch mechanics: propagate Link damage; its owner receives Threadguard.
	if battle_manager and modified_damage > 0 and battle_manager.has_method("propagate_damage_links"):
		battle_manager.propagate_damage_links(self, modified_damage, attacker)

	if current_hp <= 0:
		# Balance export (2026-08-05): who/what landed the killing blow, read by
		# main_game's death-cause tracker so the run export can say what ended it.
		if attacker != null and attacker is UnitBase:
			last_killed_by = str(attacker.unit_name)
		GearPassives.on_death(self)
		# Ashfall (VD-16): the burn jumps while the body still carries it.
		if burn_time > 0.0 and battle_manager and battle_manager.has_method("burn_ashfall"):
			battle_manager.burn_ashfall(self)
		die()
	if not gear.is_empty() or (is_instance_valid(attacker) and attacker is UnitBase 			and not attacker.gear.is_empty()):
		GearPassives.after_hit(self, attacker, mini(modified_damage, gear_pre_hp),
			modified_damage, gear_pre_hp, is_crit, true_damage)

# (The old hardcoded 1.5x rock-paper-scissors matchup table lived here until
# the 2026-07-16 affinity rework — elemental interaction is now entirely
# "attacker's offensive rating vs target's defensive rating".)

func heal(amount: int, silent: bool = false) -> void:
	# Khagan puppet: the possessed hero can't self-sustain while controlled — this
	# single gate neutralizes regen, lifesteal, drain-heals and skill/ult heals
	# alike (all sustain routes through heal()), so a geared bruiser/healer can't
	# wall the possession fight forever. Restored when control breaks.
	if has_meta("khagan_puppet"):
		return
	# Riptide (Drowned Maw, wave 30): healing RECEIVED is cut while the aura holds.
	# Same choke-point logic as the puppet gate above — one gate here covers every
	# sustain route in the game instead of patching each heal source.
	if heal_cut_time > 0.0:
		amount = int(round(float(amount) * AutoBattleManager.DROWNED_HEAL_MULT))
		if amount <= 0:
			return
	# Deep Wound (component equipment) cuts healing received.
	if not gear.is_empty():
		amount = GearPassives.heal_received(self, amount)
		if amount <= 0:
			return
	var before: int = current_hp
	current_hp = min(max_hp, current_hp + amount)   # setter emits health_changed
	var healed: int = current_hp - before
	if healed > 0 and not silent:
		spawn_heal_text(healed)

func restore_mana(amount: int) -> void:
	current_mana = min(max_mana, current_mana + amount)   # setter emits mana_changed

func spend_mana(amount: int) -> bool:
	if current_mana >= amount:
		current_mana -= amount
		return true
	return false

func change_element(new_element: Element) -> void:
	current_element = new_element
	# Re-anchor the ±affinity deltas on the new element (2026-07-16 rework).
	set_affinity_profile(base_off_affinity, base_def_affinity)
	element_changed.emit(new_element)
	update_visuals()

# Applies one tick of this unit's personalized per-level growth to every stat.
# Shared by level_up() (level 2+, in combat) AND the recruit flow (level 1
# already "counts" as having received its level's growth the moment you buy the
# hero — see UnitFactory.apply_recruit_rolls). Two recruits of the same class
# will diverge over time since their growth rolls differ.
func apply_stat_growth() -> void:
	# hp/mana route through the same fractional-carry helper as atk/magic
	# (2026-08-02: the Fortified/Mana Well Growth upgrades can add a fraction
	# on top of the already-whole per-class growth, so the carry still matters
	# once that fraction and the class's own roll don't land on a whole number).
	max_hp         = _grow_int_stat(max_hp, "hp", 1)
	max_mana       = _grow_int_stat(max_mana, "mana", 0)
	attack_damage  = _grow_int_stat(attack_damage, "atk", 1)
	magic_power    = _grow_int_stat(magic_power, "magic", 0)
	# "res" growth is always a whole number in CLASS_GROWTH_PER_LEVEL (no
	# fractional source touches it), so plain int() is fine here — no carry
	# bucket needed, and importantly resistance/magic_resist must NOT share
	# one via _grow_int_stat("res", ...) since that would corrupt each
	# other's remainder. Armor Growth below is physical-only, in its own key.
	resistance     = maxi(0, resistance     + int(stat_growth("res")))
	resistance     = _grow_int_stat(resistance, "armor", 0)
	# Magic armor rides the same "res" growth roll until it gets its own table
	# entry (defense split 2026-07-16 — keeps leveling balance-neutral).
	magic_resist   = maxi(0, magic_resist   + int(stat_growth("res")))
	# Tenacity has no per-class growth roll (no entry in CLASS_GROWTH_PER_LEVEL)
	# — the "ten" key exists so gear/crystal-tree sources can grant per-level
	# tenacity later without another special case here. int() is safe today
	# because nothing feeds it a fraction yet; give it a carry bucket if one does.
	tenacity       = maxi(0, tenacity       + int(stat_growth("ten")))
	attack_speed   = maxf(0.05, attack_speed + stat_growth("aspd"))
	hp_regen       = maxf(0.0,  hp_regen     + stat_growth("hpregen"))
	mana_regen     = maxf(0.0,  mana_regen   + stat_growth("manaregen"))
	# 2026-08-02: crit chance/damage have no innate per-class growth (see
	# PROGRESSION_GROWTH_KEYS above) — floats, so no carry needed.
	crit_chance    = maxf(0.0, crit_chance   + stat_growth("crit"))
	crit_damage    = maxf(0.0, crit_damage   + stat_growth("critdmg"))

# `allow_past_cap` exists for exactly one caller: the debug round-warp, which
# deliberately fields over-levelled heroes so a warped-to boss reads honestly.
# Everything else is capped HERE rather than at each call site (2026-08-07):
# grant_xp and set_level both checked the cap, but the "Invest in training"
# event called this raw and pushed a tester to level 16 on a tree with no Max
# Hero Level nodes. Guarding the primitive means the next new caller inherits
# the rule instead of having to remember it.
func level_up(allow_past_cap: bool = false) -> void:
	if is_player_unit and not allow_past_cap \
			and level >= Progression.hero_level_cap():
		return
	level += 1
	apply_stat_growth()
	# Leveling restores half of missing health instead of fully refilling it.
	current_hp += int(ceil(float(max_hp - current_hp) * 0.5))
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
	# (2026-07-17: offensive affinity no longer applied here — take_damage()
	# applies the attacker's multiplier centrally, so autos, skills, ultimates
	# and projectiles all ride the same off-vs-def affinity rule exactly once.)
	var damage := attack_damage
	damage = int(damage * outgoing_damage_multiplier())
	# Relic outgoing multipliers (Glass Cannon, element relics, Executioner vs bosses).
	if relic_outgoing_mult != 1.0:
		damage = int(damage * relic_outgoing_mult)
	if relic_vs_boss_mult != 1.0 and target is UnitBase and target.is_boss:
		damage = int(damage * relic_vs_boss_mult)
	# Relic "Row" mult: front-row vs back-row heroes hit differently.
	if relic_row_front_mult != 1.0 or relic_row_back_mult != 1.0:
		damage = int(damage * (relic_row_front_mult if is_front_row() else relic_row_back_mult))
	# Relic "Execute": bonus damage while the target is below an HP% threshold.
	if relic_execute_bonus > 0.0 and target is UnitBase and target.max_hp > 0 \
			and float(target.current_hp) / float(target.max_hp) <= relic_execute_threshold:
		damage = int(damage * (1.0 + relic_execute_bonus))
	# Relic "Gold-scaling": bonus damage scaling with the run's current gold total.
	if relic_gold_scaling_dmg > 0.0 and battle_manager and battle_manager.game_state:
		damage = int(damage * (1.0 + relic_gold_scaling_dmg * float(battle_manager.game_state.gold)))
	# Ant Hill swarm (2026-07-24 rework): the bonus is now a GLOBAL swarm-rage
	# counter (AutoBattleManager.ant_swarm_stacks), not a per-victim one. Every
	# landed Ant bite — on ANY target — ramps up EVERY Ant's damage against
	# ANY target for the rest of the fight. The old per-victim version let
	# players stall forever by spreading the swarm's attention (and healing)
	# across many units, since no single target ever built up enough stacks
	# to matter — this way the swarm gets scarier over time no matter who it's
	# biting, so healing through it is a real DPS check instead of a stalemate.
	# Read BEFORE this hit's stack increment (_apply_on_hit_passives), so the
	# 1st bite of the fight is normal, the 2nd is +1, the 3rd is +2, etc.
	# Passed to take_damage() as unmitigated bonus_true_damage (2026-07-10 fix)
	# — added to `damage` here it was flat-resistance'd away and floored to
	# 1 dmg forever, since resistance is a flat subtraction, not a percentage.
	var ant_bonus_dmg: int = 0
	if unit_class == UnitClass.ANT and battle_manager:
		ant_bonus_dmg = battle_manager.ant_swarm_stacks

	hit_counter += 1
	# Generic crit roll (separate from the Headhunter/Shauna hit-counter flavor
	# mechanics below — those are class-specific tricks, this is the real crit
	# stat that gear/relics/the Stat Stealer's drain read and write).
	# did_crit drives the gold/oversized/wobble crit floating text (DamageText).
	# Both the generic crit stat and the Headhunter 7th-hit triple are "crits" visually.
	var did_crit := false
	var pre_crit_damage := damage
	var crit_mult := 1.0
	# Component equipment crit sources (Desperation, Critical Focus,
	# Counterstrike) add here; both bonuses are 0 for a unit without gear.
	var roll_chance: float = crit_chance + GearPassives.crit_bonus(self)
	if roll_chance > 0.0 and randf() < roll_chance:
		crit_mult = crit_damage + GearPassives.crit_damage_bonus(self)
		damage = int(damage * crit_mult)
		did_crit = true
	GearPassives.on_attack_roll(self)
	# Relic "First Strike": the first attack each fight is a guaranteed crit for
	# at least the relic's multiplier. A natural crit that rolls lower is raised
	# to it instead of using the relic up for nothing (VD-21).
	if relic_first_strike_crit and not relic_first_strike_used:
		relic_first_strike_used = true
		if relic_first_strike_crit_mult > crit_mult:
			damage = int(pre_crit_damage * relic_first_strike_crit_mult)
		did_crit = true
	# Headhunter "Seventh Shot" — numbers from AbilityFormulas, see that file.
	var is_seventh_shot := false
	if unit_class == UnitClass.HEADHUNTER \
			and hit_counter % int(AbilityFormulas.flat(unit_class, AbilityFormulas.PASSIVE, "every")) == 0:
		damage = int(damage * AbilityFormulas.flat(unit_class, AbilityFormulas.PASSIVE, "mult"))
		did_crit = true
		is_seventh_shot = true
	# Shauna: next attack boosted from the Kite active
	var is_boosted := next_attack_boosted
	if is_boosted:
		damage = int(damage * (1.0 + AbilityFormulas.flat(
				UnitClass.SHAUNA, AbilityFormulas.ACTIVE, "boost")))
		next_attack_boosted = false
	# Shauna "Glass Cannon": every Nth hit is true damage (bypasses defence)
	var is_true_dmg := (unit_class == UnitClass.SHAUNA \
			and hit_counter % int(AbilityFormulas.flat(unit_class, AbilityFormulas.PASSIVE, "every")) == 0)

	# The Hill Giant's club uses its real attack sheet. Resolve the hit on the
	# authored contact frame instead of dealing damage before the swing begins.
	if str(get_meta("sprite_folder", "")) == "hill_giant" and battle_manager \
			and battle_manager.has_method("begin_hill_giant_auto"):
		battle_manager.begin_hill_giant_auto(self, target, damage, did_crit, is_true_dmg)
		pending_attack_log_damage += damage
		attacked.emit(target)
		return
	# The Wind-Up Bot has no authored attack sheet (static PNG art), so its swing
	# is VisualUnit.play_attack's procedural lunge. Resolve the hit at that
	# lunge's forward extent instead of before the body has moved — previously
	# the damage number appeared, then the bot leaned forward afterwards.
	if (bool(get_meta("windup_bot", false)) or str(get_meta("dot_flavor", "")) == "disease") \
			and battle_manager and battle_manager.has_method("begin_windup_auto"):
		battle_manager.begin_windup_auto(self, target, damage, did_crit, is_true_dmg)
		pending_attack_log_damage += damage
		attacked.emit(target)
		return
	# Sheildor's authored greatshield push has a clear contact beat. Queue the
	# complete landed-hit package so damage, relics and impact VFX all occur on
	# the shield collision rather than before his body starts moving.
	# June's strike is a two-beat lash: her LEFT hand leads to peak reach at 23%
	# of the clip and the right follows at 48% (measured on june_v002.glb with
	# measure_june_contact.py). Damage resolves on the lead contact.
	# Bouncer's rubber punch: the hit lands when the drawn glove reaches the
	# target (RubberArm.contact_time(): 0.19 launch + 0.07 out), not at wind-up.
	if unit_class == UnitClass.BOUNCER and battle_manager \
			and battle_manager.has_method("begin_bouncer_auto"):
		battle_manager.begin_bouncer_auto(self, target, damage, did_crit, is_true_dmg,
			BOUNCER_PUNCH_CONTACT)
		pending_attack_log_damage += damage
		attacked.emit(target)
		return
	if unit_class == UnitClass.JUNE and battle_manager \
			and battle_manager.has_method("begin_june_auto"):
		battle_manager.begin_june_auto(self, target, damage, did_crit, is_true_dmg,
			(1.0 / attacks_per_second) * 0.23)
		pending_attack_log_damage += damage
		attacked.emit(target)
		return
	if unit_class == UnitClass.SHEILDOR and battle_manager \
			and battle_manager.has_method("begin_sheildor_auto"):
		var attack_duration := 1.0 / attacks_per_second
		battle_manager.begin_sheildor_auto(self, target, damage, did_crit,
			is_true_dmg, attack_duration * 0.48)
		pending_attack_log_damage += damage
		attacked.emit(target)
		return

	# Headhunter active bonus range already applied by battle manager

	# Bouncer is a melee brawler despite having range 2 (grab/pull reach) — no projectile.
	if attack_range > 1 and unit_class != UnitClass.BOUNCER:
		gear_basic_hit = true   # stamps the projectile as a basic attack
		spawn_projectile(target, damage, false, did_crit, is_seventh_shot, is_true_dmg)
		gear_basic_hit = false
		pending_attack_log_damage += damage   # intended damage (mitigated on hit)
	else:
		var pre_hp: int = target.current_hp
		var was_alive: bool = pre_hp > 0
		gear_basic_hit = true
		target.take_damage(damage, current_element, self, is_true_dmg, ant_bonus_dmg, false, did_crit)
		gear_basic_hit = false
		var actual: int = max(0, pre_hp - target.current_hp)
		damage_dealt += actual
		pending_attack_log_damage += actual
		_charge_ultimate(actual / 4)
		apply_relic_on_hit(target, actual, was_alive)

	attacked.emit(target)

# Lifesteal + Soul-Harvest on-kill, shared by melee (here) and ranged (projectile
# on-reach). `was_alive` guards the kill bonus so it only fires on the killing blow.
func apply_relic_on_hit(target, actual: int, was_alive: bool) -> void:
	if actual <= 0:
		return
	if relic_lifesteal > 0.0:
		heal(int(round(actual * relic_lifesteal)))
	apply_bloodhound_frenzy_lifesteal(actual)
	if relic_on_kill_atk > 0.0 and was_alive and target is UnitBase and target.current_hp <= 0:
		grant_on_kill_attack()
	if relic_ult_refund_kill > 0.0 and was_alive and target is UnitBase and target.current_hp <= 0 \
			and ultimate_charge_max > 0 and not ultimate_ready:
		ultimate_charge = mini(ultimate_charge_max, ultimate_charge + int(round(ultimate_charge_max * relic_ult_refund_kill)))
		if ultimate_charge >= ultimate_charge_max:
			ultimate_ready = true

# On-kill relics ("+1% attack damage per kill, stacks all run"). Linear, as the
# text reads: each kill adds the relic's share of the hero's attack WITHOUT its
# kill growth, and the fraction carries. The old int(round(atk x 1.01)) gave
# back the same attack for any hero under 50 attack, so the relic did nothing
# (VD-21). Whole points land in attack_damage; relic_kill_atk_gain keeps the
# running total so the battle-end synergy revert and save/resume keep them.
func grant_on_kill_attack() -> void:
	var baked := kill_atk_whole()
	var base := float(maxi(1, attack_damage - baked))
	relic_kill_atk_gain += base * relic_on_kill_atk
	attack_damage += kill_atk_whole() - baked

# Whole attack points on-kill relics have added so far; the fraction waits. The
# epsilon keeps a float sum like 9.9999999 from paying out one point late.
func kill_atk_whole() -> int:
	return int(floor(relic_kill_atk_gain + 0.000001))

func apply_bloodhound_frenzy_lifesteal(actual: int) -> void:
	if actual <= 0 or unit_class != UnitClass.BLOODHOUND or not frenzy_active:
		return
	heal(int(round(actual * AbilityFormulas.flat(UnitClass.BLOODHOUND,
			AbilityFormulas.PASSIVE, "lifesteal"))))

func _charge_ultimate(amount: int) -> void:
	if ultimate_charge_max <= 0 or ultimate_ready or ult_active_time > 0.0:
		return
	if relic_ult_charge_mult != 1.0:
		amount = int(round(amount * relic_ult_charge_mult))
	# Tinder Heart (VD-16). Bounded: burn ticks never reach this function for
	# the burner, so the bonus can only ever be a flat multiplier.
	if burn_haste_active:
		amount = int(round(amount * (1.0 + relic_burn_ult_haste)))
	ultimate_charge = min(ultimate_charge + amount, ultimate_charge_max)
	if ultimate_charge >= ultimate_charge_max:
		ultimate_ready = true

func grant_xp(amount: float) -> void:
	current_xp += amount
	# 2026-08-01: hero level cap (Progression.hero_level_cap(), base 10, raised
	# by the Max Hero Level tree family). Enemies/summons (is_player_unit
	# false) aren't capped — only player heroes are meta-progression-gated.
	var cap := Progression.hero_level_cap() if is_player_unit else 999999
	while current_xp >= xp_to_level and level < cap:
		current_xp -= xp_to_level
		xp_to_level *= 1.5
		level_up()
		perk_points += 1
	if level >= cap:
		current_xp = 0.0   # capped: don't let XP pile up uselessly past the cap

func set_level(target_level: int) -> void:
	var cap := Progression.hero_level_cap() if is_player_unit else 999999
	while level < target_level and level < cap:
		level_up()

# Per-hero delay between the attack call and the bullet actually leaving the
# muzzle, so it launches on the attack sheet's fire frame instead of the
# instant the attack triggers (which used to be before the character even
# finished raising the weapon). Real seconds, matching that hero's attack
# sheet fps/frame count — 0.0 (unlisted) reproduces the old immediate-launch
# behavior. Add an entry here for any other ranged hero whose attack sheet
# has a visible aim/fire beat once it's confirmed the anim is really playing.
## Where in Sear's attack interval the bolt leaves his hand. One constant so the
## projectile's spawn_delay and the caster's flame-gather beat are driven by the
## same number instead of two hand-tuned ones that drift apart.
const SEAR_MUZZLE_FRAC := 0.30

## Goblin Archer (goblin_v010.glb `attack_bow`): the string is released on
## frame 10 of 20. The clip is played timed to one attack interval and the arrow
## waits for that frame, so the shot and the arrow cannot drift apart. Both use
## REAL seconds (the projectile's hold and the clip run on frame delta, while
## combat runs at time_scale), hence goblin_shot_seconds() divides it out.
const GOBLIN_ARROW_RELEASE_FRAC := 0.5

## Battle seconds from Bouncer's attack to the glove landing — must equal
## RubberArm launch_delay + out_time (0.19 + 0.07).
const BOUNCER_PUNCH_CONTACT := 0.26

func goblin_shot_seconds() -> float:
	var ts: float = battle_manager.time_scale if battle_manager else 1.0
	return (1.0 / maxf(attacks_per_second, 0.01)) / maxf(ts, 0.05)

const PROJECTILE_MUZZLE_DELAY := {
	UnitClass.HEADHUNTER: 0.83,   # attack.json: 12fps, flash starts ~frame 10
}

func spawn_projectile(target, damage: int, is_magic: bool = false, is_crit: bool = false, is_seventh_shot: bool = false, is_true_dmg: bool = false) -> void:
	if not battle_manager:
		return

	var projectile := Projectile.new()
	var start_pos: Vector2 = global_position
	var end_pos:   Vector2 = target.global_position if target else global_position

	projectile.setup(start_pos, end_pos, damage, current_element, target)
	projectile.is_magic = is_magic
	projectile.is_crit = is_crit
	projectile.is_seventh_shot = is_seventh_shot
	projectile.is_true_damage = is_true_dmg
	projectile.caster = self   # so on_reach_target can credit damage_dealt
	projectile.is_basic_auto = gear_basic_hit
	projectile.is_goblin_arrow = str(get_meta("sprite_folder", "")) == "goblin_archer"
	projectile.is_goblin_shaman_orb = str(get_meta("sprite_folder", "")).begins_with("goblin_shaman_")
	projectile.is_vail_gust = unit_class == UnitClass.VAIL
	if projectile.is_vail_gust:
		# Muzzle beat at Vail herself. Spawned here rather than in the battle
		# manager because this is the one place that knows a shot was actually
		# fired — the manager's skill path never runs for a basic attack.
		var vail_fx_host = battle_manager.skill_effect_container \
			if battle_manager.skill_effect_container else battle_manager
		if vail_fx_host:
			var muzzle := VailVFX.new()
			vail_fx_host.add_child(muzzle)
			muzzle.setup_point(VailVFX.Mode.GUST_MUZZLE, global_position, 0.30, self)
	projectile.focus_stacks = int(get_meta("ff_stacks", 0)) if projectile.is_goblin_arrow else 0
	projectile.spawn_delay = PROJECTILE_MUZZLE_DELAY.get(unit_class, 0.0)
	if projectile.is_goblin_arrow:
		projectile.spawn_delay = goblin_shot_seconds() * GOBLIN_ARROW_RELEASE_FRAC
	if unit_class == UnitClass.STATIC:
		projectile.is_static_arc = true
		projectile.speed = 900.0
		projectile.spawn_delay = 0.22
	elif unit_class == UnitClass.ZOLT:
		projectile.is_zolt_arc = true
		projectile.speed = 780.0
		# Zolt's hands reach their authored release pose 12% into the attack.
		# Both this delay and VisualUnit's clip duration derive from the same live
		# APS, so haste/slow can never pull the projectile away from the gesture.
		projectile.spawn_delay = (1.0 / attacks_per_second) * 0.12
	elif unit_class == UnitClass.SEAR:
		projectile.is_sear_bolt = true
		projectile.speed = 760.0
		# Shared with VisualUnit._sear_cast_beat so the bolt leaves on the same
		# beat the flame gathers, at every attack speed.
		projectile.spawn_delay = (1.0 / attacks_per_second) * SEAR_MUZZLE_FRAC
	elif unit_class == UnitClass.RIFT:
		projectile.is_rift_void = true
		projectile.speed = 720.0
		projectile.spawn_delay = (1.0 / attacks_per_second) * 0.34

	# Per-hero auto-attack sprite override — see Projectile.sprite_tex. Every
	# other hero keeps the plain colored circle.
	if unit_class == UnitClass.NEMI:
		var auto_tex: Texture2D = load("res://assets/particle/heroes/nemi/nemi_auto.png") as Texture2D
		if auto_tex:
			projectile.sprite_tex = auto_tex
			projectile.sprite_frame_w = 25
			projectile.sprite_frame_h = 30
			projectile.sprite_frame_count = 8
			projectile.sprite_fps = 14.0
			projectile.sprite_display_size = Vector2(46, 56)
	elif unit_class == UnitClass.HEADHUNTER:
		var bullet_tex: Texture2D = load("res://assets/particle/heroes/headhunter/headhunter_auto.png") as Texture2D
		if bullet_tex:
			projectile.sprite_tex = bullet_tex
			projectile.sprite_frame_w = 25
			projectile.sprite_frame_h = 20
			projectile.sprite_frame_count = 8
			projectile.sprite_fps = 14.0
			projectile.sprite_display_size = Vector2(40, 32)
	elif unit_class == UnitClass.SHAUNA:
		var frames: Array[Texture2D] = []
		for i in range(1, 9):
			var tex := load("res://assets/particle/heroes/shauna/shauna_auto_%d.png" % i) as Texture2D
			if tex:
				frames.append(tex)
		if not frames.is_empty():
			projectile.sprite_frames = frames
			projectile.sprite_fps = 14.0
			projectile.sprite_display_size = Vector2(28, 35)

	if battle_manager.has_method("add_projectile"):
		battle_manager.add_projectile(projectile)

func spawn_crippling_arrow(target, damage: int, slow_pct: float, slow_duration: float) -> void:
	if not battle_manager:
		return
	var projectile := Projectile.new()
	projectile.setup(global_position, target.global_position if target else global_position,
		damage, current_element, target)
	projectile.caster = self
	projectile.is_goblin_arrow = true
	projectile.is_crippling_arrow = true
	projectile.slow_pct = slow_pct
	projectile.slow_duration = slow_duration
	projectile.speed = 720.0
	# Same bow shot as his auto (it used to fire with no body motion at all):
	# play the draw, release the arrow on the string frame.
	if has_method("play_goblin_bow_shot"):
		call("play_goblin_bow_shot", target)
		projectile.spawn_delay = goblin_shot_seconds() * GOBLIN_ARROW_RELEASE_FRAC
	battle_manager.add_projectile(projectile)

func die() -> void:
	# Khagan's puppet: bursting it to 0 HP frees it EARLY (clamps to 1 HP instead
	# of dying) — one of two break paths, the other being the survival timer in
	# AutoBattleManager._tick_khagan_possession. end_khagan_possession restores
	# the loaned stats; the between-round row heal tops the hero up afterward
	# (home_position untouched). Mirrors the VisualUnit.die() override.
	if has_meta("khagan_puppet") and current_hp <= 0:
		current_hp = 1
		current_shield = 0
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

func spawn_damage_text(damage: int, element: Element, is_crit: bool = false) -> void:
	if not damage_text_container:
		return

	var damage_text = DamageText.new()
	# Spawn ABOVE the HP-bar zone with a little horizontal jitter so numbers
	# clear the bar and don't stack on top of each other (2026-07-17).
	var spawn_pos = global_position + Vector2(randf_range(-16.0, 16.0), -48.0)
	# add_child BEFORE setup so setup()'s global_position is resolved against the
	# container's real (battle_grid_node-offset) transform. Setting it while the
	# node was still orphaned stored the value as a LOCAL position, so once
	# parented the number flashed ~origin px to the right for a frame before
	# _process snapped it back — reading as damage text darting/duplicating off
	# to the right of the board (2026-07-22).
	damage_text_container.add_child(damage_text)
	damage_text.setup(damage, element, spawn_pos, is_crit)

# Green "+N" floating text — fires whenever heal() actually restores any HP,
# regardless of source (skills, lifesteal, auras, relics — anything routed
# through heal()), matching spawn_damage_text's shape above.
func spawn_heal_text(amount: int) -> void:
	if not damage_text_container:
		return

	var heal_text = DamageText.new()
	var spawn_pos = global_position + Vector2(randf_range(-16.0, 16.0), -48.0)
	# add_child before setup (see spawn_damage_text) so the position resolves in
	# the container's real transform instead of flashing off to the right.
	damage_text_container.add_child(heal_text)
	heal_text.setup_heal(amount, spawn_pos)
