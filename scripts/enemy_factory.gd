extends Node
class_name EnemyFactory

# ── Code → factory dispatch (single source of truth) ─────────────────────────
# Wave codes (WaveScaler formations) and type strings (wave specs) both resolve
# here. main_game.gd and the arena harness (scripts/arena/) share this — when
# adding a new enemy: add its factory below, then register it in BOTH dicts
# here, plus WaveScaler's CODE_ROLE/CODE_IS_LARGE/UNIT_POWER.
const CODE_TO_TYPE := {
	"M": "goblin", "A": "goblin_archer", "S": "goblin_shaman", "B": "orc_brute",
	"G": "hill_giant", "SL": "slime", "SK": "skeleton", "R": "rat",
	"TRI": "triarch", "SS": "stat_stealer", "AH": "ant_hill", "KHA": "khagan",
}

# Returns a NEW level-1 unit for a wave-code or type string; caller applies
# set_level() afterwards (matches main_game's flow — never level inside the
# factory, phase-boss snapshots depend on external leveling; see Triarch notes).
static func create_by_type(type: String) -> VisualUnit:
	match type:
		"goblin":        return create_goblin()
		"goblin_archer": return create_goblin_archer()
		"goblin_shaman": return create_goblin_shaman()
		"orc_brute":     return create_orc_brute()
		"hill_giant":    return create_hill_giant()
		"slime":         return create_slime()
		"skeleton":      return create_skeleton()
		"rat":           return create_rat()
		"triarch":       return create_triarch()
		"stat_stealer":  return create_stat_stealer()
		"ant_hill":      return create_ant_hill()
		"khagan":        return create_khagan()
	return null

static func create_by_code(code: String) -> VisualUnit:
	return create_by_type(CODE_TO_TYPE.get(code, ""))

# ── Goblin (weak melee) ───────────────────────────────────────────────────────
static func create_goblin(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Goblin"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 150
	u.current_hp      = 150
	u.max_mana        = 20
	u.current_mana    = 20
	u.attack_damage   = 21
	u.magic_power     = 8
	u.resistance      = 1
	u.attack_speed    = 0.68
	u.hp_regen        = 0.42
	u.mana_regen      = 0.5
	u.movement_speed  = 4
	u.attack_range    = 1
	u.gold_reward     = 15
	u.crystal_reward  = 1
	u.xp_reward       = 50
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "goblin")
	u.skill_name = "Shank"
	u.skill_damage_multiplier = 1.4
	u.skill_range = 1
	u.skill_cooldown_max = 5
	u.skill_mana_cost = 0
	u.skill_description = "Quick lunge dealing 140% ATK. · 5s CD"
	u.set_meta("mob_skill", "goblin_shank")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Goblin Archer (weak ranged) ───────────────────────────────────────────────
static func create_goblin_archer(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Goblin Archer"
	u.unit_class      = UnitBase.UnitClass.RANGER
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 120
	u.current_hp      = 120
	u.max_mana        = 30
	u.current_mana    = 30
	u.attack_damage   = 37
	u.magic_power     = 9
	u.resistance      = 3
	u.attack_speed    = 1.2
	u.hp_regen        = 0.5
	u.mana_regen      = 0.5
	u.movement_speed  = 2
	u.attack_range    = 4
	u.gold_reward     = 15
	u.crystal_reward  = 0
	u.xp_reward       = 60
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "goblin_archer")
	u.skill_name = "Crippling Arrow"
	u.skill_damage_multiplier = 1.2
	u.skill_range = 4
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 0
	u.skill_description = "Deal 120% ATK and slow the target 30% for 2s. · 6s CD"
	u.set_meta("mob_skill", "archer_cripple")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Goblin Shaman (ranged magic support) ─────────────────────────────────────
