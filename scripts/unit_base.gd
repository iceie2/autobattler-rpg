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
	BAT
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

# Attributes
@export var strength: int = 10
@export var dexterity: int = 10
@export var intelligence: int = 10
@export var resistance: int = 10
@export var spirit: int = 5    # drives HP regen (SPR+STR/10) and MP regen (SPR+INT/5)

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

# XP / levelling
var current_xp: int = 0
var xp_to_level: int = 200
var perk_points: int = 0   # queued bonus stat choices shown in level-up screen between rounds

# Economy (set on enemy units; ignored for player units)
var gold_reward: int = 0
var crystal_reward: int = 0

# Multi-cell size (1 = normal 1×1, 2 = 2×2 boss)
var cell_size: int = 1

# Gacha rolls applied at recruit time
var recruit_rolls: Dictionary = {}   # {stat_key: {flat, growth}}
var recruit_grade: String     = ""   # "S" "A" "B" "C" "D"

# ── Shield system ─────────────────────────────────────────────────────────────
var current_shield: int = 0   # absorbs damage before HP; resets at round end

# ── Summon system (Necro) ─────────────────────────────────────────────────────
var is_summoned: bool     = false   # true for Zombie / Bat summons
var summon_owner: UnitBase = null   # Necro reference (for passive heal)

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

# Battle state
var grid_position: Vector2i = Vector2i.ZERO
var home_position: Vector2i = Vector2i.ZERO   # row at battle start — drives heal/XP bonuses
var kill_count:    int       = 0              # kills this battle — counts toward XP
var target_unit = null
var is_player_unit: bool = true
var battle_manager = null
var damage_text_container: Node2D = null
var skill_effect_container: Node2D = null

# Derived stats
var attack_damage: int:
	get:
		return strength + int(dexterity * 0.5)

var magic_power: int:
	get:
		return intelligence + int(strength * 0.3)

var defense: int:
	get:
		return resistance + int(strength * 0.2)

# Basic attacks per second, derived from dexterity. Clamped so no unit is absurdly
# fast or slow. The battle manager resets attack_cooldown to 1.0 / attacks_per_second
# after each swing.
var attacks_per_second: float:
	get:
		var base: float = clampf(0.5 + dexterity * 0.02, 0.3, 3.0)
		base *= speed_modifier()
		return clampf(base, 0.1, 6.0)

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
		m *= (1.0 + momentum_stacks * 0.06)
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

func take_damage(amount: int, element: Element = Element.NORMAL, attacker = null, true_damage: bool = false) -> void:
	var modified_damage := calculate_damage_with_element(amount, element)
	if not true_damage:
		modified_damage = max(1, modified_damage - defense)
		modified_damage = int(modified_damage * get_defense_multiplier(element))
	modified_damage = max(1, modified_damage)

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
	current_hp = min(max_hp, current_hp + amount)
	health_changed.emit(current_hp, max_hp)

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