static func create_goblin_shaman(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Goblin Shaman"
	u.unit_class      = UnitBase.UnitClass.BLACK_MAGE
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.FIRE
	u.is_player_unit  = false
	u.max_hp          = 300
	u.current_hp      = 240
	u.max_mana        = 60
	u.current_mana    = 30
	u.attack_damage   = 9
	u.magic_power     = 19
	u.resistance      = 8
	u.attack_speed    = 0.66
	u.hp_regen        = 0.12
	u.mana_regen      = 3.0
	u.movement_speed  = 2
	u.attack_range    = 4
	u.gold_reward     = 18
	u.crystal_reward  = 1
	u.xp_reward       = 70
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "goblin_shaman")
	u.skill_name = "Mend"
	u.skill_damage_multiplier = 0.0
	u.skill_range = 6
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 0
	u.skill_description = "Heal the most-wounded ally for 150% MAG. · 6s CD"
	u.set_meta("mob_skill", "shaman_mend")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Orc Brute (heavy melee bruiser) ──────────────────────────────────────────
static func create_orc_brute(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Orc Brute"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.max_hp          = 750
	u.current_hp      = 750
	u.max_mana        = 20
	u.current_mana    = 20
	u.attack_damage   = 31
	u.magic_power     = 11
	u.resistance      = 14
	u.attack_speed    = 0.64
	u.hp_regen        = 0.7
	u.mana_regen      = 0.5
	u.movement_speed  = 3
	u.attack_range    = 1
	u.gold_reward     = 25
	u.crystal_reward  = 1
	u.xp_reward       = 100
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "orc_brute")
	# is_boss removed 2026-07-03: leftover from when the orc WAS a wave boss.
	# It made "vs boss" relic damage apply to every orc, and would have given
	# each fodder orc a boss-tier coin drop in the new gold economy.
	u.skill_name = "Crushing Blow"
	u.skill_damage_multiplier = 1.6
	u.skill_range = 1
	u.skill_cooldown_max = 7
	u.skill_mana_cost = 0
	u.skill_description = "Deal 160% ATK and stun for 1s. · 7s CD"
	u.set_meta("mob_skill", "brute_crush")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Slime (slow, tanky, low damage) ──────────────────────────────────────────
static func create_slime(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Slime"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.WATER
	u.is_player_unit  = false
	u.max_hp          = 220
	u.current_hp      = 220
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 14
	u.magic_power     = 4
	u.resistance      = 14          # naturally tough, hits weak
	u.attack_speed    = 0.58
	u.hp_regen        = 0.3
	u.mana_regen      = 0.17
	u.movement_speed  = 2           # sluggish
	u.attack_range    = 1
	u.gold_reward     = 12
	u.crystal_reward  = 0
	u.xp_reward       = 50
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "slime")
	u.skill_name = "Corrosive Goo"
	u.skill_damage_multiplier = 0.0
	u.skill_range = 1
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 0
	u.skill_description = "Weaken the target: -25% outgoing damage for 3s. · 6s CD"
	u.set_meta("mob_skill", "slime_goo")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Skeleton (fragile but hits hard, medium range) ────────────────────────────
static func create_skeleton(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Skeleton"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 110
	u.current_hp      = 110
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 28
	u.magic_power     = 8
	u.resistance      = 4           # brittle bones — low res
	u.attack_speed    = 0.74
	u.hp_regen        = 0.55
	u.mana_regen      = 0.33
	u.movement_speed  = 3
	u.attack_range    = 1
	u.gold_reward     = 13
	u.crystal_reward  = 0
	u.xp_reward       = 32
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "skeleton")
	u.skill_name = "Bone Shield"
	u.skill_damage_multiplier = 0.0
	u.skill_range = 1
	u.skill_cooldown_max = 8
	u.skill_mana_cost = 0
	u.skill_description = "Shield self for 25% max HP. · 8s CD"
	u.set_meta("mob_skill", "skeleton_boneshield")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Rat (fast, very low HP, weak hit — swarms in numbers) ────────────────────