func level_up() -> void:
	level += 1
	
	# Stat increases vary by class
	match unit_class:
		UnitClass.WARRIOR:
			max_hp += 25
			strength += 3
			resistance += 2
		UnitClass.RANGER:
			max_hp += 15
			dexterity += 3
			strength += 2
		UnitClass.MONK:
			max_hp += 20
			strength += 2
			dexterity += 2
			resistance += 1
		UnitClass.THIEF:
			max_hp += 12
			dexterity += 4
			strength += 1
		UnitClass.BLACK_MAGE:
			max_hp += 10
			max_mana += 20
			intelligence += 4
		UnitClass.WHITE_MAGE:
			max_hp += 12
			max_mana += 18
			intelligence += 3
			resistance += 2
		UnitClass.RED_MAGE:
			max_hp += 15
			max_mana += 15
			intelligence += 2
			strength += 2
		UnitClass.BLOODHOUND:
			max_hp += 22
			strength += 2
			resistance += 2
			spirit += 1
		UnitClass.BOUNCER:
			max_hp += 28
			intelligence += 2
			resistance += 2
			spirit += 1
		UnitClass.HEADHUNTER:
			max_hp += 10
			dexterity += 3
			strength += 1
		UnitClass.SHAUNA:
			max_hp += 12
			dexterity += 3
			strength += 1
			spirit += 1
		UnitClass.NEMI:
			max_hp += 14
			max_mana += 20
			intelligence += 3
			spirit += 2
		UnitClass.SHEILDOR:
			max_hp += 18
			max_mana += 15
			intelligence += 2
			resistance += 2
			spirit += 2
		UnitClass.LORDEE:
			max_hp += 22
			max_mana += 12
			intelligence += 3
			resistance += 2
		UnitClass.NECRO:
			max_hp += 10
			max_mana += 25
			intelligence += 4
			spirit += 2
		# ── Roster expansion ──────────────────────────────────────────────────
		UnitClass.DOC:
			max_hp += 14
			max_mana += 20
			intelligence += 3
			spirit += 3
		UnitClass.RIOT:
			max_hp += 30
			strength += 2
			resistance += 3
		UnitClass.PASTOR:
			max_hp += 14
			max_mana += 18
			intelligence += 3
			spirit += 2
		UnitClass.SABLE:
			max_hp += 11
			dexterity += 3
			strength += 2
		UnitClass.RUSH:
			max_hp += 14
			dexterity += 3
			strength += 2
		UnitClass.STITCH:
			max_hp += 13
			max_mana += 18
			intelligence += 3
			dexterity += 1
		UnitClass.COAL:
			max_hp += 22
			strength += 3
			resistance += 1
		UnitClass.JUNE:
			max_hp += 16
			max_mana += 18
			intelligence += 2
			spirit += 3
		UnitClass.CROSS:
			max_hp += 30
			strength += 2
			resistance += 3
			spirit += 1
		UnitClass.SEAR:
			max_hp += 16
			max_mana += 16
			intelligence += 3
			strength += 2
		UnitClass.EMBER:
			max_hp += 11
			dexterity += 3
			intelligence += 2
		UnitClass.RIFT:
			max_hp += 17
			max_mana += 16
			intelligence += 3
			resistance += 1
		UnitClass.ZOLT:
			max_hp += 10
			max_mana += 24
			intelligence += 4
			spirit += 2
		UnitClass.LUMEN:
			max_hp += 10
			max_mana += 22
			intelligence += 4
			dexterity += 1
		UnitClass.STATIC:
			max_hp += 13
			max_mana += 18
			intelligence += 3
			dexterity += 1
		UnitClass.REED:
			max_hp += 15
			max_mana += 20
			intelligence += 2
			spirit += 3
		UnitClass.VAIL:
			max_hp += 14
			max_mana += 20
			intelligence += 2
			spirit += 3
		UnitClass.SPORE:
			max_hp += 12
			max_mana += 22
			intelligence += 4
			spirit += 1
	# All classes gain a small spirit boost per level-up
	spirit += 1

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

	hit_counter += 1
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

	if attack_range > 1:
		spawn_projectile(target, damage)
		pending_attack_log_damage += damage   # intended damage (mitigated on hit)
	else:
		var pre_hp: int = target.current_hp
		target.take_damage(damage, current_element, self, is_true_dmg)
		var actual: int = max(0, pre_hp - target.current_hp)
		damage_dealt += actual
		pending_attack_log_damage += actual
		_charge_ultimate(actual / 2)

	attacked.emit(target)

func _charge_ultimate(amount: int) -> void:
	if ultimate_charge_max <= 0 or ultimate_ready:
		return
	ultimate_charge = min(ultimate_charge + amount, ultimate_charge_max)
	if ultimate_charge >= ultimate_charge_max:
		ultimate_ready = true

func grant_xp(amount: int) -> void:
	current_xp += amount
	while current_xp >= xp_to_level:
		current_xp -= xp_to_level
		xp_to_level = int(xp_to_level * 1.5)
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