static func create_rat(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Rat"
	u.unit_class      = UnitBase.UnitClass.RANGER
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 75
	u.current_hp      = 75
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 24
	u.magic_power     = 4
	u.resistance      = 3
	u.attack_speed    = 1.06        # fast attacker
	u.hp_regen        = 0.25
	u.mana_regen      = 0.17
	u.movement_speed  = 5           # fastest basic enemy
	u.attack_range    = 1
	u.gold_reward     = 10
	u.crystal_reward  = 0
	u.xp_reward       = 22
	u.sprite_variant  = randi() % 3
	u.set_meta("sprite_folder", "rat")
	u.skill_name = "Infected Bite"
	u.skill_damage_multiplier = 1.1
	u.skill_range = 1
	u.skill_cooldown_max = 5
	u.skill_mana_cost = 0
	u.skill_description = "Deal 110% ATK and infect: 35% ATK/s disease for 3s. · 5s CD"
	u.set_meta("mob_skill", "rat_bite")
	if lvl > 1: u.set_level(lvl)
	return u

# ── Hill Giant (2×2 elite — spawns in rounds 5/15/25, see WaveScaler) ────────
static func create_hill_giant(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Hill Giant"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.cell_size       = 2          # occupies a 2×2 area
	u.max_hp          = 2800
	u.current_hp      = 2800
	u.max_mana        = 100
	u.current_mana    = 100
	u.attack_damage   = 24
	u.magic_power     = 9
	u.resistance      = 18
	u.attack_speed    = 0.58
	u.hp_regen        = 0.55
	u.mana_regen      = 0.5
	u.movement_speed  = 2          # slow but mobile — lumbers toward the team
	u.attack_range    = 2
	u.gold_reward     = 60
	u.crystal_reward  = 2
	u.xp_reward       = 200
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "hill_giant")
	u.skill_name      = "Boulder Smash"
	u.skill_damage_multiplier = 2.0
	u.skill_range     = 2
	u.skill_cooldown_max = 4
	u.ultimate_charge_max = 0     # no ult
	u.is_elite        = true
	if lvl > 1: u.set_level(lvl)
	return u

# ── The Triarch (round 30 final boss — cycles through every attack type) ─────
# Phase 1 (Melee) is this unit's baseline form, built directly in create_triarch.
# Phases 2/3 are reached by "dying" at 0 HP while a phase remains — see
# advance_triarch_phase(), hooked into VisualUnit.die(). Each transform:
#   - re-derives stats as a multiplier on the PHASE-1 (already level-scaled)
#     baseline snapshotted in the "triarch_base_stats" meta, so boss_level
#     scaling (see WaveScaler.boss_level) carries through every phase
#   - swaps unit_class, which changes which skill effect _use_skill() dispatches
#     to AND which LPC sprite folder the unit renders as (warrior/archer/
#     black_mage all have generated sheets) — one field drives combat behavior,
#     UI class label, and silhouette all at once
#   - fully heals the new phase (this IS the "fresh health bar" per phase)
#   - clears every status-effect/proc field so the transform is a clean slate
# Only entries [1] and [2] are read by advance_triarch_phase (index 0 documents
# the melee baseline for reference; its real values live in create_triarch).
const TRIARCH_PHASES: Array[Dictionary] = [
	{
		"name": "Melee Form", "unit_class": UnitBase.UnitClass.WARRIOR,
		"hp_mult": 1.0, "mana_mult": 1.0, "atk_mult": 1.0, "magic_mult": 1.0, "res_mult": 1.0,
		"aspd_mult": 1.0, "hpregen_mult": 1.0, "manaregen_mult": 1.0,
		"move": 3, "range": 1,
		"skill_name": "Cleaving Strike", "skill_dmg": 1.3, "skill_range": 1, "skill_cd": 3, "skill_mana": 0,
	},
	{
		"name": "Ranger Form", "unit_class": UnitBase.UnitClass.RANGER,
		"hp_mult": 1.0, "mana_mult": 1.2, "atk_mult": 0.85, "magic_mult": 1.0, "res_mult": 0.85,
		"aspd_mult": 1.15, "hpregen_mult": 1.0, "manaregen_mult": 1.3,
		"move": 4, "range": 5,
		"skill_name": "Piercing Volley", "skill_dmg": 1.0, "skill_range": 6, "skill_cd": 4, "skill_mana": 0,
	},
	{
		"name": "Arcane Form", "unit_class": UnitBase.UnitClass.BLACK_MAGE,
		"hp_mult": 0.85, "mana_mult": 2.0, "atk_mult": 0.4, "magic_mult": 2.4, "res_mult": 0.9,
		"aspd_mult": 0.85, "hpregen_mult": 1.0, "manaregen_mult": 1.8,
		"move": 2, "range": 5,
		"skill_name": "Meteor Storm", "skill_dmg": 2.2, "skill_range": 6, "skill_cd": 5, "skill_mana": 25,
	},
]

static func create_triarch(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "The Triarch — Melee Form"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 2200
	u.current_hp      = 2200
	u.max_mana        = 150
	u.current_mana    = 150
	u.attack_damage   = 40
	u.magic_power     = 16
	u.resistance      = 20
	u.attack_speed    = 0.62
	u.hp_regen        = 0.6
	u.mana_regen      = 1.0
	u.movement_speed  = 3
	u.attack_range    = 1
	u.gold_reward     = 100
	u.crystal_reward  = 3
	u.xp_reward       = 350
	u.sprite_variant  = 0
	u.is_boss         = true

	u.skill_name = "Cleaving Strike"
	u.skill_damage_multiplier = 1.3
	u.skill_range = 1
	u.skill_cooldown_max = 3
	u.skill_mana_cost = 0

	if lvl > 1: u.set_level(lvl)

	# NOTE: the phase-1 baseline snapshot (used to derive phases 2/3) is taken
	# LAZILY on the first phase transition, not here — main_game.gd's spawn path
	# applies boss-tier leveling via an EXTERNAL unit.set_level(lvl) call *after*
	# this factory function returns (matching the existing Hill Giant pattern),
	# so snapshotting here would capture pre-level stats. By the time the boss
	# ever reaches 0 HP the external leveling has long since happened, so the
	# lazy snapshot in advance_triarch_phase() always sees the real scaled stats.
	u.set_meta("triarch_phase", 1)
	return u

# Called from VisualUnit.die() when a Triarch's HP hits 0. Transforms it into
# the next phase in place (no death, no removal from the fight) and returns
# true, or returns false once the final phase has actually been defeated so
# the normal death flow proceeds.
static func advance_triarch_phase(unit: VisualUnit) -> bool:
	var phase: int = int(unit.get_meta("triarch_phase", 1))
	if phase >= TRIARCH_PHASES.size():
		return false
	var next_phase: int = phase + 1
	var cfg: Dictionary = TRIARCH_PHASES[next_phase - 1]

	# Lazily snapshot the phase-1 baseline the first time we transform — see the
	# note in create_triarch() for why this can't be captured at creation time.
	if not unit.has_meta("triarch_base_stats"):
		unit.set_meta("triarch_base_stats", {
			"hp": unit.max_hp, "mana": unit.max_mana, "atk": unit.attack_damage,
			"magic": unit.magic_power, "res": unit.resistance,
			"aspd": unit.attack_speed, "hpregen": unit.hp_regen, "manaregen": unit.mana_regen,
		})
	var base: Dictionary = unit.get_meta("triarch_base_stats", {})

	unit.unit_class = cfg["unit_class"]
	unit.max_hp        = maxi(1, int(round(float(base.get("hp", unit.max_hp)) * float(cfg["hp_mult"]))))
	unit.current_hp    = unit.max_hp
	unit.max_mana      = maxi(0, int(round(float(base.get("mana", unit.max_mana)) * float(cfg["mana_mult"]))))
	unit.current_mana  = unit.max_mana
	unit.attack_damage = maxi(1, int(round(float(base.get("atk", unit.attack_damage)) * float(cfg["atk_mult"]))))
	unit.magic_power   = maxi(0, int(round(float(base.get("magic", unit.magic_power)) * float(cfg["magic_mult"]))))
	unit.resistance    = maxi(0, int(round(float(base.get("res", unit.resistance)) * float(cfg["res_mult"]))))
	unit.attack_speed  = float(base.get("aspd", unit.attack_speed)) * float(cfg["aspd_mult"])
	unit.hp_regen      = float(base.get("hpregen", unit.hp_regen)) * float(cfg["hpregen_mult"])
	unit.mana_regen    = float(base.get("manaregen", unit.mana_regen)) * float(cfg["manaregen_mult"])
	unit.movement_speed = int(cfg["move"])
	unit.attack_range   = int(cfg["range"])

	unit.skill_name = cfg["skill_name"]
	unit.skill_damage_multiplier = float(cfg["skill_dmg"])
	unit.skill_range = int(cfg["skill_range"])
	unit.skill_cooldown_max = int(cfg["skill_cd"])
	unit.skill_mana_cost = int(cfg["skill_mana"])
	unit.skill_cd_time = 0.0   # the new form opens with an immediate cast

	# Clean slate: clear shields/cooldowns/status effects so nothing carries
	# across the transformation.
	unit.current_shield = 0
	unit.attack_cooldown = 0.0
	unit.stun_time = 0.0
	unit.burn_time = 0.0; unit.burn_dps = 0.0; unit.burn_accum = 0.0; unit.burn_source = null
	unit.slow_time = 0.0; unit.slow_pct = 0.0
	unit.root_time = 0.0
	unit.taunt_time = 0.0; unit.taunt_source = null
	unit.untargetable_time = 0.0
	unit.outgoing_dmg_mult = 1.0; unit.outgoing_dmg_time = 0.0
	unit.bonus_aspd_pct = 0.0; unit.bonus_aspd_time = 0.0
	unit.weakened_pct = 0.0; unit.weakened_time = 0.0
	unit.rapid_fire_time = 0.0
	unit.overdrive_time = 0.0
	unit.frenzy_active = false

	unit.unit_name = "The Triarch — %s" % cfg["name"]
	unit.set_meta("triarch_phase", next_phase)

	if unit.health_bar:
		unit.health_bar.update_hp(unit.current_hp, unit.max_hp)
		unit.health_bar.update_mp(unit.current_mana, unit.max_mana)
		unit.health_bar.update_ult(0, 1)
		unit.health_bar.update_shield(0, unit.max_hp)
	if unit.has_method("rebuild_sprite"):
		unit.rebuild_sprite()
	return true

# ── Stat Stealer (elite — spawns in rounds 5/15/25, see WaveScaler) ──────────
# Active: shields itself for 25% of its own max HP (spends mana — see
# AutoBattleManager._use_skill). Ultimate: drains a random stat off its target
# over 10 seconds (10%/sec — see AutoBattleManager._stat_steal_drain), holding
# the stolen amount on itself until it dies, at which point the theft reverts.
static func create_stat_stealer(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Stat Stealer"
	u.unit_class      = UnitBase.UnitClass.STAT_STEALER
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(UnitBase.UnitClass.BLACK_MAGE, {}).duplicate()
	u.current_element = UnitBase.Element.NORMAL
	u.is_player_unit  = false
	u.max_hp          = 900
	u.current_hp      = 900
	u.max_mana        = 250
	u.current_mana    = 250
	u.attack_damage   = 22
	u.magic_power     = 20
	u.resistance      = 14
	u.attack_speed    = 0.65
	u.hp_regen        = 0.6
	u.mana_regen      = 1.5
	u.movement_speed  = 3
	u.attack_range    = 2
	u.gold_reward     = 50
	u.crystal_reward  = 2
	u.xp_reward       = 150
	u.sprite_variant  = randi() % 3
	u.is_elite        = true

	u.skill_name = "Siphon Ward"
	u.skill_damage_multiplier = 0.0   # utility skill, no direct damage
	u.skill_range = 0
	u.skill_cooldown_max = 6
	u.skill_mana_cost = 40

	u.ultimate_name = "Essence Drain"
	u.ultimate_damage_mult = 0.0      # utility ultimate, no direct damage
	u.ultimate_range = 6
	u.ultimate_charge_max = 350

	if lvl > 1: u.set_level(lvl)
	return u

# ── Ant Hill (elite — spawns in rounds 5/15/25, see WaveScaler) ──────────────
# A stationary 2×2 spawner: weak on its own, but periodically spawns Ants (see
# AutoBattleManager._tick_passive's ANT_HILL case + _spawn_ant) that stack a
# permanent +1-per-bite vulnerability on whoever they hit — a DPS check. Kill
# the hill fast to shut off the swarm before the stacks get out of hand.
static func create_ant_hill(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Ant Hill"
	u.unit_class      = UnitBase.UnitClass.ANT_HILL
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(UnitBase.UnitClass.WARRIOR, {}).duplicate()
	u.current_element = UnitBase.Element.EARTH
	u.is_player_unit  = false
	u.cell_size       = 2          # a wide mound, not a single-tile creature
	u.max_hp          = 1400
	u.current_hp      = 1400
	u.max_mana        = 0
	u.current_mana    = 0
	u.attack_damage   = 8          # minor — the ants are the real threat
	u.magic_power     = 0
	u.resistance      = 25         # tanky: rewards focusing it down, punishes ignoring it
	u.attack_speed    = 0.3
	u.hp_regen        = 0.4
	u.mana_regen      = 0.0
	u.movement_speed  = 0          # stationary — it's a hill, not a creature
	u.attack_range    = 1
	u.gold_reward     = 45
	u.crystal_reward  = 2
	u.xp_reward       = 130
	u.sprite_variant  = 0
	u.set_meta("sprite_folder", "ant_hill")
	u.is_elite        = true
	u.ultimate_charge_max = 0     # no skill/ultimate — purely the passive spawn behavior

	if lvl > 1: u.set_level(lvl)
	return u

# ── Khagan (wave-10 boss — mount-swap fight) ─────────────────────────────────
# Phase 1: mounted on a turtle (tanky, 2×2). Phase 2: dismounted and fighting
# alone (faster, squishier, 1×1) — reached the same way Triarch reaches its
# phases, by transforming in place instead of really dying. Phase 3 is
# different in kind: instead of a third self-transform, Khagan's "death" at the
# end of phase 2 channels his essence into one of the PLAYER's own heroes
# (highest attack_damage — turns your best carry against you), via
# AutoBattleManager.start_khagan_possession(), and Khagan's own body then dies
# for real. The player must fight that possessed hero down to 1 HP to break
# the control and end the fight (see the "khagan_puppet" check in
# UnitBase/VisualUnit.die()). No dedicated art yet — reuses the
# warrior/monk LPC sprite sheets already in the project, same approach as
# The Triarch.
const KHAGAN_PHASE_2 := {
	"name": "Dismounted", "unit_class": UnitBase.UnitClass.MONK, "element": UnitBase.Element.AIR,
	"hp_mult": 0.70, "mana_mult": 1.0, "atk_mult": 1.25, "magic_mult": 1.0, "res_mult": 0.55,
	"aspd_mult": 1.4, "hpregen_mult": 1.0, "manaregen_mult": 1.0,
	"move": 4, "range": 1,
	"skill_name": "Flowing Strikes", "skill_dmg": 1.4, "skill_range": 1, "skill_cd": 3, "skill_mana": 0,
}

static func create_khagan(lvl: int = 1) -> VisualUnit:
	var u := VisualUnit.new()
	u.unit_name       = "Khagan — Mounted"
	u.unit_class      = UnitBase.UnitClass.WARRIOR
	u.growth_base     = UnitFactory.CLASS_GROWTH_PER_LEVEL.get(u.unit_class, {}).duplicate()
	u.current_element = UnitBase.Element.WATER
	u.is_player_unit  = false
	u.cell_size       = 2          # riding a turtle mount
	u.max_hp          = 2000
	u.current_hp      = 2000
	u.max_mana        = 100
	u.current_mana    = 100
	u.attack_damage   = 26
	u.magic_power     = 10
	u.resistance      = 22
	u.attack_speed    = 0.55
	u.hp_regen        = 0.5
	u.mana_regen      = 0.5
	u.movement_speed  = 2
	u.attack_range    = 1
	u.gold_reward     = 90
	u.crystal_reward  = 3
	u.xp_reward       = 320
	u.sprite_variant  = 0
	u.is_boss         = true

	u.skill_name = "Shell Slam"
	u.skill_damage_multiplier = 1.3
	u.skill_range = 1
	u.skill_cooldown_max = 3
	u.skill_mana_cost = 0

	if lvl > 1: u.set_level(lvl)
	u.set_meta("khagan_phase", 1)
	return u

# Called from VisualUnit.die() when Khagan's HP hits 0. Phase 1→2: transforms
# in place (dismount) and returns true. Phase 2: triggers the possession
# side-effect then returns false so Khagan's body really dies.
static func advance_khagan_phase(unit: VisualUnit) -> bool:
	var phase: int = int(unit.get_meta("khagan_phase", 1))
	if phase == 1:
		# Lazily snapshot the phase-1 baseline (same reasoning as the Triarch:
		# main_game.gd applies boss-tier leveling via an EXTERNAL set_level()
		# call AFTER this factory function returns, so snapshotting eagerly at
		# creation time would miss that scaling).
		if not unit.has_meta("khagan_base_stats"):
			unit.set_meta("khagan_base_stats", {
				"hp": unit.max_hp, "mana": unit.max_mana, "atk": unit.attack_damage,
				"magic": unit.magic_power, "res": unit.resistance,
				"aspd": unit.attack_speed, "hpregen": unit.hp_regen, "manaregen": unit.mana_regen,
			})
		var base: Dictionary = unit.get_meta("khagan_base_stats")
		var cfg: Dictionary = KHAGAN_PHASE_2

		unit.unit_class      = cfg["unit_class"]
		unit.current_element = cfg["element"]
		unit.cell_size        = 1   # dismounted — no longer a 2×2 mount
		unit.max_hp        = maxi(1, int(round(float(base["hp"]) * float(cfg["hp_mult"]))))
		unit.current_hp    = unit.max_hp
		unit.max_mana      = maxi(0, int(round(float(base["mana"]) * float(cfg["mana_mult"]))))
		unit.current_mana  = unit.max_mana
		unit.attack_damage = maxi(1, int(round(float(base["atk"]) * float(cfg["atk_mult"]))))
		unit.magic_power   = maxi(0, int(round(float(base["magic"]) * float(cfg["magic_mult"]))))
		unit.resistance    = maxi(0, int(round(float(base["res"]) * float(cfg["res_mult"]))))
		unit.attack_speed  = float(base["aspd"]) * float(cfg["aspd_mult"])
		unit.hp_regen      = float(base["hpregen"]) * float(cfg["hpregen_mult"])
		unit.mana_regen    = float(base["manaregen"]) * float(cfg["manaregen_mult"])
		unit.movement_speed = int(cfg["move"])
		unit.attack_range   = int(cfg["range"])

		unit.skill_name = cfg["skill_name"]
		unit.skill_damage_multiplier = float(cfg["skill_dmg"])
		unit.skill_range = int(cfg["skill_range"])
		unit.skill_cooldown_max = int(cfg["skill_cd"])
		unit.skill_mana_cost = int(cfg["skill_mana"])
		unit.skill_cd_time = 0.0   # opens with an immediate strike, like the Triarch

		unit.current_shield = 0
		unit.attack_cooldown = 0.0
		unit.unit_name = "Khagan — %s" % cfg["name"]
		unit.set_meta("khagan_phase", 2)

		if unit.health_bar:
			# Re-derive the bar size for the new (smaller) footprint — it was
			# sized for cell_size=2 at spawn and won't auto-update otherwise.
			unit.health_bar.bar_width = 70.0 + (unit.cell_size - 1) * 120.0
			unit.health_bar.offset_y  = 60.0 + (unit.cell_size - 1) * 35.0
			unit.health_bar.update_hp(unit.current_hp, unit.max_hp)
			unit.health_bar.update_mp(unit.current_mana, unit.max_mana)
			unit.health_bar.update_ult(0, 1)
			unit.health_bar.update_shield(0, unit.max_hp)
		if unit.has_method("rebuild_sprite"):
			unit.rebuild_sprite()
		return true

	elif phase == 2:
		if unit.battle_manager and unit.battle_manager.has_method("start_khagan_possession"):
			unit.battle_manager.start_khagan_possession(unit)
		return false   # Khagan's own body really dies now — the puppet carries the fight

	return false
